/**
 * Controlador pÃºblico de licencias para FullCredit y otras apps SaaS.
 * 
 * Endpoints pÃºblicos (SIN middleware isAdmin):
 *   POST /api/public/license/validate
 *   POST /api/public/licenses/demo/start
 *   GET  /api/public/projects/:code/billing
 *   POST /api/public/license-payments/create-paypal-order
 *   POST /api/public/license-payments/capture-paypal-order
 *   POST /api/public/customers/register-or-find
 */
const { pool } = require('../db/pool');
const projectsModel = require('../models/projectsModel');
const customersModel = require('../models/customersModel');
const licensesModel = require('../models/licensesModel');
const licensePaymentOrdersModel = require('../models/licensePaymentOrdersModel');
const paypalService = require('../services/paypalService');
const { generateLicenseKey } = require('../utils/licenseKey');

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

function nullIfEmpty(value) {
  const v = String(value || '').trim();
  return v ? v : null;
}

function isUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value || '').trim());
}

function daysBetween(a, b) {
  const diff = new Date(b).getTime() - new Date(a).getTime();
  return Math.max(0, Math.floor(diff / (24 * 60 * 60 * 1000)));
}

async function updateCustomerCompat(customerId, assignments, params) {
  try {
    return await pool.query(
      `UPDATE customers
       SET ${assignments}, updated_at = now()
       WHERE id = $1
       RETURNING *`,
      params
    );
  } catch (error) {
    if (!(error && error.code === '42703')) throw error;
    return pool.query(
      `UPDATE customers
       SET ${assignments}
       WHERE id = $1
       RETURNING *`,
      params
    );
  }
}

async function resolveOrCreatePublicCustomer({ deviceId, businessName, phone, email }) {
  const device = asTrimmed(deviceId);
  const normalizedEmail = normalizeEmail(email);
  const normalizedPhone = normalizePhone(phone);
  const displayName = asTrimmed(businessName) || 'Cliente FullCredit';

  let customer = null;

  const existingRes = await pool.query(
    `SELECT DISTINCT c.*
     FROM customers c
     JOIN licenses l ON l.customer_id = c.id
     JOIN license_activations la ON la.license_id = l.id AND la.device_id = $1
     LIMIT 1`,
    [device]
  );
  customer = existingRes.rows[0] || null;

  if (!customer && normalizedEmail) {
    customer = await customersModel.findCustomerByContact({
      contacto_email: normalizedEmail,
      contacto_telefono: normalizedPhone || null
    });
  }

  if (!customer && normalizedPhone) {
    customer = await customersModel.findCustomerByContact({
      contacto_email: null,
      contacto_telefono: normalizedPhone
    });
  }

  if (!customer) {
    customer = await customersModel.createCustomer({
      nombre_negocio: displayName,
      contacto_nombre: null,
      contacto_telefono: normalizedPhone || null,
      contacto_email: normalizedEmail || null,
      rol_negocio: null,
      business_id: null
    });
    return customer;
  }

  const nextName = asTrimmed(customer.nombre_negocio) || displayName;
  const nextPhone = customer.contacto_telefono || normalizedPhone || null;
  const nextEmail = customer.contacto_email || normalizedEmail || null;

  if (
    nextName !== customer.nombre_negocio ||
    nextPhone !== customer.contacto_telefono ||
    nextEmail !== customer.contacto_email
  ) {
    const updatedRes = await updateCustomerCompat(
      customer.id,
      `nombre_negocio = $2,
       contacto_telefono = $3,
       contacto_email = $4`,
      [customer.id, nextName, nextPhone, nextEmail]
    );
    customer = updatedRes.rows[0] || customer;
  }

  return customer;
}

async function resolvePublicCustomerForPurchase({
  businessId,
  deviceId,
  businessName,
  businessType,
  ownerName,
  phone,
  email,
}) {
  const normalizedBusinessId = asTrimmed(businessId);
  const normalizedDeviceId = asTrimmed(deviceId);
  const normalizedBusinessName = asTrimmed(businessName) || 'Cliente FullPOS';
  const normalizedBusinessType = asTrimmed(businessType) || null;
  const normalizedOwnerName = asTrimmed(ownerName) || null;
  const normalizedPhone = normalizePhone(phone) || null;
  const normalizedEmail = normalizeEmail(email) || null;

  let customer = null;

  if (normalizedBusinessId) {
    try {
      customer = await customersModel.getCustomerByBusinessId(normalizedBusinessId);
    } catch (error) {
      if (!(error && error.code === 'MIGRATION_PENDING')) throw error;
    }
  }

  if (!customer && normalizedDeviceId) {
    const byDeviceRes = await pool.query(
      `SELECT DISTINCT c.*
       FROM customers c
       JOIN licenses l ON l.customer_id = c.id
       JOIN license_activations la ON la.license_id = l.id AND la.device_id = $1
       LIMIT 1`,
      [normalizedDeviceId]
    );
    customer = byDeviceRes.rows[0] || null;
  }

  if (!customer) {
    customer = await resolveOrCreatePublicCustomer({
      deviceId: normalizedDeviceId,
      businessName: normalizedBusinessName,
      phone: normalizedPhone,
      email: normalizedEmail,
    });
  }

  if (!customer) return null;

  const hasBusinessIdColumn = Object.prototype.hasOwnProperty.call(customer, 'business_id');
  const nextBusinessId = normalizedBusinessId || asTrimmed(customer.business_id);
  const nextBusinessName = normalizedBusinessName || asTrimmed(customer.nombre_negocio) || 'Cliente FullPOS';
  const nextOwnerName = normalizedOwnerName || asTrimmed(customer.contacto_nombre) || null;
  const nextPhone = normalizedPhone || customer.contacto_telefono || null;
  const nextEmail = normalizedEmail || customer.contacto_email || null;
  const nextRole = normalizedBusinessType || customer.rol_negocio || null;

  const fields = [];
  const params = [customer.id];

  if (nextBusinessName !== customer.nombre_negocio) {
    params.push(nextBusinessName);
    fields.push(`nombre_negocio = $${params.length}`);
  }
  if (nextOwnerName !== customer.contacto_nombre) {
    params.push(nextOwnerName);
    fields.push(`contacto_nombre = $${params.length}`);
  }
  if (nextPhone !== customer.contacto_telefono) {
    params.push(nextPhone);
    fields.push(`contacto_telefono = $${params.length}`);
  }
  if (nextEmail !== customer.contacto_email) {
    params.push(nextEmail);
    fields.push(`contacto_email = $${params.length}`);
  }
  if (nextRole !== customer.rol_negocio) {
    params.push(nextRole);
    fields.push(`rol_negocio = $${params.length}`);
  }
  if (hasBusinessIdColumn && nextBusinessId && nextBusinessId !== customer.business_id) {
    params.push(nextBusinessId);
    fields.push(`business_id = $${params.length}`);
  }

  if (fields.length > 0) {
    const updatedRes = await updateCustomerCompat(
      customer.id,
      fields.join(', '),
      params
    );
    customer = updatedRes.rows[0] || customer;
  }

  return customer;
}

