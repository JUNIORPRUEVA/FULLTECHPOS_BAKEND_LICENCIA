-- 053_usage_events_idempotent_activity.sql
-- Canonical DaleVentas telemetry ingestion fields and idempotency.

BEGIN;

ALTER TABLE usage_events
  ADD COLUMN IF NOT EXISTS event_id text,
  ADD COLUMN IF NOT EXISTS schema_version integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS actor_user_id text,
  ADD COLUMN IF NOT EXISTS entity_type text,
  ADD COLUMN IF NOT EXISTS entity_id text,
  ADD COLUMN IF NOT EXISTS feature_code text,
  ADD COLUMN IF NOT EXISTS platform text;

UPDATE usage_events
SET event_id = id::text
WHERE event_id IS NULL;

ALTER TABLE usage_events
  ALTER COLUMN event_id SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_usage_events_event_id_unique
  ON usage_events(event_id);

CREATE INDEX IF NOT EXISTS idx_usage_events_business_occurred
  ON usage_events(business_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_usage_events_feature_occurred
  ON usage_events(feature_code, occurred_at DESC)
  WHERE feature_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_usage_events_entity
  ON usage_events(entity_type, entity_id)
  WHERE entity_type IS NOT NULL AND entity_id IS NOT NULL;

COMMIT;
