const fs = require('fs');

const productMediaModel = require('../models/productMediaModel');
const productFilesModel = require('../models/productFilesModel');

function safeFilename(value) {
  const v = String(value || '').trim();
  if (!v || v.length > 200) return null;
  if (v.includes('..') || v.includes('/') || v.includes('\\')) return null;
  return v;
}

async function serveMedia(req, res) {
  try {
    const filename = safeFilename(req.params.filename);
    if (!filename) return res.status(400).send('Bad Request');

    // Find media by url pointing to this filename.
    const { pool } = require('../db/pool');
    const lookupUrl = `/api/public/media/${filename}`;

    const rowRes = await pool.query(
      `SELECT m.storage_path, p.status
       FROM product_media m
       JOIN products p ON p.id = m.product_id
       WHERE m.url = $1
         AND m.is_active = true
       LIMIT 1`,
      [lookupUrl]
    );

    const row = rowRes.rows[0];
    if (!row) return res.status(404).send('Not Found');
    if (row.status !== 'published') return res.status(404).send('Not Found');

    const filePath = row.storage_path;
    if (!filePath || !fs.existsSync(filePath)) return res.status(404).send('Not Found');

    return res.sendFile(filePath);
  } catch (e) {
    console.error('serveMedia error:', e);
    return res.status(500).send('Error');
  }
}

async function serveDownload(req, res) {
  try {
    const filename = safeFilename(req.params.filename);
    if (!filename) return res.status(400).send('Bad Request');

    const { pool } = require('../db/pool');
    const lookupUrl = `/api/public/download/${filename}`;

    const rowRes = await pool.query(
      `SELECT f.storage_path, f.display_name, p.status
       FROM product_files f
       JOIN products p ON p.id = f.product_id
       WHERE f.url = $1
         AND f.is_active = true
       LIMIT 1`,
      [lookupUrl]
    );

    const row = rowRes.rows[0];
    if (!row) return res.status(404).send('Not Found');
    if (row.status !== 'published') return res.status(404).send('Not Found');

    const filePath = row.storage_path;
    if (!filePath || !fs.existsSync(filePath)) return res.status(404).send('Not Found');

    return res.download(filePath, row.display_name || filename);
  } catch (e) {
    console.error('serveDownload error:', e);
    return res.status(500).send('Error');
  }
}

module.exports = {
  serveMedia,
  serveDownload
};
