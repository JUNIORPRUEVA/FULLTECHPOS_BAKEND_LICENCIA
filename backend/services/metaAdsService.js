const { pool } = require('../db/pool');

const META_ADS_CONFIG_ID = '00000000-0000-0000-0000-000000000003';

function normalizeText(value) {
  return String(value || '').trim();
}

function readEnvValue(name) {
  return normalizeText(process.env[name]);
}

function maskSecret(value) {
  const raw = normalizeText(value);
  if (!raw) return '';
  if (raw.length <= 14) {
    const head = raw.slice(0, Math.min(4, raw.length));
    const tail = raw.slice(-Math.min(2, raw.length));
    return `${head}...${tail}`;
  }
  return `${raw.slice(0, 8)}...${raw.slice(-6)}`;
}

function normalizeAdAccountId(value) {
  const raw = normalizeText(value);
  if (!raw) return '';
  if (/^act_\d+$/i.test(raw)) return raw;
  const digits = raw.replace(/[^0-9]/g, '');
  if (!digits) return '';
  return `act_${digits}`;
}

function buildGraphError(data, fallbackMessage) {
  const err = data && data.error ? data.error : {};
  const message = normalizeText(err.message) || fallbackMessage || 'Meta Graph API error';
  return {
    message,
    code: err.code,
    error_subcode: err.error_subcode,
    type: err.type,
    fbtrace_id: err.fbtrace_id,
    raw: data,
  };
}

function toGraphApiError(data, fallbackMessage, statusCode) {
  const graphError = buildGraphError(data, fallbackMessage);
  const error = new Error(graphError.message);
  error.statusCode = statusCode || 502;
  error.graphError = graphError;
  return error;
}

async function ensureMetaAdsConfigTable() {
  await pool.query(
    `CREATE TABLE IF NOT EXISTS meta_ads_config (
      id uuid PRIMARY KEY DEFAULT '00000000-0000-0000-0000-000000000003'::uuid,
      meta_ads_access_token text,
      meta_ad_account_id text,
      meta_whatsapp_phone_number_id text,
      meta_whatsapp_business_account_id text,
      meta_ads_app_id text,
      meta_ads_app_secret text,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    )`
  );
}

async function getStoredConfig() {
  await ensureMetaAdsConfigTable();
  const res = await pool.query(
    `SELECT id,
            meta_ads_access_token,
            meta_ad_account_id,
            meta_whatsapp_phone_number_id,
            meta_whatsapp_business_account_id,
            meta_ads_app_id,
            meta_ads_app_secret,
            created_at,
            updated_at
     FROM meta_ads_config
     WHERE id = $1
     LIMIT 1`,
    [META_ADS_CONFIG_ID]
  );
  return res.rows[0] || null;
}

function envDefaults() {
  return {
    id: META_ADS_CONFIG_ID,
    meta_ads_access_token: readEnvValue('META_ADS_ACCESS_TOKEN'),
    meta_ad_account_id: readEnvValue('META_AD_ACCOUNT_ID'),
    meta_whatsapp_phone_number_id: readEnvValue('META_WHATSAPP_PHONE_NUMBER_ID'),
    meta_whatsapp_business_account_id: readEnvValue('META_WHATSAPP_BUSINESS_ACCOUNT_ID'),
    meta_ads_app_id: readEnvValue('META_ADS_APP_ID'),
    meta_ads_app_secret: readEnvValue('META_ADS_APP_SECRET'),
    organic_access_token: readEnvValue('META_ACCESS_TOKEN'),
    organic_facebook_page_id: readEnvValue('META_FACEBOOK_PAGE_ID'),
    organic_instagram_business_id: readEnvValue('META_INSTAGRAM_BUSINESS_ID'),
  };
}

