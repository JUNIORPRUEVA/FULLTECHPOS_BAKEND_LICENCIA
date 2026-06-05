/**
 * FULLTECH POS WEB - Backend Server
 * Servidor Express con panel administrativo para gestionar descargas de instaladores
 * 
 * Puerto: 3000 (admin + API)
 * Puerto: 8000 (archivos estáticos públicos - continúa con Python HTTP server)
 */

const express = require('express');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const bodyParser = require('body-parser');
// Load env (SAFER DEFAULT): use .env unless explicitly told otherwise.
// This avoids accidentally connecting to localhost when .env.local contains placeholders.
const rootDir = path.join(__dirname, '..');

function resolveDotenvPath() {
  const override = process.env.DOTENV_PATH;
  if (override) {
    return path.isAbsolute(override) ? override : path.join(rootDir, override);
  }

  const useLocal = String(process.env.USE_DOTENV_LOCAL || '').trim() === '1';
  const envLocal = path.join(rootDir, '.env.local');
  const env = path.join(rootDir, '.env');

  if (useLocal && fs.existsSync(envLocal)) return envLocal;
  return env;
}

const dotenvPath = resolveDotenvPath();
require('dotenv').config({ path: dotenvPath });
console.log(`Using env file: ${dotenvPath}`);

const LICENSE_ONLY = String(process.env.LICENSE_ONLY || '').trim() === '1';

const sessions = require('./auth/sessions');
const uploadRoutes = require('./routes/uploads');
const adminCustomersRoutes = require('./routes/adminCustomersRoutes');
const adminBusinessesRoutes = require('./routes/adminBusinessesRoutes');
const adminLicensesRoutes = require('./routes/adminLicensesRoutes');
const adminLicenseConfigRoutes = require('./routes/adminLicenseConfigRoutes');
const adminActivationsRoutes = require('./routes/adminActivationsRoutes');
const adminProjectsRoutes = require('./routes/adminProjectsRoutes');
const adminPaymentsRoutes = require('./routes/adminPaymentsRoutes');
const adminLicensePaymentsRoutes = require('./routes/adminLicensePaymentsRoutes');
const adminDashboardRoutes = require('./routes/adminDashboardRoutes');
const licensesPublicRoutes = require('./routes/licensesPublicRoutes');
const activationsRoutes = require('./routes/activationsRoutes');
const paypalRoutes = require('./routes/paypalRoutes');
const billingPortalRoutes = require('./routes/billingPortalRoutes');
const licenseValidationRoutes = require('./routes/licenseValidationRoutes');
const businessesRoutes = require('./routes/businessesRoutes');
const adminProductsRoutes = require('./routes/adminProductsRoutes');
const adminPlatformUsersRoutes = require('./routes/adminPlatformUsersRoutes');
const adminRolesRoutes = require('./routes/adminRolesRoutes');
const adminStoreSettingsRoutes = require('./routes/adminStoreSettingsRoutes');
const adminSupportResetRoutes = require('./routes/adminSupportResetRoutes');
const adminSupportMessageConfigRoutes = require('./routes/adminSupportMessageConfigRoutes');
const storePublicRoutes = require('./routes/storePublicRoutes');
const publicAssetsRoutes = require('./routes/publicAssetsRoutes');
const passwordResetRoutes = require('./routes/passwordResetRoutes');
const supportRequestRoutes = require('./routes/supportRequestRoutes');
const publicLicenseRoutes = require('./routes/publicLicenseRoutes');

// Módulos opcionales (solo cuando se usa el backend completo)
const authRoutes = LICENSE_ONLY ? null : require('./routes/authRoutes');
const syncRoutes = LICENSE_ONLY ? null : require('./modules/sync/sync.routes');
const backupRoutes = LICENSE_ONLY ? null : require('./modules/backup/backup.routes');
const { pool } = require('./db/pool');
const { runMigrations } = require('./db/runMigrations');
const { rateLimit } = require('./middleware/rateLimit');

const app = express();
const ADMIN_PORT = Number.parseInt(process.env.PORT || '3000', 10);

function readEnvValue(name) {
  const value = process.env[name];
  return typeof value === 'string' ? value.trim() : '';
}

function readEnvValueFromFile(name) {
  const filePath = readEnvValue(`${name}_FILE`);
  if (!filePath) return '';
  try {
    return fs.readFileSync(filePath, 'utf8').trim();
  } catch (error) {
    console.warn(`[SECURITY] Could not read ${name}_FILE at ${filePath}: ${error.message || error}`);
    return '';
  }
}

function resolveFirstNonEmpty(names, fallback = '') {
  for (const name of names) {
    const fromEnv = readEnvValue(name);
    if (fromEnv) return fromEnv;
    const fromFile = readEnvValueFromFile(name);
    if (fromFile) return fromFile;
  }
  return fallback;
}

function createDerivedAdminCredentials() {
  const seedParts = [
    readEnvValue('DATABASE_URL'),
    readEnvValue('PG_HOST'),
    readEnvValue('PG_DATABASE'),
    readEnvValue('EVOLUTION_API_KEY'),
    readEnvValue('EVOLUTION_OWNER_NUMBER'),
    readEnvValue('LICENSE_SIGN_PRIVATE_KEY_FILE'),
    readEnvValue('PORT'),
    process.cwd(),
  ].filter(Boolean);

  const seed = seedParts.join('|') || 'fulltech-pos-fallback-admin';
  const hash = crypto.createHash('sha256').update(seed).digest('hex');
  return {
    username: `admin-${hash.slice(0, 10)}`,
    password: `${hash.slice(10, 26)}!${hash.slice(26, 34)}Aa1`,
    source: 'derived'
  };
}

const DEFAULT_ADMIN_USERNAME = 'fulltechsd@gmail.com';
const DEFAULT_ADMIN_PASSWORD = 'Ayleen10';

function getAdminCredentials() {
  const username = resolveFirstNonEmpty(['ADMIN_USERNAME', 'ADMIN_USER', 'ADMIN_EMAIL']);
  const password = resolveFirstNonEmpty(['ADMIN_PASSWORD', 'ADMIN_PASS', 'ADMIN_SECRET']);
  const nodeEnv = String(process.env.NODE_ENV || '').toLowerCase();
  const isProduction = nodeEnv === 'production';

  if (isProduction) {
    const missingUsername = !username;
    const usesDefaultPassword = !password || password === DEFAULT_ADMIN_PASSWORD;
    if (missingUsername || usesDefaultPassword) {
      return createDerivedAdminCredentials();
    }
  }

  if (username && password) {
    return { username, password, source: 'explicit' };
  }

  if (isProduction) {
    return createDerivedAdminCredentials();
  }

  return {
    username: username || DEFAULT_ADMIN_USERNAME,
    password: password || DEFAULT_ADMIN_PASSWORD,
    source: 'default'
  };
}

