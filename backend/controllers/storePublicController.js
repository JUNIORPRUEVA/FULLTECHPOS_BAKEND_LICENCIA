const productsModel = require('../models/productsModel');
const productMediaModel = require('../models/productMediaModel');
const productFilesModel = require('../models/productFilesModel');
const settingsModel = require('../models/storeSettingsModel');

function safeText(value, max = 200) {
  const v = String(value ?? '').trim();
  return v.length > max ? v.slice(0, max) : v;
}

async function getPublicSettings(req, res) {
  try {
    const settings = await settingsModel.getSettings();
    return res.json({ ok: true, settings });
  } catch (e) {
    console.error('getPublicSettings error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function listPublishedProducts(req, res) {
  try {
    const q = safeText(req.query?.q, 80);
    const platform = safeText(req.query?.platform, 30);

    // Simple filtering in SQL.
    const limit = Math.min(60, Math.max(1, Number(req.query?.limit) || 24));
    const offset = Math.max(0, Number(req.query?.offset) || 0);

    const { pool } = require('../db/pool');
    const params = [limit, offset];
    let where = `WHERE status = 'published'`;

    if (q) {
      params.push(`%${q.toLowerCase()}%`);
      where += ` AND (lower(name) LIKE $${params.length} OR lower(summary) LIKE $${params.length} OR lower(slug) LIKE $${params.length})`;
    }

    if (platform) {
      params.push(platform);
      where += ` AND $${params.length} = ANY(platforms)`;
    }

    const totalRes = await pool.query(
      `SELECT COUNT(*)::int AS total FROM products ${where}`,
      params.slice(2)
    );
    const total = totalRes.rows[0]?.total || 0;

    const rowsRes = await pool.query(
      `SELECT * FROM products ${where} ORDER BY featured DESC, updated_at DESC LIMIT $1 OFFSET $2`,
      params
    );

    // Attach cover image (first active cover_image)
    const products = rowsRes.rows;
    const ids = products.map(p => p.id);

    let coversById = Object.create(null);
    if (ids.length) {
      const coverRes = await pool.query(
        `SELECT DISTINCT ON (product_id) product_id, url
         FROM product_media
         WHERE product_id = ANY($1)
           AND kind = 'cover_image'
           AND is_active = true
         ORDER BY product_id, sort_order ASC, created_at ASC`,
        [ids]
      );
      for (const row of coverRes.rows) coversById[row.product_id] = row.url;
    }

    const shaped = products.map(p => ({
      id: p.id,
      slug: p.slug,
      name: p.name,
      summary: p.summary,
      price_text: p.price_text,
      price_amount: p.price_amount,
      currency: p.currency,
      featured: p.featured,
      tags: p.tags,
      categories: p.categories,
      platforms: p.platforms,
      cover_url: coversById[p.id] || null
    }));

    return res.json({ ok: true, total, products: shaped });
  } catch (e) {
    console.error('listPublishedProducts error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function getPublishedProductDetail(req, res) {
  try {
    const slug = String(req.params.slug || '').trim().toLowerCase();
    if (!slug) return res.status(400).json({ ok: false, message: 'slug requerido' });

    const product = await productsModel.getBySlugPublished(slug);
    if (!product) return res.status(404).json({ ok: false, message: 'No encontrado' });

    const media = await productMediaModel.listByProduct(product.id, { includeInactive: false });
    const files = await productFilesModel.listByProduct(product.id, { includeInactive: false });

    return res.json({ ok: true, product, media, files });
  } catch (e) {
    console.error('getPublishedProductDetail error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

module.exports = {
  getPublicSettings,
  listPublishedProducts,
  getPublishedProductDetail
};
