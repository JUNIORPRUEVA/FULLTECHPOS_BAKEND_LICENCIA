# 📋 Guía de Implementación: Sistema de Configuración de Licencias

## ✅ Resumen General

Se ha implementado un sistema completo de configuración de licencias para FULLTECH POS WEB que permite:

1. ⚙️ Definir y gestionar valores predeterminados para tipos de licencias (DEMO y FULL)
2. 🔌 API REST para obtener y actualizar la configuración
3. 🖥️ Interfaz web intuitiva en el panel admin
4. 🔄 Auto-relleno de valores en el formulario de creación de licencias
5. 📊 Control centralizado desde la sección "Config. Licencias"

---

## 📁 Archivos Creados/Modificados

### Backend

#### Migraciones SQL
- **`backend/db/migrations/002_create_license_config.sql`** ✨ NUEVO
  - Crea tabla `license_config` con campos para DEMO y FULL
  - Inserta configuración inicial con valores por defecto
  - Incluye trigger automático para actualizar `updated_at`

#### Servicios
- **`backend/services/licenseConfigService.js`** ✨ NUEVO
  - `getLicenseConfig()` - Obtiene la configuración actual
  - `updateLicenseConfig(payload)` - Actualiza valores específicos
  - Fallback a valores en memoria si la BD falla

#### Controladores
- **`backend/controllers/adminLicenseConfigController.js`** ✨ NUEVO
  - `getConfig()` - GET /api/admin/license-config
  - `updateConfig()` - PUT /api/admin/license-config
  - Validación completa de valores numéricos positivos

- **`backend/controllers/adminLicensesController.js`** 🔧 MODIFICADO
  - Importa `licenseConfigService`
  - En `createLicense()`, usa config como valores por defecto
  - Permite override manual de dias_validez y max_dispositivos

#### Rutas
- **`backend/routes/adminLicenseConfigRoutes.js`** ✨ NUEVO
  - GET / - Obtener configuración
  - PUT / - Actualizar configuración
  - Protegidas con middleware `isAdmin`

- **`backend/server.js`** 🔧 MODIFICADO
  - Importa `adminLicenseConfigRoutes`
  - Registra `/api/admin/license-config`

### Frontend

#### Páginas Admin (HTML)
- **`admin/admin-hub.html`** ✨ NUEVO
  - Panel principal con navegación por sidebar
  - Acceso rápido a todas las secciones
  - Bienvenida y consejos útiles

- **`admin/license-config.html`** ✨ NUEVO
  - Interfaz de configuración de licencias
  - Dos tarjetas: DEMO y FULL
  - Campos para días y dispositivos máximos
  - Guardar y resetear formulario

- **`admin/licenses.html`** ✨ NUEVO
  - Crear nuevas licencias
  - Formulario con auto-relleno por tipo
  - Listado de licencias creadas
  - Estados y validez visual

- **`admin/customers.html`** ✨ NUEVO
  - Placeholder para gestión de clientes
  - Estructura lista para integración completa

#### Scripts JavaScript
- **`assets/js/adminLicenseConfig.js`** ✨ NUEVO
  - `loadLicenseConfig()` - Carga config desde API
  - `getDefaultsForLicenseType(tipo)` - Obtiene defaults
  - `initializeLicenseTypeSelector()` - Configura auto-relleno
  - `saveLicenseConfig(newConfig)` - Guarda cambios

---

## 🚀 Guía de Uso

### Para el Dueño (Admin)

#### 1. Configurar Valores por Defecto
1. Ir a **"Config. Licencias"** en el sidebar del admin
2. Ver los valores actuales de DEMO y FULL
3. Modificar según necesidad:
   - Días de prueba para DEMO (ej: 30)
   - Máx dispositivos DEMO (ej: 2)
   - Días de pago para FULL (ej: 365)
   - Máx dispositivos FULL (ej: 5)
4. Presionar **"Guardar Configuración"**
5. Confirmación visual con mensaje verde

#### 2. Crear Nuevas Licencias
1. Ir a **"Gestionar Licencias"**
2. Rellenar el formulario:
   - Seleccionar Cliente
   - Seleccionar Tipo (DEMO o FULL) → **auto-rellena días y dispositivos**
   - Opcional: Modificar días y dispositivos si necesita valores personalizados
   - Opcional: Agregar notas
3. Presionar **"Crear Licencia"**
4. Ver la lista actualizada abajo

### Para Desarrolladores

#### Endpoints de API

