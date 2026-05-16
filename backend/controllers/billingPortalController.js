const { pool } = require('../db/pool');

function httpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function isUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value || '').trim());
}

function isMissingSchemaError(error) {
  return ['42P01', '42703', '42P07'].includes(String(error?.code || ''));
}

async function resolveUserId(req, client) {
  const explicit = req.query.user_id || req.headers['x-user-id'];
  if (explicit) {
    if (!isUuid(explicit)) throw httpError(400, 'user_id inválido');
    return String(explicit).trim();
  }

  const username = String(req.adminUser || '').trim().toLowerCase();
  if (username) {
    const res = await client.query(
      `SELECT id FROM platform_users
       WHERE lower(email) = $1 OR lower(COALESCE(display_name, '')) = $1
       LIMIT 1`,
      [username]
    );
    if (res.rows[0]) return res.rows[0].id;
  }

  throw httpError(401, 'No se pudo identificar el usuario de la sesión');
}

function planBenefits(plan) {
  const benefits = [];
  const devices = Number(plan.metadata?.devices || plan.metadata?.dispositivos || 1);
  benefits.push(`${devices} dispositivo${devices === 1 ? '' : 's'}`);
  if (plan.tipo === 'mensual') benefits.push('Renovación automática mensual');
  if (plan.tipo === 'anual') benefits.push('Renovación automática anual');
  if (plan.tipo === 'permanente') benefits.push('Licencia permanente');
  if (Array.isArray(plan.metadata?.benefits)) {
    for (const benefit of plan.metadata.benefits) {
      if (benefit) benefits.push(String(benefit));
    }
  }
  return benefits;
}

async function listPlans(req, res, next) {
  try {
    const result = await pool.query(
      `SELECT id, nombre, tipo, precio, moneda, activo, paypal_plan_id, metadata
       FROM saas_planes
       WHERE activo = true
       ORDER BY CASE tipo WHEN 'mensual' THEN 1 WHEN 'anual' THEN 2 WHEN 'permanente' THEN 3 ELSE 4 END,
                precio ASC,
                nombre ASC`
    );

    const plans = result.rows.map((plan) => ({
      id: plan.id,
      name: plan.nombre,
      nombre: plan.nombre,
      type: plan.tipo,
      tipo: plan.tipo,
      price: Number(plan.precio || 0),
      precio: Number(plan.precio || 0),
      currency: plan.moneda,
      moneda: plan.moneda,
      is_active: plan.activo,
      paypal_plan_id: plan.paypal_plan_id,
      benefits: planBenefits(plan),
      metadata: plan.metadata || {}
    }));

    return res.json({ ok: true, plans });
  } catch (error) {
    if (isMissingSchemaError(error)) return res.json({ ok: true, plans: [] });
    return next(error);
  }
}

async function listSubscriptions(req, res, next) {
  const client = await pool.connect();
  try {
    const userId = await resolveUserId(req, client);
    const subscriptionsRes = await client.query(
      `SELECT ss.*, sp.nombre AS plan_name, sp.tipo AS plan_type, sp.precio AS plan_price, sp.moneda AS plan_currency
       FROM saas_suscripciones ss
       INNER JOIN saas_planes sp ON sp.id = ss.plan_id
       WHERE ss.user_id = $1
       ORDER BY ss.created_at DESC`,
      [userId]
    );

    const paymentsRes = await client.query(
      `SELECT id, suscripcion_id, paypal_order_id, paypal_payment_id, paypal_subscription_id,
              monto, moneda, estado, fecha_pago, created_at
       FROM saas_pagos
       WHERE user_id = $1
       ORDER BY COALESCE(fecha_pago, created_at) DESC
       LIMIT 25`,
      [userId]
    );

    return res.json({
      ok: true,
      user_id: userId,
      subscriptions: subscriptionsRes.rows,
      history: paymentsRes.rows
    });
  } catch (error) {
    if (isMissingSchemaError(error)) {
      return res.json({ ok: true, subscriptions: [], history: [] });
    }
    return next(error);
  } finally {
    client.release();
  }
}

async function getLicense(req, res, next) {
  const client = await pool.connect();
  try {
    const userId = await resolveUserId(req, client);
    const licenseRes = await client.query(
      `SELECT sl.*, sp.nombre AS plan_name, sp.tipo AS plan_type,
              ss.estado AS subscription_status, ss.proximo_pago
       FROM saas_licencias sl
       LEFT JOIN saas_planes sp ON sp.id = sl.plan_id
       LEFT JOIN saas_suscripciones ss ON ss.id = sl.suscripcion_id
       WHERE sl.user_id = $1
       ORDER BY
         CASE sl.estado WHEN 'activa' THEN 1 WHEN 'inactiva' THEN 2 WHEN 'bloqueada' THEN 3 ELSE 4 END,
         sl.created_at DESC
       LIMIT 1`,
      [userId]
    );

    const license = licenseRes.rows[0] || null;
    const status = license ? String(license.estado || '').toUpperCase() : 'VENCIDA';
    return res.json({
      ok: true,
      user_id: userId,
      license,
      status,
      estado: status,
      premium_enabled: status === 'ACTIVA'
    });
  } catch (error) {
    if (isMissingSchemaError(error)) {
      return res.json({ ok: true, license: null, status: 'VENCIDA', estado: 'VENCIDA', premium_enabled: false });
    }
    return next(error);
  } finally {
    client.release();
  }
}

module.exports = {
  listPlans,
  listSubscriptions,
  getLicense
};
