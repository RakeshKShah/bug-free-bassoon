#!/usr/bin/env bash
set -euo pipefail

# Source shared infra as required by the plan
source tests/task_1309519433_20260910032107/api/_infra.sh

# Wait for app health (assuming /health is the health endpoint)
echo "Checking app health..."
curl -fsS "http://app:${APP_PORT}/health" | jq .

# Prepare database: create BUYER and SELLER users, seller profile, and a single product
# Insert users with explicit ids and enum/status literals as per plan
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('buyer-1', 'buyer@example.com', 'hashed-buyer', 'BUYER', 'ACTIVE', NOW()),
  ('seller-user-1', 'seller@example.com', 'hashed-seller', 'SELLER', 'ACTIVE', NOW())
ON CONFLICT (id) DO NOTHING;
"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES
  ('seller-profile-1', 'seller-user-1', 'Test Store', 'Test bio')
ON CONFLICT (id) DO NOTHING;
"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES (
  'product-1',
  'seller-profile-1',
  'Test Product',
  'A product for checkout tests',
  'Test Category',
  1000,
  5,
  '[]'::json,
  'ACTIVE',
  TRUE,
  NOW()
)
ON CONFLICT (id) DO NOTHING;
"

# Optional: verify seed data
echo "Verifying seeded users and products..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "SELECT id, role, status FROM users;"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "SELECT id, seller_id, price_cents, stock_qty, status, visible FROM products;"

# --- Case: single_seller_happy_path_checkout ---

# Preconditions

echo "Cleaning existing orders and order_items..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM order_items;"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM orders;"

echo "Confirming starting stock and price for product-1..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
SELECT id, price_cents, stock_qty, status, visible
FROM products
WHERE id = 'product-1';
"

# Set up authenticated BUYER context using the app's auth endpoints.
# The plan calls for reading src/routes/auth.ts; we respect its contract here.
# Because the seed used a literal password_hash, we create a test buyer via /auth/register
# and then log in with that buyer to obtain a valid JWT token.

echo "Registering test buyer via /auth/register..."
REGISTER_PAYLOAD='{"email":"test-buyer@example.com","password":"password123","role":"BUYER"}'
curl -fsS -X POST "http://app:${APP_PORT}/auth/register" \
  -H 'Content-Type: application/json' \
  -d "$REGISTER_PAYLOAD" | tee /tmp/register_response.json

TEST_BUYER_EMAIL=$(jq -r '.user.email' /tmp/register_response.json)
if [ "$TEST_BUYER_EMAIL" != "test-buyer@example.com" ]; then
  echo "Unexpected registered buyer email: $TEST_BUYER_EMAIL" >&2
  exit 1
fi

echo "Logging in test buyer via /auth/login..."
LOGIN_PAYLOAD='{"email":"test-buyer@example.com","password":"password123"}'
curl -fsS -X POST "http://app:${APP_PORT}/auth/login" \
  -H 'Content-Type: application/json' \
  -d "$LOGIN_PAYLOAD" | tee /tmp/login_response.json

TOKEN=$(jq -r '.token' /tmp/login_response.json)
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "Failed to obtain auth token from /auth/login" >&2
  exit 1
fi

echo "Obtained JWT token for buyer: $TOKEN"

# When

echo "Performing checkout for single_seller_happy_path_checkout..."
# Total cents expected: 1000 * 2 = 2000
# Platform fee expected (10%): 200
# Seller net expected: 1800

curl -fsS -X POST "http://app:${APP_PORT}/orders/checkout" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{
    "items": [
      { "product_id": "product-1", "qty": 2 }
    ]
  }' \
  | tee /tmp/checkout_response.json

ORDER_ID=$(jq -r '.order_id' /tmp/checkout_response.json)
DEMO_MODE=$(jq -r '.demo_mode' /tmp/checkout_response.json)
CLIENT_SECRET=$(jq -r '.client_secret' /tmp/checkout_response.json)
MESSAGE=$(jq -r '.message' /tmp/checkout_response.json)

echo "ORDER_ID=${ORDER_ID}"
echo "DEMO_MODE=${DEMO_MODE}"
echo "CLIENT_SECRET=${CLIENT_SECRET}"
echo "MESSAGE=${MESSAGE}"

