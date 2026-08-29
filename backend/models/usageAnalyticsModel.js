const { pool } = require('../db/pool');

function buildSubjectKey({ license_id, customer_id, business_id, app_code, device_id }) {
  if (license_id) return `license:${license_id}`;
  if (customer_id) return `customer:${customer_id}`;
  if (business_id) return `business:${business_id}`;
  return `device:${app_code}:${device_id}`;
}

async function resolveUsageContext({ license_key, business_id, project_code, client = pool }) {
  const licenseKey = String(license_key || '').trim();
  const businessId = String(business_id || '').trim();
  const projectCode = String(project_code || '').trim().toUpperCase();

  if (licenseKey) {
    const res = await client.query(
      `SELECT
         l.id AS license_id,
         l.license_key,
         l.project_id,
         l.customer_id,
         c.business_id,
         c.nombre_negocio AS customer_name,
         p.code AS project_code,
         p.name AS project_name
       FROM licenses l
       LEFT JOIN customers c ON c.id = l.customer_id
       LEFT JOIN projects p ON p.id = l.project_id
       WHERE l.license_key = $1
       LIMIT 1`,
      [licenseKey]
    );
    if (res.rows[0]) return res.rows[0];
  }

  if (businessId) {
    const params = [businessId];
    const projectFilter = projectCode
      ? `AND p.code = $${params.push(projectCode)}`
      : '';
    const res = await client.query(
      `SELECT
         l.id AS license_id,
         l.license_key,
         COALESCE(l.project_id, p.id) AS project_id,
         c.id AS customer_id,
         c.business_id,
         c.nombre_negocio AS customer_name,
         p.code AS project_code,
         p.name AS project_name
       FROM customers c
       LEFT JOIN licenses l ON l.customer_id = c.id
       LEFT JOIN projects p ON p.id = l.project_id
       WHERE c.business_id = $1
         ${projectFilter}
       ORDER BY
         CASE WHEN l.estado = 'ACTIVA' THEN 0 ELSE 1 END,
         COALESCE(l.fecha_fin, l.created_at) DESC
       LIMIT 1`,
      params
    );
    if (res.rows[0]) return res.rows[0];
  }

  if (projectCode) {
    const res = await client.query(
      `SELECT id AS project_id, code AS project_code, name AS project_name
       FROM projects
       WHERE code = $1
       LIMIT 1`,
      [projectCode]
    );
    if (res.rows[0]) return res.rows[0];
  }

  return {};
}

async function insertUsageEvent(event, { client = pool } = {}) {
  const subjectKey = buildSubjectKey(event);
  const res = await client.query(
    `INSERT INTO usage_events (
       project_id, license_id, customer_id, business_id, app_code, device_id,
       session_id, event_type, app_version, occurred_at, active_seconds,
       metrics, metadata, ip_address
     ) VALUES (
       $1, $2, $3, $4, $5, $6,
       $7, $8, $9, COALESCE($10::timestamptz, now()), $11,
       $12::jsonb, $13::jsonb, $14
     )
     RETURNING *`,
    [
      event.project_id || null,
      event.license_id || null,
      event.customer_id || null,
      event.business_id || null,
      event.app_code,
      event.device_id,
      event.session_id || null,
      event.event_type,
      event.app_version || null,
      event.occurred_at || null,
      event.active_seconds || 0,
      JSON.stringify(event.metrics || {}),
      JSON.stringify(event.metadata || {}),
      event.ip_address || null
    ]
  );

  return { row: res.rows[0], subjectKey };
}

