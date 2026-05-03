-- 030_update_licenses_saas_fields.sql
-- Add SaaS foundation fields to existing licenses table (backward compatible)

BEGIN;

-- Add company_id field
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'licenses' AND column_name = 'company_id'
  ) THEN
    ALTER TABLE licenses
      ADD COLUMN company_id uuid REFERENCES companies(id) ON DELETE SET NULL;
  END IF;
END$$;

-- Add subscription_id field
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'licenses' AND column_name = 'subscription_id'
  ) THEN
    ALTER TABLE licenses
      ADD COLUMN subscription_id uuid REFERENCES company_subscriptions(id) ON DELETE SET NULL;
  END IF;
END$$;

-- Add product_id field (note: conflicting name with POS product_id exists in some tables, but licenses doesn't have it yet)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'licenses' AND column_name = 'product_id'
  ) THEN
    ALTER TABLE licenses
      ADD COLUMN product_id uuid REFERENCES products(id) ON DELETE SET NULL;
  END IF;
END$$;

-- Add metadata JSONB field
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'licenses' AND column_name = 'metadata'
  ) THEN
    ALTER TABLE licenses
      ADD COLUMN metadata jsonb DEFAULT '{}';
  END IF;
END$$;

-- Add issued_at field
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'licenses' AND column_name = 'issued_at'
  ) THEN
    ALTER TABLE licenses
      ADD COLUMN issued_at timestamptz;
  END IF;
END$$;

-- Add revoked_at field
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'licenses' AND column_name = 'revoked_at'
  ) THEN
    ALTER TABLE licenses
      ADD COLUMN revoked_at timestamptz;
  END IF;
END$$;

-- Add revoked_reason field
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'licenses' AND column_name = 'revoked_reason'
  ) THEN
    ALTER TABLE licenses
      ADD COLUMN revoked_reason text;
  END IF;
END$$;

-- Add offline_grace_until field
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'licenses' AND column_name = 'offline_grace_until'
  ) THEN
    ALTER TABLE licenses
      ADD COLUMN offline_grace_until timestamptz;
  END IF;
END$$;

CREATE INDEX IF NOT EXISTS idx_licenses_company_id ON licenses(company_id);
CREATE INDEX IF NOT EXISTS idx_licenses_subscription_id ON licenses(subscription_id);
CREATE INDEX IF NOT EXISTS idx_licenses_product_id ON licenses(product_id);
CREATE INDEX IF NOT EXISTS idx_licenses_issued_at ON licenses(issued_at) WHERE issued_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_licenses_revoked_at ON licenses(revoked_at) WHERE revoked_at IS NOT NULL;

COMMIT;