async function getRuntimeConfig() {
  const defaults = envDefaults();
  const stored = await getStoredConfig();
  if (!stored) {
    return {
      ...defaults,
      meta_ad_account_id: normalizeAdAccountId(defaults.meta_ad_account_id),
    };
  }

  return {
    id: stored.id,
    meta_ads_access_token:
      normalizeText(stored.meta_ads_access_token) || defaults.meta_ads_access_token,
    meta_ad_account_id:
      normalizeAdAccountId(stored.meta_ad_account_id) ||
      normalizeAdAccountId(defaults.meta_ad_account_id),
    meta_whatsapp_phone_number_id:
      normalizeText(stored.meta_whatsapp_phone_number_id) ||
      defaults.meta_whatsapp_phone_number_id,
    meta_whatsapp_business_account_id:
      normalizeText(stored.meta_whatsapp_business_account_id) ||
      defaults.meta_whatsapp_business_account_id,
    meta_ads_app_id: normalizeText(stored.meta_ads_app_id) || defaults.meta_ads_app_id,
    meta_ads_app_secret:
      normalizeText(stored.meta_ads_app_secret) || defaults.meta_ads_app_secret,
    organic_access_token: defaults.organic_access_token,
    organic_facebook_page_id: defaults.organic_facebook_page_id,
    organic_instagram_business_id: defaults.organic_instagram_business_id,
    created_at: stored.created_at,
    updated_at: stored.updated_at,
  };
}

async function getMetaAdsConfigForAdmin() {
  const cfg = await getRuntimeConfig();
  return {
    ad_account_id: cfg.meta_ad_account_id,
    whatsapp_phone_number_id: cfg.meta_whatsapp_phone_number_id,
    whatsapp_business_account_id: cfg.meta_whatsapp_business_account_id,
    ads_app_id: cfg.meta_ads_app_id,
    ads_access_token_masked: maskSecret(cfg.meta_ads_access_token),
    ads_app_secret_masked: maskSecret(cfg.meta_ads_app_secret),
    has_ads_access_token: Boolean(cfg.meta_ads_access_token),
    has_ads_app_secret: Boolean(cfg.meta_ads_app_secret),
    organic_token_configured: Boolean(cfg.organic_access_token),
    organic_facebook_page_id: cfg.organic_facebook_page_id,
    organic_instagram_business_id: cfg.organic_instagram_business_id,
    updated_at: cfg.updated_at || null,
  };
}

async function updateMetaAdsConfig(payload) {
  const current = await getRuntimeConfig();
  const next = {
    meta_ads_access_token: Object.prototype.hasOwnProperty.call(payload, 'meta_ads_access_token')
      ? normalizeText(payload.meta_ads_access_token)
      : current.meta_ads_access_token,
    meta_ad_account_id: Object.prototype.hasOwnProperty.call(payload, 'meta_ad_account_id')
      ? normalizeAdAccountId(payload.meta_ad_account_id)
      : current.meta_ad_account_id,
    meta_whatsapp_phone_number_id: Object.prototype.hasOwnProperty.call(payload, 'meta_whatsapp_phone_number_id')
      ? normalizeText(payload.meta_whatsapp_phone_number_id)
      : current.meta_whatsapp_phone_number_id,
    meta_whatsapp_business_account_id: Object.prototype.hasOwnProperty.call(payload, 'meta_whatsapp_business_account_id')
      ? normalizeText(payload.meta_whatsapp_business_account_id)
      : current.meta_whatsapp_business_account_id,
    meta_ads_app_id: Object.prototype.hasOwnProperty.call(payload, 'meta_ads_app_id')
      ? normalizeText(payload.meta_ads_app_id)
      : current.meta_ads_app_id,
    meta_ads_app_secret: Object.prototype.hasOwnProperty.call(payload, 'meta_ads_app_secret')
      ? normalizeText(payload.meta_ads_app_secret)
      : current.meta_ads_app_secret,
  };

  await ensureMetaAdsConfigTable();
  const res = await pool.query(
    `INSERT INTO meta_ads_config (
      id,
      meta_ads_access_token,
      meta_ad_account_id,
      meta_whatsapp_phone_number_id,
      meta_whatsapp_business_account_id,
      meta_ads_app_id,
      meta_ads_app_secret,
      created_at,
      updated_at
    ) VALUES ($1,$2,$3,$4,$5,$6,$7, now(), now())
    ON CONFLICT (id) DO UPDATE SET
      meta_ads_access_token = EXCLUDED.meta_ads_access_token,
      meta_ad_account_id = EXCLUDED.meta_ad_account_id,
      meta_whatsapp_phone_number_id = EXCLUDED.meta_whatsapp_phone_number_id,
      meta_whatsapp_business_account_id = EXCLUDED.meta_whatsapp_business_account_id,
      meta_ads_app_id = EXCLUDED.meta_ads_app_id,
      meta_ads_app_secret = EXCLUDED.meta_ads_app_secret,
      updated_at = now()
    RETURNING updated_at`,
    [
      META_ADS_CONFIG_ID,
      next.meta_ads_access_token || null,
      next.meta_ad_account_id || null,
      next.meta_whatsapp_phone_number_id || null,
      next.meta_whatsapp_business_account_id || null,
      next.meta_ads_app_id || null,
      next.meta_ads_app_secret || null,
    ]
  );

  const cfg = await getMetaAdsConfigForAdmin();
  cfg.updated_at = res.rows[0] ? res.rows[0].updated_at : cfg.updated_at;
  return cfg;
}

