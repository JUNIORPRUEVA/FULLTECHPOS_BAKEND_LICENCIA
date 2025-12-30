const licenseConfigService = require('../services/licenseConfigService');

/**
 * GET /api/admin/license-config
 * Obtiene la configuración actual de licencias
 */
async function getConfig(req, res) {
  try {
    const config = await licenseConfigService.getLicenseConfig();

    return res.json({
      ok: true,
      config: {
        demo_dias_validez: config.demo_dias_validez,
        demo_max_dispositivos: config.demo_max_dispositivos,
        full_dias_validez: config.full_dias_validez,
        full_max_dispositivos: config.full_max_dispositivos
      }
    });
  } catch (error) {
    console.error('getConfig error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

/**
 * PUT /api/admin/license-config
 * Actualiza la configuración de licencias
 * Valida que todos los valores sean enteros positivos
 */
async function updateConfig(req, res) {
  try {
    const {
      demo_dias_validez,
      demo_max_dispositivos,
      full_dias_validez,
      full_max_dispositivos
    } = req.body || {};

    // Validar demo_dias_validez
    if (demo_dias_validez !== undefined && demo_dias_validez !== null) {
      const val = Number(demo_dias_validez);
      if (!Number.isFinite(val) || val <= 0) {
        return res.status(400).json({
          ok: false,
          message: 'demo_dias_validez debe ser un número entero > 0'
        });
      }
    }

    // Validar demo_max_dispositivos
    if (demo_max_dispositivos !== undefined && demo_max_dispositivos !== null) {
      const val = Number(demo_max_dispositivos);
      if (!Number.isFinite(val) || val <= 0) {
        return res.status(400).json({
          ok: false,
          message: 'demo_max_dispositivos debe ser un número entero > 0'
        });
      }
    }

    // Validar full_dias_validez
    if (full_dias_validez !== undefined && full_dias_validez !== null) {
      const val = Number(full_dias_validez);
      if (!Number.isFinite(val) || val <= 0) {
        return res.status(400).json({
          ok: false,
          message: 'full_dias_validez debe ser un número entero > 0'
        });
      }
    }

    // Validar full_max_dispositivos
    if (full_max_dispositivos !== undefined && full_max_dispositivos !== null) {
      const val = Number(full_max_dispositivos);
      if (!Number.isFinite(val) || val <= 0) {
        return res.status(400).json({
          ok: false,
          message: 'full_max_dispositivos debe ser un número entero > 0'
        });
      }
    }

    // Construir payload con valores numéricos
    const payload = {};
    if (demo_dias_validez !== undefined && demo_dias_validez !== null) {
      payload.demo_dias_validez = Math.floor(Number(demo_dias_validez));
    }
    if (demo_max_dispositivos !== undefined && demo_max_dispositivos !== null) {
      payload.demo_max_dispositivos = Math.floor(Number(demo_max_dispositivos));
    }
    if (full_dias_validez !== undefined && full_dias_validez !== null) {
      payload.full_dias_validez = Math.floor(Number(full_dias_validez));
    }
    if (full_max_dispositivos !== undefined && full_max_dispositivos !== null) {
      payload.full_max_dispositivos = Math.floor(Number(full_max_dispositivos));
    }

    const updatedConfig = await licenseConfigService.updateLicenseConfig(payload);

    return res.json({
      ok: true,
      config: {
        demo_dias_validez: updatedConfig.demo_dias_validez,
        demo_max_dispositivos: updatedConfig.demo_max_dispositivos,
        full_dias_validez: updatedConfig.full_dias_validez,
        full_max_dispositivos: updatedConfig.full_max_dispositivos
      }
    });
  } catch (error) {
    console.error('updateConfig error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

module.exports = {
  getConfig,
  updateConfig
};
