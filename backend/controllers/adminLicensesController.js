const licensesModel = require('../models/licensesModel');
const customersModel = require('../models/customersModel');
const licenseConfigService = require('../services/licenseConfigService');
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

async function createLicense(req, res) {
  try {
    const { customer_id, tipo, dias_validez, max_dispositivos, notas } = req.body || {};

    if (!customer_id || !String(customer_id).trim()) {
      return res.status(400).json({ ok: false, message: 'customer_id es requerido' });
    }

    if (!isUuid(customer_id)) {
      return res.status(400).json({ ok: false, message: 'customer_id inválido' });
    }

    const customer = await customersModel.getCustomerById(String(customer_id).trim());
    if (!customer) {
      return res.status(404).json({ ok: false, message: 'Cliente no encontrado' });
    }

    const tipoUpper = String(tipo || '').toUpperCase();
    if (tipoUpper !== 'DEMO' && tipoUpper !== 'FULL') {
      return res.status(400).json({ ok: false, message: "tipo debe ser 'DEMO' o 'FULL'" });
    }

    // Obtener configuración de licencias para usar como valores por defecto
    const config = await licenseConfigService.getLicenseConfig();

    // Determinar dias_validez: si no viene en el body, usar el del config
    let dias = Number(dias_validez);
    if (!Number.isFinite(dias) || dias <= 0) {
      // Si no viene o es inválido, usar el default del config según el tipo
      dias = tipoUpper === 'DEMO' ? config.demo_dias_validez : config.full_dias_validez;
    }

    // Determinar max_dispositivos: si no viene en el body, usar el del config
    let maxDisp = Number(max_dispositivos);
    if (!Number.isFinite(maxDisp) || maxDisp <= 0) {
      // Si no viene o es inválido, usar el default del config según el tipo
      maxDisp = tipoUpper === 'DEMO' ? config.demo_max_dispositivos : config.full_max_dispositivos;
    }

    // Validación final de los valores (ya sean del body o del config)
    if (!Number.isFinite(dias) || dias <= 0) {
      return res.status(400).json({ ok: false, message: 'dias_validez debe ser un número entero > 0' });
    }
    if (!Number.isFinite(maxDisp) || maxDisp <= 0) {
      return res.status(400).json({ ok: false, message: 'max_dispositivos debe ser un número entero > 0' });
    }

    // Generar license_key único con reintentos
    for (let i = 0; i < 6; i++) {
      const key = generateLicenseKey(tipoUpper);
      try {
        const license = await licensesModel.createLicenseWithKey({
          customer_id: customer.id,
          license_key: key,
          tipo: tipoUpper,
          dias_validez: Math.floor(dias),
          max_dispositivos: Math.floor(maxDisp),
          notas: notas ? String(notas) : null
        });
        return res.status(201).json({ ok: true, license });
      } catch (e) {
        // 23505 = unique_violation
        if (e && e.code === '23505') continue;
        console.error('createLicense db error:', e);
        return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
      }
    }

    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  } catch (error) {
    console.error('createLicense error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function listLicenses(req, res) {
  try {
    const { page, limit, offset } = parsePagination(req);
    const customer_id = req.query.customer_id || undefined;
    const tipo = req.query.tipo ? String(req.query.tipo).toUpperCase() : undefined;
    const estado = req.query.estado ? String(req.query.estado).toUpperCase() : undefined;

    const { total, licenses } = await licensesModel.listLicenses({
      limit,
      offset,
      customer_id,
      tipo,
      estado
    });

    return res.json({ ok: true, page, limit, total, licenses });
  } catch (error) {
    console.error('listLicenses error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function getLicenseDetail(req, res) {
  try {
    const licenseId = req.params.id;
    const license = await licensesModel.getLicenseById(licenseId);
    if (!license) {
      return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
    }
    return res.json({ ok: true, license });
  } catch (error) {
    console.error('getLicenseDetail error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function bloquearLicense(req, res) {
  try {
    const licenseId = req.params.id;
    const updated = await licensesModel.updateLicenseStatus(licenseId, 'BLOQUEADA');
    if (!updated) {
      return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
    }
    return res.json({ ok: true, license: updated });
  } catch (error) {
    console.error('bloquearLicense error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function activarManual(req, res) {
  try {
    const licenseId = req.params.id;
    const updated = await licensesModel.activateLicenseManually(licenseId);
    if (!updated) {
      return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
    }
    return res.json({ ok: true, license: updated });
  } catch (error) {
    console.error('activarManual error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function updateLicense(req, res) {
  try {
    const licenseId = req.params.id;
    const body = req.body || {};

    const patch = {};

    if (body.tipo !== undefined) {
      const tipoUpper = String(body.tipo || '').toUpperCase();
      if (tipoUpper !== 'DEMO' && tipoUpper !== 'FULL') {
        return res.status(400).json({ ok: false, message: "tipo debe ser 'DEMO' o 'FULL'" });
      }
      patch.tipo = tipoUpper;
    }

    if (body.dias_validez !== undefined) {
      const dias = Number(body.dias_validez);
      if (!Number.isFinite(dias) || dias <= 0) {
        return res.status(400).json({ ok: false, message: 'dias_validez debe ser un número entero > 0' });
      }
      patch.dias_validez = Math.floor(dias);
    }

    if (body.max_dispositivos !== undefined) {
      const maxDisp = Number(body.max_dispositivos);
      if (!Number.isFinite(maxDisp) || maxDisp <= 0) {
        return res.status(400).json({ ok: false, message: 'max_dispositivos debe ser un número entero > 0' });
      }
      patch.max_dispositivos = Math.floor(maxDisp);
    }

    if (body.estado !== undefined) {
      const estadoUpper = String(body.estado || '').toUpperCase();
      const allowed = new Set(['PENDIENTE', 'ACTIVA', 'VENCIDA', 'BLOQUEADA']);
      if (!allowed.has(estadoUpper)) {
        return res.status(400).json({ ok: false, message: "estado inválido. Use: PENDIENTE|ACTIVA|VENCIDA|BLOQUEADA" });
      }
      patch.estado = estadoUpper;
    }

    if (body.notas !== undefined) {
      if (body.notas === null || String(body.notas).trim() === '') {
        patch.notas = null;
      } else {
        patch.notas = String(body.notas);
      }
    }

    if (Object.keys(patch).length === 0) {
      return res.status(400).json({ ok: false, message: 'No hay campos para actualizar' });
    }

    const updated = await licensesModel.updateLicense(licenseId, patch);
    if (!updated) {
      return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
    }

    return res.json({ ok: true, license: updated });
  } catch (error) {
    console.error('updateLicense error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

module.exports = {
  createLicense,
  listLicenses,
  getLicenseDetail,
  bloquearLicense,
  activarManual,
  updateLicense
};
