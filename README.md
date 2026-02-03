# FULLTECHPOS Backend Licencias

Backend Node/Express + PostgreSQL para licencias, multi-empresa, sync y backups.

## Modo solo licencias (recomendado para evitar “sancocho”)
Si este deploy/DB es únicamente para licenciamiento (sin POS/sync/backups), puedes activar:

- `LICENSE_ONLY=1`

Efectos:
- No monta rutas `/api/auth`, `/api/sync`, `/api/backup`.
- `npm run migrate` ejecuta solo migraciones de licencias (allowlist).

## Novedades
- Soporte **multi-proyecto**: una misma instalación puede manejar licencias de varios productos/proyectos.
- Exportación de **archivo de licencia offline** firmado (para clientes sin internet).

## Run
- `npm install`
- `npm run start`

## Migraciones
- `npm run migrate`

Incluye una migración que crea `projects` y agrega `project_id` a licencias.

## Port
- Default: `3000` (override with `PORT`)

## Multi-proyecto (Projects)
- Proyecto por defecto: `DEFAULT` (compatibilidad con clientes viejos).

Este backend es **multi-proyecto**: cada licencia pertenece a un `project_id` (y se puede resolver por `project_code`).

Endpoints (admin):
- `GET /api/admin/projects`
- `POST /api/admin/projects` body: `{ "code": "POS", "name": "FULLTECH POS" }`

Licencias (admin):
- `POST /api/admin/licenses` body admite `project_code` o `project_id`.
- `GET /api/admin/licenses?project_code=POS` filtra por proyecto.

Licencias (app escritorio):
- `POST /api/licenses/activate` body admite `project_code` o `project_id`.
- `POST /api/licenses/check` body admite `project_code` o `project_id`.

## Prueba (DEMO) automática
Endpoint público para crear/recuperar una licencia DEMO y activarla en un dispositivo.

- `POST /api/licenses/start-demo`

Body mínimo:
```json
{
	"nombre_negocio": "Mi Empresa",
	"contacto_email": "cliente@correo.com",
	"contacto_telefono": "8290000000",
	"device_id": "MI-PC-001",
	"project_code": "FULLPOS"
}
```

Notas:
- Si envías `project_code` y no existe el proyecto, se auto-crea.
- La duración y el máximo de dispositivos de la DEMO se controlan desde `license_config` (panel admin: “License Config”).

Si no se envía proyecto, el backend usa `DEFAULT`.

## Archivo de licencia offline (sin internet)
El backend puede exportar un archivo JSON firmado con **Ed25519**. El cliente (app) puede validar la firma usando sólo la **clave pública**.

### Configurar llaves
1) Generar llaves:
- `node scripts/generate-license-signing-keys.js`

2) Ponerlas en `.env.local` (recomendado) o `.env`:
- `LICENSE_SIGN_PUBLIC_KEY` (PEM)
- `LICENSE_SIGN_PRIVATE_KEY` (PEM)

### Descargar archivo (.lic.json)
- `GET /api/admin/licenses/:id/license-file?download=1`
- Opcional (atar a un equipo): `GET /api/admin/licenses/:id/license-file?device_id=MI-PC&download=1`
- Opcional (si está PENDIENTE y no tiene fechas): `GET /api/admin/licenses/:id/license-file?ensure_active=true&download=1`

Nota: la revocación/bloqueo no se puede “forzar” offline; el archivo fija el período de validez (fecha_inicio/fecha_fin).

## Reset de datos (pruebas limpias)
Si quieres dejar las tablas de licencias vacías para probar desde cero (sin borrar el esquema):

- Preview (solo lectura): `npm run db:reset:preview`
- Reset (borra filas de licencias): `npm run db:reset:licensing`

Esto borra datos de `license_activations`, `licenses`, `customers`.

Opcional (dejar solo el proyecto `DEFAULT`):
- `node backend/db/resetLicensingData.js reset --yes --drop-nondefault-projects`
