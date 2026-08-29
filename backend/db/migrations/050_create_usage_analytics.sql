-- 050_create_usage_analytics.sql
-- Usage verification and analytics for APYRA projects and external apps.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS usage_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid REFERENCES projects(id) ON DELETE SET NULL,
  license_id uuid REFERENCES licenses(id) ON DELETE SET NULL,
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  business_id text,
  app_code text NOT NULL,
  device_id text NOT NULL,
  session_id text,
  event_type text NOT NULL DEFAULT 'app_heartbeat',
  app_version text,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  received_at timestamptz NOT NULL DEFAULT now(),
  active_seconds integer NOT NULL DEFAULT 0 CHECK (active_seconds >= 0 AND active_seconds <= 86400),
  metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  ip_address text
);

CREATE INDEX IF NOT EXISTS idx_usage_events_project_received ON usage_events(project_id, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_events_license_received ON usage_events(license_id, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_events_customer_received ON usage_events(customer_id, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_events_business_received ON usage_events(business_id, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_events_app_received ON usage_events(app_code, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_events_device_received ON usage_events(device_id, received_at DESC);

CREATE TABLE IF NOT EXISTS usage_daily_stats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stat_date date NOT NULL,
  project_id uuid REFERENCES projects(id) ON DELETE SET NULL,
  license_id uuid REFERENCES licenses(id) ON DELETE SET NULL,
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  business_id text,
  subject_key text NOT NULL,
  app_code text NOT NULL,
  device_id text NOT NULL,
  app_version text,
  sessions_count integer NOT NULL DEFAULT 0,
  heartbeat_count integer NOT NULL DEFAULT 0,
  events_count integer NOT NULL DEFAULT 0,
  active_seconds integer NOT NULL DEFAULT 0,
  first_seen_at timestamptz NOT NULL,
  last_seen_at timestamptz NOT NULL,
  last_metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (stat_date, subject_key, app_code, device_id)
);

CREATE INDEX IF NOT EXISTS idx_usage_daily_project_date ON usage_daily_stats(project_id, stat_date DESC);
CREATE INDEX IF NOT EXISTS idx_usage_daily_license_date ON usage_daily_stats(license_id, stat_date DESC);
CREATE INDEX IF NOT EXISTS idx_usage_daily_customer_date ON usage_daily_stats(customer_id, stat_date DESC);
CREATE INDEX IF NOT EXISTS idx_usage_daily_business_date ON usage_daily_stats(business_id, stat_date DESC);
CREATE INDEX IF NOT EXISTS idx_usage_daily_last_seen ON usage_daily_stats(last_seen_at DESC);

CREATE TABLE IF NOT EXISTS usage_feature_stats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stat_date date NOT NULL,
  project_id uuid REFERENCES projects(id) ON DELETE SET NULL,
  license_id uuid REFERENCES licenses(id) ON DELETE SET NULL,
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  business_id text,
  subject_key text NOT NULL,
  app_code text NOT NULL,
  feature_code text NOT NULL,
  event_count integer NOT NULL DEFAULT 0,
  last_seen_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (stat_date, subject_key, app_code, feature_code)
);

CREATE INDEX IF NOT EXISTS idx_usage_feature_project_date ON usage_feature_stats(project_id, stat_date DESC);
CREATE INDEX IF NOT EXISTS idx_usage_feature_customer_date ON usage_feature_stats(customer_id, stat_date DESC);
CREATE INDEX IF NOT EXISTS idx_usage_feature_business_date ON usage_feature_stats(business_id, stat_date DESC);

COMMIT;
