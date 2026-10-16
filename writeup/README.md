# Agent memory in one table, one query, one database

Positioning: The Unified Open Database for the Agentic Enterprise

On Monday, a billing agent learns that refunds over 50 dollars need approval. On Tuesday, a customer asks it for an 80 dollar refund. The right answer depends on one thing: whether the agent can find Monday's note again.

> Lead with proof a developer can verify.

## An agent is only as good as what it can recall

The usual fix is a second database. Business data stays in the application database, embeddings go to a vector store, and a sync job copies one into the other. Every note now lives in two places, and the copy the agent searches can lag behind the one it wrote.

MariaDB keeps the note, the agent that owns it, and its embedding in the same row. Recall is one SQL query against the same server that holds everything else. Every claim on this page comes with the script and the raw output a developer needs to verify it. The page starts with 20 lines of SQL and keeps adding load until something gives.

![Agent loop: receive a task, recall from MariaDB by vector search, reason, act through tool calls, remember by inserting the outcome into MariaDB. An embedding model turns text into vectors for both the recall and the remember steps.](diagrams/01-agent-loop.svg)

*The agent loop. MariaDB sits on two of its edges. Recall reads past notes by vector distance, and the remember step writes each new note back in the same row as its vector. The embedding model, which runs outside the database, produces the vectors for both steps.*

## Step 1 · Start with 20 lines of SQL

One table, three notes, and one query. The `VECTOR(3)` column holds each note's embedding, and the `VECTOR INDEX` lets the server find the closest ones without reading every row. The three-number vectors are written by hand so the answer is easy to check.

agent_memory.sql:

```sql
-- One table holds an agent's notes and their embeddings.
CREATE TABLE agent_memory (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  agent_id VARCHAR(64) NOT NULL,
  note TEXT NOT NULL,
  embedding VECTOR(3) NOT NULL,
  VECTOR INDEX (embedding) DISTANCE=cosine
);

INSERT INTO agent_memory (agent_id, note, embedding) VALUES
  ('billing-agent', 'Refunds over 50 dollars need approval', VEC_FromText('[1, 0, 0]')),
  ('billing-agent', 'Customer asked for a refund to the original card', VEC_FromText('[0.9, 0.1, 0]')),
  ('billing-agent', 'Parcel left at the side door', VEC_FromText('[0, 1, 0]'));

-- Retrieve the two notes closest to a query vector.
SELECT id, note
FROM agent_memory
ORDER BY VEC_DISTANCE(embedding, VEC_FromText('[0.95, 0.05, 0]'))
LIMIT 2;
```

The query vector points toward "refunds". Both refund notes come back, and the note about a parcel at the side door drops out of the top 2.

mariadb-shell · MariaDB 12.3.3 LTS · 2026-10-15:

```text
+----+--------------------------------------------------+
| id | note                                             |
+----+--------------------------------------------------+
|  1 | Refunds over 50 dollars need approval            |
|  2 | Customer asked for a refund to the original card |
+----+--------------------------------------------------+
```

The cosine distances show why. Both refund notes sit within 0.002 of the query, while the parcel note is almost a full unit away.

| id | note | cosine distance |
| --- | --- | ---: |
| 1 | Refunds over 50 dollars need approval | 0.0014 |
| 2 | Customer asked for a refund to the original card | 0.0017 |
| 3 | Parcel left at the side door | 0.9474 |

The script runs unchanged on MariaDB 11.8.9, 12.3.3, and 13.1.1. A `diff` of the three raw transcripts differs only in the `VERSION()` line.

## Step 2 · Swap in a real embedding model, and watch one LIMIT decide the refund

Hand-written vectors make the answer easy to check, but real vectors come from an embedding model. Here the embedding model is qwen3-embedding 0.6B, run locally through Ollama. It turns each of the three notes into 1,024 numbers. Then the agent asks Tuesday's question: "Can I refund this customer's 80 dollar charge without asking anyone?"

MariaDB 12.3.3 · distance from the question to each note:

```text
+----+--------------------------------------------------+--------+
| id | note                                             | dist   |
+----+--------------------------------------------------+--------+
|  2 | Customer asked for a refund to the original card | 0.3264 |
|  1 | Refunds over 50 dollars need approval            | 0.3621 |
|  3 | Parcel left at the side door                     | 0.6217 |
+----+--------------------------------------------------+--------+
```

Look at the order. The closest note is the customer's request, not the refund rule. To the embedding model, "refund this customer's charge" sounds more like "customer asked for a refund" than like "refunds over 50 dollars need approval". The request wins by 0.036. MariaDB returns exactly that order, and every distance is correct.

What happens next depends on how many notes the agent asks for. To find out, each result went to a local LLM (qwen3:4b through Ollama) with the instruction to answer from those notes only. Each version ran 10 times.

| the agent's query | notes the LLM sees | first answer | YES / NO in 10 runs |
| --- | --- | --- | ---: |
| `LIMIT 1` | Customer asked for a refund to the original card | **YES**, refunds 80 dollars with no approval | 3 / 7 |
| `LIMIT 2` | the request and the approval rule | **NO**, asks for approval first | 0 / 10 |
| policy lookup plus event lookup | the approval rule and the request, each labeled | **NO**, asks for approval first | 0 / 10 |