/**
 * Ejecuta una query SQL ignorando errores de tabla no existente (42P01).
 * Ãštil para consultas a demo_trials que puede no existir en producciÃ³n.
 */
async function queryOptionalTable(sql, params) {
  try {
    return await pool.query(sql, params);
  } catch (error) {
    if (error && error.code === '42P01') {
      // Tabla no existe, devolver resultado vacÃ­o
      return { rows: [], rowCount: 0 };
    }
    throw error;
  }
}

/**
 * POST /api/public/license/validate
 * Valida la licencia de un dispositivo para un proyecto.
 * 
 * Payload: { project_code, device_id }
 * 
 * Respuestas posibles:
 *   - Licencia ACTIVA y vigente â†’ { valid: true, status: 'ACTIVA', ... }
 *   - Demo activo â†’ { valid: true, status: 'DEMO_ACTIVE', ... }
 *   - Demo vencido â†’ { valid: false, status: 'DEMO_EXPIRED', ... }
 *   - Licencia vencida â†’ { valid: false, status: 'EXPIRED', ... }
 *   - Sin licencia â†’ { valid: false, status: 'NO_LICENSE', ... }
 */
async function validateLicense(req, res) {
  try {
    const { project_code, device_id } = req.body || {};
    const device = asTrimmed(device_id);
    const projectCode = asTrimmed(project_code);

    console.log('[PUBLIC_VALIDATE] BODY:', JSON.stringify(req.body, null, 2));

    if (!device) {
      return res.status(400).json({
        success: false, valid: false, status: 'ERROR',
        reason: 'device_id_required',
        message: 'device_id es requerido'
      });
    }

    // Buscar proyecto
    let project = null;
    if (projectCode) {
      project = await projectsModel.getProjectByCode(projectCode);
    }
    if (!project) {
      project = await projectsModel.getDefaultProject();
    }
    if (!project) {
      return res.status(404).json({
        success: false, valid: false, status: 'ERROR',
        reason: 'project_not_found',
        message: 'Proyecto no encontrado'
      });
    }

    console.log('[PUBLIC_VALIDATE] project:', { id: project.id, code: project.code, allow_demo: project.allow_demo });

    const now = new Date();

    // 1) Buscar licencias FULL activas para este device + proyecto
    const fullActRes = await pool.query(
      `SELECT l.*, c.business_id, a.device_id, a.estado AS activation_estado
       FROM license_activations a
       JOIN licenses l ON l.id = a.license_id
       LEFT JOIN customers c ON c.id = l.customer_id
       WHERE a.device_id = $1
         AND a.project_id = $2
         AND a.estado = 'ACTIVA'
         AND l.tipo = 'FULL'
       ORDER BY l.created_at DESC
       LIMIT 1`,
      [device, project.id]
    );
    const fullActivation = fullActRes.rows[0];

    if (fullActivation) {
      const licStatus = licensesModel.getEffectiveLicenseStatus
        ? licensesModel.getEffectiveLicenseStatus(fullActivation, now)
        : (fullActivation.estado === 'ACTIVA' && fullActivation.fecha_fin && new Date(fullActivation.fecha_fin).getTime() < now.getTime() ? 'VENCIDA' : fullActivation.estado);

      if (licStatus === 'ACTIVA' || licStatus === 'ACTIVE') {
        const expiresAt = fullActivation.fecha_fin;
        const daysRemaining = expiresAt ? daysBetween(now, expiresAt) : 0;

        console.log('[PUBLIC_VALIDATE] FULL activa encontrada, days_remaining:', daysRemaining);

        return res.json({
          success: true,
          valid: true,
          status: 'ACTIVA',
          reason: null,
          message: 'Licencia activa',
          license_key: fullActivation.license_key,
          project_code: project.code,
          expires_at: expiresAt,
          days_remaining: daysRemaining,
          max_devices: fullActivation.max_dispositivos,
          business_id: fullActivation.business_id || null,
          demo_active: false,
          payment_required: false,
          customer_id: fullActivation.customer_id,
          project_id: project.id,
          license_version: Number(fullActivation.license_version) || 1,
          license_updated_at: fullActivation.updated_at,
          project: {
            monthly_price: Number(project.monthly_price) || 0,
            currency: String(project.currency || 'USD'),
            demo_days: Number(project.demo_days) || 0,
            min_purchase_months: Number(project.min_purchase_months) || 1,
            is_paid_project: Boolean(project.is_paid_project),
            allow_demo: Boolean(project.allow_demo),
            is_active: Boolean(project.is_active)
          }
        });
      }

      // Licencia FULL existe pero vencida
      if (licStatus === 'VENCIDA' || licStatus === 'EXPIRED') {
        console.log('[PUBLIC_VALIDATE] FULL vencida');
        return res.json({
          success: true,
          valid: false,
          status: 'EXPIRED',
          reason: 'LICENSE_EXPIRED',
          message: 'Tu licencia ha vencido. Renueva para continuar.',
          license_key: fullActivation.license_key,
          project_code: project.code,
          expires_at: fullActivation.fecha_fin,
          days_remaining: 0,
          max_devices: fullActivation.max_dispositivos,
          demo_active: false,
          payment_required: true,
          customer_id: fullActivation.customer_id,
          project_id: project.id,
          license_version: Number(fullActivation.license_version) || 1,
          license_updated_at: fullActivation.updated_at,
          project: {
            monthly_price: Number(project.monthly_price) || 0,
            currency: String(project.currency || 'USD'),
            demo_days: Number(project.demo_days) || 0,
            min_purchase_months: Number(project.min_purchase_months) || 1,
            is_paid_project: Boolean(project.is_paid_project),
            allow_demo: Boolean(project.allow_demo),
            is_active: Boolean(project.is_active)
          }
        });
      }
    }

    // 2) Buscar licencias DEMO activas para este device + proyecto
    const demoActRes = await pool.query(
      `SELECT l.*, c.business_id, a.device_id, a.estado AS activation_estado
       FROM license_activations a
       JOIN licenses l ON l.id = a.license_id
       LEFT JOIN customers c ON c.id = l.customer_id
       WHERE a.device_id = $1
         AND a.project_id = $2
         AND a.estado = 'ACTIVA'
         AND l.tipo = 'DEMO'
       ORDER BY l.created_at DESC
       LIMIT 1`,
      [device, project.id]
    );
    const demoActivation = demoActRes.rows[0];

    if (demoActivation) {
      const demoExpired = demoActivation.fecha_fin && new Date(demoActivation.fecha_fin).getTime() < now.getTime();

      if (!demoExpired && demoActivation.estado === 'ACTIVA') {
        const expiresAt = demoActivation.fecha_fin;
        const daysRemaining = expiresAt ? daysBetween(now, expiresAt) : 0;

        console.log('[PUBLIC_VALIDATE] DEMO activa, days_remaining:', daysRemaining);

        return res.json({
          success: true,
          valid: true,
          status: 'DEMO_ACTIVE',
          reason: null,
          message: `Demo activo. Te quedan ${daysRemaining} dÃ­as.`,
          license_key: demoActivation.license_key,
          project_code: project.code,
          expires_at: expiresAt,
          days_remaining: daysRemaining,
          max_devices: demoActivation.max_dispositivos,
          business_id: demoActivation.business_id || null,
          demo_active: true,
          payment_required: false,
          customer_id: demoActivation.customer_id,
          project_id: project.id,
          license_version: Number(demoActivation.license_version) || 1,
          license_updated_at: demoActivation.updated_at,
          project: {
            monthly_price: Number(project.monthly_price) || 0,
            currency: String(project.currency || 'USD'),
            demo_days: Number(project.demo_days) || 0,
            min_purchase_months: Number(project.min_purchase_months) || 1,
            is_paid_project: Boolean(project.is_paid_project),
            allow_demo: Boolean(project.allow_demo),
            is_active: Boolean(project.is_active)
          }
        });
      }

      // Demo vencido
      console.log('[PUBLIC_VALIDATE] DEMO vencida');
      return res.json({
        success: true,
        valid: false,
        status: 'DEMO_EXPIRED',
        reason: 'DEMO_EXPIRED',
        message: 'Tu demo ha terminado. Para seguir usando, activa tu licencia.',
        project_code: project.code,
        days_remaining: 0,
        demo_active: false,
        payment_required: true,
        customer_id: demoActivation.customer_id,
        project_id: project.id,
        project: {
          monthly_price: Number(project.monthly_price) || 0,
          currency: String(project.currency || 'USD'),
          demo_days: Number(project.demo_days) || 0,
          min_purchase_months: Number(project.min_purchase_months) || 1,
          is_paid_project: Boolean(project.is_paid_project),
          allow_demo: Boolean(project.allow_demo),
          is_active: Boolean(project.is_active)
        }
      });
    }

    // 3) Verificar si hubo demo previa (demo_trials) para este device
    // Usar queryOptionalTable porque demo_trials puede no existir
    const trialRes = await queryOptionalTable(
      `SELECT id, started_at, customer_id
       FROM demo_trials
       WHERE project_id = $1 AND device_id = $2
       ORDER BY started_at DESC
       LIMIT 1`,
      [project.id, device]
    );
    const trial = trialRes.rows[0];

    if (trial) {
      console.log('[PUBLIC_VALIDATE] Demo previa encontrada en demo_trials');
      return res.json({
        success: true,
        valid: false,
        status: 'DEMO_EXPIRED',
        reason: 'DEMO_ALREADY_USED',
        message: 'Ya utilizaste tu demo. Activa tu licencia para continuar.',
        project_code: project.code,
        days_remaining: 0,
        demo_active: false,
        payment_required: true,
        customer_id: trial.customer_id,
        project_id: project.id,
        project: {
          monthly_price: Number(project.monthly_price) || 0,
          currency: String(project.currency || 'USD'),
          demo_days: Number(project.demo_days) || 0,
          min_purchase_months: Number(project.min_purchase_months) || 1,
          is_paid_project: Boolean(project.is_paid_project),
          allow_demo: Boolean(project.allow_demo),
          is_active: Boolean(project.is_active)
        }
      });
    }

    // 4) No hay licencia ni demo
    console.log('[PUBLIC_VALIDATE] Sin licencia ni demo');
    return res.json({
      success: true,
      valid: false,
      status: 'NO_LICENSE',
      reason: 'LICENSE_NOT_FOUND',
      message: 'No tienes una licencia activa. Inicia tu demo gratis o adquiere una licencia.',
      project_code: project.code,
      days_remaining: 0,
      demo_active: false,
      payment_required: project.is_paid_project,
      project_id: project.id,
      project: {
        monthly_price: Number(project.monthly_price) || 0,
        currency: String(project.currency || 'USD'),
        demo_days: Number(project.demo_days) || 0,
        min_purchase_months: Number(project.min_purchase_months) || 1,
        is_paid_project: Boolean(project.is_paid_project),
        allow_demo: Boolean(project.allow_demo),
        is_active: Boolean(project.is_active)
      }
    });
  } catch (error) {
    console.error('[PUBLIC_VALIDATE] FATAL ERROR:', {
      message: error.message,
      code: error.code,
      detail: error.detail,
      constraint: error.constraint,
      stack: error.stack
    });
    return res.status(500).json({
      success: false, valid: false, status: 'ERROR',
      reason: 'internal_error',
      message: 'Error interno del servidor'
    });
  }
}