async function upsertDailyStats(event, subjectKey, { client = pool } = {}) {
  const isSession = ['app_open', 'session_start', 'login', 'activation_create'].includes(event.event_type);
  const isHeartbeat = ['app_heartbeat', 'heartbeat', 'activation_heartbeat'].includes(event.event_type);

  await client.query(
    `INSERT INTO usage_daily_stats (
       stat_date, project_id, license_id, customer_id, business_id, subject_key,
       app_code, device_id, app_version, sessions_count, heartbeat_count,
       events_count, active_seconds, first_seen_at, last_seen_at, last_metrics
     ) VALUES (
       (COALESCE($10::timestamptz, now()) AT TIME ZONE 'UTC')::date,
       $1, $2, $3, $4, $5,
       $6, $7, $8, $11, $12,
       1, $9, COALESCE($10::timestamptz, now()), COALESCE($10::timestamptz, now()), $13::jsonb
     )
     ON CONFLICT (stat_date, subject_key, app_code, device_id)
     DO UPDATE SET
       project_id = COALESCE(EXCLUDED.project_id, usage_daily_stats.project_id),
       license_id = COALESCE(EXCLUDED.license_id, usage_daily_stats.license_id),
       customer_id = COALESCE(EXCLUDED.customer_id, usage_daily_stats.customer_id),
       business_id = COALESCE(EXCLUDED.business_id, usage_daily_stats.business_id),
       app_version = COALESCE(EXCLUDED.app_version, usage_daily_stats.app_version),
       sessions_count = usage_daily_stats.sessions_count + EXCLUDED.sessions_count,
       heartbeat_count = usage_daily_stats.heartbeat_count + EXCLUDED.heartbeat_count,
       events_count = usage_daily_stats.events_count + 1,
       active_seconds = LEAST(86400, usage_daily_stats.active_seconds + EXCLUDED.active_seconds),
       first_seen_at = LEAST(usage_daily_stats.first_seen_at, EXCLUDED.first_seen_at),
       last_seen_at = GREATEST(usage_daily_stats.last_seen_at, EXCLUDED.last_seen_at),
       last_metrics = CASE WHEN EXCLUDED.last_metrics = '{}'::jsonb THEN usage_daily_stats.last_metrics ELSE EXCLUDED.last_metrics END,
       updated_at = now()`,
    [
      event.project_id || null,
      event.license_id || null,
      event.customer_id || null,
      event.business_id || null,
      subjectKey,
      event.app_code,
      event.device_id,
      event.app_version || null,
      event.active_seconds || 0,
      event.occurred_at || null,
      isSession ? 1 : 0,
      isHeartbeat ? 1 : 0,
      JSON.stringify(event.metrics || {})
    ]
  );
}

async function upsertFeatureStats(event, subjectKey, { client = pool } = {}) {
  const featureCode = String(event.feature_code || event.metadata?.feature_code || '').trim().toLowerCase();
  if (!featureCode) return;

  await client.query(
     `INSERT INTO usage_feature_stats (
       stat_date, project_id, license_id, customer_id, business_id, subject_key,
       app_code, feature_code, event_count, last_seen_at
     ) VALUES (
       (COALESCE($8::timestamptz, now()) AT TIME ZONE 'UTC')::date,
       $1, $2, $3, $4, $5,
       $6, $7, 1, COALESCE($8::timestamptz, now())
     )
     ON CONFLICT (stat_date, subject_key, app_code, feature_code)
     DO UPDATE SET
       project_id = COALESCE(EXCLUDED.project_id, usage_feature_stats.project_id),
       license_id = COALESCE(EXCLUDED.license_id, usage_feature_stats.license_id),
       customer_id = COALESCE(EXCLUDED.customer_id, usage_feature_stats.customer_id),
       business_id = COALESCE(EXCLUDED.business_id, usage_feature_stats.business_id),
       event_count = usage_feature_stats.event_count + 1,
       last_seen_at = GREATEST(usage_feature_stats.last_seen_at, EXCLUDED.last_seen_at),
       updated_at = now()`,
    [
      event.project_id || null,
      event.license_id || null,
      event.customer_id || null,
      event.business_id || null,
      subjectKey,
      event.app_code,
      featureCode,
      event.occurred_at || null
    ]
  );
}

function usageStatusSql(alias = 'u') {
  return `
    CASE
      WHEN ${alias}.last_seen_at IS NULL THEN 'NEVER_USED'
      WHEN ${alias}.last_seen_at >= now() - interval '15 minutes' THEN 'USING_NOW'
      WHEN ${alias}.last_seen_at::date = CURRENT_DATE THEN 'ACTIVE_TODAY'
      WHEN ${alias}.last_seen_at >= now() - interval '7 days' THEN 'ACTIVE_WEEK'
      WHEN ${alias}.last_seen_at < now() - interval '30 days' THEN 'INACTIVE_30_DAYS'
      WHEN ${alias}.last_seen_at < now() - interval '15 days' THEN 'INACTIVE_15_DAYS'
      ELSE 'ACTIVE_RECENT'
    END
  `;
}

function buildAdminFilters(query, startIndex = 1) {
  const params = [];
  const where = [];

  const projectCode = String(query.project_code || '').trim().toUpperCase();
  const appCode = String(query.app_code || '').trim().toUpperCase();
  const businessId = String(query.business_id || '').trim();
  const customerId = String(query.customer_id || '').trim();
  const licenseId = String(query.license_id || '').trim();
  const from = String(query.from || '').trim();
  const to = String(query.to || '').trim();

  function add(value, condition) {
    params.push(value);
    where.push(condition.replace('?', `$${startIndex + params.length - 1}`));
  }

  if (projectCode) add(projectCode, 'p.code = ?');
  if (appCode) add(appCode, 'UPPER(u.app_code) = ?');
  if (businessId) add(businessId, 'u.business_id = ?');
  if (customerId) add(customerId, 'u.customer_id = ?');
  if (licenseId) add(licenseId, 'u.license_id = ?');
  if (from) add(from, 'u.stat_date >= ?::date');
  if (to) add(to, 'u.stat_date <= ?::date');

  return { params, where };
}

