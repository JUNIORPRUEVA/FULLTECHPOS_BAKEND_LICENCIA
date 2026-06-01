/**
 * PayPal REST API Service
 * 
 * Maneja la creación, captura y verificación de órdenes de pago PayPal.
 * Usa las variables de entorno:
 *   PAYPAL_CLIENT_ID
 *   PAYPAL_CLIENT_SECRET (o PAYPAL_SECRET)
 *   PAYPAL_ENV = sandbox | live
 *   PAYPAL_RETURN_URL
 *   PAYPAL_CANCEL_URL
 * 
 * Si PAYPAL_ENV = live, usa api-m.paypal.com
 * Si PAYPAL_ENV = sandbox o no definido, usa api-m.sandbox.paypal.com
 */

const PAYPAL_LIVE = 'https://api-m.paypal.com';
const PAYPAL_SANDBOX = 'https://api-m.sandbox.paypal.com';

function getBaseUrl() {
  const env = String(process.env.PAYPAL_ENV || process.env.PAYPAL_MODE || 'sandbox').trim().toLowerCase();
  return env === 'live' ? PAYPAL_LIVE : PAYPAL_SANDBOX;
}

function getClientId() {
  return String(process.env.PAYPAL_CLIENT_ID || '').trim();
}

function getClientSecret() {
  return String(process.env.PAYPAL_CLIENT_SECRET || process.env.PAYPAL_SECRET || '').trim();
}

/**
 * Obtiene un access token de PayPal usando Client Credentials.
 * @returns {Promise<string>} access_token
 */
async function getAccessToken() {
  const clientId = getClientId();
  const clientSecret = getClientSecret();

  if (!clientId || !clientSecret) {
    throw new Error('PAYPAL_CLIENT_ID y PAYPAL_CLIENT_SECRET son requeridos');
  }

  const base64 = Buffer.from(`${clientId}:${clientSecret}`).toString('base64');
  const url = `${getBaseUrl()}/v1/oauth2/token`;

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${base64}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'grant_type=client_credentials',
  });

  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`PayPal getAccessToken error ${response.status}: ${text || response.statusText}`);
  }

  const data = await response.json();
  return String(data.access_token || '');
}

/**
 * Crea una orden de pago en PayPal.
 * @param {Object} params
 * @param {number} params.amount - Monto total (ej: 45.00)
 * @param {string} params.currency - Código de moneda (ej: USD)
 * @param {string} params.description - Descripción de la orden
 * @param {Object} [params.metadata] - Metadatos adicionales (se guardan en custom_id / invoice_id)
 * @returns {Promise<Object>} { id, status, links, checkout_url }
 */
async function createOrder({ amount, currency, description, metadata }) {
  const accessToken = await getAccessToken();
  const returnUrl = String(process.env.PAYPAL_RETURN_URL || '').trim() || 'https://example.com/paypal/success';
  const cancelUrl = String(process.env.PAYPAL_CANCEL_URL || '').trim() || 'https://example.com/paypal/cancel';
  const brandName = String(process.env.PAYPAL_BRAND_NAME || 'FULLTECH POS').trim();

  const payload = {
    intent: 'CAPTURE',
    purchase_units: [
      {
        description: String(description || 'Compra de licencia').slice(0, 127),
        amount: {
          currency_code: String(currency || 'USD').toUpperCase(),
          value: Number(amount).toFixed(2),
        },
      },
    ],
    payment_source: {
      paypal: {
        experience_context: {
          payment_method_preference: 'IMMEDIATE_PAYMENT_REQUIRED',
          brand_name: brandName,
          locale: 'es-DO',
          landing_page: 'LOGIN',
          user_action: 'PAY_NOW',
          return_url: returnUrl,
          cancel_url: cancelUrl,
        },
      },
    },
  };

  // Agregar custom_id si hay metadata
  if (metadata && metadata.payment_order_id) {
    payload.purchase_units[0].custom_id = String(metadata.payment_order_id).slice(0, 127);
  }
  if (metadata && metadata.invoice_id) {
    payload.purchase_units[0].invoice_id = String(metadata.invoice_id).slice(0, 127);
  }

  const url = `${getBaseUrl()}/v2/checkout/orders`;
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`PayPal createOrder error ${response.status}: ${text || response.statusText}`);
  }

  const data = await response.json();

  // Extraer checkout_url (approve link)
  let checkoutUrl = '';
  if (Array.isArray(data.links)) {
    const approveLink = data.links.find(l => String(l.rel || '').toLowerCase() === 'approve');
    if (approveLink) {
      checkoutUrl = String(approveLink.href || '');
    }
  }

  return {
    id: String(data.id || ''),
    status: String(data.status || ''),
    links: data.links || [],
    checkout_url: checkoutUrl,
  };
}

/**
 * Captura una orden de PayPal previamente aprobada.
 * @param {string} orderId - El ID de la orden de PayPal
 * @returns {Promise<Object>} { id, status, capture_id, payer_email, amount, currency }
 */
async function captureOrder(orderId) {
  const accessToken = await getAccessToken();
  const url = `${getBaseUrl()}/v2/checkout/orders/${encodeURIComponent(String(orderId))}/capture`;

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
  });

  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`PayPal captureOrder error ${response.status}: ${text || response.statusText}`);
  }

  const data = await response.json();

  // Extraer capture_id del primer capture
  let captureId = '';
  let payerEmail = '';
  let capturedAmount = 0;
  let capturedCurrency = 'USD';

  if (data.purchase_units && Array.isArray(data.purchase_units)) {
    for (const pu of data.purchase_units) {
      if (pu.payments && pu.payments.captures && Array.isArray(pu.payments.captures)) {
        for (const cap of pu.payments.captures) {
          if (String(cap.status || '').toUpperCase() === 'COMPLETED') {
            captureId = String(cap.id || '');
            capturedAmount = Number(cap.amount?.value || 0);
            capturedCurrency = String(cap.amount?.currency_code || 'USD');
            break;
          }
        }
      }
    }
  }

  if (data.payer && data.payer.email_address) {
    payerEmail = String(data.payer.email_address);
  }

  return {
    id: String(data.id || ''),
    status: String(data.status || ''),
    capture_id: captureId,
    payer_email: payerEmail,
    amount: capturedAmount,
    currency: capturedCurrency,
    raw: data,
  };
}

/**
 * Verifica el estado de una orden de PayPal.
 * @param {string} orderId - El ID de la orden de PayPal
 * @returns {Promise<Object>} { id, status, ... }
 */
async function verifyOrder(orderId) {
  const accessToken = await getAccessToken();
  const url = `${getBaseUrl()}/v2/checkout/orders/${encodeURIComponent(String(orderId))}`;

  const response = await fetch(url, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
  });

  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`PayPal verifyOrder error ${response.status}: ${text || response.statusText}`);
  }

  const data = await response.json();
  return data;
}

module.exports = {
  getAccessToken,
  createOrder,
  captureOrder,
  verifyOrder,
};
