# Plan de Implementación - Sistema de Archivos de Licencia

## Estado Actual - COMPLETADO ✓

### Backend
- [x] `backend/utils/licenseFile.js` - Utilidad de firma Ed25519 con generación/verificación
- [x] `backend/keys/` - Claves PEM (private.pem, public.pem)
- [x] `backend/controllers/adminLicensesController.js` - `exportLicenseFile` endpoint
- [x] `backend/routes/adminLicensesRoutes.js` - Rutas `GET /:id/license-file` y `POST /:id/license-file`
- [x] `backend/controllers/publicLicenseController.js` - `importLicenseFromFile` endpoint
- [x] `backend/routes/publicLicenseRoutes.js` - Ruta `POST /public/license/import-activation`
- [x] `backend/controllers/adminLicensesController.js` - `resetLicenseActivations` endpoint
- [x] `backend/routes/adminLicensesRoutes.js` - Ruta `POST /:id/reset-activations`
- [x] `backend/server.js` - Carga de claves PEM al iniciar
- [x] `.env` - Variables `LICENSE_PRIVATE_KEY_PATH` y `LICENSE_PUBLIC_KEY_PATH`

### Frontend Appyra Admin
- [x] `frontend_flutter/lib/features/licenses/pages/licenses_page.dart` - Botón "Descargar licencia" con implementación real usando `universal_html`
- [x] `frontend_flutter/lib/features/licenses/services/licenses_service.dart` - Método `downloadLicenseFile`
- [x] `frontend_flutter/lib/features/licenses/widgets/license_detail_panel.dart` - Callback `onDownloadLicense`
- [x] Formato `.fulllicense` con nombre profesional

### FullCredit (App Cliente)
- [x] `lib/features/license/services/license_import_service.dart` - Servicio completo de importación
- [x] `lib/features/license/services/license_api_service.dart` - Método `importLicenseFromFile`
- [x] `lib/features/license/ui/license_gate_screen.dart` - Botón "Importar licencia"
- [x] `lib/features/license/ui/license_payment_screen.dart` - Botón "Importar licencia"
- [x] Validación de estructura, project_code, firma, expiración
- [x] Soporte offline temporal
- [x] Activación remota vía backend

### Formato del Archivo (.fulllicense)
- [x] `schema_version`, `file_type`, `generated_at`
- [x] `payload` con datos completos de licencia
- [x] `signature` con firma Ed25519
- [x] `constraints` con reglas de importación
- [x] Extensión `.fulllicense`

### Pruebas Realizadas
- [x] Descarga desde Appyra Admin
- [x] Importación en FullCredit
- [x] Firma inválida
- [x] Proyecto incorrecto
- [x] Device ID diferente
- [x] Licencia vencida
- [x] Máximo de dispositivos
- [x] Modo offline

## Resumen de Archivos Creados/Modificados

### Nuevos Archivos
1. `backend/utils/licenseFile.js` - Utilidad de firma Ed25519
2. `backend/keys/private.pem` - Clave privada
3. `backend/keys/public.pem` - Clave pública
4. `scripts/generate-license-signing-keys.js` - Script para generar claves
5. `scripts/smoke-offline-licensefile-local.js` - Script de prueba offline
6. `scripts/smoke-real-offline-export.js` - Script de prueba real
7. `../../FULLCREDIT/fullcredit/lib/features/license/services/license_import_service.dart` - Servicio de importación

### Archivos Modificados
1. `backend/controllers/adminLicensesController.js` - exportLicenseFile + resetLicenseActivations
2. `backend/routes/adminLicensesRoutes.js` - Nuevas rutas
3. `backend/controllers/publicLicenseController.js` - importLicenseFromFile
4. `backend/routes/publicLicenseRoutes.js` - Nueva ruta
5. `backend/server.js` - Carga de claves PEM
6. `.env` - Variables de entorno
7. `frontend_flutter/lib/features/licenses/pages/licenses_page.dart` - _downloadLicense implementado
8. `frontend_flutter/lib/features/licenses/services/licenses_service.dart` - downloadLicenseFile
9. `frontend_flutter/lib/features/licenses/widgets/license_detail_panel.dart` - onDownloadLicense callback
10. `../../FULLCREDIT/fullcredit/lib/features/license/services/license_api_service.dart` - importLicenseFromFile
11. `../../FULLCREDIT/fullcredit/lib/features/license/ui/license_gate_screen.dart` - Botón importar
12. `../../FULLCREDIT/fullcredit/lib/features/license/ui/license_payment_screen.dart` - Botón importar
