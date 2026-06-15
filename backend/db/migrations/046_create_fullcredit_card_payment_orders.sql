BEGIN;

CREATE TABLE IF NOT EXISTS fullcredit_card_payment_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
  project_code varchar(50) NOT NULL DEFAULT 'FULLCREDIT',
  business_id varchar(255) NOT NULL,
  device_id varchar(255) NOT NULL,
  payment_reference uuid NOT NULL,
  amount numeric(12,2) NOT NULL,
  currency varchar(10) NOT NULL DEFAULT 'USD',
  provider varchar(50) NOT NULL DEFAULT 'paypal',
  provider_order_id varchar(255),
  provider_capture_id varchar(255),
  public_token_hash char(64) NOT NULL,
  status varchar(50) NOT NULL DEFAULT 'PENDING',
  checkout_url text,
  raw_response jsonb NOT NULL DEFAULT '{}',
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_fullcredit_card_project CHECK (project_code = 'FULLCREDIT'),
  CONSTRAINT ck_fullcredit_card_amount CHECK (amount > 0),
  CONSTRAINT ck_fullcredit_card_status CHECK (
    status IN ('PENDING', 'APPROVED', 'PAID', 'FAILED', 'CANCELLED')
  ),
  CONSTRAINT uq_fullcredit_card_reference
    UNIQUE (project_code, business_id, payment_reference)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_fullcredit_card_provider_order
  ON fullcredit_card_payment_orders(provider_order_id)
  WHERE provider_order_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_fullcredit_card_business_created
  ON fullcredit_card_payment_orders(business_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_fullcredit_card_status
  ON fullcredit_card_payment_orders(status);

COMMIT;
