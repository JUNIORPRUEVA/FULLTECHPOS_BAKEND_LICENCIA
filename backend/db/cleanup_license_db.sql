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
-- 1) Muestra un PREVIEW con todas las tablas (filtradas a public) + tamaño + filas estimadas.
-- 2) Lista las tablas que NO son parte del módulo de licencias.
-- 3) (Opcional) Las mueve a un schema "_trash" (reversible).
-- 4) (Opcional) Las elimina con CASCADE (irreversible).
--
-- Tablas que se CONSERVAN (licenciamiento):
-- - customers
-- - licenses
-- - license_activations
-- - license_config
-- - projects

-- =========================================================
-- 0) PREVIEW (seguro)
-- =========================================================
-- Tip: n_live_tup es un estimado (rápido). Si quieres exactitud, haz COUNT(*) por tabla.
SELECT
  s.schemaname,
  s.relname AS tablename,
  s.n_live_tup::bigint AS approx_rows,
  pg_size_pretty(pg_total_relation_size(format('%I.%I', s.schemaname, s.relname)::regclass)) AS total_size
FROM pg_stat_user_tables s
WHERE s.schemaname = 'public'
ORDER BY pg_total_relation_size(format('%I.%I', s.schemaname, s.relname)::regclass) DESC;

-- =========================================================
-- 1) LISTAR TABLAS A LIMPIAR (seguro)
-- =========================================================
WITH keep AS (
  SELECT unnest(ARRAY[
    'customers',
    'licenses',
    'license_activations',
    'license_config',
    'projects'
  ]) AS tablename
)
SELECT t.tablename
FROM pg_tables t
LEFT JOIN keep k ON k.tablename = t.tablename
WHERE t.schemaname = 'public'
  AND k.tablename IS NULL
ORDER BY t.tablename;

-- =========================================================
-- 2) MOVER A TRASH (OPCIONAL, REVERSIBLE)
-- =========================================================
-- Esto saca las tablas "extra" del schema public sin borrarlas.
-- Si estás probando, esta es la opción más segura.
--
-- DESCOMENTA para ejecutar:
-- DO $$
-- DECLARE r record;
-- BEGIN
--   EXECUTE 'CREATE SCHEMA IF NOT EXISTS _trash';
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
--     EXECUTE format('ALTER TABLE public.%I SET SCHEMA _trash', r.tablename);
--   END LOOP;
-- END $$;

-- =========================================================
-- 3) ELIMINAR (OPCIONAL, IRREVERSIBLE)
-- =========================================================
-- DESCOMENTA SI ESTÁS 100% SEGURO que esta DB es SOLO de licencias.
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
