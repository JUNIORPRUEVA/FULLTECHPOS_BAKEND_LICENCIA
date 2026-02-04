const path = require('path');
const fs = require('fs');
const multer = require('multer');

const productsModel = require('../models/productsModel');
const productMediaModel = require('../models/productMediaModel');
const productFilesModel = require('../models/productFilesModel');

function asUuid(value) {
  const v = String(value || '').trim();
  if (!/^[0-9a-fA-F-]{36}$/.test(v)) return null;
  return v;
}

function safeText(value, max = 5000) {
  const v = String(value ?? '').trim();
  if (v.length > max) return v.slice(0, max);
  return v;
}

function ensureUploadsDir() {
  const base = path.join(__dirname, '../../uploads');
  if (!fs.existsSync(base)) fs.mkdirSync(base, { recursive: true });
  return base;
}

function productDir(productId, subdir) {
  const base = ensureUploadsDir();
  const dir = path.join(base, 'products', productId, subdir);
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function createUploader({ subdir, allowedExts, maxBytes }) {
  const storage = multer.diskStorage({
    destination: (req, file, cb) => {
      const productId = asUuid(req.params.productId);
      if (!productId) return cb(new Error('productId inválido'));
      cb(null, productDir(productId, subdir));
    },
    filename: (req, file, cb) => {
      const safe = file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
      cb(null, `${Date.now()}-${safe}`);
    }
  });

  const fileFilter = (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    if (allowedExts.includes(ext)) return cb(null, true);
    return cb(new Error(`Tipo de archivo no permitido: ${ext}`));
  };

  return multer({
    storage,
    fileFilter,
    limits: { fileSize: maxBytes }
  });
}

const uploadImage = createUploader({
  subdir: 'media',
  allowedExts: ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.svg'],
  maxBytes: 15 * 1024 * 1024
});

const uploadBinary = createUploader({
  subdir: 'files',
  allowedExts: ['.zip', '.exe', '.msi', '.apk', '.aab', '.pdf', '.tar', '.gz'],
  maxBytes: 800 * 1024 * 1024
});

async function listProducts(req, res) {
  try {
    const { status, q, limit, offset } = req.query;
    const data = await productsModel.listAdmin({
      status: status ? String(status) : undefined,
      q: q ? String(q) : undefined,
      limit: Math.min(200, Math.max(1, Number(limit) || 50)),
      offset: Math.max(0, Number(offset) || 0)
    });
    return res.json({ ok: true, ...data });
  } catch (e) {
    console.error('listProducts error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function getProduct(req, res) {
  try {
    const id = asUuid(req.params.id);
    if (!id) return res.status(400).json({ ok: false, message: 'id inválido' });

    const product = await productsModel.getById(id);
    if (!product) return res.status(404).json({ ok: false, message: 'No encontrado' });

    const media = await productMediaModel.listByProduct(id, { includeInactive: true });
    const files = await productFilesModel.listByProduct(id, { includeInactive: true });

    return res.json({ ok: true, product, media, files });
  } catch (e) {
    console.error('getProduct error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function createProduct(req, res) {
  try {
    const input = req.body || {};
    const created = await productsModel.create(input);
    return res.status(201).json({ ok: true, product: created });
  } catch (e) {
    const msg = String(e?.message || e);
    const isUnique = String(e?.code || '') === '23505';
    return res.status(isUnique ? 409 : 400).json({ ok: false, message: msg });
  }
}

async function updateProduct(req, res) {
  try {
    const id = asUuid(req.params.id);
    if (!id) return res.status(400).json({ ok: false, message: 'id inválido' });

    const updated = await productsModel.update(id, req.body || {});
    if (!updated) return res.status(404).json({ ok: false, message: 'No encontrado' });
    return res.json({ ok: true, product: updated });
  } catch (e) {
    const msg = String(e?.message || e);
    const isUnique = String(e?.code || '') === '23505';
    return res.status(isUnique ? 409 : 400).json({ ok: false, message: msg });
  }
}

async function deleteProduct(req, res) {
  try {
    const id = asUuid(req.params.id);
    if (!id) return res.status(400).json({ ok: false, message: 'id inválido' });

    const removed = await productsModel.remove(id);
    if (!removed) return res.status(404).json({ ok: false, message: 'No encontrado' });
    return res.json({ ok: true, product: removed });
  } catch (e) {
    console.error('deleteProduct error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

function hasPublishedCover(mediaRows) {
  return (mediaRows || []).some(m => m.kind === 'cover_image' && m.is_active);
}

async function setStatus(req, res) {
  try {
    const id = asUuid(req.params.id);
    if (!id) return res.status(400).json({ ok: false, message: 'id inválido' });

    const status = String(req.body?.status || '').trim().toLowerCase();
    if (!['draft', 'published', 'archived'].includes(status)) {
      return res.status(400).json({ ok: false, message: 'status inválido' });
    }

    if (status === 'published') {
      const media = await productMediaModel.listByProduct(id, { includeInactive: true });
      if (!hasPublishedCover(media)) {
        return res.status(400).json({
          ok: false,
          message: 'No se puede publicar sin una portada (cover_image) activa.'
        });
      }
    }

    const updated = await productsModel.update(id, { status });
    if (!updated) return res.status(404).json({ ok: false, message: 'No encontrado' });
    return res.json({ ok: true, product: updated });
  } catch (e) {
    console.error('setStatus error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function uploadMedia(req, res) {
  try {
    const productId = asUuid(req.params.productId);
    if (!productId) return res.status(400).json({ ok: false, message: 'productId inválido' });

    const kind = safeText(req.body?.kind, 50);
    if (!['logo', 'cover_image', 'gallery_image', 'og_image'].includes(kind)) {
      return res.status(400).json({ ok: false, message: 'kind inválido' });
    }

    if (!req.file) {
      return res.status(400).json({ ok: false, message: 'Archivo requerido' });
    }

    const storagePath = req.file.path;
    const stats = fs.statSync(storagePath);

    const media = await productMediaModel.createMedia({
      product_id: productId,
      kind,
      url: `/api/public/media/${encodeURIComponent(req.file.filename)}`,
      storage_path: storagePath,
      mime: req.file.mimetype,
      size_bytes: stats.size,
      sort_order: Number(req.body?.sort_order) || 0
    });

    return res.status(201).json({ ok: true, media });
  } catch (e) {
    console.error('uploadMedia error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function addVideoLink(req, res) {
  try {
    const productId = asUuid(req.params.productId);
    if (!productId) return res.status(400).json({ ok: false, message: 'productId inválido' });

    const url = safeText(req.body?.url, 2000);
    if (!url || !/^https?:\/\//i.test(url)) {
      return res.status(400).json({ ok: false, message: 'URL inválida' });
    }

    const media = await productMediaModel.createMedia({
      product_id: productId,
      kind: 'cover_video',
      url,
      storage_path: null,
      mime: 'text/url',
      size_bytes: null,
      sort_order: Number(req.body?.sort_order) || 0
    });

    return res.status(201).json({ ok: true, media });
  } catch (e) {
    console.error('addVideoLink error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function setMediaActive(req, res) {
  try {
    const id = asUuid(req.params.mediaId);
    if (!id) return res.status(400).json({ ok: false, message: 'mediaId inválido' });

    const updated = await productMediaModel.setActive(id, req.body?.is_active);
    if (!updated) return res.status(404).json({ ok: false, message: 'No encontrado' });
    return res.json({ ok: true, media: updated });
  } catch (e) {
    console.error('setMediaActive error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function setMediaOrder(req, res) {
  try {
    const id = asUuid(req.params.mediaId);
    if (!id) return res.status(400).json({ ok: false, message: 'mediaId inválido' });

    const updated = await productMediaModel.setOrder(id, req.body?.sort_order);
    if (!updated) return res.status(404).json({ ok: false, message: 'No encontrado' });
    return res.json({ ok: true, media: updated });
  } catch (e) {
    console.error('setMediaOrder error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function deleteMedia(req, res) {
  try {
    const id = asUuid(req.params.mediaId);
    if (!id) return res.status(400).json({ ok: false, message: 'mediaId inválido' });

    const removed = await productMediaModel.remove(id);
    if (!removed) return res.status(404).json({ ok: false, message: 'No encontrado' });

    // Delete file if stored locally.
    if (removed.storage_path) {
      try {
        fs.unlinkSync(removed.storage_path);
      } catch (_) {}
    }

    return res.json({ ok: true, media: removed });
  } catch (e) {
    console.error('deleteMedia error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function uploadFile(req, res) {
  try {
    const productId = asUuid(req.params.productId);
    if (!productId) return res.status(400).json({ ok: false, message: 'productId inválido' });

    const platform = safeText(req.body?.platform, 30);
    const file_type = safeText(req.body?.file_type, 30);
    const display_name = safeText(req.body?.display_name, 200) || 'Descarga';
    const version = safeText(req.body?.version, 50) || null;
    const requires_license = Boolean(req.body?.requires_license);

    if (!['android','windows','pwa','web','manual','other'].includes(platform)) {
      return res.status(400).json({ ok: false, message: 'platform inválido' });
    }

    if (!['apk','aab','exe','msi','zip','pdf','url','other'].includes(file_type)) {
      return res.status(400).json({ ok: false, message: 'file_type inválido' });
    }

    // URL-only entries (PWA/Web links)
    if (file_type === 'url') {
      const url = safeText(req.body?.url, 2000);
      if (!url || !/^https?:\/\//i.test(url)) {
        return res.status(400).json({ ok: false, message: 'url inválida' });
      }

      const created = await productFilesModel.createFile({
        product_id: productId,
        platform,
        file_type,
        display_name,
        version,
        url,
        storage_path: null,
        size_bytes: null,
        checksum_sha256: null,
        is_active: true,
        requires_license
      });

      return res.status(201).json({ ok: true, file: created });
    }

    if (!req.file) {
      return res.status(400).json({ ok: false, message: 'Archivo requerido' });
    }

    const storagePath = req.file.path;
    const stats = fs.statSync(storagePath);

    const created = await productFilesModel.createFile({
      product_id: productId,
      platform,
      file_type,
      display_name,
      version,
      url: `/api/public/download/${encodeURIComponent(req.file.filename)}`,
      storage_path: storagePath,
      size_bytes: stats.size,
      checksum_sha256: null,
      is_active: true,
      requires_license
    });

    return res.status(201).json({ ok: true, file: created });
  } catch (e) {
    console.error('uploadFile error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function setFileActive(req, res) {
  try {
    const id = asUuid(req.params.fileId);
    if (!id) return res.status(400).json({ ok: false, message: 'fileId inválido' });

    const updated = await productFilesModel.setActive(id, req.body?.is_active);
    if (!updated) return res.status(404).json({ ok: false, message: 'No encontrado' });
    return res.json({ ok: true, file: updated });
  } catch (e) {
    console.error('setFileActive error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function deleteFile(req, res) {
  try {
    const id = asUuid(req.params.fileId);
    if (!id) return res.status(400).json({ ok: false, message: 'fileId inválido' });

    const removed = await productFilesModel.remove(id);
    if (!removed) return res.status(404).json({ ok: false, message: 'No encontrado' });

    if (removed.storage_path) {
      try {
        fs.unlinkSync(removed.storage_path);
      } catch (_) {}
    }

    return res.json({ ok: true, file: removed });
  } catch (e) {
    console.error('deleteFile error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function serveMediaFile(req, res) {
  try {
    const id = asUuid(req.params.mediaId);
    if (!id) return res.status(400).json({ ok: false, message: 'mediaId inválido' });

    const { pool } = require('../db/pool');
    const rowRes = await pool.query(
      `SELECT storage_path, mime
       FROM product_media
       WHERE id = $1
       LIMIT 1`,
      [id]
    );

    const row = rowRes.rows[0];
    if (!row) return res.status(404).json({ ok: false, message: 'No encontrado' });

    const filePath = row.storage_path;
    if (!filePath || !fs.existsSync(filePath)) {
      return res.status(404).json({ ok: false, message: 'Archivo no encontrado' });
    }

    if (row.mime) res.setHeader('Content-Type', row.mime);
    return res.sendFile(filePath);
  } catch (e) {
    console.error('serveMediaFile error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function downloadFile(req, res) {
  try {
    const id = asUuid(req.params.fileId);
    if (!id) return res.status(400).json({ ok: false, message: 'fileId inválido' });

    const { pool } = require('../db/pool');
    const rowRes = await pool.query(
      `SELECT storage_path, display_name
       FROM product_files
       WHERE id = $1
       LIMIT 1`,
      [id]
    );

    const row = rowRes.rows[0];
    if (!row) return res.status(404).json({ ok: false, message: 'No encontrado' });

    const filePath = row.storage_path;
    if (!filePath || !fs.existsSync(filePath)) {
      return res.status(404).json({ ok: false, message: 'Archivo no encontrado' });
    }

    return res.download(filePath, row.display_name || path.basename(filePath));
  } catch (e) {
    console.error('downloadFile error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

module.exports = {
  listProducts,
  getProduct,
  createProduct,
  updateProduct,
  deleteProduct,
  setStatus,
  uploadImage,
  uploadBinary,
  uploadMedia,
  addVideoLink,
  setMediaActive,
  setMediaOrder,
  deleteMedia,
  uploadFile,
  setFileActive,
  deleteFile,
  serveMediaFile,
  downloadFile
};