With `LIMIT 1`, the approval rule never reaches the agent. The LLM can't follow a rule it can't see, so on its first run it approves the refund on its own:

qwen3:4b · LIMIT 1 · temperature 0:

```text
The notes state the customer asked for a refund to the original card, but
do not indicate any requirement to consult others before processing. Since
the notes provide no restrictions on independent action, the refund can be
processed without additional approval. DECISION: YES
```

One more note in the result changes the outcome. With `LIMIT 2`, the same LLM gets the rule as well and refuses every time:

qwen3:4b · LIMIT 2 · temperature 0:

```text
The notes state that refunds over 50 dollars require approval. Since the
customer's charge is 80 dollars (over 50), approval is needed. Therefore,
the refund cannot be processed without asking for approval. DECISION: NO
```

So the database didn't make the mistake. It answered the query it was given. The mistake was in the query, because `LIMIT 1` asks for the single most similar note, and similar isn't the same as relevant. A rule and a request about the same refund look alike to an embedding model, and either one can come out on top.

A bigger `LIMIT` helps, but it only makes the rule likely to show up. The relational half of the table makes it certain. Label each note with its kind, and look up the applicable policy and the latest event as two separate queries. The policy can then never be crowded out by a request that sounds like it:

MariaDB 12.3.3 · one column, two lookups:

```sql
ALTER TABLE agent_memory_real ADD COLUMN kind ENUM('policy', 'event') NOT NULL DEFAULT 'event';

SELECT id, kind, note FROM agent_memory_real
WHERE kind = 'policy' ORDER BY VEC_DISTANCE(embedding, @q) LIMIT 1;
+----+--------+---------------------------------------+--------+
| id | kind   | note                                  | dist   |
+----+--------+---------------------------------------+--------+
|  1 | policy | Refunds over 50 dollars need approval | 0.3621 |
+----+--------+---------------------------------------+--------+

SELECT id, kind, note FROM agent_memory_real
WHERE kind = 'event' ORDER BY VEC_DISTANCE(embedding, @q) LIMIT 1;
+----+-------+--------------------------------------------------+--------+
| id | kind  | note                                             | dist   |
+----+-------+--------------------------------------------------+--------+
|  2 | event | Customer asked for a refund to the original card | 0.3264 |
+----+-------+--------------------------------------------------+--------+

-- EXPLAIN: type index, key embedding, Using where
```

Both lookups still go through the vector index. With the rule and the request labeled, the LLM said NO in all 10 runs. That's the case for keeping memory in a relational database. The embedding finds what's similar, and a plain column guarantees that the rule always reaches the agent.

Run details: the embeddings and SQL are in `04-embedding-demo/embed-demo.sql` and `step2-proof.sql`, and the LLM runs in `ask_llm.py`. The LLM got the instruction "Answer using only the notes from your memory below", followed by the notes and the question. It had to end with `DECISION: YES` or `DECISION: NO`. Run 1 used temperature 0, and runs 2 to 10 used temperature 0.7, with seeds 42 to 51. The SQL output above is trimmed for width (the policy and event queries also selected the rounded distance). The full answers are in the evidence files.

## Step 3 · Add 100,000 rows to see the index do the work

Three rows can't show that an index matters, because scanning three rows is fast anyway. So the table grows to 100,000 rows of 384-dimension vectors, generated in SQL as 100 clusters with noise. Then the same query runs two ways, through the vector index and with `IGNORE INDEX` to force a full scan.

MariaDB 12.3.3 · one query, two paths:

```text
-- through the vector index
| table | type  | key       | rows   | Extra          |
| mem   | index | embedding | 10     |                |
Handler_read_rnd_next   11        InnoDB pages accessed   31

-- IGNORE INDEX (embedding): full scan
| table | type  | key       | rows   | Extra          |
| mem   | ALL   | NULL      | 100000 | Using filesort |
Handler_read_rnd_next   100012    InnoDB pages accessed   11145
```

The index reads 11 rows and touches 31 storage pages. The scan has to read all 100,012 rows across 11,145 pages, on every version tested.

| version | recall@10 | index p50 | index p95 | scan p50 | index build |
| --- | ---: | ---: | ---: | ---: | ---: |
| 11.8.9 LTS | 1.000 | 1.36 ms | 2.00 ms | 192.7 ms | 315 s* |
| 12.3.3 LTS | 1.000 | 1.12 ms | 1.34 ms | 190.8 ms | 335 s* |
| 13.1.1 | 0.998 | 0.97 ms | 1.13 ms | 193.3 ms | 218 s |

50 queries per version, top 10 neighbors, warm cache, `mhnsw_ef_search` = 20 (the default), `M` = 16, `mhnsw_max_cache_size` = 1 GB. Recall compares the index's top 10 with the exact top 10 from the full scan. Apple M4 Pro, 14 cores, 24 GB RAM. *The 11.8.9 and 12.3.3 builds ran at the same time, so their build times aren't comparable with 13.1.1. These scans ran on the default 128 MB InnoDB buffer pool, which slows them down. Synthetic clusters are also easier than real text, so treat this step as proof of index use, not as a benchmark.

## Step 4 · Replace the synthetic data with 200,000 real embeddings