// ==========================================
// SECURITY STARTUP CHECKS
// ==========================================
(function checkProductionSecrets() {
  const NODE_ENV = String(process.env.NODE_ENV || '').toLowerCase();
  const isProduction = NODE_ENV === 'production';
  const adminCredentials = getAdminCredentials();

  const blockingWarnings = [];
  const advisoryWarnings = [];

  if (!adminCredentials.username || adminCredentials.source === 'default') {
    blockingWarnings.push('ADMIN_USERNAME is not explicitly configured - set it in production');
  } else if (isProduction && adminCredentials.username === DEFAULT_ADMIN_USERNAME) {
    advisoryWarnings.push('ADMIN_USERNAME uses the default email; this is allowed only because ADMIN_PASSWORD is explicit and non-default');
  }
  if (!adminCredentials.password || adminCredentials.source === 'default' || adminCredentials.password === DEFAULT_ADMIN_PASSWORD) {
    blockingWarnings.push('ADMIN_PASSWORD is using the default value — set a strong password in production');
  }
  if (!process.env.DATABASE_URL) {
    advisoryWarnings.push('DATABASE_URL is not set — using individual PG* env vars');
  }
  if (!process.env.CORS_ORIGINS && isProduction) {
    advisoryWarnings.push('CORS_ORIGINS is not set — all origins are allowed (unsafe in production)');
  }
  if (isProduction && adminCredentials.source === 'derived') {
    advisoryWarnings.push('ADMIN credentials were not configured; generated deterministic runtime credentials from deploy secrets');
  }

  const warnings = [...blockingWarnings, ...advisoryWarnings];

  if (warnings.length) {
    const tag = isProduction ? '🚨 [SECURITY]' : '⚠️  [SECURITY]';
    console.warn(`\n${tag} Security configuration warnings:`);
    warnings.forEach((w) => console.warn(`   • ${w}`));
    if (isProduction && blockingWarnings.length) {
      console.error('   • Expected env vars in EasyPanel: ADMIN_USERNAME + ADMIN_PASSWORD');
      console.error('   • Also supported: ADMIN_USER / ADMIN_EMAIL and ADMIN_PASS / ADMIN_SECRET');
      console.error('   • File secrets are supported too: ADMIN_USERNAME_FILE / ADMIN_PASSWORD_FILE');
      console.error('\n[SECURITY] Refusing to start in production with default credentials.');
      process.exit(1);
    }
    if (isProduction && adminCredentials.source === 'derived') {
      console.warn(`   • Derived admin username: ${adminCredentials.username}`);
      console.warn(`   • Derived admin password: ${adminCredentials.password}`);
    }
    console.warn('');
  }
})();

function setNoCacheHeaders(res) {
  res.set('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
  res.set('Pragma', 'no-cache');
  res.set('Expires', '0');
  res.set('Surrogate-Control', 'no-store');
}

function setStaticFreshnessHeaders(res, filePath) {
  const ext = path.extname(String(filePath || '')).toLowerCase();
  const noStoreExts = new Set(['.html', '.css', '.js', '.webmanifest']);
  if (noStoreExts.has(ext)) {
    setNoCacheHeaders(res);
    return;
  }

  if (ext === '.png' || ext === '.jpg' || ext === '.jpeg' || ext === '.svg' || ext === '.webp' || ext === '.gif' || ext === '.ico') {
    res.set('Cache-Control', 'public, max-age=300, must-revalidate');
  }
}

// Behind reverse proxies (EasyPanel), this enables correct protocol detection.
// Important for secure cookies and accurate request logging.
app.set('trust proxy', 1);

// ==========================================
// HEALTH CHECKS (containers / EasyPanel)
// ==========================================
// Nota: algunos orquestadores reinician el contenedor si el healthcheck devuelve 404.
// Mantenerlo simple y rápido.
function sendHealth(req, res) {
  res.json({ ok: true, status: 'up', ts: new Date().toISOString() });
}

app.get('/api/health', sendHealth);

// Aliases por compatibilidad (algunos servicios prueban rutas distintas).
app.get(['/health', '/ready', '/readiness', '/ping', '/status'], sendHealth);

// Diagnóstico opcional de DB. No usar como healthcheck estricto.
app.get('/api/health/db', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    return res.json({ ok: true, db: 'up', ts: new Date().toISOString() });
  } catch (e) {
    return res.status(200).json({ ok: true, db: 'down', error: e?.code || e?.message || 'DB_ERROR' });
  }
});

app.get('/health/db', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    return res.json({ ok: true, db: 'up', ts: new Date().toISOString() });
  } catch (e) {
    return res.status(200).json({ ok: true, db: 'down', error: e?.code || e?.message || 'DB_ERROR' });
  }
});

const licensePaymentOrdersModel = require('./models/licensePaymentOrdersModel');
const licensesModel = require('./models/licensesModel');
const paypalService = require('./services/paypalService');
const FULLPOS_PROTOCOL_URL = 'fullpos://payment/result';

function getPublicBaseUrl(req) {
  const protoHeader = String(req.headers['x-forwarded-proto'] || '').trim();
  const proto = protoHeader || req.protocol || 'https';
  const host = String(req.headers['x-forwarded-host'] || req.get('host') || '').trim();
  return `${proto}://${host}`.replace(/\/+$/, '');
}

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

