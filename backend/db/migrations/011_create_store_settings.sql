-- 011_create_store_settings.sql
-- Store/public website settings (branding + contact).

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS store_settings (
  id smallint PRIMARY KEY DEFAULT 1,
  brand_name text NOT NULL DEFAULT 'JR Digital',
  logo_url text NULL,
  whatsapp text NULL,
  email text NULL,
  address text NULL,
  socials jsonb NOT NULL DEFAULT '{}'::jsonb,
  theme jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT store_settings_singleton CHECK (id = 1)
);

INSERT INTO store_settings (id)
VALUES (1)
ON CONFLICT (id) DO NOTHING;

COMMIT;
