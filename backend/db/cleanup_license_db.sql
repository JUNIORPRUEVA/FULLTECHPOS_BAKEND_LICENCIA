-- cleanup_license_db.sql
--
-- ATENCIÓN:
-- Este script ES PELIGROSO si lo ejecutas en una base de datos que también
-- usa tu POS u otros módulos.
--
-- Úsalo SOLO si confirmas que esta base de datos es EXCLUSIVA del backend de licencias.
-- Recomendación: primero haz un backup.
--
-- Qué hace:
-- 1) Lista las tablas que NO son parte del módulo de licencias.
-- 2) (Opcional) Las elimina con CASCADE.
--
-- Tablas que se CONSERVAN (licenciamiento):
-- - customers
-- - licenses
-- - license_activations
-- - license_config
-- - projects

-- 1) LISTAR (seguro)
SELECT tablename
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename NOT IN (
    'customers',
    'licenses',
    'license_activations',
    'license_config',
    'projects'
  )
ORDER BY tablename;

-- 2) ELIMINAR (DESCOMENTA SI ESTÁS 100% SEGURO)
-- DO $$
-- DECLARE r record;
-- BEGIN
--   FOR r IN
--     SELECT tablename
--     FROM pg_tables
--     WHERE schemaname = 'public'
--       AND tablename NOT IN (
--         'customers',
--         'licenses',
--         'license_activations',
--         'license_config',
--         'projects'
--       )
--   LOOP
--     EXECUTE format('DROP TABLE IF EXISTS public.%I CASCADE', r.tablename);
--   END LOOP;
-- END $$;
