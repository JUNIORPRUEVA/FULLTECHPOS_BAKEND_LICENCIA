const licensesModel = require('../models/licensesModel');
const customersModel = require('../models/customersModel');
const licenseConfigService = require('../services/licenseConfigService');
const { generateLicenseKey } = require('../utils/licenseKey');
const projectsModel = require('../models/projectsModel');
const licenseFile = require('../utils/licenseFile');
const licenseChangeBus = require('../services/licenseChangeBus');

function logSqlError(scope, error) {
  console.error(`[${scope}] SQL ERROR:`, {
    message: error?.message,
    code: error?.code,
    detail: error?.detail,
    stack: error?.stack
  });
}

function handleLicenseError(res, error, fallbackScope, fallbackMessage = 'Error interno del servidor') {
  if (error instanceof licensesModel.LicenseStateError) {
    return res.status(error.statusCode || 400).json({
      ok: false,
      success: false,
      message: error.message
    });
  }

  logSqlError(fallbackScope, error);
  return res.status(500).json({
    ok: false,
    success: false,
    message: fallbackMessage,
    code: error?.code || null
  });
}

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
    // ==========================================
    // LOG: Raw request body completo
    // ==========================================
    console.log('[CREATE_LICENSE] BODY:', JSON.stringify(req.body, null, 2));
    console.log('[CREATE_LICENSE] USER:', req.user || req.admin || null);

    // ==========================================
    // Normalización flexible de campos
    // ==========================================
    const customer_id = req.body.customer_id || req.body.clientId || req.body.customerId;
    const project_id = req.body.project_id || req.body.projectId;
    const project_code = req.body.project_code || req.body.projectCode;
    const tipo = req.body.tipo || req.body.type;
    const license_type = req.body.license_type || req.body.licenseType || 'SUSCRIPCION';
    const dias_validez = Number(req.body.dias_validez || req.body.validityDays || req.body.days || 0);
    const max_dispositivos = Number(req.body.max_dispositivos || req.body.maxDevices || req.body.deviceLimit || 1);
    const notas = req.body.notas || req.body.notes || null;
    const auto_activate = req.body.auto_activate ?? req.body.autoActivate ?? req.body.activar_automaticamente ?? false;
    const estado = req.body.estado || req.body.status || null;

    // ==========================================
    // LOG: Valores normalizados
    // ==========================================
    console.log('[CREATE_LICENSE] normalized:', JSON.stringify({
      customer_id,
      project_id,
      project_code,
      tipo,
      license_type,
      dias_validez,
      max_dispositivos,
      notas: notas ? '(presente)' : null,
      auto_activate,
      estado
    }));

    // ==========================================
    // Validación: project_id o project_code requerido
    // ==========================================
    if (!project_id && !project_code) {
      return res.status(400).json({
        ok: false,
        message: 'project_id o project_code es requerido. Selecciona un proyecto.'
      });
    }

    let project = null;
    if (project_id) {
      if (!isUuid(project_id)) {
        return res.status(400).json({ ok: false, message: 'project_id inválido' });
      }
      project = await projectsModel.getProjectById(String(project_id).trim());
    } else if (project_code) {
      project = await projectsModel.getProjectByCode(String(project_code));
    }

    if (!project) {
      return res.status(400).json({
        ok: false,
        message: 'El proyecto seleccionado no existe. Verifica que el proyecto esté registrado.'
      });
    }

    // LOG: Proyecto seleccionado
    console.log('[createLicense] Proyecto seleccionado:', JSON.stringify({
      id: project.id,
      code: project.code,
      name: project.name
    }));

    // ==========================================
    // Validación: customer_id requerido
    // ==========================================
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

    // LOG: Cliente seleccionado
    console.log('[createLicense] Cliente seleccionado:', JSON.stringify({
      id: customer.id,
      nombre_negocio: customer.nombre_negocio,
      business_id: customer.business_id
    }));

    // ==========================================
    // Validación: tipo
    // ==========================================
    const tipoUpper = String(tipo || '').toUpperCase();
    if (tipoUpper !== 'DEMO' && tipoUpper !== 'FULL') {
      return res.status(400).json({ ok: false, message: "tipo debe ser 'DEMO' o 'FULL'" });
    }

    // ==========================================
    // Validación: license_type
    // ==========================================
    const licenseType = String(license_type || 'SUSCRIPCION').trim().toUpperCase();
    if (!['PERMANENTE', 'SUSCRIPCION'].includes(licenseType)) {
      return res.status(400).json({ ok: false, message: "license_type debe ser 'PERMANENTE' o 'SUSCRIPCION'" });
    }

    // ==========================================
    // Obtener configuración de licencias
    // ==========================================
    const config = await licenseConfigService.getLicenseConfig();

    // Determinar dias_validez
    let dias = Number(dias_validez);
    if (!Number.isFinite(dias) || dias <= 0) {
      dias = tipoUpper === 'DEMO' ? config.demo_dias_validez : config.full_dias_validez;
    }

    // Determinar max_dispositivos
    let maxDisp = Number(max_dispositivos);
    if (!Number.isFinite(maxDisp) || maxDisp <= 0) {
      maxDisp = tipoUpper === 'DEMO' ? config.demo_max_dispositivos : config.full_max_dispositivos;
    }

    // FULLPOS: siempre 1 dispositivo
    maxDisp = 1;

    // Validación final
    if (!Number.isFinite(dias) || dias <= 0) {
      return res.status(400).json({ ok: false, message: 'dias_validez debe ser un número entero > 0' });
    }
    if (!Number.isFinite(maxDisp) || maxDisp <= 0) {
      return res.status(400).json({ ok: false, message: 'max_dispositivos debe ser un número entero > 0' });
    }

    // ==========================================
    // Generar license_key único con reintentos
    // ==========================================
    for (let i = 0; i < 6; i++) {
      const key = generateLicenseKey(tipoUpper);
      try {
        const license = await licensesModel.createLicenseWithKey({
          project_id: project.id,
          customer_id: customer.id,
          license_key: key,
          tipo: tipoUpper,
          license_type: licenseType,
          dias_validez: Math.floor(dias),
          max_dispositivos: Math.floor(maxDisp),
          notas: notas ? String(notas) : null
        });

        // LOG: Licencia generada
        console.log('[createLicense] Licencia generada:', JSON.stringify({
          id: license.id,
          license_key: license.license_key,
          project_id: license.project_id,
          customer_id: license.customer_id,
          tipo: license.tipo,
          dias_validez: license.dias_validez,
          estado: license.estado
        }));

        const autoActivate =
          auto_activate === true ||
          String(auto_activate || '').trim() === '1' ||
          String(auto_activate || '').trim().toLowerCase() === 'true' ||
          String(estado || '').trim().toUpperCase() === 'ACTIVA';

        if (!autoActivate) {
          return res.status(201).json({ ok: true, license });
        }

        const activated = await licensesModel.activateLicenseManually(license.id);

        // LOG: Activación
        console.log('[createLicense] Licencia activada automáticamente:', JSON.stringify({
          id: activated.id,
          estado: activated.estado,
          fecha_inicio: activated.fecha_inicio,
          fecha_fin: activated.fecha_fin
        }));

        try {
          const biz = String(customer?.business_id || '').trim();
          if (biz) {
            licenseChangeBus.emitBusinessLicenseChanged(biz, {
              reason: 'admin_create_license_auto_activated',
              licenseId: String(license.id),
            });
          }
        } catch (_) {}

        return res.status(201).json({ ok: true, license: activated, auto_activated: true });
      } catch (e) {
        // 23505 = unique_violation
        if (e && e.code === '23505') continue;
        if (e instanceof licensesModel.LicenseStateError) {
          return res.status(e.statusCode || 400).json({
            ok: false,
            message: e.message
          });
        }
        logSqlError('CREATE_LICENSE', e);
        return res.status(500).json({
          ok: false,
          message: 'No se pudo crear o activar la licencia por un error interno del servidor',
          error: e.message,
          code: e.code || null,
          detail: e.detail || null,
          constraint: e.constraint || null
        });
      }
    }

    return res.status(500).json({ ok: false, message: 'Error interno del servidor: no se pudo generar una license_key única' });
  } catch (error) {
    if (error instanceof licensesModel.LicenseStateError) {
      return res.status(error.statusCode || 400).json({ ok: false, message: error.message });
    }
    logSqlError('CREATE_LICENSE', error);
    return res.status(500).json({
      ok: false,
      message: 'No se pudo crear la licencia por un error interno del servidor',
      error: error.message,
      code: error.code || null,
      detail: error.detail || null,
      constraint: error.constraint || null
    });
  }
}

