const customersModel = require('../models/customersModel');

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

    if (!nombre_negocio || !String(nombre_negocio).trim()) {
      return res.status(400).json({ ok: false, message: 'nombre_negocio es requerido' });
    }

    if (!contacto_telefono || !String(contacto_telefono).trim()) {
      return res.status(400).json({ ok: false, message: 'contacto_telefono es requerido' });
    }

    const customer = await customersModel.createCustomer({
      nombre_negocio: String(nombre_negocio).trim(),
      contacto_nombre: contacto_nombre ? String(contacto_nombre).trim() : null,
      contacto_telefono: String(contacto_telefono).trim(),
      contacto_email: contacto_email ? String(contacto_email).trim() : null,
      rol_negocio: rol_negocio ? String(rol_negocio).trim() : null,
      business_id: business_id ? String(business_id).trim() : null
    });

    return res.status(201).json({ ok: true, customer });
  } catch (error) {
    console.error('createCustomer error:', error);
    // 23505 = unique_violation
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
      deletedLicensesCount: result.deletedLicensesCount
    });
  } catch (error) {
    console.error('deleteCustomer error:', error);
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

    const business_id = String(req.body?.business_id || '').trim();
    const force = Boolean(req.body?.force);

    if (!business_id) {
      return res.status(400).json({ ok: false, message: 'business_id es requerido' });
    }

    const current = await customersModel.getCustomerById(customerId);
    if (!current) {
      return res.status(404).json({ ok: false, message: 'Cliente no encontrado' });
    }

    if (current.business_id && String(current.business_id).trim() && !force) {
      if (String(current.business_id).trim() !== business_id) {
        return res.status(409).json({
          ok: false,
          code: 'BUSINESS_ID_ALREADY_SET',
          message: 'Este cliente ya tiene business_id asignado (usa force para reemplazar)'
        });
      }
    }

    const updated = await customersModel.setCustomerBusinessId({ customerId, business_id });
    if (!updated) {
      return res.status(404).json({ ok: false, message: 'Cliente no encontrado' });
    }

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

module.exports = {
  createCustomer,
  listCustomers,
  deleteCustomer,
  setBusinessId,
  getCustomerByBusinessId
};
