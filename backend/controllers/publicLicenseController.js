/**
 * Controlador público de licencias para FullCredit y otras apps SaaS.
 * 
 * Endpoints públicos (SIN middleware isAdmin):
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

/**
 * POST /api/public/license/validate
 * Valida la licencia de un dispositivo para un proyecto.
 * 
 * Payload: { project_code, device_id }
 * 
 * Respuestas posibles:
 *   - Licencia ACTIVA y vigente → { valid: true, status: 'ACTIVA', ... }
 *   - Demo activo → { valid: true, status: 'DEMO_ACTIVE', ... }
 *   - Demo vencido → { valid: false, status: 'DEMO_EXPIRED', ... }
 *   - Licencia vencida → { valid: false, status: 'EXPIRED', ... }
 *   - Sin licencia → { valid: false, status: 'NO_LICENSE', ... }
 */
async function validateLicense(req, res) {
  try {
    const { project_code, device_id } = req.body || {};
    const device = asTrimmed(device_id);
    const projectCode = asTrimmed(project_code);

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

    const now = new Date();

    // 1) Buscar licencias FULL activas para este device + proyecto
    const fullActRes = await pool.query(
      `SELECT l.*, a.device_id, a.estado AS activation_estado
       FROM license_activations a
       JOIN licenses l ON l.id = a.license_id
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
          demo_active: false,
          payment_required: false,
          customer_id: fullActivation.customer_id,
          project_id: project.id
        });
      }

      // Licencia FULL existe pero vencida
      if (licStatus === 'VENCIDA' || licStatus === 'EXPIRED') {
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
          project_id: project.id
        });
      }
    }

    // 2) Buscar licencias DEMO activas para este device + proyecto
    const demoActRes = await pool.query(
      `SELECT l.*, a.device_id, a.estado AS activation_estado
       FROM license_activations a
       JOIN licenses l ON l.id = a.license_id
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

        return res.json({
          success: true,
          valid: true,
          status: 'DEMO_ACTIVE',
          reason: null,
          message: `Demo activo. Te quedan ${daysRemaining} días.`,
          license_key: demoActivation.license_key,
          project_code: project.code,
          expires_at: expiresAt,
          days_remaining: daysRemaining,
          max_devices: demoActivation.max_dispositivos,
          demo_active: true,
          payment_required: false,
          customer_id: demoActivation.customer_id,
          project_id: project.id
        });
      }

      // Demo vencido
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
        project_id: project.id
      });
    }

    // 3) Verificar si hubo demo previa (demo_trials) para este device
    const trialRes = await pool.query(
      `SELECT id, started_at, customer_id
       FROM demo_trials
       WHERE project_id = $1 AND device_id = $2
       ORDER BY started_at DESC
       LIMIT 1`,
      [project.id, device]
    );
    const trial = trialRes.rows[0];

    if (trial) {
      // Ya consumió demo, no puede iniciar otra
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
        project_id: project.id
      });
    }

    // 4) No hay licencia ni demo
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
      project_id: project.id
    });
  } catch (error) {
    console.error('[publicLicense.validateLicense] Error:', error);
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
    const business_name = asTrimmed(req.body?.business_name || req.body?.nombre_negocio);
    const customer_name = asTrimmed(req.body?.customer_name || req.body?.contacto_nombre);
    const customer_email = normalizeEmail(req.body?.customer_email || req.body?.contacto_email);
    const device_id = asTrimmed(req.body?.device_id);
    const project_code_raw = asTrimmed(req.body?.project_code);

    if (!device_id) {
      return res.status(400).json({ success: false, message: 'device_id es requerido' });
    }

    if (!business_name && !customer_name) {
      return res.status(400).json({ success: false, message: 'business_name o customer_name es requerido' });
    }

    // Resolver proyecto
    let project = null;
    if (project_code_raw) {
      project = await projectsModel.getProjectByCode(project_code_raw);
    }
    if (!project) {
      project = await projectsModel.getDefaultProject();
    }
    if (!project) {
      return res.status(404).json({ success: false, message: 'Proyecto no encontrado' });
    }

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

      // Primero buscar por device_id en demo_trials o license_activations
      const existingCustomerRes = await client.query(
        `SELECT DISTINCT c.*
         FROM customers c
         LEFT JOIN demo_trials dt ON dt.customer_id = c.id AND dt.device_id = $1
         LEFT JOIN license_activations la ON la.customer_id = c.id AND la.device_id = $1
         WHERE dt.id IS NOT NULL OR la.id IS NOT NULL
         LIMIT 1`,
        [device_id]
      );
      customer = existingCustomerRes.rows[0] || null;

      if (!customer && customer_email) {
        customer = await customersModel.findCustomerByContact({ contacto_email: customer_email });
      }

      if (!customer) {
        // Crear nuevo customer
        const createdRes = await client.query(
          `INSERT INTO customers (nombre_negocio, contacto_nombre, contacto_email)
           VALUES ($1, $2, $3)
           RETURNING *`,
          [
            business_name || customer_name || 'Cliente FullCredit',
            customer_name || null,
            customer_email || null
          ]
        );
        customer = createdRes.rows[0];
      } else {
        // Actualizar datos si viene información nueva
        if (business_name || customer_name || customer_email) {
          try {
            await client.query(
              `UPDATE customers
               SET nombre_negocio = COALESCE(NULLIF($2,''), nombre_negocio),
                   contacto_nombre = COALESCE(NULLIF($3,''), contacto_nombre),
                   contacto_email = COALESCE(NULLIF($4,''), contacto_email)
               WHERE id = $1`,
              [customer.id, business_name, customer_name, customer_email]
            );
          } catch (_) {}
        }
      }

      // 2) Verificar que no exista demo previa para este device + proyecto
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
        return res.status(409).json({
          success: false,
          code: 'DEMO_ALREADY_USED',
          message: 'La prueba DEMO ya fue utilizada en este equipo. Debes activar una licencia FULL.'
        });
      }

      // 3) Verificar si ya existe una DEMO activa para este customer + proyecto
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

      // 4) Configuración de demo desde el proyecto
      const demoDays = Math.max(1, Number(project.demo_days) || 5);
      const maxDisp = Math.max(1, Number(project.max_dispositivos) || 1);

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
        return res.status(500).json({ success: false, message: 'No se pudo generar license_key' });
      }

      // 6) Activar demo
      const fechaInicio = now;
      const fechaFin = new Date(now.getTime() + demoDays * 24 * 60 * 60 * 1000);

      const updRes = await client.query(
        `UPDATE licenses
         SET fecha_inicio = $2, fecha_fin = $3, estado = 'ACTIVA'
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

      // 7) Registrar consumo de demo
      try {
        await client.query(
          `INSERT INTO demo_trials (project_id, device_id, contacto_email_norm, customer_id, license_id)
           VALUES ($1, $2, $3, $4, $5)`,
          [project.id, device_id, customer_email || null, customer.id, license.id]
        );
      } catch (e) {
        if (e && e.code === '23505') {
          await client.query('ROLLBACK');
          return res.status(409).json({
            success: false,
            code: 'DEMO_ALREADY_USED',
            message: 'La prueba DEMO ya fue utilizada.'
          });
        }
        throw e;
      }

      await client.query('COMMIT');
      return res.status(201).json({
        success: true,
        message: `Demo iniciada por ${demoDays} días`,
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
      console.error('[publicLicense.startDemo] Error:', error);
      return res.status(500).json({ success: false, message: 'Error interno del servidor' });
    } finally {
      client.release();
    }
  } catch (error) {
    console.error('[publicLicense.startDemo] Outer error:', error);
    return res.status(500).json({ success: false, message: 'Error interno del servidor' });
  }
}

/**
 * GET /api/public/projects/:code/billing
 * Obtiene la configuración de facturación de un proyecto.
 */
async function getProjectBillingInfo(req, res) {
  try {
    const code = asTrimmed(req.params.code);
    if (!code) {
      return res.status(400).json({ success: false, message: 'Código de proyecto requerido' });
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

/**
 * POST /api/public/license-payments/create-paypal-order
 * Crea una orden de pago PayPal para comprar tiempo de licencia.
 * 
 * El backend calcula el monto usando la configuración del proyecto.
 * El frontend NO envía el monto.
 * 
 * Payload: { project_code, device_id, months }
 */
async function createPaymentOrder(req, res) {
  try {
    const { project_code, device_id, months } = req.body || {};
    const device = asTrimmed(device_id);
    const projectCode = asTrimmed(project_code);

    if (!device) {
      return res.status(400).json({ success: false, message: 'device_id es requerido' });
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
      return res.status(400).json({ success: false, message: 'months debe ser un número entero positivo' });
    }

    const minMonths = Number(project.min_purchase_months) || 1;
    if (requestedMonths < minMonths) {
      return res.status(400).json({
        success: false,
        message: `La compra mínima es de ${minMonths} meses para este proyecto`,
      });
    }

    // Resolver customer_id por device_id
    let customerId = null;
    const customerRes = await pool.query(
      `SELECT DISTINCT customer_id
       FROM (
         SELECT customer_id FROM demo_trials WHERE device_id = $1
         UNION
         SELECT l.customer_id FROM license_activations a
         JOIN licenses l ON l.id = a.license_id
         WHERE a.device_id = $1
       ) sub
       WHERE customer_id IS NOT NULL
       LIMIT 1`,
      [device]
    );
    customerId = customerRes.rows[0]?.customer_id || null;

    if (!customerId) {
      return res.status(404).json({
        success: false,
        message: 'No se encontró un cliente asociado a este dispositivo. Debes iniciar demo primero o registrarte.'
      });
    }

    // Calcular monto usando la configuración del proyecto (NO confiar en frontend)
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
        device_id: device,
        project_code: project.code,
        months: purchase.months,
        monthly_price: purchase.monthly_price,
        total: purchase.total,
        currency: purchase.currency,
      },
    });

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
        message: 'Error al crear la orden en PayPal. Intente de nuevo más tarde.',
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

    return res.json({
      success: true,
      payment_order_id: localOrder.id,
      paypal_order_id: paypalOrder.id,
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

    // Verificar que no esté ya pagada
    if (String(localOrder.status).toUpperCase() === 'PAID') {
      return res.status(409).json({ success: false, message: 'Esta orden ya fue pagada y procesada' });
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

    // Verificar que el pago esté COMPLETED
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
      license = await licensesModel.activateOrExtendPaidLicense({
        customerId: localOrder.customer_id,
        projectId: localOrder.project_id,
        months: localOrder.months,
        paymentOrderId: localOrder.id,
        maxDevices: 1,
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

    return res.json({
      success: true,
      payment_captured: true,
      payment_order_id: localOrder.id,
      paypal_order_id: localOrder.provider_order_id,
      capture_id: captureResult.capture_id,
      license: {
        id: license.id,
        license_key: license.license_key,
        status: license.estado,
        estado: license.estado,
        activated_at: license.fecha_inicio,
        expires_at: license.fecha_fin,
        months_added: localOrder.months,
      },
      message: 'Pago confirmado. Tu licencia fue activada correctamente.',
    });
  } catch (error) {
    console.error('[publicLicense.capturePayment] Error:', error);
    return res.status(500).json({ success: false, message: 'Error interno del servidor' });
  }
}

/**
 * POST /api/public/customers/register-or-find
 * Registra o encuentra un cliente por device_id.
 * 
 * Payload: { project_code, business_name, phone, email, device_id }
 */
async function registerOrFindCustomer(req, res) {
  try {
    const { project_code, business_name, phone, email, device_id } = req.body || {};
    const device = asTrimmed(device_id);
    const businessName = asTrimmed(business_name);
    const phoneNorm = normalizePhone(phone);
    const emailNorm = normalizeEmail(email);

    if (!device) {
      return res.status(400).json({ success: false, message: 'device_id es requerido' });
    }

    if (!businessName && !emailNorm && !phoneNorm) {
      return res.status(400).json({ success: false, message: 'business_name, email o phone es requerido' });
    }

    // Buscar proyecto
    let project = null;
    if (project_code) {
      project = await projectsModel.getProjectByCode(project_code);
    }
    if (!project) {
      project = await projectsModel.getDefaultProject();
    }

    // Buscar customer existente por device_id
    let customer = null;
    const existingRes = await pool.query(
      `SELECT DISTINCT c.*
       FROM customers c
       LEFT JOIN demo_trials dt ON dt.customer_id = c.id AND dt.device_id = $1
       LEFT JOIN license_activations la ON la.customer_id = c.id AND la.device_id = $1
       WHERE dt.id IS NOT NULL OR la.id IS NOT NULL
       LIMIT 1`,
      [device]
    );
    customer = existingRes.rows[0] || null;

    // Si no, buscar por email
    if (!customer && emailNorm) {
      customer = await customersModel.findCustomerByContact({ contacto_email: emailNorm });
    }

    // Si no, buscar por teléfono
    if (!customer && phoneNorm) {
      customer = await customersModel.findCustomerByContact({ contacto_telefono: phoneNorm });
    }

    if (customer) {
      // Actualizar datos si viene información nueva
      if (businessName || emailNorm || phoneNorm) {
        try {
          await customersModel.updateCustomer(customer.id, {
            nombre_negocio: businessName || undefined,
            contacto_email: emailNorm || undefined,
            contacto_telefono: phoneNorm || undefined,
          });
        } catch (_) {}
      }

      return res.json({
        success: true,
        customer_id: customer.id,
        customer_name: customer.nombre_negocio || customer.contacto_nombre || 'Cliente',
        is_new: false,
      });
    }

    // Crear nuevo customer
    const newCustomer = await customersModel.createCustomer({
      nombre_negocio: businessName || 'Cliente FullCredit',
      contacto_nombre: null,
      contacto_telefono: phoneNorm || null,
      contacto_email: emailNorm || null,
    });

    return res.status(201).json({
      success: true,
      customer_id: newCustomer.id,
      customer_name: newCustomer.nombre_negocio || newCustomer.contacto_nombre || 'Cliente',
      is_new: true,
    });
  } catch (error) {
    console.error('[publicLicense.registerOrFindCustomer] Error:', error);
    return res.status(500).json({ success: false, message: 'Error interno del servidor' });
  }
}

module.exports = {
  validateLicense,
  startDemo,
  getProjectBillingInfo,
  createPaymentOrder,
  capturePayment,
  registerOrFindCustomer,
};
