#!/usr/bin/env bash
set -euo pipefail

# Case: prevent_unauthorized_inventory_creation_as_non_seller

# --- Setup ---
source tests/task_3134097798_20260910032107/api/_infra.sh

# Ensure DATABASE_URL and PORT are available from infra
echo "DATABASE_URL=${DATABASE_URL}"
echo "PORT=${PORT}"

# Apply Prisma migrations to create tables (users, seller_profiles, products, etc.)
cd "${WORKDIR:-.}"
npx prisma migrate deploy

# Optional: verify Product and SellerProfile models in schema
# Runner will execute read_repo_file prisma/schema.prisma per plan.

# --- Preconditions ---
# 1. Seed a non-seller user with a role literal that exists in the schema and is not "SELLER".
#    Example assumes roles include BUYER and statuses include ACTIVE.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, role, status, email, password_hash)
VALUES (
  gen_random_uuid(),
  'BUYER',
  'ACTIVE',
  'buyer@example.com',
  'dummyhash'
);
" || {
  echo "Failed to insert non-seller user" >&2
  exit 1
}

# 2. Confirm there is no seller_profiles row for this user_id (non-seller).
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
SELECT * FROM seller_profiles WHERE user_id IN (
  SELECT id FROM users WHERE email = 'buyer@example.com'
);
" || {
  echo "Failed to query seller_profiles" >&2
  exit 1
}

# 3. Ensure products table is empty or at least has no products yet (for easier assertions).
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products;" || {
  echo "Failed to clear products table" >&2
  exit 1
}

# 4. Start app (infra entrypoint should already do this) and wait for health.
#    Replace /health with the actual health endpoint path if different.
curl -sS "http://app:${PORT}/health" | jq . || {
  echo "Health check failed" >&2
  exit 1
}

# --- When ---
# 1. Obtain auth for the non-seller user.
#    Auth discovery is delegated to the runner via read_repo_file instructions in the plan.
#    If TOKEN is not set by external helpers, we fall back to a dummy token, which should
#    still trigger seller-only enforcement.
TOKEN="${TOKEN:-dummy_non_seller_token}"

# 2. Send POST /products as the authenticated non-seller user.
PRODUCT_REQ_BODY=$(jq -n '{
  title: "Non-seller attempt product",
  description: "Should not be created because user is not a seller.",
  category: "general",
  price_cents: 1999,
  stock_qty: 5,
  photos: []
}')

HTTP_RESPONSE=$(curl -sS -o /tmp/post_products_resp.json -w "%{http_code}" \
  -X POST "http://app:${PORT}/products" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d "$PRODUCT_REQ_BODY")

echo "HTTP_STATUS=${HTTP_RESPONSE}"
cat /tmp/post_products_resp.json | jq . || true

# --- Then ---
# 1. Assert HTTP status is 403.
if [ "$HTTP_RESPONSE" -ne 403 ]; then
  echo "Expected HTTP 403, got ${HTTP_RESPONSE}" >&2
  exit 1
fi

# 2. Assert error message is exactly "Seller access required".
ERROR_MSG=$(jq -r '.error' /tmp/post_products_resp.json)
if [ "$ERROR_MSG" != "Seller access required" ]; then
  echo "Expected error message 'Seller access required', got '${ERROR_MSG}'" >&2
  exit 1
fi

# 3. Assert no product row was created as a result of this request.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
SELECT COUNT(*) AS product_count FROM products;
" > /tmp/products_count.txt || {
  echo "Failed to count products" >&2
  exit 1
}

cat /tmp/products_count.txt
PRODUCT_COUNT=$(grep -Eo '[0-9]+' /tmp/products_count.txt | tail -n 1)
if [ "$PRODUCT_COUNT" -ne 0 ]; then
  echo "Expected 0 products, found ${PRODUCT_COUNT}" >&2
  exit 1
fi

# --- Teardown ---
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
DELETE FROM products;
DELETE FROM seller_profiles WHERE user_id IN (
  SELECT id FROM users WHERE email = 'buyer@example.com'
);
DELETE FROM users WHERE email = 'buyer@example.com';
" || {
  echo "Teardown cleanup failed" >&2
  exit 1
}

echo "Teardown for prevent_unauthorized_inventory_creation_as_non_seller completed."

echo "CODEVALID_TEST_ASSERTION_OK:prevent_unauthorized_inventory_creation_as_non_seller"
