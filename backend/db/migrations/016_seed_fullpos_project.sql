-- 016_seed_fullpos_project.sql
-- Ensure FULLPOS project exists (required by FULLPOS app which sends project_code=FULLPOS)

DO $$
BEGIN
  IF to_regclass('public.projects') IS NULL THEN
    -- Old installs without projects table: nothing to do.
    RETURN;
  END IF;

  INSERT INTO projects (code, name, description, is_active)
  SELECT 'FULLPOS', 'FULLPOS', 'Auto-seeded for FULLPOS app', true
  WHERE NOT EXISTS (SELECT 1 FROM projects WHERE code = 'FULLPOS');
END $$;
