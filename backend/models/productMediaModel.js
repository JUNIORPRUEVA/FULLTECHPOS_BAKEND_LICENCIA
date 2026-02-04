const { pool } = require('../db/pool');

async function listByProduct(productId, { includeInactive = true } = {}) {
  const res = await pool.query(
    `SELECT * FROM product_media
     WHERE product_id = $1
       AND ($2::boolean = true OR is_active = true)
     ORDER BY kind ASC, sort_order ASC, created_at ASC`,
    [productId, includeInactive]
  );
  return res.rows;
}

async function createMedia({
  product_id,
  kind,
  url,
  storage_path,
  mime,
  size_bytes,
  width,
  height,
  sort_order
}) {
  const res = await pool.query(
    `INSERT INTO product_media
      (product_id, kind, url, storage_path, mime, size_bytes, width, height, sort_order)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
     RETURNING *`,
    [
      product_id,
      kind,
      url,
      storage_path || null,
      mime || null,
      size_bytes != null ? Number(size_bytes) : null,
      width != null ? Number(width) : null,
      height != null ? Number(height) : null,
      sort_order != null ? Number(sort_order) : 0
    ]
  );
  return res.rows[0];
}

async function setActive(id, isActive) {
  const res = await pool.query(
    `UPDATE product_media SET is_active = $2 WHERE id = $1 RETURNING *`,
    [id, Boolean(isActive)]
  );
  return res.rows[0] || null;
}

async function setOrder(id, sortOrder) {
  const res = await pool.query(
    `UPDATE product_media SET sort_order = $2 WHERE id = $1 RETURNING *`,
    [id, Number(sortOrder) || 0]
  );
  return res.rows[0] || null;
}

async function getById(id) {
  const res = await pool.query('SELECT * FROM product_media WHERE id = $1', [id]);
  return res.rows[0] || null;
}

async function remove(id) {
  const res = await pool.query('DELETE FROM product_media WHERE id = $1 RETURNING *', [id]);
  return res.rows[0] || null;
}

module.exports = {
  listByProduct,
  createMedia,
  setActive,
  setOrder,
  getById,
  remove
};
