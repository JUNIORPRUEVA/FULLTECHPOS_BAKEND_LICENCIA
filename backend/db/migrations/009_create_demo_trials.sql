-- 009_create_demo_trials.sql
-- Prevent repeated DEMO trials per customer contact + project.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS demo_trials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
  contacto_telefono_norm text NULL,
  contacto_email_norm text NULL,
  customer_id uuid NULL REFERENCES customers(id) ON DELETE SET NULL,
  license_id uuid NULL REFERENCES licenses(id) ON DELETE SET NULL,
  started_at timestamptz NOT NULL DEFAULT now()
);

-- One DEMO per phone/email per project (NULLs do not conflict).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_demo_trials_project_phone'
  ) THEN
    ALTER TABLE demo_trials
      ADD CONSTRAINT uq_demo_trials_project_phone UNIQUE (project_id, contacto_telefono_norm);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_demo_trials_project_email'
  ) THEN
    ALTER TABLE demo_trials
      ADD CONSTRAINT uq_demo_trials_project_email UNIQUE (project_id, contacto_email_norm);
  END IF;
END$$;

CREATE INDEX IF NOT EXISTS idx_demo_trials_project_id ON demo_trials(project_id);
CREATE INDEX IF NOT EXISTS idx_demo_trials_customer_id ON demo_trials(customer_id);
CREATE INDEX IF NOT EXISTS idx_demo_trials_license_id ON demo_trials(license_id);

COMMIT;
