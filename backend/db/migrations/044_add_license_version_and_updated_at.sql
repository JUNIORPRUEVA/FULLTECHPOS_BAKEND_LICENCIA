DO $$
BEGIN
  -- Agregar columna updated_at si no existe
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'licenses' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE licenses ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
  END IF;

  -- Agregar columna license_version si no existe
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'licenses' AND column_name = 'license_version'
  ) THEN
    ALTER TABLE licenses ADD COLUMN license_version integer NOT NULL DEFAULT 1;
  END IF;
END $$;

-- Trigger para actualizar updated_at en cada UPDATE
CREATE OR REPLACE FUNCTION fn_licenses_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_licenses_updated_at ON licenses;
CREATE TRIGGER trg_licenses_updated_at
  BEFORE UPDATE ON licenses
  FOR EACH ROW
  EXECUTE FUNCTION fn_licenses_updated_at();

-- Trigger para incrementar license_version en cada UPDATE
CREATE OR REPLACE FUNCTION fn_licenses_version()
RETURNS TRIGGER AS $$
BEGIN
  NEW.license_version = OLD.license_version + 1;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_licenses_version ON licenses;
CREATE TRIGGER trg_licenses_version
  BEFORE UPDATE ON licenses
  FOR EACH ROW
  EXECUTE FUNCTION fn_licenses_version();
