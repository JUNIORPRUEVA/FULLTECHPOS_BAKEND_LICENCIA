const { pool } = require('../db/pool');

async function createOrder(input, { client = pool } = {}) {
  const res = await client.query(
    `INSERT INTO paypal_orders (
      order_type, user_id, company_id, customer_id, plan_id, product_id, project_id,
      amount, currency, status, description, request_payload
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
    RETURNING *`,
    [
      input.order_type || 'ONE_TIME',
      input.user_id || null,
      input.company_id,
      input.customer_id || null,
      input.plan_id,
      input.product_id || null,
      input.project_id || null,
      input.amount,
      input.currency || 'USD',
      input.status || 'CREATED',
      input.description || null,
      input.request_payload || {}
    ]
  );
  return res.rows[0] || null;
}

async function updateOrderById(id, patch, { client = pool } = {}) {
  const res = await client.query(
    `UPDATE paypal_orders
     SET paypal_order_id = COALESCE($2, paypal_order_id),
         license_id = COALESCE($3, license_id),
         subscription_id = COALESCE($4, subscription_id),
         status = COALESCE($5, status),
         approval_url = COALESCE($6, approval_url),
         paypal_payload = COALESCE($7, paypal_payload),
         captured_at = COALESCE($8, captured_at),
         updated_at = now()
     WHERE id = $1
     RETURNING *`,
    [
      id,
      patch.paypal_order_id || null,
      patch.license_id || null,
      patch.subscription_id || null,
      patch.status || null,
      patch.approval_url || null,
      patch.paypal_payload || null,
      patch.captured_at || null
    ]
  );
  return res.rows[0] || null;
}

async function getOrderByPayPalId(paypalOrderId, { client = pool, forUpdate = false } = {}) {
  if (forUpdate) {
    const res = await client.query('SELECT * FROM paypal_orders WHERE paypal_order_id = $1 FOR UPDATE', [paypalOrderId]);
    return res.rows[0] || null;
  }
  const res = await client.query('SELECT * FROM paypal_orders WHERE paypal_order_id = $1', [paypalOrderId]);
  return res.rows[0] || null;
}

async function markWebhookProcessing(event, { client = pool } = {}) {
  const res = await client.query(
    `INSERT INTO paypal_webhook_events (paypal_event_id, event_type, resource_id, status, payload)
     VALUES ($1,$2,$3,'processing',$4)
     ON CONFLICT (paypal_event_id) DO NOTHING
     RETURNING *`,
    [event.id, event.event_type, event.resource?.id || event.resource?.billing_agreement_id || null, event]
  );
  return res.rows[0] || null;
}

async function markWebhookProcessed(eventId, patch = {}, { client = pool } = {}) {
  const res = await client.query(
    `UPDATE paypal_webhook_events
     SET status = $2,
         error_message = $3,
         processed_at = now()
     WHERE paypal_event_id = $1
     RETURNING *`,
    [eventId, patch.status || 'processed', patch.error_message || null]
  );
  if (res.rows[0]) return res.rows[0];

  const insertRes = await client.query(
    `INSERT INTO paypal_webhook_events (
       paypal_event_id, event_type, resource_id, status, payload, error_message
     ) VALUES ($1,$2,$3,$4,$5,$6)
     ON CONFLICT (paypal_event_id) DO UPDATE
     SET status = EXCLUDED.status,
         error_message = EXCLUDED.error_message,
         processed_at = now()
     RETURNING *`,
    [
      eventId,
      patch.event_type || 'unknown',
      patch.resource_id || null,
      patch.status || 'processed',
      patch.payload || {},
      patch.error_message || null
    ]
  );
  return insertRes.rows[0] || null;
}

module.exports = {
  createOrder,
  updateOrderById,
  getOrderByPayPalId,
  markWebhookProcessing,
  markWebhookProcessed
};
