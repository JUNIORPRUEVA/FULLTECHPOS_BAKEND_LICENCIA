-- 052_create_daleventas_commercial_foundation.sql
-- Appyra-owned commercial plan, CRM, snapshot, override, and audit foundation for DaleVentas.
-- This migration is metadata-only: it does not activate, block, extend, expire, or enforce DaleVentas licenses.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS daleventas_commercial_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL,
  display_name text NOT NULL,
  description text,
  monthly_equivalent_price numeric(12,2) NOT NULL,
  currency text NOT NULL DEFAULT 'DOP',
  minimum_billing_months int NOT NULL DEFAULT 3,
  minimum_payment numeric(12,2) NOT NULL,
  trial_days int NOT NULL DEFAULT 7,
  max_users int,
  max_products int,
  max_warehouses int,
  max_devices int,
  is_active boolean NOT NULL DEFAULT true,
  sort_order int NOT NULL DEFAULT 0,
  metadata jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_daleventas_commercial_plans_code UNIQUE (code),
  CONSTRAINT ck_daleventas_commercial_plan_code CHECK (code IN ('BASIC', 'BUSINESS', 'PRO')),
  CONSTRAINT ck_daleventas_commercial_plan_price CHECK (monthly_equivalent_price >= 0),
  CONSTRAINT ck_daleventas_commercial_plan_minimum_payment CHECK (minimum_payment >= 0),
  CONSTRAINT ck_daleventas_commercial_plan_minimum_months CHECK (minimum_billing_months > 0),
  CONSTRAINT ck_daleventas_commercial_plan_trial_days CHECK (trial_days >= 0),
  CONSTRAINT ck_daleventas_commercial_plan_max_users CHECK (max_users IS NULL OR max_users > 0),
  CONSTRAINT ck_daleventas_commercial_plan_max_products CHECK (max_products IS NULL OR max_products > 0),
  CONSTRAINT ck_daleventas_commercial_plan_max_warehouses CHECK (max_warehouses IS NULL OR max_warehouses > 0),
  CONSTRAINT ck_daleventas_commercial_plan_max_devices CHECK (max_devices IS NULL OR max_devices > 0)
);

