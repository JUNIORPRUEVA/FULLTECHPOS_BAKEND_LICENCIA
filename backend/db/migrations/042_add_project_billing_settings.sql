-- 042_add_project_billing_settings.sql
-- Agrega configuración comercial/de facturación a cada proyecto
-- para soportar prepago por tiempo con PayPal.

BEGIN;

-- =====================================
-- 1. Agregar columnas de billing a projects (solo si no existen)
-- =====================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'projects' AND column_name = 'monthly_price'
  ) THEN
    ALTER TABLE projects ADD COLUMN monthly_price NUMERIC(10,2) NOT NULL DEFAULT 0;
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'projects' AND column_name = 'currency'
  ) THEN
    ALTER TABLE projects ADD COLUMN currency VARCHAR(10) NOT NULL DEFAULT 'USD';
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'projects' AND column_name = 'demo_days'
  ) THEN
    ALTER TABLE projects ADD COLUMN demo_days INTEGER NOT NULL DEFAULT 5;
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'projects' AND column_name = 'min_purchase_months'
  ) THEN
    ALTER TABLE projects ADD COLUMN min_purchase_months INTEGER NOT NULL DEFAULT 3;
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'projects' AND column_name = 'is_paid_project'
  ) THEN
    ALTER TABLE projects ADD COLUMN is_paid_project BOOLEAN NOT NULL DEFAULT true;
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'projects' AND column_name = 'allow_demo'
  ) THEN
    ALTER TABLE projects ADD COLUMN allow_demo BOOLEAN NOT NULL DEFAULT true;
  END IF;
END$$;

-- =====================================
-- 2. Configurar FULLPOS con valores por defecto
-- =====================================
UPDATE projects
SET
  monthly_price = 15,
  currency = 'USD',
  demo_days = 5,
  min_purchase_months = 3,
  is_paid_project = true,
  allow_demo = true
WHERE code = 'FULLPOS'
  AND (monthly_price IS NULL OR monthly_price = 0);

-- =====================================
-- 3. Configurar FULLCREDIT con valores por defecto
-- =====================================
UPDATE projects
SET
  monthly_price = 15,
  currency = 'USD',
  demo_days = 5,
  min_purchase_months = 3,
  is_paid_project = true,
  allow_demo = true
WHERE code = 'FULLCREDIT'
  AND (monthly_price IS NULL OR monthly_price = 0);

-- =====================================
-- 4. Configurar DEFAULT project si existe
-- =====================================
UPDATE projects
SET
  monthly_price = 0,
  currency = 'USD',
  demo_days = 0,
  min_purchase_months = 1,
  is_paid_project = false,
  allow_demo = false
WHERE code = 'DEFAULT'
  AND (monthly_price IS NULL OR monthly_price = 0);

-- =====================================
-- 5. Crear tabla license_payment_orders
-- =====================================
CREATE TABLE IF NOT EXISTS license_payment_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
  project_id uuid NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
  license_id uuid REFERENCES licenses(id) ON DELETE SET NULL,
  months INTEGER NOT NULL,
  monthly_price NUMERIC(10,2) NOT NULL,
  total_amount NUMERIC(10,2) NOT NULL,
  currency VARCHAR(10) NOT NULL DEFAULT 'USD',
  provider VARCHAR(50) NOT NULL DEFAULT 'paypal',
  provider_order_id VARCHAR(255),
  provider_capture_id VARCHAR(255),
  status VARCHAR(50) NOT NULL DEFAULT 'PENDING',
  checkout_url TEXT,
  raw_request JSONB NOT NULL DEFAULT '{}',
  raw_response JSONB NOT NULL DEFAULT '{}',
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_license_payment_orders_status CHECK (
    status IN ('PENDING', 'APPROVED', 'PAID', 'FAILED', 'CANCELLED')
  ),
  CONSTRAINT ck_license_payment_orders_months CHECK (months > 0),
  CONSTRAINT ck_license_payment_orders_amount CHECK (total_amount >= 0)
);

-- Índices para license_payment_orders
CREATE INDEX IF NOT EXISTS idx_lpo_customer_id ON license_payment_orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_lpo_project_id ON license_payment_orders(project_id);
CREATE INDEX IF NOT EXISTS idx_lpo_license_id ON license_payment_orders(license_id) WHERE license_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_lpo_provider_order_id ON license_payment_orders(provider_order_id) WHERE provider_order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_lpo_status ON license_payment_orders(status);

-- =====================================
-- 6. Agregar columna activation_source a licenses
-- =====================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'licenses' AND column_name = 'activation_source'
  ) THEN
    ALTER TABLE licenses ADD COLUMN activation_source VARCHAR(50) DEFAULT 'manual';
  END IF;
END$$;

-- =====================================
-- 7. Agregar columna payment_order_id a licenses
-- =====================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'licenses' AND column_name = 'payment_order_id'
  ) THEN
    ALTER TABLE licenses ADD COLUMN payment_order_id uuid REFERENCES license_payment_orders(id) ON DELETE SET NULL;
  END IF;
END$$;

COMMIT;
