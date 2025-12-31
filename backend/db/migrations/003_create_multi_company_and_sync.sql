-- 003_create_multi_company_and_sync.sql
-- Multi-empresa + base para sincronización (NO toca el módulo de licencias existente)

-- UUID generator
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =====================================
-- Companies (empresas)
-- =====================================
CREATE TABLE IF NOT EXISTS companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  legal_name text,
  tax_id text,
  phone text,
  address text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- =====================================
-- Branches (sucursales)
-- =====================================
CREATE TABLE IF NOT EXISTS branches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name text NOT NULL,
  address text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_branches_company_id ON branches(company_id);

-- =====================================
-- POS Users (usuarios del POS en la nube)
-- =====================================
CREATE TABLE IF NOT EXISTS pos_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  username text NOT NULL,
  display_name text,
  role text NOT NULL DEFAULT 'admin',
  is_active boolean NOT NULL DEFAULT true,
  password_hash text,
  permissions jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, username)
);
CREATE INDEX IF NOT EXISTS idx_pos_users_company_id ON pos_users(company_id);

-- =====================================
-- Company <-> License relationship
-- =====================================
CREATE TABLE IF NOT EXISTS company_licenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  license_id uuid NOT NULL REFERENCES licenses(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, license_id),
  UNIQUE (license_id)
);
CREATE INDEX IF NOT EXISTS idx_company_licenses_company_id ON company_licenses(company_id);
CREATE INDEX IF NOT EXISTS idx_company_licenses_license_id ON company_licenses(license_id);

-- =====================================
-- Sync logs
-- =====================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sync_direction') THEN
    CREATE TYPE sync_direction AS ENUM ('PUSH', 'PULL');
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS sync_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  license_id uuid NOT NULL REFERENCES licenses(id) ON DELETE CASCADE,
  device_id text NOT NULL,
  direction sync_direction NOT NULL,
  last_sync_at timestamptz,
  summary jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sync_logs_company_created ON sync_logs(company_id, created_at DESC);
