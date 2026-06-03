# INFORME DE AUDITORÍA: businessId

## Fecha: 3 de junio de 2026
## Proyectos auditados: FULLTECHPOS_BAKEND_LICENCIA (backend) + FULLPOS (frontend Flutter)

---

## A. RESUMEN EJECUTIVO

### ¿Qué se encontró?

Se identificaron **múltiples fuentes de verdad** para el businessId, con **lógica de regeneración automática** y **sobrescritura silenciosa** en varios puntos críticos del sistema. El businessId puede cambiar sin intervención del usuario debido a:

1. ~~**Regeneración automática en el frontend** cuando el businessId local está vacío (`ensureBusinessId()` genera un UUID v4 nuevo).~~ **CORREGIDO**: `ensureBusinessId()` ahora es un alias de `getBusinessId()` y NO genera UUID.
2. ~~**Sobrescritura desde el cache de licencia** (`LicenseInfo.businessId`) sobre el valor local de `BusinessIdentityStorage`.~~ **CORREGIDO**: Ahora usa `BusinessIdentityGuard.resolveAndApply()` que bloquea sobrescrituras no autorizadas.
3. ~~**Reconciliación forzada** en `BusinessRegistrationService._resolveCanonicalBusinessId()` que sobrescribe el businessId local con el del cache de licencia.~~ **CORREGIDO**: Ahora usa `BusinessIdentityGuard.resolveAndApply()` con `allowOverwrite: false`.
4. ~~**Reconciliación desde el backend** cuando hay `BUSINESS_ID_CONFLICT`, el backend devuelve un `existing_business_id` y el frontend lo sobrescribe localmente.~~ **CORREGIDO**: Ahora lanza `BusinessIdentityConflictException` en lugar de sobrescribir.
5. **Posible regeneración en el panel admin** mediante el endpoint `assignBusinessId` que puede forzar un nuevo businessId. **MITIGADO**: Se agregó validación y log de advertencia.
6. ~~**El `debugResetLicensingOnThisDevice()`** borra la identidad completa del negocio, incluyendo el businessId.~~ **CORREGIDO**: Ahora usa `clearProfile()` que NO borra businessId.

### Causa más probable del problema (ANTES de la corrección)

**CRÍTICO**: El businessId se generaba localmente en el frontend como UUID v4 cuando no existía (`BusinessIdentityStorage.ensureBusinessId()`), pero luego podía ser sobrescrito por:
- El valor proveniente del cache de licencia (`LicenseInfo.businessId`)
- El valor devuelto por el backend en `BUSINESS_ID_CONFLICT`
- El valor del archivo de licencia offline

Esto creaba una **carrera de condiciones** donde el orden de las operaciones (carga de licencia vs. registro vs. sincronización) determinaba qué businessId terminaba siendo el "canónico".

### Estado actual: **CORREGIDO** (ver sección H para detalle de cambios aplicados)
### Nivel de gravedad original: **CRÍTICO**

---

## B. MAPA DE IDENTIDAD ACTUAL

### ¿De dónde sale el businessId?

| Fuente | Dónde se genera | Persistencia | ¿Es autoritativa? |
|--------|----------------|--------------|-------------------|
| **Frontend: BusinessIdentityStorage** | `ensureBusinessId()` → `IdUtils.uuidV4()` | SharedPreferences (`business.business_id_v1`) | **SÍ** (primera fuente) |
| **Frontend: LicenseInfo cache** | `LicenseStorage` guarda `LicenseInfo.businessId` | SharedPreferences (`license.lastInfo`) | **SÍ** (puede sobrescribir) |
| **Backend: customers.business_id** | Creado por `businessesController.register()` o admin | PostgreSQL (`customers.business_id`) | **SÍ** (fuente cloud) |
| **Archivo de licencia offline** | `payload.business_id` en el `.fulllicense` | Archivo JSON firmado | **SÍ** (puede sobrescribir) |
| **Backend: BUSINESS_ID_CONFLICT** | `existing_business_id` en respuesta 409 | En memoria durante registro | **SÍ** (fuerza sobrescritura) |
| **Admin panel** | `assignBusinessId()` genera `BIZ-{hex}` | PostgreSQL | **SÍ** (puede regenerar) |

