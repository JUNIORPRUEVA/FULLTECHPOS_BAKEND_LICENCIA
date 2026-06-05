const { pool } = require('../db/pool');
const projectsModel = require('../models/projectsModel');
const licensesModel = require('../models/licensesModel');
const crypto = require('crypto');
const { getPrivateKeyPem } = require('../utils/licenseFile');
const { generateLicenseKey } = require('../utils/licenseKey');
const licenseChangeBus = require('../services/licenseChangeBus');
const {
  normalizeBusinessId,
  isValidBusinessIdForExistingRecord,
  resolveBusinessIdForNewRecord,
  emitBusinessIdAudit,
} = require('../services/businessIdPolicyService');

function asTrimmed(value) {
  const v = String(value || '').trim();
  return v ? v : '';
}

function normalizePhone(phone) {
  return String(phone || '').replace(/[^0-9]/g, '');
}

function normalizeEmail(email) {
  const value = String(email || '').trim();
  return value ? value.toLowerCase() : '';
}

function safeIsoDate(value) {
  try {
    if (!value) return null;
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return null;
    return d.toISOString();
  } catch (_) {
    return null;
  }
}

function toBase64Url(input) {
  const buf = Buffer.isBuffer(input) ? input : Buffer.from(String(input), 'utf8');
  return buf
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function signPayloadEd25519(payload) {
  // IMPORTANT: keep stable serialization for signature.
  const payloadJson = JSON.stringify(payload);
  const privateKeyPem = getPrivateKeyPem();
  const signature = crypto.sign(null, Buffer.from(payloadJson, 'utf8'), privateKeyPem);
  return {
    payload,
    signature: signature.toString('base64'),
    alg: 'Ed25519'
  };
}

function buildBusinessLicensePayload({ businessId, license, project }) {
  // IMPORTANT: keep insertion order stable (used for signing)
  return {
    v: 1,
    business_id: String(businessId || '').trim(),
    project_code: String(project?.code || '').toUpperCase(),
    license_key: String(license?.license_key || '').trim(),
    plan: String(license?.tipo || '').toUpperCase(),
    estado: String(license?.estado || '').toUpperCase(),
    // Motivo/Notas (admin). Se muestra al usuario cuando está BLOQUEADA.
    motivo: license?.notas ? String(license.notas) : null,
    starts_at: license?.fecha_inicio ? new Date(license.fecha_inicio).toISOString() : null,
    expires_at: license?.fecha_fin ? new Date(license.fecha_fin).toISOString() : null,
    features: [],
    limits: {
      max_devices: Number(license?.max_dispositivos)
    },
    // Compat: algunos clientes esperan max_devices en la raíz.
    max_devices: Number(license?.max_dispositivos),
    issued_at: new Date().toISOString()
  };
}

function addDaysIso(iso, days) {
  try {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return null;
    d.setUTCDate(d.getUTCDate() + Number(days || 0));
    return d.toISOString();
  } catch (_) {
    return null;
  }
}

function isWithinDaysFromNow(iso, days) {
  try {
    if (!iso) return false;
    const start = new Date(iso);
    if (Number.isNaN(start.getTime())) return false;
    const endIso = addDaysIso(start.toISOString(), days);
    if (!endIso) return false;
    const end = new Date(endIso);
    const now = new Date();
    return now.getTime() < end.getTime();
  } catch (_) {
    return false;
  }
}

async function ensurePersistedTrialLicense({
  customerId,
  businessId,
  project,
  trialStartAt,
  trialDays,
}) {
  const startIso = safeIsoDate(trialStartAt);
  const endIso = startIso ? addDaysIso(startIso, trialDays) : null;
  if (!customerId || !project?.id || !startIso || !endIso) return null;

  const notes = `Auto DEMO (business trial) project=${String(project.code || 'FULLPOS').toUpperCase()} business=${asTrimmed(businessId) || 'N/A'}`;

  const deletedRes = await pool.query(
    `SELECT id
     FROM licenses
     WHERE customer_id = $1
       AND project_id = $2
       AND tipo = 'DEMO'
       AND estado::text = 'ELIMINADA'
     ORDER BY created_at DESC
     LIMIT 1`,
    [customerId, project.id]
  );
  if (deletedRes.rows[0]) {
    return null;
  }

  const existingRes = await pool.query(
    `SELECT *
     FROM licenses
     WHERE customer_id = $1
       AND project_id = $2
       AND tipo = 'DEMO'
       AND estado::text <> 'ELIMINADA'
     ORDER BY created_at DESC
     LIMIT 1`,
    [customerId, project.id]
  );
  const existing = existingRes.rows[0] || null;

  const persistUpdate = async (licenseId) => {
    const attempts = [
      async () =>
        pool.query(
          `UPDATE licenses
           SET fecha_inicio = $2::timestamp,
               fecha_fin = $3::timestamp,
               expires_at = $4::timestamptz,
               dias_validez = $5,
               max_dispositivos = 1,
               estado = 'ACTIVA',
               notas = $6,
               activation_source = 'demo'
           WHERE id = $1
           RETURNING *`,
          [licenseId, startIso, endIso, endIso, trialDays, notes]
        ),
      async () =>
        pool.query(
          `UPDATE licenses
           SET fecha_inicio = $2::timestamp,
               fecha_fin = $3::timestamp,
               dias_validez = $4,
               max_dispositivos = 1,
               estado = 'ACTIVA',
               notas = $5,
               activation_source = 'demo'
           WHERE id = $1
           RETURNING *`,
          [licenseId, startIso, endIso, trialDays, notes]
        ),
      async () =>
        pool.query(
          `UPDATE licenses
           SET fecha_inicio = $2::timestamp,
               fecha_fin = $3::timestamp,
               dias_validez = $4,
               max_dispositivos = 1,
               estado = 'ACTIVA',
               notas = $5
           WHERE id = $1
           RETURNING *`,
          [licenseId, startIso, endIso, trialDays, notes]
        ),
    ];

    let lastError = null;
    for (const attempt of attempts) {
      try {
        const result = await attempt();
        return result.rows[0] || null;
      } catch (error) {
        lastError = error;
        if (error && (error.code === '42703' || error.code === '42P01')) continue;
        throw error;
      }
    }
    throw lastError || new Error('No se pudo persistir la licencia DEMO');
  };

  if (existing) {
    if (String(existing.estado || '').trim().toUpperCase() === 'BLOQUEADA') {
      return existing;
    }
    return persistUpdate(existing.id);
  }

  let created = null;
  for (let i = 0; i < 6; i += 1) {
    try {
      created = await licensesModel.createLicenseWithKey({
        project_id: project.id,
        customer_id: customerId,
        license_key: generateLicenseKey('DEMO'),
        tipo: 'DEMO',
        dias_validez: trialDays,
        max_dispositivos: 1,
        notas: notes,
      });
      break;
    } catch (error) {
      if (error && error.code === '23505') continue;
      throw error;
    }
  }

  if (!created) {
    throw new Error('No se pudo crear la licencia DEMO persistida');
  }

  return persistUpdate(created.id);
}

async function register(req, res) {
  const incomingBusinessId = normalizeBusinessId(req.body?.business_id);
  const business_name = asTrimmed(req.body?.business_name);
  const role = asTrimmed(req.body?.role);
  const owner_name = asTrimmed(req.body?.owner_name);
  const phone = normalizePhone(req.body?.phone);
  const email = normalizeEmail(req.body?.email);
  const trial_start = asTrimmed(req.body?.trial_start);
  const app_version = asTrimmed(req.body?.app_version);

  if (!business_name) {
    return res.status(400).json({ ok: false, message: 'business_name es requerido' });
  }
  if (!role) {
    return res.status(400).json({ ok: false, message: 'role es requerido' });
  }
  if (!owner_name) {
    return res.status(400).json({ ok: false, message: 'owner_name es requerido' });
  }
  if (!phone) {
    return res.status(400).json({ ok: false, message: 'phone es requerido' });
  }

  const trialStartAt = safeIsoDate(trial_start);
  let generatedBusinessId = false;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    let business_id = incomingBusinessId;
    if (business_id) {
      const existingIncomingValid = await isValidBusinessIdForExistingRecord(business_id, { client });
      if (!existingIncomingValid && !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(business_id)) {
        await client.query('ROLLBACK');
        return res.status(400).json({
          ok: false,
          code: 'INVALID_NEW_BUSINESS_ID',
          message: 'Para nuevos registros, business_id debe ser UUID v4. Los formatos legacy solo se aceptan si ya existen.',
        });
      }
    }

    const existingRes = await client.query(
      'SELECT * FROM customers WHERE business_id = $1 LIMIT 1 FOR UPDATE',
      [business_id]
    );

    let customer = existingRes.rows[0] || null;

    // If admin pre-created the customer without business_id, match by contact and attach business_id.
    // This avoids unique constraint failures on contacto_telefono/contacto_email.
    if (!customer) {
      let byPhone = null;
      if (phone) {
        const byPhoneRes = await client.query(
          `SELECT *
           FROM customers
           WHERE regexp_replace(coalesce(contacto_telefono, ''), '[^0-9]', '', 'g') = $1
           ORDER BY created_at ASC
           LIMIT 1
           FOR UPDATE`,
          [phone]
        );
        byPhone = byPhoneRes.rows[0] || null;
      }

      let byEmail = null;
      if (!byPhone && email) {
        const byEmailRes = await client.query(
          `SELECT *
           FROM customers
           WHERE lower(coalesce(contacto_email, '')) = $1
           ORDER BY created_at ASC
           LIMIT 1
           FOR UPDATE`,
          [email]
        );
        byEmail = byEmailRes.rows[0] || null;
      }

      const matched = byPhone || byEmail;
      if (matched) {
        const existingBiz = asTrimmed(matched.business_id);
        if (!business_id) {
          business_id = existingBiz || await resolveBusinessIdForNewRecord(null);
          generatedBusinessId = !existingBiz;
        }
        if (existingBiz && existingBiz !== business_id) {
          await emitBusinessIdAudit(
            {
              event: 'conflict_detected',
              source: 'businesses_register',
              action: 'blocked',
              reason: 'El cliente existente ya tiene otro business_id asignado',
              severity: 'critical',
              currentBusinessId: existingBiz,
              incomingBusinessId: business_id,
              resolvedBusinessId: existingBiz,
              customerId: matched.id,
            },
            { req, client }
          );
          await client.query('ROLLBACK');
          return res.status(409).json({
            ok: false,
            code: 'BUSINESS_ID_CONFLICT',
            message: 'Este cliente ya tiene otro business_id asignado',
            existing_business_id: existingBiz,
          });
        }

        const upd = await client.query(
          `UPDATE customers
           SET business_id = COALESCE(customers.business_id, $2),
               nombre_negocio = $3,
               rol_negocio = $4,
               contacto_nombre = $5,
               contacto_telefono = $6,
               contacto_email = $7,
               trial_start_at = COALESCE(customers.trial_start_at, $8),
               app_version = COALESCE($9, customers.app_version)
           WHERE id = $1
           RETURNING *`,
          [
            matched.id,
            business_id,
            business_name,
            role,
            owner_name,
            phone,
            email || null,
            trialStartAt,
            app_version || null
          ]
        );
        customer = upd.rows[0] || matched;
      }
    }

    if (!customer) {
      business_id = await resolveBusinessIdForNewRecord(business_id);
      generatedBusinessId = !incomingBusinessId;
      const ins = await client.query(
        `INSERT INTO customers (business_id, nombre_negocio, rol_negocio, contacto_nombre, contacto_telefono, contacto_email, trial_start_at, app_version)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         RETURNING *`,
        [
          business_id,
          business_name,
          role,
          owner_name,
          phone,
          email || null,
          trialStartAt,
          app_version || null
        ]
      );
      customer = ins.rows[0];
    } else {
      business_id = asTrimmed(customer.business_id) || await resolveBusinessIdForNewRecord(business_id);
      // Update mutable fields (keep existing trial_start_at if already set).
      const upd = await client.query(
        `UPDATE customers
         SET nombre_negocio = $2,
             rol_negocio = $3,
             contacto_nombre = $4,
             contacto_telefono = $5,
             contacto_email = $6,
             trial_start_at = COALESCE(customers.trial_start_at, $7),
             app_version = COALESCE($8, customers.app_version)
         WHERE business_id = $1
         RETURNING *`,
        [
          business_id,
          business_name,
          role,
          owner_name,
          phone,
          email || null,
          trialStartAt,
          app_version || null
        ]
      );
      customer = upd.rows[0] || customer;
    }

    await emitBusinessIdAudit(
      {
        event: generatedBusinessId ? 'initial_set' : 'read',
        source: 'businesses_register',
        action: generatedBusinessId ? 'generated' : 'allowed',
        reason: generatedBusinessId ? 'Business ID generado formalmente en backend' : 'Registro reutilizó business_id existente',
        severity: 'info',
        currentBusinessId: customer?.business_id || null,
        incomingBusinessId,
        resolvedBusinessId: business_id,
        customerId: customer?.id || null,
      },
      { req, client }
    );

    await client.query('COMMIT');
    return res.json({
      ok: true,
      business_id,
      customer: {
        id: customer.id,
        business_id: customer.business_id,
        nombre_negocio: customer.nombre_negocio,
        contacto_telefono: customer.contacto_telefono,
        contacto_email: customer.contacto_email,
        rol_negocio: customer.rol_negocio,
        created_at: customer.created_at
      }
    });
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}

    // 23505 = unique_violation
    if (error && error.code === '23505') {
      const constraint = String(error.constraint || '');

      if (constraint.includes('business_id') || constraint.includes('idx_customers_business_id_unique')) {
        return res.status(409).json({ ok: false, code: 'BUSINESS_ID_CONFLICT', message: 'business_id ya existe' });
      }

      if (constraint.includes('contacto_telefono')) {
        return res.status(409).json({ ok: false, code: 'PHONE_CONFLICT', message: 'Ya existe un cliente con ese teléfono' });
      }

      if (constraint.includes('contacto_email')) {
        return res.status(409).json({ ok: false, code: 'EMAIL_CONFLICT', message: 'Ya existe un cliente con ese email' });
      }

      return res.status(409).json({ ok: false, code: 'CONFLICT', message: 'Conflicto: cliente duplicado' });
    }

    const pgCode = error && error.code ? String(error.code) : '';
    if (pgCode === '42703' || pgCode === '42P01') {
      console.error('businesses.register DB schema error:', { code: pgCode, message: error?.message });
      return res.status(500).json({
        ok: false,
        code: 'DB_SCHEMA_OUTDATED',
        message: 'Esquema de base de datos desactualizado (faltan migraciones).',
        pg: pgCode
      });
    }

    console.error('businesses.register error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  } finally {
    client.release();
  }
}

