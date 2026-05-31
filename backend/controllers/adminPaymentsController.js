/**
 * adminPaymentsController.js
 * Controlador admin para listar pagos/órdenes de PayPal.
 */
const { pool } = require('../db/pool');

/**
 * GET /api/admin/payments
 * Lista pagos con paginación y filtros opcionales.
 */
async function listPayments(req, res) {
  try {
    const limit = Math.min(Number.parseInt(req.query.limit) || 50, 200);
    const offset = Math.max(Number.parseInt(req.query.offset) || 0, 0);
    const status = req.query.status || null;
    const search = req.query.search || null;

    let where = 'WHERE 1=1';
    const params = [];
    let paramIndex = 0;

    if (status) {
      paramIndex++;
      where += ` AND po.status = $${paramIndex}`;
      params.push(status);
    }

    if (search) {
      paramIndex++;
      where += ` AND (po.paypal_order_id ILIKE $${paramIndex} OR po.description ILIKE $${paramIndex} OR c.nombre_negocio ILIKE $${paramIndex})`;
      params.push(`%${search}%`);
    }

    const countQuery = `
      SELECT COUNT(*) AS total
      FROM paypal_orders po
      LEFT JOIN customers c ON c.id = po.customer_id
      ${where}
    `;
    const countResult = await pool.query(countQuery, params);
    const total = Number.parseInt(countResult.rows[0]?.total) || 0;

    paramIndex++;
    params.push(limit);
    paramIndex++;
    params.push(offset);

    const dataQuery = `
      SELECT
        po.id,
        po.order_type,
        po.user_id,
        po.company_id,
        po.customer_id,
        COALESCE(c.nombre_negocio, c.nombre_completo, '—') AS customer_name,
        po.plan_id,
        po.product_id,
        po.project_id,
        po.amount,
        po.currency,
        po.status,
        po.description,
        po.paypal_order_id,
        po.subscription_id,
        po.license_id,
        po.approval_url,
        po.captured_at,
        po.created_at,
        po.updated_at
      FROM paypal_orders po
      LEFT JOIN customers c ON c.id = po.customer_id
      ${where}
      ORDER BY po.created_at DESC
      LIMIT $${paramIndex - 1} OFFSET $${paramIndex}
    `;

    const result = await pool.query(dataQuery, params);

    console.log(`[adminPayments] listPayments: ${result.rows.length} payments (total: ${total})`);

    return res.json({
      ok: true,
      payments: result.rows,
      total,
      limit,
      offset,
    });
  } catch (error) {
    console.error('[adminPayments] Error listing payments:', error?.message || error);
    return res.status(500).json({
      ok: false,
      message: 'Error al listar pagos',
    });
  }
}

module.exports = {
  listPayments,
};
