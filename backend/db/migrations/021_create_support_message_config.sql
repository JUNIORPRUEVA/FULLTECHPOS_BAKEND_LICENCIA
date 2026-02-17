-- 021_create_support_message_config.sql
-- Configuración mínima de Evolution para solicitudes de soporte desde FULLPOS

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS support_message_config (
  id uuid PRIMARY KEY DEFAULT '00000000-0000-0000-0000-000000000002'::uuid,
  base_url text,
  instance_name text,
  api_key text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO support_message_config (
  id,
  base_url,
  instance_name,
  api_key,
  created_at,
  updated_at
)
VALUES (
  '00000000-0000-0000-0000-000000000002'::uuid,
  NULL,
  NULL,
  NULL,
  now(),
  now()
)
ON CONFLICT (id) DO NOTHING;

COMMIT;
