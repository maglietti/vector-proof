# 02: Prove index use at 100,000 rows

To run: "Follow `workflow/02-synthetic-scale.md`."

## Prompt

Follow `workflow/rules.md`.

Three rows can't show that a vector index does the work, because a scan of three rows is fast too. Prove index use at 100,000 rows on 11.8, 12.3, and the newest series, with the scripts in `02-synthetic-100k/`.

1. Deploy one sandbox per version without a password. Set `mhnsw_max_cache_size` to 1 GB on each (`SET GLOBAL`), and record the InnoDB buffer pool size, because it changes full-scan times.
2. Run `load.sql` with `db.execute_sql_script`. It generates 100,000 rows of 384-dimension vectors inside the server, from `SIN((row mod 100) * 7.3 + dim * 1.7)` plus uniform noise of ±0.3, which makes 100 clusters. `agent_id` is row number modulo 10.
3. Run `index.sql` to build the vector index (`M=16`, cosine). This takes 4 to 6 minutes per version. Test first whether `db.execute_sql_script` returns for a call this long. If it times out, stop and tell me (see `rules.md`).
4. Run `bench.sql`: 50 queries through the index and through `IGNORE INDEX`, recall@10, p50, p95, and max latency, `EXPLAIN` and `ANALYZE FORMAT=JSON` of both paths, and `Handler_read_rnd_next` for each. Run it twice and keep the second, warm run.
5. Run `filter.sql`: the vector query with `WHERE agent_id = 'agent-3'`, with a 1-in-1,000 filter, and filtered recall over 50 queries. Then repeat the filtered recall with `mhnsw_ef_search` at 20, 100, and 400.
6. Run the transaction test against the stage 01 table, using two `db.connect` sessions. Session A inserts an uncommitted near-duplicate of the query vector. Session B searches while A's transaction is open. Then A rolls back, and B searches again. Finally, an autocommit insert is searched for from a new session. Record which ids each session sees.
7. Save every result to `02-synthetic-100k/results/` with the version in the name, and delete the sandboxes.

## Done when

- Per version: recall@10, warm p50 and p95 through the index and the scan, `Handler_read_rnd_next` and InnoDB pages accessed for both paths, and filtered recall at each `ef_search`.
- The transaction test shows what each session saw.

## Notes from the first run

- The index read 11 rows (`Handler_read_rnd_next`) against 100,012 for the scan on every version, and touched 31 pages against 11,145.
- Synthetic filtered recall was about 0.8 and didn't improve with `ef_search`. The synthetic set is a hard case for filters, so don't use it for filtered-recall claims. Prompt 05 measures filters on real data.
- Warm latency through the index was about 1 ms. The first, cold run was 25 times slower, so always report the warm run.
