const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { pool } = require('../db/pool');

const router = express.Router();

function getJwtSecret() {
  const secret = process.env.JWT_SECRET;
  if (secret && String(secret).trim().length >= 16) return secret;

  // Dev fallback (keeps local setup easy). In production, set JWT_SECRET.
  return 'dev-jwt-secret-change-me';
}

function normalizeCompanyCode(input) {
  return String(input ?? '')
    .trim()
    .toUpperCase();
}

function normalizeEmail(input) {
  return String(input ?? '')
    .trim()
    .toLowerCase();
}

// POST /api/auth/login
// Body: { company_code|companyCode, email, password }
router.post('/login', async (req, res) => {
  const companyCode = normalizeCompanyCode(
    req.body.company_code ?? req.body.companyCode ?? req.body.company ?? ''
  );
  const email = normalizeEmail(req.body.email);
  const password = String(req.body.password ?? '');

  if (!companyCode || !email || !password) {
    return res.status(400).json({
      success: false,
      message: 'company_code, email y password son requeridos'
    });
  }

  const client = await pool.connect();
  try {
    const companyResult = await client.query(
      `SELECT id, name, code, is_active
       FROM companies
       WHERE code = $1
       LIMIT 1`,
      [companyCode]
    );

    if (companyResult.rowCount === 0) {
      return res.status(401).json({ success: false, message: 'Empresa inválida' });
    }

    const company = companyResult.rows[0];
    if (!company.is_active) {
      return res.status(403).json({ success: false, message: 'Empresa inactiva' });
    }

    const userResult = await client.query(
      `SELECT id, company_id, email, username, display_name, role, is_active, password_hash, permissions
       FROM pos_users
       WHERE company_id = $1 AND email = $2
       LIMIT 1`,
      [company.id, email]
    );

    if (userResult.rowCount === 0) {
      return res.status(401).json({ success: false, message: 'Usuario inválido' });
    }

    const user = userResult.rows[0];
    if (!user.is_active) {
      return res.status(403).json({ success: false, message: 'Usuario inactivo' });
    }

    if (!user.password_hash) {
      return res.status(401).json({
        success: false,
        message: 'Usuario sin contraseña configurada'
      });
    }

    const ok = await bcrypt.compare(password, user.password_hash);
    if (!ok) {
      return res.status(401).json({ success: false, message: 'Credenciales inválidas' });
    }

    const token = jwt.sign(
      {
        companyId: company.id,
        role: user.role
      },
      getJwtSecret(),
      {
        subject: String(user.id),
        expiresIn: process.env.JWT_EXPIRES_IN || '30d'
      }
    );

    return res.json({
      success: true,
      token,
      company: {
        id: company.id,
        code: company.code,
        name: company.name
      },
      user: {
        id: user.id,
        email: user.email,
        displayName: user.display_name || user.username || user.email,
        role: user.role,
        permissions: user.permissions
      }
    });
  } catch (err) {
    return res.status(500).json({
      success: false,
      message: 'Error al iniciar sesión',
      error: err.message
    });
  } finally {
    client.release();
  }
});

module.exports = router;