async function graphRequest({ method = 'GET', endpoint, token, query = {}, body = null }) {
  const cleanToken = normalizeText(token);
  if (!cleanToken) {
    throw new Error('Token Meta Ads no configurado');
  }
  const url = new URL(`https://graph.facebook.com/v20.0/${String(endpoint || '').replace(/^\/+/, '')}`);
  Object.entries(query || {}).forEach(([k, v]) => {
    if (v !== undefined && v !== null && `${v}` !== '') {
      url.searchParams.set(k, `${v}`);
    }
  });
  url.searchParams.set('access_token', cleanToken);

  const req = {
    method,
    headers: {
      Accept: 'application/json',
    },
  };

  if (body && method !== 'GET') {
    const form = new URLSearchParams();
    Object.entries(body).forEach(([k, v]) => {
      if (v !== undefined && v !== null) {
        form.set(k, typeof v === 'string' ? v : JSON.stringify(v));
      }
    });
    req.headers['Content-Type'] = 'application/x-www-form-urlencoded';
    req.body = form;
  }

  const response = await fetch(url, req);
  let data = null;
  try {
    data = await response.json();
  } catch (_) {
    data = null;
  }

  if (!response.ok || (data && data.error)) {
    throw toGraphApiError(data, `Meta Graph HTTP ${response.status}`, response.status);
  }

  return data || {};
}

function statusLine(key, ok, details) {
  return {
    key,
    ok,
    details,
  };
}

function isPermission10(error) {
  const code = error && error.graphError ? error.graphError.code : null;
  return Number(code) === 10;
}

