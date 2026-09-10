#!/usr/bin/env bash
set -euo pipefail

# Case: update_stock_quantity_happy_path

# Setup
source tests/task_3134097798_20260910032107/api/_infra.sh

# Ensure migrations are applied and app is healthy
read_repo_file .codevalid/entrypoint.sh >/dev/null
read_repo_file prisma/schema.prisma >/dev/null

HTTP_STATUS=$(curl -sS -o /tmp/health_resp_update_stock.json -w "%{http_code}" "http://app:${PORT}/health")
if [ "${HTTP_STATUS}" -ne 200 ]; then
  echo "Healthcheck failed for update_stock_quantity_happy_path, status=${HTTP_STATUS}" >&2
  cat /tmp/health_resp_update_stock.json || true
  exit 1
fi

# Prepare psql connection string from DATABASE_URL
DB_URL="${DATABASE_URL}"

# Seed a user, seller profile, and an ACTIVE product owned by that seller
psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('seller-user-1', 'seller@example.com', 'test-hash', 'SELLER', 'ACTIVE')
ON CONFLICT (id) DO NOTHING;
" || {
  echo "Failed to insert seller user" >&2
  exit 1
}

psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('seller-profile-1', 'seller-user-1', 'Test Store', 'Test bio')
ON CONFLICT (id) DO NOTHING;
" || {
  echo "Failed to insert seller profile" >&2
  exit 1
}

psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES (
  'product-1',
  'seller-profile-1',
  'Test Product',
  'Initial description',
  'Category A',
  1000,
  5,
  '[]'::json,
  'ACTIVE',
  true,
  NOW()
)
ON CONFLICT (id) DO NOTHING;
" || {
  echo "Failed to insert product" >&2
  exit 1
}

# Obtain a JWT token for the seeded seller user (implementation depends on existing auth routes)
# If a login route exists, use it; otherwise use any existing test helper.
read_repo_file src/routes/auth.ts || true
: "${TOKEN:?TOKEN must be set to a valid seller JWT}"
SELLER_TOKEN="${TOKEN}"

# Preconditions
# Verify seeded product exists and is ACTIVE with initial stock_qty = 5
psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "
SELECT id, seller_id, status, stock_qty
FROM products
WHERE id = 'product-1';
" > /tmp/pre_update_product_row.txt

if ! grep -q "product-1" /tmp/pre_update_product_row.txt; then
  echo "Seeded product not found in database" >&2
  cat /tmp/pre_update_product_row.txt || true
  # Teardown before exiting
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id = 'product-1';" || true
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = 'seller-profile-1';" || true
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = 'seller-user-1';" || true
  exit 1
fi

# When
# Update stock quantity to a new positive integer via PUT /products/{id}
HTTP_STATUS=$(curl -sS -o /tmp/update_stock_quantity_response.json -w "%{http_code}" \
  -X PUT "http://app:${PORT}/products/product-1" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${SELLER_TOKEN}" \
  -d '{
    "stock_qty": 10
  }')

# Then
# Assert HTTP 200 from the last curl
if [ "${HTTP_STATUS}" -ne 200 ]; then
  echo "PUT /products/{id} expected HTTP 200, got ${HTTP_STATUS}" >&2
  cat /tmp/update_stock_quantity_response.json || true
  # Teardown before exiting
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id = 'product-1';" || true
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = 'seller-profile-1';" || true
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = 'seller-user-1';" || true
  exit 1
fi

# Validate response JSON has updated stockQty and unchanged core fields
jq '.id' /tmp/update_stock_quantity_response.json | grep -q '"product-1"' || {
  echo "Unexpected product id in response" >&2
  cat /tmp/update_stock_quantity_response.json || true
  # Teardown
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id = 'product-1';" || true
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = 'seller-profile-1';" || true
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = 'seller-user-1';" || true
  exit 1
}

jq '.stockQty' /tmp/update_stock_quantity_response.json | grep -q '10' || {
  echo "stockQty not updated to 10 in response" >&2
  cat /tmp/update_stock_quantity_response.json || true
  # Teardown
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id = 'product-1';" || true
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = 'seller-profile-1';" || true
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = 'seller-user-1';" || true
  exit 1
}

jq '.status' /tmp/update_stock_quantity_response.json | grep -q '"ACTIVE"' || {
  echo "Product status should remain ACTIVE for positive stock" >&2
  cat /tmp/update_stock_quantity_response.json || true
  # Teardown
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id = 'product-1';" || true
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = 'seller-profile-1';" || true
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = 'seller-user-1';" || true
  exit 1
}

jq '.visible' /tmp/update_stock_quantity_response.json | grep -q 'true' || {
  echo "Product should remain visible to buyers" >&2
  cat /tmp/update_stock_quantity_response.json || true
  # Teardown
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id = 'product-1';" || true
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = 'seller-profile-1';" || true
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = 'seller-user-1';" || true
  exit 1
}

# Confirm persisted DB state matches the updated stock quantity
psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "
SELECT stock_qty, status, visible
FROM products
WHERE id = 'product-1';
" > /tmp/post_update_product_row.txt

if ! grep -q "10" /tmp/post_update_product_row.txt; then
  echo "Database stock_qty not updated to 10" >&2
  cat /tmp/post_update_product_row.txt || true
  # Teardown
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id = 'product-1';" || true
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = 'seller-profile-1';" || true
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = 'seller-user-1';" || true
  exit 1
fi

# Buyer-facing behavior (if a listing endpoint exists): verify product is not marked sold out
read_repo_file src/routes/products.ts >/dev/null || true
curl -sS "http://app:${PORT}/products/product-1" \
  -o /tmp/buyer_product_view.json

jq '.status' /tmp/buyer_product_view.json | grep -q '"active"' || {
  echo "Buyer view incorrectly marks product as sold out when stockQty > 0" >&2
  cat /tmp/buyer_product_view.json || true
  # Teardown
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id = 'product-1';" || true
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = 'seller-profile-1';" || true
  psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = 'seller-user-1';" || true
  exit 1
}

# Teardown
psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "
DELETE FROM products WHERE id = 'product-1';
" || echo "Failed to delete product product-1" >&2

psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "
DELETE FROM seller_profiles WHERE id = 'seller-profile-1';
" || echo "Failed to delete seller profile seller-profile-1" >&2

psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "
DELETE FROM users WHERE id = 'seller-user-1';
" || echo "Failed to delete seller user seller-user-1" >&2

# Success marker for runner
echo "CODEVALID_TEST_ASSERTION_OK:update_stock_quantity_happy_path"
