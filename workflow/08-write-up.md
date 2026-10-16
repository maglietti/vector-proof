# 08: Write the story

To run: "Follow `workflow/08-write-up.md`." Run it after prompts 01 to 07, so every number has a results file behind it.

## Prompt

Follow `workflow/rules.md`. Load the `artifact-design` and `artifact-diagramming` skills before you write the page.

Write `writeup/agent-memory-proof.html`, a page for the positioning "The Unified Open Database for the Agentic Enterprise" under the tagline "Lead with proof a developer can verify." Tell a story. Don't report like a reporter, and don't pitch. The reader is a developer who will check every claim, so every number must link to the results file it came from.

### The story

Open on one agent and one decision. On Monday, a billing agent learns that refunds over 50 dollars need approval. On Tuesday, a customer asks it for an 80 dollar refund, and the right answer depends on whether the agent can find Monday's note again. Then add load step by step until something gives, and keep each step's failures brief and its fixes concrete:

1. **The problem:** the usual answer is a second store for vectors and a sync job. MariaDB keeps the note, the owner, and the embedding in one row. Add the agent-loop diagram here.
2. **Step 1, 20 lines of SQL:** the snippet, its output, and the distances, on every version.
3. **Step 2, a real embedding model:** show the distance table. With `LIMIT 1` the LLM approves the refund, and with `LIMIT 2` or the policy lookup it refuses. Quote the LLM's own temperature-0 answers. Make it plain what the agent would have done and why: the database returned the right order, the query asked for the wrong thing, and a `kind` column fixes it.
4. **Step 3, 100,000 rows:** the index reads 11 rows where the scan reads 100,012. Say that the synthetic data only proves index use.
5. **Step 4, real data:** a data section a developer can trust. Cover where each dataset came from (name, source, license, files used), its shape (rows, columns, dimensions, text lengths, vector norms), what it stands in for, how rows and queries were split, and that `agent_id` is an added label. Then the recall and latency tables.
6. **Step 5, many agents:** the actor-model diagram, and the filtered results with their latency cost.
7. **Step 6, live writes:** new rows are searchable within milliseconds, and writes slow reads. Report both.
8. **Step 7, time travel:** the auditor's question, the schema diagram, the history results, the partition error, and the PostgreSQL T180 check.
9. **Step 8, the agent did the testing:** the architecture and call-flow ladder diagrams, the plugin install, and the agent's own memory loop. Describe how the work was actually done, including any step that didn't go through the MCP tools and why. Don't claim "every step" unless the results prove it.
10. **Run it yourself:** the Docker path and the agent prompt.
11. **What this proves:** a summary of the claims and their costs, not a conclusion. List what wasn't tested.
12. **Appendix, marked internal:** the review answers from prompt 04 and the test verdicts, one item each with a status. Then the evidence file links.

### The diagrams

Draw five inline SVG diagrams that each show a mechanism: the agent loop, the architecture, the schema, the actor model, and the call-flow ladder. Label every arrow. Use the page's color tokens so they work in light and dark themes. Wrap each one in a scroll box on phones. Check that no label overlaps another or leaves the drawing.

### The page

- Use plain, complete headings ("Start with 20 lines of SQL"), not aphorisms. Name the subject in every heading and caption, and leave no dangling "it".
- Let text fill the content column. Don't cap paragraph width with `max-width` in `ch`, and don't use `text-wrap: balance` on headings.
- Put each paragraph on one line in the source.
- Give tables and code blocks their own horizontal scroll, so the page never scrolls sideways at 375 px.

Publish the page as an artifact (update the existing one if its URL is in the repository README), and give me the link.

## Done when

- The page exists and is published, every number links to a results file, and the five diagrams pass the overlap check.

## Notes from the first run

- The first draft read like a report, and the rewrite as eight steps from one agent's decision worked better.
- Step 2 first said only that "the card-refund note edges out the approval-policy note". Reviewers couldn't tell what the agent would have done. The LLM test and the quoted answers made it plain.
- The first draft overclaimed. It said "ran every step through the MariaDB AI Plugins" and "there was no Docker", and neither was true.