app.get('/paypal/card-checkout', async (req, res) => {
  try {
    const paymentOrderId = String(req.query.payment_order_id || '').trim();
    const paypalOrderId = String(req.query.paypal_order_id || '').trim();

    let localOrder = null;
    if (paymentOrderId) {
      localOrder = await licensePaymentOrdersModel.getPaymentOrderById(paymentOrderId);
    }
    if (!localOrder && paypalOrderId) {
      localOrder = await licensePaymentOrdersModel.getPaymentOrderByProviderOrderId(paypalOrderId);
    }

    if (!localOrder) {
      return res.type('html').send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Pago no disponible</title>
<style>body{font-family:Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#f6f8fb}.card{background:#fff;border-radius:18px;padding:36px;max-width:540px;text-align:center;box-shadow:0 12px 40px rgba(15,23,42,.12)}h1{color:#dc2626;margin:0 0 14px}p{color:#475569;line-height:1.6}.btn{display:inline-block;margin-top:20px;padding:12px 22px;background:#2563eb;color:#fff;text-decoration:none;border-radius:10px}</style></head>
<body><div class="card"><h1>No encontramos tu compra</h1><p>Esta orden ya no está disponible. Vuelve a FULLPOS e intenta crear una compra nueva.</p><a href="${FULLPOS_PROTOCOL_URL}?status=missing_order" class="btn">Volver a FULLPOS</a></div></body></html>`);
    }

    if (String(localOrder.status || '').toUpperCase() === 'PAID') {
      return res.type('html').send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Pago confirmado</title>
<style>body{font-family:Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#f6f8fb}.card{background:#fff;border-radius:18px;padding:36px;max-width:540px;text-align:center;box-shadow:0 12px 40px rgba(15,23,42,.12)}h1{color:#16a34a;margin:0 0 14px}p{color:#475569;line-height:1.6}.btn{display:inline-block;margin-top:20px;padding:12px 22px;background:#16a34a;color:#fff;text-decoration:none;border-radius:10px}</style></head>
<body><div class="card"><h1>Pago ya confirmado</h1><p>Tu licencia ya está activa. Puedes volver a FULLPOS.</p><a href="${FULLPOS_PROTOCOL_URL}?status=paid" class="btn">Volver a FULLPOS</a></div></body></html>`);
    }

    const clientToken = await paypalService.generateClientToken();
    const clientId = String(process.env.PAYPAL_CLIENT_ID || '').trim();
    const currency = escapeHtml(String(localOrder.currency || 'USD').toUpperCase());
    const amount = escapeHtml(Number(localOrder.total_amount || 0).toFixed(2));
    const months = escapeHtml(localOrder.months);
    const paymentId = escapeHtml(localOrder.id);
    const orderId = escapeHtml(localOrder.provider_order_id || paypalOrderId);
    const appBackUrl = `${FULLPOS_PROTOCOL_URL}?status=cancelled`;
    const fallbackPaypalUrl = escapeHtml(localOrder.checkout_url || '');
    const publicBaseUrl = getPublicBaseUrl(req);
    const captureUrl = `${publicBaseUrl}/api/public/license-payments/capture-paypal-order`;

    if (!clientId || !orderId) {
      return res.type('html').send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Pago no disponible</title>
<style>body{font-family:Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#f6f8fb}.card{background:#fff;border-radius:18px;padding:36px;max-width:540px;text-align:center;box-shadow:0 12px 40px rgba(15,23,42,.12)}h1{color:#dc2626;margin:0 0 14px}p{color:#475569;line-height:1.6}.btn{display:inline-block;margin-top:20px;padding:12px 22px;background:#2563eb;color:#fff;text-decoration:none;border-radius:10px}</style></head>
<body><div class="card"><h1>No pudimos preparar el pago</h1><p>Faltan datos para mostrar el formulario de tarjeta. Vuelve a FULLPOS e intenta de nuevo.</p><a href="${FULLPOS_PROTOCOL_URL}?status=error" class="btn">Volver a FULLPOS</a></div></body></html>`);
    }

    return res.type('html').send(`<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>Pagar licencia</title>
  <script src="https://www.paypal.com/sdk/js?client-id=${encodeURIComponent(clientId)}&components=buttons,card-fields&currency=${encodeURIComponent(currency)}&intent=capture&commit=true" data-client-token="${escapeHtml(clientToken)}"></script>
  <style>
    :root{color-scheme:light}
    *{box-sizing:border-box}
    body{margin:0;font-family:Arial,sans-serif;background:linear-gradient(135deg,#eef5ff 0%,#f8fbff 55%,#fff8f1 100%);min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px;color:#142033}
    .shell{width:min(100%,960px);display:grid;grid-template-columns:minmax(0,1.15fr) minmax(320px,.85fr);gap:20px}
    .panel{background:rgba(255,255,255,.94);border:1px solid rgba(209,226,238,.95);border-radius:24px;box-shadow:0 18px 48px rgba(15,23,42,.12)}
    .main{padding:28px}
    .aside{padding:24px}
    h1{margin:0 0 8px;font-size:34px;line-height:1.05}
    .lead{margin:0 0 22px;color:#5b6b82;line-height:1.55}
    .badge{display:inline-flex;align-items:center;gap:8px;padding:8px 12px;border-radius:999px;background:#eff6ff;color:#1d4ed8;font-weight:700;font-size:12px;margin-bottom:16px}
    .summary{display:grid;gap:12px;margin-bottom:22px}
    .summaryCard{padding:14px 16px;border-radius:16px;background:#f8fbff;border:1px solid #d9e2ee}
    .summaryLabel{font-size:12px;color:#6b7b91;font-weight:700;text-transform:uppercase;letter-spacing:.04em}
    .summaryValue{margin-top:6px;font-size:20px;font-weight:800}
    .fieldLabel{display:block;font-size:12px;font-weight:700;color:#6b7b91;margin:10px 0 6px}
    .paypal-field{min-height:48px;border:1px solid #cfdceb;border-radius:14px;padding:14px 16px;background:#fff}
    .row{display:grid;grid-template-columns:1fr 1fr;gap:12px}
    .payBtn{margin-top:18px;width:100%;border:none;border-radius:14px;background:#b96534;color:#fff;font-weight:800;font-size:17px;padding:16px 18px;cursor:pointer;transition:transform .16s ease, box-shadow .16s ease, opacity .16s ease;box-shadow:0 12px 24px rgba(185,101,52,.24)}
    .payBtn:hover{transform:translateY(-1px)}
    .payBtn:disabled{opacity:.6;cursor:not-allowed;transform:none;box-shadow:none}
    .hint{margin-top:12px;font-size:13px;color:#5b6b82;line-height:1.5}
    .error,.success{display:none;margin-top:14px;padding:14px 16px;border-radius:14px;font-size:14px;line-height:1.5}
    .error{background:#fff1f1;border:1px solid #fecaca;color:#b91c1c}
    .success{background:#edfdf3;border:1px solid #bbf7d0;color:#166534}
    .linkBtn{display:inline-flex;align-items:center;justify-content:center;width:100%;margin-top:12px;padding:12px 16px;border-radius:12px;text-decoration:none;font-weight:700;border:1px solid #d9e2ee;color:#153e75;background:#fff}
    .mini{font-size:12px;color:#6b7b91;line-height:1.5}
    .spinner{display:none;width:18px;height:18px;border:2px solid rgba(255,255,255,.32);border-top-color:#fff;border-radius:999px;animation:spin .75s linear infinite}
    .payBtn.loading .spinner{display:inline-block}
    .payBtn.loading .btnText{opacity:.9}
    @keyframes spin{to{transform:rotate(360deg)}}
    @media (max-width:860px){.shell{grid-template-columns:1fr}.aside{order:-1}.row{grid-template-columns:1fr}}
  </style>
</head>
<body>
  <div class="shell">
    <section class="panel main">
      <div class="badge">Pago rápido con tarjeta</div>
      <h1>Completa tu compra</h1>
      <p class="lead">Ingresa tu tarjeta y confirma el pago. Al aprobarse, FULLPOS activará tu licencia automáticamente.</p>

      <label class="fieldLabel" for="card-name-field-container">Nombre en la tarjeta</label>
      <div id="card-name-field-container" class="paypal-field"></div>

      <label class="fieldLabel" for="card-number-field-container">Número de tarjeta</label>
      <div id="card-number-field-container" class="paypal-field"></div>

      <div class="row">
        <div>
          <label class="fieldLabel" for="card-expiry-field-container">Vencimiento</label>
          <div id="card-expiry-field-container" class="paypal-field"></div>
        </div>
        <div>
          <label class="fieldLabel" for="card-cvv-field-container">CVV</label>
          <div id="card-cvv-field-container" class="paypal-field"></div>
        </div>
      </div>

      <button id="payButton" class="payBtn" type="button" disabled>
        <span class="spinner"></span>
        <span class="btnText">Pagar ahora</span>
      </button>

      <div id="errorBox" class="error"></div>
      <div id="successBox" class="success"></div>

      <a class="linkBtn" href="${fallbackPaypalUrl || `${FULLPOS_PROTOCOL_URL}?status=cancelled`}">${fallbackPaypalUrl ? 'Prefiero pagar con PayPal' : 'Volver a FULLPOS'}</a>
      <p class="hint">Si el pago se aprueba, esta ventana te permitirá volver a FULLPOS al instante.</p>
    </section>

    <aside class="panel aside">
      <div class="summary">
        <div class="summaryCard">
          <div class="summaryLabel">Total a pagar</div>
          <div class="summaryValue">${amount} ${currency}</div>
        </div>
        <div class="summaryCard">
          <div class="summaryLabel">Tiempo de licencia</div>
          <div class="summaryValue">${months} meses</div>
        </div>
      </div>
      <p class="mini">Orden interna: ${paymentId}<br/>Orden PayPal: ${orderId}</p>
      <p class="mini" style="margin-top:18px">Si prefieres no usar tarjeta aquí, puedes abrir el checkout tradicional de PayPal con el botón alternativo.</p>
      <a class="linkBtn" href="${appBackUrl}">Cancelar y volver</a>
    </aside>
  </div>

  <script>
    const orderId = ${JSON.stringify(String(localOrder.provider_order_id || paypalOrderId))};
    const paymentOrderId = ${JSON.stringify(String(localOrder.id))};
    const captureUrl = ${JSON.stringify(captureUrl)};
    const fullposPaidUrl = ${JSON.stringify(`${FULLPOS_PROTOCOL_URL}?status=paid`)};
    const fallbackPaypalUrl = ${JSON.stringify(String(localOrder.checkout_url || ''))};
    const payButton = document.getElementById('payButton');
    const errorBox = document.getElementById('errorBox');
    const successBox = document.getElementById('successBox');

    function setError(message) {
      errorBox.textContent = message;
      errorBox.style.display = 'block';
      successBox.style.display = 'none';
    }

    function setSuccess(message) {
      successBox.textContent = message;
      successBox.style.display = 'block';
      errorBox.style.display = 'none';
    }

    function setLoading(value) {
      payButton.disabled = value;
      payButton.classList.toggle('loading', value);
    }

    (async function bootstrap() {
      try {
        if (!window.paypal || !window.paypal.CardFields) {
          throw new Error('PayPal no pudo cargar el formulario de tarjeta.');
        }

        const cardFields = window.paypal.CardFields({
          createOrder: () => orderId,
          onApprove: async () => {
            setLoading(true);
            try {
              const response = await fetch(captureUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
                body: JSON.stringify({
                  payment_order_id: paymentOrderId,
                  paypal_order_id: orderId,
                }),
              });
              const data = await response.json().catch(() => ({}));
              if (!response.ok || data.success === false) {
                throw new Error((data && (data.message || data.detail)) || 'No pudimos confirmar el pago.');
              }
              setSuccess('Pago confirmado. Ya puedes volver a FULLPOS.');
              window.location.href = fullposPaidUrl;
            } catch (error) {
              setError(error.message || 'No pudimos confirmar el pago. Intenta nuevamente.');
            } finally {
              setLoading(false);
            }
          },
          onError: (error) => {
            console.error('paypal card fields error', error);
            setError('No pudimos procesar la tarjeta. Revisa los datos e intenta otra vez.');
            setLoading(false);
          }
        });

        if (!cardFields.isEligible()) {
          if (fallbackPaypalUrl) {
            window.location.href = fallbackPaypalUrl;
            return;
          }
          throw new Error('Este método no está disponible ahora mismo para esta compra.');
        }

        await cardFields.NameField().render('#card-name-field-container');
        await cardFields.NumberField().render('#card-number-field-container');
        await cardFields.ExpiryField().render('#card-expiry-field-container');
        await cardFields.CVVField().render('#card-cvv-field-container');

        payButton.disabled = false;
        payButton.addEventListener('click', async () => {
          setError('');
          errorBox.style.display = 'none';
          setLoading(true);
          try {
            await cardFields.submit();
          } catch (error) {
            console.error('paypal card submit error', error);
            setError(error.message || 'Revisa los datos de la tarjeta e intenta nuevamente.');
            setLoading(false);
          }
        });
      } catch (error) {
        console.error('paypal card bootstrap error', error);
        if (fallbackPaypalUrl) {
          setError('No pudimos abrir el pago directo con tarjeta. Te llevaremos al checkout normal de PayPal.');
          setTimeout(() => { window.location.href = fallbackPaypalUrl; }, 1200);
          return;
        }
        setError(error.message || 'No pudimos abrir el formulario de pago.');
      }
    })();
  </script>
</body>
</html>`);
  } catch (error) {
    console.error('[paypal/card-checkout] Error:', error);
    return res.type('html').send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Error</title>
<style>body{font-family:Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#f6f8fb}.card{background:#fff;border-radius:18px;padding:36px;max-width:540px;text-align:center;box-shadow:0 12px 40px rgba(15,23,42,.12)}h1{color:#dc2626;margin:0 0 14px}p{color:#475569;line-height:1.6}.btn{display:inline-block;margin-top:20px;padding:12px 22px;background:#2563eb;color:#fff;text-decoration:none;border-radius:10px}</style></head>
<body><div class="card"><h1>No pudimos abrir el pago</h1><p>Intenta nuevamente desde FULLPOS. Si el problema continúa, usa el checkout normal de PayPal.</p><a href="${FULLPOS_PROTOCOL_URL}?status=error" class="btn">Volver a FULLPOS</a></div></body></html>`);
  }
});

/**
 * GET /paypal/success
 * Ruta de retorno después de pago exitoso en PayPal.
 * PayPal redirige con ?token=PAYPAL_ORDER_ID
 * 
 * Flujo:
 * 1. Recibir token (PayPal order ID)
 * 2. Buscar orden local por provider_order_id
 * 3. Si ya está PAID, mostrar confirmación
 * 4. Si está PENDING, capturar el pago y activar licencia
 */
app.get('/paypal/success', async (req, res) => {
  try {
    const token = String(req.query.token || req.query.order_id || req.query.id || '').trim();
    console.log('[paypal/success] Retorno PayPal:', { token, query: req.query });

    if (!token) {
      return res.type('html').send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Pago - Sin datos</title>
<style>body{font-family:Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#f5f5f5}.card{background:#fff;border-radius:12px;padding:40px;max-width:480px;text-align:center;box-shadow:0 2px 12px rgba(0,0,0,.1)}h1{color:#e67e22;margin:0 0 16px}p{color:#555;line-height:1.6}.btn{display:inline-block;margin-top:20px;padding:12px 24px;background:#3498db;color:#fff;text-decoration:none;border-radius:6px}</style></head>
<body><div class="card"><h1>⚠️ Sin datos de pago</h1><p>No recibimos datos de PayPal. Si realizaste un pago, verifica en la aplicación.</p><a href="${FULLPOS_PROTOCOL_URL}?status=missing" class="btn">Volver a FULLPOS</a></div></body></html>`);
    }

    // Buscar orden local por provider_order_id
    const localOrder = await licensePaymentOrdersModel.getPaymentOrderByProviderOrderId(token);

    if (!localOrder) {
      return res.type('html').send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Orden no encontrada</title>
<style>body{font-family:Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#f5f5f5}.card{background:#fff;border-radius:12px;padding:40px;max-width:480px;text-align:center;box-shadow:0 2px 12px rgba(0,0,0,.1)}h1{color:#e74c3c;margin:0 0 16px}p{color:#555;line-height:1.6}.btn{display:inline-block;margin-top:20px;padding:12px 24px;background:#3498db;color:#fff;text-decoration:none;border-radius:6px}</style></head>
<body><div class="card"><h1>❌ Orden no encontrada</h1><p>No encontramos esta orden de pago en nuestro sistema. Contacta a soporte si ya realizaste el pago.</p><a href="${FULLPOS_PROTOCOL_URL}?status=missing_order" class="btn">Volver a FULLPOS</a></div></body></html>`);
    }

    // Si ya está PAID, mostrar confirmación
    if (String(localOrder.status).toUpperCase() === 'PAID') {
      return res.type('html').send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Pago confirmado</title>
<style>body{font-family:Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#f5f5f5}.card{background:#fff;border-radius:12px;padding:40px;max-width:480px;text-align:center;box-shadow:0 2px 12px rgba(0,0,0,.1)}.icon{font-size:64px;margin-bottom:16px}h1{color:#27ae60;margin:0 0 16px}p{color:#555;line-height:1.6}.btn{display:inline-block;margin-top:20px;padding:12px 24px;background:#27ae60;color:#fff;text-decoration:none;border-radius:6px}</style></head>
<body><div class="card"><div class="icon">✅</div><h1>Pago ya confirmado</h1><p>Tu licencia ya está activa. Puedes cerrar esta ventana y volver a la aplicación.</p><a href="${FULLPOS_PROTOCOL_URL}?status=paid" class="btn">Volver a FULLPOS</a></div></body></html>`);
    }

    // Si está PENDING, capturar el pago
    if (String(localOrder.status).toUpperCase() === 'PENDING') {
      try {
        const captureResult = await paypalService.captureOrder(localOrder.provider_order_id);

        if (String(captureResult.status).toUpperCase() !== 'COMPLETED') {
          await licensePaymentOrdersModel.capturePaymentOrder(localOrder.id, {
            status: 'FAILED',
            raw_response: { captureResult, error: `PayPal status: ${captureResult.status}` },
          });
          return res.type('html').send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Pago pendiente</title>
<style>body{font-family:Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#f5f5f5}.card{background:#fff;border-radius:12px;padding:40px;max-width:480px;text-align:center;box-shadow:0 2px 12px rgba(0,0,0,.1)}h1{color:#e67e22;margin:0 0 16px}p{color:#555;line-height:1.6}.btn{display:inline-block;margin-top:20px;padding:12px 24px;background:#3498db;color:#fff;text-decoration:none;border-radius:6px}</style></head>
<body><div class="card"><h1>⏳ Pago pendiente</h1><p>El pago todavía no ha sido confirmado por PayPal. Estado: ${captureResult.status}. Vuelve a intentar desde la aplicación.</p><a href="${FULLPOS_PROTOCOL_URL}?status=pending" class="btn">Volver a FULLPOS</a></div></body></html>`);
        }

        // Captura exitosa: actualizar orden local
        await licensePaymentOrdersModel.capturePaymentOrder(localOrder.id, {
          provider_capture_id: captureResult.capture_id,
          status: 'PAID',
          raw_response: captureResult.raw || captureResult,
          paid_at: new Date(),
        });

        // Activar o extender licencia
        try {
          await licensesModel.activateOrExtendPaidLicense({
            customerId: localOrder.customer_id,
            projectId: localOrder.project_id,
            months: localOrder.months,
            paymentOrderId: localOrder.id,
            maxDevices: 1,
          });
        } catch (licenseError) {
          console.error('[paypal/success] License activation error:', licenseError.message);
        }

        return res.type('html').send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Pago exitoso</title>
<style>body{font-family:Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#f5f5f5}.card{background:#fff;border-radius:12px;padding:40px;max-width:480px;text-align:center;box-shadow:0 2px 12px rgba(0,0,0,.1)}.icon{font-size:64px;margin-bottom:16px}h1{color:#27ae60;margin:0 0 16px}p{color:#555;line-height:1.6}.btn{display:inline-block;margin-top:20px;padding:12px 24px;background:#27ae60;color:#fff;text-decoration:none;border-radius:6px}</style></head>
<body><div class="card"><div class="icon">✅</div><h1>Pago confirmado</h1><p>Tu licencia fue activada correctamente. Puedes cerrar esta ventana y volver a la aplicación.</p><a href="${FULLPOS_PROTOCOL_URL}?status=paid" class="btn">Volver a FULLPOS</a></div></body></html>`);
      } catch (captureError) {
        console.error('[paypal/success] Capture error:', captureError.message);
        await licensePaymentOrdersModel.capturePaymentOrder(localOrder.id, {
          status: 'FAILED',
          raw_response: { error: captureError.message, step: 'capture_from_success' },
        });
        return res.type('html').send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Error al capturar</title>
<style>body{font-family:Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#f5f5f5}.card{background:#fff;border-radius:12px;padding:40px;max-width:480px;text-align:center;box-shadow:0 2px 12px rgba(0,0,0,.1)}h1{color:#e74c3c;margin:0 0 16px}p{color:#555;line-height:1.6}.btn{display:inline-block;margin-top:20px;padding:12px 24px;background:#3498db;color:#fff;text-decoration:none;border-radius:6px}</style></head>
<body><div class="card"><h1>❌ Error al procesar el pago</h1><p>Ocurrió un error al capturar tu pago. Por favor, intenta nuevamente desde la aplicación o contacta a soporte.</p><a href="${FULLPOS_PROTOCOL_URL}?status=failed" class="btn">Volver a FULLPOS</a></div></body></html>`);
      }
    }

    // Otro estado
    const finalStatus = String(localOrder.status || '').toUpperCase();
    const isFailed = finalStatus === 'FAILED';
    const isCancelled = finalStatus === 'CANCELLED';
    const title = isFailed
      ? 'No pudimos confirmar tu pago'
      : isCancelled
        ? 'Pago cancelado'
        : `Estado: ${finalStatus || 'DESCONOCIDO'}`;
    const message = isFailed
      ? 'Tu pago todavía no quedó confirmado en el sistema. Vuelve a FULLPOS y usa "Ya pagué, verificar ahora". Si no terminaste el pago, vuelve a PayPal e inténtalo otra vez.'
      : isCancelled
        ? 'El pago fue cancelado. Puedes volver a FULLPOS e intentarlo de nuevo cuando quieras.'
        : 'Vuelve a FULLPOS para revisar el estado de tu licencia o verificar el pago nuevamente.';
    const accent = isFailed ? '#e67e22' : (isCancelled ? '#e67e22' : '#555');
    return res.type('html').send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Estado de pago</title>
<style>body{font-family:Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#f5f5f5}.card{background:#fff;border-radius:12px;padding:40px;max-width:520px;text-align:center;box-shadow:0 2px 12px rgba(0,0,0,.1)}h1{color:${accent};margin:0 0 16px}p{color:#555;line-height:1.6}.ref{margin-top:14px;font-size:12px;color:#7b8794}.btn{display:inline-block;margin-top:20px;padding:12px 24px;background:#3498db;color:#fff;text-decoration:none;border-radius:6px}</style></head>
<body><div class="card"><h1>${title}</h1><p>${message}</p><div class="ref">Referencia PayPal: ${localOrder.provider_order_id || token}</div><a href="${FULLPOS_PROTOCOL_URL}?status=${encodeURIComponent((finalStatus || 'unknown').toLowerCase())}" class="btn">Volver a FULLPOS</a></div></body></html>`);
  } catch (error) {
    console.error('[paypal/success] Error:', error);
    return res.type('html').send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Error</title>
<style>body{font-family:Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#f5f5f5}.card{background:#fff;border-radius:12px;padding:40px;max-width:480px;text-align:center;box-shadow:0 2px 12px rgba(0,0,0,.1)}h1{color:#e74c3c;margin:0 0 16px}p{color:#555;line-height:1.6}.btn{display:inline-block;margin-top:20px;padding:12px 24px;background:#3498db;color:#fff;text-decoration:none;border-radius:6px}</style></head>
<body><div class="card"><h1>❌ Error interno</h1><p>Ocurrió un error inesperado. Contacta a soporte.</p><a href="${FULLPOS_PROTOCOL_URL}?status=error" class="btn">Volver a FULLPOS</a></div></body></html>`);
  }
});

/**
 * GET /paypal/cancel
 * Ruta de retorno después de pago cancelado en PayPal.
 */
app.get('/paypal/cancel', async (req, res) => {
  try {
    const token = String(req.query.token || '').trim();
    console.log('[paypal/cancel] Pago cancelado:', { token, query: req.query });

    // Si hay token, marcar la orden como CANCELLED si está PENDING
    if (token) {
      const localOrder = await licensePaymentOrdersModel.getPaymentOrderByProviderOrderId(token);
      if (localOrder && String(localOrder.status).toUpperCase() === 'PENDING') {
        await licensePaymentOrdersModel.capturePaymentOrder(localOrder.id, {
          status: 'CANCELLED',
          raw_response: { cancelled_at: new Date().toISOString(), source: 'paypal_cancel_url' },
        });
        console.log('[paypal/cancel] Orden marcada como CANCELLED:', localOrder.id);
      }
    }

    return res.type('html').send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Pago cancelado</title>
<style>body{font-family:Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#f5f5f5}.card{background:#fff;border-radius:12px;padding:40px;max-width:480px;text-align:center;box-shadow:0 2px 12px rgba(0,0,0,.1)}.icon{font-size:64px;margin-bottom:16px}h1{color:#e67e22;margin:0 0 16px}p{color:#555;line-height:1.6}.btn{display:inline-block;margin-top:20px;padding:12px 24px;background:#3498db;color:#fff;text-decoration:none;border-radius:6px}</style></head>
<body><div class="card"><div class="icon">ℹ️</div><h1>Pago cancelado</h1><p>Has cancelado el pago. Puedes intentarlo nuevamente desde la aplicación cuando quieras.</p><a href="${FULLPOS_PROTOCOL_URL}?status=cancelled" class="btn">Volver a FULLPOS</a></div></body></html>`);
  } catch (error) {
    console.error('[paypal/cancel] Error:', error);
    return res.type('html').send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Pago cancelado</title>
<style>body{font-family:Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#f5f5f5}.card{background:#fff;border-radius:12px;padding:40px;max-width:480px;text-align:center;box-shadow:0 2px 12px rgba(0,0,0,.1)}h1{color:#e67e22;margin:0 0 16px}p{color:#555;line-height:1.6}.btn{display:inline-block;margin-top:20px;padding:12px 24px;background:#3498db;color:#fff;text-decoration:none;border-radius:6px}</style></head>
<body><div class="card"><h1>ℹ️ Pago cancelado</h1><p>Puedes intentarlo nuevamente desde la aplicación.</p><a href="${FULLPOS_PROTOCOL_URL}?status=cancelled" class="btn">Volver a FULLPOS</a></div></body></html>`);
  }
});

// ==========================================
// MIDDLEWARE
// ==========================================
// Backups pueden ser grandes (JSON + cifrado). Subimos el límite de forma moderada.
app.use('/api/paypal/webhook', express.raw({ type: 'application/json' }));
app.use(bodyParser.json({ limit: '25mb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '25mb' }));

// CORS (si hay cookies/credenciales, NO usar '*')
// Configura `CORS_ORIGINS` como lista separada por coma.
const corsOrigins = String(process.env.CORS_ORIGINS || '')
  .split(',')
  .map(s => s.trim())
  .filter(Boolean);

function isOriginAllowed(origin) {
  if (!origin) return false;
  if (corsOrigins.length === 0) return true; // permissive default (dev) if not set
  return corsOrigins.includes(origin);
}

app.use((req, res, next) => {
  const origin = req.headers.origin;
  const allowOrigin = isOriginAllowed(origin) ? origin : null;

  if (allowOrigin) {
    res.header('Access-Control-Allow-Origin', allowOrigin);
    res.header('Vary', 'Origin');
    res.header('Access-Control-Allow-Credentials', 'true');
  } else {
    // Non-browser calls (no Origin) or disallowed origins.
    res.header('Access-Control-Allow-Origin', '*');
  }

  res.header('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.header(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization, x-session-id, apikey, x-license-key, x-device-id'
  );
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

// Servir archivos estáticos de admin
app.use('/admin', express.static(path.join(__dirname, '../admin'), {
  etag: true,
  lastModified: true,
  setHeaders: setStaticFreshnessHeaders
}));

// Servir archivos públicos (landing + assets) para que el sitio pueda funcionar como PWA
// Nota: evitamos exponer toda la raíz del repo; sólo servimos lo necesario.
app.use('/assets', express.static(path.join(__dirname, '../assets'), {
  etag: true,
  lastModified: true,
  setHeaders: setStaticFreshnessHeaders
}));

// Public pages
// Canonical landing should be the root URL (avoid showing /home.html in the browser).
app.get('/', (req, res) => {
  setNoCacheHeaders(res);
  res.sendFile(path.join(__dirname, '../home.html'));
});

// Keep backwards compatibility for existing bookmarks.
app.get(['/index.html', '/home.html'], (req, res) => {
  res.redirect(302, '/');
});

app.get('/products.html', (req, res) => {
  setNoCacheHeaders(res);
  res.sendFile(path.join(__dirname, '../products.html'));
});

app.get('/product.html', (req, res) => {
  setNoCacheHeaders(res);
  res.sendFile(path.join(__dirname, '../product.html'));
});

app.get('/fullpos.html', (req, res) => {
  setNoCacheHeaders(res);
  res.sendFile(path.join(__dirname, '../fullpos.html'));
});

app.get('/manifest.webmanifest', (req, res) => {
  res.type('application/manifest+json');
  setNoCacheHeaders(res);
  res.sendFile(path.join(__dirname, '../manifest.webmanifest'));
});

app.get('/sw.js', (req, res) => {
  res.type('application/javascript');
  setNoCacheHeaders(res);
  res.sendFile(path.join(__dirname, '../sw.js'));
});

app.get('/offline.html', (req, res) => {
  setNoCacheHeaders(res);
  res.sendFile(path.join(__dirname, '../offline.html'));
});

// Servir descargas públicamente
app.use('/descargas', express.static(path.join(__dirname, '../descargas')));

// ==========================================
// STORE / PRODUCTS (public + admin)
// ==========================================
// Public read-only APIs
app.use('/api/public', storePublicRoutes);
app.use('/api/public', publicAssetsRoutes);

// Public License APIs (FullCredit / SaaS apps)
// Rate limit: 60 req/min per IP (tight enough for license validation)
const publicLicenseLimiter = rateLimit({ windowMs: 60_000, max: 60, message: 'Límite de peticiones alcanzado. Espere un momento.' });
app.use('/api/public', publicLicenseLimiter, publicLicenseRoutes);

// Endpoint público de versión para confirmar deploy
app.get('/api/public/version', (req, res) => {
  res.json({
    success: true,
    service: 'appyra-license-backend',
    version: 'demo-delete-marker-fix-2026-06-04',
    has_public_license_routes: true,
    has_demo_start: true,
    has_migration_043: true,
    license_only_mode: LICENSE_ONLY,
    node_env: String(process.env.NODE_ENV || 'development'),
    ts: new Date().toISOString()
  });
});


// Admin APIs (protected by x-session-id)
app.use('/api/admin', adminProductsRoutes);
app.use('/api/admin', adminStoreSettingsRoutes);
app.use('/api/admin/platform-users', adminPlatformUsersRoutes);
app.use('/api/admin/roles', adminRolesRoutes);
app.use('/api/admin/support-reset', adminSupportResetRoutes);
app.use('/api/admin/support-message-config', adminSupportMessageConfigRoutes);

// Recuperación de contraseña para login local FULLPOS (código OTP vía Evolution)
app.use('/api/password-reset', passwordResetRoutes);

// Solicitudes de soporte desde FULLPOS (envío server-side vía Evolution)
app.use('/api/support', supportRequestRoutes);

// ==========================================
// RUTAS DE AUTENTICACIÓN
// ==========================================

// Credenciales fijas (MUY BÁSICO - para desarrollo)
const { username: ADMIN_USERNAME, password: ADMIN_PASSWORD } = getAdminCredentials();
const AUTH_DEBUG = String(process.env.AUTH_DEBUG || '').trim() === '1';

// POST /api/login - Verificar credenciales
app.post('/api/login', async (req, res) => {
  const { username, password } = req.body;

  if (AUTH_DEBUG) {
    console.log('[auth] login attempt', {
      userProvided: String(username || '').trim() ? true : false,
      origin: req.headers.origin || null,
      host: req.headers.host || null,
      xfProto: req.headers['x-forwarded-proto'] || null,
      proto: req.protocol || null
    });
  }

  if (username === ADMIN_USERNAME && password === ADMIN_PASSWORD) {
    // Important: await DB insert so sessions work across instances / restarts.
    const sessionId = await sessions.createSessionAsync(username);

    res.json({
      success: true,
      sessionId: sessionId,
      message: 'Login exitoso'
    });
  } else {
    res.status(401).json({
      success: false,
      message: 'Credenciales inválidas'
    });
  }
});

// Auth app (JWT) - multi-company login
if (!LICENSE_ONLY) {
  app.use('/api/auth', authRoutes);
}

// ==========================================
// RUTAS DE UPLOAD
// ==========================================
// Nota: protegemos únicamente el endpoint de subida con sesión válida.
// El resto de endpoints públicos (ej. /api/latest-installer) siguen abiertos.
app.use('/api', (req, res, next) => {
  if (req.path === '/upload-installer') {
    return sessions.verifySessionMiddleware(req, res, next);
  }
  next();
}, uploadRoutes);

// ==========================================
// MÓDULO DE LICENCIAS (PostgreSQL)
// ==========================================
// ADMIN (panel web)
app.use('/api/admin/customers', adminCustomersRoutes);
app.use('/api/admin/businesses', adminBusinessesRoutes);
app.use('/api/admin/licenses', adminLicensesRoutes);
app.use('/api/admin/license-config', adminLicenseConfigRoutes);
app.use('/api/admin/activations', adminActivationsRoutes);
app.use('/api/admin/projects', adminProjectsRoutes);
app.use('/api/admin/payments', adminPaymentsRoutes);
app.use('/api/admin/license-payments', adminLicensePaymentsRoutes);
app.use('/api/admin', adminDashboardRoutes);

// APP ESCRITORIO
// Rate limit public endpoints: 120 req/min per IP (generous for POS apps,
// tight enough to block naive brute-force and scraping).
const licensePublicLimiter = rateLimit({ windowMs: 60_000, max: 120, message: 'Límite de peticiones alcanzado. Espere un momento.' });
app.use('/api', licensePublicLimiter, billingPortalRoutes);
app.use('/api/activations', licensePublicLimiter, activationsRoutes);
app.use('/api/paypal', (req, res, next) => {
  if (req.path === '/webhook') return next();
  return licensePublicLimiter(req, res, next);
}, paypalRoutes);
app.use('/api/licenses', licensePublicLimiter, licensesPublicRoutes);
app.use('/api/v2/licenses', licensePublicLimiter, licenseValidationRoutes);

// Registro de negocios + auto-licencia (sin device_id)
// Soportamos ambas rutas por compatibilidad con la especificación.
app.use('/api/businesses', businessesRoutes);
app.use('/businesses', businessesRoutes);

// SINCRONIZACIÓN (nube ⇆ local)
if (!LICENSE_ONLY) {
  app.use('/api/sync', syncRoutes);
}

// BACKUPS (nube ⇆ local)
if (!LICENSE_ONLY) {
  app.use('/api/backup', backupRoutes);
}

// POST /api/logout - Cerrar sesión
app.post('/api/logout', sessions.verifySessionMiddleware, (req, res) => {
  sessions.destroySession(req.sessionId);
  res.json({
    success: true,
    message: 'Sesión cerrada'
  });
});

// GET /api/verify-session - Verificar si la sesión es válida
// Importante: usa middleware para soportar sesiones respaldadas por Postgres.
app.get('/api/verify-session', sessions.verifySessionMiddleware, (req, res) => {
  return res.json({ success: true, username: req.adminUser || 'Admin' });
});

// ==========================================
// RUTAS DE VERSIONES
// ==========================================

// GET /api/versions - Obtener todas las versiones (protegido)
app.get('/api/versions', sessions.verifySessionMiddleware, (req, res) => {
  try {
    const versionsPath = path.join(__dirname, 'versions.json');
    const versions = JSON.parse(fs.readFileSync(versionsPath, 'utf8'));
    res.json({
      success: true,
      versions: versions
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Error al obtener versiones',
      error: error.message
    });
  }
});

// GET /api/latest-installer - Obtener el último instalador (público)
app.get('/api/latest-installer', (req, res) => {
  try {
    const versionsPath = path.join(__dirname, 'versions.json');
    const versions = JSON.parse(fs.readFileSync(versionsPath, 'utf8'));

    if (versions.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'No hay versiones disponibles'
      });
    }

    // Retornar la última versión (la más reciente)
    const latest = versions[versions.length - 1];
    res.json({
      success: true,
      version: latest
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Error al obtener el instalador',
      error: error.message
    });
  }
});

// ==========================================
// EVOLUTION API (WHATSAPP) - ENV BASED
// ==========================================

function normalizePhoneToE164Like(raw) {
  if (!raw) return '';
  const digits = String(raw).replace(/[^0-9]/g, '');
  // Para RD normalmente: 1 + 10 dígitos (ej: 18295319442)
  if (digits.length === 10) return `1${digits}`;
  return digits;
}

async function sendEvolutionText({ toNumber, message }) {
  const baseUrl = (process.env.EVOLUTION_API_URL || '').replace(/\/$/, '');
  const instanceName = process.env.EVOLUTION_API_INSTANCE_NAME;
  const apiKey = process.env.EVOLUTION_API_KEY;

  if (!baseUrl || !instanceName || !apiKey) {
    throw new Error('Faltan variables en .env: EVOLUTION_API_URL, EVOLUTION_API_INSTANCE_NAME, EVOLUTION_API_KEY');
  }

  const headers = {
    'Content-Type': 'application/json',
    apikey: apiKey
  };

  // Intento 1: /message/sendText con instance en body
  let response = await fetch(`${baseUrl}/message/sendText`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      number: toNumber,
      text: message,
      instance: instanceName
    })
  });

  // Fallback: /message/sendText/:instance
  if (response.status === 404) {
    response = await fetch(`${baseUrl}/message/sendText/${encodeURIComponent(instanceName)}`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        number: toNumber,
        text: message
      })
    });
  }

  const text = await response.text().catch(() => '');
  if (!response.ok) {
    throw new Error(`Evolution API error ${response.status}: ${text || response.statusText}`);
  }

  return text;
}

// POST /api/send-license-request - Recibe datos del formulario y envía al WhatsApp del dueño
app.post('/api/send-license-request', async (req, res) => {
  try {
    const ownerRaw = process.env.EVOLUTION_OWNER_NUMBER;
    if (!ownerRaw) {
      return res.status(500).json({
        success: false,
        message: 'Falta EVOLUTION_OWNER_NUMBER en el archivo .env'
      });
    }

    const ownerNumber = normalizePhoneToE164Like(ownerRaw);
    const nombre = (req.body.nombre || '').trim();
    const telefono = (req.body.telefono || '').trim();
    const email = (req.body.email || '').trim();
    const negocio = (req.body.negocio || '').trim();
    const mensaje = (req.body.mensaje || '').trim();

    if (!nombre || !telefono || !email) {
      return res.status(400).json({
        success: false,
        message: 'Faltan campos requeridos (nombre, teléfono, email)'
      });
    }

    const whatsappMessage =
      `📋 *NUEVA SOLICITUD DE LICENCIA - FULLTECH POS*\n\n` +
      `👤 *Nombre:* ${nombre}\n` +
      `📱 *Teléfono:* ${telefono}\n` +
      `📧 *Email:* ${email}\n` +
      `🏪 *Negocio:* ${negocio || '-'}\n` +
      `💬 *Mensaje:* ${mensaje || '-'}\n\n` +
      `⏰ *Fecha:* ${new Date().toLocaleString('es-DO')}`;

    await sendEvolutionText({
      toNumber: ownerNumber,
      message: whatsappMessage
    });

    res.json({
      success: true,
      message: 'Solicitud enviada por WhatsApp al dueño'
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Error enviando a WhatsApp',
      error: error.message
    });
  }
});

// DELETE /api/delete-installer/:id - Eliminar una versión (protegido)
app.delete('/api/delete-installer/:id', sessions.verifySessionMiddleware, (req, res) => {
  try {
    const versionId = req.params.id;
    const versionsPath = path.join(__dirname, 'versions.json');
    let versions = JSON.parse(fs.readFileSync(versionsPath, 'utf8'));

    // Encontrar versión a eliminar
    const versionIndex = versions.findIndex(v => v.id === versionId);
    if (versionIndex === -1) {
      return res.status(404).json({
        success: false,
        message: 'Versión no encontrada'
      });
    }

    const version = versions[versionIndex];

    // Eliminar archivo
    const filePath = path.join(__dirname, '..', version.ruta);
    if (fs.existsSync(filePath)) {
      fs.unlinkSync(filePath);
    }

    // Eliminar de JSON
    versions.splice(versionIndex, 1);
    fs.writeFileSync(versionsPath, JSON.stringify(versions, null, 2));

    res.json({
      success: true,
      message: 'Versión eliminada correctamente'
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Error al eliminar versión',
      error: error.message
    });
  }
});

// GET /admin - Panel único
app.get(['/admin', '/admin/'], (req, res) => {
  res.redirect(302, '/admin/admin-hub.html');
});

// GET /admin/login - Servir login.html
app.get('/admin/login', (req, res) => {
  res.sendFile(path.join(__dirname, '../admin/login.html'));
});

// GET /admin/dashboard - Servir dashboard.html
app.get('/admin/dashboard', (req, res) => {
  res.sendFile(path.join(__dirname, '../admin/dashboard.html'));
});

// ==========================================
// GLOBAL ERROR HANDLER
// ==========================================
// Must be declared after all routes. Catches unhandled errors from next(err).
// In production: never expose stack traces or internal error details.
// eslint-disable-next-line no-unused-vars
app.use(function globalErrorHandler(err, req, res, next) {
  const NODE_ENV = String(process.env.NODE_ENV || '').toLowerCase();
  const isProduction = NODE_ENV === 'production';

  // Log full error server-side always.
  console.error('[error]', req.method, req.path, err?.message || err);

  const status = typeof err?.status === 'number' ? err.status : 500;

  if (isProduction) {
    // Never expose internals to clients in production.
    return res.status(status).json({ ok: false, message: 'Error interno del servidor' });
  }

  // Dev: include message but never stack in response body to avoid accidental leakage.
  return res.status(status).json({ ok: false, message: err?.message || 'Error interno del servidor' });
});

// ==========================================
// INICIAR SERVIDOR
// ==========================================

async function startServer() {
  try {
    if (String(process.env.SKIP_STARTUP_MIGRATIONS || '').trim() !== '1') {
      await runMigrations({ endPool: false });
    }
  } catch (error) {
    console.error('[startup] No se pudieron aplicar las migraciones:', error?.message || error);
    process.exit(1);
  }

  app.listen(ADMIN_PORT, () => {
    console.log(`\n✅ FULLTECH POS Admin Server ejecutándose en puerto ${ADMIN_PORT}`);
    console.log(`   Admin Panel: http://localhost:${ADMIN_PORT}/admin/login.html`);
    console.log(`   API: http://localhost:${ADMIN_PORT}/api`);
    console.log(`   Landing Pública: http://localhost:${ADMIN_PORT}/\n`);
  });
}

startServer();
