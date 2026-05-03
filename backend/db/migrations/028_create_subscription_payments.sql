-- 028_create_subscription_payments.sql
-- Payment records linked to subscriptions

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS subscription_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  subscription_id uuid NOT NULL REFERENCES company_subscriptions(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id) ON DELETE SET NULL,
  project_id uuid REFERENCES projects(id) ON DELETE SET NULL,
  license_id uuid REFERENCES licenses(id) ON DELETE SET NULL,
  amount numeric(12,2) NOT NULL,
  currency text NOT NULL DEFAULT 'DOP',
  status text NOT NULL DEFAULT 'pending',
  payment_method text NOT NULL DEFAULT 'manual',
  reference text,
  notes text,
  paid_at timestamptz,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  recorded_by uuid REFERENCES platform_users(id) ON DELETE SET NULL,
  gateway_payload jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_subscription_payments_status CHECK (status IN ('pending', 'paid', 'failed', 'refunded', 'cancelled')),
  CONSTRAINT ck_subscription_payments_method CHECK (payment_method IN ('manual', 'cash', 'transfer', 'card', 'paypal', 'stripe', 'other')),
  CONSTRAINT ck_subscription_payments_amount CHECK (amount >= 0)
);

CREATE INDEX IF NOT EXISTS idx_subscription_payments_company_id ON subscription_payments(company_id);
CREATE INDEX IF NOT EXISTS idx_subscription_payments_subscription_id ON subscription_payments(subscription_id);
CREATE INDEX IF NOT EXISTS idx_subscription_payments_product_id ON subscription_payments(product_id) WHERE product_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_subscription_payments_project_id ON subscription_payments(project_id) WHERE project_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_subscription_payments_status ON subscription_payments(status);
CREATE INDEX IF NOT EXISTS idx_subscription_payments_paid_at ON subscription_payments(paid_at) WHERE paid_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_subscription_payments_recorded_at ON subscription_payments(recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_subscription_payments_lookup ON subscription_payments(company_id, subscription_id, status);

COMMIT;
