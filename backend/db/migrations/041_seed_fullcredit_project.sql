-- 041_seed_fullcredit_project.sql
-- Ensure FULLCREDIT project exists in Apyra project list.

DO $$
BEGIN
  IF to_regclass('public.projects') IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO projects (code, name, description, is_active)
  SELECT 'FULLCREDIT', 'FULLCREDIT', 'Auto-seeded for FULLCREDIT app', true
  WHERE NOT EXISTS (SELECT 1 FROM projects WHERE code = 'FULLCREDIT');
END $$;