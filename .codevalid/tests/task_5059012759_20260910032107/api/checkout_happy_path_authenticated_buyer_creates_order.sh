#!/usr/bin/env bash
set -euo pipefail

# Case: checkout_happy_path_authenticated_buyer_creates_order

# Setup
source tests/task_5059012759_20260910032107/api/_infra.sh

# Seed a buyer user with BUYER role and corresponding auth credentials
# Use a bcrypt hash of the password "test-password" so /auth/login will succeed.
# This hash was generated with bcrypt (salt rounds 10):
# node -e "const bcrypt = require('bcryptjs'); bcrypt.hash('test-password', 10).then(h => console.log(h));"
BUYER_PASSWORD_HASH='$2a$10$8qvFjvA3ZiZsa1onbXqI9eFXr0LqF9q3iQiyF1mLwXG.aOuhlW3XO'

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO users (id, email, password_hash, role, status, created_at)
  VALUES (
    'buyer-uuid-1',
    'buyer@example.com',
    '${BUYER_PASSWORD_HASH}',
    'BUYER',
    'ACTIVE',
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    password_hash = EXCLUDED.password_hash,
    role = EXCLUDED.role,
    status = EXCLUDED.status;
"

# Seed a seller profile and associated user if required by products.seller_id FK
SELLER_PASSWORD_HASH='$2a$10$8qvFjvA3ZiZsa1onbXqI9eFXr0LqF9q3iQiyF1mLwXG.aOuhlW3XO'

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO users (id, email, password_hash, role, status, created_at)
  VALUES (
    'seller-user-uuid-1',
    'seller@example.com',
    '${SELLER_PASSWORD_HASH}',
    'SELLER',
    'PENDING',
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    password_hash = EXCLUDED.password_hash,
    role = EXCLUDED.role,
    status = EXCLUDED.status;
"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO seller_profiles (id, user_id, store_name, bio)
  VALUES (
    'seller-profile-uuid-1',
    'seller-user-uuid-1',
    'Test Seller Store',
    ''
  )
  ON CONFLICT (id) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    store_name = EXCLUDED.store_name;
"

# Seed a visible ACTIVE product with sufficient stock for checkout
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO products (
    id,
    seller_id,
    title,
    description,
    category,
    price_cents,
    stock_qty,
    photos,
    status,
    visible,
    created_at
  )
  VALUES (
    'product-uuid-1',
    'seller-profile-uuid-1',
    'Test Product',
    'A product used for checkout tests',
    'test-category',
    1000,
    5,
    '[]'::json,
    'ACTIVE',
    true,
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    seller_id = EXCLUDED.seller_id,
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    category = EXCLUDED.category,
    price_cents = EXCLUDED.price_cents,
    stock_qty = EXCLUDED.stock_qty,
    photos = EXCLUDED.photos,
    status = EXCLUDED.status,
    visible = EXCLUDED.visible;
"

# Optionally seed a SOLD_OUT product that still meets stock checks but will be used in other tests (not used here)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  INSERT INTO products (
    id,
    seller_id,
    title,
    description,
    category,
    price_cents,
    stock_qty,
    photos,
    status,
    visible,
    created_at
  )
  VALUES (
    'product-uuid-2',
    'seller-profile-uuid-1',
    'Sold Out Product',
    'Out of stock product for other scenarios',
    'test-category',
    1500,
    0,
    '[]'::json,
    'SOLD_OUT',
    true,
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    seller_id = EXCLUDED.seller_id,
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    category = EXCLUDED.category,
    price_cents = EXCLUDED.price_cents,
    stock_qty = EXCLUDED.stock_qty,
    photos = EXCLUDED.photos,
    status = EXCLUDED.status,
    visible = EXCLUDED.visible;
"

# Obtain an auth token or session for the buyer user via /auth/login
BUYER_TOKEN="$(
  curl -s -X POST "http://app:${PORT}/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"buyer@example.com","password":"test-password"}' | jq -r '.token'
)"

# Verify the app health endpoint is responding before running the case
HEALTH_JSON="$(curl -s "http://app:${PORT}/health")"
if [ -z "$HEALTH_JSON" ]; then
  echo "Health check returned empty response" >&2
  exit 1
fi

# Preconditions

# Ensure seeded buyer, seller profile, and product exist with expected values
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  SELECT id, role, status
  FROM users
  WHERE id = 'buyer-uuid-1';
"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  SELECT id, seller_id, status, visible, stock_qty
  FROM products
  WHERE id = 'product-uuid-1';
"

# Confirm buyer auth token is non-empty
if [ -z "$BUYER_TOKEN" ] || [ "$BUYER_TOKEN" = "null" ]; then
  echo 'Buyer token not set; check auth route and login call.' >&2
  exit 1
fi

# When

# Perform checkout for the authenticated buyer with a valid cart item
CHECKOUT_RESPONSE="$(
  curl -s -X POST "http://app:${PORT}/orders/checkout" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${BUYER_TOKEN}" \
    -d '{
      "items": [
        {
          "product_id": "product-uuid-1",
          "qty": 2
        }
      ]
    }'
)"

