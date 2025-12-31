-- 006_create_backups.sql
-- Backups encrypted payload storage (company + device scoped)

BEGIN;

CREATE TABLE IF NOT EXISTS backups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  device_id text NOT NULL,
  backup_json jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_backups_company_created_at
  ON backups(company_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_backups_company_device_created_at
  ON backups(company_id, device_id, created_at DESC);

COMMIT;
