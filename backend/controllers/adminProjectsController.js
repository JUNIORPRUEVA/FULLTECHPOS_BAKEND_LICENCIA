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

module.exports = {
  listProjects,
  createProject
};
