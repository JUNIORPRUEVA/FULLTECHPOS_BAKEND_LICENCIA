const base = 'https://fullpos-backend-fullposlicenciaswed.onqyr1.easypanel.host';

async function request(path, options = {}) {
  const response = await fetch(`${base}${path}`, {
    ...options,
    headers: {
      'content-type': 'application/json',
      ...(options.headers || {})
    }
  });

  const text = await response.text();
  let data = {};
  try {
    data = text ? JSON.parse(text) : {};
  } catch (_) {
    data = { raw: text };
  }

  return {
    ok: response.ok,
    status: response.status,
    data
  };
}

(async () => {
  const login = await request('/api/login', {
    method: 'POST',
    body: JSON.stringify({
      username: 'fulltechsd@gmail.com',
      password: 'Ayleen10'
    })
  });

  console.log('LOGIN', login.status, login.data?.success === true ? 'OK' : 'FAIL');

  const sessionId = login.data?.sessionId || '';

  const cfg = await request('/api/admin/support-message-config', {
    method: 'GET',
    headers: {
      'x-session-id': sessionId
    }
  });

  console.log(
    'CONFIG',
    cfg.status,
    cfg.data?.ok === true ? 'OK' : 'FAIL',
    `base_url=${cfg.data?.config?.base_url || ''}`,
    `instance=${cfg.data?.config?.instance_name || ''}`,
    `api_key=${cfg.data?.config?.api_key_masked || ''}`
  );

  const send = await request('/api/support/request', {
    method: 'POST',
    body: JSON.stringify({
      business_id: 'FT-PRUEBA-E2E',
      username: 'admin',
      business_name: 'NEGOCIO PRUEBA E2E',
      owner_name: 'Soporte QA',
      phone: '8295319442',
      email: 'qa@fulltechrd.com',
      message: 'Prueba E2E desde VS Code para validar envío por instancia configurada en nube.'
    })
  });

  console.log(
    'SEND',
    send.status,
    send.data?.ok === true ? 'OK' : 'FAIL',
    `provider_status=${send.data?.status || ''}`,
    `message=${send.data?.message || ''}`
  );

  if (!send.ok) {
    console.log('SEND_JSON', JSON.stringify(send.data));
    process.exitCode = 1;
  }
})().catch((error) => {
  console.error('E2E_ERROR', error?.message || error);
  process.exit(1);
});