/**
 * POST /api/public/licenses/demo/start
 * Inicia una demo gratis para un dispositivo.
 * 
 * Payload: { project_code, device_id, customer_name, customer_email, business_name }
 */
async function startDemo(req, res) {
  try {
    // Normalizar campos con mÃºltiples alias
    const project_code = req.body.project_code || req.body.projectCode || '';
    const device_id = req.body.device_id || req.body.deviceId || '';
    const business_name =
      req.body.business_name ||
      req.body.businessName ||
      req.body.customer_name ||
      req.body.customerName ||
      req.body.nombre_negocio ||
      '';
    const phone =
      req.body.phone ||
      req.body.telefono ||
      req.body.customer_phone ||
      req.body.contacto_telefono ||
      '';
    const email =
      req.body.email ||
      req.body.customer_email ||
      req.body.customerEmail ||
      req.body.contacto_email ||
      '';

    console.log('[PUBLIC_DEMO_START] BODY:', JSON.stringify(req.body, null, 2));
    console.log('[PUBLIC_DEMO_START] normalized:', {
      project_code,
      device_id,
      business_name,
      phone,
      email
    });

    if (!device_id) {
      return res.status(400).json({ success: false, message: 'device_id es requerido' });
    }

    if (!project_code) {
      return res.status(400).json({ success: false, message: 'project_code es requerido' });
    }

    // Resolver proyecto
    let project = null;
    if (project_code) {
      project = await projectsModel.getProjectByCode(project_code);
    }
    if (!project) {
      project = await projectsModel.getDefaultProject();
    }
    if (!project) {
      return res.status(404).json({ success: false, message: 'Proyecto no encontrado' });
    }

    console.log('[PUBLIC_DEMO_START] project:', { id: project.id, code: project.code, allow_demo: project.allow_demo, demo_days: project.demo_days });

    // Validar que el proyecto permita demo
    if (!project.allow_demo) {
      return res.status(400).json({ success: false, message: 'Este proyecto no permite demo' });
    }

    const now = new Date();
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // 1) Buscar o crear customer
      let customer = null;

      // Primero buscar por device_id a travÃ©s de licenses (license_activations NO tiene customer_id)
      const existingCustomerRes = await client.query(
        `SELECT DISTINCT c.*
         FROM customers c
         JOIN licenses l ON l.customer_id = c.id
         JOIN license_activations la ON la.license_id = l.id AND la.device_id = $1
         LIMIT 1`,
        [device_id]
      );
      customer = existingCustomerRes.rows[0] || null;

      console.log('[PUBLIC_DEMO_START] existing customer by activation:', customer ? customer.id : null);


      if (!customer && email) {
        customer = await customersModel.findCustomerByContact({ contacto_email: email });
        console.log('[PUBLIC_DEMO_START] existing customer by email:', customer ? customer.id : null);
      }

      if (!customer) {
        // Crear nuevo customer
        const createdRes = await client.query(
          `INSERT INTO customers (nombre_negocio, contacto_nombre, contacto_telefono, contacto_email)
           VALUES ($1, $2, $3, $4)
           RETURNING *`,
          [
            business_name || 'Cliente FullCredit',
            null,
            phone || null,
            email || null
          ]
        );
        customer = createdRes.rows[0];
        console.log('[PUBLIC_DEMO_START] customer created:', customer.id);
      } else {
        // Actualizar datos si viene informaciÃ³n nueva
        if (business_name || phone || email) {
          try {
            await client.query(
              `UPDATE customers
               SET nombre_negocio = COALESCE(NULLIF($2,''), nombre_negocio),
                   contacto_telefono = COALESCE(NULLIF($3,''), contacto_telefono),
                   contacto_email = COALESCE(NULLIF($4,''), contacto_email)
               WHERE id = $1`,
              [customer.id, business_name, phone, email]
            );
            console.log('[PUBLIC_DEMO_START] customer updated');
          } catch (_) {
            console.log('[PUBLIC_DEMO_START] customer update skipped (non-critical)');
          }
        }
      }

      // 2) Verificar si ya existe una DEMO activa para este customer + proyecto
      const existingDemoRes = await client.query(
        `SELECT l.*
         FROM licenses l
         JOIN license_activations a ON a.license_id = l.id
         WHERE l.tipo = 'DEMO'
           AND l.customer_id = $1
           AND l.project_id = $2
           AND a.device_id = $3
           AND a.estado = 'ACTIVA'
         ORDER BY l.created_at DESC
         LIMIT 1`,
        [customer.id, project.id, device_id]
      );
      const existingDemo = existingDemoRes.rows[0];

      if (existingDemo) {
        const demoExpired = existingDemo.fecha_fin && new Date(existingDemo.fecha_fin).getTime() < now.getTime();
        if (!demoExpired && existingDemo.estado !== 'BLOQUEADA' && existingDemo.estado !== 'VENCIDA') {
          await client.query('COMMIT');
          console.log('[PUBLIC_DEMO_START] Demo ya activa, retornando existente');
          return res.json({
            success: true,
            message: 'Demo ya activa',
            license: {
              license_key: existingDemo.license_key,
              tipo: existingDemo.tipo,
              fecha_inicio: existingDemo.fecha_inicio,
              fecha_fin: existingDemo.fecha_fin,
              estado: existingDemo.estado
            }
          });
        }
      }

      // 3) Verificar que no exista demo previa para este device + proyecto en demo_trials
      // Usar query directa con manejo de tabla no existente
      try {
        const deviceTrialRes = await client.query(
          `SELECT id, started_at
           FROM demo_trials
           WHERE project_id = $1 AND device_id = $2
           ORDER BY started_at ASC
           LIMIT 1`,
          [project.id, device_id]
        );
        const deviceTrial = deviceTrialRes.rows[0];

        if (deviceTrial) {
          await client.query('ROLLBACK');
          console.log('[PUBLIC_DEMO_START] Demo ya usada para este device');
          return res.status(409).json({
            success: false,
            code: 'DEMO_ALREADY_USED',
            message: 'La prueba DEMO ya fue utilizada en este equipo. Debes activar una licencia FULL.'
          });
        }
      } catch (e) {
        // Si demo_trials no existe (42P01), continuar normalmente
        if (e && e.code === '42P01') {
          console.log('[PUBLIC_DEMO_START] demo_trials table does not exist, skipping check');
        } else {
          throw e;
        }
      }

      // 4) ConfiguraciÃ³n de demo desde el proyecto
      const demoDays = Math.max(1, Number(project.demo_days) || 5);
      const maxDisp = Math.max(1, Number(project.max_dispositivos) || 1);

      console.log('[PUBLIC_DEMO_START] demo config:', { demoDays, maxDisp });

      // 5) Crear licencia DEMO
      let license;
      for (let i = 0; i < 6; i++) {
        const key = generateLicenseKey('DEMO');
        try {
          const licRes = await client.query(
            `INSERT INTO licenses (project_id, customer_id, license_key, tipo, dias_validez, max_dispositivos, estado, notas)
             VALUES ($1, $2, $3, 'DEMO', $4, $5, 'PENDIENTE', $6)
             RETURNING *`,
            [project.id, customer.id, key, demoDays, maxDisp, `Auto DEMO (public) project=${project.code}`]
          );
          license = licRes.rows[0];
          break;
        } catch (e) {
          if (e && e.code === '23505') continue;
          throw e;
        }
      }

      if (!license) {
        await client.query('ROLLBACK');
        console.log('[PUBLIC_DEMO_START] No se pudo generar license_key');
        return res.status(500).json({ success: false, message: 'No se pudo generar license_key' });
      }

      console.log('[PUBLIC_DEMO_START] license created:', { id: license.id, key: license.license_key });

      // 6) Activar demo
      const fechaInicio = now;
      const fechaFin = new Date(now.getTime() + demoDays * 24 * 60 * 60 * 1000);

      const updRes = await client.query(
        `UPDATE licenses
         SET fecha_inicio = $2::timestamp, fecha_fin = $3::timestamp, estado = 'ACTIVA'
         WHERE id = $1
         RETURNING *`,
        [license.id, fechaInicio, fechaFin]
      );
      license = updRes.rows[0];

      console.log('[PUBLIC_DEMO_START] license activated:', { id: license.id, fecha_inicio: license.fecha_inicio, fecha_fin: license.fecha_fin });

      await client.query(
        `INSERT INTO license_activations (license_id, project_id, device_id, estado)
         VALUES ($1, $2, $3, 'ACTIVA')
         ON CONFLICT (license_id, device_id)
         DO UPDATE SET estado = 'ACTIVA', project_id = EXCLUDED.project_id, activated_at = now(), last_check_at = now()`,
        [license.id, project.id, device_id]
      );

      console.log('[PUBLIC_DEMO_START] activation created');

      // 7) Registrar consumo de demo (si la tabla existe)
      try {
        await client.query(
          `INSERT INTO demo_trials (project_id, device_id, contacto_email_norm, customer_id, license_id)
           VALUES ($1, $2, $3, $4, $5)`,
          [project.id, device_id, email || null, customer.id, license.id]
        );
        console.log('[PUBLIC_DEMO_START] demo_trial registered');
      } catch (e) {
        if (e && e.code === '23505') {
          await client.query('ROLLBACK');
          console.log('[PUBLIC_DEMO_START] Demo ya usada (unique constraint)');
          return res.status(409).json({
            success: false,
            code: 'DEMO_ALREADY_USED',
            message: 'La prueba DEMO ya fue utilizada.'
          });
        }
        if (e && e.code === '42P01') {
          // Tabla demo_trials no existe, continuar sin registrar
          console.log('[PUBLIC_DEMO_START] demo_trials table does not exist, skipping insert');
        } else {
          throw e;
        }
      }

      await client.query('COMMIT');
      console.log('[PUBLIC_DEMO_START] Demo iniciada exitosamente');

      return res.status(201).json({
        success: true,
        valid: true,
        status: 'DEMO_ACTIVE',
        reason: null,
        message: `Demo iniciada por ${demoDays} dÃ­as`,
        license_key: license.license_key,
        project_code: project.code,
        expires_at: license.fecha_fin,
        days_remaining: demoDays,
        max_devices: license.max_dispositivos,
        demo_active: true,
        payment_required: false,
        customer_id: customer.id,
        project_id: project.id,
        license: {
          license_key: license.license_key,
          project_code: project.code,
          tipo: license.tipo,
          fecha_inicio: license.fecha_inicio,
          fecha_fin: license.fecha_fin,
          estado: license.estado,
          max_dispositivos: license.max_dispositivos,
          days_remaining: demoDays
        },
        customer: {
          id: customer.id,
          name: customer.nombre_negocio || customer.contacto_nombre,
          email: customer.contacto_email
        }
      });
    } catch (error) {
      await client.query('ROLLBACK');
      console.error('[PUBLIC_DEMO_START] FATAL ERROR:', {
        message: error.message,
        code: error.code,
        detail: error.detail,
        constraint: error.constraint,
        table: error.table,
        column: error.column,
        stack: error.stack
      });
      return res.status(500).json({
        success: false,
        message: 'Error interno del servidor',
        error: error.message,
        code: error.code || null,
        detail: error.detail || null,
        constraint: error.constraint || null
      });
    } finally {
      client.release();
    }
  } catch (error) {
    console.error('[PUBLIC_DEMO_START] OUTER FATAL ERROR:', {
      message: error.message,
      code: error.code,
      detail: error.detail,
      constraint: error.constraint,
      stack: error.stack
    });
    return res.status(500).json({
      success: false,
      message: 'Error interno del servidor',
      error: error.message,
      code: error.code || null,
      detail: error.detail || null,
      constraint: error.constraint || null
    });
  }
}