Synthetic clusters flatter an index, so the next run uses two public datasets that developers can download and check. Both come from Hugging Face. One holds Wikipedia paragraphs, the kind of text chunks an agent keeps as knowledge. The other holds DBpedia entities embedded with OpenAI's model, the kind of reference data an agent looks things up in.

| dataset | source | rows used | dims | model | used in |
| --- | --- | ---: | ---: | --- | --- |
| Snippet notes | hand-written | 3 | 3 | none | the example |
| Synthetic clusters | generated in SQL | 100,000 | 384 | none | proof at scale |
| Wikipedia paragraphs | Hugging Face | 100,000 + 220,250 | 384 | all-MiniLM-L6-v2 | real embeddings, time travel |
| DBpedia entities | Hugging Face | 115,386 | 1,536 | OpenAI text-embedding-ada-002 | real embeddings, mixed load |
| Agent notes | hand-written | 3 + 5 | 1,024 / 256 | qwen3-embedding 0.6B | embedding step, agent memory |

### Wikipedia paragraphs, 384 dimensions

- **Source:** the `maloyan/wikipedia-22-12-en-embeddings-all-MiniLM-L6-v2` dataset holds 35,167,920 English Wikipedia paragraphs from the December 2022 dump, in 145 Parquet files. Its columns are `id`, `title`, `text`, `url`, `wiki_id`, `views`, `paragraph_id`, `langs`, and `emb`. The dataset declares no license, and the text is Wikipedia's, under CC BY-SA.
- **The slice used here:** the first Parquet file (613 MB) holds 242,538 paragraphs from 3,681 articles. The file is sorted by page views, so these are the most-read articles, such as "Deaths in 2022", YouTube, Elon Musk, the United States, and Elizabeth II. Paragraphs run 209 to 1,042 characters (10th to 90th percentile), with a median of 528, which is close to the chunk size a retrieval system stores.
- **Vectors:** each paragraph has 384 32-bit floats from the sentence-transformers model all-MiniLM-L6-v2. Every vector has length 1.0000, so cosine distance is the right metric.
- **What it stands in for:** an agent's knowledge memory, with many short passages about the same topics. At about 66 paragraphs per article, each query has close neighbors from its own article. That's realistic for chunked documents, and kinder to an index than unrelated text.

### DBpedia entities, 1,536 dimensions

- **Source:** the `KShivendu/dbpedia-entities-openai-1M` dataset (MIT license) holds 1,000,000 DBpedia entities in 26 Parquet files. Each row has an `_id`, a `title`, a short abstract in `text`, and the embedding in `openai`.
- **The slice used here:** the first three files (1.1 GB) hold 115,386 entities.
- **Vectors:** each entity has 1,536 floats from OpenAI text-embedding-ada-002, loaded as 32-bit floats, the format a `VECTOR` column stores. Every vector has length 1.0000. Public vector benchmarks commonly use this set.
- **What it stands in for:** an agent's reference memory, a knowledge base embedded with a hosted model, at the vector size of OpenAI's widely used embeddings.

### How the test uses the data

- **Rows and queries:** each dataset is shuffled with a fixed seed (42). The first 100,000 rows go into the table, and the next 250 become queries. No query is in the table, so every query is a new passage looking for its nearest neighbors.
- **Queries are passages, not questions:** a held-out paragraph searches for similar paragraphs, while a real agent searches with a question. Step 2 and the last step cover the question-to-note case on a small scale.
- **The `agent_id` label:** row number modulo 10, so each agent owns exactly 10% of the rows, unrelated to content. Real agents usually remember different topics, so their rows would cluster in vector space. That case isn't tested here.
- **Loading:** the vectors travel as hex-encoded 32-bit floats in TSV files and load with `LOAD DATA LOCAL INFILE ... SET embedding = UNHEX(@h)`. Loading takes 3 seconds for 100,000 rows at 384 dimensions and 9 seconds at 1,536.

With real data, the index still finds about 98 of every 100 true nearest neighbors at the default setting, and answers in under 2 milliseconds at p99. The exact scan takes 45 to 138 milliseconds at p50.

| MariaDB 12.3.3 | ef_search | recall@10 | p50 | p95 | p99 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 384 dims, index | 20 | 0.988 | 0.30 ms | 0.70 ms | 0.89 ms |
| 384 dims, index | 100 | 0.997 | 0.81 ms | 1.39 ms | 1.68 ms |
| 384 dims, full scan | n/a | 1.000 | 44.95 ms | 46.89 ms | 51.08 ms |
| 1,536 dims, index | 20 | 0.979 | 0.58 ms | 1.15 ms | 1.65 ms |
| 1,536 dims, index | 100 | 0.995 | 2.37 ms | 6.75 ms | 8.77 ms |
| 1,536 dims, full scan | n/a | 1.000 | 138.32 ms | 142.03 ms | 147.92 ms |

Raising `mhnsw_ef_search`, the number of candidates the index examines, buys back the rest of the recall for a few milliseconds. On 11.8.9, recall at the default is lower (0.968 at 384 dimensions and 0.949 at 1,536) and reaches 0.994 and 0.988 at 200. Each version had one index build, so part of that gap may be build-to-build variation.

## Step 5 · Give each agent its own memory in the same table

