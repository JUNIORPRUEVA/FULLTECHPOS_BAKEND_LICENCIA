-- 020_create_support_reset_tokens.sql
-- Tokens manuales de soporte (válidos 15 min) para resetear contraseña local en cliente

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS support_reset_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id text NOT NULL,
  username text NOT NULL,
  token_hash text NOT NULL,
  token_expires_at timestamptz NOT NULL,
  issued_by text,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_reset_pending
  ON support_reset_tokens (business_id, username, created_at DESC)
  WHERE consumed_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_support_reset_hash
  ON support_reset_tokens (business_id, username, token_hash)
  WHERE consumed_at IS NULL;

COMMIT;
