const { pool } = require('../db/pool');

async function listByProduct(productId, { includeInactive = true } = {}) {
  const res = await pool.query(
    `SELECT * FROM product_files
     WHERE product_id = $1
       AND ($2::boolean = true OR is_active = true)
     ORDER BY platform ASC, uploaded_at DESC`,
    [productId, includeInactive]
  );
  return res.rows;
}

async function createFile({
  product_id,
  platform,
  file_type,
  display_name,
  version,
  url,
  storage_path,
  size_bytes,
  checksum_sha256,
  is_active,
  requires_license
}) {
  const res = await pool.query(
    `INSERT INTO product_files
      (product_id, platform, file_type, display_name, version, url, storage_path, size_bytes, checksum_sha256, is_active, requires_license)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
     RETURNING *`,
    [
      product_id,
      platform,
      file_type,
      display_name,
      version || null,
      url,
      storage_path || null,
      size_bytes != null ? Number(size_bytes) : null,
      checksum_sha256 || null,
      is_active != null ? Boolean(is_active) : true,
      requires_license != null ? Boolean(requires_license) : false
    ]
  );
  return res.rows[0];
}

async function setActive(id, isActive) {
  const res = await pool.query(
    `UPDATE product_files SET is_active = $2 WHERE id = $1 RETURNING *`,
    [id, Boolean(isActive)]
  );
  return res.rows[0] || null;
}

async function getById(id) {
  const res = await pool.query('SELECT * FROM product_files WHERE id = $1', [id]);
  return res.rows[0] || null;
}

async function remove(id) {
  const res = await pool.query('DELETE FROM product_files WHERE id = $1 RETURNING *', [id]);
  return res.rows[0] || null;
}

module.exports = {
  listByProduct,
  createFile,
  setActive,
  getById,
  remove
};
