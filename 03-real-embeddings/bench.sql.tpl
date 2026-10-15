USE scale;
DROP TABLE IF EXISTS exact_TBL, ann_TBL, timing_TBL, results_TBL;
CREATE TABLE exact_TBL (mode VARCHAR(20), qid INT, id INT, KEY (mode, qid, id));
CREATE TABLE ann_TBL (mode VARCHAR(20), ef INT, qid INT, id INT, KEY (mode, ef, qid, id));
CREATE TABLE timing_TBL (mode VARCHAR(20), ef INT, qid INT, us BIGINT);
CREATE TABLE results_TBL (mode VARCHAR(20), ef INT, recall_at_10 DECIMAL(6,4), rows_returned INT,
  p50_ms DECIMAL(8,2), p95_ms DECIMAL(8,2), p99_ms DECIMAL(8,2), max_ms DECIMAL(8,2));

DELIMITER //
-- Exact top 10 by full scan, the ground truth for recall.
CREATE OR REPLACE PROCEDURE exact_TBL(p_mode VARCHAR(20))
BEGIN
  DECLARE i INT DEFAULT 1;
  DECLARE t0 DATETIME(6);
  WHILE i <= 250 DO
    SELECT v INTO @v FROM q_TBL WHERE qid = i;
    SET t0 = NOW(6);
    IF p_mode = 'filtered' THEN
      INSERT INTO exact_TBL SELECT p_mode, i, id FROM TBL IGNORE INDEX (embedding)
        WHERE agent_id = 'agent-3' ORDER BY VEC_DISTANCE_COSINE(embedding, @v) LIMIT 10;
    ELSE
      INSERT INTO exact_TBL SELECT p_mode, i, id FROM TBL IGNORE INDEX (embedding)
        ORDER BY VEC_DISTANCE_COSINE(embedding, @v) LIMIT 10;
    END IF;
    INSERT INTO timing_TBL VALUES (CONCAT(p_mode, '-scan'), 0, i, TIMESTAMPDIFF(MICROSECOND, t0, NOW(6)));
    SET i = i + 1;
  END WHILE;
END//
-- Top 10 through the vector index at a given ef_search.
CREATE OR REPLACE PROCEDURE ann_TBL(p_mode VARCHAR(20), p_ef INT)
BEGIN
  DECLARE i INT DEFAULT 1;
  DECLARE t0 DATETIME(6);
  SET SESSION mhnsw_ef_search = p_ef;
  WHILE i <= 250 DO
    SELECT v INTO @v FROM q_TBL WHERE qid = i;
    SET t0 = NOW(6);
    IF p_mode = 'filtered' THEN
      INSERT INTO ann_TBL SELECT p_mode, p_ef, i, id FROM TBL
        WHERE agent_id = 'agent-3' ORDER BY VEC_DISTANCE(embedding, @v) LIMIT 10;
    ELSE
      INSERT INTO ann_TBL SELECT p_mode, p_ef, i, id FROM TBL
        ORDER BY VEC_DISTANCE(embedding, @v) LIMIT 10;
    END IF;
    INSERT INTO timing_TBL VALUES (p_mode, p_ef, i, TIMESTAMPDIFF(MICROSECOND, t0, NOW(6)));
    SET i = i + 1;
  END WHILE;
  INSERT INTO results_TBL
  SELECT p_mode, p_ef,
    (SELECT COUNT(a.id) / COUNT(*) FROM exact_TBL e
       LEFT JOIN ann_TBL a ON a.mode = e.mode AND a.ef = p_ef AND a.qid = e.qid AND a.id = e.id
       WHERE e.mode = p_mode),
    (SELECT COUNT(*) FROM ann_TBL WHERE mode = p_mode AND ef = p_ef),
    MAX(CASE WHEN r = 125 THEN us END) / 1000, MAX(CASE WHEN r = 238 THEN us END) / 1000,
    MAX(CASE WHEN r = 248 THEN us END) / 1000, MAX(us) / 1000
  FROM (SELECT us, ROW_NUMBER() OVER (ORDER BY us) r FROM timing_TBL WHERE mode = p_mode AND ef = p_ef) z;
END//
DELIMITER ;

CALL exact_TBL('all');
CALL exact_TBL('filtered');
-- Warm-up pass, not recorded in results.
CALL ann_TBL('all', 20); DELETE FROM results_TBL; DELETE FROM ann_TBL; DELETE FROM timing_TBL WHERE mode = 'all';
CALL ann_TBL('all', 20);
CALL ann_TBL('all', 40);
CALL ann_TBL('all', 100);
CALL ann_TBL('all', 200);
CALL ann_TBL('filtered', 20);
CALL ann_TBL('filtered', 100);
CALL ann_TBL('filtered', 400);

SELECT VERSION() AS version, 'TBL' AS dataset, (SELECT COUNT(*) FROM TBL) AS row_count;
SELECT * FROM results_TBL ORDER BY mode, ef;
SELECT REPLACE(mode, '-scan', '') AS full_scan_mode,
  MAX(CASE WHEN r = 125 THEN us END) / 1000 AS p50_ms, MAX(CASE WHEN r = 238 THEN us END) / 1000 AS p95_ms,
  MAX(CASE WHEN r = 248 THEN us END) / 1000 AS p99_ms
FROM (SELECT mode, us, ROW_NUMBER() OVER (PARTITION BY mode ORDER BY us) r FROM timing_TBL WHERE mode LIKE '%-scan') z
GROUP BY mode;
SELECT v INTO @v FROM q_TBL WHERE qid = 1;
EXPLAIN SELECT id FROM TBL ORDER BY VEC_DISTANCE(embedding, @v) LIMIT 10;
FLUSH STATUS;
SELECT COUNT(*) AS rows_returned FROM (SELECT id FROM TBL ORDER BY VEC_DISTANCE(embedding, @v) LIMIT 10) x;
SHOW SESSION STATUS LIKE 'Handler_read_rnd_next';
FLUSH STATUS;
SELECT COUNT(*) AS rows_returned FROM (SELECT id FROM TBL IGNORE INDEX (embedding) ORDER BY VEC_DISTANCE_COSINE(embedding, @v) LIMIT 10) x;
SHOW SESSION STATUS LIKE 'Handler_read_rnd_next';