An enterprise runs more than one agent. Each agent works like an actor in the actor model. It keeps its own state and talks to the other agents only through messages. In the table, an agent's state is the set of rows with its `agent_id`, and it reads them with a filtered vector query.

![Actor model: three agents exchange messages with each other and never read each other's memory. Each agent reads and writes only its own rows in one shared agent_memory table, selected by WHERE agent_id. One vector index covers all agents' rows, so every filtered query walks the shared graph.](diagrams/02-actor-model.svg)

*Agents as actors. They exchange messages and never read each other's memory. In the database, each agent's memory is its rows, selected with `WHERE agent_id = ?`, and one vector index covers every agent. Each filtered query walks the shared graph and skips other agents' rows, so the cost is the latency in the table below. Per-agent database users and grants would make this isolation enforced, not only filtered. That part is not tested here.*

Every filtered query returns the full 10 rows, and recall stays high, from 0.959 to 0.998 depending on `mhnsw_ef_search`. The cost is latency, because the index walks past other agents' rows to collect 10 of the right ones.

| MariaDB 12.3.3 | ef_search | recall@10 | p50 | p95 | p99 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 384 dims, index + WHERE | 20 | 0.959 | 2.59 ms | 5.50 ms | 9.11 ms |
| 384 dims, index + WHERE | 400 | 0.996 | 11.15 ms | 19.85 ms | 23.57 ms |
| 384 dims, scan + WHERE | n/a | 1.000 | 22.49 ms | 23.24 ms | 23.62 ms |
| 1,536 dims, index + WHERE | 20 | 0.990 | 12.56 ms | 49.94 ms | 66.32 ms |
| 1,536 dims, index + WHERE | 400 | 0.998 | 83.57 ms | 218.03 ms | 308.70 ms |
| 1,536 dims, scan + WHERE | n/a | 1.000 | 51.59 ms | 52.84 ms | 54.81 ms |

At 1,536 dimensions with a filter that keeps 10% of the rows, the index's p95 (50 ms) already matches an exact filtered scan (52 ms). For a filter that selective at this size, the exact scan is the better plan, and it's still one SQL query on the same table.

## Step 6 · Keep reading while the agent writes

Agents learn while they work, so their memory changes under load. This run keeps four readers searching the 1,536-dimension table for 60 seconds while a writer adds about 18 new rows per second. A fifth session searches for each new row with that row's own vector, to see how soon it shows up.

| 1,536 dims, 60 s | reads/s | read p50 | read p95 | read p99 | insert p50 | insert p99 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 12.3.3, 4 readers, no writes | 2,837 | 1.19 ms | 3.26 ms | 4.51 ms | n/a | n/a |
| 12.3.3, 4 readers + 18.5 inserts/s | 524 | 5.67 ms | 20.04 ms | 33.12 ms | 15.57 ms | 41.85 ms |
| 11.8.9, 4 readers, no writes | 3,049 | 1.09 ms | 3.03 ms | 4.24 ms | n/a | n/a |
| 11.8.9, 4 readers + 18.5 inserts/s | 708 | 3.89 ms | 15.83 ms | 28.55 ms | 13.28 ms | 35.24 ms |

- **New rows are searchable right away:** the prober finds 1,107 of 1,109 new rows on 12.3.3 (1,106 on 11.8.9) as the top result, on average 30 to 33 ms after commit, including its own polling time. The few misses are search misses, not visibility gaps, because an exact search returns each missed row as its own top match.
- **Writes cost reads:** 18 inserts per second cut read throughput by 4 to 5 times and raise the read p99 from about 4.5 ms to 29 to 33 ms. Each insert, including its vector index update, takes 13 to 16 ms at p50.
- **Transactions hold:** in a separate test, a row written inside an open transaction is invisible to other sessions' searches, and it leaves search after `ROLLBACK`.

## Step 7 · Ask what the agent knew before the policy changed

Back to the billing agent. If the refund limit moves from 50 to 100 dollars, an auditor will ask what the agent knew when it approved last week's refunds. A system-versioned table keeps every past version of a row, and the server maintains that history on its own. With a vector index on the same table, one query searches the agent's memory as it was at any past moment.

MariaDB 12.3.3:

```sql
CREATE TABLE mem_v ( ... embedding VECTOR(384) NOT NULL,
  VECTOR INDEX (embedding) DISTANCE=cosine ) WITH SYSTEM VERSIONING;

SELECT id FROM mem_v FOR SYSTEM_TIME AS OF @before_policy_change
ORDER BY VEC_DISTANCE(embedding, @question) LIMIT 10;
-- plan: type index, key embedding, Using where
```

![Schema: the agent_memory table has id, agent_id, note, and a VECTOR embedding column, plus two invisible timestamp columns added by system versioning. The primary key indexes id. One vector index covers the embedding of both current rows and history rows; queries filter by row_end or AS OF time while they walk that index.](diagrams/03-schema.svg)

*One row holds the relational columns and the embedding. System versioning adds two invisible timestamp columns and keeps old versions in the same table, so current and history rows sit in one vector index graph. Each query applies its time filter while it walks that graph. That is why current-state recall fell as history grew. A vector index can't be split by history partitions (error 1506).*

