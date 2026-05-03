-- 023_create_roles.sql
-- Platform and company-level roles

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL,
  name text NOT NULL,
  description text,
  scope_type text NOT NULL DEFAULT 'platform',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_roles_scope_type CHECK (scope_type IN ('platform', 'company')),
  CONSTRAINT uq_roles_code UNIQUE (code)
);

CREATE INDEX IF NOT EXISTS idx_roles_code ON roles(code);
CREATE INDEX IF NOT EXISTS idx_roles_scope_type ON roles(scope_type);

COMMIT;
