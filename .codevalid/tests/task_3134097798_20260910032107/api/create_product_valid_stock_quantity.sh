#!/usr/bin/env bash
set -euo pipefail

# Case: create_product_valid_stock_quantity

# Setup
source tests/task_3134097798_20260910032107/api/_infra.sh

# Ensure app and database (via toxiproxy) are up; healthcheck endpoint should return 200.
HTTP_STATUS=$(curl -sS -o /tmp/health_resp.json -w "%{http_code}" "http://app:${PORT}/health")
if [ "${HTTP_STATUS}" -ne 200 ]; then
  echo "Healthcheck failed, status=${HTTP_STATUS}" >&2
  cat /tmp/health_resp.json || true
  exit 1
fi

# Read Prisma schema to confirm Product and SellerProfile models and enum values.
read_repo_file prisma/schema.prisma >/tmp/schema.prisma

# Preconditions
# Seed an approved SELLER user and matching seller_profile.
# Column names and role/status literals must match actual schema.
# Schema enums: Role (BUYER, SELLER, ADMIN), UserStatus (PENDING, ACTIVE, SUSPENDED).

psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status)
VALUES (
  'seller-user-1',
  'seller1@example.com',
  'hashed-password',
  'SELLER',
  'ACTIVE'
);
" || {
  echo "Failed to insert seller user" >&2
  exit 1
}

psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES (
  'seller-profile-1',
  'seller-user-1',
  'Test Store',
  'Test seller profile bio'
);
" || {
  echo "Failed to insert seller profile" >&2
  exit 1
}

# When
# Perform authenticated POST /products as the seeded SELLER user.
# Assume TOKEN provided via environment or _infra; fail if missing.
: "${TOKEN:?TOKEN must be set in environment or _infra.sh}"

REQUEST_BODY=$(cat <<'JSON'
{
  "title": "Sample Product",
  "description": "Sample product description",
  "category": "Accessories",
  "price_cents": 1999,
  "stock_qty": 10,
  "photos": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"]
}
JSON
)

RESPONSE=$(curl -sS "http://app:${PORT}/products" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d "${REQUEST_BODY}")

echo "Create product response:" >&2
echo "${RESPONSE}" | jq . >&2 || true

# Then
HTTP_STATUS=$(curl -sS -o /tmp/create_product_resp.json -w "%{http_code}" \
  "http://app:${PORT}/products" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d "${REQUEST_BODY}")

if [ "${HTTP_STATUS}" -ne 201 ]; then
  echo "Expected HTTP 201, got ${HTTP_STATUS}" >&2
  cat /tmp/create_product_resp.json || true
  # Teardown partial data before exiting
  psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = 'seller-profile-1';" || true
  psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = 'seller-user-1';" || true
  exit 1
fi

RESPONSE_BODY=$(cat /tmp/create_product_resp.json)

echo "Validated response body:" >&2
echo "${RESPONSE_BODY}" | jq . >&2 || true

# Validate essential fields in the response.
echo "${RESPONSE_BODY}" | jq -e '.id | length > 0' >/dev/null
# sellerId should match the seeded seller profile id
echo "${RESPONSE_BODY}" | jq -e '.sellerId == "seller-profile-1"' >/dev/null
echo "${RESPONSE_BODY}" | jq -e '.title == "Sample Product"' >/dev/null
echo "${RESPONSE_BODY}" | jq -e '.description == "Sample product description"' >/dev/null
echo "${RESPONSE_BODY}" | jq -e '.category == "Accessories"' >/dev/null
echo "${RESPONSE_BODY}" | jq -e '.priceCents == 1999' >/dev/null
echo "${RESPONSE_BODY}" | jq -e '.stockQty == 10' >/dev/null
echo "${RESPONSE_BODY}" | jq -e '.photos | length == 2' >/dev/null
echo "${RESPONSE_BODY}" | jq -e '.status == "ACTIVE"' >/dev/null
echo "${RESPONSE_BODY}" | jq -e '.visible == true' >/dev/null
echo "${RESPONSE_BODY}" | jq -e '.createdAt | length > 0' >/dev/null

# Cross-check persistence in the products table.
PRODUCT_ID=$(echo "${RESPONSE_BODY}" | jq -r '.id')

psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "
SELECT id, seller_id, title, description, category, price_cents, stock_qty, status, visible
FROM products
WHERE id = '${PRODUCT_ID}'
;" > /tmp/db_product_row.txt

grep "Sample Product" /tmp/db_product_row.txt >/dev/null
grep "seller-profile-1" /tmp/db_product_row.txt >/dev/null
grep "1999" /tmp/db_product_row.txt >/dev/null
grep "10" /tmp/db_product_row.txt >/dev/null
grep "ACTIVE" /tmp/db_product_row.txt >/dev/null
# visible true in Postgres boolean output is 't'
grep "t" /tmp/db_product_row.txt >/dev/null

# Teardown
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "
DELETE FROM products WHERE id = '${PRODUCT_ID}';
" || echo "Failed to delete product ${PRODUCT_ID}" >&2

psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "
DELETE FROM seller_profiles WHERE id = 'seller-profile-1';
" || echo "Failed to delete seller profile" >&2

psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "
DELETE FROM users WHERE id = 'seller-user-1';
" || echo "Failed to delete seller user" >&2

# Success marker for runner
echo "CODEVALID_TEST_ASSERTION_OK:create_product_valid_stock_quantity"