### ¿Dónde se guarda?

1. **SharedPreferences** (clave `business.business_id_v1`) → `BusinessIdentityStorage`
2. **SharedPreferences** (clave `license.lastInfo`) → `LicenseStorage` (dentro de `LicenseInfo.businessId`)
3. **PostgreSQL** → `customers.business_id` (con unique index parcial)
4. **Archivo `.fulllicense`** → dentro del payload firmado

### ¿Quién lo modifica?

| Acción | Componente | ¿Cuándo? |
|--------|-----------|----------|
| **Genera** | `BusinessIdentityStorage.ensureBusinessId()` | Cuando no existe y se necesita |
| **Genera** | `adminCustomersController.assignBusinessId()` | Admin fuerza regeneración |
| **Sobrescribe** | `BusinessRegistrationService._resolveCanonicalBusinessId()` | Durante registro, si cache de licencia tiene otro valor |
| **Sobrescribe** | `BusinessRegistrationService._registerWithBusinessIdReconcile()` | Cuando backend responde 409 BUSINESS_ID_CONFLICT |
| **Sobrescribe** | `LicenseController.load()` línea 258-260 | Si localBusinessId es null pero cachedBusinessId existe |
| **Sobrescribe** | `LicenseController.applyOfflineLicenseFile()` línea 867-869 | Si archivo tiene business_id y local no existe |
| **Sobrescribe** | `LicensePage._refreshBusinessId()` línea 133-136 | Si licenseState tiene businessId pero local no |
| **Borra** | `BusinessIdentityStorage.clearAll()` | `debugResetLicensingOnThisDevice()` |
| **Borra** | `LicenseStorage.clearAll()` | `clearLocal()` y `debugResetLicensingOnThisDevice()` |

### ¿Qué otros IDs dependen de él?

- **companyTenantKey**: No se encontró evidencia de que se use este concepto en el proyecto.
- **deviceId**: Es independiente, se genera con `SessionManager.ensureTerminalId()`.
- **licenseId**: Es el UUID de la licencia en PostgreSQL, independiente.
- **customer.id**: Es el UUID del cliente en PostgreSQL, independiente.

---

## C. ARCHIVOS SOSPECHOSOS

### CRÍTICOS (pueden cambiar el businessId automáticamente)

#### 1. `@FULLPOS:lib/features/registration/services/business_identity_storage.dart`

| Línea | Función | Qué hace | Riesgo |
|-------|---------|----------|--------|
| 57-64 | `ensureBusinessId()` | Si no existe businessId, **genera un UUID v4 nuevo** | **CRÍTICO**: Si se llama en el momento equivocado, crea un businessId diferente al que el backend tiene registrado |
| 72-86 | `setBusinessId()` | Guarda businessId. Si `overwrite=false` y ya existe, no sobrescribe. Si `overwrite=true`, **sobrescribe sin preguntar** | **CRÍTICO**: `overwrite=true` se usa en `_resolveCanonicalBusinessId()` y `_registerWithBusinessIdReconcile()` |
| 35-45 | `clearAll()` | **Borra** businessId, nombre, rol, teléfono, email, trial | **CRÍTICO**: Elimina la identidad completa del negocio |

#### 2. `@FULLPOS:lib/features/registration/services/business_registration_service.dart`

| Línea | Función | Qué hace | Riesgo |
|-------|---------|----------|--------|
| 24-45 | `_resolveCanonicalBusinessId()` | Si `cachedLicenseBusinessId` existe y es diferente al local, **sobrescribe el local con `overwrite=true`** | **CRÍTICO**: El cache de licencia puede tener un businessId antiguo o de otro contexto |
| 128-156 | `_registerWithBusinessIdReconcile()` | Si backend responde `BUSINESS_ID_CONFLICT` con `existingBusinessId`, **sobrescribe el local con `overwrite=true`** | **CRÍTICO**: El backend puede forzar un cambio de businessId sin validación del usuario |

