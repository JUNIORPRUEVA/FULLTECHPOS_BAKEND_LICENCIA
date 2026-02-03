-- 007_create_projects_and_project_scoping.sql
-- Adds multi-project support to licensing (keeps backward compatibility)

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =====================================
-- Projects
-- =====================================
CREATE TABLE IF NOT EXISTS projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL,
  name text NOT NULL,
  description text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (code)
);

-- Default project for backward compatibility
INSERT INTO projects (code, name, description, is_active)
SELECT 'DEFAULT', 'Default Project', 'Auto-created default project', true
WHERE NOT EXISTS (SELECT 1 FROM projects WHERE code = 'DEFAULT');

-- =====================================
-- licenses.project_id
-- =====================================
ALTER TABLE licenses
  ADD COLUMN IF NOT EXISTS project_id uuid;

-- Backfill any NULL project_id
UPDATE licenses
SET project_id = (SELECT id FROM projects WHERE code = 'DEFAULT' LIMIT 1)
WHERE project_id IS NULL;

-- Add FK + NOT NULL (safe after backfill)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_licenses_project_id'
  ) THEN
    ALTER TABLE licenses
      ADD CONSTRAINT fk_licenses_project_id
      FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT;
  END IF;
END$$;

ALTER TABLE licenses
  ALTER COLUMN project_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_licenses_project_id ON licenses(project_id);

-- =====================================
-- license_activations.project_id
-- (denormalized for faster queries / auditing)
-- =====================================
ALTER TABLE license_activations
  ADD COLUMN IF NOT EXISTS project_id uuid;

UPDATE license_activations a
SET project_id = l.project_id
FROM licenses l
WHERE a.license_id = l.id
  AND a.project_id IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_license_activations_project_id'
  ) THEN
    ALTER TABLE license_activations
      ADD CONSTRAINT fk_license_activations_project_id
      FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT;
  END IF;
END$$;

ALTER TABLE license_activations
  ALTER COLUMN project_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_license_activations_project_id ON license_activations(project_id);

COMMIT;
