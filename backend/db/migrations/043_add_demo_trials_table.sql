-- 043_add_demo_trials_table.sql
-- Crea la tabla demo_trials para rastrear el consumo de demos por dispositivo.
-- Cada dispositivo puede consumir UNA demo por proyecto.
-- Esto evita que un mismo dispositivo reinicie la demo infinitamente.

BEGIN;

-- =====================================
-- 1. Crear tabla demo_trials
-- =====================================
CREATE TABLE IF NOT EXISTS demo_trials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
  device_id VARCHAR(255) NOT NULL,
  contacto_email_norm VARCHAR(255),
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  license_id uuid REFERENCES licenses(id) ON DELETE SET NULL,
  started_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_demo_trials_project_device UNIQUE (project_id, device_id)
);

-- Índices para demo_trials
CREATE INDEX IF NOT EXISTS idx_demo_trials_device_id ON demo_trials(device_id);
CREATE INDEX IF NOT EXISTS idx_demo_trials_project_id ON demo_trials(project_id);
CREATE INDEX IF NOT EXISTS idx_demo_trials_customer_id ON demo_trials(customer_id) WHERE customer_id IS NOT NULL;

COMMIT;