#### 3. `@FULLPOS:lib/features/license/services/license_controller.dart`

| Línea | Función | Qué hace | Riesgo |
|-------|---------|----------|--------|
| 254-261 | `load()` | Si `localBusinessId` es null pero `cachedBusinessId` (de `LicenseInfo`) existe, **guarda el cached como local** | **ALTO**: Si el cache de licencia tiene un businessId desactualizado, lo restaura como si fuera el canónico |
| 283-286 | `load()` | En el merge de `LicenseInfo`, usa `_resolveBusinessIdValue(localBusinessId, merged.businessId)` | **ALTO**: Prioriza el local sobre el cache, pero si local es null usa el cache |
| 398-401 | `activate()` | Usa `_resolveBusinessIdValue(map['business_id'], localBusinessId)` | **ALTO**: Si el backend devuelve un business_id diferente, lo usa como fallback |
| 428-431 | `activate()` | Mismo patrón: `_resolveBusinessIdValue(map['business_id'], localBusinessId)` | **ALTO**: El backend puede cambiar el businessId durante activación |
| 512-515 | `check()` | Mismo patrón: `_resolveBusinessIdValue(map['business_id'], localBusinessId)` | **ALTO**: El backend puede cambiar el businessId durante verificación |
| 860-877 | `applyOfflineLicenseFile()` | Si el archivo tiene `business_id` y el local no existe, **guarda el del archivo**. Si existe y es diferente, **lanza error** | **MEDIO**: Correcto al validar, pero puede establecer un businessId desde un archivo externo |
| 1090-1136 | `debugResetLicensingOnThisDevice()` | **Borra TODO**: archivo de licencia, cache, identidad, cola de registro | **CRÍTICO**: Aunque es solo debug, borra el businessId permanentemente |

#### 4. `@FULLPOS:lib/features/license/ui/license_page.dart`

| Línea | Función | Qué hace | Riesgo |
|-------|---------|----------|--------|
| 117-155 | `_refreshBusinessId()` | Si `licenseState.info.businessId` existe y el local no, **guarda el de licenseState como local** | **ALTO**: El businessId de la UI puede propagarse al storage local |
| 133-136 | `_refreshBusinessId()` | `if (localBusinessId.isEmpty) { await storage.setBusinessId(canonicalBusinessId); }` | **ALTO**: Sobrescritura silenciosa del businessId local |

#### 5. `backend/controllers/businessesController.js`

| Línea | Función | Qué hace | Riesgo |
|-------|---------|----------|--------|
| 102-311 | `register()` | Recibe `business_id` del frontend. Si hay conflicto, devuelve `BUSINESS_ID_CONFLICT` con `existing_business_id` | **MEDIO**: El backend correctamente rechaza businessId duplicados, pero el frontend sobrescribe automáticamente |
| 175-183 | `register()` | Si encuentra cliente por teléfono/email con otro business_id, **devuelve 409** | **MEDIO**: Correcto, pero el frontend reemplaza el businessId local |

#### 6. `backend/controllers/adminCustomersController.js`

| Línea | Función | Qué hace | Riesgo |
|-------|---------|----------|--------|
| 333-385 | `assignBusinessId()` | Si `force=true`, **regenera el businessId** con `BIZ-{hex}` | **ALTO**: Un admin puede forzar un cambio de businessId, rompiendo la vinculación con dispositivos |
| 360-364 | `assignBusinessId()` | Genera businessId con `crypto.randomBytes(12).toString('hex')` | **ALTO**: Formato diferente al UUID v4 del frontend |

#### 7. `backend/utils/licenseFile.js`

