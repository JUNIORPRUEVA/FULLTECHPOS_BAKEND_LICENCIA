-- 039_allow_pending_saas_subscriptions.sql
-- Allow PayPal checkout subscriptions to be stored before PayPal activates them.

BEGIN;

ALTER TABLE saas_suscripciones
  DROP CONSTRAINT IF EXISTS ck_saas_suscripciones_estado;

ALTER TABLE saas_suscripciones
  ADD CONSTRAINT ck_saas_suscripciones_estado
  CHECK (estado IN ('pendiente', 'activa', 'cancelada', 'vencida'));

COMMIT;