async function testMetaAdsConnection() {
  const cfg = await getRuntimeConfig();
  const token = cfg.meta_ads_access_token || cfg.organic_access_token;
  const adAccountId = cfg.meta_ad_account_id;
  const checks = [];
  const warnings = [];

  if (!token) {
    return {
      ok: false,
      checks: [statusLine('token', false, 'No hay token configurado')],
      warnings,
      token_source: 'none',
      token_masked: '',
    };
  }

  let tokenOk = false;
  try {
    const me = await graphRequest({ endpoint: 'me', token, query: { fields: 'id,name' } });
    tokenOk = true;
    checks.push(statusLine('token', true, `Token válido para ${me.name || me.id || 'usuario'}`));
  } catch (error) {
    checks.push(statusLine('token', false, error.message));
    return {
      ok: false,
      checks,
      warnings,
      token_source: cfg.meta_ads_access_token ? 'meta_ads' : 'organic_fallback',
      token_masked: maskSecret(token),
    };
  }

  if (tokenOk) {
    try {
      const perms = await graphRequest({ endpoint: 'me/permissions', token });
      const rows = Array.isArray(perms.data) ? perms.data : [];
      const adsMgmt = rows.find((item) => String(item.permission || '').toLowerCase() === 'ads_management');
      const granted = adsMgmt && String(adsMgmt.status || '').toLowerCase() === 'granted';
      checks.push(statusLine('ads_management', Boolean(granted), granted ? 'Permiso ads_management concedido' : 'Permiso ads_management no concedido'));
    } catch (error) {
      checks.push(statusLine('ads_management', false, error.message));
    }
  }

  if (!adAccountId) {
    checks.push(statusLine('ad_account', false, 'META_AD_ACCOUNT_ID no configurado'));
  } else {
    try {
      const acc = await graphRequest({
        endpoint: adAccountId,
        token,
        query: { fields: 'id,name,account_status' },
      });
      checks.push(statusLine('ad_account', true, `Acceso OK a ${acc.name || acc.id || adAccountId}`));
    } catch (error) {
      checks.push(statusLine('ad_account', false, error.message));
    }

    try {
      await graphRequest({
        endpoint: `${adAccountId}/campaigns`,
        token,
        query: { limit: '1', fields: 'id,name,status' },
      });
      checks.push(statusLine('campaign_access', true, 'Acceso a campañas OK'));
    } catch (error) {
      checks.push(statusLine('campaign_access', false, error.message));
    }

    try {
      await graphRequest({
        endpoint: `${adAccountId}/adcreatives`,
        token,
        query: { limit: '1', fields: 'id,name' },
      });
      checks.push(statusLine('creative_access', true, 'Acceso a creatives OK'));
    } catch (error) {
      checks.push(statusLine('creative_access', false, error.message));
    }
  }

  if (cfg.meta_whatsapp_phone_number_id) {
    try {
      const wa = await graphRequest({
        endpoint: cfg.meta_whatsapp_phone_number_id,
        token,
        query: { fields: 'id,display_phone_number,verified_name' },
      });
      const name = wa.display_phone_number || wa.verified_name || wa.id;
      checks.push(statusLine('whatsapp_phone', true, `Acceso WhatsApp OK (${name})`));
    } catch (error) {
      if (isPermission10(error)) {
        const warning = 'El token no puede consultar el número, pero se intentará usarlo al crear el anuncio.';
        checks.push(statusLine('whatsapp_phone', true, warning));
        warnings.push(warning);
      } else {
        checks.push(statusLine('whatsapp_phone', false, error.message));
      }
    }
  } else {
    checks.push(statusLine('whatsapp_phone', false, 'META_WHATSAPP_PHONE_NUMBER_ID no configurado'));
  }

  const requiredKeys = ['token', 'ads_management', 'ad_account', 'campaign_access', 'creative_access'];
  const requiredFailed = checks.some((item) => requiredKeys.includes(item.key) && !item.ok);

  return {
    ok: !requiredFailed,
    checks,
    warnings,
    token_source: cfg.meta_ads_access_token ? 'meta_ads' : 'organic_fallback',
    token_masked: maskSecret(token),
  };
}