async function listLicenses(req, res) {
  try {
    const { page, limit, offset } = parsePagination(req);
    const project_id = req.query.project_id || undefined;
    const project_code = req.query.project_code || undefined;
    const customer_id = req.query.customer_id || undefined;
    const tipo = req.query.tipo ? String(req.query.tipo).toUpperCase() : undefined;
    const estado = req.query.estado ? String(req.query.estado).toUpperCase() : undefined;

    let resolvedProjectId = project_id;
    if (!resolvedProjectId && project_code) {
      const project = await projectsModel.getProjectByCode(String(project_code));
      if (!project) {
        return res.status(404).json({ ok: false, message: 'Proyecto no encontrado' });
      }
      resolvedProjectId = project.id;
    }

    if (resolvedProjectId && !isUuid(resolvedProjectId)) {
      return res.status(400).json({ ok: false, message: 'project_id inválido' });
    }

    const { total, licenses } = await licensesModel.listLicenses({
      limit,
      offset,
      project_id: resolvedProjectId,
      customer_id,
      tipo,
      estado,
      // Por defecto: no mostrar licencias eliminadas (soft-delete).
      // Si el usuario filtra explícitamente por estado=ELIMINADA, sí deben aparecer.
      excludeEstados: estado ? undefined : ['ELIMINADA']
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
    const motivoRaw = (req.body || {}).motivo ?? (req.body || {}).notas;
    const motivo = String(motivoRaw || '').trim();

    const current = await licensesModel.getLicenseById(licenseId);
    if (!current) {
      return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
    }

    const finalNotas = motivo || String(current.notas || '').trim();
    if (!finalNotas) {
      return res.status(400).json({
        ok: false,
        message: 'Para bloquear, debes indicar el motivo (campo notas/motivo)'
      });
    }

    const updated = await licensesModel.updateLicense(licenseId, {
      estado: 'BLOQUEADA',
      notas: finalNotas
    });

    // Notify connected clients (SSE) to refresh license status.
    try {
      const biz = String(current?.business_id || '').trim();
      if (biz) {
        licenseChangeBus.emitBusinessLicenseChanged(biz, {
          reason: 'admin_block_license',
          licenseId: String(licenseId),
        });
      }
    } catch (_) {}

    return res.json({ ok: true, license: updated });
  } catch (error) {
    console.error('bloquearLicense error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function activarManual(req, res) {
  try {
    const licenseId = req.params.id;
    const current = await licensesModel.getLicenseById(licenseId);
    const updated = await licensesModel.activateLicenseManually(licenseId);
    if (!updated) {
      return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
    }

    try {
      const biz = String(current?.business_id || '').trim();
      if (biz) {
        licenseChangeBus.emitBusinessLicenseChanged(biz, {
          reason: 'admin_activate_manual',
          licenseId: String(licenseId),
        });
      }
    } catch (_) {}

    return res.json({ ok: true, license: updated });
  } catch (error) {
    return handleLicenseError(res, error, 'activateLicense', 'No se pudo activar la licencia por un error interno del servidor');
  }
}

/**
 * POST /api/admin/licenses/:id/activate
 * Activate a license with proper validation.
 * - 404 if license not found
 * - 409 if already active
 * - 400 if blocked
 * - 400 if expired
 * - 200 on success
 */
async function activateLicense(req, res) {
  try {
    const licenseId = req.params.id;
    const current = await licensesModel.getLicenseById(licenseId);

    if (!current) {
      return res.status(404).json({
        success: false,
        message: 'Licencia no encontrada',
      });
    }

    const estado = licensesModel.normalizeLicenseStatus(current.estado, current.estado);

    if (estado === 'ACTIVA') {
      return res.status(409).json({
        success: false,
        message: 'La licencia ya está activa',
      });
    }

    if (estado === 'BLOQUEADA') {
      return res.status(400).json({
        success: false,
        message: 'No se puede activar una licencia bloqueada. Desbloquéela primero.',
      });
    }

    if (estado === 'VENCIDA') {
      return res.status(400).json({
        success: false,
        message: 'No se puede activar una licencia vencida. Renueve la licencia primero.',
      });
    }

    const updated = await licensesModel.activateLicenseManually(licenseId);
    if (!updated) {
      return res.status(500).json({
        success: false,
        message: 'Error al activar la licencia',
      });
    }

    try {
      const biz = String(current?.business_id || '').trim();
      if (biz) {
        licenseChangeBus.emitBusinessLicenseChanged(biz, {
          reason: 'admin_activate_license',
          licenseId: String(licenseId),
        });
      }
    } catch (_) {}

    return res.json({
      success: true,
      message: 'Licencia activada correctamente',
      license: {
        id: updated.id,
        license_key: updated.license_key,
        status: 'ACTIVA',
        estado: 'ACTIVA',
        activated_at: updated.fecha_inicio,
        expires_at: updated.fecha_fin,
      },
    });
  } catch (error) {
    return handleLicenseError(
      res,
      error,
      'activateLicense',
      'No se pudo activar la licencia por un error interno del servidor'
    );
  }
}

async function desbloquearLicense(req, res) {
  try {
    const licenseId = req.params.id;
    const current = await licensesModel.getLicenseById(licenseId);
    if (!current) {
      return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
    }

    // Desbloquear debe dejar la licencia utilizable.
    // activateLicenseManually se encarga de (re)armar fechas si están ausentes o vencidas.
    const updated = await licensesModel.activateLicenseManually(licenseId);
    if (!updated) {
      return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
    }

    try {
      const biz = String(current?.business_id || '').trim();
      if (biz) {
        licenseChangeBus.emitBusinessLicenseChanged(biz, {
          reason: 'admin_unblock_license',
          licenseId: String(licenseId),
        });
      }
    } catch (_) {}

    return res.json({ ok: true, license: updated });
  } catch (error) {
    console.error('desbloquearLicense error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function deleteLicense(req, res) {
  try {
    const licenseId = String(req.params.id || '').trim();
    if (!isUuid(licenseId)) {
      return res.status(400).json({ ok: false, message: 'id inválido' });
    }

    const current = await licensesModel.getLicenseById(licenseId);
    const deleted = await licensesModel.deleteLicense(licenseId);
    if (!deleted) {
      return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
    }

    try {
      const biz = String(current?.business_id || '').trim();
      if (biz) {
        licenseChangeBus.emitBusinessLicenseChanged(biz, {
          reason: 'admin_delete_license',
          licenseId: String(licenseId),
        });
      }
    } catch (_) {}

    return res.json({ ok: true, deleted });
  } catch (error) {
    console.error('deleteLicense error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function updateLicense(req, res) {
  try {
    const licenseId = req.params.id;
    const body = req.body || {};
    const current = await licensesModel.getLicenseById(licenseId);

    const patch = {};

    if (body.tipo !== undefined) {
      const tipoUpper = String(body.tipo || '').toUpperCase();
      if (tipoUpper !== 'DEMO' && tipoUpper !== 'FULL') {
        return res.status(400).json({ ok: false, message: "tipo debe ser 'DEMO' o 'FULL'" });
      }
      patch.tipo = tipoUpper;
    }

    if (body.license_type !== undefined) {
      const licenseType = String(body.license_type || '').trim().toUpperCase();
      if (!['PERMANENTE', 'SUSCRIPCION'].includes(licenseType)) {
        return res.status(400).json({ ok: false, message: "license_type debe ser 'PERMANENTE' o 'SUSCRIPCION'" });
      }
      patch.license_type = licenseType;
    }

    if (body.customer_id !== undefined) {
      const customerId = String(body.customer_id || '').trim();
      if (!isUuid(customerId)) {
        return res.status(400).json({ ok: false, message: 'customer_id inválido' });
      }
      const customer = await customersModel.getCustomerById(customerId);
      if (!customer) {
        return res.status(404).json({ ok: false, message: 'Cliente no encontrado' });
      }
      patch.customer_id = customer.id;
    }

    if (body.project_id !== undefined) {
      const projectId = String(body.project_id || '').trim();
      if (!isUuid(projectId)) {
        return res.status(400).json({ ok: false, message: 'project_id inválido' });
      }
      const project = await projectsModel.getProjectById(projectId);
      if (!project) {
        return res.status(404).json({ ok: false, message: 'Proyecto no encontrado' });
      }
      patch.project_id = project.id;
    } else if (body.project_code !== undefined) {
      const projectCode = String(body.project_code || '').trim();
      if (!projectCode) {
        return res.status(400).json({ ok: false, message: 'project_code inválido' });
      }
      const project = await projectsModel.getProjectByCode(projectCode);
      if (!project) {
        return res.status(404).json({ ok: false, message: 'Proyecto no encontrado' });
      }
      patch.project_id = project.id;
    }

    if (body.dias_validez !== undefined) {
      const dias = Number(body.dias_validez);
      if (!Number.isFinite(dias) || dias <= 0) {
        return res.status(400).json({ ok: false, message: 'dias_validez debe ser un número entero > 0' });
      }
      patch.dias_validez = Math.floor(dias);
    }

    if (body.max_dispositivos !== undefined) {
      // FULLPOS: siempre 1 dispositivo
      patch.max_dispositivos = 1;
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

    try {
      const biz = String(current?.business_id || updated?.business_id || '').trim();
      if (biz) {
        licenseChangeBus.emitBusinessLicenseChanged(biz, {
          reason: 'admin_update_license',
          licenseId: String(licenseId),
        });
      }
    } catch (_) {}

    return res.json({ ok: true, license: updated });
  } catch (error) {
    return handleLicenseError(res, error, 'updateLicense', 'No se pudo actualizar la licencia por un error interno del servidor');
  }
}

async function extenderDias(req, res) {
  try {
    const licenseId = req.params.id;
    const current = await licensesModel.getLicenseById(licenseId);
    const dias = Number((req.body || {}).dias);
    if (!Number.isFinite(dias) || dias <= 0) {
      return res.status(400).json({ ok: false, message: 'dias debe ser un número entero > 0' });
    }

    const updated = await licensesModel.extendLicenseDays(licenseId, Math.floor(dias));
    if (!updated) {
      return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
    }

    try {
      const biz = String(current?.business_id || updated?.business_id || '').trim();
      if (biz) {
        licenseChangeBus.emitBusinessLicenseChanged(biz, {
          reason: 'admin_extend_license_days',
          licenseId: String(licenseId),
        });
      }
    } catch (_) {}

    return res.json({ ok: true, license: updated });
  } catch (error) {
    console.error('extenderDias error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function bloquearLicenseByKey(req, res) {
  try {
    const licenseKey = String(req.body?.license_key || '').trim();
    if (!licenseKey) {
      return res.status(400).json({ ok: false, message: 'license_key es requerido' });
    }

    const motivoRaw = req.body?.motivo ?? req.body?.notas;
    const motivo = String(motivoRaw || '').trim();

    const license = await licensesModel.findLicenseByKey(licenseKey);
    if (!license) {
      return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
    }

    const finalNotas = motivo || String(license.notas || '').trim();
    if (!finalNotas) {
      return res.status(400).json({
        ok: false,
        message: 'Para bloquear, debes indicar el motivo (campo notas/motivo)'
      });
    }

    const updated = await licensesModel.updateLicense(license.id, {
      estado: 'BLOQUEADA',
      notas: finalNotas
    });

    // Notify connected clients (SSE) to refresh license status.
    try {
      const detail = await licensesModel.getLicenseById(String(license.id));
      const biz = String(detail?.business_id || '').trim();
      if (biz) {
        licenseChangeBus.emitBusinessLicenseChanged(biz, {
          reason: 'admin_block_license_by_key',
          licenseId: String(license.id),
        });
      }
    } catch (_) {}

    return res.json({ ok: true, license: updated });
  } catch (error) {
    console.error('bloquearLicenseByKey error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function vencerLicenseByKey(req, res) {
  try {
    const licenseKey = String(req.body?.license_key || '').trim();
    if (!licenseKey) {
      return res.status(400).json({ ok: false, message: 'license_key es requerido' });
    }

    const license = await licensesModel.findLicenseByKey(licenseKey);
    if (!license) {
      return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
    }

    const updated = await licensesModel.updateLicense(license.id, { estado: 'VENCIDA' });

    try {
      const detail = await licensesModel.getLicenseById(String(license.id));
      const biz = String(detail?.business_id || '').trim();
      if (biz) {
        licenseChangeBus.emitBusinessLicenseChanged(biz, {
          reason: 'admin_expire_license_by_key',
          licenseId: String(license.id),
        });
      }
    } catch (_) {}

    return res.json({ ok: true, license: updated });
  } catch (error) {
    console.error('vencerLicenseByKey error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function activarManualByKey(req, res) {
  try {
    const licenseKey = String(req.body?.license_key || '').trim();
    if (!licenseKey) {
      return res.status(400).json({ ok: false, message: 'license_key es requerido' });
    }

    const license = await licensesModel.findLicenseByKey(licenseKey);
    if (!license) {
      return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
    }

    const updated = await licensesModel.activateLicenseManually(license.id);

    // Notify connected clients (SSE) to refresh license status.
    try {
      const detail = await licensesModel.getLicenseById(String(license.id));
      const biz = String(detail?.business_id || '').trim();
      if (biz) {
        licenseChangeBus.emitBusinessLicenseChanged(biz, {
          reason: 'admin_activate_manual_by_key',
          licenseId: String(license.id),
        });
      }
    } catch (_) {}

    return res.json({ ok: true, license: updated });
  } catch (error) {
    return handleLicenseError(res, error, 'activateLicense', 'No se pudo activar la licencia por un error interno del servidor');
  }
}

module.exports = {
  createLicense,
  listLicenses,
  getLicenseDetail,
  bloquearLicense,
  bloquearLicenseByKey,
  activarManual,
  activarManualByKey,
  activateLicense,
  desbloquearLicense,
  deleteLicense,
  updateLicense,
  extenderDias,
  vencerLicenseByKey,
  exportLicenseFile
};

async function exportLicenseFile(req, res) {
  try {
    const licenseId = req.params.id;
    const deviceId = (req.query.device_id ?? (req.body || {}).device_id ?? null);
    const ensureActiveRaw = (req.query.ensure_active ?? (req.body || {}).ensure_active ?? 'false');
    const ensureActive = String(ensureActiveRaw).toLowerCase() === 'true';

    let license = await licensesModel.getLicenseById(licenseId);
    if (!license) {
      return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
    }

    if (ensureActive && (!license.fecha_inicio || !license.fecha_fin)) {
      const updated = await licensesModel.activateLicenseManually(licenseId);
      if (!updated) {
        return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
      }
      license = await licensesModel.getLicenseById(licenseId);
    }

    const project = license.project_code
      ? await projectsModel.getProjectByCode(license.project_code)
      : await projectsModel.getProjectById(license.project_id);

    if (!project) {
      return res.status(500).json({ ok: false, message: 'Proyecto de la licencia no encontrado' });
    }

    const customer = license.customer_id
      ? {
          id: license.customer_id,
          nombre_negocio: license.nombre_negocio,
          business_id: license.business_id
        }
      : null;

    let fileObj;
    try {
      fileObj = licenseFile.createLicenseFileFromDbRows({
        license,
        project,
        customer,
        device_id: deviceId ? String(deviceId).trim() : null
      });
    } catch (e) {
      if (e && e.code === 'MISSING_ENV') {
        return res.status(501).json({
          ok: false,
          message: 'Exportación offline no configurada. Configure LICENSE_SIGN_PRIVATE_KEY y LICENSE_SIGN_PUBLIC_KEY (o use LICENSE_SIGN_PRIVATE_KEY_FILE y LICENSE_SIGN_PUBLIC_KEY_FILE).'
        });
      }
      if (e && e.code === 'LICENSE_NOT_STARTED') {
        return res.status(400).json({ ok: false, message: e.message });
      }
      console.error('exportLicenseFile error:', e);
      return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
    }

    const download = String(req.query.download || '').toLowerCase() === '1' || String(req.query.download || '').toLowerCase() === 'true';
    if (download) {
      const fileName = `license_${project.code}_${license.license_key}${deviceId ? '_' + String(deviceId).trim() : ''}.lic.json`;
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
      res.setHeader('Content-Disposition', `attachment; filename="${fileName}"`);
      return res.status(200).send(JSON.stringify(fileObj, null, 2));
    }

    return res.json({ ok: true, license_file: fileObj });
  } catch (error) {
    console.error('exportLicenseFile outer error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}