To see how this holds up as history grows, the table starts with 20,000 real MiniLM vectors. Ten revision rounds give every memory a new real embedding, and each round moves the old versions to history. Each measurement uses 250 held-out queries against an exact `IGNORE INDEX` baseline.

| query | history rows | recall@10 | p50 | p99 | exact p50 |
| --- | ---: | ---: | ---: | ---: | ---: |
| current state | 0 | 0.986 | 0.36 ms | 2.58 ms | 9.69 ms |
| current state | 20,000 | 0.980 | 1.18 ms | 10.75 ms | 17.49 ms |
| current state | 100,000 | 0.955 | 5.09 ms | 37.56 ms | 43.58 ms |
| current state | 200,000 | 0.922 | 11.93 ms | 68.87 ms | 74.71 ms |
| AS OF original | 20,000 | 0.996 | 0.75 ms | 2.02 ms | 15.63 ms |
| AS OF original | 100,000 | 0.983 | 2.60 ms | 8.15 ms | 37.48 ms |
| AS OF original | 200,000 | 0.974 | 5.41 ms | 17.62 ms | 63.69 ms |

- **The past is searchable:** every query returns the full 10 rows and uses the vector index. The query for the original memories keeps recall at 0.974 or higher, with p99 under 18 ms, even with 200,000 history rows.
- **History has a cost:** history rows share the vector index with current rows. At 10 versions per memory, current-state recall falls to 0.922, and its p99 (69 ms) nears the exact scan's p50 (75 ms). Each round of 20,000 updates takes 78 to 100 seconds, and the rounds slow as history grows.
- **Partitions don't help:** the usual fix, `PARTITION BY SYSTEM_TIME`, is refused with `ERROR 1506: Partitioned tables do not support VECTOR`. Pruning history with `DELETE HISTORY BEFORE` is the lever that's left.
- **PostgreSQL has no equivalent:** the PostgreSQL 18.6 documentation lists SQL feature T180, "System-versioned tables", as unsupported, and so does the development documentation (20devel, which includes PostgreSQL 19). A pgvector stack needs triggers and a separate history table with its own vector index, or an extension.

## Step 8 · Let an agent run the tests, and remember what it learned

Nobody installed a database by hand for any of this. A coding agent, Claude Code, ran every step through the MariaDB AI Plugins. The plugin's tools run on `mariadb-shell`, the MariaDB command-line shell, which the plugin starts as a local MCP server. MCP (Model Context Protocol) is the standard way an agent calls external tools.

![Architecture: Claude Code calls the mariadb-shell MCP server from the MariaDB AI Plugins. Its sandbox tools start and stop local MariaDB server processes, and its db tools send SQL to them. Ollama turns text into vectors for the agent. Inside MariaDB, one agent_memory table holds notes, vectors, and history rows, all covered by one vector index.](diagrams/04-architecture.svg)

*The agent talks to one MCP server. Through the `sandbox.*` tools it starts and stops local MariaDB processes, then sends SQL to them with `db.*`. Embeddings come from Ollama, outside the plugin. Inside the server, notes, vectors, and history rows share one table and one vector index. Without an agent, `sandbox.sh` drives the same `mariadb-shell` sandbox commands, and the `mariadb` client sends the same SQL.*

Installing the plugin takes two commands in Claude Code. On first use, the plugin installs `mariadb-shell` if it's missing. Before the MCP server can reach a database, run `mariadb-shell -- mcp setup` once per machine.

install the plugin in Claude Code:

```text
/plugin marketplace add mariadb/ai-plugins
/plugin install dev@mariadb
```

The agent deployed a local sandbox for each version, ran every script, and deleted the sandboxes afterward. There was no Docker, no cloud account, and no setup script.

| step | tool | what it did |
| --- | --- | --- |
| 1 | sandbox.list_available_versions | Listed 11.8.9, 12.3.3, 13.1.1 |
| 2 | sandbox.deploy | Started one local server per version on ports 3411, 3412, 3410 |
| 3 | mariadb-shell --sql -f | Ran the exact script on each version and saved the raw output |
| 4 | mariadb client | Bulk-loaded 100,000 rows and ran the scale, filter, and transaction tests |
| 5 | sandbox.stop, sandbox.delete | Shut down and removed all three sandboxes |

Then the test turned around. The agent used MariaDB as its own memory, through the same MCP server. It embedded five things it had learned during these runs, stored them, and closed the connection. On a new connection, it embedded three questions and recalled the top 2 memories for each.

![Call flow ladder across five participants: developer, Claude Code, Ollama, the mariadb-shell MCP server, and the MariaDB sandbox. Setup deploys the sandbox. Turn 1 connects, embeds five notes, and inserts them. Turn 2 opens a new connection, embeds a question, and runs a vector query that walks the index and returns the top 2 notes. Cleanup stops and deletes the sandbox.](diagrams/05-call-flow-ladder.svg)

*The run in call order. Solid arrows are requests and dashed arrows are replies. The agent is the only participant that talks to both the embedding model and the MCP server. The plugin never converts text to vectors, and it only sees each vector as a SQL parameter. Turn 2 opens a new connection, so the recall comes from what the database stored, not from the session.*

