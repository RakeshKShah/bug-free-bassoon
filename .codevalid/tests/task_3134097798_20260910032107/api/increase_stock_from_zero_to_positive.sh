#!/usr/bin/env bash
set -euo pipefail

# Case: increase_stock_from_zero_to_positive

### Setup
source tests/task_3134097798_20260910032107/api/_infra.sh

# Ensure migrations are applied (Prisma)
run_prisma_migrate

# Confirm app health
curl -f "http://app:6713/health"

### Preconditions
# Read Prisma schema for reference (do not echo contents)
read_repo_file prisma/schema.prisma

# 1) Seed a user row compatible with seller_profiles.user_id FK.
#    Use a stable UUID literal so it can be reused across inserts.
USER_ID="00000000-0000-0000-0000-000000000001"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash)
VALUES (
  '$USER_ID',
  'seller@example.com',
  '\$2b\$10\$testhashforsellerpasswordxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
);
" || true

# 2) Seed a seller_profiles row for that user.
SELLER_PROFILE_ID="00000000-0000-0000-0000-000000000002"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES (
  '$SELLER_PROFILE_ID',
  '$USER_ID',
  'Test Store',
  'Test seller bio'
);
" || true

# 3) Seed a sold-out product for that seller with stock_qty = 0 and status = 'SOLD_OUT'.
PRODUCT_ID="00000000-0000-0000-0000-000000000003"
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
) VALUES (
  '$PRODUCT_ID',
  '$SELLER_PROFILE_ID',
  'Sold-out item',
  'Initially sold-out product used for stock replenishment test.',
  'Accessories',
  1500,
  0,
  '[]'::json,
  'SOLD_OUT',
  true,
  NOW()
);
" || true

# 4) Obtain JWT for the seeded user using existing auth/login route.
#    Read routes to confirm login endpoint if needed.
read_repo_file src/routes/auth.ts || true

JWT_TOKEN="$(
  curl -s -X POST "http://app:6713/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"seller@example.com\",\"password\":\"password\"}" \
    | jq -r '.token'
)"

if [ -z "$JWT_TOKEN" ] || [ "$JWT_TOKEN" = "null" ]; then
  echo "Failed to obtain JWT token for seller user" >&2
  exit 1
fi

### When
# Increase stock from 0 to a positive value (e.g., 5) via PUT /products/{id}.
UPDATE_BODY="$(jq -n '{stock_qty: 5}')"

RESPONSE="$(
  curl -s -X PUT "http://app:6713/products/$PRODUCT_ID" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer '"$JWT_TOKEN"'" \
    -d "$UPDATE_BODY"
)"

echo "$RESPONSE" | jq '.'
HTTP_STATUS="$(
  curl -s -o /dev/null -w '%{http_code}' -X PUT "http://app:6713/products/$PRODUCT_ID" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    -d "$UPDATE_BODY"
)"

echo "HTTP_STATUS=$HTTP_STATUS"

### Then
# Assert HTTP status is 200.
if [ "$HTTP_STATUS" != "200" ]; then
  echo "Expected HTTP 200 from PUT /products/{id}, got $HTTP_STATUS" >&2
  exit 1
fi

# 1) stockQty should be the positive value we set (5).
STOCK_QTY="$(echo "$RESPONSE" | jq -r '.stockQty')"
if [ "$STOCK_QTY" != "5" ]; then
  echo "Expected stockQty=5 after update, got '$STOCK_QTY'" >&2
  exit 1
fi

# 2) status should have transitioned from SOLD_OUT to ACTIVE.
STATUS="$(echo "$RESPONSE" | jq -r '.status')"
if [ "$STATUS" != "ACTIVE" ]; then
  echo "Expected status='ACTIVE' after replenishing stock, got '$STATUS'" >&2
  exit 1
fi

# 3) visible should remain true (product visible and purchasable).
VISIBLE="$(echo "$RESPONSE" | jq -r '.visible')"
if [ "$VISIBLE" != "true" ]; then
  echo "Expected visible=true for product after stock increase, got '$VISIBLE'" >&2
  exit 1
fi

# 4) Confirm the record in DB reflects the updated stock and ACTIVE status.
DB_CHECK="$(psql "$DATABASE_URL" -t -A -F ',' -c "
SELECT stock_qty, status, visible
FROM products
WHERE id = '$PRODUCT_ID';
")"

echo "DB_CHECK=$DB_CHECK"

DB_STOCK_QTY="$(echo "$DB_CHECK" | cut -d',' -f1)"
DB_STATUS="$(echo "$DB_CHECK" | cut -d',' -f2)"
DB_VISIBLE="$(echo "$DB_CHECK" | cut -d',' -f3)"

if [ "$DB_STOCK_QTY" != "5" ]; then
  echo "DB: Expected stock_qty=5, got '$DB_STOCK_QTY'" >&2
  exit 1
fi

if [ "$DB_STATUS" != "ACTIVE" ]; then
  echo "DB: Expected status='ACTIVE', got '$DB_STATUS'" >&2
  exit 1
fi

if [ "$DB_VISIBLE" != "t" ] && [ "$DB_VISIBLE" != "true" ]; then
  echo "DB: Expected visible=true, got '$DB_VISIBLE'" >&2
  exit 1
fi

### Teardown
# Clean up seeded data to avoid cross-test pollution.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
DELETE FROM products WHERE id = '$PRODUCT_ID';
DELETE FROM seller_profiles WHERE id = '$SELLER_PROFILE_ID';
DELETE FROM users WHERE id = '$USER_ID';
"

# Success marker required by runner
echo "CODEVALID_TEST_ASSERTION_OK:increase_stock_from_zero_to_positive"
