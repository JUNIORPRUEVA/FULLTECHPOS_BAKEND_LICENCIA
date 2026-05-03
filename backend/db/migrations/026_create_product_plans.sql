-- 026_create_product_plans.sql
-- Pricing plans for products/projects (bridge between catalog and licensing)

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS product_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  project_id uuid REFERENCES projects(id) ON DELETE CASCADE,
  code text NOT NULL,
  name text NOT NULL,
  billing_period text NOT NULL,
  price_amount numeric(12,2) NOT NULL,
  currency text NOT NULL DEFAULT 'DOP',
  device_limit int NOT NULL DEFAULT 1,
  company_limit int NOT NULL DEFAULT 1,
  default_grace_days int NOT NULL DEFAULT 0,
  trial_days int,
  is_active boolean NOT NULL DEFAULT true,
  metadata jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_product_plans_owner CHECK (
    (product_id IS NOT NULL AND project_id IS NULL)
    OR (product_id IS NULL AND project_id IS NOT NULL)
  ),
  CONSTRAINT ck_product_plans_billing_period CHECK (billing_period IN ('trial', 'monthly', 'annual', 'lifetime')),
  CONSTRAINT ck_product_plans_device_limit CHECK (device_limit > 0),
  CONSTRAINT ck_product_plans_company_limit CHECK (company_limit > 0),
  CONSTRAINT ck_product_plans_price CHECK (price_amount >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_product_plans_product_code
  ON product_plans(product_id, code)
  WHERE product_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_product_plans_project_code
  ON product_plans(project_id, code)
  WHERE project_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_product_plans_product_id ON product_plans(product_id) WHERE product_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_product_plans_project_id ON product_plans(project_id) WHERE project_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_product_plans_code ON product_plans(code);
CREATE INDEX IF NOT EXISTS idx_product_plans_billing_period ON product_plans(billing_period);
CREATE INDEX IF NOT EXISTS idx_product_plans_is_active ON product_plans(is_active);

COMMIT;
