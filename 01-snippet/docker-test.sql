SELECT VERSION();
CREATE TABLE agent_memory (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  agent_id VARCHAR(64) NOT NULL,
  note TEXT NOT NULL,
  embedding VECTOR(3) NOT NULL,
  VECTOR INDEX (embedding) DISTANCE=cosine
);
INSERT INTO agent_memory (agent_id, note, embedding) VALUES
  ('billing-agent', 'Refunds over 50 dollars need approval', VEC_FromText('[1, 0, 0]')),
  ('billing-agent', 'Customer asked for a refund to the original card', VEC_FromText('[0.9, 0.1, 0]')),
  ('billing-agent', 'Parcel left at the side door', VEC_FromText('[0, 1, 0]'));
SELECT id, note
FROM agent_memory
ORDER BY VEC_DISTANCE(embedding, VEC_FromText('[0.95, 0.05, 0]'))
LIMIT 2;
SELECT id, note, ROUND(VEC_DISTANCE_COSINE(embedding, VEC_FromText('[0.95, 0.05, 0]')),4) AS dist FROM agent_memory ORDER BY dist;
EXPLAIN SELECT id, note FROM agent_memory ORDER BY VEC_DISTANCE(embedding, VEC_FromText('[0.95, 0.05, 0]')) LIMIT 2;