**GET /api/admin/license-config**
```bash
# Obtener configuración actual
curl -H "x-session-id: YOUR_SESSION" http://localhost:3000/api/admin/license-config

# Respuesta:
{
  "ok": true,
  "config": {
    "demo_dias_validez": 15,
    "demo_max_dispositivos": 1,
    "full_dias_validez": 365,
    "full_max_dispositivos": 2
  }
}
```

**PUT /api/admin/license-config**
```bash
# Actualizar configuración (valores opcionales)
curl -X PUT \
  -H "Content-Type: application/json" \
  -H "x-session-id: YOUR_SESSION" \
  -d '{
    "demo_dias_validez": 30,
    "full_max_dispositivos": 5
  }' \
  http://localhost:3000/api/admin/license-config

# Respuesta:
{
  "ok": true,
  "config": {
    "demo_dias_validez": 30,
    "demo_max_dispositivos": 1,
    "full_dias_validez": 365,
    "full_max_dispositivos": 5
  }
}
```

**POST /api/admin/licenses (Modificado)**
```bash
# Crear licencia - usa config como defaults
curl -X POST \
  -H "Content-Type: application/json" \
  -H "x-session-id: YOUR_SESSION" \
  -d '{
    "customer_id": "uuid-123",
    "tipo": "DEMO"
    // dias_validez y max_dispositivos son opcionales
    // Si no se envían, toma valores de config
  }' \
  http://localhost:3000/api/admin/licenses
```

#### Integración en JavaScript

```javascript
// Cargar configuración
const config = await loadLicenseConfig();
// config = { demo_dias_validez: 15, ... }

// Obtener defaults para un tipo
const demoDefaults = getDefaultsForLicenseType('DEMO');
// demoDefaults = { dias_validez: 15, max_dispositivos: 1 }

// Guardar nueva configuración
const result = await saveLicenseConfig({
  demo_dias_validez: 30,
  full_max_dispositivos: 5
});
```

---

## 🔍 Flujo de Datos

```
┌─────────────────────────────────────────────────────────────┐
│ Panel Admin: license-config.html                             │
│ - Carga config inicial con GET /api/admin/license-config    │
│ - Usuario modifica valores                                   │
│ - PUT /api/admin/license-config con nuevos valores          │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ Backend: adminLicenseConfigController.js                    │
│ - Valida que sean números enteros > 0                       │
│ - Llama a licenseConfigService.updateLicenseConfig()        │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ PostgreSQL: license_config table                            │
│ - UPDATE con nuevos valores                                  │
│ - Trigger automático actualiza updated_at                   │
└──────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────┐
│ Panel Admin: licenses.html                                   │
│ - Usuario selecciona tipo en dropdown                        │
│ - JavaScript carga config con loadLicenseConfig()           │
│ - getDefaultsForLicenseType() rellena auto los campos       │
│ - Usuario puede modificar si necesita personalizar          │
│ - POST /api/admin/licenses                                   │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ Backend: adminLicensesController.createLicense()            │
│ - Si dias_validez NO viene, toma de config según tipo       │
│ - Si max_dispositivos NO viene, toma de config según tipo   │
│ - Generar license_key y crear en BD con estado PENDIENTE    │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ PostgreSQL: licenses table                                  │
│ - Inserta nueva licencia con valores (config o personalizados)
└──────────────────────────────────────────────────────────────┘
```

---

## 📊 Estructura de la Base de Datos

### Tabla: license_config
```sql
CREATE TABLE license_config (
  id UUID PRIMARY KEY DEFAULT '00000000-0000-0000-0000-000000000001'::uuid,
  demo_dias_validez INTEGER NOT NULL DEFAULT 15,
  demo_max_dispositivos INTEGER NOT NULL DEFAULT 1,
  full_dias_validez INTEGER NOT NULL DEFAULT 365,
  full_max_dispositivos INTEGER NOT NULL DEFAULT 2,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
)
```

**Solo contiene 1 registro** con ID fijo para fácil acceso.

---

## ✨ Características Principales

### 1. Auto-relleno Inteligente
```javascript
// Cuando el usuario selecciona DEMO en licenses.html:
1. Se carga la config desde /api/admin/license-config
2. Se buscan los valores: demo_dias_validez y demo_max_dispositivos
3. Se rellenan automáticamente en los campos
4. El usuario puede modificarlos si lo necesita
```

