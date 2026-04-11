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
const licensesPublicRoutes = require('./routes/licensesPublicRoutes');
const businessesRoutes = require('./routes/businessesRoutes');
const adminProductsRoutes = require('./routes/adminProductsRoutes');
const adminStoreSettingsRoutes = require('./routes/adminStoreSettingsRoutes');
const adminSupportResetRoutes = require('./routes/adminSupportResetRoutes');
const adminSupportMessageConfigRoutes = require('./routes/adminSupportMessageConfigRoutes');
const storePublicRoutes = require('./routes/storePublicRoutes');
const publicAssetsRoutes = require('./routes/publicAssetsRoutes');
const passwordResetRoutes = require('./routes/passwordResetRoutes');
const supportRequestRoutes = require('./routes/supportRequestRoutes');

// Módulos opcionales (solo cuando se usa el backend completo)
const authRoutes = LICENSE_ONLY ? null : require('./routes/authRoutes');
const syncRoutes = LICENSE_ONLY ? null : require('./modules/sync/sync.routes');
const backupRoutes = LICENSE_ONLY ? null : require('./modules/backup/backup.routes');
const { pool } = require('./db/pool');

const app = express();
const ADMIN_PORT = Number.parseInt(process.env.PORT || '3000', 10);

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
app.get('/api/health', (req, res) => {
  res.json({ ok: true, status: 'up', ts: new Date().toISOString() });
});

// Alias por compatibilidad (algunos servicios prueban /health).
app.get('/health', (req, res) => {
  res.json({ ok: true, status: 'up', ts: new Date().toISOString() });
});

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

// ==========================================
// MIDDLEWARE
// ==========================================
// Backups pueden ser grandes (JSON + cifrado). Subimos el límite de forma moderada.
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

// Admin APIs (protected by x-session-id)
app.use('/api/admin', adminProductsRoutes);
app.use('/api/admin', adminStoreSettingsRoutes);
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
const ADMIN_USERNAME = process.env.ADMIN_USERNAME || 'fulltechsd@gmail.com';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'Ayleen10';
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

// APP ESCRITORIO
app.use('/api/licenses', licensesPublicRoutes);

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

// GET /admin/login - Servir login.html
app.get('/admin/login', (req, res) => {
  res.sendFile(path.join(__dirname, '../admin/login.html'));
});

// GET /admin/dashboard - Servir dashboard.html
app.get('/admin/dashboard', (req, res) => {
  res.sendFile(path.join(__dirname, '../admin/dashboard.html'));
});

// ==========================================
// INICIAR SERVIDOR
// ==========================================

app.listen(ADMIN_PORT, () => {
  console.log(`\n✅ FULLTECH POS Admin Server ejecutándose en puerto ${ADMIN_PORT}`);
  console.log(`   Admin Panel: http://localhost:${ADMIN_PORT}/admin/login.html`);
  console.log(`   API: http://localhost:${ADMIN_PORT}/api`);
  console.log(`   Landing Pública: http://localhost:${ADMIN_PORT}/\n`);
});
