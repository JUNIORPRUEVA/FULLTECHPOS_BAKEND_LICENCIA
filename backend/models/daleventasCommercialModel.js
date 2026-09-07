const { pool } = require('../db/pool');

const PLAN_CODES = new Set(['BASIC', 'BUSINESS', 'PRO']);
const PLAN_CLASSIFICATIONS = new Set(['LEGACY', 'CUSTOM', 'CATALOG']);
const COMMERCIAL_STATUSES = new Set([
  'DEMO',
  'CONTACTED',
  'INTERESTED',
  'PURCHASED',
  'ACTIVE_CUSTOMER',
  'RENEWAL_DUE',
  'EXPIRED',
  'LOST'
]);
const LEAD_SOURCES = new Set(['WEB', 'WHATSAPP', 'FACEBOOK', 'INSTAGRAM', 'REFERIDO', 'DIRECTO', 'OTRO']);
const PRIMARY_FILTERS = new Set([
  'TODOS',
  'DEMO',
  'COMPRARON',
  'ACTIVOS',
  'POR_VENCER',
  'VENCIDOS',
  'BLOQUEADOS',
  'SEGUIMIENTO'
]);

function normalizeEnum(value, allowed, fieldName, { nullable = true } = {}) {
  if (value == null || value === '') {
    if (nullable) return null;
    throw new Error(`${fieldName} es requerido`);
  }
  const normalized = String(value).trim().toUpperCase();
  if (!allowed.has(normalized)) throw new Error(`${fieldName} invalido`);
  return normalized;
}

function normalizePlanCode(value, { nullable = false } = {}) {
  return normalizeEnum(value, PLAN_CODES, 'planCode', { nullable });
}

function normalizePlanClassification(value, { nullable = false } = {}) {
  return normalizeEnum(value, PLAN_CLASSIFICATIONS, 'planClassification', { nullable });
}

function normalizeCommercialStatus(value, { nullable = false } = {}) {
  return normalizeEnum(value, COMMERCIAL_STATUSES, 'commercialStatus', { nullable });
}

function normalizeLeadSource(value) {
  return normalizeEnum(value, LEAD_SOURCES, 'leadSource', { nullable: true });
}

function safeText(value, max = 5000) {
  if (value == null) return null;
  const v = String(value).trim();
  return v ? v.slice(0, max) : null;
}

function toNullableDate(value, fieldName) {
  if (value == null || value === '') return null;
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) throw new Error(`${fieldName} invalido`);
  return date;
}

function toNullablePositiveInt(value, fieldName) {
  if (value == null || value === '') return null;
  const number = Number(value);
  if (!Number.isInteger(number) || number <= 0) throw new Error(`${fieldName} debe ser mayor que cero`);
  return number;
}

function toNullableNonNegativeInt(value, fieldName) {
  if (value == null || value === '') return null;
  const number = Number(value);
  if (!Number.isInteger(number) || number < 0) throw new Error(`${fieldName} no puede ser negativo`);
  return number;
}

function toNullableMoney(value, fieldName) {
  if (value == null || value === '') return null;
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0) throw new Error(`${fieldName} no puede ser negativo`);
  return number;
}

function toBool(value) {
  if (value == null || value === '') return null;
  if (typeof value === 'boolean') return value;
  const v = String(value).trim().toLowerCase();
  if (['true', '1', 'yes', 'si'].includes(v)) return true;
  if (['false', '0', 'no'].includes(v)) return false;
  return null;
}

function maybeUuid(value) {
  const v = safeText(value, 80);
  if (!v) return null;
  return /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(v)
    ? v
    : null;
}

function getActor(reqLike = {}) {
  return {
    actor_user_id: maybeUuid(reqLike.adminUserId || reqLike.actor_user_id || reqLike.actorUserId),
    actor_type: 'admin_session',
    actor_label: safeText(reqLike.adminUser || reqLike.actor_label || reqLike.actorLabel || 'Appyra Admin', 160),
    ip_address: reqLike.ip || reqLike.ip_address || null,
    user_agent: reqLike.headers?.['user-agent'] || reqLike.user_agent || null
  };
}