async function getOverview(query = {}) {
  const { params, where } = buildAdminFilters(query);
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const res = await pool.query(
    `WITH usage_scope AS (
       SELECT u.*, p.code AS project_code
       FROM usage_daily_stats u
       LEFT JOIN projects p ON p.id = u.project_id
       ${whereSql}
     ),
     latest_subject AS (
       SELECT DISTINCT ON (subject_key, app_code)
         subject_key, app_code, project_id, customer_id, business_id, license_id,
         last_seen_at, app_version
       FROM usage_scope
       ORDER BY subject_key, app_code, last_seen_at DESC
     )
     SELECT
       COUNT(DISTINCT subject_key) FILTER (WHERE last_seen_at::date = CURRENT_DATE) AS active_today,
       COUNT(DISTINCT subject_key) FILTER (WHERE last_seen_at >= now() - interval '7 days') AS active_7_days,
       COUNT(DISTINCT subject_key) FILTER (WHERE last_seen_at < now() - interval '15 days') AS inactive_15_days,
       COUNT(DISTINCT subject_key) FILTER (WHERE last_seen_at < now() - interval '30 days') AS inactive_30_days,
       COALESCE((SELECT SUM(active_seconds) FROM usage_scope), 0)::bigint AS active_seconds,
       COALESCE((SELECT SUM(events_count) FROM usage_scope), 0)::bigint AS events_count,
       COALESCE((SELECT SUM(sessions_count) FROM usage_scope), 0)::bigint AS sessions_count,
       (SELECT COUNT(DISTINCT device_id) FROM usage_scope)::bigint AS devices_count
     FROM latest_subject`,
    params
  );
  return res.rows[0] || {};
}

