BEGIN;

CREATE OR REPLACE FUNCTION prevent_customer_business_id_change()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.business_id IS NOT NULL
     AND NEW.business_id IS DISTINCT FROM OLD.business_id
     AND COALESCE(current_setting('app.allow_business_id_repair', true), '0') <> '1' THEN
    RAISE EXCEPTION 'customers.business_id cannot be changed once assigned without repair mode'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_customer_business_id_change ON customers;

CREATE TRIGGER trg_prevent_customer_business_id_change
BEFORE UPDATE OF business_id ON customers
FOR EACH ROW
EXECUTE FUNCTION prevent_customer_business_id_change();

COMMIT;
