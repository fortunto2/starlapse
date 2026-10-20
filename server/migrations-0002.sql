-- 2026-10-20: raw star samples and the meter version (plan E1). Columns are named in
-- INSERT order in src/observation.ts `row`, so the table is rebuilt rather than ALTERed
-- (ALTER ADD COLUMN appends at the end). It held only test rows.
DROP TABLE IF EXISTS observations;
