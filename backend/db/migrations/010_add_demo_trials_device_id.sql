-- 010_add_demo_trials_device_id.sql
-- Enforce one DEMO trial per device + project.

BEGIN;

ALTER TABLE demo_trials
  ADD COLUMN IF NOT EXISTS device_id text NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_demo_trials_project_device'
  ) THEN
    ALTER TABLE demo_trials
      ADD CONSTRAINT uq_demo_trials_project_device UNIQUE (project_id, device_id);
  END IF;
END$$;

CREATE INDEX IF NOT EXISTS idx_demo_trials_device_id ON demo_trials(device_id);

COMMIT;
