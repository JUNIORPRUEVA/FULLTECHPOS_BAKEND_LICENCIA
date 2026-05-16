-- 036_create_user_saas_billing_schema.sql
-- User-centric SaaS billing schema for PayPal payments, subscriptions, and licenses.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS saas_planes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre text NOT NULL,
  tipo text NOT NULL,
  precio numeric(12,2) NOT NULL DEFAULT 0,
  moneda text NOT NULL DEFAULT 'USD',
  activo boolean NOT NULL DEFAULT true,
  paypal_product_id text,
  paypal_plan_id text,
  metadata jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_saas_planes_tipo CHECK (tipo IN ('mensual', 'anual', 'permanente')),
  CONSTRAINT ck_saas_planes_precio CHECK (precio >= 0),
  CONSTRAINT ck_saas_planes_moneda CHECK (moneda ~ '^[A-Z]{3}$')
);

CREATE TABLE IF NOT EXISTS saas_suscripciones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES platform_users(id) ON DELETE CASCADE,
  plan_id uuid NOT NULL REFERENCES saas_planes(id) ON DELETE RESTRICT,
  paypal_subscription_id text,
  estado text NOT NULL DEFAULT 'activa',
  fecha_inicio timestamptz NOT NULL DEFAULT now(),
  fecha_fin timestamptz,
  proximo_pago timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_saas_suscripciones_estado CHECK (estado IN ('activa', 'cancelada', 'vencida')),
  CONSTRAINT ck_saas_suscripciones_fechas CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)
);

CREATE TABLE IF NOT EXISTS saas_pagos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES platform_users(id) ON DELETE CASCADE,
  suscripcion_id uuid REFERENCES saas_suscripciones(id) ON DELETE SET NULL,
  licencia_id uuid,
  tipo text NOT NULL DEFAULT 'paypal',
  paypal_order_id text,
  paypal_payment_id text,
  paypal_subscription_id text,
  monto numeric(12,2) NOT NULL,
  moneda text NOT NULL DEFAULT 'USD',
  estado text NOT NULL DEFAULT 'pendiente',
  fecha_pago timestamptz,
  paypal_payload jsonb NOT NULL DEFAULT '{}',
  metadata jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_saas_pagos_tipo CHECK (tipo IN ('paypal')),
  CONSTRAINT ck_saas_pagos_estado CHECK (estado IN ('pendiente', 'completado', 'fallido')),
  CONSTRAINT ck_saas_pagos_monto CHECK (monto >= 0),
  CONSTRAINT ck_saas_pagos_moneda CHECK (moneda ~ '^[A-Z]{3}$')
);

CREATE TABLE IF NOT EXISTS saas_licencias (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES platform_users(id) ON DELETE CASCADE,
  plan_id uuid REFERENCES saas_planes(id) ON DELETE SET NULL,
  suscripcion_id uuid REFERENCES saas_suscripciones(id) ON DELETE SET NULL,
  tipo text NOT NULL,
  estado text NOT NULL DEFAULT 'inactiva',
  fecha_activacion timestamptz,
  fecha_expiracion timestamptz,
  license_key text UNIQUE,
  metadata jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_saas_licencias_tipo CHECK (tipo IN ('permanente', 'suscripcion')),
  CONSTRAINT ck_saas_licencias_estado CHECK (estado IN ('activa', 'inactiva', 'bloqueada')),
  CONSTRAINT ck_saas_licencias_fechas CHECK (
    fecha_expiracion IS NULL
    OR fecha_activacion IS NULL
    OR fecha_expiracion >= fecha_activacion
  )
);

ALTER TABLE saas_pagos DROP CONSTRAINT IF EXISTS fk_saas_pagos_licencia_id;
ALTER TABLE saas_pagos
  ADD CONSTRAINT fk_saas_pagos_licencia_id
  FOREIGN KEY (licencia_id) REFERENCES saas_licencias(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_saas_planes_nombre_tipo ON saas_planes(lower(nombre), tipo);
CREATE UNIQUE INDEX IF NOT EXISTS uq_saas_planes_paypal_plan_id
  ON saas_planes(paypal_plan_id)
  WHERE paypal_plan_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_saas_suscripciones_paypal_subscription_id
  ON saas_suscripciones(paypal_subscription_id)
  WHERE paypal_subscription_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_saas_pagos_paypal_order_id
  ON saas_pagos(paypal_order_id)
  WHERE paypal_order_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_saas_pagos_paypal_payment_id
  ON saas_pagos(paypal_payment_id)
  WHERE paypal_payment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_saas_planes_tipo ON saas_planes(tipo);
CREATE INDEX IF NOT EXISTS idx_saas_planes_activo ON saas_planes(activo);

CREATE INDEX IF NOT EXISTS idx_saas_suscripciones_user_id ON saas_suscripciones(user_id);
CREATE INDEX IF NOT EXISTS idx_saas_suscripciones_plan_id ON saas_suscripciones(plan_id);
CREATE INDEX IF NOT EXISTS idx_saas_suscripciones_estado ON saas_suscripciones(estado);
CREATE INDEX IF NOT EXISTS idx_saas_suscripciones_proximo_pago
  ON saas_suscripciones(proximo_pago)
  WHERE proximo_pago IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_saas_suscripciones_user_estado
  ON saas_suscripciones(user_id, estado);

CREATE INDEX IF NOT EXISTS idx_saas_pagos_user_id ON saas_pagos(user_id);
CREATE INDEX IF NOT EXISTS idx_saas_pagos_suscripcion_id ON saas_pagos(suscripcion_id);
CREATE INDEX IF NOT EXISTS idx_saas_pagos_licencia_id ON saas_pagos(licencia_id);
CREATE INDEX IF NOT EXISTS idx_saas_pagos_estado ON saas_pagos(estado);
CREATE INDEX IF NOT EXISTS idx_saas_pagos_fecha_pago
  ON saas_pagos(fecha_pago DESC)
  WHERE fecha_pago IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_saas_pagos_paypal_subscription_id
  ON saas_pagos(paypal_subscription_id)
  WHERE paypal_subscription_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_saas_licencias_user_id ON saas_licencias(user_id);
CREATE INDEX IF NOT EXISTS idx_saas_licencias_plan_id ON saas_licencias(plan_id);
CREATE INDEX IF NOT EXISTS idx_saas_licencias_suscripcion_id ON saas_licencias(suscripcion_id);
CREATE INDEX IF NOT EXISTS idx_saas_licencias_estado ON saas_licencias(estado);
CREATE INDEX IF NOT EXISTS idx_saas_licencias_tipo ON saas_licencias(tipo);
CREATE INDEX IF NOT EXISTS idx_saas_licencias_fecha_expiracion
  ON saas_licencias(fecha_expiracion)
  WHERE fecha_expiracion IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_saas_licencias_user_estado
  ON saas_licencias(user_id, estado);

COMMIT;
