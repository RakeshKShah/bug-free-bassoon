#!/usr/bin/env bash
set -euo pipefail

# Case: update_other_fields_without_changing_stock

### Setup
source tests/task_3134097798_20260910032107/api/_infra.sh

# Wait for app health to be ready before running requests
wait_for_app_health() {
  local url="$1"
  local max_retries=30
  local sleep_seconds=2
  local attempt=1

  while [ "$attempt" -le "$max_retries" ]; do
    if curl -s -o /dev/null "$url"; then
      echo "App health check succeeded on attempt $attempt"
      return 0
    fi
    echo "Waiting for app health... attempt $attempt/$max_retries" >&2
    attempt=$((attempt + 1))
    sleep "$sleep_seconds"
  done

  echo "App health check failed after $max_retries attempts" >&2
  return 1
}

wait_for_app_health "http://localhost:6713/health"

# Seed base user, seller profile, and product rows
# 1. Create a user compatible with seller_profiles.user_id FK.
psql "$DATABASE_URL" -c "
INSERT INTO users (id, email, password_hash)
VALUES (
  '11111111-1111-1111-1111-111111111111',
  'seller@example.com',
  '\$2b\$10\$testhashforsellerpassword'
)
ON CONFLICT (id) DO NOTHING;
"

# 2. Create a seller profile linked to that user.
psql "$DATABASE_URL" -c "
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES (
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111',
  'Test Store',
  'Test seller bio'
)
ON CONFLICT (id) DO NOTHING;
"

# 3. Create an ACTIVE product with non-zero stock_qty and known metadata.
psql "$DATABASE_URL" -c "
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES (
  '33333333-3333-3333-3333-333333333333',
  '22222222-2222-2222-2222-222222222222',
  'Original Title',
  'Original Description',
  'Original Category',
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

# Obtain JWT for the seeded user using existing auth endpoint.
# (Assumes POST /auth/login or similar; adjust path if needed.)
AUTH_TOKEN="$(
  curl -s -X POST "http://app:6713/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"seller@example.com","password":"password"}' | jq -r '.token'
)"

if [ -z "$AUTH_TOKEN" ] || [ "$AUTH_TOKEN" = "null" ]; then
  echo "Failed to obtain auth token for seller user" >&2
  exit 1
fi

### Preconditions
# Verify seeded product exists with expected initial values.
psql "$DATABASE_URL" -c "
SELECT id, seller_id, title, description, category, price_cents, stock_qty, status, visible
FROM products
WHERE id = '33333333-3333-3333-3333-333333333333';
"

# Optional: assert initial stock_qty and status via jqable query.
INITIAL_ROW_JSON="$(
  psql "$DATABASE_URL" -t -A -F"," -c "
    SELECT stock_qty, status
    FROM products
    WHERE id = '33333333-3333-3333-3333-333333333333';
  " | awk -F',' 'NF==2 {printf "{\"stock_qty\":%s,\"status\":\"%s\"}
", $1, $2}'
)"

echo "$INITIAL_ROW_JSON" | jq '.'

ORIGINAL_STOCK_QTY="$(echo "$INITIAL_ROW_JSON" | jq -r '.stock_qty')"
ORIGINAL_STATUS="$(echo "$INITIAL_ROW_JSON" | jq -r '.status')"

if [ "$ORIGINAL_STOCK_QTY" != "5" ]; then
  echo "Unexpected initial stock_qty: $ORIGINAL_STOCK_QTY" >&2
  exit 1
fi

if [ "$ORIGINAL_STATUS" != "ACTIVE" ]; then
  echo "Unexpected initial status: $ORIGINAL_STATUS" >&2
  exit 1
fi

### When
# Perform PUT /products/{id} updating metadata only, omitting stock_qty.
UPDATE_RESPONSE="$(
  curl -s -X PUT "http://app:6713/products/33333333-3333-3333-3333-333333333333" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -d '{
      "title": "Updated Title",
      "description": "Updated Description",
      "category": "Updated Category",
      "price_cents": 1500,
      "photos": []
    }'
)"

echo "$UPDATE_RESPONSE" | jq '.'

HTTP_STATUS="$(
  curl -s -o /dev/null -w "%{http_code}" -X PUT "http://app:6713/products/33333333-3333-3333-3333-333333333333" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -d '{
      "title": "Updated Title 2",
      "description": "Updated Description 2",
      "category": "Updated Category 2",
      "price_cents": 2000,
      "photos": []
    }'
)"

echo "Second PUT status: $HTTP_STATUS"

if [ "$HTTP_STATUS" != "200" ]; then
  echo "Expected 200 OK for metadata-only update, got $HTTP_STATUS" >&2
  # Proceeding to teardown before exit
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '33333333-3333-3333-3333-333333333333';"
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '22222222-2222-2222-2222-222222222222';"
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '11111111-1111-1111-1111-111111111111';"
  exit 1
fi

### Then
# Re-fetch product after update to validate fields and stock.
GET_RESPONSE="$(
  curl -s "http://app:6713/products/33333333-3333-3333-3333-333333333333" \
    -H "Authorization: Bearer $AUTH_TOKEN"
)"

echo "$GET_RESPONSE" | jq '.'

# Validate updated fields in the JSON response.
UPDATED_TITLE="$(echo "$GET_RESPONSE" | jq -r '.title')"
UPDATED_DESCRIPTION="$(echo "$GET_RESPONSE" | jq -r '.description')"
UPDATED_CATEGORY="$(echo "$GET_RESPONSE" | jq -r '.category')"
UPDATED_PRICE_CENTS="$(echo "$GET_RESPONSE" | jq -r '.price_cents // .priceCents')"
UPDATED_STOCK_QTY="$(echo "$GET_RESPONSE" | jq -r '.stock_qty // .stockQty')"
UPDATED_STATUS="$(echo "$GET_RESPONSE" | jq -r '.status')"
UPDATED_VISIBLE="$(echo "$GET_RESPONSE" | jq -r '.visible')"