function externalCompanyIdFrom(companyOrId) {
  if (typeof companyOrId === 'string' || typeof companyOrId === 'number') return safeText(companyOrId, 160);
  const company = companyOrId || {};
  return safeText(
    company.id ||
      company.companyId ||
      company.company_id ||
      company.businessId ||
      company.business_id ||
      company.license?.companyId,
    160
  );
}

function companyTechnicalSnapshot(company = {}) {
  const limits = company.limits || {};
  const account = company.account || {};
  return {
    external_company_name: safeText(company.name || company.companyName || company.businessName || account.companyName, 500),
    external_company_slug: safeText(company.slug || company.companySlug || account.slug, 240),
    technical_license_status: safeText(company.status || company.licenseStatus || company.license?.status, 80),
    technical_license_expires_at: toNullableDate(
      company.endsAt || company.expiresAt || company.expires_at || company.license?.expiresAt || company.license?.expires_at,
      'technicalLicenseExpiresAt'
    ),
    technical_trial_ends_at: toNullableDate(
      company.trialEndsAt || company.trial_ends_at || company.license?.trialEndsAt || company.license?.trial_ends_at,
      'technicalTrialEndsAt'
    ),
    technical_max_users: toNullablePositiveInt(
      limits.maxUsers || company.maxUsers || company.max_users || company.license?.maxUsers,
      'technicalMaxUsers'
    ),
    technical_max_products: toNullablePositiveInt(
      limits.maxProducts || company.maxProducts || company.max_products || company.license?.maxProducts,
      'technicalMaxProducts'
    ),
    technical_license_key: safeText(company.licenseKey || company.license_key || company.license?.licenseKey, 240)
  };
}

function planSnapshot(plan) {
  return {
    plan_code_snapshot: plan.code,
    plan_name_snapshot: plan.display_name,
    currency_snapshot: plan.currency,
    monthly_equivalent_price_snapshot: plan.monthly_equivalent_price,
    minimum_billing_months_snapshot: plan.minimum_billing_months,
    minimum_payment_snapshot: plan.minimum_payment,
    max_users_snapshot: plan.max_users,
    max_products_snapshot: plan.max_products,
    max_warehouses_snapshot: plan.max_warehouses,
    max_devices_snapshot: plan.max_devices
  };
}

function resolveEffectiveEntitlements(profile = {}) {
  const resolve = (overrideKey, snapshotKey, technicalKey = null) => {
    if (profile[overrideKey] != null) return profile[overrideKey];
    if (profile[snapshotKey] != null) return profile[snapshotKey];
    if (technicalKey && profile[technicalKey] != null) return profile[technicalKey];
    return null;
  };

  const expirationDate =
    profile.override_expiration_date ||
    profile.technical_license_expires_at ||
    profile.technical_trial_ends_at ||
    null;

  return {
    maxUsers: resolve('override_max_users', 'max_users_snapshot', 'technical_max_users'),
    maxProducts: resolve('override_max_products', 'max_products_snapshot', 'technical_max_products'),
    maxWarehouses: resolve('override_max_warehouses', 'max_warehouses_snapshot'),
    maxDevices: resolve('override_max_devices', 'max_devices_snapshot'),
    expirationDate,
    extraDays: profile.override_extra_days ?? null,
    sources: {
      maxUsers: profile.override_max_users != null ? 'override' : profile.max_users_snapshot != null ? 'plan_snapshot' : profile.technical_max_users != null ? 'technical' : 'unconfigured',
      maxProducts: profile.override_max_products != null ? 'override' : profile.max_products_snapshot != null ? 'plan_snapshot' : profile.technical_max_products != null ? 'technical' : 'unconfigured',
      maxWarehouses: profile.override_max_warehouses != null ? 'override' : profile.max_warehouses_snapshot != null ? 'plan_snapshot' : 'unconfigured',
      maxDevices: profile.override_max_devices != null ? 'override' : profile.max_devices_snapshot != null ? 'plan_snapshot' : 'unconfigured',
      expirationDate: profile.override_expiration_date != null ? 'override' : profile.technical_license_expires_at != null ? 'technical' : profile.technical_trial_ends_at != null ? 'technical_trial' : 'unconfigured'
    }
  };
}

function mapProfile(row) {
  if (!row) return null;
  return {
    ...row,
    effective_entitlements: resolveEffectiveEntitlements(row)
  };
}