| Línea | Función | Qué hace | Riesgo |
|-------|---------|----------|--------|
| 148 | `createLicenseFileFromDbRows()` | Usa `customer.business_id` como `business_id` en el payload firmado | **MEDIO**: El business_id del archivo debe coincidir con el local |

---

## D. FLUJOS PELIGROSOS DETECTADOS

### D.1 Arranque de la app (LicenseController.load())

```
1. LicenseController.load() se ejecuta
2. Lee businessId de BusinessIdentityStorage → localBusinessId
3. Lee LicenseInfo de LicenseStorage → cachedBusinessId (del cache)
4. SI localBusinessId == null Y cachedBusinessId != null:
   → BusinessIdentityStorage.setBusinessId(cachedBusinessId)  ← SOBRESCRITURA SILENCIOSA
5. Merge: usa _resolveBusinessIdValue(localBusinessId, merged.businessId)
   → Si local existe, lo usa. Si no, usa el del cache.
```

**Problema**: Si el cache de licencia tiene un businessId antiguo (por ejemplo, de un restore de backup), se restaura silenciosamente sobre el storage local.

### D.2 Registro de negocio (startLocalTrialOfflineFirst)

```
1. startLocalTrialOfflineFirst() se ejecuta
2. BusinessRegistrationService.buildPayload() llama a _resolveCanonicalBusinessId()
3. _resolveCanonicalBusinessId():
   a. Lee localBusinessId de BusinessIdentityStorage
   b. Lee cachedLicenseBusinessId de LicenseStorage.getLastInfo().businessId
   c. SI cachedLicenseBusinessId existe Y es diferente al local:
      → BusinessIdentityStorage.setBusinessId(cachedLicenseBusinessId, overwrite: true)  ← SOBRESCRITURA FORZADA
   d. Retorna cachedLicenseBusinessId (prioriza cache sobre local)
4. registerNowOrQueue() → _registerWithBusinessIdReconcile()
5. SI backend responde 409 BUSINESS_ID_CONFLICT con existingBusinessId:
   → BusinessIdentityStorage.setBusinessId(existingBusinessId, overwrite: true)  ← SOBRESCRITURA FORZADA
   → payload.business_id = existingBusinessId
   → Reintenta registro
```

**Problema**: El businessId puede cambiar hasta 2 veces durante un solo registro: primero por el cache de licencia, luego por el backend.

### D.3 Activación de licencia (LicenseController.activate())

```
1. activate() se ejecuta
2. Lee localBusinessId de BusinessIdentityStorage
3. Llama a api.activate() que devuelve map['business_id']
4. Crea LicenseInfo con:
   businessId: _resolveBusinessIdValue(map['business_id'], localBusinessId)
   → Si el backend devuelve business_id, lo usa. Si no, usa local.
5. Guarda LicenseInfo en LicenseStorage (con el businessId resuelto)
```

**Problema**: Si el backend devuelve un business_id diferente (por ejemplo, si el admin lo cambió), el nuevo valor se guarda en el cache de licencia. Luego en el próximo `load()`, este valor puede sobrescribir el local.

### D.4 Aplicación de archivo de licencia offline

```
1. applyOfflineLicenseFile() se ejecuta
2. Lee payload.business_id del archivo
3. SI localBusinessId == null:
   → BusinessIdentityStorage.setBusinessId(payloadBusinessId)  ← ESTABLECE DESDE ARCHIVO
4. SI localBusinessId != null Y != payloadBusinessId:
   → Lanza error "Este archivo no corresponde a este negocio"  ← BIEN VALIDADO
```

**Problema**: Aunque la validación es correcta, si el archivo se aplica antes de que exista un businessId local, el archivo establece el businessId. Si luego se aplica otro archivo con diferente businessId, el sistema queda bloqueado.

### D.5 debugResetLicensingOnThisDevice()