CREATE TABLE IF NOT EXISTS daleventas_commercial_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  external_company_id text NOT NULL,
  external_company_name text,
  external_company_slug text,
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  project_id uuid REFERENCES projects(id) ON DELETE SET NULL,

  commercial_status text NOT NULL DEFAULT 'DEMO',
  lead_source text,
  first_contact_at timestamptz,
  last_contact_at timestamptz,
  next_follow_up_at timestamptz,
  converted_at timestamptz,
  assigned_to uuid REFERENCES platform_users(id) ON DELETE SET NULL,
  commercial_notes text,
  lost_reason text,

  plan_id uuid REFERENCES daleventas_commercial_plans(id) ON DELETE SET NULL,
  plan_classification text NOT NULL DEFAULT 'LEGACY',
  plan_code_snapshot text,
  plan_name_snapshot text,
  currency_snapshot text,
  monthly_equivalent_price_snapshot numeric(12,2),
  minimum_billing_months_snapshot int,
  minimum_payment_snapshot numeric(12,2),
  max_users_snapshot int,
  max_products_snapshot int,
  max_warehouses_snapshot int,
  max_devices_snapshot int,
  plan_assigned_at timestamptz,
  plan_assigned_by uuid REFERENCES platform_users(id) ON DELETE SET NULL,

  override_expiration_date timestamptz,
  override_extra_days int,
  override_max_users int,
  override_max_products int,
  override_max_warehouses int,
  override_max_devices int,
  override_notes text,
  override_reason text,
  override_updated_at timestamptz,
  override_updated_by uuid REFERENCES platform_users(id) ON DELETE SET NULL,

  technical_license_status text,
  technical_license_expires_at timestamptz,
  technical_trial_ends_at timestamptz,
  technical_max_users int,
  technical_max_products int,
  technical_license_key text,
  last_synced_at timestamptz,

  metadata jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_daleventas_commercial_profiles_external_company_id UNIQUE (external_company_id),
  CONSTRAINT ck_daleventas_commercial_status CHECK (commercial_status IN (
    'DEMO', 'CONTACTED', 'INTERESTED', 'PURCHASED', 'ACTIVE_CUSTOMER', 'RENEWAL_DUE', 'EXPIRED', 'LOST'
  )),
  CONSTRAINT ck_daleventas_commercial_lead_source CHECK (
    lead_source IS NULL OR lead_source IN ('WEB', 'WHATSAPP', 'FACEBOOK', 'INSTAGRAM', 'REFERIDO', 'DIRECTO', 'OTRO')
  ),
  CONSTRAINT ck_daleventas_commercial_plan_classification CHECK (
    plan_classification IN ('LEGACY', 'CUSTOM', 'CATALOG')
  ),
  CONSTRAINT ck_daleventas_commercial_plan_code_snapshot CHECK (
    plan_code_snapshot IS NULL OR plan_code_snapshot IN ('BASIC', 'BUSINESS', 'PRO', 'LEGACY', 'CUSTOM')
  ),
  CONSTRAINT ck_daleventas_commercial_snapshot_max_users CHECK (max_users_snapshot IS NULL OR max_users_snapshot > 0),
  CONSTRAINT ck_daleventas_commercial_snapshot_max_products CHECK (max_products_snapshot IS NULL OR max_products_snapshot > 0),
  CONSTRAINT ck_daleventas_commercial_snapshot_max_warehouses CHECK (max_warehouses_snapshot IS NULL OR max_warehouses_snapshot > 0),
  CONSTRAINT ck_daleventas_commercial_snapshot_max_devices CHECK (max_devices_snapshot IS NULL OR max_devices_snapshot > 0),
  CONSTRAINT ck_daleventas_commercial_override_extra_days CHECK (override_extra_days IS NULL OR override_extra_days >= 0),
  CONSTRAINT ck_daleventas_commercial_override_max_users CHECK (override_max_users IS NULL OR override_max_users > 0),
  CONSTRAINT ck_daleventas_commercial_override_max_products CHECK (override_max_products IS NULL OR override_max_products > 0),
  CONSTRAINT ck_daleventas_commercial_override_max_warehouses CHECK (override_max_warehouses IS NULL OR override_max_warehouses > 0),
  CONSTRAINT ck_daleventas_commercial_override_max_devices CHECK (override_max_devices IS NULL OR override_max_devices > 0),
  CONSTRAINT ck_daleventas_commercial_technical_max_users CHECK (technical_max_users IS NULL OR technical_max_users > 0),
  CONSTRAINT ck_daleventas_commercial_technical_max_products CHECK (technical_max_products IS NULL OR technical_max_products > 0)
);

CREATE TABLE IF NOT EXISTS daleventas_commercial_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id uuid REFERENCES daleventas_commercial_profiles(id) ON DELETE CASCADE,
  external_company_id text NOT NULL,
  actor_user_id uuid REFERENCES platform_users(id) ON DELETE SET NULL,
  actor_type text NOT NULL DEFAULT 'admin_session',
  actor_label text,
  action text NOT NULL,
  before_data jsonb NOT NULL DEFAULT '{}',
  after_data jsonb NOT NULL DEFAULT '{}',
  reason text,
  ip_address text,
  user_agent text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_daleventas_commercial_audit_actor_type CHECK (actor_type IN ('platform_user', 'system', 'admin_session')),
  CONSTRAINT ck_daleventas_commercial_audit_action CHECK (action IN (
    'PLAN_ASSIGNED', 'PLAN_CHANGED', 'LIMIT_OVERRIDE_CHANGED', 'COMMERCIAL_STATUS_CHANGED',
    'FOLLOW_UP_CHANGED', 'CRM_PROFILE_UPDATED'
  ))
);

CREATE INDEX IF NOT EXISTS idx_daleventas_commercial_plans_active_sort
  ON daleventas_commercial_plans(is_active, sort_order, code);