async function listAccounts(query = {}) {
  const page = Math.max(1, Number(query.page || 1) || 1);
  const limit = Math.min(200, Math.max(1, Number(query.limit || 50) || 50));
  const offset = (page - 1) * limit;
  const projectCode = String(query.project_code || '').trim().toUpperCase();
  const appCode = String(query.app_code || '').trim().toUpperCase();
  const status = String(query.status || '').trim().toUpperCase();
  const businessId = String(query.business_id || '').trim();
  const from = String(query.from || '').trim();
  const to = String(query.to || '').trim();

  const params = [];
  const licenseWhere = [];
  let projectParam = null;
  let businessParam = null;
  if (projectCode) {
    params.push(projectCode);
    projectParam = params.length;
    licenseWhere.push(`p.code = $${params.length}`);
  }
  if (businessId) {
    params.push(businessId);
    businessParam = params.length;
    licenseWhere.push(`c.business_id = $${params.length}`);
  }
  const licenseWhereSql = licenseWhere.length ? `WHERE ${licenseWhere.join(' AND ')}` : '';

  params.push(appCode || null);
  const appParam = params.length;
  params.push(from || null);
  const fromParam = params.length;
  params.push(to || null);
  const toParam = params.length;
  params.push(status || null);
  const statusParam = params.length;
  params.push(limit, offset);
  const limitParam = params.length - 1;
  const offsetParam = params.length;

  const res = await pool.query(
    `WITH license_accounts AS (
       SELECT
         l.id AS license_id,
         l.license_key,
         l.estado::text AS license_status,
         l.fecha_fin AS license_expires_at,
         c.id AS customer_id,
         c.business_id,
         c.nombre_negocio AS customer_name,
         c.contacto_email AS customer_email,
         p.id AS project_id,
         p.code AS project_code,
         p.name AS project_name
       FROM licenses l
       LEFT JOIN customers c ON c.id = l.customer_id
       LEFT JOIN projects p ON p.id = l.project_id
       ${licenseWhereSql}
     ),
     linked_usage_keys AS (
       SELECT DISTINCT u.subject_key
       FROM usage_daily_stats u
       JOIN license_accounts la
         ON u.license_id = la.license_id
         OR u.customer_id = la.customer_id
         OR (la.business_id IS NOT NULL AND u.business_id = la.business_id)
     ),
     account_usage AS (
       SELECT
         la.*,
         COALESCE(du.app_code, $${appParam}, la.project_code, 'UNKNOWN') AS app_code,
         du.last_seen_at,
         du.first_seen_at,
         du.app_version,
         COALESCE(du.active_seconds, 0) AS active_seconds,
         COALESCE(du.sessions_count, 0) AS sessions_count,
         COALESCE(du.events_count, 0) AS events_count,
         COALESCE(du.devices_count, 0) AS devices_count,
         COALESCE(du.last_metrics, '{}'::jsonb) AS last_metrics,
         COALESCE(du.platform_breakdown, '[]'::jsonb) AS platform_breakdown
       FROM license_accounts la
       LEFT JOIN LATERAL (
         SELECT
           MAX(u.last_seen_at) AS last_seen_at,
           MIN(u.first_seen_at) AS first_seen_at,
           (ARRAY_AGG(u.app_code ORDER BY u.last_seen_at DESC))[1] AS app_code,
           (ARRAY_AGG(u.app_version ORDER BY u.last_seen_at DESC))[1] AS app_version,
           SUM(u.active_seconds)::bigint AS active_seconds,
           SUM(u.sessions_count)::bigint AS sessions_count,
           SUM(u.events_count)::bigint AS events_count,
           COUNT(DISTINCT u.device_id)::bigint AS devices_count,
           (ARRAY_AGG(u.last_metrics ORDER BY u.last_seen_at DESC))[1] AS last_metrics,
           COALESCE((
             SELECT jsonb_agg(
               jsonb_build_object(
                 'platform', platform,
                 'events_count', events_count,
                 'active_seconds', active_seconds,
                 'devices_count', devices_count
               )
               ORDER BY events_count DESC, devices_count DESC, platform ASC
             )
             FROM (
               SELECT
                 COALESCE(NULLIF(LOWER(x.last_metrics->>'platform'), ''), 'api') AS platform,
                 SUM(x.events_count)::bigint AS events_count,
                 SUM(x.active_seconds)::bigint AS active_seconds,
                 COUNT(DISTINCT x.device_id)::bigint AS devices_count
               FROM usage_daily_stats x
               WHERE (x.license_id = la.license_id OR x.customer_id = la.customer_id OR (la.business_id IS NOT NULL AND x.business_id = la.business_id))
                 AND ($${appParam}::text IS NULL OR UPPER(x.app_code) = $${appParam})
                 AND ($${fromParam}::text IS NULL OR x.stat_date >= $${fromParam}::date)
                 AND ($${toParam}::text IS NULL OR x.stat_date <= $${toParam}::date)
               GROUP BY platform
             ) platform_rows
           ), '[]'::jsonb) AS platform_breakdown
         FROM usage_daily_stats u
         WHERE (u.license_id = la.license_id OR u.customer_id = la.customer_id OR (la.business_id IS NOT NULL AND u.business_id = la.business_id))
           AND ($${appParam}::text IS NULL OR UPPER(u.app_code) = $${appParam})
           AND ($${fromParam}::text IS NULL OR u.stat_date >= $${fromParam}::date)
           AND ($${toParam}::text IS NULL OR u.stat_date <= $${toParam}::date)
       ) du ON true
     ),
     external_usage AS (
       SELECT
         NULL::uuid AS license_id,
         NULL::text AS license_key,
         NULL::text AS license_status,
         NULL::timestamp AS license_expires_at,
         NULL::uuid AS customer_id,
         u.business_id,
         COALESCE((ARRAY_AGG(u.last_metrics->>'business_name' ORDER BY u.last_seen_at DESC))[1], u.business_id, 'Cuenta externa') AS customer_name,
         NULL::text AS customer_email,
         u.project_id,
         p.code AS project_code,
         p.name AS project_name,
         (ARRAY_AGG(u.app_code ORDER BY u.last_seen_at DESC))[1] AS app_code,
         MAX(u.last_seen_at) AS last_seen_at,
         MIN(u.first_seen_at) AS first_seen_at,
         (ARRAY_AGG(u.app_version ORDER BY u.last_seen_at DESC))[1] AS app_version,
         SUM(u.active_seconds)::bigint AS active_seconds,
         SUM(u.sessions_count)::bigint AS sessions_count,
         SUM(u.events_count)::bigint AS events_count,
         COUNT(DISTINCT u.device_id)::bigint AS devices_count,
         (ARRAY_AGG(u.last_metrics ORDER BY u.last_seen_at DESC))[1] AS last_metrics,
         COALESCE((
           SELECT jsonb_agg(
             jsonb_build_object(
               'platform', platform,
               'events_count', events_count,
               'active_seconds', active_seconds,
               'devices_count', devices_count
             )
             ORDER BY events_count DESC, devices_count DESC, platform ASC
           )
           FROM (
             SELECT
               COALESCE(NULLIF(LOWER(x.last_metrics->>'platform'), ''), 'api') AS platform,
               SUM(x.events_count)::bigint AS events_count,
               SUM(x.active_seconds)::bigint AS active_seconds,
               COUNT(DISTINCT x.device_id)::bigint AS devices_count
             FROM usage_daily_stats x
             WHERE x.business_id = u.business_id
               AND (($${appParam})::text IS NULL OR UPPER(x.app_code) = $${appParam})
               AND ($${fromParam}::text IS NULL OR x.stat_date >= $${fromParam}::date)
               AND ($${toParam}::text IS NULL OR x.stat_date <= $${toParam}::date)
             GROUP BY platform
           ) platform_rows
         ), '[]'::jsonb) AS platform_breakdown
       FROM usage_daily_stats u
       LEFT JOIN projects p ON p.id = u.project_id
       WHERE NOT EXISTS (SELECT 1 FROM linked_usage_keys lk WHERE lk.subject_key = u.subject_key)
         AND ($${appParam}::text IS NULL OR UPPER(u.app_code) = $${appParam})
         AND ($${fromParam}::text IS NULL OR u.stat_date >= $${fromParam}::date)
         AND ($${toParam}::text IS NULL OR u.stat_date <= $${toParam}::date)
         ${projectParam ? `AND p.code = $${projectParam}` : ''}
         ${businessParam ? `AND u.business_id = $${businessParam}` : ''}
       GROUP BY u.business_id, u.project_id, p.code, p.name
     ),
     all_usage AS (
       SELECT * FROM account_usage
       UNION ALL
       SELECT * FROM external_usage
     ),
     with_status AS (
       SELECT *, ${usageStatusSql('all_usage')} AS usage_status
       FROM all_usage
     )
     SELECT *, COUNT(*) OVER()::int AS total
     FROM with_status
     WHERE ($${statusParam}::text IS NULL OR usage_status = $${statusParam})
     ORDER BY last_seen_at DESC NULLS LAST, customer_name ASC
     LIMIT $${limitParam} OFFSET $${offsetParam}`,
    params
  );

  const total = res.rows[0]?.total || 0;
  return { page, limit, total, accounts: res.rows.map(({ total, ...row }) => row) };
}

