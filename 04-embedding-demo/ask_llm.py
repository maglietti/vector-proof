# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Ask a local LLM the Step 2 refund question with each retrieved context, and count its decisions.

Usage: uv run ask_llm.py [model] [runs]   (defaults: qwen3:4b, 10)

Each context is exactly what a query in step2-proof.sql returned. The LLM sees only those notes.
Run 1 of each context uses temperature 0. The other runs use temperature 0.7, to show how stable
the decision is. Thinking mode is off, so the answer is the LLM's direct reply.
"""
import json
import re
import sys
import urllib.request

MODEL = sys.argv[1] if len(sys.argv) > 1 else "qwen3:4b"
RUNS = int(sys.argv[2]) if len(sys.argv) > 2 else 10
QUESTION = "Can I refund this customer's 80 dollar charge without asking anyone?"
SYSTEM = ("You are a billing support agent. Answer using only the notes from your memory below. "
          "Explain briefly, then end with a final line that is exactly DECISION: YES or DECISION: NO.")
CONTEXTS = {
    "LIMIT 1": ["Customer asked for a refund to the original card"],
    "LIMIT 2": ["Customer asked for a refund to the original card", "Refunds over 50 dollars need approval"],
    "policy + event": ["Policy: Refunds over 50 dollars need approval", "Event: Customer asked for a refund to the original card"],
}


def ask(notes, temperature, seed):
    user = "Notes from memory:\n" + "\n".join(f"- {n}" for n in notes) + f"\n\nQuestion: {QUESTION}"
    body = {"model": MODEL, "stream": False, "think": False,
            "messages": [{"role": "system", "content": SYSTEM}, {"role": "user", "content": user}],
            "options": {"temperature": temperature, "seed": seed, "num_predict": 1500}}
    req = urllib.request.Request("http://localhost:11434/api/chat", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        text = json.load(r)["message"]["content"]
    found = re.findall(r"DECISION:\s*\**\s*(YES|NO)", text, re.I)
    return (found[-1].upper() if found else "NONE"), " ".join(text.split())


print(f"model: {MODEL}\nquestion: {QUESTION}\n")
for name, notes in CONTEXTS.items():
    answers = [ask(notes, 0 if i == 0 else 0.7, 42 + i) for i in range(RUNS)]
    yes = sum(d == "YES" for d, _ in answers)
    no = sum(d == "NO" for d, _ in answers)
    print(f"== context {name}: {notes}")
    print(f"   decisions over {RUNS} runs: YES {yes}, NO {no}, none {RUNS - yes - no}")
    for i, (d, text) in enumerate(answers):
        print(f"   run {i + 1} ({'temperature 0' if i == 0 else 'temperature 0.7'}): {d} | {text[-400:]}")
    print()
