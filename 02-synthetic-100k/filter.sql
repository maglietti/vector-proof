USE demo;
SELECT v INTO @v FROM q WHERE qid = 1;
-- Filtered search: one agent's memory only (10% of rows).
EXPLAIN SELECT id, agent_id FROM mem WHERE agent_id = 'agent-3' ORDER BY VEC_DISTANCE(embedding, @v) LIMIT 10;
SELECT COUNT(*) AS rows_returned, SUM(agent_id = 'agent-3') AS correct_agent
FROM (SELECT id, agent_id FROM mem WHERE agent_id = 'agent-3' ORDER BY VEC_DISTANCE(embedding, @v) LIMIT 10) x;
-- Selective filter (1 row in 1,000): does the index still fill LIMIT 10?
SELECT COUNT(*) AS rows_returned
FROM (SELECT id FROM mem WHERE id % 1000 = 0 ORDER BY VEC_DISTANCE(embedding, @v) LIMIT 10) x;
SELECT COUNT(*) AS rows_returned_exact
FROM (SELECT id FROM mem IGNORE INDEX (embedding) WHERE id % 1000 = 0 ORDER BY VEC_DISTANCE_COSINE(embedding, @v) LIMIT 10) x;
-- Filtered recall: index with WHERE vs exact with WHERE, 50 queries.
DROP TABLE IF EXISTS fann, fexact;
CREATE TABLE fann (qid INT, id INT);
CREATE TABLE fexact (qid INT, id INT);
DELIMITER //
CREATE OR REPLACE PROCEDURE fbench()
BEGIN
  DECLARE i INT DEFAULT 1;
  WHILE i <= 50 DO
    SELECT v INTO @v FROM q WHERE qid = i;
    INSERT INTO fann SELECT i, id FROM mem WHERE agent_id = 'agent-3' ORDER BY VEC_DISTANCE(embedding, @v) LIMIT 10;
    INSERT INTO fexact SELECT i, id FROM mem IGNORE INDEX (embedding) WHERE agent_id = 'agent-3' ORDER BY VEC_DISTANCE_COSINE(embedding, @v) LIMIT 10;
    SET i = i + 1;
  END WHILE;
END//
DELIMITER ;
CALL fbench();
SELECT (SELECT COUNT(*) FROM fann) AS ann_rows, (SELECT COUNT(*) FROM fexact) AS exact_rows,
  ROUND(COUNT(a.id) / (SELECT COUNT(*) FROM fexact), 4) AS filtered_recall_at_10
FROM fexact e LEFT JOIN fann a ON a.qid = e.qid AND a.id = e.id;
