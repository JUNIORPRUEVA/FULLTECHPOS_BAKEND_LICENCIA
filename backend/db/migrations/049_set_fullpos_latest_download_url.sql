-- 049_set_fullpos_latest_download_url.sql
-- Store a stable bot-friendly URL for FULLPOS downloads.
-- The endpoint redirects to whichever installer is latest in versions.json.

BEGIN;

UPDATE projects
SET
  product_profile = jsonb_set(
    COALESCE(product_profile, '{}'::jsonb),
    '{release_download_url}',
    to_jsonb('https://fullpos-backend-fullposlicenciaswed.onqyr1.easypanel.host/api/latest-installer/download'::text),
    true
  ),
  updated_at = now()
WHERE UPPER(code) = 'FULLPOS';

COMMIT;
