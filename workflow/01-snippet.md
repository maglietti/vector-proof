# 01: Test the 20-line agent memory snippet

To run: start a Claude Code session in the repository root and say "Follow `workflow/01-snippet.md`."

## Prompt

Follow `workflow/rules.md`.

Spin up MariaDB sandboxes with the MariaDB AI Plugins and test the snippet in `01-snippet/snippet.sql`. It creates an `agent_memory` table with a `VECTOR(3)` column and a cosine vector index, inserts three billing notes with hand-written vectors, and retrieves the two notes closest to a query vector.

1. List the available versions with `sandbox.list_available_versions`. Deploy one sandbox each for 11.8, 12.3, and the newest series, on ports 3411, 3412, and 3410. Don't pass a password.
2. Connect to each with `db.connect`, and run `01-snippet/snippet.sql` with `db.execute_sql_script` and `file_path`. The script also runs the cosine distance check, `EXPLAIN` of the retrieval query, `SHOW CREATE TABLE`, and `SHOW GLOBAL VARIABLES LIKE 'mhnsw%'`.
3. Save each version's result to `01-snippet/results/snippet-<version>.txt`. Render the JSON result sets as aligned text tables so a reader can compare them, and keep every value exactly as returned.
4. Compare the three results and report any difference other than the `VERSION()` line.
5. Check the MariaDB release notes for each version's status (GA, RC, or preview), and note it in the results.
6. Stop and delete the sandboxes.

## Done when

- Three result files exist, one per version.
- Your report states the two rows returned, the three distances, the `EXPLAIN` key, and whether the versions differ.

## Expected result

Rows 1 and 2 (the two refund notes), cosine distances 0.0014, 0.0017, and 0.9474, and `EXPLAIN` with `type = index` and `key = embedding` on every version.
