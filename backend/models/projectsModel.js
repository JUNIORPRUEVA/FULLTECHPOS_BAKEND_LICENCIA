const { pool } = require('../db/pool');

function normalizeCode(code) {
  return String(code || '').trim().toUpperCase();
}

async function getProjectById(projectId) {
  const res = await pool.query('SELECT * FROM projects WHERE id = $1', [projectId]);
  return res.rows[0] || null;
}

async function getProjectByCode(code) {
  const c = normalizeCode(code);
  const res = await pool.query('SELECT * FROM projects WHERE code = $1', [c]);
  return res.rows[0] || null;
}

async function getDefaultProject() {
  let project = await getProjectByCode('DEFAULT');
  if (project) return project;

  project = await getProjectByCode('FULLPOS');
  if (project) return project;

  const result = await pool.query(
    'SELECT * FROM projects ORDER BY created_at DESC LIMIT 1'
  );
  return result.rows[0] || null;
}

async function createProject({ code, name, description }) {
  const c = normalizeCode(code);
  const n = String(name || '').trim();
  const d = description == null ? null : String(description);

  const res = await pool.query(
    `INSERT INTO projects (code, name, description, is_active)
     VALUES ($1, $2, $3, true)
     RETURNING *`,
    [c, n, d]
  );
  return res.rows[0] || null;
}

async function listProjects() {
  const res = await pool.query(
    `SELECT *
     FROM projects
     ORDER BY created_at DESC`
  );
  return res.rows;
}

/**
 * Actualiza todos los campos editables de un proyecto.
 * @param {string} projectId - UUID del proyecto
 * @param {Object} data - Campos a actualizar
 * @returns {Object|null} Proyecto actualizado o null
 */
async function updateProject(projectId, data) {
  const {
    name,
    code,
    description,
    monthly_price,
    currency,
    demo_days,
    min_purchase_months,
    is_paid_project,
    allow_demo,
    is_active,
    product_profile
  } = data;

  const res = await pool.query(
    `UPDATE projects
     SET
       name = COALESCE($2, name),
       code = COALESCE($3, code),
       description = COALESCE($4, description),
       monthly_price = COALESCE($5, monthly_price),
       currency = COALESCE($6, currency),
       demo_days = COALESCE($7, demo_days),
       min_purchase_months = COALESCE($8, min_purchase_months),
       is_paid_project = COALESCE($9, is_paid_project),
       allow_demo = COALESCE($10, allow_demo),
       is_active = COALESCE($11, is_active),
       product_profile = COALESCE($12, product_profile),
       updated_at = now()
     WHERE id = $1
     RETURNING *`,
    [
      projectId,
      name != null ? String(name).trim() : null,
      code != null ? normalizeCode(code) : null,
      description !== undefined ? (description == null ? null : String(description)) : null,
      monthly_price != null ? monthly_price : null,
      currency || null,
      demo_days != null ? demo_days : null,
      min_purchase_months != null ? min_purchase_months : null,
      is_paid_project != null ? is_paid_project : null,
      allow_demo != null ? allow_demo : null,
      is_active != null ? is_active : null,
      product_profile !== undefined ? product_profile : null
    ]
  );
  return res.rows[0] || null;
}

async function updateProjectBillingSettings(projectId, settings) {
  const {
    monthly_price,
    currency,
    demo_days,
    min_purchase_months,
    is_paid_project,
    allow_demo,
    is_active
  } = settings;

  const res = await pool.query(
    `UPDATE projects
     SET
       monthly_price = COALESCE($2, monthly_price),
       currency = COALESCE($3, currency),
       demo_days = COALESCE($4, demo_days),
       min_purchase_months = COALESCE($5, min_purchase_months),
       is_paid_project = COALESCE($6, is_paid_project),
       allow_demo = COALESCE($7, allow_demo),
       is_active = COALESCE($8, is_active),
       updated_at = now()
     WHERE id = $1
     RETURNING *`,
    [
      projectId,
      monthly_price != null ? monthly_price : null,
      currency || null,
      demo_days != null ? demo_days : null,
      min_purchase_months != null ? min_purchase_months : null,
      is_paid_project != null ? is_paid_project : null,
      allow_demo != null ? allow_demo : null,
      is_active != null ? is_active : null
    ]
  );
  return res.rows[0] || null;
}

/**
 * Calcula el costo de una compra de licencia basada en la configuración del proyecto.
 * @param {Object} project - El objeto del proyecto con monthly_price, currency, min_purchase_months
 * @param {number} months - Cantidad de meses a comprar
 * @returns {Object} { months, monthly_price, currency, subtotal, total }
 */
function calculateLicensePurchase(project, months) {
  const monthlyPrice = Number(project.monthly_price) || 0;
  const minMonths = Number(project.min_purchase_months) || 1;
  const currency = String(project.currency || 'USD').trim();

  const validatedMonths = Math.max(minMonths, Math.floor(Number(months)) || minMonths);
  const subtotal = monthlyPrice * validatedMonths;
  const total = subtotal; // Sin impuestos por ahora

  return {
    months: validatedMonths,
    monthly_price: monthlyPrice,
    currency,
    subtotal,
    total
  };
}

module.exports = {
  normalizeCode,
  getProjectById,
  getProjectByCode,
  getDefaultProject,
  createProject,
  listProjects,
  updateProject,
  updateProjectBillingSettings,
  calculateLicensePurchase
};
