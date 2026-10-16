# Rules for every prompt in this workflow

Every prompt in `workflow/` starts with "Follow `workflow/rules.md`." These rules come from mistakes made in the first run on 2026-10-15. Each rule names the mistake it prevents.

## Database access

- **Use the MariaDB AI Plugins MCP tools for all database work.** Deploy and remove servers with `sandbox.deploy`, `sandbox.stop`, and `sandbox.delete`. Run SQL with `db.connect`, `db.execute_sql`, and `db.execute_sql_script`. Don't run `mariadb`, `mariadb-shell`, `mariadb-dump`, `mysql`, or Docker from a shell to reach a database. The first run used the `mariadb` client and the `mariadb-shell` command line for bulk loads and transcripts, and the plugin team flagged it. The command-line tools in this repository (`sandbox.sh`, `run.sh`, `tt-run.sh`) are for a human operator, not for the agent.
- **Never choose or type a database password.** Call `sandbox.deploy` without `password`, so the plugin generates one and stores it for the `db.*` tools. Never put a password on a command line or in a file.
- **Run SQL files with `db.execute_sql_script` and `file_path`.** The repository directory must be on the MCP server's allowed paths. If the call is refused, stop and ask me to run `mariadb-shell -- mcp setup` to allow it. Don't paste large scripts inline to get around the allowlist, and don't change the allowlist yourself.
- **If a `db.*` tool can't do a step, stop and tell me.** Three steps may hit limits: bulk `LOAD DATA LOCAL INFILE` of large files, index builds that run 5 to 35 minutes, and the six concurrent sessions of the mixed-load test. Test each with a small case first. Report what works, what fails, and the exact error, then wait for my decision. Don't switch to the command line on your own.
- **Read the plugin skills that apply before you start.** At minimum: `dev:mariadb-vector`, `dev:mariadb-vector-functions`, `dev:mariadb-create-table`, `dev:mariadb-load-data`, `dev:mariadb-explain`, and, for stage 05, `dev:mariadb-system-versioned-tables`.

## Sandboxes and versions

- Test on the versions `sandbox.list_available_versions` offers, at least the current long-term support release (12.3 on 2026-10-15) and 11.8. Check the release notes before you call a version GA. The first run headlined 13.1.1, which had no published release notes.
- Before any vector index build on more than a few thousand rows, set `mhnsw_max_cache_size` to at least 1 GB. With the 16 MB default, a 100,000-row build was only 64% done after 21 minutes.
- Stop and delete every sandbox when the stage ends, and say so.

## Data, downloads, and evidence

- **Ask before every download.** Name the file, the source, and the size, and wait for a yes. That includes datasets, Python packages, and Ollama models. Approval for one download doesn't cover the next.
- Save the raw output of every run in the stage's `results/` folder, named with the server version (for example `bench-12.3.3-wiki384.txt`). Strip terminal color codes.
- Never fabricate or round away a result. If a number is worse than expected, report it as it is. If a claim can't be tested, say "not tested".
- Every claim in the write-up must trace to a file in `results/`. If you can't point to the file, cut the claim.

## Writing

- Follow `~/.claude/CLAUDE.md` Section 4 for all prose, and run the `/proofread` skill before you present any write-up text.
- Contractions are fine in the write-up. Use "the agent" for the acting system and "the LLM" for the language model. Use "the embedding model" only for the text-to-vector model.
- One line per paragraph. Never hard-wrap prose.
- Lint every Markdown file with `markdownlint-cli2 --config ~/.markdownlint-cli2.yaml` and fix every error before you show it.
