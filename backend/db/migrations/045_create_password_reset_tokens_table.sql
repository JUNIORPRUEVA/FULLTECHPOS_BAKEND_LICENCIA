-- 045_create_password_reset_tokens_table.sql
-- Crea la tabla password_reset_tokens para el flujo de token de reset
-- que genera el admin desde el panel para que el cliente lo use en FULLPOS.

BEGIN;

CREATE TABLE IF NOT EXISTS password_reset_tokens (
  customer_id uuid PRIMARY KEY,
  token text NOT NULL,
  expires_at timestamptz NOT NULL,
  used boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_token
  ON password_reset_tokens (token);

CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_expires
  ON password_reset_tokens (expires_at);

COMMIT;
