#!/usr/bin/env bash
set -euo pipefail

# Case: validation_failure_non_integer_or_negative_stock
# Setup
source tests/task_3134097798_20260910032107/api/_infra.sh

# Confirm app port and DATABASE_URL are available
echo "PORT=${PORT}"
echo "DATABASE_URL=${DATABASE_URL}"

# Wait for app health (assuming GET /health is implemented per infra checklist)
curl -sS "http://app:${PORT}/health" | jq .

# Seed: create approved SELLER user and seller profile
# (Use schema details from prisma/schema.prisma)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, role, status, email, password_hash)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'SELLER', 'ACTIVE', 'seller1@example.com', 'test-hash');
" || { echo "Failed to insert seller user"; exit 1; }

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001', 'Test Store', 'Test bio');
" || { echo "Failed to insert seller profile"; exit 1; }

# Ensure products table is empty before test
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products;" || { echo "Failed to clear products"; exit 1; }

# Preconditions
# Database has one approved SELLER user and matching seller_profiles row; products is empty
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
SELECT id, role, status FROM users WHERE id = '00000000-0000-0000-0000-000000000001';
" || { echo "Precondition check for users failed"; exit 1; }

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
SELECT id, user_id, store_name FROM seller_profiles WHERE user_id = '00000000-0000-0000-0000-000000000001';
" || { echo "Precondition check for seller_profiles failed"; exit 1; }

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "SELECT COUNT(*) AS product_count FROM products;" || { echo "Precondition check for products failed"; exit 1; }

## When
# 1) stock_qty as a string
INVALID_STRING_BODY=$(cat <<'JSON'
{
  "title": "Invalid stock product - string",
  "description": "Should fail validation due to string stock_qty",
  "category": "gadgets",
  "price_cents": 1999,
  "stock_qty": "ten",
  "photos": []
}
JSON
)

curl -sS -o /tmp/resp_invalid_string.json -w "%{http_code}" \
  -X POST "http://app:${PORT}/products" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${SELLER1_TOKEN}" \
  --data "${INVALID_STRING_BODY}"

echo
cat /tmp/resp_invalid_string.json | jq .

# 2) stock_qty as a decimal
INVALID_DECIMAL_BODY=$(cat <<'JSON'
{
  "title": "Invalid stock product - decimal",
  "description": "Should fail validation due to decimal stock_qty",
  "category": "gadgets",
  "price_cents": 2999,
  "stock_qty": 10.5,
  "photos": []
}
JSON
)

curl -sS -o /tmp/resp_invalid_decimal.json -w "%{http_code}" \
  -X POST "http://app:${PORT}/products" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${SELLER1_TOKEN}" \
  --data "${INVALID_DECIMAL_BODY}"

echo
cat /tmp/resp_invalid_decimal.json | jq .

# 3) stock_qty as a negative integer
INVALID_NEGATIVE_BODY=$(cat <<'JSON'
{
  "title": "Invalid stock product - negative",
  "description": "Should fail validation due to negative stock_qty",
  "category": "gadgets",
  "price_cents": 3999,
  "stock_qty": -1,
  "photos": []
}
JSON
)

curl -sS -o /tmp/resp_invalid_negative.json -w "%{http_code}" \
  -X POST "http://app:${PORT}/products" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${SELLER1_TOKEN}" \
  --data "${INVALID_NEGATIVE_BODY}"

echo
cat /tmp/resp_invalid_negative.json | jq .

## Then
# Assert each response is a validation failure (HTTP 400 and error key present)
status_string=$(jq -r '._status // empty' /tmp/resp_invalid_string.json 2>/dev/null || echo "")
status_decimal=$(jq -r '._status // empty' /tmp/resp_invalid_decimal.json 2>/dev/null || echo "")
status_negative=$(jq -r '._status // empty' /tmp/resp_invalid_negative.json 2>/dev/null || echo "")

if [[ "$status_string" != "400" ]] || [[ "$status_decimal" != "400" ]] || [[ "$status_negative" != "400" ]]; then
  echo "Expected HTTP 400 status for all invalid stock_qty requests";
  exit 1;
fi

jq '.error' /tmp/resp_invalid_string.json >/dev/null || { echo "Missing error key for string stock_qty"; exit 1; }
jq '.error' /tmp/resp_invalid_decimal.json >/dev/null || { echo "Missing error key for decimal stock_qty"; exit 1; }
jq '.error' /tmp/resp_invalid_negative.json >/dev/null || { echo "Missing error key for negative stock_qty"; exit 1; }

# Confirm no products were created
product_count=$(psql "$DATABASE_URL" -At -v ON_ERROR_STOP=1 -c "SELECT COUNT(*) AS product_count FROM products;" | tr -d '[:space:]')
if [[ "$product_count" != "0" ]]; then
  echo "Expected no products to be created, found: $product_count";
  exit 1;
fi

## Teardown
# Clean up seeded data (optional if tests run in isolated DB)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products;" || { echo "Teardown failed: products"; exit 1; }
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = '11111111-1111-1111-1111-111111111111';" || { echo "Teardown failed: seller_profiles"; exit 1; }
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '00000000-0000-0000-0000-000000000001';" || { echo "Teardown failed: users"; exit 1; }

# Success marker required by runner
echo "CODEVALID_TEST_ASSERTION_OK:validation_failure_non_integer_or_negative_stock"
