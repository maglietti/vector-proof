USE demo;
DROP TABLE IF EXISTS q, ann, exact_nn, timing;
CREATE TABLE q (qid INT PRIMARY KEY, v VECTOR(384) NOT NULL);
-- 50 query vectors near the cluster centers, with fresh noise.
INSERT INTO q
SELECT s.seq,
  VEC_FromText(CONCAT('[', (SELECT GROUP_CONCAT(ROUND(SIN(((s.seq * 37) % 100) * 7.3 + t.seq * 1.7) + (RAND() - 0.5) * 0.6, 4) ORDER BY t.seq) FROM seq_1_to_384 t), ']'))
FROM seq_1_to_50 s;
CREATE TABLE ann (qid INT, id INT);
CREATE TABLE exact_nn (qid INT, id INT);
CREATE TABLE timing (qid INT, ann_us BIGINT, exact_us BIGINT);

DELIMITER //
CREATE OR REPLACE PROCEDURE bench()
BEGIN
  DECLARE i INT DEFAULT 1;
  DECLARE t0, t1, t2 DATETIME(6);
  WHILE i <= 50 DO
    SELECT v INTO @v FROM q WHERE qid = i;
    SET t0 = NOW(6);
    INSERT INTO ann SELECT i, id FROM mem ORDER BY VEC_DISTANCE(embedding, @v) LIMIT 10;
    SET t1 = NOW(6);
    INSERT INTO exact_nn SELECT i, id FROM mem IGNORE INDEX (embedding) ORDER BY VEC_DISTANCE_COSINE(embedding, @v) LIMIT 10;
    SET t2 = NOW(6);
    INSERT INTO timing VALUES (i, TIMESTAMPDIFF(MICROSECOND, t0, t1), TIMESTAMPDIFF(MICROSECOND, t1, t2));
    SET i = i + 1;
  END WHILE;
END//
DELIMITER ;
CALL bench();

SELECT VERSION() AS version, (SELECT COUNT(*) FROM mem) AS row_count;
-- Recall@10 of the index against the exact (full scan) answer.
SELECT ROUND(COUNT(a.id) / (SELECT COUNT(*) FROM exact_nn), 4) AS recall_at_10
FROM exact_nn e LEFT JOIN ann a ON a.qid = e.qid AND a.id = e.id;
-- Latency percentiles in milliseconds, 50 queries each.
WITH r AS (
  SELECT ann_us, exact_us,
    ROW_NUMBER() OVER (ORDER BY ann_us) AS ra,
    ROW_NUMBER() OVER (ORDER BY exact_us) AS re
  FROM timing)
SELECT 'vector index' AS path,
  ROUND(MAX(CASE WHEN ra = 25 THEN ann_us END) / 1000, 2) AS p50_ms,
  ROUND(MAX(CASE WHEN ra = 48 THEN ann_us END) / 1000, 2) AS p95_ms,
  ROUND(MAX(ann_us) / 1000, 2) AS max_ms
FROM r
UNION ALL
SELECT 'full scan (IGNORE INDEX)',
  ROUND(MAX(CASE WHEN re = 25 THEN exact_us END) / 1000, 2),
  ROUND(MAX(CASE WHEN re = 48 THEN exact_us END) / 1000, 2),
  ROUND(MAX(exact_us) / 1000, 2)
FROM r;

SELECT v INTO @v FROM q WHERE qid = 1;
EXPLAIN SELECT id FROM mem ORDER BY VEC_DISTANCE(embedding, @v) LIMIT 10;
EXPLAIN SELECT id FROM mem IGNORE INDEX (embedding) ORDER BY VEC_DISTANCE_COSINE(embedding, @v) LIMIT 10;
ANALYZE FORMAT=JSON SELECT id FROM mem ORDER BY VEC_DISTANCE(embedding, @v) LIMIT 10;
ANALYZE FORMAT=JSON SELECT id FROM mem IGNORE INDEX (embedding) ORDER BY VEC_DISTANCE_COSINE(embedding, @v) LIMIT 10;
FLUSH STATUS;
SELECT COUNT(*) AS rows_returned FROM (SELECT id FROM mem ORDER BY VEC_DISTANCE(embedding, @v) LIMIT 10) x;
SHOW SESSION STATUS WHERE Variable_name IN ('Handler_read_rnd_next', 'Handler_read_key', 'Handler_read_next', 'Handler_read_rnd');
FLUSH STATUS;
SELECT COUNT(*) AS rows_returned FROM (SELECT id FROM mem IGNORE INDEX (embedding) ORDER BY VEC_DISTANCE_COSINE(embedding, @v) LIMIT 10) x;
SHOW SESSION STATUS WHERE Variable_name IN ('Handler_read_rnd_next', 'Handler_read_key', 'Handler_read_next', 'Handler_read_rnd');
