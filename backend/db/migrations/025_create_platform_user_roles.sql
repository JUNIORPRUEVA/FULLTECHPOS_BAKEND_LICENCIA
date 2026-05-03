-- 025_create_platform_user_roles.sql
-- Many-to-many relationship between platform users and roles

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS platform_user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES platform_users(id) ON DELETE CASCADE,
  role_id uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_platform_user_roles_global
  ON platform_user_roles(user_id, role_id)
  WHERE company_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_platform_user_roles_company
  ON platform_user_roles(user_id, role_id, company_id)
  WHERE company_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_platform_user_roles_user_id ON platform_user_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_platform_user_roles_role_id ON platform_user_roles(role_id);
CREATE INDEX IF NOT EXISTS idx_platform_user_roles_company_id ON platform_user_roles(company_id);
CREATE INDEX IF NOT EXISTS idx_platform_user_roles_user_role ON platform_user_roles(user_id, role_id);

COMMIT;
