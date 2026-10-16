# 04: Answer the review questions that decide what the opener can claim

To run: "Follow `workflow/04-review-questions.md`."

The first run answered a 14-item review list from the launch team. This prompt answers the factual ones again from current sources, because release status and names change. Prompts 05 to 07 answer the rest by testing.

## Prompt

Follow `workflow/rules.md`.

Answer these questions from primary sources: the GitHub repositories, the MariaDB release notes in `~/Code/mariadb-corporation/mariadb-docs`, the plugin's own files, and the PostgreSQL documentation. Cite the file, commit, or URL for each answer. Mark anything you can't confirm as open.

1. Are `mariadb/ai-plugins`, `mariadb-corporation/ai-plugins`, and `mariadb-corporation/mariadb-shell` public? Check with an unauthenticated GitHub API call. What is the newest release of each, and is it still marked pre-release? Does the plugin's installer need a GitHub token?
2. Which MariaDB releases were the first with vectors, the first GA, and the first LTS? Which Enterprise Server releases include vectors?
3. Which series is the current LTS, and what is the status of each newer series (GA, RC, or preview)?
4. What changed in vector support from 11.8 to the newest series? Include new functions, variables, `INFORMATION_SCHEMA` views, and behavior changes. Does any of it change the stage 01 snippet?
5. What are the public names and capitalization of the plugin, the shell, and the MCP server? Check the DevHub page title at ai-plugins.mariadb.org, the plugin README, the release titles, and the repository descriptions.
6. What does `mariadb-shell --help` print as its copyright line? Report it, because it matters for how the shell is positioned.

Save the answers to `workflow/review-answers-<date>.md`, with one section per question, the source for each fact, and a short recommendation where a decision is needed (for example, which external path to lead with).

## Done when

- Every question has an answer with a source, or is marked open with the reason.

## Notes from the first run (2026-10-15)

- All three repositories were public, and every release was still marked pre-release. The plugin README still said `mariadb-shell` was private, which was out of date.
- 12.3 was the current LTS. The docs listed 13.0.1 as an RC and had no 13.1 release notes.
- The DevHub page title was "MariaDB AI Plugins". `mariadb-shell --help` printed an Oracle copyright line.
