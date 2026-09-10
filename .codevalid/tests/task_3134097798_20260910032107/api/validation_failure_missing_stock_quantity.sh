#!/usr/bin/env bash
set -euo pipefail

# Case: validation_failure_missing_stock_quantity

# Setup
source tests/task_3134097798_20260910032107/api/_infra.sh

# Ensure DATABASE_URL and PORT are exported by _infra.sh and docker-compose is up
wait_for_http "http://app:${PORT}/health" 60

# Preconditions (seed)
# 1. Read Prisma schema to confirm datasource env and model fields
# (Already inspected via tooling in the test harness; no runtime action needed here.)

# 2. Seed an approved SELLER user
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO users (id, role, status, email, password_hash) VALUES ('seller-user-1', 'SELLER', 'ACTIVE', 'seller1@example.com', 'test-hash');"

# 3. Seed a seller_profiles row linked to the user
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('seller-profile-1', 'seller-user-1', 'Test Store', 'Test bio');"

# 4. Optionally verify the seeded seller profile
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "SELECT id, user_id, store_name FROM seller_profiles WHERE id = 'seller-profile-1';"

# 5. Prepare auth header or token for the seller user
# Implementation depends on auth; expected to be provided by _infra.sh
# using the same seller identity (seller1@example.com) when possible.

# When
# 6. Call POST /products without stock_qty
curl -sS -o /tmp/resp.json -w '%{http_code}' \
  -X POST "http://app:${PORT}/products" \
  -H "Content-Type: application/json" \
  -H "$auth_header" \
  -d '{
    "title": "No stock field product",
    "description": "Product created without stock quantity",
    "category": "general",
    "price_cents": 1500,
    "photos": []
  }' > /tmp/status.txt

# Then
# 7. Assert HTTP status is 400
status=$(cat /tmp/status.txt)
if [ "$status" != "400" ]; then
  echo "Expected status 400, got $status" >&2
  exit 1
fi

# 8. Assert response has an error message indicating validation failure
error_msg=$(jq -r '.error // empty' /tmp/resp.json)
if [ -z "$error_msg" ]; then
  echo "Expected non-empty error message in response" >&2
  cat /tmp/resp.json >&2
  exit 1
fi

# 9. Confirm no product row was created for this seller
product_count=$(psql "$DATABASE_URL" -t -A -v ON_ERROR_STOP=1 -c "SELECT COUNT(*) FROM products WHERE seller_id = 'seller-profile-1';")
if [ "$product_count" != "0" ]; then
  echo "Expected 0 products for seller-profile-1, found $product_count" >&2
  exit 1
fi

# Teardown
# 10. Clean up seeded data
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE seller_id = 'seller-profile-1';"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = 'seller-profile-1';"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = 'seller-user-1';"

# Success marker required by the runner
echo "CODEVALID_TEST_ASSERTION_OK:validation_failure_missing_stock_quantity"
