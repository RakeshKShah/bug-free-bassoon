#!/usr/bin/env bash
set -euo pipefail

# Case: authenticated_buyer_views_product_with_reviews

# Setup
source tests/task_6954783313_20260910032107/api/_infra.sh

# Database schema is already applied by the app container entrypoint via MIGRATE_CMD=npx prisma migrate deploy

# Seed users: buyer and seller (with explicit IDs and enums)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('buyer-1', 'bu@example.com', 'hash-buyer', 'BUYER', 'ACTIVE', NOW()),
  ('seller-user-1', 'se@example.com', 'hash-seller', 'SELLER', 'ACTIVE', NOW());
"

# Seed seller profile linked to seller user
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES
  ('seller-profile-1', 'seller-user-1', 'Test Store', 'Seller bio');
"

# Seed ACTIVE, visible product for seller; photos as empty JSON array
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('product-1', 'seller-profile-1', 'Test Product', 'Great product', 'CategoryA', 1000, 10, '[]'::json, 'ACTIVE', TRUE, NOW());
"

# Seed orders for buyer (DELIVERED) and another buyer to simulate multiple reviewers
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('buyer-2', 'ot@example.com', 'hash-buyer2', 'BUYER', 'ACTIVE', NOW());
INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents, created_at)
VALUES
  ('order-1', 'buyer-1', 'DELIVERED', 1000, 100, NOW()),
  ('order-2', 'buyer-2', 'DELIVERED', 1000, 100, NOW());
"

# Seed payouts required by order_items FK (payout_id -> payouts.id)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO payouts (id, seller_id, amount_cents, period_start, period_end, status)
VALUES
  ('payout-1', 'seller-profile-1', 900, NOW() - INTERVAL '7 days', NOW(), 'PENDING'),
  ('payout-2', 'seller-profile-1', 900, NOW() - INTERVAL '7 days', NOW(), 'PENDING');
"

# Seed order_items for both orders pointing to product-1
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO order_items (id, order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents, payout_id)
VALUES
  ('order-item-1', 'order-1', 'product-1', 'seller-profile-1', 1, 1000, 900, 'payout-1'),
  ('order-item-2', 'order-2', 'product-1', 'seller-profile-1', 1, 1000, 900, 'payout-2');
"

# Seed reviews linked to product-1 and corresponding order_items and buyers
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO reviews (id, order_item_id, product_id, buyer_id, rating, body, created_at)
VALUES
  ('review-1', 'order-item-1', 'product-1', 'buyer-1', 5, 'Amazing product!', NOW()),
  ('review-2', 'order-item-2', 'product-1', 'buyer-2', 4, 'Good quality.', NOW());
"

# Obtain JWT for buyer-1 using password auth flow
# (Use existing auth route from the repo; implementation is in src/routes/auth.ts and src/middleware/auth.ts)
BUYER_TOKEN="$(
  curl -sS -X POST "http://app:6713/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"bu@example.com","password":"password-placeholder"}' | jq -r '.token'
)"

# Preconditions
# Verify product exists and is ACTIVE & visible
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
SELECT id, status, visible FROM products WHERE id = 'product-1';
"

# Verify reviews exist for product-1
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
SELECT id, product_id, buyer_id, rating, body FROM reviews WHERE product_id = 'product-1';
"

# Confirm BUYER_TOKEN is non-empty
if [ -z "$BUYER_TOKEN" ] || [ "$BUYER_TOKEN" = "null" ]; then
  echo "Buyer token is missing; auth login may have failed."
  # Teardown before exit to avoid contamination
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
DELETE FROM reviews WHERE product_id = 'product-1';
DELETE FROM order_items WHERE product_id = 'product-1';
DELETE FROM payouts WHERE id IN ('payout-1', 'payout-2');
DELETE FROM orders WHERE id IN ('order-1', 'order-2');
DELETE FROM products WHERE id = 'product-1';
DELETE FROM seller_profiles WHERE id = 'seller-profile-1';
DELETE FROM users WHERE id IN ('buyer-1', 'buyer-2', 'seller-user-1');
"
  exit 1
fi

# When
# Authenticated buyer requests product detail with reviews
PRODUCT_RESPONSE="$(
  curl -sS -X GET "http://app:6713/products/product-1" \
    -H "Authorization: Bearer $BUYER_TOKEN" \
    -H "Accept: application/json"
)"
echo "$PRODUCT_RESPONSE" | jq '.'

# Then
# Assert HTTP 200 by checking no error field and presence of id
echo "$PRODUCT_RESPONSE" | jq -e '.id' > /dev/null