/**
 * GET /api/public/projects/:code/billing
 * Obtiene la configuraciÃ³n de facturaciÃ³n de un proyecto.
 */
async function getProjectBillingInfo(req, res) {
  try {
    const code = asTrimmed(req.params.code);
    if (!code) {
      return res.status(400).json({ success: false, message: 'CÃ³digo de proyecto requerido' });
    }

    const project = await projectsModel.getProjectByCode(code);
    if (!project) {
      return res.status(404).json({ success: false, message: 'Proyecto no encontrado' });
    }

    return res.json({
      success: true,
      project_id: project.id,
      project_code: project.code,
      project_name: project.name,
      monthly_price: Number(project.monthly_price) || 0,
      currency: String(project.currency || 'USD'),
      demo_days: Number(project.demo_days) || 0,
      min_purchase_months: Number(project.min_purchase_months) || 1,
      is_paid_project: Boolean(project.is_paid_project),
      allow_demo: Boolean(project.allow_demo),
      is_active: Boolean(project.is_active)
    });
  } catch (error) {
    console.error('[publicLicense.getProjectBillingInfo] Error:', error);
    return res.status(500).json({ success: false, message: 'Error interno del servidor' });
  }
}

async function finalizePaidLicenseOrder(localOrder) {
  let result = await pool.query(
    `SELECT l.*, c.business_id
       FROM licenses l
       LEFT JOIN customers c ON c.id = l.customer_id
      WHERE l.payment_order_id = $1
      ORDER BY l.created_at DESC
      LIMIT 1`,
    [localOrder.id]
  );
  let license = result.rows[0] || null;

  if (!license) {
    const created = await licensesModel.activateOrExtendPaidLicense({
      customerId: localOrder.customer_id,
      projectId: localOrder.project_id,
      months: localOrder.months,
      paymentOrderId: localOrder.id,
      maxDevices: 1,
    });
    result = await pool.query(
      `SELECT l.*, c.business_id
         FROM licenses l
         LEFT JOIN customers c ON c.id = l.customer_id
        WHERE l.id = $1
        LIMIT 1`,
      [created.id]
    );
    license = result.rows[0] || created;
  }

  const rawRequest =
    localOrder.raw_request && typeof localOrder.raw_request === 'object'
      ? localOrder.raw_request
      : {};
  const deviceId = asTrimmed(rawRequest.device_id);
  if (deviceId) {
    await pool.query(
      `INSERT INTO license_activations (
         license_id, project_id, device_id, estado, activated_at, last_check_at
       )
       VALUES ($1, $2, $3, 'ACTIVA', now(), now())
       ON CONFLICT (license_id, device_id)
       DO UPDATE SET
         project_id = EXCLUDED.project_id,
         estado = 'ACTIVA',
         last_check_at = now()`,
      [license.id, localOrder.project_id, deviceId]
    );
  }

  return license;
}

