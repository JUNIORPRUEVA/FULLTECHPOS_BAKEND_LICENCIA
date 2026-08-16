const DEFAULT_TIMEOUT_MS = 15000;
const BASE_URL_ENV_NAMES = [
  'DALEVENTAS_LICENSE_API_BASE_URL',
  'DALEVENTA_LICENSE_API_BASE_URL',
  'DALEVENTAS_API_BASE_URL',
  'FULLPOS_CLOUD_API_BASE_URL',
];
const ADMIN_SECRET_ENV_NAMES = [
  'DALEVENTAS_LICENSE_ADMIN_SECRET',
  'DALEVENTA_LICENSE_ADMIN_SECRET',
  'DALEVENTAS_ADMIN_SECRET',
  'LICENSE_ADMIN_SECRET',
];

function readEnv(name) {
  const value = process.env[name];
  return typeof value === 'string' ? value.trim() : '';
}

function readEnvFile(name) {
  const filePath = readEnv(`${name}_FILE`);
  if (!filePath) return '';
  try {
    return require('fs').readFileSync(filePath, 'utf8').trim();
  } catch (error) {
    console.warn(
      `[daleventas-license-bridge] Could not read ${name}_FILE: ${error.message || error}`
    );
    return '';
  }
}

function firstConfigured(names) {
  for (const name of names) {
    const value = readEnv(name) || readEnvFile(name);
    if (value) return { name, value };
  }
  return { name: null, value: '' };
}

function getConfig() {
  const base = firstConfigured(BASE_URL_ENV_NAMES);
  const adminSecret = firstConfigured(ADMIN_SECRET_ENV_NAMES);

  return {
    baseUrl: base.value.replace(/\/+$/, ''),
    secret: adminSecret.value,
    sources: {
      baseUrl: base.name,
      secret: adminSecret.name,
    },
    missing: [
      ...(base.value ? [] : ['DALEVENTAS_LICENSE_API_BASE_URL']),
      ...(adminSecret.value ? [] : ['DALEVENTAS_LICENSE_ADMIN_SECRET']),
    ],
  };
}

function getConfigStatus() {
  const config = getConfig();
  return {
    configured: config.missing.length === 0,
    hasBaseUrl: Boolean(config.baseUrl),
    hasAdminSecret: Boolean(config.secret),
    baseUrlSource: config.sources.baseUrl,
    adminSecretSource: config.sources.secret,
    acceptedBaseUrlEnvNames: BASE_URL_ENV_NAMES,
    acceptedAdminSecretEnvNames: ADMIN_SECRET_ENV_NAMES,
    missing: config.missing,
  };
}

function adminActor(req) {
  return String(req.adminUser || req.headers['x-admin-user'] || 'Appyra Admin')
    .trim()
    .slice(0, 120);
}

function buildQuery(query) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query || {})) {
    if (value == null || value === '') continue;
    params.set(key, String(value));
  }
  const qs = params.toString();
  return qs ? `?${qs}` : '';
}

async function requestDaleVentas(req, res, method, path, body) {
  const { baseUrl, secret, missing } = getConfig();
  if (!baseUrl || !secret) {
    return res.status(503).json({
      success: false,
      errorCode: 'DALEVENTAS_LICENSE_BRIDGE_NOT_CONFIGURED',
      message:
        `El puente de licencias DaleVentas no esta configurado. Falta definir: ${missing.join(', ')}.`,
      missing,
      acceptedBaseUrlEnvNames: BASE_URL_ENV_NAMES,
      acceptedAdminSecretEnvNames: ADMIN_SECRET_ENV_NAMES,
    });
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);

  try {
    const response = await fetch(`${baseUrl}${path}`, {
      method,
      signal: controller.signal,
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'x-license-admin-secret': secret,
        'x-license-admin-actor': adminActor(req),
      },
      body: body ? JSON.stringify(body) : undefined,
    });

    const text = await response.text();
    let data = {};
    if (text) {
      try {
        data = JSON.parse(text);
      } catch (_) {
        data = { message: text };
      }
    }

    return res.status(response.status).json(data);
  } catch (error) {
    const isTimeout = error && error.name === 'AbortError';
    return res.status(isTimeout ? 504 : 502).json({
      success: false,
      message: isTimeout
        ? 'DaleVentas no respondio a tiempo.'
        : 'No se pudo conectar con DaleVentas para gestionar la licencia.',
      details: process.env.NODE_ENV === 'production' ? undefined : String(error.message || error),
    });
  } finally {
    clearTimeout(timeout);
  }
}

exports.listCompanies = (req, res) => {
  return requestDaleVentas(
    req,
    res,
    'GET',
    `/license/admin/companies${buildQuery(req.query)}`
  );
};

exports.getCompany = (req, res) => {
  return requestDaleVentas(
    req,
    res,
    'GET',
    `/license/admin/${encodeURIComponent(req.params.companyId)}`
  );
};

exports.updateCompany = (req, res) => {
  return requestDaleVentas(
    req,
    res,
    'PATCH',
    `/license/admin/${encodeURIComponent(req.params.companyId)}`,
    req.body || {}
  );
};

exports.activateCompany = (req, res) => {
  return requestDaleVentas(
    req,
    res,
    'POST',
    `/license/admin/${encodeURIComponent(req.params.companyId)}/activate`,
    req.body || {}
  );
};

exports.blockCompany = (req, res) => {
  return requestDaleVentas(
    req,
    res,
    'POST',
    `/license/admin/${encodeURIComponent(req.params.companyId)}/block`,
    req.body || {}
  );
};

exports.deleteCompanyLicense = (req, res) => {
  return requestDaleVentas(
    req,
    res,
    'DELETE',
    `/license/admin/${encodeURIComponent(req.params.companyId)}`,
    req.body || {}
  );
};

exports.permanentlyDeleteCompanyLicense = (req, res) => {
  return requestDaleVentas(
    req,
    res,
    'DELETE',
    `/license/admin/${encodeURIComponent(req.params.companyId)}/permanent`,
    req.body || {}
  );
};

exports.getConfigStatus = getConfigStatus;