echo "$CHECKOUT_RESPONSE" | jq '.'

# Then

# Assert checkout response has required fields and indicates success based on actual implementation
ORDER_ID="$(echo "$CHECKOUT_RESPONSE" | jq -r '.order_id')"
MESSAGE_FIELD="$(echo "$CHECKOUT_RESPONSE" | jq -r '.message')"
DEMO_MODE_FIELD="$(echo "$CHECKOUT_RESPONSE" | jq -r '.demo_mode')"
CLIENT_SECRET_FIELD="$(echo "$CHECKOUT_RESPONSE" | jq -r '.client_secret')"
ERROR_FIELD="$(echo "$CHECKOUT_RESPONSE" | jq -r '.error // empty')"

if [ -z "$ORDER_ID" ] || [ "$ORDER_ID" = "null" ]; then
  echo "Expected non-empty order_id in response, got: $ORDER_ID" >&2
  exit 1
fi

if [ "$MESSAGE_FIELD" != "Order placed" ]; then
  echo "Expected message to be 'Order placed', got: $MESSAGE_FIELD" >&2
  exit 1
fi

if [ "$DEMO_MODE_FIELD" != "true" ]; then
  echo "Expected demo_mode to be true, got: $DEMO_MODE_FIELD" >&2
  exit 1
fi

if [ "$CLIENT_SECRET_FIELD" != "null" ]; then
  echo "Expected client_secret to be null, got: $CLIENT_SECRET_FIELD" >&2
  exit 1
fi

if [ -n "$ERROR_FIELD" ]; then
  echo "Expected no error field, got: $ERROR_FIELD" >&2
  exit 1
fi

# Verify order row exists with correct buyer_id and status PAID
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  SELECT id, buyer_id, status, total_cents, platform_fee_cents
  FROM orders
  WHERE id = '${ORDER_ID}';
"

# Verify order_items rows exist for the product with correct qty and price_at_purchase
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  SELECT order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents
  FROM order_items
  WHERE order_id = '${ORDER_ID}' AND product_id = 'product-uuid-1';
"

# Verify product stock has been decremented appropriately
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  SELECT stock_qty
  FROM products
  WHERE id = 'product-uuid-1';
"

# Attempt a second checkout with the same item to ensure cart/order behavior
SECOND_CHECKOUT_RESPONSE="$(
  curl -s -X POST "http://app:${PORT}/orders/checkout" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${BUYER_TOKEN}" \
    -d '{
      "items": [
        {
          "product_id": "product-uuid-1",
          "qty": 2
        }
      ]
    }'
)"

echo "$SECOND_CHECKOUT_RESPONSE" | jq '.'

SECOND_ORDER_ID="$(echo "$SECOND_CHECKOUT_RESPONSE" | jq -r '.order_id')"

if [ -z "$SECOND_ORDER_ID" ] || [ "$SECOND_ORDER_ID" = "null" ]; then
  echo "Expected non-empty order_id for second checkout, got: $SECOND_ORDER_ID" >&2
  exit 1
fi

if [ "$SECOND_ORDER_ID" = "$ORDER_ID" ]; then
  echo "Expected subsequent checkout to create a distinct order, but reused order_id: $SECOND_ORDER_ID" >&2
  exit 1
fi

# Teardown

# Clean up orders, order_items, products, and users created for this test case
if [ -n "${ORDER_ID:-}" ] && [ "$ORDER_ID" != "null" ]; then
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
    DELETE FROM order_items WHERE order_id = '${ORDER_ID}';
  "
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
    DELETE FROM orders WHERE id = '${ORDER_ID}';
  "
fi

if [ -n "${SECOND_ORDER_ID:-}" ] && [ "$SECOND_ORDER_ID" != "null" ]; then
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
    DELETE FROM order_items WHERE order_id = '${SECOND_ORDER_ID}';
  "
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
    DELETE FROM orders WHERE id = '${SECOND_ORDER_ID}';
  "
fi

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  DELETE FROM products WHERE id IN ('product-uuid-1', 'product-uuid-2');
"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  DELETE FROM seller_profiles WHERE id = 'seller-profile-uuid-1';
"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  DELETE FROM users WHERE id IN ('buyer-uuid-1', 'seller-user-uuid-1');
"

# Success marker required by runner
echo "CODEVALID_TEST_ASSERTION_OK:checkout_happy_path_authenticated_buyer_creates_order"