function paidLicenseResponse(localOrder, license, { idempotent = false } = {}) {
  const expiresAt = license.fecha_fin || license.expires_at || null;
  const expiresDate = expiresAt ? new Date(expiresAt) : null;
  const daysRemaining =
    expiresDate && Number.isFinite(expiresDate.getTime())
      ? Math.max(0, Math.ceil((expiresDate.getTime() - Date.now()) / 86400000))
      : 0;

  return {
    success: true,
    valid: true,
    status: 'ACTIVE',
    payment_captured: true,
    idempotent,
    payment_order_id: localOrder.id,
    paypal_order_id: localOrder.provider_order_id,
    capture_id: localOrder.provider_capture_id || null,
    message: 'Pago confirmado. Licencia activada correctamente.',
    license_key: license.license_key,
    project_code: localOrder.project_code,
    expires_at: expiresAt,
    days_remaining: daysRemaining,
    max_devices: Number(license.max_dispositivos) || 1,
    demo_active: false,
    payment_required: false,
    customer_id: localOrder.customer_id,
    project_id: localOrder.project_id,
    business_id: license.business_id || null,
    license: {
      id: license.id,
      license_key: license.license_key,
      status: license.estado,
      estado: license.estado,
      activated_at: license.fecha_inicio,
      expires_at: expiresAt,
      months: localOrder.months,
      monthly_price: Number(localOrder.monthly_price),
      total_amount: Number(localOrder.total_amount),
      currency: localOrder.currency,
      license_version: Number(license.license_version) || 1,
      license_updated_at: license.updated_at,
    },
  };
}

/**
 * POST /api/public/license-payments/create-paypal-order
 * Crea una orden de pago PayPal para comprar tiempo de licencia.
 * 
 * El backend calcula el monto usando la configuraciÃ³n del proyecto.
 * El frontend NO envÃ­a el monto.
 * 
 * Payload: { project_code, device_id, months }
 */
