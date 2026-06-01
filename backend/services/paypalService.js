/**
 * PayPal REST API Service
 * 
 * Maneja la creación, captura y verificación de órdenes de pago PayPal.
 * 
 * Variables de entorno:
 *   PAYPAL_MODE | PAYPAL_ENV  = sandbox | live
 *   PAYPAL_BASE_URL           = override de base URL (opcional)
 *   PAYPAL_CLIENT_ID          = Client ID de la app PayPal
 *   PAYPAL_CLIENT_SECRET      = Client Secret de la app PayPal
 *   PAYPAL_RETURN_URL         = URL de retorno después de pago exitoso
 *   PAYPAL_CANCEL_URL         = URL de retorno después de pago cancelado
 *   PAYPAL_BRAND_NAME         = Nombre de marca (default: "Appyra")
 *   PAYPAL_WEBHOOK_ID         = ID del webhook para verificación de firma
 */

const PAYPAL_LIVE = 'https://api-m.paypal.com';
const PAYPAL_SANDBOX = 'https://api-m.sandbox.paypal.com';

/**
 * Normaliza el modo PayPal (sandbox | live).
 * Soporta PAYPAL_ENV y PAYPAL_MODE.
 */
function getPaypalMode() {
  const mode = (
    process.env.PAYPAL_ENV ||
    process.env.PAYPAL_MODE ||
    'sandbox'
  ).toLowerCase();

  if (mode !== 'sandbox' && mode !== 'live') {
    console.warn(`[paypal] Modo "${mode}" no válido. Usando sandbox.`);
    return 'sandbox';
  }
  return mode;
}

/**
 * Obtiene la base URL de PayPal.
 * Si PAYPAL_BASE_URL está definido, lo usa como override.
 * Si no, usa la URL según el modo.
 */
function getBaseUrl() {
  const override = String(process.env.PAYPAL_BASE_URL || '').trim();
  if (override) return override;

  const mode = getPaypalMode();
  return mode === 'live' ? PAYPAL_LIVE : PAYPAL_SANDBOX;
}

function getClientId() {
  return String(process.env.PAYPAL_CLIENT_ID || '').trim();
}

function getClientSecret() {
  return String(process.env.PAYPAL_CLIENT_SECRET || process.env.PAYPAL_SECRET || '').trim();
}

/**
 * Valida que la configuración de PayPal esté completa.
 * @returns {{ ok: boolean, missing: string[], mode: string, baseUrl: string, clientIdConfigured: boolean, clientSecretConfigured: boolean, returnUrl: string, cancelUrl: string, webhookIdConfigured: boolean, brandName: string }}
 */
function validatePaypalConfig() {
  const missing = [];
  const clientId = getClientId();
  const clientSecret = getClientSecret();
  const returnUrl = String(process.env.PAYPAL_RETURN_URL || '').trim();
  const cancelUrl = String(process.env.PAYPAL_CANCEL_URL || '').trim();
  const webhookId = String(process.env.PAYPAL_WEBHOOK_ID || '').trim();
  const brandName = String(process.env.PAYPAL_BRAND_NAME || 'Appyra').trim();

  if (!clientId) missing.push('PAYPAL_CLIENT_ID');
  if (!clientSecret) missing.push('PAYPAL_CLIENT_SECRET');
  if (!returnUrl) missing.push('PAYPAL_RETURN_URL');
  if (!cancelUrl) missing.push('PAYPAL_CANCEL_URL');

  const mode = getPaypalMode();
  const baseUrl = getBaseUrl();

  return {
    ok: missing.length === 0,
    missing,
    mode,
    baseUrl,
    clientIdConfigured: Boolean(clientId),
    clientSecretConfigured: Boolean(clientSecret),
    returnUrl,
    cancelUrl,
    webhookIdConfigured: Boolean(webhookId),
    brandName,
  };
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
  const brandName = String(process.env.PAYPAL_BRAND_NAME || 'Appyra').trim();

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

  if (!checkoutUrl) {
    throw new Error('PayPal no devolvió un link de aprobación (approve). Verifica la configuración de la app PayPal.');
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

  // Extraer capture_id del primer capture COMPLETED
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
  validatePaypalConfig,
  getPaypalMode,
  getBaseUrl,
};
