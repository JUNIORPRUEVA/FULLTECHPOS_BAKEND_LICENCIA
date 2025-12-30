-- FULLTECH POS - Licencias
-- Ejecutar en PostgreSQL (una sola vez)

-- UUID helper
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre_negocio text NOT NULL,
  contacto_nombre text,
  contacto_telefono text,
  contacto_email text,
  created_at timestamp NOT NULL DEFAULT now()
);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'license_tipo') THEN
    CREATE TYPE license_tipo AS ENUM ('DEMO', 'FULL');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'license_estado') THEN
    CREATE TYPE license_estado AS ENUM ('PENDIENTE', 'ACTIVA', 'VENCIDA', 'BLOQUEADA');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'activation_estado') THEN
    CREATE TYPE activation_estado AS ENUM ('ACTIVA', 'REVOCADA');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS licenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid REFERENCES customers(id) ON DELETE RESTRICT,
  license_key text NOT NULL UNIQUE,
  tipo license_tipo NOT NULL,
  dias_validez int NOT NULL,
  max_dispositivos int NOT NULL,
  fecha_inicio timestamp NULL,
  fecha_fin timestamp NULL,
  estado license_estado NOT NULL,
  notas text,
  created_at timestamp NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_licenses_customer_id ON licenses(customer_id);
CREATE INDEX IF NOT EXISTS idx_licenses_estado ON licenses(estado);
CREATE INDEX IF NOT EXISTS idx_licenses_tipo ON licenses(tipo);

CREATE TABLE IF NOT EXISTS license_activations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  license_id uuid NOT NULL REFERENCES licenses(id) ON DELETE CASCADE,
  device_id text NOT NULL,
  activated_at timestamp NOT NULL DEFAULT now(),
  last_check_at timestamp NOT NULL DEFAULT now(),
  estado activation_estado NOT NULL,
  UNIQUE (license_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_license_activations_license_id ON license_activations(license_id);
CREATE INDEX IF NOT EXISTS idx_license_activations_device_id ON license_activations(device_id);
