const { pool } = require('../db/pool');

function normalizeSlug(value) {
  const v = String(value || '').trim().toLowerCase();
  // keep url-safe: letters, numbers, dash
  return v
    .replace(/\s+/g, '-')
    .replace(/[^a-z0-9-]/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function normalizeTextArray(value) {
  if (value == null) return [];
  const arr = Array.isArray(value) ? value : String(value).split(',');
  return arr
    .map(v => String(v || '').trim())
    .filter(Boolean)
    .slice(0, 50);
}

async function listAdmin({ status, q, limit = 50, offset = 0 }) {
  const params = [];
  const where = [];

  if (status) {
    params.push(String(status));
    where.push(`status = $${params.length}`);
  }

  if (q) {
    params.push(`%${String(q).trim().toLowerCase()}%`);
    where.push(`(lower(name) LIKE $${params.length} OR lower(slug) LIKE $${params.length})`);
  }

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const totalRes = await pool.query(
    `SELECT COUNT(*)::int AS total FROM products ${whereSql}`,
    params
  );
  const total = totalRes.rows[0]?.total || 0;

  params.push(limit);
  params.push(offset);

  const rowsRes = await pool.query(
    `SELECT *
     FROM products
     ${whereSql}
     ORDER BY featured DESC, updated_at DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );

  return { total, products: rowsRes.rows };
}

async function getById(id) {
  const res = await pool.query('SELECT * FROM products WHERE id = $1', [id]);
  return res.rows[0] || null;
}

async function getBySlugPublished(slug) {
  const res = await pool.query(
    `SELECT * FROM products WHERE slug = $1 AND status = 'published'`,
    [slug]
  );
  return res.rows[0] || null;
}

async function create(input) {
  const slug = normalizeSlug(input.slug);
  if (!slug) throw new Error('Slug inválido');

  const name = String(input.name || '').trim();
  if (!name) throw new Error('Nombre requerido');

  const summary = String(input.summary || '').trim();
  const description = String(input.description || '').trim();

  const price_text = input.price_text != null ? String(input.price_text).trim() : null;
  const price_amount = input.price_amount != null && String(input.price_amount).trim() !== ''
    ? Number(input.price_amount)
    : null;

  const currency = String(input.currency || 'DOP').trim().toUpperCase();
  const status = String(input.status || 'draft').trim().toLowerCase();
  const featured = Boolean(input.featured);

  const tags = normalizeTextArray(input.tags);
  const categories = normalizeTextArray(input.categories);
  const platforms = normalizeTextArray(input.platforms);

  const system_requirements = input.system_requirements != null ? String(input.system_requirements) : null;
  const contact_whatsapp = input.contact_whatsapp != null ? String(input.contact_whatsapp).trim() : null;
  const contact_email = input.contact_email != null ? String(input.contact_email).trim() : null;
  const seo_title = input.seo_title != null ? String(input.seo_title).trim() : null;
  const seo_description = input.seo_description != null ? String(input.seo_description).trim() : null;

  const res = await pool.query(
    `INSERT INTO products
      (slug, name, summary, description, price_text, price_amount, currency, status, featured,
       tags, categories, platforms, system_requirements, contact_whatsapp, contact_email,
       seo_title, seo_description)
     VALUES
      ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17)
     RETURNING *`,
    [
      slug,
      name,
      summary,
      description,
      price_text,
      Number.isFinite(price_amount) ? price_amount : null,
      currency,
      status,
      featured,
      tags,
      categories,
      platforms,
      system_requirements,
      contact_whatsapp,
      contact_email,
      seo_title,
      seo_description
    ]
  );
  return res.rows[0];
}

async function update(id, patch) {
  const existing = await getById(id);
  if (!existing) return null;

  const slug = patch.slug != null ? normalizeSlug(patch.slug) : null;
  const name = patch.name != null ? String(patch.name).trim() : null;
  const summary = patch.summary != null ? String(patch.summary).trim() : null;
  const description = patch.description != null ? String(patch.description).trim() : null;

  const price_text = patch.price_text != null ? String(patch.price_text).trim() : null;
  const price_amount = patch.price_amount != null && String(patch.price_amount).trim() !== ''
    ? Number(patch.price_amount)
    : null;

  const currency = patch.currency != null ? String(patch.currency).trim().toUpperCase() : null;
  const status = patch.status != null ? String(patch.status).trim().toLowerCase() : null;
  const featured = patch.featured != null ? Boolean(patch.featured) : null;

  const tags = patch.tags != null ? normalizeTextArray(patch.tags) : null;
  const categories = patch.categories != null ? normalizeTextArray(patch.categories) : null;
  const platforms = patch.platforms != null ? normalizeTextArray(patch.platforms) : null;

  const system_requirements = patch.system_requirements != null ? String(patch.system_requirements) : null;
  const contact_whatsapp = patch.contact_whatsapp != null ? String(patch.contact_whatsapp).trim() : null;
  const contact_email = patch.contact_email != null ? String(patch.contact_email).trim() : null;
  const seo_title = patch.seo_title != null ? String(patch.seo_title).trim() : null;
  const seo_description = patch.seo_description != null ? String(patch.seo_description).trim() : null;

  const res = await pool.query(
    `UPDATE products
     SET slug = COALESCE($2, slug),
         name = COALESCE($3, name),
         summary = COALESCE($4, summary),
         description = COALESCE($5, description),
         price_text = COALESCE($6, price_text),
         price_amount = COALESCE($7, price_amount),
         currency = COALESCE($8, currency),
         status = COALESCE($9, status),
         featured = COALESCE($10, featured),
         tags = COALESCE($11, tags),
         categories = COALESCE($12, categories),
         platforms = COALESCE($13, platforms),
         system_requirements = COALESCE($14, system_requirements),
         contact_whatsapp = COALESCE($15, contact_whatsapp),
         contact_email = COALESCE($16, contact_email),
         seo_title = COALESCE($17, seo_title),
         seo_description = COALESCE($18, seo_description),
         updated_at = now()
     WHERE id = $1
     RETURNING *`,
    [
      id,
      slug,
      name,
      summary,
      description,
      price_text,
      Number.isFinite(price_amount) ? price_amount : null,
      currency,
      status,
      featured,
      tags,
      categories,
      platforms,
      system_requirements,
      contact_whatsapp,
      contact_email,
      seo_title,
      seo_description
    ]
  );
  return res.rows[0] || null;
}

async function remove(id) {
  const res = await pool.query('DELETE FROM products WHERE id = $1 RETURNING *', [id]);
  return res.rows[0] || null;
}

module.exports = {
  normalizeSlug,
  listAdmin,
  getById,
  getBySlugPublished,
  create,
  update,
  remove
};
