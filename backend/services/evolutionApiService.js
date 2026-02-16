const { getEvolutionConfig } = require('./evolutionConfigService');

function cleanPhone(input) {
  return String(input || '').replace(/[^0-9]/g, '');
}

function formatTemplate(template, params) {
  let text = String(template || '').trim();
  for (const [key, value] of Object.entries(params || {})) {
    text = text.replaceAll(`{${key}}`, String(value ?? ''));
  }
  return text;
}

async function sendPasswordResetCode({ toPhone, code }) {
  const config = await getEvolutionConfig();
  if (!config.enabled) {
    const err = new Error('Evolution API está deshabilitada');
    err.code = 'EVOLUTION_DISABLED';
    throw err;
  }

  if (!config.base_url || !config.instance_name || !config.api_key) {
    const err = new Error('Configuración Evolution incompleta');
    err.code = 'EVOLUTION_CONFIG_INCOMPLETE';
    throw err;
  }

  const phone = cleanPhone(toPhone);
  if (!phone) {
    const err = new Error('Número destino inválido');
    err.code = 'PHONE_INVALID';
    throw err;
  }

  const text = formatTemplate(config.template_text, {
    code,
    ttl_minutes: config.otp_ttl_minutes
  });

  const url = `${config.base_url}/message/sendText/${encodeURIComponent(config.instance_name)}`;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), Math.max(1000, Number(config.send_timeout_ms || 12000)));

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: config.api_key
      },
      body: JSON.stringify({
        number: phone,
        text,
        delay: 0,
        ...(config.from_number ? { from: cleanPhone(config.from_number) } : {})
      }),
      signal: controller.signal
    });

    const raw = await response.text();
    let parsed = null;
    try {
      parsed = raw ? JSON.parse(raw) : null;
    } catch (_) {}

    if (!response.ok) {
      const err = new Error(`Evolution API HTTP ${response.status}`);
      err.code = 'EVOLUTION_HTTP_ERROR';
      err.status = response.status;
      err.responseBody = parsed || raw;
      throw err;
    }

    return {
      ok: true,
      status: response.status,
      response: parsed || raw
    };
  } catch (error) {
    if (error && error.name === 'AbortError') {
      const err = new Error('Timeout enviando mensaje por Evolution API');
      err.code = 'EVOLUTION_TIMEOUT';
      throw err;
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

module.exports = {
  sendPasswordResetCode
};
