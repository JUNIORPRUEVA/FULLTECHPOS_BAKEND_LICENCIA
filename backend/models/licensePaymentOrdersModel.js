/**
 * Modelo para license_payment_orders
 * Órdenes de pago de licencia (prepago por tiempo).
 */
const { pool } = require('../db/pool');

/**
 * Crea una orden de pago de licencia.
 */
async function createPaymentOrder({
  customer_id,
  project_id,
  license_id,
  months,
  monthly_price,
  total_amount,
  currency,
  provider,
  provider_order_id,
  checkout_url,
  raw_request,
}) {
  const res = await pool.query(
    `INSERT INTO license_payment_orders
     (customer_id, project_id, license_id, months, monthly_price, total_amount, currency,
      provider, provider_order_id, checkout_url, raw_request, status)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'PENDING')
     RETURNING *`,
    [
      customer_id,
      project_id,
      license_id || null,
      Math.floor(Number(months)),
      Number(monthly_price),
      Number(total_amount),
      String(currency || 'USD').toUpperCase(),
      String(provider || 'paypal').toLowerCase(),
      provider_order_id || null,
      checkout_url || null,
      JSON.stringify(raw_request || {}),
    ]
  );
  return res.rows[0] || null;
}

/**
 * Obtiene una orden de pago por ID.
 */
async function getPaymentOrderById(id) {
  const res = await pool.query(
    `SELECT lpo.*,
            c.nombre_negocio AS customer_name,
            c.email AS customer_email,
            p.code AS project_code,
            p.name AS project_name
     FROM license_payment_orders lpo
     LEFT JOIN customers c ON c.id = lpo.customer_id
     LEFT JOIN projects p ON p.id = lpo.project_id
     WHERE lpo.id = $1`,
    [id]
  );
  return res.rows[0] || null;
}

/**
 * Obtiene una orden de pago por provider_order_id (PayPal order ID).
 */
async function getPaymentOrderByProviderOrderId(providerOrderId) {
  const res = await pool.query(
    `SELECT lpo.*,
            c.nombre_negocio AS customer_name,
            c.email AS customer_email,
            p.code AS project_code,
            p.name AS project_name
     FROM license_payment_orders lpo
     LEFT JOIN customers c ON c.id = lpo.customer_id
     LEFT JOIN projects p ON p.id = lpo.project_id
     WHERE lpo.provider_order_id = $1`,
    [providerOrderId]
  );
  return res.rows[0] || null;
}

/**
 * Actualiza el estado de una orden de pago después de la captura.
 */
async function capturePaymentOrder(id, { provider_capture_id, status, raw_response, paid_at }) {
  const res = await pool.query(
    `UPDATE license_payment_orders
     SET
       provider_capture_id = COALESCE($2, provider_capture_id),
       status = $3,
       raw_response = $4,
       paid_at = $5,
       updated_at = now()
     WHERE id = $1
     RETURNING *`,
    [
      id,
      provider_capture_id || null,
      String(status || 'PAID').toUpperCase(),
      JSON.stringify(raw_response || {}),
      paid_at ? paid_at : (status === 'PAID' ? new Date() : null),
    ]
  );
  return res.rows[0] || null;
}

/**
 * Lista órdenes de pago con filtros opcionales.
 */
async function listPaymentOrders({ limit, offset, status, project_id, customer_id }) {
  const conditions = [];
  const params = [];

  if (status) {
    params.push(String(status).toUpperCase());
    conditions.push(`lpo.status = $${params.length}`);
  }
  if (project_id) {
    params.push(project_id);
    conditions.push(`lpo.project_id = $${params.length}`);
  }
  if (customer_id) {
    params.push(customer_id);
    conditions.push(`lpo.customer_id = $${params.length}`);
  }

  const whereSql = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

  const countRes = await pool.query(
    `SELECT COUNT(*)::int AS total FROM license_payment_orders lpo ${whereSql}`,
    params
  );
  const total = countRes.rows[0]?.total || 0;

  const dataParams = [...params, limit, offset];
  const dataRes = await pool.query(
    `SELECT lpo.*,
            c.nombre_negocio AS customer_name,
            c.email AS customer_email,
            p.code AS project_code,
            p.name AS project_name
     FROM license_payment_orders lpo
     LEFT JOIN customers c ON c.id = lpo.customer_id
     LEFT JOIN projects p ON p.id = lpo.project_id
     ${whereSql}
     ORDER BY lpo.created_at DESC
     LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
    dataParams
  );

  return { total, orders: dataRes.rows };
}

module.exports = {
  createPaymentOrder,
  getPaymentOrderById,
  getPaymentOrderByProviderOrderId,
  capturePaymentOrder,
  listPaymentOrders,
};
