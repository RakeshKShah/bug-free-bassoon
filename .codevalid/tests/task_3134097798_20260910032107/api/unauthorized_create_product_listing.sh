#!/usr/bin/env bash
set -euo pipefail

# Case: unauthorized_create_product_listing

### Setup
source tests/task_3134097798_20260910032107/api/_infra.sh

# Ensure app PORT and DATABASE_URL are exported in the environment (provided by _infra.sh or test harness).
# Wait for the app to be healthy before running the test.
wait_for_health
curl -sS "http://app:${PORT}/health" | jq .

### Preconditions
# For this unauthorized case, we only need a migrated, empty products table; no auth setup.
# Confirm the database is reachable and migrations applied (assumed by shared infra).
# Optionally, ensure products table is empty before the test.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products;"

### When
# Send POST /products without any Authorization header or cookie.
# Use a valid-looking body so rejection is due to auth, not validation.
curl -sS -o /tmp/resp_unauth.json -w "%{http_code}" \
  -X POST "http://app:${PORT}/products" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Unauthorized widget",
    "description": "Attempted create without auth",
    "category": "widgets",
    "price_cents": 1999,
    "stock_qty": 10,
    "photos": []
  }' > /tmp/status_unauth.txt

### Then
# Assert the status code indicates auth failure (401 or 403 depending on requireAuth).
STATUS_CODE="$(cat /tmp/status_unauth.txt)"
echo "Status: ${STATUS_CODE}"
if [ "$STATUS_CODE" != "401" ] && [ "$STATUS_CODE" != "403" ]; then
  echo "EXPECTED 401 or 403 for unauthorized POST /products, got ${STATUS_CODE}"
  exit 1
fi

# Inspect the response body for an error key.
cat /tmp/resp_unauth.json | jq .

ERROR_MSG="$(jq -r '.error // empty' /tmp/resp_unauth.json)"
if [ -z "$ERROR_MSG" ]; then
  echo "EXPECTED error message in response body for unauthorized request"
  exit 1
fi

# Confirm that no product row was created.
PRODUCT_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products;")"
echo "Products count: ${PRODUCT_COUNT}"
if [ "$PRODUCT_COUNT" != "0" ]; then
  echo "EXPECTED no products created for unauthorized request, found ${PRODUCT_COUNT}"
  exit 1
fi

### Teardown
# Clean any data that might have been created (defensive; should be none).
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products;"

echo "CODEVALID_TEST_ASSERTION_OK:unauthorized_create_product_listing"
