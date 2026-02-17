-- 018_create_password_reset_and_evolution_config.sql
-- Configuración Evolution API + OTP para reseteo de contraseña local FULLPOS

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS evolution_config (
  id uuid PRIMARY KEY DEFAULT '00000000-0000-0000-0000-000000000001'::uuid,
  enabled boolean NOT NULL DEFAULT true,
  base_url text,
  instance_name text,
  api_key text,
  from_number text,
  otp_ttl_minutes integer NOT NULL DEFAULT 10,
  send_timeout_ms integer NOT NULL DEFAULT 12000,
  template_text text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO evolution_config (
  id,
  enabled,
  base_url,
  instance_name,
  api_key,
  from_number,
  otp_ttl_minutes,
  send_timeout_ms,
  template_text,
  created_at,
  updated_at
)
VALUES (
  '00000000-0000-0000-0000-000000000001'::uuid,
  true,
  NULL,
  NULL,
  NULL,
  NULL,
  10,
  12000,
  'FULLPOS: Tu código para restablecer contraseña es {code}. Vence en {ttl_minutes} minutos.',
  now(),
  now()
)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS password_reset_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id text NOT NULL,
  username text NOT NULL,
  phone text NOT NULL,
  code_hash text NOT NULL,
  code_expires_at timestamptz NOT NULL,
  attempts integer NOT NULL DEFAULT 0,
  max_attempts integer NOT NULL DEFAULT 5,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_password_reset_pending
  ON password_reset_requests (business_id, username, created_at DESC)
  WHERE consumed_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_password_reset_expiration
  ON password_reset_requests (code_expires_at);

COMMIT;
