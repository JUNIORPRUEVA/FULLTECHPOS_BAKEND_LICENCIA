# ⚡ Guía Rápida de Configuración de Licencias

## 🚀 Inicio Rápido (3 pasos)

### 1. Ejecutar la Migración SQL
```bash
# Conectar a PostgreSQL y ejecutar:
psql -U tu_usuario -d tu_db -f backend/db/migrations/002_create_license_config.sql

# Verificar que se creó:
SELECT * FROM license_config;
```

### 2. Reiniciar el Servidor
```bash
npm start
# o 
node backend/server.js
```

### 3. Acceder al Panel Admin
1. Login en http://localhost:3000/admin/login.html
2. Click en "Config. Licencias" en el sidebar
3. Ajustar valores y guardar

---

## 📋 Menú del Admin

Nuevo sidebar con 5 opciones:
```
🏠 Panel Principal        → admin-hub.html
📤 Gestionar Instaladores → dashboard.html
👥 Gestionar Clientes     → customers.html  
📜 Gestionar Licencias    → licenses.html
⚙️ Config. Licencias      → license-config.html
```

---

## 🎯 Endpoints API

| Método | URL | Descripción |
|--------|-----|-------------|
| GET | `/api/admin/license-config` | Obtener configuración actual |
| PUT | `/api/admin/license-config` | Actualizar configuración |
| POST | `/api/admin/licenses` | Crear licencia (ahora usa config) |

---

## 💾 Base de Datos

Tabla: `license_config`
```sql
-- Solo 1 registro (ID fijo)
id: 00000000-0000-0000-0000-000000000001
demo_dias_validez: 15         (días de prueba)
demo_max_dispositivos: 1      (máx dispositivos en DEMO)
full_dias_validez: 365        (días de pago)
full_max_dispositivos: 2      (máx dispositivos en FULL)
```

---

## 📁 Archivos Clave

```
Backend:
  ✅ backend/db/migrations/002_create_license_config.sql
  ✅ backend/services/licenseConfigService.js
  ✅ backend/controllers/adminLicenseConfigController.js
  ✅ backend/routes/adminLicenseConfigRoutes.js
  ✅ backend/controllers/adminLicensesController.js (MODIFICADO)
  ✅ backend/server.js (MODIFICADO)

Frontend:
  ✅ admin/admin-hub.html
  ✅ admin/license-config.html
  ✅ admin/licenses.html
  ✅ admin/customers.html
  ✅ assets/js/adminLicenseConfig.js
```

---

## 🔄 Flujo de Uso

### Configurar Valores
```
Admin Panel
    ↓
license-config.html
    ↓
PUT /api/admin/license-config
    ↓
PostgreSQL (license_config table)
    ↓
✅ Confirmación
```

### Crear Licencia con Auto-relleno
```
Admin Panel
    ↓
licenses.html
    ↓
SELECT Tipo (DEMO/FULL)
    ↓
JavaScript carga config
    ↓
Auto-rellena días y dispositivos
    ↓
Usuario puede cambiar si quiere
    ↓
POST /api/admin/licenses
    ↓
Backend usa valores del request o del config
    ↓
✅ Licencia creada
```

---

## ✨ Características

| Característica | Estado |
|---|---|
| Tabla de configuración | ✅ Implementado |
| Endpoints API | ✅ Implementado |
| Panel de configuración | ✅ Implementado |
| Auto-relleno en formulario | ✅ Implementado |
| Validación de valores | ✅ Implementado |
| Respuesta a errores | ✅ Implementado |
| Responsive design | ✅ Implementado |
| Sidebar de navegación | ✅ Implementado |
| Autenticación | ✅ Implementado |

---

## 🧪 Prueba Rápida

### 1. Con cURL
```bash
# Obtener config actual
curl -H "x-session-id: YOUR_SESSION" \
  http://localhost:3000/api/admin/license-config

# Actualizar
curl -X PUT \
  -H "Content-Type: application/json" \
  -H "x-session-id: YOUR_SESSION" \
  -d '{"demo_dias_validez": 30}' \
  http://localhost:3000/api/admin/license-config
```

### 2. En el Panel
1. Ir a http://localhost:3000/admin/license-config.html
2. Cambiar valores
3. Presionar "Guardar Configuración"
4. Ver confirmación verde

### 3. Crear Licencia
1. Ir a http://localhost:3000/admin/licenses.html
2. Seleccionar cliente
3. Cambiar tipo a DEMO
4. ✅ Verás que se rellenaron automáticamente
5. Presionar "Crear Licencia"

---

## ⚠️ Importante

- **Migración**: Ejecutar SQL antes de usar
- **Sesión**: Necesitas estar logueado en el admin
- **Valores Nuevos**: Solo aplican a licencias futuras
- **BD**: Si cae, tiene fallback a valores en memoria

---

## 🔧 Solución de Problemas

### "404 en /api/admin/license-config"
- [ ] Verificar que server.js importa adminLicenseConfigRoutes
- [ ] Verificar que está registrada: `app.use('/api/admin/license-config', ...)`
- [ ] Reiniciar servidor: `npm start`

### "No se rellenan los campos automáticamente"
- [ ] Verificar que `assets/js/adminLicenseConfig.js` está en `<script>`
- [ ] Abrir DevTools y verificar que no hay errores
- [ ] Verificar que sessionId es válida

### "Sesión expirada"
- [ ] Volver a login en http://localhost:3000/admin/login.html
- [ ] Credenciales: las del archivo `.env`

---

## 📚 Documentación Completa

Ver: [IMPLEMENTACION_CONFIGURACION_LICENCIAS.md](./IMPLEMENTACION_CONFIGURACION_LICENCIAS.md)

---

**Listo para usar! 🎉**
