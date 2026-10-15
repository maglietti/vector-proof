USE scale;
DELIMITER //
-- Writer: inserts p_rate rows per second for p_secs seconds, autocommit, timing each insert.
CREATE OR REPLACE PROCEDURE writer(p_rate INT, p_secs INT)
BEGIN
  DECLARE i INT DEFAULT 1;
  DECLARE t0 DATETIME(6);
  DECLARE stop_at DATETIME(6) DEFAULT NOW(6) + INTERVAL p_secs SECOND;
  WHILE NOW(6) < stop_at DO
    SET t0 = NOW(6);
    INSERT INTO dbpedia1536 (id, agent_id, note, embedding)
      SELECT 200000 + n, CONCAT('agent-', n % 10), note, v FROM incoming WHERE n = i;
    INSERT INTO wlog (id, insert_us, committed_at) VALUES (200000 + i, TIMESTAMPDIFF(MICROSECOND, t0, NOW(6)), NOW(6));
    SET i = i + 1;
    DO SLEEP(GREATEST(0, 1 / p_rate - TIMESTAMPDIFF(MICROSECOND, t0, NOW(6)) / 1e6));
  END WHILE;
END//
-- Reader: runs the held-out queries in a loop for p_secs seconds.
CREATE OR REPLACE PROCEDURE reader(p_reader INT, p_secs INT)
BEGIN
  DECLARE i INT DEFAULT 1;
  DECLARE t0 DATETIME(6);
  DECLARE stop_at DATETIME(6) DEFAULT NOW(6) + INTERVAL p_secs SECOND;
  SET SESSION mhnsw_ef_search = 40;
  WHILE NOW(6) < stop_at DO
    SELECT v INTO @v FROM q_dbpedia1536 WHERE qid = (i + p_reader * 50) % 250 + 1;
    SET t0 = NOW(6);
    SELECT GROUP_CONCAT(id) INTO @ids FROM (SELECT id FROM dbpedia1536 ORDER BY VEC_DISTANCE(embedding, @v) LIMIT 10) x;
    INSERT INTO reads_log VALUES (p_reader, (i + p_reader * 50) % 250 + 1, TIMESTAMPDIFF(MICROSECOND, t0, NOW(6)), NOW(6));
    SET i = i + 1;
  END WHILE;
END//
-- Prober: from another session, searches for each newly committed row with its own vector.
CREATE OR REPLACE PROCEDURE prober(p_secs INT)
BEGIN
  DECLARE v_id INT;
  DECLARE v_at DATETIME(6);
  DECLARE t0 DATETIME(6);
  DECLARE stop_at DATETIME(6) DEFAULT NOW(6) + INTERVAL p_secs SECOND;
  SET SESSION mhnsw_ef_search = 40;
  WHILE NOW(6) < stop_at DO
    SET v_id = NULL;
    SELECT id, committed_at INTO v_id, v_at FROM wlog WHERE probed = 0 ORDER BY id DESC LIMIT 1;
    IF v_id IS NOT NULL THEN
      UPDATE wlog SET probed = 1 WHERE id <= v_id AND probed = 0;
      SELECT v INTO @pv FROM incoming WHERE n = v_id - 200000;
      SET t0 = NOW(6);
      SELECT id INTO @top FROM dbpedia1536 ORDER BY VEC_DISTANCE(embedding, @pv) LIMIT 1;
      INSERT INTO probe_log VALUES (v_id, @top = v_id, TIMESTAMPDIFF(MICROSECOND, v_at, NOW(6)), TIMESTAMPDIFF(MICROSECOND, t0, NOW(6)));
    ELSE
      DO SLEEP(0.005);
    END IF;
  END WHILE;
END//
DELIMITER ;
