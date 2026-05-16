-- 038_add_user_to_paypal_orders.sql
-- Link direct PayPal checkout orders to platform users for automatic activation.

BEGIN;

ALTER TABLE paypal_orders
  ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES platform_users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_paypal_orders_user_id ON paypal_orders(user_id) WHERE user_id IS NOT NULL;

COMMIT;
