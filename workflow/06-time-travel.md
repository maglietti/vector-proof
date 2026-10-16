# 06: Ask what the agent knew before the policy changed

To run: "Follow `workflow/06-time-travel.md`."

## Prompt

Follow `workflow/rules.md`. Read the `dev:mariadb-system-versioned-tables` skill first.

Test whether built-in row history is a real differentiator for agent memory against pgvector, with the files in `05-time-travel/`. Test MariaDB's side as hard as PostgreSQL's.

1. Run `05-time-travel/tt-small.sql` on a 12.3 sandbox (no password): a three-row system-versioned table with a vector index. Show the current answer, the `FOR SYSTEM_TIME AS OF` answer from before the policy update, and `EXPLAIN` for both.
2. Build the load files with `./05-time-travel/tt-run.sh prep`. This runs Python only. It uses the MiniLM file from prompt 05: 20,000 original memories, 250 queries, and 10 rounds of 20,000 revised vectors, all real and distinct.
3. Run `tt-setup.sql` and `tt-procs.sql` with `db.execute_sql_script`. Then measure `CALL measure(...)` at 0x history. For each of 10 rounds, run `CALL revise(n)`, and measure the current-state and the `AS OF` original query at 1x, 5x, and 10x history. Each revision round runs 80 to 100 seconds, so test the MCP call length first.
4. Run `tt-partition.sql` to check whether `PARTITION BY SYSTEM_TIME` can keep history out of the vector index.
5. Check the PostgreSQL side in the official documentation. Is SQL feature T180, "System-versioned tables", supported in the current release and in the development docs? What would a pgvector stack need to answer the same question? Cite the URLs.
6. Save the results to `05-time-travel/results/` with the version in the name, and delete the sandbox.
7. Give a verdict. Is the claim safe, and what wording and caveats does it need?

## Done when

- A table of recall, p50, p99, and exact-scan p50 for both queries at each history level, the partition test result, and the PostgreSQL sources.

## Notes from the first run (12.3.3)

- The `AS OF` query kept recall at 0.974 or higher with p99 under 18 ms at 200,000 history rows.
- Current-state recall fell from 0.986 to 0.922, and p99 rose from 2.6 ms to 69 ms, because history rows share the vector index.
- `PARTITION BY SYSTEM_TIME` failed with `ERROR 1506: Partitioned tables do not support VECTOR`.
- PostgreSQL 18.6 and the 20devel docs both listed T180 as unsupported.
- Safe wording: "built-in memory history, searchable in one query", with a retention policy (`DELETE HISTORY`). Don't say "free".
