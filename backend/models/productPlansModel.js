const { pool } = require('../db/pool');

function normalizeUuid(value) {
  const raw = String(value || '').trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(raw)
    ? raw
    : null;
}

function normalizeText(value, { lower = false, upper = false } = {}) {
  if (value == null) return null;
  let next = String(value).trim();
  if (!next) return null;
  if (lower) next = next.toLowerCase();
  if (upper) next = next.toUpperCase();
  return next;
}

function normalizeJson(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function normalizeOptionalInt(value, fallback = null) {
  if (value == null || value === '') return fallback;
  const next = Number(value);
  if (!Number.isFinite(next)) throw new Error('valor numérico inválido');
  return Math.floor(next);
}

function normalizeOptionalAmount(value, fallback = null) {
  if (value == null || value === '') return fallback;
  const next = Number(value);
  if (!Number.isFinite(next)) throw new Error('price_amount inválido');
  return next;
}

function sanitizePlanInput(input, { partial = false } = {}) {
  const payload = input || {};
  const productId = payload.product_id === undefined ? undefined : normalizeUuid(payload.product_id);
  const projectId = payload.project_id === undefined ? undefined : normalizeUuid(payload.project_id);

  if (!partial || payload.product_id !== undefined || payload.project_id !== undefined) {
    const productProvided = productId != null;
    const projectProvided = projectId != null;
    if (productProvided === projectProvided) {
      throw new Error('Debe enviar exactamente uno entre product_id o project_id');
    }
  }

  const code = payload.code === undefined ? undefined : normalizeText(payload.code, { lower: true });
  const name = payload.name === undefined ? undefined : normalizeText(payload.name);
  const billingPeriod = payload.billing_period === undefined ? undefined : normalizeText(payload.billing_period, { lower: true });
  const currency = payload.currency === undefined ? undefined : normalizeText(payload.currency, { upper: true });
  const trialDays = payload.trial_days === undefined ? undefined : normalizeOptionalInt(payload.trial_days);
  const defaultGraceDays = payload.default_grace_days === undefined ? undefined : normalizeOptionalInt(payload.default_grace_days);
  const deviceLimit = payload.device_limit === undefined ? undefined : normalizeOptionalInt(payload.device_limit);
  const companyLimit = payload.company_limit === undefined ? undefined : normalizeOptionalInt(payload.company_limit);
  const priceAmount = payload.price_amount === undefined ? undefined : normalizeOptionalAmount(payload.price_amount);
  const isActive = payload.is_active === undefined ? undefined : Boolean(payload.is_active);

  if (!partial) {
    if (!code) throw new Error('code es requerido');
    if (!name) throw new Error('name es requerido');
    if (!billingPeriod) throw new Error('billing_period es requerido');
    if (!['trial', 'monthly', 'annual', 'lifetime'].includes(billingPeriod)) {
      throw new Error('billing_period inválido');
    }
    if (!Number.isFinite(priceAmount) || priceAmount < 0) {
      throw new Error('price_amount inválido');
    }
  } else if (billingPeriod && !['trial', 'monthly', 'annual', 'lifetime'].includes(billingPeriod)) {
    throw new Error('billing_period inválido');
  }

  return {
    product_id: productId,
    project_id: projectId,
    code,
    name,
    billing_period: billingPeriod,
    price_amount: priceAmount,
    currency: currency || undefined,
    device_limit: deviceLimit,
    company_limit: companyLimit,
    default_grace_days: defaultGraceDays,
    trial_days: trialDays,
    is_active: isActive,
    metadata: payload.metadata === undefined ? undefined : normalizeJson(payload.metadata)
  };
}

function selectBase() {
  return `
    SELECT pp.*, p.slug AS product_slug, p.name AS product_name,
           pr.code AS project_code, pr.name AS project_name
    FROM product_plans pp
    LEFT JOIN products p ON p.id = pp.product_id
    LEFT JOIN projects pr ON pr.id = pp.project_id
  `;
}

async function list({ product_id, project_id, is_active, q, limit = 50, offset = 0 } = {}) {
  const params = [];
  const where = [];

  if (product_id) {
    params.push(product_id);
    where.push(`pp.product_id = $${params.length}`);
  }
  if (project_id) {
    params.push(project_id);
    where.push(`pp.project_id = $${params.length}`);
  }
  if (is_active !== undefined) {
    params.push(Boolean(is_active));
    where.push(`pp.is_active = $${params.length}`);
  }
  if (q) {
    params.push(`%${String(q).trim().toLowerCase()}%`);
    where.push(`(lower(pp.name) LIKE $${params.length} OR lower(pp.code) LIKE $${params.length})`);
  }

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const totalRes = await pool.query(
    `SELECT COUNT(*)::int AS total FROM product_plans pp ${whereSql}`,
    params
  );

  params.push(limit, offset);
  const rowsRes = await pool.query(
    `${selectBase()}
     ${whereSql}
     ORDER BY pp.updated_at DESC, pp.created_at DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );

  return { total: totalRes.rows[0]?.total || 0, plans: rowsRes.rows };
}

async function getById(id, { client = pool } = {}) {
  const res = await client.query(`${selectBase()} WHERE pp.id = $1`, [id]);
  return res.rows[0] || null;
}

async function create(input, { client = pool } = {}) {
  const data = sanitizePlanInput(input);
  const res = await client.query(
    `INSERT INTO product_plans (
      product_id, project_id, code, name, billing_period, price_amount, currency,
      device_limit, company_limit, default_grace_days, trial_days, is_active, metadata
    ) VALUES (
      $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13
    ) RETURNING *`,
    [
      data.product_id,
      data.project_id,
      data.code,
      data.name,
      data.billing_period,
      data.price_amount,
      data.currency || 'DOP',
      data.device_limit == null ? 1 : data.device_limit,
      data.company_limit == null ? 1 : data.company_limit,
      data.default_grace_days == null ? 0 : data.default_grace_days,
      data.trial_days,
      data.is_active === undefined ? true : data.is_active,
      data.metadata === undefined ? {} : data.metadata
    ]
  );
  return getById(res.rows[0].id, { client });
}

async function update(id, patch, { client = pool } = {}) {
  const current = await getById(id, { client });
  if (!current) return null;
  const data = sanitizePlanInput(patch, { partial: true });

  const nextProductId = patch.product_id === undefined ? current.product_id : data.product_id;
  const nextProjectId = patch.project_id === undefined ? current.project_id : data.project_id;
  if ((nextProductId ? 1 : 0) === (nextProjectId ? 1 : 0)) {
    throw new Error('El plan debe mantener exactamente uno entre product_id o project_id');
  }

  const res = await client.query(
    `UPDATE product_plans
     SET product_id = $2,
         project_id = $3,
         code = $4,
         name = $5,
         billing_period = $6,
         price_amount = $7,
         currency = $8,
         device_limit = $9,
         company_limit = $10,
         default_grace_days = $11,
         trial_days = $12,
         is_active = $13,
         metadata = $14,
         updated_at = now()
     WHERE id = $1
     RETURNING *`,
    [
      id,
      nextProductId,
      nextProjectId,
      data.code || current.code,
      data.name || current.name,
      data.billing_period || current.billing_period,
      data.price_amount == null ? current.price_amount : data.price_amount,
      data.currency || current.currency,
      data.device_limit == null ? current.device_limit : data.device_limit,
      data.company_limit == null ? current.company_limit : data.company_limit,
      data.default_grace_days == null ? current.default_grace_days : data.default_grace_days,
      patch.trial_days === undefined ? current.trial_days : data.trial_days,
      data.is_active === undefined ? current.is_active : data.is_active,
      data.metadata === undefined ? current.metadata : data.metadata
    ]
  );
  return getById(res.rows[0].id, { client });
}

async function setActive(id, isActive, { client = pool } = {}) {
  const res = await client.query(
    `UPDATE product_plans SET is_active = $2, updated_at = now() WHERE id = $1 RETURNING *`,
    [id, Boolean(isActive)]
  );
  return res.rows[0] ? getById(id, { client }) : null;
}

module.exports = {
  list,
  getById,
  create,
  update,
  setActive
};