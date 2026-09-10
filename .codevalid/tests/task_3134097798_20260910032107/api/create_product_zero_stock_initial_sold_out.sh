#!/usr/bin/env bash
set -euo pipefail

# Setup
source tests/task_3134097798_20260910032107/api/_infra.sh
export PORT="${PORT:-3000}"

# Optional repo context reads from plan (no-op for execution, but kept for traceability)
if [ -f .codevalid/docker-compose.yml ]; then
  : "docker-compose file present"
fi
if [ -f prisma/schema.prisma ]; then
  : "prisma schema present"
fi

# Wait for app health
wait_for_http "http://app:${PORT}/health"

# Preconditions (seed)
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('00000000-0000-0000-0000-000000000001', 'seller@example.com', 'hashedpassword', 'SELLER', 'ACTIVE');"
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000001', 'Zero Stock Store', 'Store for sold-out tests');"

# When: initial POST to capture sample response
curl -sS -X POST "http://app:${PORT}/products" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${SELLER_TOKEN}" \
  -d '{
    "title": "Sold-out from start",
    "description": "Product created with zero inventory",
    "category": "test-category",
    "price_cents": 1999,
    "stock_qty": 0,
    "photos": []
  }' \
  | tee /tmp/create_product_zero_stock_initial_sold_out.json >/dev/null

# Then: status check with second POST
HTTP_STATUS=$(curl -sS -o /tmp/create_product_zero_stock_initial_sold_out_status_body.json -w '%{http_code}' -X POST "http://app:${PORT}/products" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${SELLER_TOKEN}" \
  -d '{
    "title": "Sold-out from start (status check)",
    "description": "Product created with zero inventory (status check)",
    "category": "test-category",
    "price_cents": 1999,
    "stock_qty": 0,
    "photos": []
  }')

if [ "${HTTP_STATUS}" != "201" ]; then
  echo "Expected 201 from POST /products, got ${HTTP_STATUS}" >&2
  # Teardown on failure for isolation
  psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE seller_id = '00000000-0000-0000-0000-000000000010';" || true
  psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = '00000000-0000-0000-0000-000000000010';" || true
  psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '00000000-0000-0000-0000-000000000001';" || true
  exit 1
fi

PRODUCT_JSON=/tmp/create_product_zero_stock_initial_sold_out_status_body.json

STOCK_QTY=$(jq '.stockQty' "${PRODUCT_JSON}")
STATUS=$(jq -r '.status' "${PRODUCT_JSON}")
VISIBLE=$(jq '.visible' "${PRODUCT_JSON}")

if [ "${STOCK_QTY}" != "0" ]; then
  echo "Expected stockQty 0, got ${STOCK_QTY}" >&2
  psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE seller_id = '00000000-0000-0000-0000-000000000010';" || true
  psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = '00000000-0000-0000-0000-000000000010';" || true
  psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '00000000-0000-0000-0000-000000000001';" || true
  exit 1
fi

if [ "${STATUS}" != "SOLD_OUT" ]; then
  echo "Expected status SOLD_OUT, got ${STATUS}" >&2
  psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE seller_id = '00000000-0000-0000-0000-000000000010';" || true
  psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = '00000000-0000-0000-0000-000000000010';" || true
  psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '00000000-0000-0000-0000-000000000001';" || true
  exit 1
fi

if [ "${VISIBLE}" != "true" ]; then
  echo "Expected visible true, got ${VISIBLE}" >&2
  psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE seller_id = '00000000-0000-0000-0000-000000000010';" || true
  psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = '00000000-0000-0000-0000-000000000010';" || true
  psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '00000000-0000-0000-0000-000000000001';" || true
  exit 1
fi

PHOTOS_TYPE=$(jq -r 'if .photos == null then "null" else (if (.photos|type)=="array" then "array" else "other" end) end' "${PRODUCT_JSON}")
if [ "${PHOTOS_TYPE}" = "null" ]; then
  echo "Expected photos key to be non-null" >&2
  psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE seller_id = '00000000-0000-0000-0000-000000000010';" || true
  psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = '00000000-0000-0000-0000-000000000010';" || true
  psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '00000000-0000-0000-0000-000000000001';" || true
  exit 1
fi

# Teardown
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE seller_id = '00000000-0000-0000-0000-000000000010';"
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = '00000000-0000-0000-0000-000000000010';"
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '00000000-0000-0000-0000-000000000001';"

echo "CODEVALID_TEST_ASSERTION_OK:create_product_zero_stock_initial_sold_out"