async function createPaymentOrder(req, res) {
  try {
    const {
      project_code,
      device_id,
      months,
      business_id,
      business_name,
      business_type,
      owner_name,
      phone,
      email,
    } = req.body || {};
    const device = asTrimmed(device_id);
    const projectCode = asTrimmed(project_code);
    const businessId = asTrimmed(business_id);

    if (!device && !businessId) {
      return res.status(400).json({
        success: false,
        message: 'device_id o business_id es requerido',
      });
    }

    // Buscar proyecto
    let project = null;
    if (projectCode) {
      project = await projectsModel.getProjectByCode(projectCode);
    }
    if (!project) {
      project = await projectsModel.getDefaultProject();
    }
    if (!project) {
      return res.status(404).json({ success: false, message: 'Proyecto no encontrado' });
    }

    // Validar que el proyecto acepte pagos
    if (!project.is_paid_project) {
      return res.status(400).json({ success: false, message: 'Este proyecto no requiere pago' });
    }

    // Validar months
    const requestedMonths = Math.floor(Number(months));
    if (!Number.isFinite(requestedMonths) || requestedMonths < 1) {
      return res.status(400).json({ success: false, message: 'months debe ser un nÃºmero entero positivo' });
    }

    const minMonths = Number(project.min_purchase_months) || 1;
    if (requestedMonths < minMonths) {
      return res.status(400).json({
        success: false,
        message: `La compra mÃ­nima es de ${minMonths} meses para este proyecto`,
      });
    }

    const customer = await resolvePublicCustomerForPurchase({
      businessId,
      deviceId: device,
      businessName: business_name,
      businessType: business_type,
      ownerName: owner_name,
      phone,
      email,
    });
    const customerId = customer?.id || null;

    if (!customerId) {
      return res.status(500).json({
        success: false,
        message: 'No se pudo preparar el cliente para procesar el pago.'
      });
    }

    // Calcular monto usando la configuraciÃ³n del proyecto (NO confiar en frontend)
    const purchase = projectsModel.calculateLicensePurchase(project, requestedMonths);

    if (purchase.total <= 0) {
      return res.status(400).json({
        success: false,
        message: 'El monto total debe ser mayor que 0. Verifica el precio mensual del proyecto.'
      });
    }

    // Crear orden local PENDING
    const localOrder = await licensePaymentOrdersModel.createPaymentOrder({
      customer_id: customerId,
      project_id: project.id,
      license_id: null,
      months: purchase.months,
      monthly_price: purchase.monthly_price,
      total_amount: purchase.total,
      currency: purchase.currency,
      provider: 'paypal',
      raw_request: {
        business_id: businessId || customer?.business_id || null,
        device_id: device,
        project_code: project.code,
        business_name: asTrimmed(business_name) || customer?.nombre_negocio || null,
        business_type: asTrimmed(business_type) || customer?.rol_negocio || null,
        owner_name: asTrimmed(owner_name) || customer?.contacto_nombre || null,
        phone: normalizePhone(phone) || customer?.contacto_telefono || null,
        email: normalizeEmail(email) || customer?.contacto_email || null,
        months: purchase.months,
        monthly_price: purchase.monthly_price,
        total: purchase.total,
        currency: purchase.currency,
      },
    });
    
    // Validar configuraciÃ³n de PayPal antes de intentar crear la orden
    const paypalConfig = paypalService.validatePaypalConfig();
    if (!paypalConfig.ok) {
      console.error('[publicLicense.createPaymentOrder] PayPal no configurado:', paypalConfig.missing);
      await licensePaymentOrdersModel.capturePaymentOrder(localOrder.id, {
        status: 'FAILED',
        raw_response: { error: 'PayPal no configurado', missing: paypalConfig.missing },
      });
      return res.status(502).json({
        success: false,
        message: 'El sistema de pagos PayPal no estÃ¡ configurado. Contacte al administrador.',
        detail: `Faltan: ${paypalConfig.missing.join(', ')}`,
        paypal_configured: false,
      });
    }

    // Crear orden en PayPal
    let paypalOrder;
    try {
      paypalOrder = await paypalService.createOrder({
        amount: purchase.total,
        currency: purchase.currency,
        description: `Compra de licencia ${project.code} - ${purchase.months} meses`,
        metadata: {
          payment_order_id: localOrder.id,
        },
      });
    } catch (paypalError) {
      console.error('[publicLicense.createPaymentOrder] PayPal error:', paypalError.message);
      await licensePaymentOrdersModel.capturePaymentOrder(localOrder.id, {
        status: 'FAILED',
        raw_response: { error: paypalError.message },
      });
      return res.status(502).json({
        success: false,
        message: 'Error al crear la orden en PayPal. Intente de nuevo mÃ¡s tarde.',
        detail: paypalError.message,
      });
    }

    // Actualizar orden local con datos de PayPal
    await pool.query(
      `UPDATE license_payment_orders
       SET provider_order_id = $2, checkout_url = $3, raw_request = $4, updated_at = now()
       WHERE id = $1`,
      [localOrder.id, paypalOrder.id, paypalOrder.checkout_url, JSON.stringify({
        ...localOrder.raw_request,
        paypal_order_id: paypalOrder.id,
      })]
    );

    const protoHeader = String(req.headers['x-forwarded-proto'] || '').trim();
    const proto = protoHeader || req.protocol || 'https';
    const host = String(req.headers['x-forwarded-host'] || req.get('host') || '').trim();
    const publicBaseUrl = `${proto}://${host}`.replace(/\/+$/, '');
    const cardCheckoutUrl =
      `${publicBaseUrl}/paypal/card-checkout?payment_order_id=${encodeURIComponent(localOrder.id)}` +
      `&paypal_order_id=${encodeURIComponent(paypalOrder.id)}`;

    return res.json({
      success: true,
      payment_order_id: localOrder.id,
      paypal_order_id: paypalOrder.id,
      preferred_checkout_url: cardCheckoutUrl,
      card_checkout_url: cardCheckoutUrl,
      checkout_url: paypalOrder.checkout_url,
      amount: purchase.total,
      currency: purchase.currency,
      months: purchase.months,
      monthly_price: purchase.monthly_price,
    });
  } catch (error) {
    console.error('[publicLicense.createPaymentOrder] Error:', error);
    return res.status(500).json({ success: false, message: 'Error interno del servidor' });
  }
}

/**
 * POST /api/public/license-payments/capture-paypal-order
 * Captura una orden de PayPal aprobada y activa/renueva la licencia.
 * 
 * Payload: { payment_order_id, paypal_order_id }
 */
