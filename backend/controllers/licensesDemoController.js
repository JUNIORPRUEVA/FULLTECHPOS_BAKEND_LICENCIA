const { pool } = require('../db/pool');
const customersModel = require('../models/customersModel');
const licenseConfigService = require('../services/licenseConfigService');
const { generateLicenseKey } = require('../utils/licenseKey');
const projectsModel = require('../models/projectsModel');

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
 * Crea/encuentra cliente, crea licencia DEMO y activa inmediatamente en el device.
 * - Opcional: project_code (ej: FULLPOS). Si no existe el proyecto, se auto-crea.
 * - La duración/limites DEMO se controlan desde /admin/license-config.
 */
async function startDemo(req, res) {
  const nombre_negocio = asTrimmed(req.body?.nombre_negocio);
  const rol_negocio = asTrimmed(req.body?.rol_negocio ?? req.body?.business_role);
  const contacto_nombre = asTrimmed(req.body?.contacto_nombre);
  const contacto_email = normalizeEmail(req.body?.contacto_email);
  const contacto_telefono = normalizePhone(req.body?.contacto_telefono);
  const device_id = asTrimmed(req.body?.device_id);
  const project_code_raw = asTrimmed(req.body?.project_code ?? req.body?.projectCode);

  if (!nombre_negocio) {
    return res.status(400).json({ ok: false, message: 'nombre_negocio es requerido' });
  }

  if (!device_id) {
    return res.status(400).json({ ok: false, message: 'device_id es requerido' });
  }

  // FULLPOS: requerimos datos completos para iniciar prueba.
  const projectCodeGuess = String(project_code_raw || '').toUpperCase();
  if (projectCodeGuess === 'FULLPOS') {
    if (!rol_negocio) {
      return res.status(400).json({ ok: false, message: 'rol_negocio es requerido' });
    }
    if (!contacto_nombre) {
      return res.status(400).json({ ok: false, message: 'contacto_nombre es requerido' });
    }
    if (!contacto_telefono) {
      return res.status(400).json({ ok: false, message: 'contacto_telefono es requerido' });
    }
  } else {
    if (!contacto_email && !contacto_telefono) {
      return res.status(400).json({ ok: false, message: 'contacto_email o contacto_telefono es requerido' });
    }
  }

  const now = new Date();

  // Resolver proyecto (multi-proyecto). La DEMO se controla desde license_config.
  let project = null;
  if (project_code_raw) {
    project = await projectsModel.getProjectByCode(project_code_raw);
    if (!project) {
      project = await projectsModel.createProject({
        code: project_code_raw,
        name: project_code_raw,
        description: 'Auto-created by start-demo'
      });
    }
  }
  if (!project) {
    project = await projectsModel.getDefaultProject();
  }
  if (!project) {
    project = await projectsModel.createProject({
      code: 'DEFAULT',
      name: 'DEFAULT',
      description: 'Auto-created by start-demo'
    });
  }

  const projectCode = String(project.code || '').toUpperCase();

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // 1) Encontrar o crear cliente
    let customer = await customersModel.findCustomerByContact({
      contacto_email,
      contacto_telefono
    });

    if (!customer) {
      try {
        const createdRes = await client.query(
          `INSERT INTO customers (nombre_negocio, contacto_nombre, contacto_telefono, contacto_email, rol_negocio)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING *`,
          [
            nombre_negocio,
            contacto_nombre || null,
            contacto_telefono || null,
            contacto_email || null,
            rol_negocio || null
          ]
        );
        customer = createdRes.rows[0];
      } catch (e) {
        // 42703 = undefined_column (migration pending)
        if (e && e.code === '42703') {
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
        } else {
          throw e;
        }
      }
    } else {
      // Actualizar campos si viene información nueva (sin borrar data existente).
      try {
        await client.query(
          `UPDATE customers
           SET nombre_negocio = COALESCE(NULLIF($2,''), nombre_negocio),
               contacto_nombre = COALESCE(NULLIF($3,''), contacto_nombre),
               contacto_telefono = COALESCE(NULLIF($4,''), contacto_telefono),
               contacto_email = COALESCE(NULLIF($5,''), contacto_email),
               rol_negocio = COALESCE(NULLIF($6,''), rol_negocio)
           WHERE id = $1`,
          [
            customer.id,
            nombre_negocio,
            contacto_nombre,
            contacto_telefono,
            contacto_email,
            rol_negocio
          ]
        );
      } catch (_) {
        // Si la columna aún no existe (migración pendiente), no bloqueamos el flujo.
      }
    }

    // 2) Si ya existe una DEMO activa para este device, devolverla (idempotente)
    const existingRes = await client.query(
      `SELECT l.*
       FROM licenses l
       JOIN license_activations a ON a.license_id = l.id
       WHERE l.tipo = 'DEMO'
         AND l.customer_id = $1
         AND l.project_id = $3
         AND a.device_id = $2
         AND a.estado = 'ACTIVA'
       ORDER BY l.created_at DESC
       LIMIT 1`,
      [customer.id, device_id, project.id]
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

    // 3) Config DEMO (controlado desde Admin)
    const config = await licenseConfigService.getLicenseConfig();
    const dias = Math.max(1, Number(config.demo_dias_validez) || 15);
    const maxDisp = Math.max(1, Number(config.demo_max_dispositivos) || 1);

    // 4) Crear licencia DEMO (key único)
    let license;
    for (let i = 0; i < 6; i++) {
      const key = generateLicenseKey('DEMO');
      try {
        const licRes = await client.query(
          `INSERT INTO licenses (project_id, customer_id, license_key, tipo, dias_validez, max_dispositivos, estado, notas)
           VALUES ($1, $2, $3, 'DEMO', $4, $5, 'PENDIENTE', $6)
           RETURNING *`,
          [project.id, customer.id, key, dias, maxDisp, `Auto DEMO (start-demo) project=${projectCode}`]
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
      `INSERT INTO license_activations (license_id, project_id, device_id, estado)
       VALUES ($1, $2, $3, 'ACTIVA')
       ON CONFLICT (license_id, device_id)
       DO UPDATE SET estado = 'ACTIVA', project_id = EXCLUDED.project_id, activated_at = now(), last_check_at = now()`,
      [license.id, project.id, device_id]
    );

    await client.query('COMMIT');
    return res.status(201).json({
      ok: true,
      customer,
      license_key: license.license_key,
      project_code: projectCode,
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