async function createMetaAdsCampaign(payload) {
  const cfg = await getRuntimeConfig();
  const token = cfg.meta_ads_access_token || cfg.organic_access_token;
  if (!token) {
    const err = new Error('No hay token configurado para campañas (META_ADS_ACCESS_TOKEN)');
    err.statusCode = 400;
    throw err;
  }

  const adAccountId = normalizeAdAccountId(payload.ad_account_id || cfg.meta_ad_account_id);
  if (!adAccountId) {
    const err = new Error('Ad Account ID no configurado');
    err.statusCode = 400;
    throw err;
  }

  const pageId = normalizeText(payload.facebook_page_id || cfg.organic_facebook_page_id);
  const instagramActorId = normalizeText(payload.instagram_business_id || cfg.organic_instagram_business_id);
  const whatsappPhoneId = normalizeText(payload.whatsapp_phone_number_id || cfg.meta_whatsapp_phone_number_id);
  const campaignName = normalizeText(payload.name) || `Campaña ${new Date().toISOString()}`;

  const warnings = [];
  if (whatsappPhoneId) {
    try {
      await graphRequest({
        endpoint: whatsappPhoneId,
        token,
        query: { fields: 'id' },
      });
    } catch (error) {
      if (isPermission10(error)) {
        warnings.push('El token no puede consultar el número, pero se intentará usarlo al crear el anuncio.');
      } else {
        throw error;
      }
    }
  }

  const campaign = await graphRequest({
    method: 'POST',
    endpoint: `${adAccountId}/campaigns`,
    token,
    body: {
      name: campaignName,
      objective: normalizeText(payload.objective) || 'OUTCOME_ENGAGEMENT',
      status: normalizeText(payload.status) || 'PAUSED',
      special_ad_categories: [],
    },
  });

  let adset = null;
  let creative = null;
  let ad = null;

  const dailyBudget = Number(payload.daily_budget || 500);
  const countries = Array.isArray(payload.countries) && payload.countries.length
    ? payload.countries
    : ['DO'];

  adset = await graphRequest({
    method: 'POST',
    endpoint: `${adAccountId}/adsets`,
    token,
    body: {
      name: normalizeText(payload.adset_name) || `${campaignName} - Ad Set`,
      campaign_id: campaign.id,
      daily_budget: Number.isFinite(dailyBudget) && dailyBudget > 0 ? Math.floor(dailyBudget) : 500,
      billing_event: 'IMPRESSIONS',
      optimization_goal: normalizeText(payload.optimization_goal) || 'REACH',
      bid_strategy: 'LOWEST_COST_WITHOUT_CAP',
      targeting: {
        geo_locations: { countries },
      },
      promoted_object: {
        page_id: pageId || undefined,
        whatsapp_phone_number: whatsappPhoneId || undefined,
      },
      status: 'PAUSED',
    },
  });

  const destinationLink = normalizeText(payload.destination_link) || 'https://wa.me/18295344286';
  const primaryText = normalizeText(payload.message) || 'Escribenos por WhatsApp para mas informacion.';

  const creativeBody = {
    name: normalizeText(payload.creative_name) || `${campaignName} - Creative`,
    object_story_spec: {
      page_id: pageId,
      link_data: {
        link: destinationLink,
        message: primaryText,
        call_to_action: {
          type: 'WHATSAPP_MESSAGE',
          value: {
            app_destination: 'WHATSAPP',
            link: destinationLink,
          },
        },
      },
    },
  };

  if (instagramActorId) {
    creativeBody.object_story_spec.instagram_actor_id = instagramActorId;
  }

  try {
    creative = await graphRequest({
      method: 'POST',
      endpoint: `${adAccountId}/adcreatives`,
      token,
      body: creativeBody,
    });
  } catch (error) {
    error.statusCode = error.statusCode || 400;
    throw error;
  }

  ad = await graphRequest({
    method: 'POST',
    endpoint: `${adAccountId}/ads`,
    token,
    body: {
      name: normalizeText(payload.ad_name) || `${campaignName} - Ad`,
      adset_id: adset.id,
      creative: { creative_id: creative.id },
      status: 'PAUSED',
    },
  });

  return {
    ok: true,
    warnings,
    token_source: cfg.meta_ads_access_token ? 'meta_ads' : 'organic_fallback',
    token_masked: maskSecret(token),
    campaign,
    adset,
    creative,
    ad,
  };
}

module.exports = {
  getMetaAdsConfigForAdmin,
  updateMetaAdsConfig,
  testMetaAdsConnection,
  createMetaAdsCampaign,
  maskSecret,
};
