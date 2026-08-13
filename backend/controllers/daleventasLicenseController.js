const DEFAULT_TIMEOUT_MS = 15000;

function getConfig() {
  const baseUrl = String(
    process.env.DALEVENTAS_LICENSE_API_BASE_URL ||
      process.env.DALEVENTA_LICENSE_API_BASE_URL ||
      process.env.DALEVENTAS_API_BASE_URL ||
      ''
  ).trim().replace(/\/+$/, '');

  const secret = String(
    process.env.DALEVENTAS_LICENSE_ADMIN_SECRET ||
      process.env.DALEVENTA_LICENSE_ADMIN_SECRET ||
      process.env.LICENSE_ADMIN_SECRET ||
      ''
  ).trim();

  return { baseUrl, secret };
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
  const { baseUrl, secret } = getConfig();
  if (!baseUrl || !secret) {
    return res.status(503).json({
      success: false,
      message:
        'El puente de licencias DaleVentas no esta configurado. Defina DALEVENTAS_LICENSE_API_BASE_URL y DALEVENTAS_LICENSE_ADMIN_SECRET.',
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
