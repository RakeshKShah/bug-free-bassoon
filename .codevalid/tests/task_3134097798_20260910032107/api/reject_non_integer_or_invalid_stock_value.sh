#!/usr/bin/env bash
set -euo pipefail

# Setup
source tests/task_3134097798_20260910032107/api/_infra.sh

# Read repo files as per plan (no-ops in script, documented for traceability)
# prisma/schema.prisma
# src/routes/products.ts
# src/services/payouts.ts

psql "$DATABASE_URL" -c "TRUNCATE TABLE products RESTART IDENTITY CASCADE;"
psql "$DATABASE_URL" -c "TRUNCATE TABLE seller_profiles RESTART IDENTITY CASCADE;"
psql "$DATABASE_URL" -c "TRUNCATE TABLE users RESTART IDENTITY CASCADE;"

# Seed a user row compatible with seller_profiles.user_id FK.
psql "$DATABASE_URL" -c "
  INSERT INTO users (id, email, password_hash, role)
  VALUES (
    'user-stock-invalid-1',
    'seller_invalid_stock@example.com',
    '\$2b\$10\$0123456789abcdef01234uPq7uPq7uPq7uPq7uPq7uPq7uPq7uPq7',
    'SELLER'
  );
"

# Seed a seller profile for that user.
psql "$DATABASE_URL" -c "
  INSERT INTO seller_profiles (id, user_id, store_name, bio)
  VALUES (
    'seller-invalid-stock-1',
    'user-stock-invalid-1',
    'Invalid Stock Test Store',
    'Store used for invalid stock_qty tests'
  );
"

# Seed an ACTIVE visible product with an integer stock_qty.
psql "$DATABASE_URL" -c "
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
    'product-invalid-stock-1',
    'seller-invalid-stock-1',
    'Test Product Invalid Stock',
    'Product used to verify invalid stock_qty update validation',
    'test-category',
    1500,
    5,
    '[]'::json,
    'ACTIVE',
    true,
    NOW()
  );
"

# Obtain JWT for the seeded user via the app’s auth API.
AUTH_RESPONSE="$(curl -s -X POST http://app:6713/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"seller_invalid_stock@example.com","password":"password-placeholder"}')"
JWT_TOKEN="$(echo "$AUTH_RESPONSE" | jq -r '.token')"

if [[ -z "$JWT_TOKEN" || "$JWT_TOKEN" == "null" ]]; then
  echo "Failed to obtain JWT token for seller_invalid_stock@example.com" >&2
  exit 1
fi

# Confirm app health before running the case.
curl -s http://app:6713/health | jq '.' || true

# Preconditions
psql "$DATABASE_URL" -c "
  SELECT id, seller_id, stock_qty, status, visible
  FROM products
  WHERE id = 'product-invalid-stock-1';
"

# When
# 1) Attempt to update stock_qty with a string value (invalid type).
INVALID_RESPONSE_STRING="$(curl -s -o /tmp/invalid_stock_string_resp.json -w '%{http_code}' \
  -X PUT http://app:6713/products/product-invalid-stock-1 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -d '{"stock_qty":"not-an-integer"}')"
echo "HTTP status (string stock_qty): $INVALID_RESPONSE_STRING"
cat /tmp/invalid_stock_string_resp.json | jq '.' || true

# 2) Attempt to update stock_qty with a float value (invalid for Int).
INVALID_RESPONSE_FLOAT="$(curl -s -o /tmp/invalid_stock_float_resp.json -w '%{http_code}' \
  -X PUT http://app:6713/products/product-invalid-stock-1 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -d '{"stock_qty":3.5}')"
echo "HTTP status (float stock_qty): $INVALID_RESPONSE_FLOAT"
cat /tmp/invalid_stock_float_resp.json | jq '.' || true

# Then
# Assert HTTP 400 responses for both invalid payloads.
test "$INVALID_RESPONSE_STRING" -eq 400
test "$INVALID_RESPONSE_FLOAT" -eq 400

# Confirm the error key exists and is a non-empty string.
jq -e '.error | select(type=="string" and length>0)' /tmp/invalid_stock_string_resp.json >/dev/null
jq -e '.error | select(type=="string" and length>0)' /tmp/invalid_stock_float_resp.json >/dev/null

# Verify that stock_qty was not modified and remains the original integer value (5).
psql "$DATABASE_URL" -c "
  SELECT id, stock_qty
  FROM products
  WHERE id = 'product-invalid-stock-1';
"

ACTUAL_STOCK_QTY="$(psql "$DATABASE_URL" -t -A -c "SELECT stock_qty FROM products WHERE id = 'product-invalid-stock-1';")"
test "$ACTUAL_STOCK_QTY" -eq 5

# Teardown
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = 'product-invalid-stock-1';"
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = 'seller-invalid-stock-1';"
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = 'user-stock-invalid-1';"

# Success marker required by runner
echo "CODEVALID_TEST_ASSERTION_OK:reject_non_integer_or_invalid_stock_value"
