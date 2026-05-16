-- 034_update_activation_saas_fields.sql
-- Complete SaaS activation model while keeping legacy activation columns compatible.

BEGIN;

ALTER TABLE license_activations
  ADD COLUMN IF NOT EXISTS device_name text,
  ADD COLUMN IF NOT EXISTS device_type text,
  ADD COLUMN IF NOT EXISTS ip_address text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz,
  ADD COLUMN IF NOT EXISTS status text;

UPDATE license_activations
SET created_at = COALESCE(created_at, activated_at, now()),
    last_seen_at = COALESCE(last_seen_at, last_check_at, activated_at, now()),
    status = COALESCE(
      status,
      CASE estado::text
        WHEN 'ACTIVA' THEN 'ACTIVE'
        WHEN 'BLOQUEADA' THEN 'BLOCKED'
        WHEN 'REVOCADA' THEN 'REVOKED'
        ELSE 'REVOKED'
      END
    ),
    device_type = COALESCE(device_type, 'unknown')
WHERE created_at IS NULL
   OR last_seen_at IS NULL
   OR status IS NULL
   OR device_type IS NULL;

ALTER TABLE license_activations
  ALTER COLUMN created_at SET DEFAULT now(),
  ALTER COLUMN created_at SET NOT NULL,
  ALTER COLUMN last_seen_at SET DEFAULT now(),
  ALTER COLUMN last_seen_at SET NOT NULL,
  ALTER COLUMN status SET DEFAULT 'ACTIVE',
  ALTER COLUMN status SET NOT NULL;

ALTER TABLE license_activations DROP CONSTRAINT IF EXISTS ck_license_activations_status;
ALTER TABLE license_activations
  ADD CONSTRAINT ck_license_activations_status CHECK (status IN ('ACTIVE', 'BLOCKED', 'REVOKED'));

ALTER TABLE license_activations DROP CONSTRAINT IF EXISTS ck_license_activations_device_type;
ALTER TABLE license_activations
  ADD CONSTRAINT ck_license_activations_device_type CHECK (device_type IN ('pc', 'movil', 'mobile', 'tablet', 'unknown'));

CREATE INDEX IF NOT EXISTS idx_license_activations_status ON license_activations(status);
CREATE INDEX IF NOT EXISTS idx_license_activations_last_seen_at ON license_activations(last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_license_activations_device_status ON license_activations(device_id, status);
CREATE INDEX IF NOT EXISTS idx_license_activations_license_status ON license_activations(license_id, status);

COMMIT;
