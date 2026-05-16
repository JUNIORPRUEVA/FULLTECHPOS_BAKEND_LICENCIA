-- 033_add_saas_license_payment_controls.sql
-- Professional SaaS controls: permanent/subscription licenses, due dates, debts, and payment dates.

BEGIN;

ALTER TABLE licenses
  ADD COLUMN IF NOT EXISTS license_type text NOT NULL DEFAULT 'SUSCRIPCION',
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

UPDATE licenses
SET license_type = CASE
  WHEN fecha_fin IS NULL AND subscription_id IS NULL THEN 'PERMANENTE'
  ELSE 'SUSCRIPCION'
END
WHERE license_type IS NULL OR license_type NOT IN ('PERMANENTE', 'SUSCRIPCION');

UPDATE licenses
SET expires_at = fecha_fin
WHERE expires_at IS NULL AND fecha_fin IS NOT NULL;

ALTER TABLE licenses DROP CONSTRAINT IF EXISTS ck_licenses_license_type;
ALTER TABLE licenses
  ADD CONSTRAINT ck_licenses_license_type CHECK (license_type IN ('PERMANENTE', 'SUSCRIPCION'));

CREATE INDEX IF NOT EXISTS idx_licenses_license_type ON licenses(license_type);
CREATE INDEX IF NOT EXISTS idx_licenses_expires_at ON licenses(expires_at) WHERE expires_at IS NOT NULL;

ALTER TABLE company_subscriptions
  ADD COLUMN IF NOT EXISTS customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS license_id uuid REFERENCES licenses(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS amount numeric(12,2),
  ADD COLUMN IF NOT EXISTS next_payment_date timestamptz,
  ADD COLUMN IF NOT EXISTS license_type text NOT NULL DEFAULT 'SUSCRIPCION';

UPDATE company_subscriptions cs
SET amount = COALESCE(cs.amount, pp.price_amount),
    next_payment_date = COALESCE(cs.next_payment_date, cs.renewal_date, cs.end_date),
    license_type = CASE WHEN pp.billing_period = 'lifetime' THEN 'PERMANENTE' ELSE 'SUSCRIPCION' END
FROM product_plans pp
WHERE pp.id = cs.plan_id;

UPDATE company_subscriptions cs
SET license_id = l.id,
    customer_id = COALESCE(cs.customer_id, l.customer_id)
FROM licenses l
WHERE l.subscription_id = cs.id
  AND cs.license_id IS NULL;

ALTER TABLE company_subscriptions DROP CONSTRAINT IF EXISTS ck_company_subscriptions_status;
ALTER TABLE company_subscriptions
  ADD CONSTRAINT ck_company_subscriptions_status CHECK (
    status IN (
      'trial', 'active', 'past_due', 'suspended', 'cancelled', 'expired', 'lifetime',
      'ACTIVE', 'PENDING_PAYMENT', 'GRACE', 'EXPIRED', 'CANCELLED'
    )
  );

ALTER TABLE company_subscriptions DROP CONSTRAINT IF EXISTS ck_company_subscriptions_amount;
ALTER TABLE company_subscriptions
  ADD CONSTRAINT ck_company_subscriptions_amount CHECK (amount IS NULL OR amount >= 0);

ALTER TABLE company_subscriptions DROP CONSTRAINT IF EXISTS ck_company_subscriptions_license_type;
ALTER TABLE company_subscriptions
  ADD CONSTRAINT ck_company_subscriptions_license_type CHECK (license_type IN ('PERMANENTE', 'SUSCRIPCION'));

CREATE INDEX IF NOT EXISTS idx_company_subscriptions_customer_id ON company_subscriptions(customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_company_subscriptions_license_id ON company_subscriptions(license_id) WHERE license_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_company_subscriptions_next_payment_date ON company_subscriptions(next_payment_date) WHERE next_payment_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_company_subscriptions_license_type ON company_subscriptions(license_type);

ALTER TABLE subscription_payments
  ADD COLUMN IF NOT EXISTS payment_date timestamptz;

UPDATE subscription_payments
SET payment_date = COALESCE(payment_date, paid_at, recorded_at, created_at)
WHERE payment_date IS NULL;

CREATE INDEX IF NOT EXISTS idx_subscription_payments_payment_date ON subscription_payments(payment_date DESC) WHERE payment_date IS NOT NULL;

COMMIT;
