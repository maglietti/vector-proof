# Vector proof: agent memory in MariaDB

This repository holds every script and raw result behind the "Agent Memory in One Table" write-up in [`writeup/`](#the-write-up). The write-up supports the positioning "The Unified Open Database for the Agentic Enterprise" under the tagline "Lead with proof a developer can verify". All tests ran on 2026-10-15 on an Apple M4 Pro (14 cores, 24 GB RAM).

Each numbered directory is one stage. Every stage has its scripts at the top level and its raw output in `results/`. You can rerun any stage on its own.

## Layout

| Path | What it holds |
| --- | --- |
| `sandbox.sh` | Starts, stops, and connects to a local MariaDB sandbox with `mariadb-shell`. Every stage uses it. |
| `data/` | `download.sh`, which fetches the Parquet datasets for stages 03 and 05. The files are not in the repository. See [Get the data](#get-the-data). |
| `01-snippet/` | The 20-line agent memory example, run on 11.8.9, 12.3.3, and 13.1.1. |
| `02-synthetic-100k/` | Index proof, recall, latency, and filtered search on 100,000 synthetic 384-dimension vectors. Also the transaction isolation test. |
| `03-real-embeddings/` | Recall, latency, filtered search, and mixed read/write load on 100,000 real embeddings at 384 and 1,536 dimensions. |
| `04-embedding-demo/` | The stage 01 example with real embeddings from a local Ollama model. |
| `05-time-travel/` | Vector search on a system-versioned table as history grows. The candidate differentiator against pgvector. |
| `06-agent-memory-loop/` | The agent storing and recalling its own memory through the MariaDB AI Plugins MCP server. |
| `writeup/` | The write-up in HTML and Markdown, its five diagrams as SVG files, and the script that builds the Markdown and SVG files from the HTML. See [The write-up](#the-write-up). |
| `workflow/` | Nine prompts and a shared rules file that rebuild every stage and the write-up with Claude Code and the MariaDB AI Plugins. Start at [workflow/README.md](workflow/README.md). |

## The write-up

`writeup/` holds the write-up that presents these results. Its evidence links point at the raw results in the stage folders of this repository.

- [writeup/agent-memory-proof.html](writeup/agent-memory-proof.html) is the source. Open it in a browser. It follows the system light or dark theme.
- [writeup/README.md](writeup/README.md) is the same content in Markdown, with one line per paragraph so the text reflows at any width.
- [writeup/diagrams/](writeup/diagrams/) holds the five diagrams as standalone SVG files with their own light and dark styles: [agent loop](writeup/diagrams/01-agent-loop.svg), [actor model](writeup/diagrams/02-actor-model.svg), [schema](writeup/diagrams/03-schema.svg), [architecture](writeup/diagrams/04-architecture.svg), and [call-flow ladder](writeup/diagrams/05-call-flow-ladder.svg).
- [writeup/export.py](writeup/export.py) rebuilds the Markdown and SVG files from the HTML. It fails if any evidence link points at a missing file. Run it after you edit the HTML.

```bash
uv run writeup/export.py
```

## Data

| Dataset | Source | Rows used | Dimensions | Model | Stages |
| --- | --- | --- | --- | --- | --- |
| Snippet notes | hand-written | 3 | 3 | none | 01 |
| Synthetic clusters | generated in SQL | 100,000 | 384 | none | 02 |
| Wikipedia paragraphs | `maloyan/wikipedia-22-12-en-embeddings-all-MiniLM-L6-v2`, file 0 | 100,000 + 250 queries (03); 20,000 + 200,000 revisions + 250 queries (05) | 384 | all-MiniLM-L6-v2 | 03, 05 |
| DBpedia entities | `KShivendu/dbpedia-entities-openai-1M`, files 0 to 2 | 100,000 + 250 queries + 15,136 writer rows | 1,536 | OpenAI text-embedding-ada-002 | 03 |
| Agent notes | hand-written | 3 notes + 1 question (04); 5 notes + 3 questions (06) | 1,024 (04), 256 (06) | qwen3-embedding 0.6B through Ollama | 04, 06 |

- **Wikipedia file 0** (`data/wiki-minilm-train-00000.parquet`, 613 MB, fetched by `data/download.sh wiki`) holds 242,538 paragraphs from the 3,681 most-viewed articles of the December 2022 English Wikipedia, sorted by page views. Paragraphs run 209 to 1,042 characters (10th to 90th percentile), with a median of 528. Columns: `id`, `title`, `text`, `url`, `wiki_id`, `views`, `paragraph_id`, `langs`, `emb`. Vectors are 384 32-bit floats with length 1.0. The dataset declares no license; the text is Wikipedia's (CC BY-SA). The whole dataset is 35,167,920 rows in 145 files.
- **DBpedia files 0 to 2** (1.1 GB, fetched by `data/download.sh dbpedia`) hold 115,386 of the dataset's 1,000,000 entities. Columns: `_id`, `title`, `text`, `openai`. Vectors have 1,536 floats with length 1.0 and are converted to 32-bit floats on load. License: MIT.
- **Split:** `prep.py` and `prep_tt.py` shuffle with seed 42. The first rows are loaded, and the next 250 are queries, so no query is in the table. Queries are passages, not questions.
- **`agent_id`** is row number modulo 10, a label added for the filter tests. It is uniform (10% per agent) and unrelated to content.
- **Load format:** TSV with each vector as hex-encoded 32-bit little-endian floats, loaded with `LOAD DATA LOCAL INFILE ... SET embedding = UNHEX(@h)`.
- **Synthetic clusters** come from `02-synthetic-100k/load.sql`: each value is `SIN((row mod 100) * 7.3 + dim * 1.7)` plus uniform noise of ±0.3, so 100 clusters. Use them only for index-use proof, not for recall claims.

### Get the data

The Parquet files total about 1.7 GB, so the repository does not include them. `.gitignore` also excludes them and the TSV load files built from them. Stages 01, 02, 04, and 06 need no download.

Fetch both datasets from Hugging Face with `curl`:

```bash
./data/download.sh
```

To fetch only one dataset, pass `wiki` (613 MB, stages 03 and 05) or `dbpedia` (1.1 GB, stage 03 only). The script skips files that are already present, so you can run it again safely.

```bash
./data/download.sh wiki
```

The `prep` steps of stages 03 and 05 then convert the Parquet files into TSV load files in each stage's `load/` folder.

## Prerequisites

- **`mariadb-shell`**, the MariaDB command-line shell. The MariaDB AI Plugins install it on first use at `~/.local/bin/mariadb-shell`. The tests used version 26.9.5.
- **The `mariadb` client** on your `PATH`, for loading data and running SQL files. The tests used the Homebrew client.
- **MariaDB server binaries** under `~/.local/share/mariadb-sandbox-server/<version>/`. The plugin's `sandbox.deploy` tool downloads them there. If a version is missing, ask your agent once to "deploy a MariaDB 12.3 sandbox", or set `MARIADBD_HOME` to any MariaDB installation directory.
- **`uv`**, the Python package and project manager, for every Python script (stages 03, 04, and 05, and `writeup/export.py`). Each script declares its Python version and dependencies in an inline metadata block (PEP 723), so `uv run <script>.py` creates a cached, isolated environment and installs nothing globally. Install it with `brew install uv` or see <https://docs.astral.sh/uv/getting-started/installation/>.
- **Ollama with `qwen3-embedding:0.6b`**, for stages 04 and 06 only. Pull it with `ollama pull qwen3-embedding:0.6b`.

## Sandboxes

`sandbox.sh` gives every sandbox the settings the tests used: root password `sandbox`, TLS off, `LOAD DATA LOCAL` on, a 2 GB `mhnsw_max_cache_size`, and a 4 GB InnoDB buffer pool.

```bash
./sandbox.sh up 3412 12.3.3
```

```bash
./sandbox.sh sql 3412 < 01-snippet/snippet.sql
```

```bash
./sandbox.sh down 3412
```

The ports used in the tests were 3411 for 11.8.9, 3412 for 12.3.3, and 3410 for 13.1.1. Any free port works.

One difference from the recorded runs: stages 01 and 02 ran on the server defaults (16 MB vector cache, 128 MB buffer pool), except where noted below. `sandbox.sh` always applies the larger settings, so a rerun of stage 02 shows faster full scans than `02-synthetic-100k/results/`.

## Stage 01: the snippet

The script creates the `agent_memory` table, inserts three notes, and runs the retrieval query. It also runs the distance check, `EXPLAIN`, `SHOW CREATE TABLE`, and the `mhnsw_*` variables.

```bash
./sandbox.sh sql 3412 < 01-snippet/snippet.sql
```

Expected result: ids 1 and 2 (the two refund notes), cosine distances 0.0014, 0.0017, and 0.9474, and a plan with `key = embedding`. The three files in `01-snippet/results/` differ only in the `VERSION()` line. They were produced with `mariadb-shell --sql --table -f snippet.sql`.

`01-snippet/docker-test.sql` is the same test from the first run, which used the Docker images `mariadb:latest` (13.0.2) and `mariadb:11.8` (11.8.8) instead of sandboxes. Those results matched.

## Stage 02: synthetic 100K and transactions

The data is generated inside the server: 100,000 rows, 384 dimensions, 100 clusters with noise, and `agent_id` spread over 10 agents.

1. Load the rows (about 18 seconds):

   ```bash
   ./sandbox.sh sql 3412 < 02-synthetic-100k/load.sql
   ```

2. Build the index (`M=16`, cosine). With a 1 GB or larger vector cache this took 218 to 335 seconds. With the 16 MB default it was only 64% done after 21 minutes.

   ```bash
   ./sandbox.sh sql 3412 < 02-synthetic-100k/index.sql
   ```

3. Run 50 queries for recall@10, latency, `EXPLAIN`, `ANALYZE`, and the handler counters:

   ```bash
   ./sandbox.sh sql 3412 < 02-synthetic-100k/bench.sql
   ```

4. Run the filtered search tests (`WHERE agent_id`, and a 1-in-1,000 filter):

   ```bash
   ./sandbox.sh sql 3412 < 02-synthetic-100k/filter.sql
   ```

The transaction test needs the stage 01 table on the same port. It shows that an uncommitted row is invisible to other sessions, a rolled-back row leaves search, and a committed row is found at once.

```bash
./02-synthetic-100k/transactions.sh 3412
```

`results/warm-latency.txt` and `results/efsearch-12.3.3.txt` came from rerunning the `bench()` and `fbench()` procedures (created by the scripts above) on a warm cache, with `SET SESSION mhnsw_ef_search` at 20, 100, and 400.

## Stage 03: real embeddings and mixed load

Datasets: 100,000 Wikipedia paragraphs embedded with all-MiniLM-L6-v2 (384 dimensions), and 100,000 DBpedia entities embedded with OpenAI ada-002 (1,536 dimensions, MIT license). The rows are shuffled with seed 42. 250 held-out rows are the queries, so no query matches a loaded row.

1. Download both datasets (about 1.7 GB, see [Get the data](#get-the-data)):

   ```bash
   ./data/download.sh
   ```

2. Build the TSV load files in `03-real-embeddings/load/`:

   ```bash
   ./03-real-embeddings/run.sh prep
   ```

3. Load both datasets (3 and 9 seconds):

   ```bash
   ./03-real-embeddings/run.sh load 3412
   ```

4. Build both indexes in parallel (201 to 524 seconds when four builds ran at the same time):

   ```bash
   ./03-real-embeddings/run.sh index 3412
   ```

5. Measure recall@10 and p50, p95, and p99 at `ef_search` 20, 40, 100, and 200, then filtered at 20, 100, and 400, against an exact `IGNORE INDEX` baseline:

   ```bash
   ./03-real-embeddings/run.sh bench 3412
   ```

6. Run the mixed load: one writer at 20 inserts per second, four readers, and one visibility prober for 60 seconds, then the four readers alone for 60 seconds:

   ```bash
   ./03-real-embeddings/run.sh mixed 3412
   ```

Run `bench` before `mixed`, because `mixed` adds rows to `dbpedia1536`. The recorded results cover 11.8.9 and 12.3.3. `results/mixed-misses-12.3.3.txt` shows that the 2 rows the prober missed were present and were their own exact top match, so they were search misses, not visibility gaps.

## Stage 04: the embedding step

The script embeds the three notes and a question with Ollama, then prints a SQL script that rebuilds the stage 01 table at 1,024 dimensions and runs the retrieval.

```bash
uv run 04-embedding-demo/embed_demo.py qwen3-embedding:0.6b > 04-embedding-demo/embed-demo.sql
```

```bash
./sandbox.sh sql 3412 < 04-embedding-demo/embed-demo.sql
```

Expected result: both refund notes first (distances near 0.33 and 0.36), the parcel note last (near 0.62). The customer's request ranks above the approval rule.

`step2-proof.sql` shows what that ranking does to an agent. Run it in the same session as `embed-demo.sql`, which sets `@q` to the question's vector. It returns the `LIMIT 1` and `LIMIT 2` results, then adds a `kind` column (`policy` or `event`) and looks up each kind separately through the vector index.

```bash
cat 04-embedding-demo/embed-demo.sql 04-embedding-demo/step2-proof.sql | ./sandbox.sh sql 3412
```

`ask_llm.py` gives each retrieved context to a local LLM (`qwen3:4b` through Ollama, pulled with `ollama pull qwen3:4b`, about 2.5 GB). It asks the refund question 10 times per context and counts the `DECISION: YES` and `DECISION: NO` answers. Run 1 uses temperature 0, and runs 2 to 10 use temperature 0.7.

```bash
uv run 04-embedding-demo/ask_llm.py qwen3:4b 10
```

Recorded result (`results/step2-proof-12.3.3.txt` and `results/step2-llm-decisions.txt`): with `LIMIT 1`, the LLM sees only the customer's request and approves the refund on its own (YES at temperature 0, 3 YES in 10 runs). With `LIMIT 2`, or with the policy and event lookups, it says NO in 10 of 10 runs.

## Stage 05: time-travel memory

The table `mem_v` is `WITH SYSTEM VERSIONING` and has a cosine vector index. It starts with 20,000 memories. Each of 10 revision rounds gives every memory a new real embedding, so the old version moves to history. The run measures the current-state query and the `FOR SYSTEM_TIME AS OF` query for the original state, at 0x, 1x, 5x, and 10x history. Each measurement uses 250 queries against an exact `IGNORE INDEX` baseline.

The prep step needs the Wikipedia file. Fetch it first if stage 03 has not already done so.

```bash
./data/download.sh wiki
```

```bash
./05-time-travel/tt-run.sh prep
```

```bash
./05-time-travel/tt-run.sh run 3412
```

One run takes about 20 minutes. Each revision round takes 80 to 95 seconds.

Recorded result on 12.3.3 (`results/timetravel-12.3.3.txt`): every query returned 10 rows and used the vector index. As history grew from 0 to 200,000 rows, current-state recall@10 fell from 0.986 to 0.922, and its p99 rose from 2.58 ms to 68.87 ms. The `AS OF` query for the original state kept recall at 0.974 or higher, with p99 under 18 ms.

The three-row version runs in seconds:

```bash
./sandbox.sh sql 3412 < 05-time-travel/tt-small.sql
```

`tt-partition.sql` shows that history partitioning can't separate history from current rows when the table has a vector index. On 12.3.3 it fails with `ERROR 1506 (HY000): Partitioned tables do not support VECTOR` (`results/tt-partition-12.3.3.txt`).

```bash
./sandbox.sh sql 3412 < 05-time-travel/tt-partition.sql
```

The PostgreSQL side was checked against the official documentation. PostgreSQL 18.6 lists T180 "System-versioned tables" under Unsupported Features. So does the development documentation (PostgreSQL 20devel), which includes everything in PostgreSQL 19.

- <https://www.postgresql.org/docs/current/unsupported-features-sql-standard.html>
- <https://www.postgresql.org/docs/devel/unsupported-features-sql-standard.html>

## Stage 06: agent memory loop through MCP

This stage ran through the agent, not a script. `results/agent-memory-loop.txt` lists every tool call and its raw output. To repeat it, install the plugin in Claude Code:

```text
/plugin marketplace add mariadb/ai-plugins
/plugin install dev@mariadb
```

Then give the agent this prompt:

```text
Deploy a MariaDB 12.3 sandbox. Create agentmem.agent_memory with a VECTOR(256) column and a cosine vector index. Embed five notes with 06-agent-memory-loop/embed.py and store them with db.execute_sql, passing each vector as a VEC_FromText parameter. Close the connection, open a new one, embed three questions the same way, and retrieve the top 2 notes for each.
```

`embed.py` calls Ollama with `"dimensions": 256`, which `qwen3-embedding` supports. Smaller vectors keep each MCP call short. The MCP server can't read SQL files from directories that weren't allowed with `mcp.setup`, so the agent passes SQL inline.

Recorded result: 2 of 3 questions found the expected memory at rank 1, and 3 of 3 within the top 2.

## Cleanup

- Stop and delete each sandbox with `./sandbox.sh down <port>`.
- The downloaded Parquet files in `data/` and the TSV files in `03-real-embeddings/load/` and `05-time-travel/load/` hold about 3 GB when fully populated. `.gitignore` excludes all of them. Delete them when you no longer need to rerun stages 03 and 05.