# Ensure metadata changes took effect.
if [ "$UPDATED_TITLE" != "Updated Title 2" ]; then
  echo "Title was not updated as expected: $UPDATED_TITLE" >&2
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '33333333-3333-3333-3333-333333333333';"
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '22222222-2222-2222-2222-222222222222';"
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '11111111-1111-1111-1111-111111111111';"
  exit 1
fi

if [ "$UPDATED_DESCRIPTION" != "Updated Description 2" ]; then
  echo "Description was not updated as expected: $UPDATED_DESCRIPTION" >&2
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '33333333-3333-3333-3333-333333333333';"
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '22222222-2222-2222-2222-222222222222';"
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '11111111-1111-1111-1111-111111111111';"
  exit 1
fi

if [ "$UPDATED_CATEGORY" != "Updated Category 2" ]; then
  echo "Category was not updated as expected: $UPDATED_CATEGORY" >&2
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '33333333-3333-3333-3333-333333333333';"
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '22222222-2222-2222-2222-222222222222';"
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '11111111-1111-1111-1111-111111111111';"
  exit 1
fi

if [ "$UPDATED_PRICE_CENTS" != "2000" ]; then
  echo "price_cents/priceCents was not updated as expected: $UPDATED_PRICE_CENTS" >&2
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '33333333-3333-3333-3333-333333333333';"
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '22222222-2222-2222-2222-222222222222';"
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '11111111-1111-1111-1111-111111111111';"
  exit 1
fi

# stockQty must remain unchanged (still 5).
if [ "$UPDATED_STOCK_QTY" != "5" ]; then
  echo "stock_qty/stockQty changed unexpectedly: $UPDATED_STOCK_QTY (expected 5)" >&2
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '33333333-3333-3333-3333-333333333333';"
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '22222222-2222-2222-2222-222222222222';"
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '11111111-1111-1111-1111-111111111111';"
  exit 1
fi

# Status should remain ACTIVE and visible true (still purchasable).
if [ "$UPDATED_STATUS" != "ACTIVE" ]; then
  echo "Product status changed unexpectedly: $UPDATED_STATUS (expected ACTIVE)" >&2
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '33333333-3333-3333-3333-333333333333';"
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '22222222-2222-2222-2222-222222222222';"
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '11111111-1111-1111-1111-111111111111';"
  exit 1
fi

if [ "$UPDATED_VISIBLE" != "true" ] && [ "$UPDATED_VISIBLE" != "True" ]; then
  echo "Product visibility changed unexpectedly: $UPDATED_VISIBLE (expected true)" >&2
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '33333333-3333-3333-3333-333333333333';"
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '22222222-2222-2222-2222-222222222222';"
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '11111111-1111-1111-1111-111111111111';"
  exit 1
fi

# Double-check DB row directly for stock and status consistency.
DB_ROW_JSON="$(
  psql "$DATABASE_URL" -t -A -F"," -c "
    SELECT stock_qty, status, visible
    FROM products
    WHERE id = '33333333-3333-3333-3333-333333333333';
  " | awk -F',' 'NF==3 {printf "{\"stock_qty\":%s,\"status\":\"%s\",\"visible\":%s}
", $1, $2, $3}'
)"

echo "$DB_ROW_JSON" | jq '.'

DB_STOCK_QTY="$(echo "$DB_ROW_JSON" | jq -r '.stock_qty')"
DB_STATUS="$(echo "$DB_ROW_JSON" | jq -r '.status')"
DB_VISIBLE="$(echo "$DB_ROW_JSON" | jq -r '.visible')"

if [ "$DB_STOCK_QTY" != "5" ]; then
  echo "Database stock_qty changed unexpectedly: $DB_STOCK_QTY (expected 5)" >&2
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '33333333-3333-3333-3333-333333333333';"
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '22222222-2222-2222-2222-222222222222';"
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '11111111-1111-1111-1111-111111111111';"
  exit 1
fi

if [ "$DB_STATUS" != "ACTIVE" ]; then
  echo "Database status changed unexpectedly: $DB_STATUS (expected ACTIVE)" >&2
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '33333333-3333-3333-3333-333333333333';"
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '22222222-2222-2222-2222-222222222222';"
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '11111111-1111-1111-1111-111111111111';"
  exit 1
fi

if [ "$DB_VISIBLE" != "t" ] && [ "$DB_VISIBLE" != "true" ]; then
  echo "Database visible flag changed unexpectedly: $DB_VISIBLE (expected true/t)" >&2
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '33333333-3333-3333-3333-333333333333';"
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '22222222-2222-2222-2222-222222222222';"
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '11111111-1111-1111-111111111111';"
  exit 1
fi

### Teardown
# Clean up seeded data to avoid cross-test contamination.
psql "$DATABASE_URL" -c "
DELETE FROM products
WHERE id = '33333333-3333-3333-3333-333333333333';
"

psql "$DATABASE_URL" -c "
DELETE FROM seller_profiles
WHERE id = '22222222-2222-2222-2222-222222222222';
"

psql "$DATABASE_URL" -c "
DELETE FROM users
WHERE id = '11111111-1111-1111-1111-111111111111';
"

echo "CODEVALID_TEST_ASSERTION_OK:update_other_fields_without_changing_stock"
