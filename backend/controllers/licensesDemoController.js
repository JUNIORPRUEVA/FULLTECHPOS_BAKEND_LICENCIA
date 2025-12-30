const { pool } = require('../db/pool');
const customersModel = require('../models/customersModel');
const licenseConfigService = require('../services/licenseConfigService');
const { generateLicenseKey } = require('../utils/licenseKey');

function normalizePhone(phone) {
  return String(phone || '').replace(/[^0-9]/g, '');
}

function normalizeEmail(email) {
  const value = String(email || '').trim();
  return value ? value.toLowerCase() : '';
}

function asTrimmed(value) {
  const v = String(value || '').trim();
  return v ? v : '';
}

function isExpiredByDate(license, now) {
  if (!license.fecha_fin) return false;
  return new Date(license.fecha_fin).getTime() < now.getTime();
}

/**
 * POST /api/licenses/start-demo
 * Crea/encuentra cliente, crea licencia DEMO con config y activa inmediatamente en el device.
 */
async function startDemo(req, res) {
  const nombre_negocio = asTrimmed(req.body?.nombre_negocio);
  const contacto_nombre = asTrimmed(req.body?.contacto_nombre);
  const contacto_email = normalizeEmail(req.body?.contacto_email);
  const contacto_telefono = normalizePhone(req.body?.contacto_telefono);
  const device_id = asTrimmed(req.body?.device_id);

  if (!nombre_negocio) {
    return res.status(400).json({ ok: false, message: 'nombre_negocio es requerido' });
  }

  if (!device_id) {
    return res.status(400).json({ ok: false, message: 'device_id es requerido' });
  }

  if (!contacto_email && !contacto_telefono) {
    return res.status(400).json({ ok: false, message: 'contacto_email o contacto_telefono es requerido' });
  }

  const now = new Date();

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // 1) Encontrar o crear cliente
    let customer = await customersModel.findCustomerByContact({
      contacto_email,
      contacto_telefono
    });

    if (!customer) {
      const createdRes = await client.query(
        `INSERT INTO customers (nombre_negocio, contacto_nombre, contacto_telefono, contacto_email)
         VALUES ($1, $2, $3, $4)
         RETURNING *`,
        [
          nombre_negocio,
          contacto_nombre || null,
          contacto_telefono || null,
          contacto_email || null
        ]
      );
      customer = createdRes.rows[0];
    }

    // 2) Si ya existe una DEMO activa para este device, devolverla (idempotente)
    const existingRes = await client.query(
      `SELECT l.*
       FROM licenses l
       JOIN license_activations a ON a.license_id = l.id
       WHERE l.tipo = 'DEMO'
         AND l.customer_id = $1
         AND a.device_id = $2
         AND a.estado = 'ACTIVA'
       ORDER BY l.created_at DESC
       LIMIT 1`,
      [customer.id, device_id]
    );

    const existing = existingRes.rows[0];
    if (existing) {
      // Si venció por fecha, marcar como VENCIDA y continuar a crear otra demo
      if (!isExpiredByDate(existing, now) && existing.estado !== 'BLOQUEADA' && existing.estado !== 'VENCIDA') {
        await client.query('COMMIT');
        return res.json({
          ok: true,
          customer,
          license_key: existing.license_key,
          tipo: existing.tipo,
          fecha_inicio: existing.fecha_inicio,
          fecha_fin: existing.fecha_fin,
          estado: existing.estado
        });
      }
    }

    // 3) Config DEMO
    const config = await licenseConfigService.getLicenseConfig();
    const dias = Math.max(1, Number(config.demo_dias_validez) || 15);
    const maxDisp = Math.max(1, Number(config.demo_max_dispositivos) || 1);

    // 4) Crear licencia DEMO (key único)
    let license;
    for (let i = 0; i < 6; i++) {
      const key = generateLicenseKey('DEMO');
      try {
        const licRes = await client.query(
          `INSERT INTO licenses (customer_id, license_key, tipo, dias_validez, max_dispositivos, estado, notas)
           VALUES ($1, $2, 'DEMO', $3, $4, 'PENDIENTE', $5)
           RETURNING *`,
          [customer.id, key, dias, maxDisp, 'Auto DEMO (start-demo)']
        );
        license = licRes.rows[0];
        break;
      } catch (e) {
        // 23505 = unique_violation
        if (e && e.code === '23505') continue;
        throw e;
      }
    }

    if (!license) {
      await client.query('ROLLBACK');
      return res.status(500).json({ ok: false, message: 'No se pudo generar license_key' });
    }

    // 5) Activar de una vez (asigna fechas + activation)
    const fechaInicio = now;
    const fechaFin = new Date(now.getTime() + dias * 24 * 60 * 60 * 1000);

    const updRes = await client.query(
      `UPDATE licenses
       SET fecha_inicio = $2,
           fecha_fin = $3,
           estado = 'ACTIVA'
       WHERE id = $1
       RETURNING *`,
      [license.id, fechaInicio, fechaFin]
    );
    license = updRes.rows[0];

    await client.query(
      `INSERT INTO license_activations (license_id, device_id, estado)
       VALUES ($1, $2, 'ACTIVA')
       ON CONFLICT (license_id, device_id)
       DO UPDATE SET estado = 'ACTIVA', activated_at = now(), last_check_at = now()`,
      [license.id, device_id]
    );

    await client.query('COMMIT');
    return res.status(201).json({
      ok: true,
      customer,
      license_key: license.license_key,
      tipo: license.tipo,
      fecha_inicio: license.fecha_inicio,
      fecha_fin: license.fecha_fin,
      estado: license.estado,
      max_dispositivos: license.max_dispositivos
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('startDemo error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  } finally {
    client.release();
  }
}

module.exports = {
  startDemo
};