```
1. debugResetLicensingOnThisDevice() se ejecuta (solo debug)
2. fileStorage.delete() → borra license.dat
3. storage.clearAll() → borra LicenseStorage (cache de licencia)
4. BusinessIdentityStorage.clearAll() → BORRA businessId, nombre, rol, teléfono, email, trial
5. PendingRegistrationQueue.clear() → borra cola de registro
6. LicenseState.initial() → resetea estado
7. load() → se ejecuta de nuevo
8. En load(), como businessId ya no existe:
   → ensureBusinessId() genera un UUID v4 NUEVO  ← NUEVO businessId
```

**Problema**: Aunque es solo debug, si se ejecuta accidentalmente, **el businessId cambia permanentemente**. El nuevo UUID v4 no coincide con el del backend, rompiendo toda la vinculación.

### D.6 Login/Logout

**No se encontró** lógica que modifique el businessId durante login o logout. El `SessionManager.logout()` y `LogoutFlowService` no tocan el `BusinessIdentityStorage`.

### D.7 Sincronización cloud (BusinessLicenseSync)

**No se encontró** lógica que modifique el businessId durante la sincronización. El sync descarga el token de licencia pero no altera `BusinessIdentityStorage`.

### D.8 Admin panel - Asignación de businessId

```
1. POST /api/admin/customers/:id/assign-business-id
2. Si force=true, genera NUEVO businessId: 'BIZ-' + crypto.randomBytes(12).toString('hex')
3. Lo guarda en customers.business_id
```

**Problema**: El formato `BIZ-{hex}` es diferente al UUID v4 que genera el frontend. Si el admin fuerza un cambio, el frontend nunca sabrá que cambió hasta que intente registrar y reciba un `BUSINESS_ID_CONFLICT`.

---

## E. POSIBLES CAUSAS RAÍZ (ordenadas de más probable a menos probable)

### E.1 [CRÍTICO] Múltiples fuentes de verdad sin jerarquía clara

El businessId se almacena en:
- `BusinessIdentityStorage` (SharedPreferences)
- `LicenseStorage` (SharedPreferences, dentro de `LicenseInfo`)
- `customers.business_id` (PostgreSQL)
- Archivo `.fulllicense`

No hay un mecanismo que garantice que todas las fuentes tengan el mismo valor. La reconciliación entre ellas es frágil y puede causar cambios inesperados.

### E.2 [CRÍTICO] ensureBusinessId() genera UUID v4 sin verificar contra el backend

`BusinessIdentityStorage.ensureBusinessId()` (línea 57-64) genera un UUID v4 nuevo si no existe businessId local. Esto es peligroso porque:
- Si se llama después de un reset, crea un businessId completamente nuevo
- No verifica si el backend ya tiene un businessId para este cliente
- El nuevo UUID no coincide con el del backend

### E.3 [ALTO] Reconciliación forzada en _resolveCanonicalBusinessId()

`BusinessRegistrationService._resolveCanonicalBusinessId()` (línea 24-45) sobrescribe el businessId local con el del cache de licencia usando `overwrite: true`. Esto significa que el cache de licencia (que puede estar desactualizado) tiene prioridad sobre el storage local.

### E.4 [ALTO] Sobrescritura silenciosa en LicenseController.load()

En `load()` (línea 258-260), si `localBusinessId` es null pero `cachedBusinessId` existe, se guarda el cached como local. Esto es correcto como fallback, pero puede restaurar un businessId antiguo si el cache no se limpió correctamente.

### E.5 [ALTO] BUSINESS_ID_CONFLICT fuerza cambio de businessId local

Cuando el backend responde 409 con `existing_business_id`, el frontend sobrescribe su businessId local sin preguntar al usuario (línea 143-146 de `business_registration_service.dart`).

### E.6 [MEDIO] debugResetLicensingOnThisDevice() borra la identidad completa

Aunque es solo debug, borra el businessId, y el próximo `load()` generará uno nuevo.

### E.7 [MEDIO] Admin puede forzar cambio de businessId

