#!/usr/bin/env bash
set -euo pipefail

# Case: update_stock_for_nonexistent_product

# Setup
source tests/task_3134097798_20260910032107/api/_infra.sh

# Seed a user row compatible with seller_profiles.user_id FK
psql "$DATABASE_URL" -c "
  INSERT INTO users (id, email, password_hash, role, status)
  VALUES (
    '11111111-1111-1111-1111-111111111111',
    'seller_nonexistent_product@example.com',
    '\$2b\$10\$testhashsellernonexistentproduct',
    'SELLER',
    'ACTIVE'
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    password_hash = EXCLUDED.password_hash,
    role = EXCLUDED.role,
    status = EXCLUDED.status;
"

# Seed an active seller profile for the user
psql "$DATABASE_URL" -c "
  INSERT INTO seller_profiles (id, user_id, store_name, bio)
  VALUES (
    '22222222-2222-2222-2222-222222222222',
    '11111111-1111-1111-1111-111111111111',
    'Nonexistent Product Store',
    'Store used for testing update of nonexistent products.'
  )
  ON CONFLICT (id) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    store_name = EXCLUDED.store_name,
    bio = EXCLUDED.bio;
"

# Verify that no products row exists for the target non-existent product id
psql "$DATABASE_URL" -c "
  DELETE FROM products
  WHERE id = '99999999-9999-9999-9999-999999999999';
"

# Obtain JWT for the seeded user: use a pre-baked token signed with JWT_SECRET=codevalid-test-secret
# matching user id=11111111-..., sellerProfileId=22222222-..., role=SELLER, status=ACTIVE
JWT_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjExMTExMTExLTExMTEtMTExMS0xMTExLTExMTExMTExMTExMSIsImVtYWlsIjoic2VsbGVyX25vbmV4aXN0ZW50X3Byb2R1Y3RAZXhhbXBsZS5jb20iLCJyb2xlIjoiU0VMTEVSIiwic3RhdHVzIjoiQUNUSVZFIiwic2VsbGVyUHJvZmlsZUlkIjoiMjIyMjIyMjItMjIyMi0yMjIyLTIyMjItMjIyMjIyMjIyMjIyIiwiaWF0IjoxNzAwMDAwMDAwLCJleHAiOjk5OTk5OTk5OTl9.NNsEzOqs7HeAXTL_qqube7OuVM6cJCpNxKT8d9G-urg"

# Preconditions
NONEXISTENT_COUNT="$(psql "$DATABASE_URL" -t -A -c "
  SELECT COUNT(*)
  FROM products
  WHERE id = '99999999-9999-9999-9999-999999999999';
" | tr -d '[:space:]')"
if [ "$NONEXISTENT_COUNT" != "0" ]; then
  echo "Expected no products with id 99999999-9999-9999-9999-999999999999, found $NONEXISTENT_COUNT" >&2
  exit 1
fi

# When: Call PUT /products/{id} for a non-existent product, attempting to update stock_qty
UPDATE_RESPONSE="$(
  curl -s -o /tmp/update_nonexistent_product.json -w '%{http_code}' \
    -X PUT "http://app:6713/products/99999999-9999-9999-9999-999999999999" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "stock_qty": 5,
      "title": "Updated title for nonexistent product"
    }'
)"

echo "HTTP status for nonexistent product update: $UPDATE_RESPONSE"
cat /tmp/update_nonexistent_product.json || true

# Then
# Assert HTTP status is 404
if [ "$UPDATE_RESPONSE" -ne 404 ]; then
  echo "Expected HTTP 404 when updating non-existent product, got $UPDATE_RESPONSE" >&2
  exit 1
fi

# Assert error message is "Product not found"
ERROR_MESSAGE="$(jq -r '.error // empty' /tmp/update_nonexistent_product.json)"
if [ "$ERROR_MESSAGE" != "Product not found" ]; then
  echo "Expected error message 'Product not found', got '$ERROR_MESSAGE'" >&2
  exit 1
fi

# Assert that no products row was created for the requested id
POST_UPDATE_COUNT="$(psql "$DATABASE_URL" -t -A -c "
  SELECT COUNT(*)
  FROM products
  WHERE id = '99999999-9999-9999-9999-999999999999';
" | tr -d '[:space:]')"
if [ "$POST_UPDATE_COUNT" != "0" ]; then
  echo "Expected no products row created for id 99999999-9999-9999-9999-999999999999, found $POST_UPDATE_COUNT" >&2
  exit 1
fi

# Teardown
# Remove seller's products
psql "$DATABASE_URL" -c "
  DELETE FROM products
  WHERE seller_id = '22222222-2222-2222-2222-222222222222';
"

# Remove seller profile
psql "$DATABASE_URL" -c "
  DELETE FROM seller_profiles
  WHERE id = '22222222-2222-2222-2222-222222222222';
"

# Remove user
psql "$DATABASE_URL" -c "
  DELETE FROM users
  WHERE id = '11111111-1111-1111-1111-111111111111';
"

# Success marker required by runner
echo "CODEVALID_TEST_ASSERTION_OK:update_stock_for_nonexistent_product"
