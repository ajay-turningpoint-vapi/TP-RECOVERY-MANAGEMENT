-- Migration 026's backfill only excluded names already ending in ' -TP'
-- or ' -Claart' — it didn't know about branches added later. Since
-- migrate.js re-runs every .sql file on every invocation, every
-- FP-VAPI/FP-NAVSARI/PORSHIVE salesman got ' -TP' appended a second time
-- on each subsequent `npm run migrate` (e.g. 'BHARAT -FPNAVSARI' became
-- 'BHARAT -FPNAVSARI -TP'). 026 is now fixed to not recur; this strips
-- the erroneous suffix already written.
UPDATE users
  SET full_name = SUBSTRING(full_name, 1, CHAR_LENGTH(full_name) - CHAR_LENGTH(' -TP'))
  WHERE role = 'SALESPERSON'
    AND busy_salesman_code IS NOT NULL
    AND full_name LIKE '% -TP'
    AND (full_name LIKE '% -FPVAPI -TP' OR full_name LIKE '% -FPNAVSARI -TP' OR full_name LIKE '% -PORSHIVE -TP' OR full_name LIKE '% -Claart -TP');
