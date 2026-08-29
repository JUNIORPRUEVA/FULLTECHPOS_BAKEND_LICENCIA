-- 051_backfill_usage_from_license_activations.sql
-- Seeds usage_daily_stats from existing license activation checks so the
-- usage dashboard has historical signal before apps send rich telemetry.

BEGIN;

INSERT INTO usage_daily_stats (
  stat_date,
  project_id,
  license_id,
  customer_id,
  business_id,
  subject_key,
  app_code,
  device_id,
  app_version,
  sessions_count,
  heartbeat_count,
  events_count,
  active_seconds,
  first_seen_at,
  last_seen_at,
  last_metrics,
  updated_at
)
SELECT
  (COALESCE(a.last_seen_at, a.last_check_at, a.activated_at, now()) AT TIME ZONE 'UTC')::date AS stat_date,
  COALESCE(a.project_id, l.project_id) AS project_id,
  l.id AS license_id,
  c.id AS customer_id,
  c.business_id,
  'license:' || l.id::text AS subject_key,
  COALESCE(p.code, 'LICENSED_APP') AS app_code,
  a.device_id,
  c.app_version,
  0 AS sessions_count,
  1 AS heartbeat_count,
  1 AS events_count,
  0 AS active_seconds,
  COALESCE(a.activated_at, a.last_check_at, a.last_seen_at, now()) AS first_seen_at,
  COALESCE(a.last_seen_at, a.last_check_at, a.activated_at, now()) AS last_seen_at,
  jsonb_build_object('source', 'license_activations_backfill') AS last_metrics,
  now() AS updated_at
FROM license_activations a
JOIN licenses l ON l.id = a.license_id
LEFT JOIN customers c ON c.id = l.customer_id
LEFT JOIN projects p ON p.id = COALESCE(a.project_id, l.project_id)
WHERE a.device_id IS NOT NULL
ON CONFLICT (stat_date, subject_key, app_code, device_id)
DO UPDATE SET
  project_id = COALESCE(EXCLUDED.project_id, usage_daily_stats.project_id),
  license_id = COALESCE(EXCLUDED.license_id, usage_daily_stats.license_id),
  customer_id = COALESCE(EXCLUDED.customer_id, usage_daily_stats.customer_id),
  business_id = COALESCE(EXCLUDED.business_id, usage_daily_stats.business_id),
  app_version = COALESCE(EXCLUDED.app_version, usage_daily_stats.app_version),
  heartbeat_count = GREATEST(usage_daily_stats.heartbeat_count, EXCLUDED.heartbeat_count),
  events_count = GREATEST(usage_daily_stats.events_count, EXCLUDED.events_count),
  first_seen_at = LEAST(usage_daily_stats.first_seen_at, EXCLUDED.first_seen_at),
  last_seen_at = GREATEST(usage_daily_stats.last_seen_at, EXCLUDED.last_seen_at),
  last_metrics = EXCLUDED.last_metrics,
  updated_at = now();

COMMIT;