| question | memory at rank 1 | dist |
| --- | --- | ---: |
| My vector index build on a big table is crawling. What should I check first? | Raise mhnsw_max_cache_size to at least 1 GB | 0.263 |
| Do developers need a GitHub token to install the MariaDB agent plugin? | The repositories are public, so no token is needed | 0.178 |
| Which MariaDB version should the launch page use in its examples? | The repositories are public (the expected "12.3 is the current LTS" came second, 0.303) | 0.267 |

The right memory comes first for 2 of the 3 questions and is in the top 2 for all 3. The plugin has no embedding step, so the agent calls the embedding model itself and passes each vector as a SQL parameter. The MCP server also refuses to read SQL files from directories that weren't allowed with `mcp.setup`, so the agent sends its SQL inline. That refusal is a sensible default for an agent tool.

## Use Docker, or ask your agent

Two Docker commands run the example on the current long-term support release:

shell:

```bash
docker run -d --name agent-memory -e MARIADB_ROOT_PASSWORD=demo -e MARIADB_DATABASE=demo mariadb:12.3
docker exec -i agent-memory mariadb -uroot -pdemo demo --table < agent_memory.sql
```

Wait a few seconds after the first command for the server to start, and remove the container with `docker rm -f agent-memory` when you're done. With the plugin installed, you can hand the script to your agent with one sentence instead:

prompt:

```text
Spin up MariaDB 11.8 and 12.3 sandboxes, run agent_memory.sql on both, show me the results, then delete the sandboxes.
```

## One table carries the whole memory loop, with known costs

- **One row:** the note, the agent that owns it, its embedding, and its history live together, so there's no sync job between a relational store and a vector store.
- **One language:** recall is `ORDER BY VEC_DISTANCE(...) LIMIT k`, and any developer who reads SQL can follow it.
- **One transaction:** a new memory is searchable within milliseconds of commit, and a rolled-back one never shows up.
- **One open server:** everything here runs on the community server from public packages, with no license key or managed service.
- **The costs:** filtered search trades latency for recall, concurrent writes slow reads, and history shares the vector index. This page doesn't cover 1 million rows or questions-as-queries at scale.

## Appendix · Answers to the 14 review questions

Each item shows what was tested, the result, and what is still open. Items 1 to 3 decide what the opener can claim.

### Resolve

#### 1. Release dates and the external path

Status: PARTLY

- Both repositories are public now. An anonymous GitHub API call returns 200 for `mariadb-corporation/mariadb-shell` and `mariadb/ai-plugins`. No token is needed. The "Private repository" note in the plugin README (26.10.0) is out of date.
- Every release is still marked Pre-release: `ai-plugins` v26.10.3 (2026-10-15) and `mariadb-shell` v26.10.1 (2026-10-08). The launcher falls back to the newest prerelease, so installation works today.
- Open: whether a stable release ships before Nov 3. The repositories don't say. Ask the plugin and shell owners.
- Recommendation: lead externally with the SQL and Docker path. It needs no pre-release software. Make the agent path the second beat until stable releases exist.

#### 2. Exact statements and raw output on every version

Status: DONE

- Statements: the snippet as written, then `SELECT id, note, ROUND(VEC_DISTANCE_COSINE(embedding, VEC_FromText('[0.95, 0.05, 0]')), 4) AS dist FROM agent_memory ORDER BY dist;`, then `EXPLAIN` of the snippet's query, `SHOW CREATE TABLE`, and `SHOW GLOBAL VARIABLES LIKE 'mhnsw%'`.
- Run with `mariadb-shell --sql --table -f` on 11.8.9, 12.3.3, and 13.1.1. The raw transcripts are in the evidence files below.

#### 3. What `type = index` means, and proof of index use

Status: DONE

- For a normal B-tree, `type = index` means a full index scan. For a vector index, it means the optimizer reads rows in distance order from the HNSW graph and stops at the `LIMIT`, which is why `rows` shows 10. On its own, that line is not proof.
- The proof is the counters at 100,000 rows: `Handler_read_rnd_next` 11 against 100,012, and 31 InnoDB pages against 11,145. The scan's plan shows `ALL` and `Using filesort`. Results matched on all three versions.
- On 13.1.1, the new `INFORMATION_SCHEMA.VECTOR_INDEXES` view reports 100,000 nodes and 384 dimensions for the index.

#### 4. Version facts

Status: DONE

- Vector preview: 11.6.0-vector, 29 July 2024. First release with vectors: 11.7.1 (RC), 21 Nov 2024. First GA: 11.7.2 (rolling), 13 Feb 2025. First LTS: 11.8.2 GA, 4 Jun 2025.
- Enterprise Server: backported to 11.4.5-3. Enterprise Server 11.8 is GA from 11.8.3-1, 22 Oct 2025.
- 12.3 is the current LTS (12.3.3 GA, 24 Aug 2026). The docs list 13.0.1 as an RC and have no 13.1 release notes yet, so don't headline 13.1.1.
- The snippet's behavior is identical from 11.8.9 to 13.1.1, and so are the four `mhnsw_*` defaults. 12.3 adds faster distance calculations (MDEV-36205). 13.1 adds `INFORMATION_SCHEMA.VECTOR_INDEXES` (MDEV-34805).
- Source: the local `mariadb-docs` repository, commit cc40a6916 (13 Oct 2026).

