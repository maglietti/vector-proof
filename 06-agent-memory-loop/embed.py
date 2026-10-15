# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Embed text lines with Ollama qwen3-embedding:0.6b at 256 dimensions; print one JSON object per line: {text, vec}.

Usage: uv run embed.py <text> [<text> ...]
vec is the VEC_FromText literal body, '[x,y,...]'.
"""
import json
import sys
import urllib.request

DIMS = 256
texts = sys.argv[1:]
req = urllib.request.Request("http://localhost:11434/api/embed",
                             data=json.dumps({"model": "qwen3-embedding:0.6b", "input": texts, "dimensions": DIMS}).encode(),
                             headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req) as r:
    embs = json.load(r)["embeddings"]
for t, e in zip(texts, embs):
    print(json.dumps({"text": t, "dim": len(e), "vec": "[" + ",".join(f"{x:.5f}" for x in e) + "]"}))
