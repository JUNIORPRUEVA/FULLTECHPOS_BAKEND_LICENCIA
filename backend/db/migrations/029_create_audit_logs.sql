-- 029_create_audit_logs.sql
-- Platform-wide audit trail for compliance and debugging

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id uuid REFERENCES platform_users(id) ON DELETE SET NULL,
  actor_type text NOT NULL,
  company_id uuid REFERENCES companies(id) ON DELETE SET NULL,
  product_id uuid REFERENCES products(id) ON DELETE SET NULL,
  project_id uuid REFERENCES projects(id) ON DELETE SET NULL,
  target_type text NOT NULL,
  target_id text NOT NULL,
  action text NOT NULL,
  before_data jsonb NOT NULL DEFAULT '{}',
  after_data jsonb NOT NULL DEFAULT '{}',
  ip_address text,
  user_agent text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_audit_logs_actor_type CHECK (actor_type IN ('platform_user', 'system', 'admin_session', 'client')),
  CONSTRAINT ck_audit_logs_target_type CHECK (target_type IN (
    'license', 'customer', 'company', 'subscription', 'payment', 'product', 'plan',
    'user', 'role', 'permission', 'config', 'other'
  ))
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_actor_user_id ON audit_logs(actor_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor_type ON audit_logs(actor_type);
CREATE INDEX IF NOT EXISTS idx_audit_logs_company_id ON audit_logs(company_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_product_id ON audit_logs(product_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_project_id ON audit_logs(project_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_target_type_id ON audit_logs(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_lookup ON audit_logs(company_id, created_at DESC, action);

COMMIT;