CREATE INDEX IF NOT EXISTS idx_daleventas_commercial_profiles_customer_id
  ON daleventas_commercial_profiles(customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_daleventas_commercial_profiles_project_id
  ON daleventas_commercial_profiles(project_id) WHERE project_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_daleventas_commercial_profiles_status
  ON daleventas_commercial_profiles(commercial_status);
CREATE INDEX IF NOT EXISTS idx_daleventas_commercial_profiles_lead_source
  ON daleventas_commercial_profiles(lead_source) WHERE lead_source IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_daleventas_commercial_profiles_plan_snapshot
  ON daleventas_commercial_profiles(plan_code_snapshot, plan_classification);
CREATE INDEX IF NOT EXISTS idx_daleventas_commercial_profiles_follow_up
  ON daleventas_commercial_profiles(next_follow_up_at) WHERE next_follow_up_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_daleventas_commercial_profiles_converted_at
  ON daleventas_commercial_profiles(converted_at) WHERE converted_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_daleventas_commercial_profiles_assigned_to
  ON daleventas_commercial_profiles(assigned_to) WHERE assigned_to IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_daleventas_commercial_profiles_technical_status
  ON daleventas_commercial_profiles(technical_license_status);
CREATE INDEX IF NOT EXISTS idx_daleventas_commercial_profiles_technical_expires
  ON daleventas_commercial_profiles(technical_license_expires_at) WHERE technical_license_expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_daleventas_commercial_profiles_filter_ready
  ON daleventas_commercial_profiles(commercial_status, next_follow_up_at, technical_license_status, technical_license_expires_at);

CREATE INDEX IF NOT EXISTS idx_daleventas_commercial_audit_profile_created
  ON daleventas_commercial_audit_logs(profile_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_daleventas_commercial_audit_external_created
  ON daleventas_commercial_audit_logs(external_company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_daleventas_commercial_audit_action_created
  ON daleventas_commercial_audit_logs(action, created_at DESC);

CREATE OR REPLACE FUNCTION touch_daleventas_commercial_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_daleventas_commercial_plans_updated_at ON daleventas_commercial_plans;
CREATE TRIGGER trg_daleventas_commercial_plans_updated_at
BEFORE UPDATE ON daleventas_commercial_plans
FOR EACH ROW EXECUTE FUNCTION touch_daleventas_commercial_updated_at();

DROP TRIGGER IF EXISTS trg_daleventas_commercial_profiles_updated_at ON daleventas_commercial_profiles;
CREATE TRIGGER trg_daleventas_commercial_profiles_updated_at
BEFORE UPDATE ON daleventas_commercial_profiles
FOR EACH ROW EXECUTE FUNCTION touch_daleventas_commercial_updated_at();

INSERT INTO daleventas_commercial_plans (
  code, display_name, description, monthly_equivalent_price, currency,
  minimum_billing_months, minimum_payment, trial_days, sort_order, metadata
) VALUES
  ('BASIC', 'Básico', 'FullPOS Cloud public commercial plan. Entitlement limits are configurable and intentionally unseeded.', 1000.00, 'DOP', 3, 3000.00, 7, 10, '{"source":"https://fullposcloud.fulltechrd.com","verified_at":"2026-09-06","public_limits_published":false}'::jsonb),
  ('BUSINESS', 'Negocio', 'FullPOS Cloud public commercial plan. Entitlement limits are configurable and intentionally unseeded.', 1500.00, 'DOP', 3, 4500.00, 7, 20, '{"source":"https://fullposcloud.fulltechrd.com","verified_at":"2026-09-06","public_limits_published":false}'::jsonb),
  ('PRO', 'Pro', 'FullPOS Cloud public commercial plan. Entitlement limits are configurable and intentionally unseeded.', 2500.00, 'DOP', 3, 7500.00, 7, 30, '{"source":"https://fullposcloud.fulltechrd.com","verified_at":"2026-09-06","public_limits_published":false}'::jsonb)
ON CONFLICT (code) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  description = EXCLUDED.description,
  monthly_equivalent_price = EXCLUDED.monthly_equivalent_price,
  currency = EXCLUDED.currency,
  minimum_billing_months = EXCLUDED.minimum_billing_months,
  minimum_payment = EXCLUDED.minimum_payment,
  trial_days = EXCLUDED.trial_days,
  sort_order = EXCLUDED.sort_order,
  metadata = daleventas_commercial_plans.metadata || EXCLUDED.metadata,
  updated_at = now();

COMMIT;
