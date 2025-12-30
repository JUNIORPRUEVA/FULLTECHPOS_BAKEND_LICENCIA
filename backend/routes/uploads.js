/**
 * RUTAS DE UPLOAD
 * Maneja la subida de instaladores y gestión de versiones
 */

const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const router = express.Router();

// ==========================================
// CONFIGURACIÓN DE MULTER
// ==========================================

// Crear carpeta /descargas (en la raíz del proyecto) si no existe
const descargasPath = path.join(__dirname, '../../descargas');
if (!fs.existsSync(descargasPath)) {
  fs.mkdirSync(descargasPath, { recursive: true });
}

// Configurar almacenamiento
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, descargasPath);
  },
  filename: (req, file, cb) => {
    // Evitar sobreescritura: prefijo con timestamp
    const safeOriginal = file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
    cb(null, `${Date.now()}-${safeOriginal}`);
  }
});

// Filtro de archivos (solo .zip, .exe, .msi)
const fileFilter = (req, file, cb) => {
  const allowedExts = ['.zip', '.exe', '.msi', '.tar', '.gz'];
  const fileExt = path.extname(file.originalname).toLowerCase();

  if (allowedExts.includes(fileExt)) {
    cb(null, true);
  } else {
    cb(new Error('Tipo de archivo no permitido. Use: .zip, .exe, .msi, .tar, .gz'));
  }
};

const upload = multer({
  storage: storage,
  fileFilter: fileFilter,
  limits: {
    fileSize: 500 * 1024 * 1024 // 500 MB máximo
  }
});

// ==========================================
// RUTAS
// ==========================================

/**
 * POST /api/upload-installer
 * Subir nuevo instalador
 * 
 * Form-data:
 * - installer: archivo
 * - version: (opcional) número de versión (ej: 1.0.0)
 * - description: (opcional) descripción
 * 
 * Headers:
 * - x-session-id: ID de sesión válido
 */
router.post('/upload-installer', upload.single('installer'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: 'No se subió ningún archivo'
      });
    }

    // Obtener información del archivo
    const fileStats = fs.statSync(path.join(descargasPath, req.file.filename));
    const fileSizeKB = (fileStats.size / 1024).toFixed(2);
    const fileSizeMB = (fileStats.size / (1024 * 1024)).toFixed(2);

    // Crear entrada de versión
    const newVersion = {
      id: Date.now().toString(),
      nombre: req.file.filename,
      ruta: `descargas/${req.file.filename}`,
      tamaño: fileSizeKB > 1024 ? `${fileSizeMB} MB` : `${fileSizeKB} KB`,
      tamanoBites: fileStats.size,
      fechaSubida: new Date().toISOString(),
      descripcion: req.body.description || '',
      version: req.body.version || '1.0.0'
    };

    // Leer versiones actuales
    const versionsPath = path.join(__dirname, '../versions.json');
    let versions = [];

    if (fs.existsSync(versionsPath)) {
      try {
        versions = JSON.parse(fs.readFileSync(versionsPath, 'utf8'));
      } catch (e) {
        versions = [];
      }
    }

    // Agregar nueva versión
    versions.push(newVersion);

    // Guardar en JSON
    fs.writeFileSync(versionsPath, JSON.stringify(versions, null, 2));

    res.json({
      success: true,
      message: 'Instalador subido correctamente',
      version: newVersion
    });

  } catch (error) {
    // Eliminar archivo si hubo error al guardar
    if (req.file) {
      fs.unlinkSync(path.join(descargasPath, req.file.filename));
    }

    res.status(500).json({
      success: false,
      message: 'Error al subir instalador',
      error: error.message
    });
  }
});

module.exports = router;
