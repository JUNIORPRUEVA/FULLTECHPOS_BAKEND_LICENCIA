# FRONTEND FLUTTER MIGRATION PLAN

## Objetivo
Reemplazar el frontend HTML/CSS/JS por Flutter Web en carpeta separada (`frontend_flutter`) sin tocar backend ni romper rutas legacy hasta completar migracion.

## Fase 1 (base completada)
1. Auditar endpoints reales del frontend legacy y backend.
2. Crear base Flutter Web profesional (tema, layout, router, API client, auth/session).
3. Migrar pantallas funcionales:
   - Login (`/login`)
   - Panel (`/admin/panel`)
   - Clientes (`/admin/clientes`)
   - Licencias (`/admin/licencias`)
4. Enlazar pantallas SaaS pendientes contra API real:
   - Productos (`/admin/productos`)
   - Planes (`/admin/planes`)
   - Suscripciones (`/admin/suscripciones`)
   - Pagos (`/admin/pagos`)
   - Auditoria (`/admin/auditoria`)
   - Usuarios (`/admin/usuarios`)
   - Configuracion tienda (`/admin/configuracion-tienda`)
5. Validacion tecnica:
   - `flutter pub get`
   - `flutter analyze`
   - `flutter run -d chrome`

## Criterios de arquitectura aplicados
- Frontend separado: `frontend_flutter`.
- Backend intacto (sin cambios de endpoints).
- Datos en la nube: Flutter consume el backend por HTTP; no abre ni requiere DB local.
- `API_BASE_URL` por `--dart-define` para apuntar a backend cloud desde desarrollo.
- En produccion, `APP_ENV=production` permite usar el mismo origen donde se publique backend + Flutter.
- Session via `x-session-id` (compatible con backend actual).
- `ApiClient` centralizado para GET/POST/PUT/PATCH/DELETE.
- Manejo de errores HTTP 400/401/403/404/409/500.
- Timeout global de requests.
- Logs solo en debug.
- Sidebar unico, sin doble appbar/sidebars.
- Responsive desktop/movil con drawer en movil.
- Estados de carga por pantalla: loading/error/empty/data + refresh.

## Fase 2 recomendada
1. Completar formularios avanzados de creacion/edicion para Productos, Planes, Suscripciones, Pagos y Usuarios.
2. Ajustar PWA Flutter (manifest/iconos/versionado cache).
3. Pruebas E2E completas contra backend cloud y DB cloud.
4. Publicar Flutter junto al backend o bajo ruta separada (`/admin-flutter`) y validar CORS si queda en otro dominio.

## Estrategia de rollout
1. Mantener frontend legacy activo en paralelo.
2. Publicar Flutter en ruta separada (ej. `/admin-flutter`).
3. Ejecutar smoke tests funcionales contra la nube.
4. Cambiar trafico gradualmente.
5. Retirar HTML legacy solo cuando todas las pantallas esten migradas y validadas.
