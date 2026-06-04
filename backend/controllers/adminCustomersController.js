const { pool } = require('../db/pool');
const customersModel = require('../models/customersModel');
const {
  normalizeBusinessId,
  isValidBusinessIdForExistingRecord,
  isValidBusinessIdForNewRecord,
  resolveBusinessIdForNewRecord,
  getCustomerBusinessIdMutationContext,
  canChangeBusinessIdNormally,
  requiresRepairMode,
  hasProtectedCustomerActivity,
  beginBusinessIdRepairSession,
  emitBusinessIdAudit,
} = require('../services/businessIdPolicyService');

function parsePagination(req) {
  const pageRaw = req.query.page;
  const limitRaw = req.query.limit;
  const page = Math.max(1, Number(pageRaw || 1) || 1);
  const limit = Math.min(100, Math.max(1, Number(limitRaw || 20) || 20));
  const offset = (page - 1) * limit;
  return { page, limit, offset };
}

async function createCustomer(req, res) {
  try {
    const { nombre_negocio, contacto_nombre, contacto_telefono, contacto_email, rol_negocio, business_id } = req.body || {};
    const normalizedBusinessId = normalizeBusinessId(business_id);

    if (!nombre_negocio || !String(nombre_negocio).trim()) {
      return res.status(400).json({ ok: false, message: 'nombre_negocio es requerido' });
    }

    if (!contacto_telefono || !String(contacto_telefono).trim()) {
      return res.status(400).json({ ok: false, message: 'contacto_telefono es requerido' });
    }

    if (normalizedBusinessId && !isValidBusinessIdForNewRecord(normalizedBusinessId)) {
      return res.status(400).json({
        ok: false,
        code: 'INVALID_NEW_BUSINESS_ID',
        message: 'Para nuevos clientes, business_id debe ser UUID v4',
      });
    }

    const customer = await customersModel.createCustomer({
      nombre_negocio: String(nombre_negocio).trim(),
      contacto_nombre: contacto_nombre ? String(contacto_nombre).trim() : null,
      contacto_telefono: String(contacto_telefono).trim(),
      contacto_email: contacto_email ? String(contacto_email).trim() : null,
      rol_negocio: rol_negocio ? String(rol_negocio).trim() : null,
      business_id: normalizedBusinessId
    });

    return res.status(201).json({ ok: true, customer });
  } catch (error) {
    console.error('createCustomer error:', error);
    // 23505 = unique_violation
    if (error && error.code === 'INVALID_NEW_BUSINESS_ID') {
      return res.status(400).json({ success: false, code: error.code, message: 'Para nuevas asignaciones, business_id debe ser UUID v4' });
    }

    if (error && error.code === 'INVALID_NEW_BUSINESS_ID') {
      return res.status(400).json({ success: false, code: error.code, message: 'Para nuevas asignaciones, business_id debe ser UUID v4' });
    }

    if (error && error.code === '23505') {
      const constraint = String(error.constraint || '');
      if (constraint.includes('contacto_telefono')) {
        return res.status(409).json({ ok: false, message: 'Ya existe un cliente con ese contacto_telefono' });
      }
      if (constraint.includes('contacto_email')) {
        return res.status(409).json({ ok: false, message: 'Ya existe un cliente con ese contacto_email' });
      }
      if (constraint.includes('business_id') || constraint.includes('idx_customers_business_id_unique')) {
        return res.status(409).json({ ok: false, message: 'Ya existe un cliente con ese business_id' });
      }
      return res.status(409).json({ ok: false, message: 'Ya existe un cliente con esos datos (duplicado)' });
    }

    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function listCustomers(req, res) {
  try {
    const { page, limit, offset } = parsePagination(req);
    const { total, customers } = await customersModel.listCustomers({ limit, offset });
    return res.json({ ok: true, page, limit, total, customers });
  } catch (error) {
    console.error('listCustomers error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

function isUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value || ''));
}

function businessIdConflictResponse(message, extra = {}) {
  return {
    ok: false,
    success: false,
    code: 'BUSINESS_ID_MUTATION_BLOCKED',
    message,
    ...extra,
  };
}

async function deleteCustomer(req, res) {
  try {
    const customerId = String(req.params.id || '').trim();
    if (!customerId) {
      return res.status(400).json({ ok: false, message: 'id es requerido' });
    }

    if (!isUuid(customerId)) {
      return res.status(400).json({ ok: false, message: 'id inválido (UUID requerido)' });
    }

    const result = await customersModel.deleteCustomerCascade(customerId);
    if (!result) {
      return res.status(404).json({ ok: false, message: 'Cliente no encontrado' });
    }

    return res.json({
      ok: true,
      deletedCustomer: result.deletedCustomer,
      deletedLicensesCount: result.deletedLicensesCount,
      deletedPaymentOrdersCount: result.deletedPaymentOrdersCount || 0
    });
  } catch (error) {
    console.error('deleteCustomer error:', error);

    // Errores de validación de negocio (409)
    if (error && (error.code === 'CUSTOMER_HAS_ACTIVE_LICENSES' || error.code === 'CUSTOMER_HAS_PAYMENTS')) {
      return res.status(error.statusCode || 409).json({
        ok: false,
        code: error.code,
        message: error.message
      });
    }

    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function setBusinessId(req, res) {
  try {
    const customerId = String(req.params.id || '').trim();
    if (!customerId) {
      return res.status(400).json({ ok: false, message: 'id es requerido' });
    }

    if (!isUuid(customerId)) {
      return res.status(400).json({ ok: false, message: 'id inválido (UUID requerido)' });
    }

    const business_id = normalizeBusinessId(req.body?.business_id);

    if (!business_id) {
      return res.status(400).json({ ok: false, message: 'business_id es requerido' });
    }

    const context = await getCustomerBusinessIdMutationContext(customerId);
    if (!context) {
      return res.status(404).json({ ok: false, message: 'Cliente no encontrado' });
    }

    if (!canChangeBusinessIdNormally(context, business_id)) {
      await emitBusinessIdAudit(
        {
          event: 'overwrite_blocked',
          source: 'admin_set_business_id',
          action: 'blocked',
          reason: 'Cambio normal bloqueado para proteger business_id existente',
          severity: hasProtectedCustomerActivity(context) ? 'critical' : 'warn',
          currentBusinessId: context.customer.business_id || null,
          incomingBusinessId: business_id,
          resolvedBusinessId: context.customer.business_id || null,
          customerId,
        },
        { req }
      );
      return res.status(409).json(
        businessIdConflictResponse(
          'Este cliente ya tiene business_id asignado. Usa la ruta de reparación administrativa si necesitas corregirlo.'
        )
      );
    }

    if (!context.customer.business_id && !isValidBusinessIdForNewRecord(business_id)) {
      return res.status(400).json({
        ok: false,
        code: 'INVALID_NEW_BUSINESS_ID',
        message: 'Para una asignación inicial, business_id debe ser UUID v4',
      });
    }

    const updated = await customersModel.setCustomerBusinessId({ customerId, business_id });
    if (!updated) {
      return res.status(404).json({ ok: false, message: 'Cliente no encontrado' });
    }

    await emitBusinessIdAudit(
      {
        event: context.customer.business_id ? 'read' : 'initial_set',
        source: 'admin_set_business_id',
        action: 'allowed',
        reason: context.customer.business_id ? 'Asignación idempotente' : 'Business ID inicial establecido',
        severity: 'info',
        currentBusinessId: context.customer.business_id || null,
        incomingBusinessId: business_id,
        resolvedBusinessId: updated.business_id || business_id,
        customerId,
      },
      { req }
    );

    return res.json({ ok: true, customer: updated });
  } catch (error) {
    console.error('admin.setBusinessId error:', error);

    if (error && error.code === 'MIGRATION_PENDING') {
      return res.status(501).json({ ok: false, message: 'Migración pendiente: falta columna business_id en customers' });
    }

    // 23505 = unique_violation
    if (error && error.code === '23505') {
      return res.status(409).json({ ok: false, message: 'Ese business_id ya está asignado a otro cliente' });
    }

    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function getCustomerByBusinessId(req, res) {
  try {
    const businessId = String(req.params.businessId || '').trim();
    if (!businessId) {
      return res.status(400).json({ ok: false, message: 'business_id es requerido' });
    }

    const customer = await customersModel.getCustomerByBusinessId(businessId);
    if (!customer) {
      return res.status(404).json({ ok: false, message: 'Cliente no encontrado para ese business_id' });
    }

    return res.json({ ok: true, customer });
  } catch (error) {
    console.error('admin.getCustomerByBusinessId error:', error);
    if (error && error.code === 'MIGRATION_PENDING') {
      return res.status(501).json({ ok: false, message: 'Migración pendiente: falta columna business_id en customers' });
    }
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function getCustomerById(req, res) {
  try {
    const customerId = String(req.params.id || '').trim();
    if (!customerId) {
      return res.status(400).json({ ok: false, message: 'id es requerido' });
    }

    if (!isUuid(customerId)) {
      return res.status(400).json({ ok: false, message: 'id inválido (UUID requerido)' });
    }

    const customer = await customersModel.getCustomerById(customerId);
    if (!customer) {
      return res.status(404).json({ ok: false, message: 'Cliente no encontrado' });
    }

    return res.json({ ok: true, customer });
  } catch (error) {
    console.error('admin.getCustomerById error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function updateCustomer(req, res) {
  try {
    const customerId = String(req.params.id || '').trim();
    if (!customerId) {
      return res.status(400).json({ ok: false, message: 'id es requerido' });
    }

    if (!isUuid(customerId)) {
      return res.status(400).json({ ok: false, message: 'id inválido (UUID requerido)' });
    }

    const body = req.body || {};
    const allowed = ['nombre_negocio', 'contacto_nombre', 'contacto_telefono', 'contacto_email', 'rol_negocio', 'business_id'];
    const updates = {};
    for (const k of allowed) {
      if (Object.prototype.hasOwnProperty.call(body, k)) {
        const rawValue = body[k];
        if (rawValue === null) {
          updates[k] = null;
        } else {
          const trimmed = String(rawValue || '').trim();
          updates[k] = trimmed === '' ? null : trimmed;
        }
      }
    }

    if (!Object.keys(updates).length) {
      return res.status(400).json({ ok: false, message: 'No hay campos para actualizar' });
    }

    // Basic validation: if nombre_negocio or contacto_telefono provided, must be non-empty
    if (updates.hasOwnProperty('nombre_negocio') && !updates.nombre_negocio) {
      return res.status(400).json({ ok: false, message: 'nombre_negocio es requerido' });
    }

    if (updates.hasOwnProperty('contacto_telefono') && !updates.contacto_telefono) {
      return res.status(400).json({ ok: false, message: 'contacto_telefono es requerido' });
    }

    const current = await customersModel.getCustomerById(customerId);
    if (!current) {
      return res.status(404).json({ ok: false, message: 'Cliente no encontrado' });
    }

    if (Object.prototype.hasOwnProperty.call(updates, 'business_id')) {
      const context = await getCustomerBusinessIdMutationContext(customerId);
      const nextBusinessId = normalizeBusinessId(updates.business_id);
      const currentBusinessId = normalizeBusinessId(current.business_id);

      if (!nextBusinessId) {
        return res.status(409).json(
          businessIdConflictResponse(
            'No se permite vaciar business_id desde el flujo normal.'
          )
        );
      }

      if (!canChangeBusinessIdNormally(context, nextBusinessId)) {
        await emitBusinessIdAudit(
          {
            event: 'overwrite_blocked',
            source: 'admin_update_customer',
            action: 'blocked',
            reason: 'Intento de mutación de business_id desde updateCustomer',
            severity: hasProtectedCustomerActivity(context) ? 'critical' : 'warn',
            currentBusinessId,
            incomingBusinessId: nextBusinessId,
            resolvedBusinessId: currentBusinessId,
            customerId,
          },
          { req }
        );
        return res.status(409).json(
          businessIdConflictResponse(
            'No se permite cambiar business_id desde la edición normal del cliente.'
          )
        );
      }

      if (!currentBusinessId && !isValidBusinessIdForNewRecord(nextBusinessId)) {
        return res.status(400).json({
          ok: false,
          code: 'INVALID_NEW_BUSINESS_ID',
          message: 'Para asignación inicial, business_id debe ser UUID v4',
        });
      }

      updates.business_id = nextBusinessId;
    }

    const updated = await customersModel.updateCustomer(customerId, updates);
    if (!updated) {
      return res.status(404).json({ ok: false, message: 'Cliente no encontrado' });
    }

    return res.json({ ok: true, customer: updated });
  } catch (error) {
    console.error('updateCustomer error:', error);
    if (error && error.code === '23505') {
      const constraint = String(error.constraint || '');
      if (constraint.includes('contacto_telefono')) {
        return res.status(409).json({ ok: false, message: 'Ya existe un cliente con ese contacto_telefono' });
      }
      if (constraint.includes('contacto_email')) {
        return res.status(409).json({ ok: false, message: 'Ya existe un cliente con ese contacto_email' });
      }
      if (constraint.includes('business_id') || constraint.includes('idx_customers_business_id_unique')) {
        return res.status(409).json({ ok: false, message: 'Ya existe un cliente con ese business_id' });
      }
      return res.status(409).json({ ok: false, message: 'Ya existe un cliente con esos datos (duplicado)' });
    }

    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

/**
 * GET /api/admin/customers/:id/licenses
 * Obtiene todas las licencias de un cliente.
 */
async function getCustomerLicenses(req, res) {
  try {
    const customerId = String(req.params.id || '').trim();
    if (!customerId) {
      return res.status(400).json({ success: false, message: 'id es requerido' });
    }

    if (!isUuid(customerId)) {
      return res.status(400).json({ success: false, message: 'id inválido (UUID requerido)' });
    }

    const context = await getCustomerBusinessIdMutationContext(customerId);
    if (!context) {
      return res.status(404).json({ success: false, message: 'Cliente no encontrado' });
    }

    const licenses = await customersModel.getCustomerLicenses(customerId);

    // Mapear al formato esperado por el frontend
    const mapped = licenses.map(l => ({
      id: l.id,
      license_key: l.license_key,
      project_id: l.project_id,
      project_code: l.project_code || 'DEFAULT',
      project_name: l.project_name || 'Proyecto no definido',
      tipo: l.tipo,
      estado: l.estado,
      activation_source: l.activation_source || null,
      payment_order_id: l.payment_order_id || null,
      created_at: l.created_at,
      activated_at: l.fecha_inicio,
      expires_at: l.fecha_fin,
      days_remaining: l.days_remaining,
      max_dispositivos: l.max_dispositivos,
      notas: l.notas,
      customer_name: l.nombre_negocio,
      business_id: l.business_id
    }));

    return res.json({ success: true, licenses: mapped });
  } catch (error) {
    console.error('getCustomerLicenses error:', error);
    return res.status(500).json({ success: false, message: 'Error al obtener licencias del cliente' });
  }
}

/**
 * POST /api/admin/customers/:id/assign-business-id
 * Asigna o regenera el Business ID de un cliente.
 */
async function assignBusinessId(req, res) {
  try {
    const customerId = String(req.params.id || '').trim();
    if (!customerId) {
      return res.status(400).json({ success: false, message: 'id es requerido' });
    }

    if (!isUuid(customerId)) {
      return res.status(400).json({ success: false, message: 'id inválido (UUID requerido)' });
    }

    const context = await getCustomerBusinessIdMutationContext(customerId);
    if (!context) {
      return res.status(404).json({ success: false, message: 'Cliente no encontrado' });
    }

    // Si ya tiene business_id y no se fuerza regeneración
    if (context.customer.business_id && String(context.customer.business_id).trim()) {
      await emitBusinessIdAudit(
        {
          event: 'overwrite_blocked',
          source: 'admin_assign_business_id',
          action: 'blocked',
          reason: 'assignBusinessId no puede reemplazar business_id existente',
          severity: hasProtectedCustomerActivity(context) ? 'critical' : 'warn',
          currentBusinessId: context.customer.business_id,
          incomingBusinessId: normalizeBusinessId(req.body?.business_id),
          resolvedBusinessId: context.customer.business_id,
          customerId,
        },
        { req }
      );
      return res.json({
        success: true,
        message: 'El cliente ya tiene un Business ID asignado',
        customer: context.customer,
        already_exists: true
      });
    }

    // Generar business_id único
    let businessId = normalizeBusinessId(req.body?.business_id);
    businessId = await resolveBusinessIdForNewRecord(businessId);

    const updated = await customersModel.setCustomerBusinessId({ customerId, business_id: businessId });
    if (!updated) {
      return res.status(404).json({ success: false, message: 'Cliente no encontrado' });
    }

    await emitBusinessIdAudit(
      {
        event: 'initial_set',
        source: 'admin_assign_business_id',
        action: 'allowed',
        reason: 'Business ID inicial asignado desde admin',
        severity: 'info',
        currentBusinessId: null,
        incomingBusinessId: businessId,
        resolvedBusinessId: updated.business_id,
        customerId,
      },
      { req }
    );

    return res.json({
      success: true,
      message: 'Business ID asignado correctamente',
      customer: updated
    });
  } catch (error) {
    console.error('assignBusinessId error:', error);

    if (error && error.code === '23505') {
      return res.status(409).json({ success: false, message: 'Ese business_id ya está asignado a otro cliente' });
    }

    return res.status(500).json({ success: false, message: 'Error interno del servidor' });
  }
}

async function repairBusinessId(req, res) {
  const customerId = String(req.params.id || '').trim();
  const business_id = normalizeBusinessId(req.body?.business_id);
  const forceRepair = req.body?.forceRepair === true;
  const reason = String(req.body?.reason || '').trim();

  if (!customerId) {
    return res.status(400).json({ success: false, message: 'id es requerido' });
  }
  if (!isUuid(customerId)) {
    return res.status(400).json({ success: false, message: 'id invÃ¡lido (UUID requerido)' });
  }
  if (!forceRepair) {
    return res.status(400).json({ success: false, code: 'FORCE_REPAIR_REQUIRED', message: 'forceRepair=true es requerido para reparaciones de business_id' });
  }
  if (!reason) {
    return res.status(400).json({ success: false, code: 'REPAIR_REASON_REQUIRED', message: 'Debes indicar un motivo para la reparaciÃ³n administrativa' });
  }
  if (!business_id) {
    return res.status(400).json({ success: false, message: 'business_id es requerido' });
  }

  const context = await getCustomerBusinessIdMutationContext(customerId);
  if (!context) {
    return res.status(404).json({ success: false, message: 'Cliente no encontrado' });
  }

  const currentBusinessId = normalizeBusinessId(context.customer.business_id);
  if (!currentBusinessId && !isValidBusinessIdForNewRecord(business_id)) {
    return res.status(400).json({ success: false, code: 'INVALID_NEW_BUSINESS_ID', message: 'Para asignaciÃ³n inicial, business_id debe ser UUID v4' });
  }
  if (currentBusinessId && !(await isValidBusinessIdForExistingRecord(business_id))) {
    return res.status(400).json({ success: false, code: 'INVALID_EXISTING_BUSINESS_ID', message: 'El business_id de reparaciÃ³n no es vÃ¡lido para un registro existente' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await beginBusinessIdRepairSession(client);

    const updated = await customersModel.setCustomerBusinessId({ customerId, business_id }, { client });
    if (!updated) {
      await client.query('ROLLBACK');
      return res.status(404).json({ success: false, message: 'Cliente no encontrado' });
    }

    await emitBusinessIdAudit(
      {
        event: currentBusinessId ? 'admin_repair_completed' : 'initial_set',
        source: 'admin_business_id_repair',
        action: 'allowed',
        reason,
        severity: hasProtectedCustomerActivity(context) ? 'critical' : 'warn',
        currentBusinessId,
        incomingBusinessId: business_id,
        resolvedBusinessId: updated.business_id,
        customerId,
      },
      { req, client }
    );

    await client.query('COMMIT');
    return res.json({
      success: true,
      warning: 'ReparaciÃ³n administrativa aplicada. Revisa las activaciones y el cliente antes de continuar.',
      customer: updated,
    });
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('repairBusinessId error:', error);

    if (error && error.code === '23505') {
      return res.status(409).json({ success: false, message: 'Ese business_id ya estÃ¡ asignado a otro cliente' });
    }
    if (error && error.code === 'INVALID_NEW_BUSINESS_ID') {
      return res.status(400).json({ success: false, code: error.code, message: 'Para asignaciÃ³n inicial, business_id debe ser UUID v4' });
    }
    if (error && error.code === 'INVALID_EXISTING_BUSINESS_ID') {
      return res.status(400).json({ success: false, code: error.code, message: 'El business_id indicado no es compatible con un cliente legacy existente' });
    }

    return res.status(500).json({ success: false, message: 'Error interno del servidor' });
  } finally {
    client.release();
  }
}

/**
 * POST /api/admin/customers/:id/reset-token
 * Genera un token de reset para el cliente.
 */
async function resetToken(req, res) {
  try {
    const customerId = String(req.params.id || '').trim();
    if (!customerId) {
      return res.status(400).json({ success: false, message: 'id es requerido' });
    }

    if (!isUuid(customerId)) {
      return res.status(400).json({ success: false, message: 'id inválido (UUID requerido)' });
    }

    const customer = await customersModel.getCustomerById(customerId);
    if (!customer) {
      return res.status(404).json({ success: false, message: 'Cliente no encontrado' });
    }

    // Generar token único
    const token = crypto.randomBytes(32).toString('hex');
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 horas

    // Guardar token en la base de datos (en tabla password_reset_tokens o similar)
    try {
      await pool.query(
        `INSERT INTO password_reset_tokens (customer_id, token, expires_at, used)
         VALUES ($1, $2, $3, false)
         ON CONFLICT (customer_id) DO UPDATE SET token = $2, expires_at = $3, used = false, created_at = NOW()`,
        [customerId, token, expiresAt]
      );
    } catch (e) {
      // Si la tabla no existe, intentar con una tabla genérica o simplemente devolver el token
      if (e && e.code === '42P01') {
        // Tabla no existe, devolvemos el token sin persistir
        console.warn('resetToken: password_reset_tokens table does not exist, returning token without persistence');
      } else {
        throw e;
      }
    }

    return res.json({
      success: true,
      token,
      expires_at: expiresAt.toISOString(),
      message: 'Token de reset generado correctamente'
    });
  } catch (error) {
    console.error('resetToken error:', error);
    return res.status(500).json({ success: false, message: 'Error interno del servidor' });
  }
}

/**
 * GET /api/admin/customers/:id/payments
 * Obtiene los pagos de un cliente.
 */
async function getCustomerPayments(req, res) {
  try {
    const customerId = String(req.params.id || '').trim();
    if (!customerId) {
      return res.status(400).json({ success: false, message: 'id es requerido' });
    }

    if (!isUuid(customerId)) {
      return res.status(400).json({ success: false, message: 'id inválido (UUID requerido)' });
    }

    const customer = await customersModel.getCustomerById(customerId);
    if (!customer) {
      return res.status(404).json({ success: false, message: 'Cliente no encontrado' });
    }

    const payments = await customersModel.getCustomerPayments(customerId);

    return res.json({ success: true, payments });
  } catch (error) {
    console.error('getCustomerPayments error:', error);
    return res.status(500).json({ success: false, message: 'Error al obtener pagos del cliente' });
  }
}

module.exports = {
  createCustomer,
  listCustomers,
  deleteCustomer,
  setBusinessId,
  getCustomerByBusinessId,
  getCustomerById,
  updateCustomer,
  getCustomerLicenses,
  assignBusinessId,
  repairBusinessId,
  resetToken,
  getCustomerPayments
};
