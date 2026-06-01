const projectsModel = require('../models/projectsModel');

function isUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value || '').trim());
}

async function listProjects(req, res) {
  try {
    const projects = await projectsModel.listProjects();
    return res.json({ ok: true, projects });
  } catch (error) {
    console.error('listProjects error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function createProject(req, res) {
  try {
    const { code, name, description } = req.body || {};

    const normalizedCode = projectsModel.normalizeCode(code);
    const n = String(name || '').trim();

    if (!normalizedCode) {
      return res.status(400).json({ ok: false, message: 'code es requerido' });
    }
    if (!n) {
      return res.status(400).json({ ok: false, message: 'name es requerido' });
    }

    // Guard: avoid accidentally passing UUID as code from clients
    if (isUuid(normalizedCode)) {
      return res.status(400).json({ ok: false, message: 'code inválido' });
    }

    try {
      const project = await projectsModel.createProject({ code: normalizedCode, name: n, description });
      return res.status(201).json({ ok: true, project });
    } catch (e) {
      // 23505 = unique_violation
      if (e && e.code === '23505') {
        return res.status(409).json({ ok: false, message: 'Ya existe un proyecto con ese code' });
      }
      console.error('createProject db error:', e);
      return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
    }
  } catch (error) {
    console.error('createProject error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

/**
 * PATCH /api/admin/projects/:id/billing-settings
 * Actualiza la configuración comercial/de facturación de un proyecto.
 */
async function updateBillingSettings(req, res) {
  try {
    const projectId = req.params.id;
    if (!isUuid(projectId)) {
      return res.status(400).json({ ok: false, message: 'project_id inválido' });
    }

    const project = await projectsModel.getProjectById(projectId);
    if (!project) {
      return res.status(404).json({ ok: false, message: 'Proyecto no encontrado' });
    }

    const body = req.body || {};

    // Validaciones
    if (body.monthly_price !== undefined) {
      const price = Number(body.monthly_price);
      if (!Number.isFinite(price) || price < 0) {
        return res.status(400).json({ ok: false, message: 'monthly_price no puede ser negativo' });
      }
      if (body.is_paid_project === true && price <= 0) {
        return res.status(400).json({ ok: false, message: 'Si el proyecto requiere pago, monthly_price debe ser mayor que 0' });
      }
    }

    if (body.min_purchase_months !== undefined) {
      const min = Number(body.min_purchase_months);
      if (!Number.isFinite(min) || min < 1) {
        return res.status(400).json({ ok: false, message: 'min_purchase_months debe ser al menos 1' });
      }
    }

    if (body.demo_days !== undefined) {
      const days = Number(body.demo_days);
      if (!Number.isFinite(days) || days < 0) {
        return res.status(400).json({ ok: false, message: 'demo_days no puede ser negativo' });
      }
    }

    if (body.currency !== undefined) {
      const curr = String(body.currency || '').trim().toUpperCase();
      if (!curr || curr.length > 10) {
        return res.status(400).json({ ok: false, message: 'currency inválido' });
      }
    }

    const settings = {
      monthly_price: body.monthly_price !== undefined ? Number(body.monthly_price) : undefined,
      currency: body.currency !== undefined ? String(body.currency).trim().toUpperCase() : undefined,
      demo_days: body.demo_days !== undefined ? Math.floor(Number(body.demo_days)) : undefined,
      min_purchase_months: body.min_purchase_months !== undefined ? Math.floor(Number(body.min_purchase_months)) : undefined,
      is_paid_project: body.is_paid_project !== undefined ? Boolean(body.is_paid_project) : undefined,
      allow_demo: body.allow_demo !== undefined ? Boolean(body.allow_demo) : undefined,
      is_active: body.is_active !== undefined ? Boolean(body.is_active) : undefined
    };

    const updated = await projectsModel.updateProjectBillingSettings(projectId, settings);
    if (!updated) {
      return res.status(500).json({ ok: false, message: 'Error al actualizar configuración del proyecto' });
    }

    return res.json({ success: true, project: updated });
  } catch (error) {
    console.error('updateBillingSettings error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

/**
 * GET /api/admin/projects/:id
 * Obtiene detalle de un proyecto por ID.
 */
async function getProjectById(req, res) {
  try {
    const projectId = req.params.id;
    if (!isUuid(projectId)) {
      return res.status(400).json({ ok: false, message: 'project_id inválido' });
    }
    const project = await projectsModel.getProjectById(projectId);
    if (!project) {
      return res.status(404).json({ ok: false, message: 'Proyecto no encontrado' });
    }
    return res.json({ ok: true, project });
  } catch (error) {
    console.error('getProjectById error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

module.exports = {
  listProjects,
  createProject,
  updateBillingSettings,
  getProjectById
};