async function listPlans(filters = {}) {
  const params = [];
  const where = [];
  const active = toBool(filters.active);
  if (active != null) {
    params.push(active);
    where.push(`is_active = $${params.length}`);
  }
  const res = await pool.query(
    `SELECT *
     FROM daleventas_commercial_plans
     ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
     ORDER BY sort_order ASC, code ASC`,
    params
  );
  return res.rows;
}

async function getPlanById(id) {
  const res = await pool.query('SELECT * FROM daleventas_commercial_plans WHERE id = $1', [id]);
  return res.rows[0] || null;
}

async function getPlanByCode(code) {
  const normalized = normalizePlanCode(code);
  const res = await pool.query('SELECT * FROM daleventas_commercial_plans WHERE code = $1', [normalized]);
  return res.rows[0] || null;
}

function planInput(input = {}, { partial = false } = {}) {
  const out = {};
  const hasAny = (...keys) => keys.some((key) => Object.prototype.hasOwnProperty.call(input, key));
  const set = (outputKey, value, ...inputKeys) => {
    if (!partial || hasAny(...inputKeys)) out[outputKey] = value;
  };

  if (!partial || hasAny('code')) set('code', normalizePlanCode(input.code), 'code');
  set('display_name', safeText(input.displayName ?? input.display_name, 160), 'displayName', 'display_name');
  set('description', safeText(input.description, 1000), 'description');
  set('monthly_equivalent_price', toNullableMoney(input.monthlyEquivalentPrice ?? input.monthly_equivalent_price, 'monthlyEquivalentPrice'), 'monthlyEquivalentPrice', 'monthly_equivalent_price');
  set('currency', safeText(input.currency || 'DOP', 12), 'currency');
  set('minimum_billing_months', toNullablePositiveInt(input.minimumBillingMonths ?? input.minimum_billing_months ?? 3, 'minimumBillingMonths'), 'minimumBillingMonths', 'minimum_billing_months');
  set('minimum_payment', toNullableMoney(input.minimumPayment ?? input.minimum_payment, 'minimumPayment'), 'minimumPayment', 'minimum_payment');
  set('trial_days', toNullableNonNegativeInt(input.trialDays ?? input.trial_days ?? 7, 'trialDays'), 'trialDays', 'trial_days');
  set('max_users', toNullablePositiveInt(input.maxUsers ?? input.max_users, 'maxUsers'), 'maxUsers', 'max_users');
  set('max_products', toNullablePositiveInt(input.maxProducts ?? input.max_products, 'maxProducts'), 'maxProducts', 'max_products');
  set('max_warehouses', toNullablePositiveInt(input.maxWarehouses ?? input.max_warehouses, 'maxWarehouses'), 'maxWarehouses', 'max_warehouses');
  set('max_devices', toNullablePositiveInt(input.maxDevices ?? input.max_devices, 'maxDevices'), 'maxDevices', 'max_devices');
  if (!partial || hasAny('isActive', 'is_active')) set('is_active', toBool(input.isActive ?? input.is_active) ?? true, 'isActive', 'is_active');
  set('sort_order', toNullableNonNegativeInt(input.sortOrder ?? input.sort_order ?? 0, 'sortOrder'), 'sortOrder', 'sort_order');
  if (!partial || hasAny('metadata')) set('metadata', input.metadata && typeof input.metadata === 'object' ? input.metadata : {}, 'metadata');

  if (!partial) {
    for (const key of ['display_name', 'monthly_equivalent_price', 'minimum_payment']) {
      if (out[key] == null) throw new Error(`${key} es requerido`);
    }
  }

  return out;
}

async function createPlan(input) {
  const p = planInput(input);
  const res = await pool.query(
    `INSERT INTO daleventas_commercial_plans (
      code, display_name, description, monthly_equivalent_price, currency, minimum_billing_months,
      minimum_payment, trial_days, max_users, max_products, max_warehouses, max_devices,
      is_active, sort_order, metadata
    ) VALUES (
      $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15
    ) RETURNING *`,
    [
      p.code,
      p.display_name,
      p.description,
      p.monthly_equivalent_price,
      p.currency,
      p.minimum_billing_months,
      p.minimum_payment,
      p.trial_days,
      p.max_users,
      p.max_products,
      p.max_warehouses,
      p.max_devices,
      p.is_active,
      p.sort_order,
      p.metadata
    ]
  );
  return res.rows[0] || null;
}

