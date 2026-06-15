BEGIN;

UPDATE projects
SET currency = 'USD',
    updated_at = now()
WHERE UPPER(code) IN ('FULLPOS', 'FULLCREDIT')
  AND currency IS DISTINCT FROM 'USD';

COMMIT;
