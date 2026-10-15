CREATE DATABASE IF NOT EXISTS demo;
USE demo;
DROP TABLE IF EXISTS mem;
CREATE TABLE mem (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  agent_id VARCHAR(64) NOT NULL,
  note VARCHAR(64) NOT NULL,
  embedding VECTOR(384) NOT NULL
);
-- 100,000 rows, 384 dimensions, 100 clusters with noise; agent_id spread over 10 agents.
INSERT INTO mem (agent_id, note, embedding)
SELECT CONCAT('agent-', s.seq % 10), CONCAT('note ', s.seq),
  VEC_FromText(CONCAT('[', (SELECT GROUP_CONCAT(ROUND(SIN((s.seq % 100) * 7.3 + t.seq * 1.7) + (RAND() - 0.5) * 0.6, 4) ORDER BY t.seq) FROM seq_1_to_384 t), ']'))
FROM seq_1_to_100000 s;
SELECT COUNT(*) FROM mem;
