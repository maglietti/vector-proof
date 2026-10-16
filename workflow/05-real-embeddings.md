# 05: Recall, latency, filters, and live writes on 200,000 real embeddings

To run: "Follow `workflow/05-real-embeddings.md`."

## Prompt

Follow `workflow/rules.md`.

Synthetic clusters flatter an index. Rerun the scale test on two public embedding datasets that developers can download and check, with the scripts in `03-real-embeddings/`.

1. Ask before each download. Then run `./data/download.sh all`. It fetches the first Wikipedia MiniLM Parquet file (613 MB, 384 dimensions) and the first three DBpedia OpenAI files (1.1 GB, 1,536 dimensions).
2. Profile both datasets before you use them, and record the results for the write-up's data section. Cover the row count, columns, distinct articles or entities, text length percentiles, vector dimensions, vector norms, how the file is sorted, and the license.
3. Build the load files with `./03-real-embeddings/run.sh prep`. It shuffles with seed 42, writes 100,000 rows and 250 held-out queries per dataset, and writes the unused DBpedia rows for the writer. This step runs Python only, not SQL.
4. Deploy 12.3 and 11.8 sandboxes without passwords, with `mhnsw_max_cache_size` at 2 GB and an InnoDB buffer pool of 4 GB.
5. Load the TSV files with `db.execute_sql_script` and the generated `gen/load-*.sql` scripts. They use `LOAD DATA LOCAL INFILE`. Test it first with a 1,000-row file. If the MCP server can't read a local file for `LOAD DATA LOCAL`, stop and tell me.
6. Build both vector indexes (`M=16`, cosine). They take 3 to 9 minutes each.
7. Run `gen/bench-*.sql`. It measures recall@10 against an exact `IGNORE INDEX` baseline at `ef_search` 20, 40, 100, and 200, then with `WHERE agent_id = 'agent-3'` at 20, 100, and 400. It also records p50, p95, and p99 over 250 queries, the exact scan's latency, `EXPLAIN`, and `Handler_read_rnd_next`.
8. Run the mixed load on the 1,536-dimension table with `mixed-setup.sql`, `mixed-procs.sql`, and `mixed-report.sql`. That's one writer at 20 inserts per second, four readers, and one prober for 60 seconds, then the four readers alone. The test needs six concurrent sessions. Check first whether the MCP server allows six open connections with calls running at the same time. If it doesn't, stop and tell me.
9. Save every result to `03-real-embeddings/results/` with the version in the name, and delete the sandboxes.

## Done when

- Per version and dataset: recall and latency at each `ef_search`, filtered recall and latency, and the scan baseline.
- Mixed load: reads per second with and without writes, read and insert latency, and how many new rows the prober found and how fast.
- A data profile for each dataset, ready for the write-up.

## Notes from the first run

- On 12.3.3 at `ef_search` 20, recall@10 was 0.988 (384 dimensions) and 0.979 (1,536), with p99 of 0.89 ms and 1.65 ms. Exact scans took 45 ms and 138 ms at p50. 11.8.9 had lower recall at the same setting.
- Filtered recall on real data was 0.96 to 0.998. At 1,536 dimensions with a 10% filter, the index's p95 (50 ms) matched an exact filtered scan (52 ms).
- About 18 inserts per second cut read throughput 4 to 5 times and raised read p99 from about 4.5 ms to about 30 ms. The prober found 99.7% to 99.8% of new rows as the top result, about 30 ms after commit. The misses were search misses, not visibility gaps.
- The Wikipedia file holds the 3,681 most-viewed articles, about 66 paragraphs each. Disclose that, because it makes queries easier than unrelated text would.
- `agent_id` is a label added by the scripts, not part of either dataset. Say so wherever filtered results appear.
