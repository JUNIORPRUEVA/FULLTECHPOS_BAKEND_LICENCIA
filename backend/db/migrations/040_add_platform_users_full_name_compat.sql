-- 040_add_platform_users_full_name_compat.sql
-- Compatibility column for code paths that still read platform_users.full_name.

BEGIN;

ALTER TABLE platform_users
  ADD COLUMN IF NOT EXISTS full_name text;

UPDATE platform_users
SET full_name = COALESCE(NULLIF(full_name, ''), display_name)
WHERE display_name IS NOT NULL
  AND (full_name IS NULL OR full_name = '');

UPDATE platform_users
SET display_name = COALESCE(NULLIF(display_name, ''), full_name)
WHERE full_name IS NOT NULL
  AND (display_name IS NULL OR display_name = '');

CREATE OR REPLACE FUNCTION sync_platform_users_names()
RETURNS trigger AS $$
BEGIN
  IF NEW.display_name IS NULL OR NEW.display_name = '' THEN
    NEW.display_name := NEW.full_name;
  END IF;

  IF NEW.full_name IS NULL OR NEW.full_name = '' THEN
    NEW.full_name := NEW.display_name;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_platform_users_names ON platform_users;
CREATE TRIGGER trg_sync_platform_users_names
BEFORE INSERT OR UPDATE OF display_name, full_name ON platform_users
FOR EACH ROW
EXECUTE FUNCTION sync_platform_users_names();

COMMIT;