# Check core product fields exist
echo "$PRODUCT_RESPONSE" | jq -e '.seller_id' > /dev/null
echo "$PRODUCT_RESPONSE" | jq -e '.title' > /dev/null
echo "$PRODUCT_RESPONSE" | jq -e '.description' > /dev/null
echo "$PRODUCT_RESPONSE" | jq -e '.category' > /dev/null
echo "$PRODUCT_RESPONSE" | jq -e '.price_cents' > /dev/null
echo "$PRODUCT_RESPONSE" | jq -e '.stock_qty' > /dev/null
echo "$PRODUCT_RESPONSE" | jq -e '.photos' > /dev/null
echo "$PRODUCT_RESPONSE" | jq -e '.status' > /dev/null
echo "$PRODUCT_RESPONSE" | jq -e '.visible' > /dev/null
echo "$PRODUCT_RESPONSE" | jq -e '.created_at' > /dev/null
echo "$PRODUCT_RESPONSE" | jq -e '.seller' > /dev/null

# Assert reviews array exists and has at least two entries
echo "$PRODUCT_RESPONSE" | jq -e '.reviews' > /dev/null
REVIEWS_COUNT="$(echo "$PRODUCT_RESPONSE" | jq '.reviews | length')"
if [ "$REVIEWS_COUNT" -lt 2 ]; then
  echo "Expected at least 2 reviews for product-1, got $REVIEWS_COUNT"
  # Teardown before exit
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
DELETE FROM reviews WHERE product_id = 'product-1';
DELETE FROM order_items WHERE product_id = 'product-1';
DELETE FROM payouts WHERE id IN ('payout-1', 'payout-2');
DELETE FROM orders WHERE id IN ('order-1', 'order-2');
DELETE FROM products WHERE id = 'product-1';
DELETE FROM seller_profiles WHERE id = 'seller-profile-1';
DELETE FROM users WHERE id IN ('buyer-1', 'buyer-2', 'seller-user-1');
"
  exit 1
fi

# Verify each review has required fields: id, rating, body, created_at, buyer_email
echo "$PRODUCT_RESPONSE" | jq -e '.reviews[] | .id' > /dev/null
echo "$PRODUCT_RESPONSE" | jq -e '.reviews[] | .rating' > /dev/null
echo "$PRODUCT_RESPONSE" | jq -e '.reviews[] | .body' > /dev/null
echo "$PRODUCT_RESPONSE" | jq -e '.reviews[] | .created_at' > /dev/null
echo "$PRODUCT_RESPONSE" | jq -e '.reviews[] | .buyer_email' > /dev/null

# Verify that masked buyer_email values correspond to seed emails pattern (2 chars then ***)
BUYER_EMAIL_MASK="$(echo "$PRODUCT_RESPONSE" | jq -r '.reviews[] | select(.rating == 5) | .buyer_email' | head -n1)"
OTHER_EMAIL_MASK="$(echo "$PRODUCT_RESPONSE" | jq -r '.reviews[] | select(.rating == 4) | .buyer_email' | head -n1)"

case "$BUYER_EMAIL_MASK" in
  bu***@*) ;;
  *)
    echo "Buyer email mask not in expected format for buyer-1: $BUYER_EMAIL_MASK"
    # Teardown before exit
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
DELETE FROM reviews WHERE product_id = 'product-1';
DELETE FROM order_items WHERE product_id = 'product-1';
DELETE FROM payouts WHERE id IN ('payout-1', 'payout-2');
DELETE FROM orders WHERE id IN ('order-1', 'order-2');
DELETE FROM products WHERE id = 'product-1';
DELETE FROM seller_profiles WHERE id = 'seller-profile-1';
DELETE FROM users WHERE id IN ('buyer-1', 'buyer-2', 'seller-user-1');
"
    exit 1
    ;;
esac

case "$OTHER_EMAIL_MASK" in
  ot***@*) ;;
  *)
    echo "Buyer email mask not in expected format for buyer-2: $OTHER_EMAIL_MASK"
    # Teardown before exit
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
DELETE FROM reviews WHERE product_id = 'product-1';
DELETE FROM order_items WHERE product_id = 'product-1';
DELETE FROM payouts WHERE id IN ('payout-1', 'payout-2');
DELETE FROM orders WHERE id IN ('order-1', 'order-2');
DELETE FROM products WHERE id = 'product-1';
DELETE FROM seller_profiles WHERE id = 'seller-profile-1';
DELETE FROM users WHERE id IN ('buyer-1', 'buyer-2', 'seller-user-1');
"
    exit 1
    ;;
esac

# Confirm review bodies match seed content for product-1
echo "$PRODUCT_RESPONSE" | jq -e '.reviews[] | select(.body == "Amazing product!")' > /dev/null
echo "$PRODUCT_RESPONSE" | jq -e '.reviews[] | select(.body == "Good quality.")' > /dev/null

# Teardown
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
DELETE FROM reviews WHERE product_id = 'product-1';
DELETE FROM order_items WHERE product_id = 'product-1';
DELETE FROM payouts WHERE id IN ('payout-1', 'payout-2');
DELETE FROM orders WHERE id IN ('order-1', 'order-2');
DELETE FROM products WHERE id = 'product-1';
DELETE FROM seller_profiles WHERE id = 'seller-profile-1';
DELETE FROM users WHERE id IN ('buyer-1', 'buyer-2', 'seller-user-1');
"

# Success marker required by runner
echo "CODEVALID_TEST_ASSERTION_OK:authenticated_buyer_views_product_with_reviews"
