-- 005_add_company_code_and_user_email.sql
-- Adds company login code + email login for pos_users (keeps existing schema compatible)

BEGIN;

-- Company code used for login (human-friendly)
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS code text;

-- Unique company code (case-insensitive handled at app level by uppercasing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'idx_companies_code_unique'
  ) THEN
    CREATE UNIQUE INDEX idx_companies_code_unique ON companies (code);
  END IF;
END$$;

-- Email login for POS users
ALTER TABLE pos_users
  ADD COLUMN IF NOT EXISTS email text;

-- Backfill email from username for existing rows
UPDATE pos_users
SET email = username
WHERE email IS NULL;

-- Unique (company_id, email)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'idx_pos_users_company_email_unique'
  ) THEN
    CREATE UNIQUE INDEX idx_pos_users_company_email_unique ON pos_users (company_id, email);
  END IF;
END$$;

-- Optional seed (safe / idempotent) for initial testing.
-- Password: admin123
-- bcrypt hash (cost 10): $2a$10$6bgt6EwHRvTbcnAQRv4LheIfTGEwEt0FvLGI70w8CV08a7Mujxku2
INSERT INTO companies (name, code, is_active)
SELECT 'Empresa Demo', 'DEMO', true
WHERE NOT EXISTS (SELECT 1 FROM companies WHERE code = 'DEMO');

INSERT INTO pos_users (company_id, username, email, display_name, role, is_active, password_hash, permissions)
SELECT c.id, 'admin@demo.com', 'admin@demo.com', 'Administrador', 'admin', true,
       '$2a$10$6bgt6EwHRvTbcnAQRv4LheIfTGEwEt0FvLGI70w8CV08a7Mujxku2',
       NULL
FROM companies c
WHERE c.code = 'DEMO'
  AND NOT EXISTS (
    SELECT 1
    FROM pos_users u
    WHERE u.company_id = c.id AND u.email = 'admin@demo.com'
  );

-- If the user already exists but password_hash is NULL, backfill it.
UPDATE pos_users u
SET password_hash = '$2a$10$6bgt6EwHRvTbcnAQRv4LheIfTGEwEt0FvLGI70w8CV08a7Mujxku2'
FROM companies c
WHERE c.id = u.company_id
  AND c.code = 'DEMO'
  AND u.email = 'admin@demo.com'
  AND (u.password_hash IS NULL OR u.password_hash = '');

COMMIT;