async function listEvents(query = {}) {
  const page = Math.max(1, Number(query.page || 1) || 1);
  const limit = Math.min(500, Math.max(1, Number(query.limit || 100) || 100));
  const offset = (page - 1) * limit;

  const params = [];
  const where = [];
  function add(value, condition) {
    params.push(value);
    where.push(condition.replace('?', `$${params.length}`));
  }

  const projectCode = String(query.project_code || '').trim().toUpperCase();
  const appCode = String(query.app_code || '').trim().toUpperCase();
  const businessId = String(query.business_id || '').trim();
  const customerId = String(query.customer_id || '').trim();
  const licenseId = String(query.license_id || '').trim();
  const from = String(query.from || '').trim();
  const to = String(query.to || '').trim();

  if (projectCode) add(projectCode, 'p.code = ?');
  if (appCode) add(appCode, 'UPPER(e.app_code) = ?');
  if (businessId) add(businessId, 'e.business_id = ?');
  if (customerId) add(customerId, 'e.customer_id = ?');
  if (licenseId) add(licenseId, 'e.license_id = ?');
  if (from) add(from, 'e.received_at >= ?::date');
  if (to) add(to, 'e.received_at < (?::date + interval \'1 day\')');

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  params.push(limit, offset);

  const res = await pool.query(
    `SELECT
       e.*, p.code AS project_code, p.name AS project_name,
       c.nombre_negocio AS customer_name, l.license_key,
       COUNT(*) OVER()::int AS total
     FROM usage_events e
     LEFT JOIN projects p ON p.id = e.project_id
     LEFT JOIN customers c ON c.id = e.customer_id
     LEFT JOIN licenses l ON l.id = e.license_id
     ${whereSql}
     ORDER BY e.received_at DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );

  const total = res.rows[0]?.total || 0;
  return { page, limit, total, events: res.rows.map(({ total, ...row }) => row) };
}

module.exports = {
  buildSubjectKey,
  resolveUsageContext,
  insertUsageEvent,
  upsertDailyStats,
  upsertFeatureStats,
  getOverview,
  listAccounts,
  listEvents
};
