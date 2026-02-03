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
    const { nombre_negocio, contacto_nombre, contacto_telefono, contacto_email } = req.body || {};

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
      contacto_email: contacto_email ? String(contacto_email).trim() : null
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

module.exports = {
  createCustomer,
  listCustomers
};
