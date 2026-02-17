-- 021_create_support_message_config.sql
-- Configuración mínima de Evolution para solicitudes de soporte desde FULLPOS

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS support_message_config (
  id uuid PRIMARY KEY DEFAULT '00000000-0000-0000-0000-000000000002'::uuid,
  enabled boolean NOT NULL DEFAULT false,
  base_url text,
  instance_name text,
  api_key text,
  support_phone text,
  send_timeout_ms integer NOT NULL DEFAULT 12000,
  template_text text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO support_message_config (
  id,
  enabled,
  base_url,
  instance_name,
  api_key,
  support_phone,
  send_timeout_ms,
  template_text,
  created_at,
  updated_at
)
VALUES (
  '00000000-0000-0000-0000-000000000002'::uuid,
  false,
  NULL,
  NULL,
  NULL,
  NULL,
  12000,
  'Solicitud de soporte FULLPOS\nBusiness ID: {business_id}\nNegocio: {business_name}\nPropietario: {owner_name}\nTeléfono: {phone}\nEmail: {email}\nUsuario: {username}\nDetalle: {client_message}\nFecha: {ts}',
  now(),
  now()
)
ON CONFLICT (id) DO NOTHING;

COMMIT;
