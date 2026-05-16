-- 037_relax_paypal_orders_for_direct_checkout.sql
-- Allow direct PayPal checkout orders created from amount + description.

BEGIN;

ALTER TABLE paypal_orders
  ALTER COLUMN company_id DROP NOT NULL,
  ALTER COLUMN plan_id DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS description text;

CREATE INDEX IF NOT EXISTS idx_paypal_orders_paypal_order_id
  ON paypal_orders(paypal_order_id)
  WHERE paypal_order_id IS NOT NULL;

COMMIT;
