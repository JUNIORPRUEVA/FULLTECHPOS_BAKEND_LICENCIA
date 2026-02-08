const { pool } = require('../db/pool');
const projectsModel = require('../models/projectsModel');
const crypto = require('crypto');
const { verifyLicenseFile, getPublicKeyPem } = require('../utils/licenseFile');

function nowDate() {
  return new Date();
}

function isExpiredByDate(license, now) {
  if (!license.fecha_fin) return false;
  return new Date(license.fecha_fin).getTime() < now.getTime();
}

function normalizeTrim(value) {
  const v = String(value || '').trim();
  return v ? v : '';
}

function safeIsoDate(value) {
  try {
    if (!value) return null;
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return null;
    return d.toISOString();
  } catch (_) {
    return null;
  }
}

function isExpiredByPayloadDate(payload, now) {
  if (!payload || !payload.fecha_fin) return false;
  const d = new Date(payload.fecha_fin);
  if (Number.isNaN(d.getTime())) return false;
  return d.getTime() < now.getTime();
}

async function verifyOfflineFile(req, res) {
  try {
    const licenseFile = req.body;
    const deviceToCheck = normalizeTrim(req.query?.device_id || req.body?.device_id_check);

    const publicKeyPem = getPublicKeyPem();
    const sig = verifyLicenseFile(licenseFile, publicKeyPem);

    const payload = licenseFile && typeof licenseFile === 'object' ? licenseFile.payload : null;
    const now = nowDate();
    const expired = isExpiredByPayloadDate(payload, now);

    let device_match = null;
    if (deviceToCheck && payload && payload.device_id) {
      device_match = normalizeTrim(payload.device_id) === deviceToCheck;
    }

    return res.json({
      ok: true,
      signature_ok: Boolean(sig.ok),
      signature_reason: sig.reason,
      expired,
      device_match,
      now: now.toISOString(),
      payload: {
        v: payload?.v ?? null,
        project_code: payload?.project_code ?? null,
        license_key: payload?.license_key ?? null,
        tipo: payload?.tipo ?? null,
        fecha_inicio: safeIsoDate(payload?.fecha_inicio),
        fecha_fin: safeIsoDate(payload?.fecha_fin),
        dias_validez: payload?.dias_validez ?? null,
        max_dispositivos: payload?.max_dispositivos ?? null,
        device_id: payload?.device_id ?? null,
        customer: payload?.customer ?? null,
        issued_at: safeIsoDate(payload?.issued_at)
      }
    });
  } catch (error) {
    console.error('verifyOfflineFile error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function getPublicSigningKey(req, res) {
  try {
    const publicKeyPem = getPublicKeyPem();
    const keyObject = crypto.createPublicKey(publicKeyPem);
    const jwk = keyObject.export({ format: 'jwk' });

    // For Ed25519: jwk.kty=OKP, jwk.crv=Ed25519, jwk.x=base64url
    return res.json({ ok: true, alg: 'Ed25519', jwk });
  } catch (error) {
    console.error('getPublicSigningKey error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
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
        estado: currentEstado,
        motivo: license.notas || null
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

// POST /api/licenses/auto-activate
// Auto-detects the customer from prior activations on this device (DEMO or FULL)
// and, if an ACTIVA license exists for that customer+project, activates it for the device.
// This enables the ONLINE upgrade flow after DEMO ends without the user typing a new key.
async function autoActivateByDevice(req, res) {
  try {
    const { device_id, project_id, project_code } = req.body || {};
    const device = String(device_id || '').trim();

    if (!device) {
      return res.status(400).json({ ok: false, message: 'device_id es requerido' });
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

      // 1) Identify customer_id from the latest activation on this device for this project.
      const histRes = await client.query(
        `SELECT l.customer_id
         FROM license_activations a
         JOIN licenses l ON l.id = a.license_id
         WHERE a.device_id = $1
           AND a.project_id = $2
         ORDER BY a.last_check_at DESC, a.activated_at DESC, l.created_at DESC
         LIMIT 1`,
        [device, project.id]
      );

      const hist = histRes.rows[0];
      if (!hist || !hist.customer_id) {
        await client.query('ROLLBACK');
        return res.status(404).json({ ok: false, code: 'NO_HISTORY', message: 'Sin historial de licencias para este dispositivo' });
      }

      const customerId = hist.customer_id;
      const now = nowDate();

      // 2) Find newest license for this customer+project that can be used.
      const licRes = await client.query(
        `SELECT *
         FROM licenses
         WHERE customer_id = $1
           AND project_id = $2
         ORDER BY created_at DESC
         LIMIT 25`,
        [customerId, project.id]
      );

      let chosen = null;
      for (const l of licRes.rows) {
        if (!l) continue;

        if (l.estado === 'BLOQUEADA') {
          // If the newest license is blocked, treat as blocked.
          chosen = l;
          break;
        }

        if (l.estado === 'VENCIDA') {
          continue;
        }

        if (isExpiredByDate(l, now)) {
          // Normalize to VENCIDA in DB.
          try {
            await client.query(`UPDATE licenses SET estado = 'VENCIDA' WHERE id = $1`, [l.id]);
          } catch (_) {}
          continue;
        }

        if (l.estado === 'ACTIVA') {
          chosen = l;
          break;
        }
      }

      if (!chosen) {
        await client.query('ROLLBACK');
        return res.status(404).json({ ok: false, code: 'NO_ACTIVE_LICENSE', message: 'No hay licencia activa para este cliente' });
      }

      if (chosen.estado === 'BLOQUEADA') {
        await client.query('COMMIT');
        return res.status(403).json({
          ok: false,
          code: 'BLOCKED',
          estado: 'BLOQUEADA',
          motivo: chosen.notas || null
        });
      }

      // 3) Ensure license has dates: initialize on first activation.
      if (!chosen.fecha_inicio) {
        const days = Number(chosen.dias_validez) || 1;
        const fechaInicio = now;
        const fechaFin = new Date(now.getTime() + days * 24 * 60 * 60 * 1000);
        const upd = await client.query(
          `UPDATE licenses
           SET fecha_inicio = $2,
               fecha_fin = $3,
               estado = 'ACTIVA'
           WHERE id = $1
           RETURNING *`,
          [chosen.id, fechaInicio, fechaFin]
        );
        chosen = upd.rows[0] || chosen;
      }

      // 4) Activate this license for the device (respect max_dispositivos).
      const existingActRes = await client.query(
        `SELECT * FROM license_activations WHERE license_id = $1 AND device_id = $2`,
        [chosen.id, device]
      );
      const existing = existingActRes.rows[0];

      const countRes = await client.query(
        `SELECT COUNT(*)::int AS total
         FROM license_activations
         WHERE license_id = $1 AND estado = 'ACTIVA'`,
        [chosen.id]
      );
      const used = countRes.rows[0]?.total || 0;

      if (existing && existing.estado === 'ACTIVA') {
        await client.query(`UPDATE license_activations SET last_check_at = now() WHERE id = $1`, [existing.id]);
        await client.query('COMMIT');
        return res.json({
          ok: true,
          code: 'OK',
          license_key: chosen.license_key,
          tipo: chosen.tipo,
          fecha_inicio: chosen.fecha_inicio,
          fecha_fin: chosen.fecha_fin,
          max_dispositivos: chosen.max_dispositivos,
          usados: used,
          estado: 'ACTIVA',
          motivo: chosen.notas || null
        });
      }

      if (!existing && used >= Number(chosen.max_dispositivos)) {
        await client.query('ROLLBACK');
        return res.status(400).json({ ok: false, code: 'MAX_DEVICES_REACHED' });
      }

      if (existing && existing.estado !== 'ACTIVA') {
        await client.query(
          `UPDATE license_activations
           SET estado = 'ACTIVA', activated_at = now(), last_check_at = now(), project_id = $2
           WHERE id = $1`,
          [existing.id, project.id]
        );
        await client.query('COMMIT');
        return res.json({
          ok: true,
          code: 'OK',
          license_key: chosen.license_key,
          tipo: chosen.tipo,
          fecha_inicio: chosen.fecha_inicio,
          fecha_fin: chosen.fecha_fin,
          max_dispositivos: chosen.max_dispositivos,
          usados: used + 1,
          estado: 'ACTIVA',
          motivo: chosen.notas || null
        });
      }

      await client.query(
        `INSERT INTO license_activations (license_id, project_id, device_id, estado)
         VALUES ($1, $2, $3, 'ACTIVA')`,
        [chosen.id, project.id, device]
      );

      await client.query('COMMIT');
      return res.json({
        ok: true,
        code: 'OK',
        license_key: chosen.license_key,
        tipo: chosen.tipo,
        fecha_inicio: chosen.fecha_inicio,
        fecha_fin: chosen.fecha_fin,
        max_dispositivos: chosen.max_dispositivos,
        usados: used + 1,
        estado: 'ACTIVA',
        motivo: chosen.notas || null
      });
    } catch (error) {
      await client.query('ROLLBACK');
      console.error('autoActivateByDevice error:', error);
      return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
    } finally {
      client.release();
    }
  } catch (error) {
    console.error('autoActivateByDevice outer error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

module.exports = {
  activate,
  check,
  autoActivateByDevice,
  verifyOfflineFile,
  getPublicSigningKey
};
