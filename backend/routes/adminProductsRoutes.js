const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const controller = require('../controllers/adminProductsController');

const router = express.Router();

router.use(isAdmin);

router.get('/products', controller.listProducts);
router.post('/products', controller.createProduct);
router.get('/products/:id', controller.getProduct);
router.put('/products/:id', controller.updateProduct);
router.delete('/products/:id', controller.deleteProduct);

router.put('/products/:id/status', controller.setStatus);

// Media uploads
router.post(
  '/products/:productId/media/upload',
  controller.uploadImage.single('file'),
  controller.uploadMedia
);
router.post('/products/:productId/media/video-link', controller.addVideoLink);
router.put('/products/media/:mediaId/active', controller.setMediaActive);
router.put('/products/media/:mediaId/order', controller.setMediaOrder);
router.delete('/products/media/:mediaId', controller.deleteMedia);

// Files uploads
router.post(
  '/products/:productId/files/upload',
  controller.uploadBinary.single('file'),
  controller.uploadFile
);
router.put('/products/files/:fileId/active', controller.setFileActive);
router.delete('/products/files/:fileId', controller.deleteFile);

// Admin-only preview/download for draft content
router.get('/products/media/:mediaId/file', controller.serveMediaFile);
router.get('/products/files/:fileId/download', controller.downloadFile);

module.exports = router;
