/**
 * Admin License Configuration Script
 * Maneja la interfaz de configuración de licencias en el panel admin
 */

const LICENSE_CONFIG_API = '/api/admin/license-config';
let currentConfig = null;

/**
 * Cargar la configuración actual de licencias
 */
async function loadLicenseConfig() {
  try {
    const response = await fetch(LICENSE_CONFIG_API, {
      method: 'GET',
      cache: 'no-store',
      headers: {
        'x-session-id': sessionId
      }
    });

    const data = await response.json();

    if (data.ok && data.config) {
      currentConfig = data.config;
      return currentConfig;
    }

    console.error('Error loading license config:', data.message);
    return null;
  } catch (error) {
    console.error('loadLicenseConfig error:', error);
    return null;
  }
}

/**
 * Obtener los valores por defecto para un tipo de licencia
 * @param {string} tipo - Tipo de licencia ('DEMO' o 'FULL')
 * @returns {object} Objeto con dias_validez y max_dispositivos
 */
function getDefaultsForLicenseType(tipo) {
  if (!currentConfig) {
    // Fallback si la configuración no se ha cargado
    return tipo === 'DEMO'
      ? { dias_validez: 15, max_dispositivos: 1 }
      : { dias_validez: 365, max_dispositivos: 2 };
  }

  if (tipo === 'DEMO') {
    return {
      dias_validez: currentConfig.demo_dias_validez,
      max_dispositivos: currentConfig.demo_max_dispositivos
    };
  } else if (tipo === 'FULL') {
    return {
      dias_validez: currentConfig.full_dias_validez,
      max_dispositivos: currentConfig.full_max_dispositivos
    };
  }

  return null;
}

/**
 * Inicializar el selector de tipo de licencia con auto-relleno
 * Esta función debe llamarse cuando se está creando una nueva licencia
 */
function initializeLicenseTypeSelector() {
  const tipoSelect = document.getElementById('licenseType');
  const diasInput = document.getElementById('diasValidez');
  const dispositivosInput = document.getElementById('maxDispositivos');

  if (!tipoSelect || !diasInput || !dispositivosInput) {
    console.warn('License type selector elements not found');
    return;
  }

  // Evento cuando cambia el tipo de licencia
  tipoSelect.addEventListener('change', (e) => {
    const tipo = e.target.value.toUpperCase();
    if (tipo === 'DEMO' || tipo === 'FULL') {
      const defaults = getDefaultsForLicenseType(tipo);
      if (defaults) {
        diasInput.value = defaults.dias_validez;
        dispositivosInput.value = defaults.max_dispositivos;
      }
    }
  });

  // Establecer valores por defecto si el tipo ya está seleccionado
  const selectedTipo = tipoSelect.value.toUpperCase();
  if (selectedTipo === 'DEMO' || selectedTipo === 'FULL') {
    const defaults = getDefaultsForLicenseType(selectedTipo);
    if (defaults) {
      diasInput.value = defaults.dias_validez;
      dispositivosInput.value = defaults.max_dispositivos;
    }
  }
}

/**
 * Guardar la configuración de licencias
 * @param {object} newConfig - Objeto con los nuevos valores de configuración
 */
async function saveLicenseConfig(newConfig) {
  try {
    const response = await fetch(LICENSE_CONFIG_API, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        'x-session-id': sessionId
      },
      body: JSON.stringify(newConfig)
    });

    const data = await response.json();

    if (data.ok && data.config) {
      currentConfig = data.config;
      return {
        success: true,
        config: data.config
      };
    }

    return {
      success: false,
      message: data.message || 'Error al guardar la configuración'
    };
  } catch (error) {
    console.error('saveLicenseConfig error:', error);
    return {
      success: false,
      message: 'Error de conexión: ' + error.message
    };
  }
}

// Exportar para uso en otros módulos si es necesario
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    loadLicenseConfig,
    getDefaultsForLicenseType,
    initializeLicenseTypeSelector,
    saveLicenseConfig
  };
}