El endpoint `assignBusinessId` con `force=true` puede regenerar el businessId de un cliente, rompiendo la vinculación con todos sus dispositivos.

### E.8 [BAJO] No hay validación de formato de businessId

El frontend genera UUID v4, el admin puede generar `BIZ-{hex}`, y el backend acepta cualquier texto. No hay consistencia en el formato.

---

## F. EVIDENCIAS

### F.1 ensureBusinessId() genera UUID v4 sin verificar

**Archivo**: `@FULLPOS:lib/features/registration/services/business_identity_storage.dart`
**Líneas**: 57-64
```dart
Future<String> ensureBusinessId() async {
    final sp = await SharedPreferences.getInstance();
    final existing = (sp.getString(_kBusinessId) ?? '').trim();
    if (existing.isNotEmpty) return existing;
    final id = IdUtils.uuidV4();  // ← GENERA UUID NUEVO
    await sp.setString(_kBusinessId, id);
    return id;
}
```

### F.2 Sobrescritura forzada desde cache de licencia

**Archivo**: `@FULLPOS:lib/features/registration/services/business_registration_service.dart`
**Líneas**: 24-45
```dart
Future<String> _resolveCanonicalBusinessId() async {
    final localBusinessId = (await identityStorage.getBusinessId() ?? '').trim();
    final cachedLicenseBusinessId =
        ((await licenseStorage.getLastInfo())?.businessId ?? '').trim();
    if (cachedLicenseBusinessId.isNotEmpty) {
      if (localBusinessId != cachedLicenseBusinessId) {
        await identityStorage.setBusinessId(
          cachedLicenseBusinessId,
          overwrite: true,  // ← SOBRESCRITURA FORZADA
        );
      }
      return cachedLicenseBusinessId;  // ← PRIORIZA CACHE SOBRE LOCAL
    }
    if (localBusinessId.isNotEmpty) {
      return localBusinessId;
    }
    return identityStorage.ensureBusinessId();  // ← GENERA UUID SI NO EXISTE
}
```

### F.3 Sobrescritura silenciosa en load()

**Archivo**: `@FULLPOS:lib/features/license/services/license_controller.dart`
**Líneas**: 254-261
```dart
var localBusinessId = _resolveBusinessIdValue(
    await identityStorage.getBusinessId(),
);
final cachedBusinessId = _resolveBusinessIdValue(last?.businessId);
if (localBusinessId == null && cachedBusinessId != null) {
    await identityStorage.setBusinessId(cachedBusinessId);  // ← SOBRESCRITURA SILENCIOSA
    localBusinessId = cachedBusinessId;
}
```

### F.4 BUSINESS_ID_CONFLICT fuerza sobrescritura

**Archivo**: `@FULLPOS:lib/features/registration/services/business_registration_service.dart`
**Líneas**: 128-156
```dart
if (backendCode == 'BUSINESS_ID_CONFLICT' &&
    existingBusinessId.isNotEmpty) {
    await identityStorage.setBusinessId(
      existingBusinessId,
      overwrite: true,  // ← SOBRESCRITURA FORZADA DESDE BACKEND
    );
    payloadToSend['business_id'] = existingBusinessId;
}
```

### F.5 debugResetLicensingOnThisDevice() borra identidad

**Archivo**: `@FULLPOS:lib/features/license/services/license_controller.dart`
**Líneas**: 1090-1136
```dart
Future<void> debugResetLicensingOnThisDevice() async {
    if (!kDebugMode) return;
    // ...
    await BusinessIdentityStorage().clearAll();  // ← BORRA businessId
    // ...
    state = LicenseState.initial();
    await load();  // ← load() generará NUEVO businessId con ensureBusinessId()
}
```

### F.6 Admin puede regenerar businessId