async function updatePlan(id, input) {
  const p = planInput(input, { partial: true });
  delete p.code;
  const allowed = Object.keys(p).filter((key) => p[key] !== undefined);
  if (!allowed.length) return getPlanById(id);
  const params = allowed.map((key) => p[key]);
  params.push(id);
  const sets = allowed.map((key, index) => `${key} = $${index + 1}`);
  const res = await pool.query(
    `UPDATE daleventas_commercial_plans SET ${sets.join(', ')}
     WHERE id = $${params.length}
     RETURNING *`,
    params
  );
  return res.rows[0] || null;
}

async function ensureProfileForCompany(companyOrId, { client = pool } = {}) {
  const externalCompanyId = externalCompanyIdFrom(companyOrId);
  if (!externalCompanyId) throw new Error('externalCompanyId es requerido');
  const technical = typeof companyOrId === 'object' ? companyTechnicalSnapshot(companyOrId) : {};
  const res = await client.query(
    `INSERT INTO daleventas_commercial_profiles (
      external_company_id, external_company_name, external_company_slug,
      technical_license_status, technical_license_expires_at, technical_trial_ends_at,
      technical_max_users, technical_max_products, technical_license_key, last_synced_at
    ) VALUES (
      $1,$2,$3,$4,$5,$6,$7,$8,$9,now()
    )
    ON CONFLICT (external_company_id) DO UPDATE SET
      external_company_name = COALESCE(EXCLUDED.external_company_name, daleventas_commercial_profiles.external_company_name),
      external_company_slug = COALESCE(EXCLUDED.external_company_slug, daleventas_commercial_profiles.external_company_slug),
      technical_license_status = COALESCE(EXCLUDED.technical_license_status, daleventas_commercial_profiles.technical_license_status),
      technical_license_expires_at = COALESCE(EXCLUDED.technical_license_expires_at, daleventas_commercial_profiles.technical_license_expires_at),
      technical_trial_ends_at = COALESCE(EXCLUDED.technical_trial_ends_at, daleventas_commercial_profiles.technical_trial_ends_at),
      technical_max_users = COALESCE(EXCLUDED.technical_max_users, daleventas_commercial_profiles.technical_max_users),
      technical_max_products = COALESCE(EXCLUDED.technical_max_products, daleventas_commercial_profiles.technical_max_products),
      technical_license_key = COALESCE(EXCLUDED.technical_license_key, daleventas_commercial_profiles.technical_license_key),
      last_synced_at = now()
    RETURNING *`,
    [
      externalCompanyId,
      technical.external_company_name || null,
      technical.external_company_slug || null,
      technical.technical_license_status || null,
      technical.technical_license_expires_at || null,
      technical.technical_trial_ends_at || null,
      technical.technical_max_users || null,
      technical.technical_max_products || null,
      technical.technical_license_key || null
    ]
  );
  return mapProfile(res.rows[0]);
}

async function getProfile(externalCompanyId) {
  const res = await pool.query(
    'SELECT * FROM daleventas_commercial_profiles WHERE external_company_id = $1',
    [safeText(externalCompanyId, 160)]
  );
  return mapProfile(res.rows[0]);
}

