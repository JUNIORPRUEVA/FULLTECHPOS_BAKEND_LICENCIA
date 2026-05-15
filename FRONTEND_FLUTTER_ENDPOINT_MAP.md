# FRONTEND_FLUTTER_ENDPOINT_MAP

Mapeo auditado desde frontend legacy (`assets/js/*.js`, `admin/*.html`) y rutas backend (`backend/server.js`, `backend/routes/*.js`).

## Login / Sesion

| Pantalla | Metodo | Endpoint | Payload esperado | Respuesta esperada | Origen legacy | Servicio Flutter |
|---|---|---|---|---|---|---|
| Login admin | POST | `/api/login` | `{ username, password }` | `{ success, sessionId, message }` | `admin/login.html`, `backend/server.js` | `AuthService.login()` |
| Verificar sesion | GET | `/api/verify-session` | Header `x-session-id` | `{ success, username }` | `assets/js/adminCommon.js`, `admin/customers.html` | `AuthService._initialize()` |
| Logout | POST | `/api/logout` | Header `x-session-id` | `{ success }` | `assets/js/adminCommon.js`, `admin/customer-detail.html` | `AuthService.logout()` |

## Dashboard / Panel

| Pantalla | Metodo | Endpoint | Payload esperado | Respuesta esperada | Origen legacy | Servicio Flutter |
|---|---|---|---|---|---|---|
| Panel principal | GET | `/api/admin/saas-dashboard` | Header `x-session-id` | `{ ok, data: { total_companies, active_subscriptions, expired_subscriptions, ... } }` | `admin/admin-hub.html` | `DashboardService.getDashboard()` |
| Conteo clientes (fallback) | GET | `/api/admin/customers?limit=1&page=1` | Query paginacion | `{ ok, total, customers }` | `admin/admin-hub.html` | `CustomersService.listCustomers()` |
| Conteo licencias (fallback) | GET | `/api/admin/licenses?limit=1&page=1` | Query paginacion/filtros | `{ ok, total, licenses }` | `admin/admin-hub.html` | `LicensesService.listLicenses()` |

## Clientes

| Pantalla | Metodo | Endpoint | Payload esperado | Respuesta esperada | Origen legacy | Servicio Flutter |
|---|---|---|---|---|---|---|
| Listar clientes | GET | `/api/admin/customers?page=:page&limit=:limit` | Query paginacion | `{ ok, total, customers[] }` | `admin/customers.html`, `admin/customer-detail.html` | `CustomersService.listCustomers()` |
| Detalle cliente | GET | `/api/admin/customers/:id` | `id` UUID | `{ ok, customer }` | `admin/customer-detail.html` | `CustomersService.getCustomer()` |
| Crear cliente | POST | `/api/admin/customers` | `{ nombre_negocio, contacto_telefono, contacto_nombre?, contacto_email?, rol_negocio?, business_id? }` | `{ ok, customer }` | `admin/customers.html` | `CustomersService.createCustomer()` |
| Asignar business_id | PUT | `/api/admin/customers/:id/business_id` | `{ business_id }` | `{ ok, customer }` | `admin/customer-detail.html` | `CustomersService.setBusinessId()` |
| Eliminar cliente | DELETE | `/api/admin/customers/:id` | `id` UUID | `{ ok, deleted }` | `admin/customer-detail.html` | `CustomersService.deleteCustomer()` |

## Licencias

