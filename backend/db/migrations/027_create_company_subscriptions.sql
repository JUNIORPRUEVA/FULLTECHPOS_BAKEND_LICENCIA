-- 027_create_company_subscriptions.sql
-- Subscriptions linking companies to product plans

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS company_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id) ON DELETE SET NULL,
  project_id uuid REFERENCES projects(id) ON DELETE SET NULL,
  plan_id uuid NOT NULL REFERENCES product_plans(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'trial',
  start_date timestamptz NOT NULL,
  end_date timestamptz,
  renewal_date timestamptz,
  grace_until timestamptz,
  cancelled_at timestamptz,
  suspended_at timestamptz,
  notes text,
  metadata jsonb NOT NULL DEFAULT '{}',
  created_by uuid REFERENCES platform_users(id) ON DELETE SET NULL,
  updated_by uuid REFERENCES platform_users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_company_subscriptions_status CHECK (status IN ('trial', 'active', 'past_due', 'suspended', 'cancelled', 'expired', 'lifetime')),
  CONSTRAINT ck_company_subscriptions_dates CHECK (start_date <= COALESCE(end_date, start_date + INTERVAL '100 years'))
);

CREATE INDEX IF NOT EXISTS idx_company_subscriptions_company_id ON company_subscriptions(company_id);
CREATE INDEX IF NOT EXISTS idx_company_subscriptions_product_id ON company_subscriptions(product_id) WHERE product_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_company_subscriptions_project_id ON company_subscriptions(project_id) WHERE project_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_company_subscriptions_plan_id ON company_subscriptions(plan_id);
CREATE INDEX IF NOT EXISTS idx_company_subscriptions_status ON company_subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_company_subscriptions_renewal_date ON company_subscriptions(renewal_date) WHERE renewal_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_company_subscriptions_end_date ON company_subscriptions(end_date) WHERE end_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_company_subscriptions_active ON company_subscriptions(company_id, status) WHERE status IN ('trial', 'active', 'lifetime');

COMMIT;