async function logAudit(client, profile, action, beforeData, afterData, actor, reason) {
  await client.query(
    `INSERT INTO daleventas_commercial_audit_logs (
      profile_id, external_company_id, actor_user_id, actor_type, actor_label,
      action, before_data, after_data, reason, ip_address, user_agent
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
    [
      profile.id,
      profile.external_company_id,
      actor.actor_user_id,
      actor.actor_type,
      actor.actor_label,
      action,
      beforeData || {},
      afterData || {},
      safeText(reason, 1000),
      actor.ip_address || null,
      actor.user_agent || null
    ]
  );
}

function commercialProfilePatch(input = {}) {
  const fields = {};
  if ('commercialStatus' in input || 'commercial_status' in input) {
    fields.commercial_status = normalizeCommercialStatus(input.commercialStatus ?? input.commercial_status);
  }
  if ('leadSource' in input || 'lead_source' in input) fields.lead_source = normalizeLeadSource(input.leadSource ?? input.lead_source);
  if ('firstContactAt' in input || 'first_contact_at' in input) fields.first_contact_at = toNullableDate(input.firstContactAt ?? input.first_contact_at, 'firstContactAt');
  if ('lastContactAt' in input || 'last_contact_at' in input) fields.last_contact_at = toNullableDate(input.lastContactAt ?? input.last_contact_at, 'lastContactAt');
  if ('nextFollowUpAt' in input || 'next_follow_up_at' in input) fields.next_follow_up_at = toNullableDate(input.nextFollowUpAt ?? input.next_follow_up_at, 'nextFollowUpAt');
  if ('convertedAt' in input || 'converted_at' in input) fields.converted_at = toNullableDate(input.convertedAt ?? input.converted_at, 'convertedAt');
  if ('assignedTo' in input || 'assigned_to' in input) fields.assigned_to = maybeUuid(input.assignedTo ?? input.assigned_to);
  if ('commercialNotes' in input || 'commercial_notes' in input) fields.commercial_notes = safeText(input.commercialNotes ?? input.commercial_notes, 10000);
  if ('lostReason' in input || 'lost_reason' in input) fields.lost_reason = safeText(input.lostReason ?? input.lost_reason, 2000);
  return fields;
}

function overridePatch(input = {}) {
  const fields = {};
  if ('expirationDate' in input || 'override_expiration_date' in input) fields.override_expiration_date = toNullableDate(input.expirationDate ?? input.override_expiration_date, 'expirationDate');
  if ('extraDays' in input || 'override_extra_days' in input) fields.override_extra_days = toNullableNonNegativeInt(input.extraDays ?? input.override_extra_days, 'extraDays');
  if ('maxUsers' in input || 'override_max_users' in input) fields.override_max_users = toNullablePositiveInt(input.maxUsers ?? input.override_max_users, 'maxUsers');
  if ('maxProducts' in input || 'override_max_products' in input) fields.override_max_products = toNullablePositiveInt(input.maxProducts ?? input.override_max_products, 'maxProducts');
  if ('maxWarehouses' in input || 'override_max_warehouses' in input) fields.override_max_warehouses = toNullablePositiveInt(input.maxWarehouses ?? input.override_max_warehouses, 'maxWarehouses');
  if ('maxDevices' in input || 'override_max_devices' in input) fields.override_max_devices = toNullablePositiveInt(input.maxDevices ?? input.override_max_devices, 'maxDevices');
  if ('notes' in input || 'override_notes' in input) fields.override_notes = safeText(input.notes ?? input.override_notes, 10000);
  if ('reason' in input || 'override_reason' in input) fields.override_reason = safeText(input.reason ?? input.override_reason, 2000);
  return fields;
}

async function updateProfile(externalCompanyId, input, actorInput) {
  const actor = getActor(actorInput);
  const fields = commercialProfilePatch(input);
  if (!Object.keys(fields).length) return getProfile(externalCompanyId);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const before = await ensureProfileForCompany(externalCompanyId, { client });
    const keys = Object.keys(fields);
    const params = keys.map((key) => fields[key]);
    params.push(before.external_company_id);
    const sets = keys.map((key, index) => `${key} = $${index + 1}`);
    const res = await client.query(
      `UPDATE daleventas_commercial_profiles SET ${sets.join(', ')}
       WHERE external_company_id = $${params.length}
       RETURNING *`,
      params
    );
    const after = mapProfile(res.rows[0]);
    let action = 'CRM_PROFILE_UPDATED';
    if (fields.commercial_status && fields.commercial_status !== before.commercial_status) action = 'COMMERCIAL_STATUS_CHANGED';
    if ('next_follow_up_at' in fields) action = 'FOLLOW_UP_CHANGED';
    await logAudit(client, after, action, before, after, actor, input.reason);
    await client.query('COMMIT');
    return after;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function updateOverrides(externalCompanyId, input, actorInput) {
  const actor = getActor(actorInput);
  const fields = overridePatch(input);
  fields.override_updated_at = new Date();
  fields.override_updated_by = actor.actor_user_id;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const before = await ensureProfileForCompany(externalCompanyId, { client });
    const keys = Object.keys(fields);
    const params = keys.map((key) => fields[key]);
    params.push(before.external_company_id);
    const sets = keys.map((key, index) => `${key} = $${index + 1}`);
    const res = await client.query(
      `UPDATE daleventas_commercial_profiles SET ${sets.join(', ')}
       WHERE external_company_id = $${params.length}
       RETURNING *`,
      params
    );
    const after = mapProfile(res.rows[0]);
    await logAudit(client, after, 'LIMIT_OVERRIDE_CHANGED', before, after, actor, input.reason);
    await client.query('COMMIT');
    return after;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function assignPlan(externalCompanyId, input = {}, actorInput) {
  const actor = getActor(actorInput);
  const plan = input.planId || input.plan_id ? await getPlanById(input.planId || input.plan_id) : await getPlanByCode(input.planCode || input.plan_code);
  if (!plan) throw new Error('Plan no encontrado');
  const status = input.commercialStatus || input.commercial_status
    ? normalizeCommercialStatus(input.commercialStatus ?? input.commercial_status)
    : 'PURCHASED';

  const snap = planSnapshot(plan);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const before = await ensureProfileForCompany(externalCompanyId, { client });
    const res = await client.query(
      `UPDATE daleventas_commercial_profiles SET
        plan_id = $1,
        plan_classification = 'CATALOG',
        plan_code_snapshot = $2,
        plan_name_snapshot = $3,
        currency_snapshot = $4,
        monthly_equivalent_price_snapshot = $5,
        minimum_billing_months_snapshot = $6,
        minimum_payment_snapshot = $7,
        max_users_snapshot = $8,
        max_products_snapshot = $9,
        max_warehouses_snapshot = $10,
        max_devices_snapshot = $11,
        plan_assigned_at = now(),
        plan_assigned_by = $12,
        commercial_status = $13,
        converted_at = COALESCE(converted_at, now())
       WHERE external_company_id = $14
       RETURNING *`,
      [
        plan.id,
        snap.plan_code_snapshot,
        snap.plan_name_snapshot,
        snap.currency_snapshot,
        snap.monthly_equivalent_price_snapshot,
        snap.minimum_billing_months_snapshot,
        snap.minimum_payment_snapshot,
        snap.max_users_snapshot,
        snap.max_products_snapshot,
        snap.max_warehouses_snapshot,
        snap.max_devices_snapshot,
        actor.actor_user_id,
        status,
        before.external_company_id
      ]
    );
    const after = mapProfile(res.rows[0]);
    const action = before.plan_id ? 'PLAN_CHANGED' : 'PLAN_ASSIGNED';
    await logAudit(client, after, action, before, after, actor, input.reason);
    await client.query('COMMIT');
    return after;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

function buildProfileWhere(filters = {}) {
  const params = [];
  const where = [];
  const add = (sql, value) => {
    params.push(value);
    where.push(sql.replace('?', `$${params.length}`));
  };

  const primary = normalizeEnum(filters.primaryFilter || filters.primary || 'TODOS', PRIMARY_FILTERS, 'primaryFilter', { nullable: false });
  if (primary === 'DEMO') add('commercial_status = ?', 'DEMO');
  if (primary === 'COMPRARON') where.push(`commercial_status IN ('PURCHASED', 'ACTIVE_CUSTOMER', 'RENEWAL_DUE')`);
  if (primary === 'ACTIVOS') where.push(`technical_license_status = 'ACTIVE' OR commercial_status = 'ACTIVE_CUSTOMER'`);
  if (primary === 'VENCIDOS') where.push(`technical_license_status = 'EXPIRED' OR commercial_status = 'EXPIRED'`);
  if (primary === 'BLOQUEADOS') add('technical_license_status = ?', 'BLOCKED');
  if (primary === 'SEGUIMIENTO') where.push(`next_follow_up_at IS NOT NULL AND next_follow_up_at <= now()`);
  if (primary === 'POR_VENCER') {
    const days = toNullablePositiveInt(filters.expirationDays || filters.days || 30, 'expirationDays');
    params.push(days);
    where.push(`COALESCE(override_expiration_date, technical_license_expires_at, technical_trial_ends_at) BETWEEN now() AND now() + ($${params.length}::int * interval '1 day')`);
  }

  const plan = safeText(filters.plan || filters.planCode || filters.plan_code, 40);
  if (plan) {
    const normalized = plan.toUpperCase();
    if (normalized === 'LEGACY' || normalized === 'CUSTOM') add('plan_classification = ?', normalized);
    else add('plan_code_snapshot = ?', normalizePlanCode(normalized));
  }

  if (filters.commercialStatus || filters.commercial_status) add('commercial_status = ?', normalizeCommercialStatus(filters.commercialStatus ?? filters.commercial_status));
  if (filters.leadSource || filters.lead_source) add('lead_source = ?', normalizeLeadSource(filters.leadSource ?? filters.lead_source));

  const expiration = safeText(filters.expiration || filters.expirationWindow, 20);
  if (expiration) {
    const map = { HOY: 0, '7': 7, '7_DIAS': 7, '15': 15, '15_DIAS': 15, '30': 30, '30_DIAS': 30 };
    const key = expiration.toUpperCase().replace(/\s+/g, '_');
    const days = map[key];
    if (days == null) throw new Error('expiration invalido');
    if (days === 0) {
      where.push(`COALESCE(override_expiration_date, technical_license_expires_at, technical_trial_ends_at)::date = now()::date`);
    } else {
      params.push(days);
      where.push(`COALESCE(override_expiration_date, technical_license_expires_at, technical_trial_ends_at) BETWEEN now() AND now() + ($${params.length}::int * interval '1 day')`);
    }
  }

  if (filters.q) {
    params.push(`%${String(filters.q).trim()}%`);
    where.push(`(external_company_name ILIKE $${params.length} OR external_company_id ILIKE $${params.length})`);
  }

  return { where, params };
}

async function listProfiles(filters = {}) {
  const limit = Math.min(200, Math.max(1, Number(filters.limit) || 50));
  const offset = Math.max(0, Number(filters.offset) || 0);
  const { where, params } = buildProfileWhere(filters);
  const whereSql = where.length ? `WHERE ${where.map((clause) => `(${clause})`).join(' AND ')}` : '';
  const totalRes = await pool.query(
    `SELECT COUNT(*)::int AS total FROM daleventas_commercial_profiles ${whereSql}`,
    params
  );
  const pageParams = [...params, limit, offset];
  const rowsRes = await pool.query(
    `SELECT *
     FROM daleventas_commercial_profiles
     ${whereSql}
     ORDER BY COALESCE(next_follow_up_at, updated_at) ASC NULLS LAST, updated_at DESC
     LIMIT $${pageParams.length - 1} OFFSET $${pageParams.length}`,
    pageParams
  );
  return { total: totalRes.rows[0]?.total || 0, items: rowsRes.rows.map(mapProfile) };
}

async function listAudit(externalCompanyId, filters = {}) {
  const limit = Math.min(200, Math.max(1, Number(filters.limit) || 50));
  const offset = Math.max(0, Number(filters.offset) || 0);
  const res = await pool.query(
    `SELECT *
     FROM daleventas_commercial_audit_logs
     WHERE external_company_id = $1
     ORDER BY created_at DESC
     LIMIT $2 OFFSET $3`,
    [safeText(externalCompanyId, 160), limit, offset]
  );
  return res.rows;
}

async function decorateCompany(company) {
  try {
    const profile = await ensureProfileForCompany(company);
    return {
      ...company,
      commercial: profile,
      effectiveEntitlements: profile.effective_entitlements
    };
  } catch (error) {
    console.warn('[daleventas-commercial] decorate failed:', error.message || error);
    return company;
  }
}

async function decorateCompanies(companies = []) {
  const out = [];
  for (const company of companies) out.push(await decorateCompany(company));
  return out;
}

module.exports = {
  PLAN_CODES,
  COMMERCIAL_STATUSES,
  LEAD_SOURCES,
  PRIMARY_FILTERS,
  normalizePlanCode,
  normalizeCommercialStatus,
  normalizeLeadSource,
  resolveEffectiveEntitlements,
  buildProfileWhere,
  listPlans,
  getPlanById,
  getPlanByCode,
  createPlan,
  updatePlan,
  ensureProfileForCompany,
  getProfile,
  updateProfile,
  updateOverrides,
  assignPlan,
  listProfiles,
  listAudit,
  decorateCompany,
  decorateCompanies
};