async function getLicense(req, res) {
  const businessId = asTrimmed(req.params?.business_id);
  if (!businessId) {
    return res.status(400).json({ ok: false, message: 'business_id es requerido' });
  }

  try {
    const custRes = await pool.query('SELECT * FROM customers WHERE business_id = $1 LIMIT 1', [businessId]);
    const customer = custRes.rows[0] || null;
    if (!customer) {
      return res.status(404).json({ ok: false, code: 'BUSINESS_NOT_FOUND', message: 'Negocio no encontrado' });
    }

    // FULLPOS: prefer project FULLPOS, fallback to default.
    let project = await projectsModel.getProjectByCode('FULLPOS');
    if (!project) project = await projectsModel.getDefaultProject();
    if (!project) {
      return res.status(500).json({ ok: false, message: 'Proyecto no configurado' });
    }

    const licRes = await pool.query(
      `SELECT *
       FROM licenses
       WHERE customer_id = $1 AND project_id = $2
       ORDER BY created_at DESC
       LIMIT 25`,
      [customer.id, project.id]
    );

    const now = new Date();

    let chosen = null;
    let blocked = null;
    let hasDeletedMarker = false;
    for (const l of licRes.rows) {
      if (!l) continue;
      if (String(l.estado || '').toUpperCase() === 'ELIMINADA') {
        hasDeletedMarker = true;
      }
      if (String(l.estado || '').toUpperCase() === 'BLOQUEADA') {
        blocked = l;
        break;
      }
      if (String(l.estado || '').toUpperCase() === 'VENCIDA') {
        continue;
      }
      if (!l.fecha_inicio || !l.fecha_fin) {
        // Not started/activated yet.
        continue;
      }
      const fin = new Date(l.fecha_fin);
      if (!Number.isNaN(fin.getTime()) && fin.getTime() < now.getTime()) {
        try {
          await pool.query(`UPDATE licenses SET estado = 'VENCIDA' WHERE id = $1 AND estado <> 'VENCIDA'`, [l.id]);
        } catch (_) {}
        continue;
      }
      if (String(l.estado || '').toUpperCase() !== 'ACTIVA') {
        continue;
      }
      chosen = l;
      break;
    }

    // Si está BLOQUEADA, devolver token bloqueado para que el cliente muestre
    // inmediatamente la pantalla de bloqueo (y no se quede en TRIAL/local).
    if (blocked) {
      const payload = buildBusinessLicensePayload({ businessId, license: blocked, project });
      const licenseFile = signPayloadEd25519(payload);
      const token = toBase64Url(JSON.stringify(licenseFile));
      return res.json({
        ok: true,
        business_id: businessId,
        license_token: token,
        plan: payload.plan,
        starts_at: payload.starts_at,
        expires_at: payload.expires_at,
        estado: payload.estado
      });
    }

    if (!chosen) {
      // Si el admin eliminó la licencia explícitamente, NO emitir token TRIAL.
      // Esto permite que el cliente aplique la revocación casi al instante.
      if (hasDeletedMarker) {
        return res.status(204).send();
      }

      // TRIAL: si el negocio tiene trial_start_at y aún está dentro de ventana,
      // emitir un token TRIAL firmado. El cliente lo puede guardar local y
      // seguir funcionando offline-first.
      const trialStartAt = customer.trial_start_at ? new Date(customer.trial_start_at).toISOString() : null;
      const TRIAL_DAYS = 5;
      if (trialStartAt && isWithinDaysFromNow(trialStartAt, TRIAL_DAYS)) {
        let trialLicense = null;
        try {
          trialLicense = await ensurePersistedTrialLicense({
            customerId: customer.id,
            businessId,
            project,
            trialStartAt,
            trialDays: TRIAL_DAYS,
          });
        } catch (persistError) {
          console.error('businesses.getLicense persist trial error:', persistError);
        }

        if (!trialLicense) {
          trialLicense = {
            license_key: `TRIAL-${businessId}`,
            tipo: 'TRIAL',
            estado: 'ACTIVA',
            fecha_inicio: trialStartAt,
            fecha_fin: addDaysIso(trialStartAt, TRIAL_DAYS),
            max_dispositivos: 1,
            notas: 'Fallback trial token (non-persisted)',
          };
        }
        const payload = buildBusinessLicensePayload({ businessId, license: trialLicense, project });
        const licenseFile = signPayloadEd25519(payload);
        const token = toBase64Url(JSON.stringify(licenseFile));
        return res.json({
          ok: true,
          business_id: businessId,
          license_token: token,
          plan: payload.plan,
          starts_at: payload.starts_at,
          expires_at: payload.expires_at,
          estado: payload.estado
        });
      }

      return res.status(204).send();
    }

    const payload = buildBusinessLicensePayload({ businessId, license: chosen, project });
    const licenseFile = signPayloadEd25519(payload);
    const token = toBase64Url(JSON.stringify(licenseFile));

    return res.json({
      ok: true,
      business_id: businessId,
      license_token: token,
      plan: payload.plan,
      starts_at: payload.starts_at,
      expires_at: payload.expires_at
    });
  } catch (error) {
    const pgCode = error && error.code ? String(error.code) : '';
    if (pgCode === '42703' || pgCode === '42P01') {
      console.error('businesses.getLicense DB schema error:', { code: pgCode, message: error?.message });
      return res.status(500).json({
        ok: false,
        code: 'DB_SCHEMA_OUTDATED',
        message: 'Esquema de base de datos desactualizado (faltan migraciones).',
        pg: pgCode
      });
    }

    console.error('businesses.getLicense error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function streamLicenseChanges(req, res) {
  const businessId = asTrimmed(req.params?.business_id);
  if (!businessId) {
    return res.status(400).json({ ok: false, message: 'business_id es requerido' });
  }

  // Server-Sent Events (SSE) stream.
  res.status(200);
  res.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
  res.setHeader('Cache-Control', 'no-cache, no-transform');
  res.setHeader('Connection', 'keep-alive');
  // Prevent buffering on some reverse proxies.
  res.setHeader('X-Accel-Buffering', 'no');

  try {
    res.flushHeaders?.();
  } catch (_) {}

  // Suggest client retry delay (ms) when disconnected.
  res.write('retry: 1000\n');

  // Initial event so clients know the stream is up.
  res.write(
    `event: ready\n` +
      `data: ${JSON.stringify({ ok: true, business_id: businessId, ts: new Date().toISOString() })}\n\n`
  );

  const keepAlive = setInterval(() => {
    try {
      // SSE comment line as heartbeat.
      res.write(`: ping ${Date.now()}\n\n`);
    } catch (_) {}
  }, 15000);

  const unsubscribe = licenseChangeBus.onBusinessLicenseChanged(businessId, (payload) => {
    try {
      res.write(`event: license_changed\ndata: ${JSON.stringify(payload || { business_id: businessId, ts: new Date().toISOString() })}\n\n`);
    } catch (_) {}
  });

  const cleanup = () => {
    try {
      clearInterval(keepAlive);
    } catch (_) {}
    try {
      unsubscribe();
    } catch (_) {}
    try {
      res.end();
    } catch (_) {}
  };

  // Close events
  req.on('close', cleanup);
  req.on('aborted', cleanup);
}

module.exports = {
  register,
  getLicense,
  streamLicenseChanges
};
