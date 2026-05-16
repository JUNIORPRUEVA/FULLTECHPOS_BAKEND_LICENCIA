-- 035_add_paypal_saas_integration.sql
-- PayPal gateway fields, order tracking, and idempotent webhook processing.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE product_plans
  ADD COLUMN IF NOT EXISTS paypal_product_id text,
  ADD COLUMN IF NOT EXISTS paypal_plan_id text;

ALTER TABLE company_subscriptions
  ADD COLUMN IF NOT EXISTS paypal_subscription_id text;

ALTER TABLE subscription_payments
  ADD COLUMN IF NOT EXISTS paypal_order_id text,
  ADD COLUMN IF NOT EXISTS paypal_capture_id text,
  ADD COLUMN IF NOT EXISTS paypal_subscription_id text;

CREATE TABLE IF NOT EXISTS paypal_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  paypal_order_id text UNIQUE,
  order_type text NOT NULL,
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  plan_id uuid NOT NULL REFERENCES product_plans(id) ON DELETE RESTRICT,
  product_id uuid REFERENCES products(id) ON DELETE SET NULL,
  project_id uuid REFERENCES projects(id) ON DELETE SET NULL,
  license_id uuid REFERENCES licenses(id) ON DELETE SET NULL,
  subscription_id uuid REFERENCES company_subscriptions(id) ON DELETE SET NULL,
  amount numeric(12,2) NOT NULL,
  currency text NOT NULL DEFAULT 'USD',
  status text NOT NULL DEFAULT 'CREATED',
  approval_url text,
  request_payload jsonb NOT NULL DEFAULT '{}',
  paypal_payload jsonb NOT NULL DEFAULT '{}',
  captured_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_paypal_orders_type CHECK (order_type IN ('ONE_TIME')),
  CONSTRAINT ck_paypal_orders_amount CHECK (amount >= 0)
);

CREATE TABLE IF NOT EXISTS paypal_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  paypal_event_id text NOT NULL UNIQUE,
  event_type text NOT NULL,
  resource_id text,
  status text NOT NULL DEFAULT 'processed',
  payload jsonb NOT NULL DEFAULT '{}',
  error_message text,
  processed_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_product_plans_paypal_plan_id
  ON product_plans(paypal_plan_id)
  WHERE paypal_plan_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_company_subscriptions_paypal_subscription_id
  ON company_subscriptions(paypal_subscription_id)
  WHERE paypal_subscription_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_subscription_payments_paypal_order_id
  ON subscription_payments(paypal_order_id)
  WHERE paypal_order_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_subscription_payments_paypal_capture_id
  ON subscription_payments(paypal_capture_id)
  WHERE paypal_capture_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_subscription_payments_paypal_subscription_id
  ON subscription_payments(paypal_subscription_id)
  WHERE paypal_subscription_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_paypal_orders_company_id ON paypal_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_paypal_orders_status ON paypal_orders(status);
CREATE INDEX IF NOT EXISTS idx_paypal_orders_plan_id ON paypal_orders(plan_id);
CREATE INDEX IF NOT EXISTS idx_paypal_webhook_events_type ON paypal_webhook_events(event_type);
CREATE INDEX IF NOT EXISTS idx_paypal_webhook_events_resource_id ON paypal_webhook_events(resource_id);

COMMIT;
