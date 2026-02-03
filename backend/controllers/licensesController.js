const { pool } = require('../db/pool');
const projectsModel = require('../models/projectsModel');

function nowDate() {
  return new Date();
}

function isExpiredByDate(license, now) {
  if (!license.fecha_fin) return false;
  return new Date(license.fecha_fin).getTime() < now.getTime();
}

async function activate(req, res) {
  try {
    const { license_key, device_id, project_id, project_code } = req.body || {};
    const key = String(license_key || '').trim();
    const device = String(device_id || '').trim();

    if (!key || !device) {
      return res.status(400).json({ ok: false, message: 'license_key y device_id son requeridos' });
    }

    let project = null;
    if (project_id) {
      project = await projectsModel.getProjectById(String(project_id).trim());
    } else if (project_code) {
      project = await projectsModel.getProjectByCode(String(project_code));
    } else {
      project = await projectsModel.getDefaultProject();
    }

    if (!project) {
      return res.status(404).json({ ok: false, message: 'Proyecto no encontrado' });
    }

    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const licRes = await client.query(
        'SELECT * FROM licenses WHERE license_key = $1 AND project_id = $2 FOR UPDATE',
        [key, project.id]
      );
      const license = licRes.rows[0];

      if (!license) {
        await client.query('ROLLBACK');
        return res.status(404).json({ ok: false, code: 'NOT_FOUND' });
      }

      if (license.estado === 'BLOQUEADA' || license.estado === 'VENCIDA') {
        await client.query('ROLLBACK');
        return res.status(400).json({ ok: false, code: 'BLOCKED_OR_EXPIRED' });
      }

      const now = nowDate();

      // Si existe fecha_fin y ya está vencida por fecha, marcar como VENCIDA y fallar
      if (isExpiredByDate(license, now)) {
        await client.query(`UPDATE licenses SET estado = 'VENCIDA' WHERE id = $1`, [license.id]);
        await client.query('COMMIT');
        return res.status(400).json({ ok: false, code: 'BLOCKED_OR_EXPIRED' });
      }

      // Si aún no tiene fecha de inicio, activarla por primera vez
      if (!license.fecha_inicio) {
        const days = Number(license.dias_validez);
        const fechaInicio = now;
        const fechaFin = new Date(now.getTime() + days * 24 * 60 * 60 * 1000);

        const upd = await client.query(
          `UPDATE licenses
           SET fecha_inicio = $2,
               fecha_fin = $3,
               estado = 'ACTIVA'
           WHERE id = $1
           RETURNING *`,
          [license.id, fechaInicio, fechaFin]
        );

        license.fecha_inicio = upd.rows[0].fecha_inicio;
        license.fecha_fin = upd.rows[0].fecha_fin;
        license.estado = upd.rows[0].estado;
      }

      // Normalizar a ACTIVA (si aplica)
      if (license.estado !== 'ACTIVA') {
        const upd = await client.query(`UPDATE licenses SET estado = 'ACTIVA' WHERE id = $1 RETURNING *`, [license.id]);
        license.estado = upd.rows[0].estado;
      }

      // Si este device ya está activado, solo tocar last_check_at y devolver
      const existingActRes = await client.query(
        `SELECT * FROM license_activations WHERE license_id = $1 AND device_id = $2`,
        [license.id, device]
      );
      const existing = existingActRes.rows[0];

      if (existing && existing.estado === 'ACTIVA') {
        await client.query(`UPDATE license_activations SET last_check_at = now() WHERE id = $1`, [existing.id]);
        const countRes = await client.query(
          `SELECT COUNT(*)::int AS total
           FROM license_activations
           WHERE license_id = $1 AND estado = 'ACTIVA'`,
          [license.id]
        );
        const used = countRes.rows[0]?.total || 0;
        await client.query('COMMIT');
        return res.json({
          ok: true,
          tipo: license.tipo,
          fecha_inicio: license.fecha_inicio,
          fecha_fin: license.fecha_fin,
          max_dispositivos: license.max_dispositivos,
          usados: used,
          estado: 'ACTIVA'
        });
      }

      const countRes = await client.query(
        `SELECT COUNT(*)::int AS total
         FROM license_activations
         WHERE license_id = $1 AND estado = 'ACTIVA'`,
        [license.id]
      );
      const used = countRes.rows[0]?.total || 0;

      if (used >= Number(license.max_dispositivos)) {
        await client.query('ROLLBACK');
        return res.status(400).json({ ok: false, code: 'MAX_DEVICES_REACHED' });
      }

      if (existing && existing.estado !== 'ACTIVA') {
        // Reactivar este mismo device sin consumir otro slot (ya existe la fila)
        await client.query(
          `UPDATE license_activations
           SET estado = 'ACTIVA', activated_at = now(), last_check_at = now()
           WHERE id = $1`,
          [existing.id]
        );
      } else {
        await client.query(
          `INSERT INTO license_activations (license_id, project_id, device_id, estado)
           VALUES ($1, $2, $3, 'ACTIVA')`,
          [license.id, project.id, device]
        );
      }

      const usedAfter = used + 1;
      await client.query('COMMIT');
      return res.json({
        ok: true,
        tipo: license.tipo,
        fecha_inicio: license.fecha_inicio,
        fecha_fin: license.fecha_fin,
        max_dispositivos: license.max_dispositivos,
        usados: usedAfter,
        estado: 'ACTIVA'
      });
    } catch (error) {
      await client.query('ROLLBACK');
      console.error('activate error:', error);
      return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
    } finally {
      client.release();
    }
  } catch (error) {
    console.error('activate outer error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function check(req, res) {
  try {
    const { license_key, device_id, project_id, project_code } = req.body || {};
    const key = String(license_key || '').trim();
    const device = String(device_id || '').trim();

    if (!key || !device) {
      return res.status(400).json({ ok: false, message: 'license_key y device_id son requeridos' });
    }

    let project = null;
    if (project_id) {
      project = await projectsModel.getProjectById(String(project_id).trim());
    } else if (project_code) {
      project = await projectsModel.getProjectByCode(String(project_code));
    } else {
      project = await projectsModel.getDefaultProject();
    }

    if (!project) {
      return res.status(404).json({ ok: false, message: 'Proyecto no encontrado' });
    }

    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const licRes = await client.query(
        'SELECT * FROM licenses WHERE license_key = $1 AND project_id = $2 FOR UPDATE',
        [key, project.id]
      );
      const license = licRes.rows[0];

      if (!license) {
        await client.query('ROLLBACK');
        return res.status(404).json({ ok: false, code: 'NOT_FOUND' });
      }

      const actRes = await client.query(
        `SELECT * FROM license_activations
         WHERE license_id = $1 AND device_id = $2`,
        [license.id, device]
      );
      const activation = actRes.rows[0];

      if (!activation || activation.estado !== 'ACTIVA') {
        await client.query('ROLLBACK');
        return res.status(404).json({ ok: false, code: 'NOT_FOUND' });
      }

      await client.query('UPDATE license_activations SET last_check_at = now() WHERE id = $1', [activation.id]);

      const now = nowDate();
      let currentEstado = license.estado;
      let code = 'OK';
      let ok = true;

      if (license.estado === 'BLOQUEADA') {
        ok = false;
        code = 'BLOCKED';
      } else if (license.estado === 'VENCIDA' || isExpiredByDate(license, now)) {
        ok = false;
        code = 'EXPIRED';
        if (license.estado !== 'VENCIDA') {
          await client.query(`UPDATE licenses SET estado = 'VENCIDA' WHERE id = $1`, [license.id]);
          currentEstado = 'VENCIDA';
        }
      } else {
        // Si está vigente, normalizar a ACTIVA
        if (license.estado !== 'ACTIVA') {
          const upd = await client.query(`UPDATE licenses SET estado = 'ACTIVA' WHERE id = $1 RETURNING *`, [license.id]);
          currentEstado = upd.rows[0]?.estado || 'ACTIVA';
        } else {
          currentEstado = 'ACTIVA';
        }
      }

      await client.query('COMMIT');
      return res.json({
        ok,
        code,
        tipo: license.tipo,
        fecha_inicio: license.fecha_inicio,
        fecha_fin: license.fecha_fin,
        estado: currentEstado
      });
    } catch (error) {
      await client.query('ROLLBACK');
      console.error('check error:', error);
      return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
    } finally {
      client.release();
    }
  } catch (error) {
    console.error('check outer error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

module.exports = {
  activate,
  check
};