**Archivo**: `backend/controllers/adminCustomersController.js`
**Líneas**: 333-385
```javascript
async function assignBusinessId(req, res) {
    // ...
    if (customer.business_id && String(customer.business_id).trim() && !force) {
      // Si ya tiene y no force, no hace nada
    }
    // Generar business_id único
    let businessId = req.body?.business_id || null;
    if (!businessId) {
      businessId = 'BIZ-' + crypto.randomBytes(12).toString('hex').toUpperCase();  // ← FORMATO DIFERENTE
    }
    const updated = await customersModel.setCustomerBusinessId({ customerId, business_id: String(businessId).trim() });
}
```

### F.7 Backend acepta cualquier businessId del frontend

**Archivo**: `backend/controllers/businessesController.js`
**Líneas**: 102-311
El endpoint `register()` recibe el `business_id` del body y lo usa directamente. No valida formato, no verifica si es un UUID, no verifica si el cliente ya tenía uno diferente (excepto por unique constraint).

### F.8 customers.business_id tiene unique index parcial

**Archivo**: `backend/db/migrations/015_add_customers_business_id.sql`
**Líneas**: 8-17
```sql
CREATE UNIQUE INDEX idx_customers_business_id_unique
    ON customers (business_id)
    WHERE business_id IS NOT NULL;
```
Esto evita duplicados, pero no evita que un businessId sea reemplazado por otro.

---

## G. RECOMENDACIÓN TÉCNICA

### Arquitectura correcta propuesta

#### Principios

1. **El businessId es la identidad permanente del negocio. Una vez creado, NUNCA cambia.**
2. **El deviceId identifica el equipo físico. Es independiente del businessId.**
3. **El licenseId identifica la licencia. Está vinculado al businessId pero no lo reemplaza.**
4. **No debe existir regeneración automática de businessId bajo ninguna circunstancia.**

#### Jerarquía de fuentes de verdad

```
BUSINESS_ID (inmutable)
  ├── Fuente primaria: PostgreSQL (customers.business_id)
  ├── Cache local: BusinessIdentityStorage (SharedPreferences)
  ├── Cache de licencia: LicenseInfo.businessId (solo lectura, nunca escribe sobre primaria)
  └── Archivo offline: payload.business_id (solo validación, nunca escritura)
```

#### Reglas estrictas

1. **El businessId SOLO se crea una vez**: Cuando el usuario completa el registro inicial (trial o compra). Después de eso, es READ-ONLY.

2. **NUNCA regenerar businessId localmente**: `ensureBusinessId()` no debe generar UUID. Debe devolver null si no existe, y el sistema debe pedir al usuario que se registre o inicie sesión.

3. **El cache de licencia NO debe sobrescribir el businessId local**: `LicenseInfo.businessId` es solo para referencia. Si hay discrepancia, debe mostrar un error, no sobrescribir silenciosamente.

4. **BUSINESS_ID_CONFLICT debe ser un error de usuario**: Si el backend detecta conflicto, debe notificar al usuario, no sobrescribir automáticamente.

5. **El admin NO debe poder regenerar businessId**: El endpoint `assignBusinessId` debe eliminarse o requerir confirmación explícita del usuario.

6. **debugResetLicensingOnThisDevice() NO debe borrar businessId**: Debe preservar la identidad del negocio.

7. **Validación de formato**: El businessId debe tener un formato consistente (UUID v4) y validarse en backend y frontend.

---

## H. CAMBIOS APLICADOS (CORRECCIÓN)

### Resumen de cambios realizados

Se implementaron las siguientes correcciones para proteger el businessId:

#### H.1 `BusinessIdentityStorage` (`@FULLPOS:lib/features/registration/services/business_identity_storage.dart`)

- **`ensureBusinessId()` ahora es `@Deprecated` y solo llama a `getBusinessId()`**: Ya NO genera UUID v4. Si no existe businessId, retorna null.
- **`setBusinessId()` ahora tiene `overwrite=false` por defecto**: Si ya existe un businessId diferente, no lo sobrescribe a menos que se pase `overwrite: true` explícitamente.
- **Se agregó `clearProfile()`**: Borra solo datos no críticos (nombre, rol, teléfono, email, trial) pero NO borra businessId.
- **`clearAll()` documentado**: Solo debe llamarse desde flujo admin explícito.

