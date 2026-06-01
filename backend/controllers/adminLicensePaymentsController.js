/**
 * Controlador de pagos de licencia (prepago por tiempo).
 * 
 * Endpoints:
 *   POST /api/admin/license-payments/create-paypal-order
 *   POST /api/admin/license-payments/capture-paypal-order
 *   GET  /api/admin/license-payments
 *   GET  /api/admin/license-payments/:id
 *   POST /api/admin/licenses/demo
 */
const { pool } = require('../db/pool');
const projectsModel = require('../models/projectsModel');
const customersModel = require('../models/customersModel');
const licensesModel = require('../models/licensesModel');
const licensePaymentOrdersModel = require('../models/licensePaymentOrdersModel');
const paypalService = require('../services/paypalService');
const { generateLicenseKey } = require('../utils/licenseKey');

function isUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value || '').trim());
}

function parsePagination(req) {
  const pageRaw = req.query.page;
  const limitRaw = req.query.limit;
  const page = Math.max(1, Number(pageRaw || 1) || 1);
  const limit = Math.min(100, Math.max(1, Number(limitRaw || 20) || 20));
  const offset = (page - 1) * limit;
  return { page, limit, offset };
}

/**
 * POST /api/admin/license-payments/create-paypal-order
 * Crea una orden de pago PayPal para comprar tiempo de licencia.
 * 
 * El backend calcula el monto usando la configuración del proyecto.
 * El frontend NO envía el monto.
 */
async function createPayPalOrder(req, res) {
  try {
    const { customer_id, project_id, months, license_id } = req.body || {};

    // Validar customer_id
    if (!customer_id || !isUuid(customer_id)) {
      return res.status(400).json({ success: false, message: 'customer_id inválido' });
    }
    const customer = await customersModel.getCustomerById(customer_id);
    if (!customer) {
      return res.status(404).json({ success: false, message: 'Cliente no encontrado' });
    }

    // Validar project_id
    if (!project_id || !isUuid(project_id)) {
      return res.status(400).json({ success: false, message: 'project_id inválido' });
    }
    const project = await projectsModel.getProjectById(project_id);
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

    // Calcular monto usando la configuración del proyecto (NO confiar en frontend)
    const purchase = projectsModel.calculateLicensePurchase(project, requestedMonths);

    if (purchase.total <= 0) {
      return res.status(400).json({ success: false, message: 'El monto total debe ser mayor que 0. Verifica el precio mensual del proyecto.' });
    }

    // Validar license_id si se proporciona
    let license = null;
    if (license_id) {
      if (!isUuid(license_id)) {
        return res.status(400).json({ success: false, message: 'license_id inválido' });
      }
      license = await licensesModel.getLicenseById(license_id);
      if (!license) {
        return res.status(404).json({ success: false, message: 'Licencia no encontrada' });
      }
      // Verificar que la licencia pertenezca al cliente y proyecto
      if (String(license.customer_id) !== String(customer_id)) {
        return res.status(400).json({ success: false, message: 'La licencia no pertenece a este cliente' });
      }
    }

    // Crear orden local PENDING
    const localOrder = await licensePaymentOrdersModel.createPaymentOrder({
      customer_id: customer.id,
      project_id: project.id,
      license_id: license ? license.id : null,
      months: purchase.months,
      monthly_price: purchase.monthly_price,
      total_amount: purchase.total,
      currency: purchase.currency,
      provider: 'paypal',
      raw_request: {
        customer_id: customer.id,
        project_id: project.id,
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
      console.error('[createPayPalOrder] PayPal error:', paypalError.message);
      // Marcar la orden local como FAILED
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
    console.error('[createPayPalOrder] Error:', error);
    return res.status(500).json({ success: false, message: 'Error interno del servidor' });
  }
}

/**
 * POST /api/admin/license-payments/capture-paypal-order
 * Captura una orden de PayPal aprobada y activa/renueva la licencia.
 */
async function capturePayPalOrder(req, res) {
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
      console.error('[capturePayPalOrder] PayPal capture error:', paypalError.message);
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
      console.error('[capturePayPalOrder] License activation error:', licenseError);
      // La orden ya está PAID, pero la licencia no se pudo activar
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
      message: 'Pago completado. Tu licencia fue activada correctamente.',
    });
  } catch (error) {
    console.error('[capturePayPalOrder] Error:', error);
    return res.status(500).json({ success: false, message: 'Error interno del servidor' });
  }
}

/**
 * GET /api/admin/license-payments
 * Lista órdenes de pago.
 */
