USE scale;
SELECT VERSION() AS version, (SELECT COUNT(*) FROM wlog) AS rows_inserted,
  ROUND((SELECT COUNT(*) FROM wlog) / 60, 1) AS inserts_per_s,
  (SELECT COUNT(*) FROM reads_log) AS reads_done, ROUND((SELECT COUNT(*) FROM reads_log) / 60, 1) AS reads_per_s;
SELECT 'insert (with index update)' AS op,
  MAX(CASE WHEN r = CEIL(c * 0.50) THEN us END) / 1000 AS p50_ms, MAX(CASE WHEN r = CEIL(c * 0.95) THEN us END) / 1000 AS p95_ms,
  MAX(CASE WHEN r = CEIL(c * 0.99) THEN us END) / 1000 AS p99_ms
FROM (SELECT insert_us AS us, ROW_NUMBER() OVER (ORDER BY insert_us) r, COUNT(*) OVER () c FROM wlog) z
UNION ALL
SELECT 'vector read under load',
  MAX(CASE WHEN r = CEIL(c * 0.50) THEN us END) / 1000, MAX(CASE WHEN r = CEIL(c * 0.95) THEN us END) / 1000,
  MAX(CASE WHEN r = CEIL(c * 0.99) THEN us END) / 1000
FROM (SELECT us, ROW_NUMBER() OVER (ORDER BY us) r, COUNT(*) OVER () c FROM reads_log) z;
SELECT COUNT(*) AS rows_probed, SUM(found_top1) AS found_as_top1,
  ROUND(AVG(lag_us) / 1000, 2) AS avg_ms_commit_to_found, ROUND(MAX(lag_us) / 1000, 2) AS max_ms_commit_to_found
FROM probe_log;