async function capturePayment(req, res) {
  try {
    const { paypal_order_id, payment_order_id } = req.body || {};

    if (!paypal_order_id && !payment_order_id) {
      return res.status(400).json({ success: false, message: 'paypal_order_id o payment_order_id es requerido' });
    }

    // Buscar orden local
    let localOrder = null;
    if (payment_order_id) {
      localOrder = await licensePaymentOrdersModel.getPaymentOrderById(payment_order_id);
    } else if (paypal_order_id) {
      localOrder = await licensePaymentOrdersModel.getPaymentOrderByProviderOrderId(paypal_order_id);
    }

    if (!localOrder) {
      return res.status(404).json({ success: false, message: 'Orden de pago no encontrada' });
    }

    // Verificar que no estÃ© ya pagada
    if (String(localOrder.status).toUpperCase() === 'PAID') {
      try {
        const license = await finalizePaidLicenseOrder(localOrder);
        return res.json(paidLicenseResponse(localOrder, license, { idempotent: true }));
      } catch (recoveryError) {
        console.error('[publicLicense.capturePayment] Paid order recovery error:', recoveryError);
        return res.status(500).json({
          success: false,
          payment_captured: true,
          message: 'El pago está confirmado, pero la licencia requiere recuperación.',
        });
      }
    }

    // Capturar orden en PayPal
    let captureResult;
    try {
      captureResult = await paypalService.captureOrder(localOrder.provider_order_id);
    } catch (paypalError) {
      console.error('[publicLicense.capturePayment] PayPal capture error:', paypalError.message);
      await licensePaymentOrdersModel.capturePaymentOrder(localOrder.id, {
        status: 'FAILED',
        raw_response: { error: paypalError.message, step: 'capture' },
      });
      return res.status(502).json({
        success: false,
        message: 'Error al capturar el pago en PayPal. Intente de nuevo.',
        detail: paypalError.message,
      });
    }

    // Verificar que el pago estÃ© COMPLETED
    if (String(captureResult.status).toUpperCase() !== 'COMPLETED') {
      await licensePaymentOrdersModel.capturePaymentOrder(localOrder.id, {
        status: 'FAILED',
        raw_response: { captureResult, error: `PayPal status: ${captureResult.status}` },
      });
      return res.status(400).json({
        success: false,
        message: `El pago no fue completado. Estado: ${captureResult.status}`,
      });
    }

    const amountMatches =
      Math.abs(Number(captureResult.amount) - Number(localOrder.total_amount)) < 0.005;
    const currencyMatches =
      String(captureResult.currency || '').toUpperCase() ===
      String(localOrder.currency || '').toUpperCase();
    if (!captureResult.capture_id || !amountMatches || !currencyMatches) {
      await licensePaymentOrdersModel.capturePaymentOrder(localOrder.id, {
        status: 'FAILED',
        raw_response: {
          captureResult,
          error: 'PayPal amount/currency verification failed',
        },
      });
      return res.status(409).json({
        success: false,
        message: 'PayPal no confirmó exactamente el monto y la moneda esperados.',
      });
    }

    // Actualizar orden local como PAID
    const updatedOrder = await licensePaymentOrdersModel.capturePaymentOrder(localOrder.id, {
      provider_capture_id: captureResult.capture_id,
      status: 'PAID',
      raw_response: captureResult.raw || captureResult,
      paid_at: new Date(),
    });

    // Activar o extender la licencia
    let license;
    try {
      license = await finalizePaidLicenseOrder({
        ...localOrder,
        provider_capture_id: captureResult.capture_id,
        status: updatedOrder.status,
      });
    } catch (licenseError) {
      console.error('[publicLicense.capturePayment] License activation error:', licenseError);
      return res.status(500).json({
        success: true,
        payment_captured: true,
        payment_order_id: localOrder.id,
        paypal_order_id: localOrder.provider_order_id,
        message: 'El pago fue capturado pero hubo un error al activar la licencia. Contacte a soporte.',
        license_error: licenseError.message,
      });
    }

    return res.json(
      paidLicenseResponse(
        {
          ...localOrder,
          provider_capture_id: captureResult.capture_id,
          status: updatedOrder.status,
        },
        license
      )
    );
  } catch (error) {
    console.error('[publicLicense.capturePayment] Error:', error);
    return res.status(500).json({ success: false, message: 'Error interno del servidor' });
  }
}

/**
 * POST /api/public/customers/register-or-find
 * Registra o encuentra un cliente por device_id.
 * 
 * Payload: { project_code, device_id, business_name, phone, email }
 */
async function registerOrFindCustomer(req, res) {
  try {
    const {
      project_code,
      device_id,
      business_id,
      business_name,
      business_type,
      owner_name,
      phone,
      email,
    } = req.body || {};
    const device = asTrimmed(device_id);
    const businessId = asTrimmed(business_id);
    const projectCode = asTrimmed(project_code);
    if (!device && !businessId) {
      return res.status(400).json({ success: false, message: 'device_id o business_id es requerido' });
    }
    let project = null;
    if (projectCode) {
      project = await projectsModel.getProjectByCode(projectCode);
    }
    if (!project) {
      project = await projectsModel.getDefaultProject();
    }
    if (!project) {
      return res.status(404).json({ success: false, message: 'Proyecto no encontrado' });
    }
    const customer = await resolvePublicCustomerForPurchase({
      businessId,
      deviceId: device,
      businessName: business_name,
      businessType: business_type,
      ownerName: owner_name,
      phone,
      email,
    });
    return res.json({
      success: true,
      customer_id: customer.id,
      customer_name: customer.nombre_negocio || customer.contacto_nombre,
      customer_email: customer.contacto_email,
      customer_phone: customer.contacto_telefono,
      business_id: customer.business_id || businessId || null,
    });
  } catch (error) {
    console.error('[publicLicense.registerOrFindCustomer] Error:', error);
    return res.status(500).json({ success: false, message: 'Error interno del servidor' });
  }
}/**
 * GET /api/public/paypal/status
 * DiagnÃ³stico del estado de configuraciÃ³n de PayPal.
 * No requiere autenticaciÃ³n.
 */
async function getPaypalStatus(req, res) {
  try {
    const config = paypalService.validatePaypalConfig();
    return res.json({
      success: true,
      paypal_configured: config.ok,
      config: {
        mode: config.mode,
        base_url: config.baseUrl,
        client_id_configured: config.clientIdConfigured,
        client_secret_configured: config.clientSecretConfigured,
        return_url: config.returnUrl || '(no configurado)',
        cancel_url: config.cancelUrl || '(no configurado)',
        webhook_configured: config.webhookIdConfigured,
        brand_name: config.brandName,
      },
      missing: config.missing,
      message: config.ok
        ? 'PayPal estÃ¡ configurado correctamente'
        : `Falta configuraciÃ³n de PayPal: ${config.missing.join(', ')}`,
    });
  } catch (error) {
    console.error('[publicLicense.getPaypalStatus] Error:', error);
    return res.status(500).json({
      success: false,
      message: 'Error al verificar configuraciÃ³n de PayPal',
      error: error.message,
    });
  }
}

/**
 * POST /api/public/license/import-activation
 * Importa una licencia desde un archivo .fulllicense.
 * 
 * Payload: {
 *   project_code: string,
 *   device_id: string,
 *   license_file: { ... contenido completo del archivo .fulllicense ... }
 * }
 * 
 * Flujo:
 * 1. Verificar firma del archivo
 * 2. Verificar project_code coincide
 * 3. Verificar licencia existe y estÃ¡ activa
 * 4. Verificar no vencida
 * 5. Verificar max_devices
 * 6. Crear license_activation para este device_id
 * 7. Devolver licencia activa
 */
