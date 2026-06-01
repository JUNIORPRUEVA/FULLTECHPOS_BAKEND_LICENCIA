-- ============================================
-- SCRIPT DE PRUEBA: Configurar datos de prueba
-- para FullCredit en Appyra Admin
-- ============================================
-- 
-- Uso:
--   psql -U postgres -d fullpos_sistema -f backend/scripts/setupFullcreditTestData.sql
--
-- O desde Node:
--   node -e "require('dotenv').config({path:'.env'}); const {pool}=require('./backend/db/pool'); require('fs').readFileSync('./backend/scripts/setupFullcreditTestData.sql','utf8').split(';').filter(Boolean).forEach(async s=>{try{await pool.query(s)}catch(e){console.error(e.message)}}); console.log('Done')"
--
-- ============================================

-- 1. Crear o actualizar proyecto FULLCREDIT
INSERT INTO projects (code, name, description, monthly_price, currency, demo_days, min_purchase_months, is_paid_project, allow_demo, is_active, created_at, updated_at)
VALUES (
  'FULLCREDIT',
  'FullCredit',
  'Sistema de gestión de préstamos y créditos',
  15.00,
  'USD',
  5,
  3,
  true,
  true,
  true,
  NOW(),
  NOW()
)
ON CONFLICT (code) DO UPDATE SET
  monthly_price = 15.00,
  currency = 'USD',
  demo_days = 5,
  min_purchase_months = 3,
  is_paid_project = true,
  allow_demo = true,
  is_active = true,
  updated_at = NOW();

-- 2. Crear un cliente de prueba (si no existe)
INSERT INTO customers (nombre_negocio, contacto_nombre, contacto_email, contacto_telefono, created_at, updated_at)
SELECT 'Cliente Prueba FullCredit', 'Juan Pérez', 'juan@test.com', '8095550101', NOW(), NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM customers WHERE nombre_negocio = 'Cliente Prueba FullCredit'
);

-- 3. Mostrar los IDs creados
SELECT '=== PROYECTO FULLCREDIT ===' AS info;
SELECT id, code, name, monthly_price, currency, demo_days, min_purchase_months, is_paid_project, allow_demo, is_active
FROM projects WHERE code = 'FULLCREDIT';

SELECT '=== CLIENTE DE PRUEBA ===' AS info;
SELECT id, nombre_negocio, contacto_nombre, contacto_email, contacto_telefono
FROM customers WHERE nombre_negocio = 'Cliente Prueba FullCredit';

SELECT '=== INSTRUCCIONES ===' AS info;
SELECT 'Para probar el flujo completo, usa estos IDs en los endpoints:' AS instruccion;
SELECT '1. POST /api/public/customers/register-or-find' AS paso;
SELECT '   {"project_code":"FULLCREDIT","business_name":"Mi Negocio","phone":"8095550101","email":"test@test.com","device_id":"test-device-emulador-001"}' AS payload;
SELECT '2. POST /api/public/licenses/demo/start' AS paso;
SELECT '   {"project_code":"FULLCREDIT","device_id":"test-device-emulador-001","business_name":"Mi Negocio"}' AS payload;
SELECT '3. GET /api/public/projects/FULLCREDIT/billing' AS paso;
SELECT '4. POST /api/public/license/validate' AS paso;
SELECT '   {"project_code":"FULLCREDIT","device_id":"test-device-emulador-001"}' AS payload;
