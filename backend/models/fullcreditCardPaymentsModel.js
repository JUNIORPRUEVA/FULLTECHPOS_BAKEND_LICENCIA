const { pool } = require('../db/pool');

async function findProject() {
  const result = await pool.query(
    `SELECT id, code, currency
       FROM projects
      WHERE UPPER(code) = 'FULLCREDIT' AND is_active = true
      LIMIT 1`
  );
  return result.rows[0] || null;
}

async function hasActiveInstallation({ businessId, deviceId }) {
  const result = await pool.query(
    `SELECT 1
       FROM licenses l
       JOIN projects p ON p.id = l.project_id
       JOIN customers c ON c.id = l.customer_id
       JOIN license_activations a
         ON a.license_id = l.id
        AND a.device_id = $2
        AND a.estado = 'ACTIVA'
      WHERE UPPER(p.code) = 'FULLCREDIT'
        AND c.business_id = $1
        AND l.estado = 'ACTIVA'
        AND (l.fecha_inicio IS NULL OR l.fecha_inicio <= now())
        AND (l.fecha_fin IS NULL OR l.fecha_fin >= now())
      LIMIT 1`,
    [businessId, deviceId]
  );
  return result.rows.length > 0;
}

async function createOrder({
  projectId,
  businessId,
  deviceId,
  paymentReference,
  amount,
  currency,
  publicTokenHash,
}) {
  const result = await pool.query(
    `INSERT INTO fullcredit_card_payment_orders (
       project_id, project_code, business_id, device_id, payment_reference,
       amount, currency, public_token_hash
     )
     VALUES ($1, 'FULLCREDIT', $2, $3, $4, $5, $6, $7)
     ON CONFLICT (project_code, business_id, payment_reference) DO NOTHING
     RETURNING *`,
    [
      projectId,
      businessId,
      deviceId,
      paymentReference,
      amount,
      currency,
      publicTokenHash,
    ]
  );
  return result.rows[0] || null;
}

async function findByReference({ businessId, paymentReference }) {
  const result = await pool.query(
    `SELECT *
       FROM fullcredit_card_payment_orders
      WHERE project_code = 'FULLCREDIT'
        AND business_id = $1
        AND payment_reference = $2
      LIMIT 1`,
    [businessId, paymentReference]
  );
  return result.rows[0] || null;
}

async function findById(id) {
  const result = await pool.query(
    'SELECT * FROM fullcredit_card_payment_orders WHERE id = $1 LIMIT 1',
    [id]
  );
  return result.rows[0] || null;
}

async function findByProviderOrderId(providerOrderId) {
  const result = await pool.query(
    `SELECT *
       FROM fullcredit_card_payment_orders
      WHERE provider_order_id = $1
      LIMIT 1`,
    [providerOrderId]
  );
  return result.rows[0] || null;
}

async function attachProviderOrder(id, { providerOrderId, checkoutUrl, rawResponse }) {
  const result = await pool.query(
    `UPDATE fullcredit_card_payment_orders
        SET provider_order_id = $2,
            checkout_url = $3,
            raw_response = COALESCE(raw_response, '{}'::jsonb) || $4::jsonb,
            updated_at = now()
      WHERE id = $1
      RETURNING *`,
    [id, providerOrderId, checkoutUrl, JSON.stringify(rawResponse || {})]
  );
  return result.rows[0] || null;
}

async function updateStatus(
  id,
  { status, providerCaptureId, rawResponse, paidAt = null }
) {
  const result = await pool.query(
    `UPDATE fullcredit_card_payment_orders
        SET status = $2,
            provider_capture_id = COALESCE($3, provider_capture_id),
            raw_response = COALESCE(raw_response, '{}'::jsonb) || $4::jsonb,
            paid_at = COALESCE($5, paid_at),
            updated_at = now()
      WHERE id = $1
      RETURNING *`,
    [
      id,
      String(status).toUpperCase(),
      providerCaptureId || null,
      JSON.stringify(rawResponse || {}),
      paidAt,
    ]
  );
  return result.rows[0] || null;
}

module.exports = {
  findProject,
  hasActiveInstallation,
  createOrder,
  findByReference,
  findById,
  findByProviderOrderId,
  attachProviderOrder,
  updateStatus,
};
