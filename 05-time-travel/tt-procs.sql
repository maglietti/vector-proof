USE tt;
DELIMITER //
-- One revision round: every memory gets a new embedding, the old row goes to history.
CREATE OR REPLACE PROCEDURE revise(p_round INT)
BEGIN
  UPDATE mem_v m JOIN rev r ON r.round = p_round AND r.id = m.id
    SET m.embedding = r.v, m.note = CONCAT('revision ', p_round);
  DO SLEEP(1);
  INSERT INTO cp VALUES (p_round, NOW(6));
  DO SLEEP(1);
END//
-- 250 queries; p_asof NULL = current state, else FOR SYSTEM_TIME AS OF that checkpoint.
CREATE OR REPLACE PROCEDURE measure(p_label VARCHAR(30), p_asof INT)
BEGIN
  DECLARE i INT DEFAULT 1;
  DECLARE t0 DATETIME(6);
  DECLARE ex_us BIGINT DEFAULT 0;
  DECLARE ex_list TEXT DEFAULT '';
  SET SESSION mhnsw_ef_search = 20;
  SELECT ts INTO @ts FROM cp WHERE round = p_asof;
  CREATE TEMPORARY TABLE IF NOT EXISTS ex_t (us BIGINT);
  TRUNCATE ex_t;
  WHILE i <= 250 DO
    SELECT v INTO @v FROM q WHERE qid = i;
    IF p_asof IS NULL THEN
      SET t0 = NOW(6);
      INSERT INTO ann SELECT p_label, i, id FROM mem_v ORDER BY VEC_DISTANCE(embedding, @v) LIMIT 10;
      INSERT INTO timing VALUES (p_label, i, TIMESTAMPDIFF(MICROSECOND, t0, NOW(6)));
      SET t0 = NOW(6);
      INSERT INTO exact_nn SELECT p_label, i, id FROM mem_v IGNORE INDEX (embedding) ORDER BY VEC_DISTANCE_COSINE(embedding, @v) LIMIT 10;
      INSERT INTO ex_t VALUES (TIMESTAMPDIFF(MICROSECOND, t0, NOW(6)));
    ELSE
      SET t0 = NOW(6);
      INSERT INTO ann SELECT p_label, i, id FROM mem_v FOR SYSTEM_TIME AS OF @ts ORDER BY VEC_DISTANCE(embedding, @v) LIMIT 10;
      INSERT INTO timing VALUES (p_label, i, TIMESTAMPDIFF(MICROSECOND, t0, NOW(6)));
      SET t0 = NOW(6);
      INSERT INTO exact_nn SELECT p_label, i, id FROM mem_v FOR SYSTEM_TIME AS OF @ts IGNORE INDEX (embedding) ORDER BY VEC_DISTANCE_COSINE(embedding, @v) LIMIT 10;
      INSERT INTO ex_t VALUES (TIMESTAMPDIFF(MICROSECOND, t0, NOW(6)));
    END IF;
    SET i = i + 1;
  END WHILE;
  INSERT INTO results
  SELECT p_label,
    (SELECT COUNT(*) FROM mem_v FOR SYSTEM_TIME ALL) - (SELECT COUNT(*) FROM mem_v),
    (SELECT COUNT(a.id) / COUNT(*) FROM exact_nn e LEFT JOIN ann a ON a.label = e.label AND a.qid = e.qid AND a.id = e.id WHERE e.label = p_label),
    (SELECT COUNT(*) FROM ann WHERE label = p_label),
    (SELECT COUNT(*) FROM (SELECT qid FROM ann WHERE label = p_label GROUP BY qid HAVING COUNT(*) < 10) s),
    MAX(CASE WHEN r = 125 THEN us END) / 1000, MAX(CASE WHEN r = 238 THEN us END) / 1000, MAX(CASE WHEN r = 248 THEN us END) / 1000,
    (SELECT MAX(CASE WHEN r2 = 125 THEN us END) / 1000 FROM (SELECT us, ROW_NUMBER() OVER (ORDER BY us) r2 FROM ex_t) e2)
  FROM (SELECT us, ROW_NUMBER() OVER (ORDER BY us) r FROM timing WHERE label = p_label) z;
END//
DELIMITER ;