| Pantalla | Metodo | Endpoint | Payload esperado | Respuesta esperada | Origen legacy | Servicio Flutter |
|---|---|---|---|---|---|---|
| Listar licencias | GET | `/api/admin/licenses?page=:page&limit=:limit&estado=:estado&tipo=:tipo&customer_id=:id` | Query filtros | `{ ok, total, licenses[] }` | `admin/admin-hub.html`, `admin/customer-detail.html` | `LicensesService.listLicenses()` |
| Detalle licencia | GET | `/api/admin/licenses/:id` | `id` UUID | `{ ok, license }` | `admin/customer-detail.html` | `LicensesService.getLicense()` |
| Crear licencia | POST | `/api/admin/licenses` | `{ customer_id, tipo, dias_validez, max_dispositivos?, notas?, project_id?/project_code?, auto_activate?, estado? }` | `{ ok, license }` | `admin/licenses.html`, `backend/controllers/adminLicensesController.js` | `LicensesService.createLicense()` |
| Actualizar licencia | PATCH | `/api/admin/licenses/:id` | `{ tipo?, dias_validez?, estado?, notas? }` | `{ ok, license }` | `admin/licenses.html` | `LicensesService.updateLicense()` |
| Bloquear licencia | PATCH | `/api/admin/licenses/:id/bloquear` | `{ motivo? / notas? }` | `{ ok, license }` | `admin/customer-detail.html` | `LicensesService.blockLicense()` |
| Desbloquear licencia | PATCH | `/api/admin/licenses/:id/desbloquear` | `{}` | `{ ok, license }` | `admin/customer-detail.html` | `LicensesService.unblockLicense()` |
| Activar manual | PATCH | `/api/admin/licenses/:id/activar-manual` | `{}` | `{ ok, license }` | `admin/customer-detail.html` | `LicensesService.activateManual()` |
| Extender dias | PATCH | `/api/admin/licenses/:id/extender-dias` | `{ dias }` | `{ ok, license }` | `admin/licenses.html` | `LicensesService.extendDays()` |
| Eliminar licencia | DELETE | `/api/admin/licenses/:id` | `id` UUID | `{ ok, deleted }` | `admin/customer-detail.html` | `LicensesService.deleteLicense()` |
| Exportar archivo licencia | GET/POST | `/api/admin/licenses/:id/license-file` | query/body `device_id` | archivo / payload export | `admin/licenses.html` | Pendiente Fase 2 |

## Productos

| Pantalla | Metodo | Endpoint | Payload esperado | Respuesta esperada | Origen legacy | Servicio Flutter |
|---|---|---|---|---|---|---|
| Listar productos | GET | `/api/admin/products` | filtros query | `{ ok, products[] }` | `assets/js/adminProductPlans.js`, `assets/js/adminSubscriptions.js` | `CloudResourcePage(productResourceConfig)` |
| CRUD producto | POST/GET/PUT/DELETE | `/api/admin/products/:id?` | payload producto | entidad producto | `assets/js/admin*.js` | Pendiente formularios avanzados |

## Planes

| Pantalla | Metodo | Endpoint | Payload esperado | Respuesta esperada | Origen legacy | Servicio Flutter |
|---|---|---|---|---|---|---|
| Listar planes | GET | `/api/admin/product-plans` | filtros query | `{ ok, plans[] }` | `assets/js/adminProductPlans.js` | `CloudResourcePage(planResourceConfig)` |
| Detalle plan | GET | `/api/admin/product-plans/:id` | `id` | `{ ok, plan }` | `assets/js/adminProductPlans.js` | Vista detalle desde lista |
| Crear plan | POST | `/api/admin/product-plans` | payload plan | `{ ok, plan }` | `assets/js/adminProductPlans.js` | Pendiente formulario avanzado |
| Editar plan | PATCH | `/api/admin/product-plans/:id` | payload parcial | `{ ok, plan }` | `assets/js/adminProductPlans.js` | Pendiente formulario avanzado |
| Habilitar / deshabilitar | PATCH | `/api/admin/product-plans/:id/enable` `/disable` | `{}` | `{ ok }` | `assets/js/adminProductPlans.js` | Pendiente accion directa |

## Suscripciones

