-- 015_add_customers_business_id.sql
-- Add stable business_id identifier (no device_id) for cloud registration + license fetch.

ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS business_id text;

-- Unique business_id (when present)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE indexname = 'idx_customers_business_id_unique'
  ) THEN
    CREATE UNIQUE INDEX idx_customers_business_id_unique
      ON customers (business_id)
      WHERE business_id IS NOT NULL;
  END IF;
END $$;

ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS trial_start_at timestamptz;

ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS app_version text;