#### 5. Which names and versions are public

Status: PARTLY

- Public: "MariaDB AI Plugins" is the title of ai-plugins.mariadb.org. The `dev@mariadb` install name, the repository names, and the version tags are public on GitHub.
- The versions are public pre-releases. Pinning 26.10.0 or 26.9.5 in launch copy will date it fast, so name the product and leave the version out.

### Explore

#### 6. Scale test with real embeddings

Status: DONE AT 100K

- Done: 100,000 real embeddings at 384 dimensions (MiniLM) and at 1,536 dimensions (OpenAI ada-002), on 11.8.9 and 12.3.3, with 250 held-out queries. On 12.3.3 at the default `ef_search` of 20: recall@10 of 0.988 and 0.979, with p99 of 0.89 ms and 1.65 ms. Exact scans took 45 ms and 138 ms at p50. The full tables are in Step 4 above.
- Embedding step: the plugin has none. A local Ollama model (qwen3-embedding 0.6B) embedded the snippet's notes and question, and the retrieval worked.
- Finding: the default `mhnsw_max_cache_size` is 16 MB. With that default, the 13.1.1 index build on synthetic data was only 64% done after 21 minutes. With 1 GB it finished in 218 seconds. Any public "run it yourself" at scale must set this.
- Not run: 1 million rows. Cite MariaDB's published 1 million OpenAI-embedding benchmark for that scale, and label it as MariaDB's own.

#### 7. Filtered search with `WHERE agent_id`

Status: CAVEAT

- Plan: the vector index is still used (`type = index`, `key = embedding`, `Using where`).
- Correctness: every returned row matched the filter. The query returned the full `LIMIT` of 10, even with a filter that matches 1 row in 1,000.
- Synthetic data: filtered recall@10 dropped to 0.78 to 0.85, and raising `mhnsw_ef_search` didn't help. The synthetic set is a hard case: most queries target clusters with few rows for the filtered agent.
- Real embeddings on 12.3.3: filtered recall@10 was 0.959 (384 dims) and 0.990 (1,536 dims) at `ef_search` 20, and 0.996 and 0.998 at 400. Higher `ef_search` costs latency. At 1,536 dims, the filtered index query's p95 (50 ms) matches an exact filtered scan (52 ms), so the exact scan is the better plan for a 10% filter at 100,000 rows.
- Claim implication: "filter and search in one query" is true, with high recall on real data. Don't claim the filtered path is faster than a scan at every size. Don't make the filtered query the opener.

#### 8. Transactions and live data

Status: DONE

- Isolation, tested on 11.8.9: during an open transaction, the writer's search included its new row and another session's search did not. After `ROLLBACK`, the row was gone from search.
- Under load (1,536 dims, 60 seconds, 4 readers, about 18.5 inserts per second): another session found 99.7% to 99.8% of new rows as the top search result, on average 30 to 33 ms after commit, including the prober's own polling. The few misses were search misses, not visibility gaps.
- Cost: concurrent writes cut read throughput from about 2,800 to 3,000 reads/s down to 524 to 708 reads/s, and raised the read p99 from about 4.5 ms to 29 to 33 ms. Inserts took 13 to 16 ms at p50, including the index update.
- Claim implication: "same live data, searchable within milliseconds of commit" is supported. "No impact on reads" is not.

#### 9. The 8 "not yet shown" ledger claims

Status: NEEDS INPUT

- The ledger wasn't shared with this run. Send the 8 claims, and each one can be mapped to plugin tool calls.

#### 10. The agent's own memory through the MCP server

Status: DONE

- Claude Code stored 5 memories with `db.execute_sql`, closed the connection, and recalled them by meaning on a new one. The expected memory came first for 2 of 3 questions and was in the top 2 for all 3 (Step 8 above).
- The embedding came from Ollama, outside the plugin. Small vectors (256 dimensions) keep each MCP call short.

### Alter

#### 11. Lead with the SQL or the agent prompt

Status: DECISION

- Recommendation: lead with the SQL. It runs on GA software today, and the agent prompt depends on pre-release tools (item 1). Use the agent run as the second beat: "your agent can do this too."

#### 12. A real differentiator against pgvector

Status: USE WITH SCOPE

- Parity points don't differentiate. pgvector also has one-table vectors, transactions, and filters. "No extension" is weak, because most managed PostgreSQL services ship pgvector.
- The differentiator holds: "ask what the agent knew at any past moment, in one vector query, with history the server keeps for you." It ran on 12.3.3 at 20,000 memories with up to 200,000 history rows. Recall stayed at 0.974 or higher for the past-state query, with p99 under 18 ms. PostgreSQL 18.6 and the development docs list system-versioned tables (T180) as unsupported.
- Scope it: history shares the vector index. At 10 versions per memory, current-state recall fell to 0.922 and p99 rose to 69 ms. Vector indexes can't use history partitions (error 1506). Say "built-in memory history", and pair it with a history retention policy (`DELETE HISTORY`). Don't say "free".

#### 13. Canonical names and capitalization

Status: DECISION

- In use today: "MariaDB AI Plugins" (DevHub title), "MariaDB plugin for Claude Code" (plugin README), "MariaDB Shell" (release titles), `mariadb-shell` (binary), and "a MariaDB Shell-based MCP server" (repository description).
- Flag: `mariadb-shell --help` prints an Oracle copyright line. Check how that reads before the shell gets a launch spotlight.