| Pantalla | Metodo | Endpoint | Payload esperado | Respuesta esperada | Origen legacy | Servicio Flutter |
|---|---|---|---|---|---|---|
| Listar suscripciones | GET | `/api/admin/subscriptions` | filtros query | `{ ok, subscriptions[] }` | `assets/js/adminSubscriptions.js` | `CloudResourcePage(subscriptionResourceConfig)` |
| Detalle suscripcion | GET | `/api/admin/subscriptions/:id` | `id` | `{ ok, subscription }` | `assets/js/adminSubscriptions.js` | Vista detalle desde lista |
| Crear suscripcion | POST | `/api/admin/subscriptions` | payload | `{ ok, subscription }` | `assets/js/adminSubscriptions.js` | Pendiente formulario avanzado |
| Cambiar estado | PATCH | `/api/admin/subscriptions/:id/status` | `{ status }` | `{ ok, subscription }` | `assets/js/adminSubscriptions.js` | Pendiente accion directa |
| Extender / cancelar / suspender | PATCH | `/api/admin/subscriptions/:id/extend|cancel|suspend` | payload accion | `{ ok }` | `assets/js/adminSubscriptions.js` | Pendiente accion directa |
| Mantenimiento | POST | `/api/admin/subscriptions/run-maintenance` | `{}` | `{ ok }` | `admin/admin-hub.html` | Pendiente accion directa |

## Pagos

| Pantalla | Metodo | Endpoint | Payload esperado | Respuesta esperada | Origen legacy | Servicio Flutter |
|---|---|---|---|---|---|---|
| Listar pagos | GET | `/api/admin/payments` | filtros query | `{ ok, payments[] }` | `assets/js/adminPayments.js` | `CloudResourcePage(paymentResourceConfig)` |
| Detalle pago | GET | `/api/admin/payments/:id` | `id` | `{ ok, payment }` | `assets/js/adminPayments.js` | Vista detalle desde lista |
| Registrar pago manual | POST | `/api/admin/payments` | payload pago | `{ ok, payment }` | `assets/js/adminPayments.js` | Pendiente formulario avanzado |

## Auditoria

| Pantalla | Metodo | Endpoint | Payload esperado | Respuesta esperada | Origen legacy | Servicio Flutter |
|---|---|---|---|---|---|---|
| Listar auditoria | GET | `/api/admin/audit-logs` | filtros query | `{ ok, logs[] }` | `assets/js/adminAuditLogs.js` | `CloudResourcePage(auditResourceConfig)` |

## Usuarios plataforma

| Pantalla | Metodo | Endpoint | Payload esperado | Respuesta esperada | Origen legacy | Servicio Flutter |
|---|---|---|---|---|---|---|
| Listar usuarios plataforma | GET | `/api/admin/platform-users` | filtros query | `{ ok, users[] }` | `assets/js/adminPlatformUsers.js` | `CloudResourcePage(userResourceConfig)` |
| Crear usuario plataforma | POST | `/api/admin/platform-users` | payload usuario | `{ ok, user }` | `assets/js/adminPlatformUsers.js` | Pendiente formulario avanzado |
| Asignar roles | POST | `/api/admin/platform-users/:id/roles` | `{ role_ids }` | `{ ok }` | `assets/js/adminPlatformUsers.js` | Pendiente accion directa |
| Catalogo de roles | GET | `/api/admin/roles` | none | `{ ok, roles[] }` | `assets/js/adminPlatformUsers.js` | Pendiente accion directa |

## Configuracion tienda

| Pantalla | Metodo | Endpoint | Payload esperado | Respuesta esperada | Origen legacy | Servicio Flutter |
|---|---|---|---|---|---|---|
| Obtener configuracion tienda | GET | `/api/admin/store-settings` | none | `{ ok, settings }` | `assets/js/adminStoreSettings.js` | `CloudStoreSettingsPage` |
| Guardar configuracion tienda | PUT | `/api/admin/store-settings` | payload settings | `{ ok, settings }` | `assets/js/adminStoreSettings.js` | `CloudStoreSettingsPage` |

## Otros endpoints detectados (admin)

- `/api/admin/license-config` (GET/PUT) desde `assets/js/adminLicenseConfig.js`.
- `/api/admin/projects` (GET/POST) desde `assets/js/adminProductPlans.js`, `admin/admin-hub.html`.
- `/api/admin/support-reset` y `/api/admin/support-message-config` (configuracion soporte).