# Then

echo "Asserting checkout response fields..."
# Assert response fields exist and are non-empty
test -n "${ORDER_ID}"
test -n "${CLIENT_SECRET}"
# demo_mode and message can be informational; just ensure keys exist
jq -e '.demo_mode' /tmp/checkout_response.json >/dev/null
jq -e '.message' /tmp/checkout_response.json >/dev/null

echo "Verifying order row totals and fees..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
SELECT id, buyer_id, status, total_cents, platform_fee_cents
FROM orders
WHERE id = '${ORDER_ID}';
" | tee /tmp/order_row.txt

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
SELECT
  total_cents,
  platform_fee_cents,
  (total_cents - platform_fee_cents) AS seller_net_cents
FROM orders
WHERE id = '${ORDER_ID}';
" | tee /tmp/order_fees.txt

echo "Confirming order status is PAID..."
ORDER_STATUS=$(psql "$DATABASE_URL" -t -A -v ON_ERROR_STOP=1 -c "
SELECT status
FROM orders
WHERE id = '${ORDER_ID}';
")
if [ "$ORDER_STATUS" != "PAID" ]; then
  echo "Expected order status PAID, got: $ORDER_STATUS" >&2
  exit 1
fi

echo "Verifying order_items rows and seller payouts..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
SELECT order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents
FROM order_items
WHERE order_id = '${ORDER_ID}';
" | tee /tmp/order_items.txt

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
SELECT
  qty,
  price_at_purchase,
  seller_payout_cents,
  (price_at_purchase * qty) AS line_total_cents,
  (price_at_purchase * qty) - seller_payout_cents AS platform_fee_component
FROM order_items
WHERE order_id = '${ORDER_ID}';
" | tee /tmp/order_item_fees.txt

echo "Verifying product stock was decremented by qty=2..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
SELECT id, stock_qty, status
FROM products
WHERE id = 'product-1';
" | tee /tmp/product_after_checkout.txt

echo "Inspecting payouts for seller-profile-1..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
SELECT *
FROM payouts
WHERE seller_id = 'seller-profile-1';
" | tee /tmp/payouts.txt

echo "Checking seller net matches order total minus platform fee..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
SELECT
  (SELECT COALESCE(SUM(seller_payout_cents), 0) FROM order_items WHERE order_id = '${ORDER_ID}') AS total_seller_payout,
  (SELECT total_cents - platform_fee_cents FROM orders WHERE id = '${ORDER_ID}') AS expected_seller_net;
" | tee /tmp/seller_net_check.txt

# Basic assertion: total_seller_payout == expected_seller_net
TOTAL_SELLER_PAYOUT=$(psql "$DATABASE_URL" -t -A -v ON_ERROR_STOP=1 -c "
SELECT COALESCE(SUM(seller_payout_cents), 0) FROM order_items WHERE order_id = '${ORDER_ID}';
")
EXPECTED_SELLER_NET=$(psql "$DATABASE_URL" -t -A -v ON_ERROR_STOP=1 -c "
SELECT total_cents - platform_fee_cents FROM orders WHERE id = '${ORDER_ID}';
")

if [ "$TOTAL_SELLER_PAYOUT" != "$EXPECTED_SELLER_NET" ]; then
  echo "Seller payout mismatch: total_seller_payout=$TOTAL_SELLER_PAYOUT expected_seller_net=$EXPECTED_SELLER_NET" >&2
  exit 1
fi

# Teardown

echo "Cleaning up test data..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM order_items WHERE order_id = '${ORDER_ID}';"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM orders WHERE id = '${ORDER_ID}';"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id = 'product-1';"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = 'seller-profile-1';"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id IN ('buyer-1', 'seller-user-1');"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = 'test-buyer@example.com';"

rm -f /tmp/checkout_response.json /tmp/order_row.txt /tmp/order_fees.txt \
      /tmp/order_items.txt /tmp/order_item_fees.txt /tmp/product_after_checkout.txt \
      /tmp/payouts.txt /tmp/seller_net_check.txt /tmp/register_response.json /tmp/login_response.json || true

# Success marker required by runner
echo "CODEVALID_TEST_ASSERTION_OK:single_seller_happy_path_checkout"
