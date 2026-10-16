# 07: The agent stores and recalls its own memory through MCP

To run: "Follow `workflow/07-agent-memory.md`." Run it after prompts 01 to 06, so the agent has real findings to remember.

## Prompt

Follow `workflow/rules.md`.

Use MariaDB as your own memory through the MariaDB AI Plugins MCP server, and record every tool call.

1. Deploy a 12.3 sandbox without a password, and connect with `db.connect`.
2. Create `agentmem.agent_memory` with `id`, `agent_id`, `note`, `created_at`, and `embedding VECTOR(256)` with a cosine vector index.
3. Pick five specific things you learned in prompts 01 to 06. Embed each one with `uv run 06-agent-memory-loop/embed.py "<note>" ...`, which calls Ollama `qwen3-embedding:0.6b` at 256 dimensions. Store each note with `db.execute_sql`, passing the vector as a parameter to `VEC_FromText(?)`.
4. Close the connection with `db.close`, and open a new one, so recall can't come from the session.
5. Write three questions that each should recall one specific note, without reusing the note's wording. Embed them, and retrieve the top 2 notes for each with `ORDER BY VEC_DISTANCE(...) LIMIT 2`.
6. Write `06-agent-memory-loop/results/agent-memory-loop.txt`. List every tool call with its arguments and raw result, with vectors elided as `[256 floats]`, the expected note for each question, and the rank where it came back.
7. Delete the sandbox.

## Done when

- The transcript shows the store turn, the new connection, and the recall turn, plus how many questions found the expected note at rank 1 and in the top 2.

## Notes from the first run

- 2 of 3 questions found the expected note at rank 1, and all 3 in the top 2. Report a miss as a miss.
- The plugin has no embedding step. The agent calls the embedding model itself and passes each vector as a SQL parameter.
- 256-dimension vectors keep each MCP call short. qwen3-embedding supports a `dimensions` option.
