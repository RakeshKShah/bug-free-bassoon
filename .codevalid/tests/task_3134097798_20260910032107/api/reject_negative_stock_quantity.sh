#!/usr/bin/env bash
set -euo pipefail

# Case: reject_negative_stock_quantity
# Test that negative stock quantity updates are rejected and do not alter stored inventory.

source tests/task_3134097798_20260910032107/api/_infra.sh

# --- Preconditions (seed) ---
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
-- Seed a user compatible with seller_profiles.user_id FK
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('user-neg-stock-1', 'negstock@example.com', '$2b$10$testhashfornegativestock', 'SELLER', 'ACTIVE')
ON CONFLICT (id) DO NOTHING;

-- Seed a seller profile for this user
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('seller-neg-stock-1', 'user-neg-stock-1', 'Neg Stock Store', 'Store for negative stock test')
ON CONFLICT (id) DO NOTHING;

-- Seed a product owned by this seller with positive stock_qty and ACTIVE status
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES (
  'product-neg-stock-1',
  'seller-neg-stock-1',
  'Test Product Negative Stock',
  'Product used to verify negative stock updates are rejected',
  'TEST_CATEGORY',
  1000,
  5,
  '[]'::json,
  'ACTIVE',
  true,
  NOW()
)
ON CONFLICT (id) DO NOTHING;
SQL

# --- Obtain JWT for the seeded user (password-based auth) ---
# If a dedicated seed-test helper exists for login, use it; otherwise inspect auth routes.
# Here we directly call the auth login endpoint.

JWT_TOKEN="$(curl -sS -X POST "http://app:6713/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"email":"negstock@example.com","password":"password-for-negstock"}' | jq -r '.token')"

if [ -z "$JWT_TOKEN" ] || [ "$JWT_TOKEN" = "null" ]; then
  echo "Failed to obtain JWT_TOKEN for negstock@example.com" >&2
  # Teardown before exit
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
DELETE FROM products WHERE id = 'product-neg-stock-1';
DELETE FROM seller_profiles WHERE id = 'seller-neg-stock-1';
DELETE FROM users WHERE id = 'user-neg-stock-1';
SQL
  exit 1
fi

# --- When: attempt to update stock_qty to a negative value via PUT /products/{id} ---
HTTP_STATUS="$(curl -sS -o /tmp/neg_stock_resp.json -w '%{http_code}' \
  -X PUT "http://app:6713/products/product-neg-stock-1" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"stock_qty": -1}')"

echo "PUT /products/{id} HTTP status: $HTTP_STATUS"
cat /tmp/neg_stock_resp.json || true

# --- Then: assertions ---
# Assert that the request was rejected with a 4xx validation error (expected 400)
if [ "$HTTP_STATUS" -ne 400 ]; then
  echo "Expected HTTP 400 for negative stock_qty, got $HTTP_STATUS" >&2
  # Teardown before exit
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
DELETE FROM products WHERE id = 'product-neg-stock-1';
DELETE FROM seller_profiles WHERE id = 'seller-neg-stock-1';
DELETE FROM users WHERE id = 'user-neg-stock-1';
SQL
  exit 1
fi

ERROR_MSG="$(jq -r '.error // empty' < /tmp/neg_stock_resp.json)"
if [ -z "$ERROR_MSG" ]; then
  echo "Expected an error message in response for negative stock_qty" >&2
  # Teardown before exit
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
DELETE FROM products WHERE id = 'product-neg-stock-1';
DELETE FROM seller_profiles WHERE id = 'seller-neg-stock-1';
DELETE FROM users WHERE id = 'user-neg-stock-1';
SQL
  exit 1
fi

echo "Received validation error: $ERROR_MSG"

# Verify the product's stock_qty in the database remains unchanged (still 5)
CURRENT_STOCK_QTY="$(psql "$DATABASE_URL" -t -A -c "SELECT stock_qty FROM products WHERE id = 'product-neg-stock-1';")"

echo "Current stock_qty in DB: $CURRENT_STOCK_QTY"

if [ "$CURRENT_STOCK_QTY" != "5" ]; then
  echo "Expected stock_qty to remain 5 after rejected update, got $CURRENT_STOCK_QTY" >&2
  # Teardown before exit
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
DELETE FROM products WHERE id = 'product-neg-stock-1';
DELETE FROM seller_profiles WHERE id = 'seller-neg-stock-1';
DELETE FROM users WHERE id = 'user-neg-stock-1';
SQL
  exit 1
fi

# --- Teardown ---
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
DELETE FROM products WHERE id = 'product-neg-stock-1';
DELETE FROM seller_profiles WHERE id = 'seller-neg-stock-1';
DELETE FROM users WHERE id = 'user-neg-stock-1';
SQL

# Success marker required by runner
echo "CODEVALID_TEST_ASSERTION_OK:reject_negative_stock_quantity"
