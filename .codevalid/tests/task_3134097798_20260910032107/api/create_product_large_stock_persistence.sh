#!/usr/bin/env bash
set -euo pipefail

# Case: create_product_large_stock_persistence

# Setup
source tests/task_3134097798_20260910032107/api/_infra.sh

# Ensure schema reference is up to date (models and enums)
read_repo_file prisma/schema.prisma

# Wait for app health to be ready before running API calls
wait_for_health

# Preconditions
# Seed an approved SELLER user; ensure role/status literals come from schema / existing code
# (role includes 'SELLER'; status includes at least 'PENDING', 'SUSPENDED', and an approved status such as 'ACTIVE')
# Use deterministic UUIDs for FK relationships

SELLER_USER_ID="00000000-0000-0000-0000-000000000001"
SELLER_PROFILE_ID="00000000-0000-0000-0000-000000000002"

# Read users schema to confirm allowed role/status values
read_repo_file prisma/schema.prisma

# Insert seller user with role SELLER and approved status (e.g. 'ACTIVE')
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, role, status, email)
VALUES (
  '$SELLER_USER_ID',
  'SELLER',
  'ACTIVE',
  'large-stock-seller@example.com'
)
ON CONFLICT (id) DO UPDATE
SET role = EXCLUDED.role,
    status = EXCLUDED.status;
"

# Insert seller profile linked to the seller user
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES (
  '$SELLER_PROFILE_ID',
  '$SELLER_USER_ID',
  'High Volume Store',
  'Store for large inventory tests'
)
ON CONFLICT (id) DO UPDATE
SET user_id = EXCLUDED.user_id,
    store_name = EXCLUDED.store_name;
"

# Export auth context for the seed-test client; requireAuth will read from the session/token
# Implementation of create_auth_token is in infra; we just call it.
SELLER_TOKEN="$(create_auth_token "$SELLER_USER_ID" "SELLER" "ACTIVE")"

# When
# Create a product with a large but valid stock_qty value
LARGE_STOCK_QTY=9999

CREATE_PRODUCT_RESPONSE="$(
  curl -sS -X POST "http://app:${PORT}/products" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${SELLER_TOKEN}" \
    -d "{
      \"title\": \"Bulk Widget Pack\",
      \"description\": \"A large inventory pack for stress testing.\",
      \"category\": \"STRESS_TEST_CATEGORY\",
      \"price_cents\": 1599,
      \"stock_qty\": ${LARGE_STOCK_QTY},
      \"photos\": []
    }"
)"

echo "$CREATE_PRODUCT_RESPONSE" | jq '.'

HTTP_STATUS="$(
  curl -sS -o /tmp/create_product_body.json -w "%{http_code}" -X POST "http://app:${PORT}/products" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${SELLER_TOKEN}" \
    -d "{
      \"title\": \"Bulk Widget Pack\",
      \"description\": \"A large inventory pack for stress testing.\",
      \"category\": \"STRESS_TEST_CATEGORY\",
      \"price_cents\": 1599,
      \"stock_qty\": ${LARGE_STOCK_QTY},
      \"photos\": []
    }"
)"

CREATE_PRODUCT_BODY="$(cat /tmp/create_product_body.json)"
echo "$CREATE_PRODUCT_BODY" | jq '.'

PRODUCT_ID="$(echo "$CREATE_PRODUCT_BODY" | jq -r '.id')"
RESPONSE_STOCK_QTY="$(echo "$CREATE_PRODUCT_BODY" | jq -r '.stockQty')"
RESPONSE_STATUS="$(echo "$CREATE_PRODUCT_BODY" | jq -r '.status')"
RESPONSE_VISIBLE="$(echo "$CREATE_PRODUCT_BODY" | jq -r '.visible')"

# Then
# Assert HTTP status is 201
if [ "$HTTP_STATUS" != "201" ]; then
  echo "Expected HTTP 201 but got: $HTTP_STATUS"
  exit 1
fi

# Assert product id was returned and is non-empty
if [ -z "$PRODUCT_ID" ] || [ "$PRODUCT_ID" = "null" ]; then
  echo "Expected non-null product id in response, got: $PRODUCT_ID"
  exit 1
fi

# Assert stockQty in response equals the large quantity we sent
if [ "$RESPONSE_STOCK_QTY" != "$LARGE_STOCK_QTY" ]; then
  echo "Expected stockQty=$LARGE_STOCK_QTY but got: $RESPONSE_STOCK_QTY"
  exit 1
fi

# Assert status is ACTIVE for positive stock_qty
if [ "$RESPONSE_STATUS" != "ACTIVE" ]; then
  echo "Expected status='ACTIVE' for positive stock_qty but got: $RESPONSE_STATUS"
  exit 1
fi

# Assert visible is true
if [ "$RESPONSE_VISIBLE" != "true" ]; then
  echo "Expected visible=true but got: $RESPONSE_VISIBLE"
  exit 1
fi

# Verify persistence by reading the products row directly
DB_STOCK_QTY="$(
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -t -A -c "
    SELECT stock_qty FROM products WHERE id = '$PRODUCT_ID';
  "
)"

DB_STATUS="$(
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -t -A -c "
    SELECT status FROM products WHERE id = '$PRODUCT_ID';
  "
)"

DB_VISIBLE="$(
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -t -A -c "
    SELECT visible FROM products WHERE id = '$PRODUCT_ID';
  "
)"

# Trim potential whitespace
DB_STOCK_QTY="$(echo "$DB_STOCK_QTY" | tr -d '[:space:]')"
DB_STATUS="$(echo "$DB_STATUS" | tr -d '[:space:]')"
DB_VISIBLE="$(echo "$DB_VISIBLE" | tr -d '[:space:]')"

if [ "$DB_STOCK_QTY" != "$LARGE_STOCK_QTY" ]; then
  echo "DB stock_qty persistence mismatch: expected $LARGE_STOCK_QTY but got: $DB_STOCK_QTY"
  exit 1
fi

if [ "$DB_STATUS" != "ACTIVE" ]; then
  echo "DB status mismatch: expected 'ACTIVE' but got: $DB_STATUS"
  exit 1
fi

if [ "$DB_VISIBLE" != "t" ] && [ "$DB_VISIBLE" != "true" ]; then
  echo "DB visible mismatch: expected true but got: $DB_VISIBLE"
  exit 1
fi

echo "create_product_large_stock_persistence: PASS"
echo "CODEVALID_TEST_ASSERTION_OK:create_product_large_stock_persistence"

# Teardown
# Clean up seeded product and seller records to avoid test pollution

if [ -n "$PRODUCT_ID" ] && [ "$PRODUCT_ID" != "null" ]; then
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
    DELETE FROM products WHERE id = '$PRODUCT_ID';
  "
fi

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  DELETE FROM seller_profiles WHERE id = '$SELLER_PROFILE_ID';
"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
  DELETE FROM users WHERE id = '$SELLER_USER_ID';
"
