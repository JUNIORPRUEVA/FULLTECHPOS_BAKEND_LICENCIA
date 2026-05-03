-- 022_create_platform_users.sql
-- Platform IAM: users for admins, support, and internal staff

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS platform_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL,
  password_hash text,
  display_name text,
  phone text,
  status text NOT NULL DEFAULT 'active',
  user_type text NOT NULL DEFAULT 'admin',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  last_login_at timestamptz,
  CONSTRAINT ck_platform_users_status CHECK (status IN ('active', 'inactive', 'suspended')),
  CONSTRAINT ck_platform_users_type CHECK (user_type IN ('owner', 'admin', 'support', 'client_owner', 'client_user')),
  CONSTRAINT uq_platform_users_email UNIQUE (email)
);

CREATE INDEX IF NOT EXISTS idx_platform_users_email ON platform_users(email);
CREATE INDEX IF NOT EXISTS idx_platform_users_status ON platform_users(status);
CREATE INDEX IF NOT EXISTS idx_platform_users_user_type ON platform_users(user_type);
CREATE INDEX IF NOT EXISTS idx_platform_users_created_at ON platform_users(created_at DESC);

COMMIT;
