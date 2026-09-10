#!/usr/bin/env bash
set -euo pipefail

# Case: unauthorized_user_cannot_modify_inventory

### Setup
source tests/task_3134097798_20260910032107/api/_infra.sh

# Seed users and seller_profiles and products for the authorization scenario
echo "Seeding users, seller profile, and product..."
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('user_auth', 'auth@example.com', 'hash_auth', 'BUYER', 'ACTIVE') ON CONFLICT (id) DO NOTHING;"
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('user_seller', 'seller@example.com', 'hash_seller', 'SELLER', 'ACTIVE') ON CONFLICT (id) DO NOTHING;"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('seller_1', 'user_seller', 'Test Store', 'Bio') ON CONFLICT (id) DO NOTHING;"
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at) VALUES ('prod_1', 'seller_1', 'Test Product', 'Desc', 'Category', 1000, 5, '[]'::json, 'ACTIVE', true, NOW()) ON CONFLICT (id) DO NOTHING;"

### Preconditions
echo "Verifying seeded product state..."
psql "$DATABASE_URL" -c "SELECT id, seller_id, stock_qty, status, visible FROM products WHERE id = 'prod_1';"

### When
# Obtain JWT for non-seller user_auth (password-based auth; use existing auth route)
NON_SELLER_JWT="$(curl -s -X POST http://app:6713/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"auth@example.com","password":"password_auth"}' | jq -r '.token')"

if [ -z "$NON_SELLER_JWT" ] || [ "$NON_SELLER_JWT" = "null" ]; then
  echo "Failed to obtain JWT for non-seller user_auth"
  exit 1
fi

echo "Non-seller JWT acquired"

# Attempt to update product inventory as unauthorized user (no active seller profile)
UNAUTH_RESP="$(curl -s -o /tmp/unauth_resp.json -w "%{http_code}" -X PUT http://app:6713/products/prod_1 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${NON_SELLER_JWT}" \
  -d '{"stock_qty":0}')"
echo "UNAUTH_STATUS=${UNAUTH_RESP}"
cat /tmp/unauth_resp.json || true

### Then
# Assert that the status code indicates authorization failure (401 or 403)
if [ "$UNAUTH_RESP" != "401" ] && [ "$UNAUTH_RESP" != "403" ]; then
  echo "Expected 401 or 403 for unauthorized inventory update, got ${UNAUTH_RESP}"
  exit 1
fi

# Verify product inventory is unchanged in the database
echo "Verifying product inventory remains unchanged..."
psql "$DATABASE_URL" -c "SELECT stock_qty, status FROM products WHERE id = 'prod_1';" > /tmp/prod_1_state.txt
cat /tmp/prod_1_state.txt

# Basic check that stock_qty is still 5 and status is still ACTIVE
if ! grep -q "5" /tmp/prod_1_state.txt; then
  echo "Expected stock_qty to remain 5 after unauthorized update attempt"
  exit 1
fi
if ! grep -q "ACTIVE" /tmp/prod_1_state.txt; then
  echo "Expected status to remain ACTIVE after unauthorized update attempt"
  exit 1
fi

### Teardown
# Clean up seeded data (optional; keep simple for test isolation)
echo "Cleaning up seeded data..."
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = 'prod_1';"
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = 'seller_1';"
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('user_auth','user_seller');"

# Success marker required by runner
echo "CODEVALID_TEST_ASSERTION_OK:unauthorized_user_cannot_modify_inventory"
