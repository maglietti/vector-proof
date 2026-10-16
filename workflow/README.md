# Workflow: reproduce the "Agent memory in one table" write-up

This folder holds the prompts that rebuild the tests and the write-up in this repository, in the order they were first built on 2026-10-15. Give each prompt to Claude Code with the MariaDB AI Plugins installed, from the repository root. Each prompt produces one stage folder or one part of the write-up, and each says what "done" looks like.

The first run reached the result through many corrections. These prompts fold those corrections in, so a rerun should need fewer of them. The biggest fix: every prompt runs database work through the plugin's MCP tools, never the command line. [rules.md](rules.md) has the shared rules and the mistake behind each one.

## Before you start

1. Install the plugin in Claude Code:

   ```text
   /plugin marketplace add mariadb/ai-plugins
   /plugin install dev@mariadb
   ```

2. Allow the MCP server to reach the sandboxes and to read SQL files from this repository. Run this once per machine and add this repository's path when it asks for allowed paths:

   ```bash
   mariadb-shell -- mcp setup
   ```

3. Install Ollama and pull the embedding model, about 640 MB: `ollama pull qwen3-embedding:0.6b`. Prompt 03 also asks to pull `qwen3:4b`, about 2.5 GB.

4. Make sure `uv` is installed. The Python scripts declare their own dependencies.

Expect to approve these downloads along the way:

| Download | Size | Prompt |
| --- | ---: | --- |
| MariaDB server packages for each version, through `sandbox.deploy` | a few hundred MB each | 01 |
| `qwen3:4b` through Ollama | 2.5 GB | 03 |
| `maloyan/wikipedia-22-12-en-embeddings-all-MiniLM-L6-v2`, first Parquet file | 613 MB | 05, 06 |
| `KShivendu/dbpedia-entities-openai-1M`, first three Parquet files | 1.1 GB | 05 |

## The prompts

Run them in order. Prompts 01 to 07 produce evidence, and prompts 08 and 09 turn the evidence into the write-up. Start each prompt in a fresh session if the current one is long, because every prompt names the files it reads.

| # | Prompt | Produces | Time on an M4 Pro |
| --- | --- | --- | ---: |
| 01 | [01-snippet.md](01-snippet.md) | `01-snippet/`: the 20-line example on three versions | 10 min |
| 02 | [02-synthetic-scale.md](02-synthetic-scale.md) | `02-synthetic-100k/`: index proof at 100,000 rows, filters, transactions | 30 min |
| 03 | [03-embedding-step.md](03-embedding-step.md) | `04-embedding-demo/`: real embeddings, and how `LIMIT 1` leads an LLM to a wrong refund | 15 min |
| 04 | [04-review-questions.md](04-review-questions.md) | release, version, and naming facts for the 14 review questions | 20 min |
| 05 | [05-real-embeddings.md](05-real-embeddings.md) | `03-real-embeddings/`: recall, latency, filtered search, and mixed load on 200,000 real embeddings | 60 min |
| 06 | [06-time-travel.md](06-time-travel.md) | `05-time-travel/`: vector search on a system-versioned table, and the PostgreSQL check | 30 min |
| 07 | [07-agent-memory.md](07-agent-memory.md) | `06-agent-memory-loop/`: the agent stores and recalls its own memory through MCP | 10 min |
| 08 | [08-write-up.md](08-write-up.md) | `writeup/agent-memory-proof.html`: the story, five diagrams, and the data section | 60 min |
| 09 | [09-proofread-and-export.md](09-proofread-and-export.md) | the proofread pass, the Markdown and SVG exports, the root README | 20 min |

The stage folder numbers don't match the prompt numbers for 03 to 05. The folders keep the names from the first run, and the prompts follow the order the work was done.

## What a rerun should match

A rerun on the same versions should reproduce the recorded results closely. Recall and latency vary slightly with each index build and with the machine.

- Stage 01: refund notes 1 and 2, distances 0.0014, 0.0017, and 0.9474, and a plan with `key = embedding`.
- Stage 02: `Handler_read_rnd_next` of 11 through the index against 100,012 for the scan.
- Stage 04 (embedding step): with `LIMIT 1` the LLM approves the refund at temperature 0. With `LIMIT 2` or the policy lookup, it refuses in 10 of 10 runs.
- Stage 03 (real embeddings): recall@10 near 0.98 at the default `ef_search` on 12.3, and p99 under 2 ms.
- Stage 05: current-state recall falls toward 0.92 at 10 versions per memory, and `PARTITION BY SYSTEM_TIME` fails with error 1506.
- Stage 06: the expected memory in the top 2 for all 3 questions.

If a rerun differs, report the difference. Don't tune it away.

## Known gaps from the first run

- The first run used the command-line tools for bulk loads, transcripts, and the mixed-load test. These prompts require the MCP tools, and some of those steps may hit MCP limits (see [rules.md](rules.md)). Where they do, the prompt stops for your decision. That decision is part of the record.
- The first run's write-up said the agent "ran every step through the MariaDB AI Plugins", which wasn't true. Prompt 08 checks the write-up's description of how the work was done against what actually happened.
- 1 million rows, questions-as-queries at scale, and per-agent database users were not tested.
