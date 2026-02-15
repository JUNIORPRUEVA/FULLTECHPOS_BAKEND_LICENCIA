-- 017_add_license_estado_eliminada.sql
-- Adds ELIMINADA to license_estado enum (used for soft-delete)

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_enum e ON e.enumtypid = t.oid
    WHERE t.typname = 'license_estado'
      AND e.enumlabel = 'ELIMINADA'
  ) THEN
    -- ALTER TYPE cannot run directly inside plpgsql without EXECUTE.
    EXECUTE 'ALTER TYPE license_estado ADD VALUE ''ELIMINADA''';
  END IF;
END $$;
