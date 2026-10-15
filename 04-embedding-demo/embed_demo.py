# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Embed the agent_memory notes and a question with a local Ollama model.

Prints a SQL script on stdout: the snippet's table at the model's dimension,
the three notes with real embeddings, and the retrieval query.
Usage: uv run embed_demo.py <model>
"""
import json
import sys
import urllib.request

MODEL = sys.argv[1]
NOTES = [
    ("billing-agent", "Refunds over 50 dollars need approval"),
    ("billing-agent", "Customer asked for a refund to the original card"),
    ("billing-agent", "Parcel left at the side door"),
]
QUESTION = "Can I refund this customer's 80 dollar charge without asking anyone?"


def embed(texts):
    body = json.dumps({"model": MODEL, "input": texts}).encode()
    req = urllib.request.Request("http://localhost:11434/api/embed", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        return json.load(r)["embeddings"]


vectors = embed([n for _, n in NOTES] + [QUESTION])
dim = len(vectors[0])


def lit(v):
    return "VEC_FromText('[" + ",".join(f"{x:.6f}" for x in v) + "]')"


print(f"-- {MODEL}: {dim} dimensions. Question: {QUESTION}", file=sys.stderr)
print("CREATE DATABASE IF NOT EXISTS demo; USE demo;")
print("DROP TABLE IF EXISTS agent_memory_real;")
print(f"""CREATE TABLE agent_memory_real (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  agent_id VARCHAR(64) NOT NULL,
  note TEXT NOT NULL,
  embedding VECTOR({dim}) NOT NULL,
  VECTOR INDEX (embedding) DISTANCE=cosine
);""")
for (agent, note), v in zip(NOTES, vectors):
    print(f"INSERT INTO agent_memory_real (agent_id, note, embedding) VALUES ('{agent}', '{note}', {lit(v)});")
print(f"SET @q = {lit(vectors[-1])};")
print("SELECT id, note, ROUND(VEC_DISTANCE_COSINE(embedding, @q), 4) AS dist FROM agent_memory_real ORDER BY dist;")
print("SELECT id, note FROM agent_memory_real ORDER BY VEC_DISTANCE(embedding, @q) LIMIT 2;")
