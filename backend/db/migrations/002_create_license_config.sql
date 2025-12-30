-- FULLTECH POS - License Configuration
-- Tabla para almacenar configuración global de licencias

CREATE TABLE IF NOT EXISTS license_config (
  id uuid PRIMARY KEY DEFAULT '00000000-0000-0000-0000-000000000001'::uuid,
  demo_dias_validez integer NOT NULL DEFAULT 15,
  demo_max_dispositivos integer NOT NULL DEFAULT 1,
  full_dias_validez integer NOT NULL DEFAULT 365,
  full_max_dispositivos integer NOT NULL DEFAULT 2,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Insertar configuración inicial si no existe
INSERT INTO license_config (
  id,
  demo_dias_validez,
  demo_max_dispositivos,
  full_dias_validez,
  full_max_dispositivos,
  created_at,
  updated_at
)
VALUES (
  '00000000-0000-0000-0000-000000000001'::uuid,
  15,
  1,
  365,
  2,
  now(),
  now()
)
ON CONFLICT (id) DO NOTHING;

-- Crear función para actualizar automáticamente updated_at
CREATE OR REPLACE FUNCTION update_license_config_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear trigger para actualizar updated_at automáticamente
DROP TRIGGER IF EXISTS update_license_config_timestamp_trigger ON license_config;
CREATE TRIGGER update_license_config_timestamp_trigger
BEFORE UPDATE ON license_config
FOR EACH ROW
EXECUTE FUNCTION update_license_config_timestamp();