async function listPaymentOrders(req, res) {
  try {
    const { page, limit, offset } = parsePagination(req);
    const status = req.query.status ? String(req.query.status).toUpperCase() : undefined;
    const project_id = req.query.project_id || undefined;
    const customer_id = req.query.customer_id || undefined;

    const result = await licensePaymentOrdersModel.listPaymentOrders({
      limit,
      offset,
      status,
      project_id,
      customer_id,
    });

    return res.json({
      success: true,
      page,
      limit,
      total: result.total,
      orders: result.orders,
    });
  } catch (error) {
    console.error('[listPaymentOrders] Error:', error);
    return res.status(500).json({ success: false, message: 'Error interno del servidor' });
  }
}

/**
 * GET /api/admin/license-payments/:id
 * Obtiene detalle de una orden de pago.
 */
async function getPaymentOrderDetail(req, res) {
  try {
    const orderId = req.params.id;
    if (!isUuid(orderId)) {
      return res.status(400).json({ success: false, message: 'ID inválido' });
    }
    const order = await licensePaymentOrdersModel.getPaymentOrderById(orderId);
    if (!order) {
      return res.status(404).json({ success: false, message: 'Orden no encontrada' });
    }
    return res.json({ success: true, order });
  } catch (error) {
    console.error('[getPaymentOrderDetail] Error:', error);
    return res.status(500).json({ success: false, message: 'Error interno del servidor' });
  }
}

/**
 * POST /api/admin/licenses/demo
 * Crea una licencia demo gratis para un cliente.
 */
async function createDemoLicense(req, res) {
  try {
    const { customer_id, project_id, max_dispositivos, notas } = req.body || {};

    // Validar customer_id
    if (!customer_id || !isUuid(customer_id)) {
      return res.status(400).json({ success: false, message: 'customer_id inválido' });
    }
    const customer = await customersModel.getCustomerById(customer_id);
    if (!customer) {
      return res.status(404).json({ success: false, message: 'Cliente no encontrado' });
    }

    // Validar project_id
    if (!project_id || !isUuid(project_id)) {
      return res.status(400).json({ success: false, message: 'project_id inválido' });
    }
    const project = await projectsModel.getProjectById(project_id);
    if (!project) {
      return res.status(404).json({ success: false, message: 'Proyecto no encontrado' });
    }

    // Validar que el proyecto permita demo
    if (!project.allow_demo) {
      return res.status(400).json({ success: false, message: 'Este proyecto no permite demo' });
    }

    const demoDays = Number(project.demo_days) || 5;
    const maxDisp = Math.floor(Number(max_dispositivos)) || 1;

    // Verificar si ya existe una licencia demo activa para este cliente/proyecto
    const existingLicenses = await licensesModel.listLicenses({
      customer_id: customer.id,
      project_id: project.id,
      limit: 10,
      offset: 0,
    });

    const hasActiveDemo = existingLicenses.licenses.some(
      l => String(l.tipo || '').toUpperCase() === 'DEMO' &&
           String(l.estado || '').toUpperCase() === 'ACTIVA'
    );

    if (hasActiveDemo) {
      return res.status(409).json({
        success: false,
        message: 'Este cliente ya tiene una licencia demo activa para este proyecto',
      });
    }

    // Generar license_key
    let licenseKey;
    for (let i = 0; i < 6; i++) {
      licenseKey = generateLicenseKey('DEMO');
      try {
        const existing = await licensesModel.findLicenseByKey(licenseKey);
        if (!existing) break;
      } catch (_) {
        break;
      }
    }

    // Crear licencia
    const license = await licensesModel.createLicenseWithKey({
      project_id: project.id,
      customer_id: customer.id,
      license_key: licenseKey,
      tipo: 'DEMO',
      license_type: 'SUSCRIPCION',
      dias_validez: demoDays,
      max_dispositivos: maxDisp,
      notas: notas ? String(notas) : 'Demo gratis',
    });

    // Activar automáticamente
    const activated = await licensesModel.activateLicenseManually(license.id);

    // Actualizar activation_source
    try {
      await pool.query(
        `UPDATE licenses SET activation_source = 'demo' WHERE id = $1`,
        [activated.id]
      );
    } catch (_) {}

    return res.status(201).json({
      success: true,
      license: {
        ...activated,
        activation_source: 'demo',
      },
      message: `Licencia demo creada y activada por ${demoDays} días`,
    });
  } catch (error) {
    console.error('[createDemoLicense] Error:', error);
    return res.status(500).json({ success: false, message: 'Error interno del servidor' });
  }
}

module.exports = {
  createPayPalOrder,
  capturePayPalOrder,
  listPaymentOrders,
  getPaymentOrderDetail,
  createDemoLicense,
};