async function importLicenseFromFile(req, res) {
  try {
    const { project_code, device_id, license_file } = req.body || {};
    const device = asTrimmed(device_id);
    const projectCode = asTrimmed(project_code);

    console.log('[PUBLIC_IMPORT_FILE] BODY:', JSON.stringify({ project_code, device_id, has_file: !!license_file }));

    if (!device) {
      return res.status(400).json({ success: false, message: 'device_id es requerido' });
    }

    if (!license_file || typeof license_file !== 'object') {
      return res.status(400).json({ success: false, message: 'license_file es requerido (contenido del archivo .fulllicense)' });
    }

    // 1) Verificar firma
    let publicKeyPem;
    try {
      const licenseFileUtil = require('../utils/licenseFile');
      publicKeyPem = licenseFileUtil.getPublicKeyPem();
      const verification = licenseFileUtil.verifyLicenseFile(license_file, publicKeyPem);
      if (!verification.ok) {
        return res.status(400).json({
          success: false,
          message: 'Archivo de licencia invÃ¡lido o modificado. La firma no coincide.',
          reason: verification.reason
        });
      }
    } catch (e) {
      if (e && e.code === 'MISSING_ENV') {
        return res.status(501).json({
          success: false,
          message: 'La verificaciÃ³n de licencias no estÃ¡ configurada en el servidor.'
        });
      }
      console.error('[PUBLIC_IMPORT_FILE] Signature verification error:', e);
      return res.status(500).json({ success: false, message: 'Error al verificar la firma del archivo' });
    }

    const payload = license_file.payload;
    if (!payload) {
      return res.status(400).json({ success: false, message: 'Archivo de licencia invÃ¡lido: falta payload' });
    }

    // 2) Verificar project_code
    const fileProjectCode = String(payload.project_code || '').toUpperCase();
    if (projectCode && fileProjectCode !== projectCode.toUpperCase()) {
      return res.status(400).json({
        success: false,
        message: `Este archivo de licencia no pertenece a este sistema. El archivo es para ${fileProjectCode}.`
      });
    }

    // 3) Buscar licencia por license_key
    const license = await licensesModel.findLicenseByKey(payload.license_key);
    if (!license) {
      return res.status(404).json({
        success: false,
        message: 'La licencia del archivo no existe en el sistema. Verifica que el archivo sea vÃ¡lido.'
      });
    }

    const licenseDetail = await licensesModel.getLicenseById(license.id);
    const payloadBusinessId = String(payload.business_id || '').trim();
    const customerBusinessId = String(licenseDetail?.business_id || '').trim();
    if (payloadBusinessId && customerBusinessId && payloadBusinessId !== customerBusinessId) {
      return res.status(409).json({
        success: false,
        code: 'BUSINESS_ID_CONFLICT',
        message: 'El archivo de licencia pertenece a otro negocio.',
      });
    }

    // 4) Verificar estado
    const licStatus = licensesModel.normalizeLicenseStatus(license.estado);
    if (licStatus === 'BLOQUEADA') {
      return res.status(400).json({ success: false, message: 'Esta licencia estÃ¡ bloqueada. Contacte a soporte.' });
    }
    if (licStatus === 'ELIMINADA') {
      return res.status(400).json({ success: false, message: 'Esta licencia ha sido eliminada.' });
    }
    if (licStatus === 'VENCIDA') {
      return res.status(400).json({ success: false, message: 'Esta licencia estÃ¡ vencida.' });
    }

    // 5) Verificar expiraciÃ³n por fecha
    if (license.fecha_fin) {
      const now = new Date();
      const expiresAt = new Date(license.fecha_fin);
      if (expiresAt.getTime() < now.getTime()) {
        return res.status(400).json({ success: false, message: 'Esta licencia estÃ¡ vencida.' });
      }
    }

    // 6) Verificar max_devices
    const maxDevices = Number(license.max_dispositivos) || 1;
    const actRes = await pool.query(
      `SELECT COUNT(*)::int AS count
       FROM license_activations
       WHERE license_id = $1 AND estado = 'ACTIVA'`,
      [license.id]
    );
    const currentActivations = actRes.rows[0]?.count || 0;

    // Verificar si este device ya estÃ¡ activado
    const existingActRes = await pool.query(
      `SELECT id FROM license_activations
       WHERE license_id = $1 AND device_id = $2 AND estado = 'ACTIVA'`,
      [license.id, device]
    );
    const alreadyActivated = existingActRes.rows.length > 0;

    if (!alreadyActivated && currentActivations >= maxDevices) {
      return res.status(400).json({
        success: false,
        message: `Esta licencia ya estÃ¡ activada en ${currentActivations} equipo(s) y el mÃ¡ximo permitido es ${maxDevices}. Contacte al administrador para liberar un dispositivo.`,
        max_devices: maxDevices,
        current_activations: currentActivations
      });
    }

    // 7) Crear o reactivar activation
    if (alreadyActivated) {
      // Ya estÃ¡ activada en este device, reactivar
      await pool.query(
        `UPDATE license_activations
         SET estado = 'ACTIVA', activated_at = now(), last_check_at = now()
         WHERE license_id = $1 AND device_id = $2`,
        [license.id, device]
      );
    } else {
      // Crear nueva activation
      await pool.query(
        `INSERT INTO license_activations (license_id, project_id, device_id, estado)
         VALUES ($1, $2, $3, 'ACTIVA')
         ON CONFLICT (license_id, device_id)
         DO UPDATE SET estado = 'ACTIVA', project_id = EXCLUDED.project_id, activated_at = now(), last_check_at = now()`,
        [license.id, license.project_id, device]
      );
    }

    // 8) Si la licencia estaba PENDIENTE, activarla
    if (licStatus === 'PENDIENTE') {
      try {
        await licensesModel.activateLicenseManually(license.id);
      } catch (_) {
        // Ignorar si ya estaba activa
      }
    }

    console.log('[PUBLIC_IMPORT_FILE] Licencia importada exitosamente:', {
      license_id: license.id,
      license_key: license.license_key,
      device_id: device,
      project_code: fileProjectCode
    });

    return res.json({
      success: true,
      message: 'Licencia importada correctamente.',
      license: {
        id: license.id,
        license_key: license.license_key,
        status: 'ACTIVA',
        estado: 'ACTIVA',
        project_code: fileProjectCode,
        business_id: customerBusinessId || payloadBusinessId || null,
        expires_at: license.fecha_fin,
        max_devices: maxDevices,
        device_id: device
      }
    });
  } catch (error) {
    console.error('[PUBLIC_IMPORT_FILE] FATAL ERROR:', {
      message: error.message,
      code: error.code,
      detail: error.detail,
      stack: error.stack
    });
    return res.status(500).json({
      success: false,
      message: 'Error interno del servidor al importar la licencia'
    });
  }
}

module.exports = {
  validateLicense,
  startDemo,
  getProjectBillingInfo,
  createPaymentOrder,
  capturePayment,
  registerOrFindCustomer,
  getPaypalStatus,
  importLicenseFromFile
};



