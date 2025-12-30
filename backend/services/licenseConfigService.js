const pool = require('../db/pool');

// Valores por defecto en memoria como fallback
const DEFAULT_CONFIG = {
  demo_dias_validez: 15,
  demo_max_dispositivos: 1,
  full_dias_validez: 365,
  full_max_dispositivos: 2
};

/**
 * Obtiene la configuración de licencias
 * Si no existe en BD, devuelve valores por defecto
 */
async function getLicenseConfig() {
  try {
    const result = await pool.query(
      'SELECT id, demo_dias_validez, demo_max_dispositivos, full_dias_validez, full_max_dispositivos, created_at, updated_at FROM license_config LIMIT 1'
    );

    if (result.rows && result.rows.length > 0) {
      return result.rows[0];
    }

    // Si no existe registro, devolver valores por defecto
    return DEFAULT_CONFIG;
  } catch (error) {
    console.error('getLicenseConfig error:', error);
    // Retornar valores por defecto en caso de error
    return DEFAULT_CONFIG;
  }
}

/**
 * Actualiza la configuración de licencias
 * Solo actualiza los campos que se envían
 */
async function updateLicenseConfig(payload) {
  try {
    const {
      demo_dias_validez,
      demo_max_dispositivos,
      full_dias_validez,
      full_max_dispositivos
    } = payload;

    // Construir dinámicamente la consulta SQL
    const updates = [];
    const values = [];
    let paramIndex = 1;

    if (demo_dias_validez !== undefined && demo_dias_validez !== null) {
      updates.push(`demo_dias_validez = $${paramIndex++}`);
      values.push(demo_dias_validez);
    }

    if (demo_max_dispositivos !== undefined && demo_max_dispositivos !== null) {
      updates.push(`demo_max_dispositivos = $${paramIndex++}`);
      values.push(demo_max_dispositivos);
    }

    if (full_dias_validez !== undefined && full_dias_validez !== null) {
      updates.push(`full_dias_validez = $${paramIndex++}`);
      values.push(full_dias_validez);
    }

    if (full_max_dispositivos !== undefined && full_max_dispositivos !== null) {
      updates.push(`full_max_dispositivos = $${paramIndex++}`);
      values.push(full_max_dispositivos);
    }

    // Si no hay nada para actualizar, retornar config actual
    if (updates.length === 0) {
      return getLicenseConfig();
    }

    // Agregar la cláusula RETURNING
    const query = `
      UPDATE license_config
      SET ${updates.join(', ')}
      WHERE id = '00000000-0000-0000-0000-000000000001'::uuid
      RETURNING id, demo_dias_validez, demo_max_dispositivos, full_dias_validez, full_max_dispositivos, created_at, updated_at
    `;

    const result = await pool.query(query, values);

    if (result.rows && result.rows.length > 0) {
      return result.rows[0];
    }

    // Si no existe el registro, crearlo con los valores actualizados
    const currentConfig = await getLicenseConfig();
    const newConfig = {
      ...currentConfig,
      ...payload
    };

    const insertQuery = `
      INSERT INTO license_config (
        id,
        demo_dias_validez,
        demo_max_dispositivos,
        full_dias_validez,
        full_max_dispositivos,
        created_at,
        updated_at
      )
      VALUES (
        '00000000-0000-0000-0000-000000000001'::uuid,
        $1,
        $2,
        $3,
        $4,
        now(),
        now()
      )
      ON CONFLICT (id) DO UPDATE SET
        demo_dias_validez = EXCLUDED.demo_dias_validez,
        demo_max_dispositivos = EXCLUDED.demo_max_dispositivos,
        full_dias_validez = EXCLUDED.full_dias_validez,
        full_max_dispositivos = EXCLUDED.full_max_dispositivos,
        updated_at = now()
      RETURNING id, demo_dias_validez, demo_max_dispositivos, full_dias_validez, full_max_dispositivos, created_at, updated_at
    `;

    const insertResult = await pool.query(insertQuery, [
      newConfig.demo_dias_validez,
      newConfig.demo_max_dispositivos,
      newConfig.full_dias_validez,
      newConfig.full_max_dispositivos
    ]);

    return insertResult.rows[0] || newConfig;
  } catch (error) {
    console.error('updateLicenseConfig error:', error);
    throw error;
  }
}

module.exports = {
  getLicenseConfig,
  updateLicenseConfig
};