#### 14. Does the release change the snippet?

Status: DONE

- No syntax changes from 11.8 to 13.1. The default metric is still Euclidean, so keep `DISTANCE=cosine` explicit. The maximum is 16,383 dimensions.
- Optional idiom change: `VEC_DISTANCE` fails with error 4206 when the column has no vector index. `VEC_DISTANCE_COSINE` works with or without one, which is safer for copy-paste.

## Raw output from every run

- [snippet.sql](../01-snippet/snippet.sql)
- [snippet 11.8.9](../01-snippet/results/snippet-11.8.9.txt)
- [snippet 12.3.3](../01-snippet/results/snippet-12.3.3.txt)
- [snippet 13.1.1](../01-snippet/results/snippet-13.1.1.txt)
- [load.sql](../02-synthetic-100k/load.sql)
- [bench.sql](../02-synthetic-100k/bench.sql)
- [filter.sql](../02-synthetic-100k/filter.sql)
- [bench 11.8.9](../02-synthetic-100k/results/bench-11.8.9.txt)
- [bench 12.3.3](../02-synthetic-100k/results/bench-12.3.3.txt)
- [bench 13.1.1](../02-synthetic-100k/results/bench-13.1.1.txt)
- [filter 11.8.9](../02-synthetic-100k/results/filter-11.8.9.txt)
- [filter 12.3.3](../02-synthetic-100k/results/filter-12.3.3.txt)
- [filter 13.1.1](../02-synthetic-100k/results/filter-13.1.1.txt)
- [warm latency](../02-synthetic-100k/results/warm-latency.txt)
- [ef_search 12.3.3](../02-synthetic-100k/results/efsearch-12.3.3.txt)

### Real embeddings and mixed load

- [prep.py](../03-real-embeddings/prep.py)
- [prep_extra.py](../03-real-embeddings/prep_extra.py)
- [load template](../03-real-embeddings/load.sql.tpl)
- [bench template](../03-real-embeddings/bench.sql.tpl)
- [mixed-setup.sql](../03-real-embeddings/mixed-setup.sql)
- [mixed-procs.sql](../03-real-embeddings/mixed-procs.sql)
- [mixed-report.sql](../03-real-embeddings/mixed-report.sql)
- [embed_demo.py](../04-embedding-demo/embed_demo.py)
- [build 11.8.9](../03-real-embeddings/results/build-11.8.9.txt)
- [build 12.3.3](../03-real-embeddings/results/build-12.3.3.txt)
- [bench 11.8.9 384](../03-real-embeddings/results/bench-11.8.9-wiki384.txt)
- [bench 11.8.9 1,536](../03-real-embeddings/results/bench-11.8.9-dbpedia1536.txt)
- [bench 12.3.3 384](../03-real-embeddings/results/bench-12.3.3-wiki384.txt)
- [bench 12.3.3 1,536](../03-real-embeddings/results/bench-12.3.3-dbpedia1536.txt)
- [mixed 11.8.9](../03-real-embeddings/results/mixed-11.8.9-20rps.txt)
- [read-only 11.8.9](../03-real-embeddings/results/mixed-11.8.9-readonly.txt)
- [mixed 12.3.3](../03-real-embeddings/results/mixed-12.3.3-20rps.txt)
- [read-only 12.3.3](../03-real-embeddings/results/mixed-12.3.3-readonly.txt)
- [probe misses](../03-real-embeddings/results/mixed-misses-12.3.3.txt)
- [embedding demo](../04-embedding-demo/results/embed-demo-12.3.3.txt)
- [step2-proof.sql](../04-embedding-demo/step2-proof.sql)
- [ask_llm.py](../04-embedding-demo/ask_llm.py)
- [Step 2 SQL output](../04-embedding-demo/results/step2-proof-12.3.3.txt)
- [Step 2 LLM decisions](../04-embedding-demo/results/step2-llm-decisions.txt)

### Time travel and the agent's memory

- [prep_tt.py](../05-time-travel/prep_tt.py)
- [tt-setup.sql](../05-time-travel/tt-setup.sql)
- [tt-procs.sql](../05-time-travel/tt-procs.sql)
- [tt-run.sh](../05-time-travel/tt-run.sh)
- [time travel 12.3.3](../05-time-travel/results/timetravel-12.3.3.txt)
- [partition test 12.3.3](../05-time-travel/results/tt-partition-12.3.3.txt)
- [embed.py](../06-agent-memory-loop/embed.py)
- [agent memory loop](../06-agent-memory-loop/results/agent-memory-loop.txt)

Every script and raw result is in this repository. The top-level README explains how to rerun each stage and how to download the source datasets.

*Tested 2026-10-15 by Claude Code with the MariaDB AI Plugins (dev@mariadb 26.10.0, mariadb-shell 26.9.5) in local sandboxes running MariaDB 11.8.9, 12.3.3, and 13.1.1 on an Apple M4 Pro. Real-embedding and mixed-load runs used 11.8.9 and 12.3.3, and the time-travel and agent-memory runs used 12.3.3, all on the same day. All sandboxes were deleted after the runs.*
