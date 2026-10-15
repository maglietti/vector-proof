-- Three-row time-travel check: what did the agent know before the policy changed?
-- Usage: ../sandbox.sh sql <port> < tt-small.sql
CREATE DATABASE IF NOT EXISTS demo;
USE demo;
SELECT VERSION();
DROP TABLE IF EXISTS agent_memory_v;
CREATE TABLE agent_memory_v (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  agent_id VARCHAR(64) NOT NULL,
  note TEXT NOT NULL,
  embedding VECTOR(3) NOT NULL,
  VECTOR INDEX (embedding) DISTANCE=cosine
) WITH SYSTEM VERSIONING;
INSERT INTO agent_memory_v (agent_id, note, embedding) VALUES
  ('billing-agent', 'Refunds over 50 dollars need approval', VEC_FromText('[1, 0, 0]')),
  ('billing-agent', 'Customer asked for a refund to the original card', VEC_FromText('[0.9, 0.1, 0]')),
  ('billing-agent', 'Parcel left at the side door', VEC_FromText('[0, 1, 0]'));
SET @before = NOW(6);
DO SLEEP(1);
UPDATE agent_memory_v SET note = 'Refunds over 100 dollars need approval' WHERE id = 1;
-- What the agent knows now:
SELECT id, note FROM agent_memory_v ORDER BY VEC_DISTANCE(embedding, VEC_FromText('[0.95, 0.05, 0]')) LIMIT 2;
-- What the agent knew before the policy change:
SELECT id, note FROM agent_memory_v FOR SYSTEM_TIME AS OF @before ORDER BY VEC_DISTANCE_COSINE(embedding, VEC_FromText('[0.95, 0.05, 0]')) LIMIT 2;
EXPLAIN SELECT id, note FROM agent_memory_v ORDER BY VEC_DISTANCE(embedding, VEC_FromText('[0.95, 0.05, 0]')) LIMIT 2;
EXPLAIN SELECT id, note FROM agent_memory_v FOR SYSTEM_TIME AS OF @before ORDER BY VEC_DISTANCE_COSINE(embedding, VEC_FromText('[0.95, 0.05, 0]')) LIMIT 2;
