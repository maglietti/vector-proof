# 03: Swap in a real embedding model, and test what the agent decides

To run: "Follow `workflow/03-embedding-step.md`."

## Prompt

Follow `workflow/rules.md`.

The stage 01 vectors are hand-written. Replace them with real embeddings from a local model, then show what the retrieval result does to an agent's decision. Use the files in `04-embedding-demo/`.

1. Check that Ollama serves `qwen3-embedding:0.6b`. Generate the SQL with `uv run 04-embedding-demo/embed_demo.py qwen3-embedding:0.6b > 04-embedding-demo/embed-demo.sql`. It embeds the three notes and the question "Can I refund this customer's 80 dollar charge without asking anyone?" at 1,024 dimensions.
2. Deploy a 12.3 sandbox without a password. Run `embed-demo.sql`, then `step2-proof.sql`, with `db.execute_sql_script` in one session, because the second script uses `@q` from the first. Record the distance of each note, the `LIMIT 1` result, the `LIMIT 2` result, and the policy and event lookups after the `kind` column is added.
3. Ask before you pull `qwen3:4b` (about 2.5 GB). Then run `uv run 04-embedding-demo/ask_llm.py qwen3:4b 10`. It gives each retrieved context to the LLM 10 times and counts `DECISION: YES` and `DECISION: NO`. Run 1 uses temperature 0, and the others use 0.7.
4. Save the outputs to `04-embedding-demo/results/step2-proof-<version>.txt` and `step2-llm-decisions.txt`, and delete the sandbox.
5. Explain the result in plain words. Say which note ranked first and why, what the LLM saw and decided with each query, and whether the database or the query caused any wrong decision.

## Done when

- Both result files exist, and your explanation answers "what would the agent have done?" for each query.

## Expected result

The customer's request ranks first (0.3264), ahead of the approval rule (0.3621). With `LIMIT 1` the LLM never sees the rule and approves the refund at temperature 0 (3 YES in 10 runs). With `LIMIT 2`, or with separate policy and event lookups, it refuses in 10 of 10 runs. The database returned the correct order. The query asked for the single most similar note, and similar isn't the same as relevant.

## Notes from the first run

- `qwen3:4b` reasons in its reply even with thinking turned off. Give it room (`num_predict` of 1,500) and parse a required final `DECISION:` line, or every answer gets cut off before the decision.
- Not every local model can generate text. Check that the model supports chat before you build on it.
