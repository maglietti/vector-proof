-- Step 2 proof. Run in the same session as embed-demo.sql, which creates
-- demo.agent_memory_real and sets @q to the question's embedding.
-- Usage: cat embed-demo.sql step2-proof.sql | ../sandbox.sh sql <port>

-- What the agent sees with LIMIT 1:
SELECT id, note FROM agent_memory_real ORDER BY VEC_DISTANCE(embedding, @q) LIMIT 1;

-- What the agent sees with LIMIT 2:
SELECT id, note FROM agent_memory_real ORDER BY VEC_DISTANCE(embedding, @q) LIMIT 2;

-- The fix: label each note by kind, and look up policies separately.
ALTER TABLE agent_memory_real ADD COLUMN kind ENUM('policy', 'event') NOT NULL DEFAULT 'event';
UPDATE agent_memory_real SET kind = 'policy' WHERE note = 'Refunds over 50 dollars need approval';
SELECT id, kind, note FROM agent_memory_real ORDER BY id;

-- Policies that apply to the question, and recent events, as two indexed lookups:
SELECT id, kind, note, ROUND(VEC_DISTANCE_COSINE(embedding, @q), 4) AS dist
FROM agent_memory_real WHERE kind = 'policy' ORDER BY VEC_DISTANCE(embedding, @q) LIMIT 1;
SELECT id, kind, note, ROUND(VEC_DISTANCE_COSINE(embedding, @q), 4) AS dist
FROM agent_memory_real WHERE kind = 'event' ORDER BY VEC_DISTANCE(embedding, @q) LIMIT 1;
EXPLAIN SELECT id FROM agent_memory_real WHERE kind = 'policy' ORDER BY VEC_DISTANCE(embedding, @q) LIMIT 1;