### 2. Valores por Defecto en Backend
```javascript
// En adminLicensesController.createLicense():
if (!dias_validez || dias_validez <= 0) {
  dias_validez = tipo === 'DEMO' 
    ? config.demo_dias_validez 
    : config.full_dias_validez;
}
```

### 3. Validación Completa
- Números enteros positivos
- Rango razonable (1-9999 días, 1-99 dispositivos)
- Mensajes de error claros
- Fallback a valores en memoria si BD falla

### 4. UI Moderna y Responsive
- Sidebar de navegación
- Tarjetas visuales para DEMO y FULL
- Mensajes de éxito/error animados
- Responsive design para móvil

---

## 🧪 Verificación Rápida

### Pruebas a Realizar

1. **Obtener Configuración**
   ```bash
   curl -H "x-session-id: YOUR_SESSION" \
     http://localhost:3000/api/admin/license-config
   ```
   ✅ Debe devolver config con 4 campos

2. **Actualizar Configuración**
   ```bash
   curl -X PUT \
     -H "Content-Type: application/json" \
     -H "x-session-id: YOUR_SESSION" \
     -d '{"demo_dias_validez": 30}' \
     http://localhost:3000/api/admin/license-config
   ```
   ✅ Debe devolver config actualizada

3. **Crear Licencia DEMO sin especificar días**
   ```bash
   curl -X POST \
     -H "Content-Type: application/json" \
     -H "x-session-id: YOUR_SESSION" \
     -d '{
       "customer_id": "uuid-xxx",
       "tipo": "DEMO"
     }' \
     http://localhost:3000/api/admin/licenses
   ```
   ✅ Debe usar demo_dias_validez del config

4. **Crear Licencia FULL con override personalizado**
   ```bash
   curl -X POST \
     -H "Content-Type: application/json" \
     -H "x-session-id: YOUR_SESSION" \
     -d '{
       "customer_id": "uuid-xxx",
       "tipo": "FULL",
       "dias_validez": 500,
       "max_dispositivos": 10
     }' \
     http://localhost:3000/api/admin/licenses
   ```
   ✅ Debe respetar los valores personalizados

5. **Panel Admin - license-config.html**
   - Ir a http://localhost:3000/admin/license-config.html
   - ✅ Debe cargar valores actuales
   - ✅ Modificar y guardar debe funcionar
   - ✅ Ver mensaje verde de confirmación

6. **Panel Admin - licenses.html**
   - Ir a http://localhost:3000/admin/licenses.html
   - Seleccionar tipo DEMO
   - ✅ Campos de días y dispositivos deben rellenarse
   - Cambiar a FULL
   - ✅ Campos deben actualizarse con nuevos valores

---

## 🔐 Seguridad

- ✅ Todos los endpoints están protegidos con middleware `isAdmin`
- ✅ Validación de entrada en backend
- ✅ Validación de tipos de datos
- ✅ Rango de valores validado
- ✅ Sesión requerida para acceso

---

## 📝 Notas Importantes

1. **Migración SQL**: Ejecutar `002_create_license_config.sql` antes de usar
2. **Valores por Defecto**: Si la BD falla, usa valores en memoria
3. **Modificaciones Futuras**: Solo afectan licencias nuevas, no las existentes
4. **Base de Datos**: Solo 1 registro en license_config (ID fijo)
5. **Timestamp**: `updated_at` se actualiza automáticamente con trigger

---

## 🎯 Próximos Pasos (Opcional)

1. **Completar Gestión de Clientes**: Implementar CRUD completo
2. **Auditoría**: Log de cambios en configuración
3. **Roles**: Diferentes niveles de permisos
4. **Múltiples Configuraciones**: Una por tipo de negocio
5. **Historial**: Guardar histórico de cambios

---

## 📞 Soporte Técnico

### Errores Comunes

| Error | Causa | Solución |
|-------|-------|----------|
| "Sesión no válida" | sessionId expirada | Ir a login |
| 404 en /api/admin/license-config | Ruta no registrada | Reiniciar servidor |
| "Error al cargar configuración" | BD no disponible | Verificar conexión PostgreSQL |
| Auto-relleno no funciona | adminLicenseConfig.js no cargado | Verificar ruta en HTML |

### Logs Útiles
```bash
# Ver logs del backend
tail -f backend.log

# Queries a BD
SELECT * FROM license_config;
SELECT id, tipo, dias_validez, max_dispositivos FROM licenses;
```

---

**Implementación Completada ✅**

Todos los archivos están listos. Solo ejecuta la migración SQL y reinicia el servidor.