#### H.2 `BusinessIdentityGuard` (NUEVO ARCHIVO: `@FULLPOS:lib/features/registration/services/business_identity_guard.dart`)

Se creó un guardia central que valida TODAS las operaciones sobre businessId:

- **`resolveAndApply()`**: Método único que decide si se puede escribir un businessId.
- **Reglas**:
  - `allowInitialSet: false` → No permite establecer businessId si no existe localmente.
  - `allowRestoreWhenLocalMissing: true` → Solo permite restaurar desde cache si local está vacío.
  - `allowOverwrite: false` → Nunca sobrescribe un businessId existente.
- **`BusinessIdentityConflictException`**: Excepción clara cuando hay conflicto, con `currentBusinessId`, `incomingBusinessId`, `source` y `reason`.

#### H.3 `BusinessRegistrationService` (`@FULLPOS:lib/features/registration/services/business_registration_service.dart`)

- **`_resolveCanonicalBusinessId()` ahora usa `BusinessIdentityGuard.resolveAndApply()`**: Ya no sobrescribe el businessId local con el del cache de licencia.
- **`_registerWithBusinessIdReconcile()` ahora lanza `BusinessIdentityConflictException`**: Cuando el backend responde `BUSINESS_ID_CONFLICT`, ya no sobrescribe automáticamente. Lanza una excepción clara que el usuario debe resolver manualmente.

#### H.4 `LicenseController` (`@FULLPOS:lib/features/license/services/license_controller.dart`)

- **`load()` ahora usa `BusinessIdentityGuard.resolveAndApply()`**: Ya no restaura silenciosamente el businessId desde el cache de licencia.
- **`debugResetLicensingOnThisDevice()` ahora usa `clearProfile()`**: Ya NO borra businessId. Solo borra perfil, trial y cola de registro.

#### H.5 `CloudCompanyIdentityService` (`@FULLPOS:lib/core/services/cloud_company_identity_service.dart`)

- **`resolve()` ahora usa `getBusinessId()`**: Ya no llama a `ensureBusinessId()` que podría generar un UUID nuevo.

#### H.6 `LicensePage` (`@FULLPOS:lib/features/license/ui/license_page.dart`)

- **`_refreshBusinessId()` ya no tiene parámetro `ensureExists`**: Eliminado el flag que permitía regeneración automática.
- **Todas las llamadas a `_refreshBusinessId(ensureExists: true/false)` corregidas**: Ahora solo usan `force: true` o sin parámetros.

### Pendiente para próxima iteración

1. **Eliminar `assignBusinessId` del admin** o requerir confirmación explícita del usuario.
2. **Agregar validación de formato de businessId** en backend (UUID v4).
3. **Agregar constraint en PostgreSQL** para evitar que `customers.business_id` cambie después de creado.
4. **Agregar logging** cada vez que se intente cambiar el businessId.
5. **Agregar verificación de integridad** al inicio de la app.
6. **Agregar tests** que verifiquen que el businessId nunca cambia después de la creación inicial.

---

## NOTAS ADICIONALES

- **companyTenantKey**: No se encontró evidencia de este concepto en el proyecto. No se usa.
- **deviceId**: Se genera con `SessionManager.ensureTerminalId()` y es independiente del businessId. No hay evidencia de que afecte al businessId.
- **No se encontró** lógica que derive businessId desde RNC, nombre de empresa o datos del equipo.
- **No se encontró** lógica de "factory reset" o "clear local data" que afecte al businessId (excepto `debugResetLicensingOnThisDevice`).
- **No se encontró** lógica en el módulo de sync que modifique el businessId.
- **No se encontró** lógica en login/logout que modifique el businessId.

---

*Fin del informe de auditoría.*
