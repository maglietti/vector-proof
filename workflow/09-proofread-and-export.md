# 09: Proofread, export, and link everything

To run: "Follow `workflow/09-proofread-and-export.md`."

## Prompt

Follow `workflow/rules.md`.

1. Run the `/proofread` skill on `writeup/agent-memory-proof.html`. It runs the `/lint-prose` checks first, then the 12-item editorial checklist. Report each item as PASS or NEEDS WORK with the fixes you made. Watch for balanced-clause mirrors, colons before full sentences, "we" or "our", and bare "the model".
2. Check every claim about how the work was done against the results files and the session's tool calls. Fix any sentence that says more than the evidence shows.
3. Rebuild the Markdown and SVG files with `uv run writeup/export.py`. It writes `writeup/README.md` and `writeup/diagrams/*.svg`, and fails if an evidence link points at a missing file.
4. Lint every Markdown file in the repository with `markdownlint-cli2 --config ~/.markdownlint-cli2.yaml`, and fix every error.
5. Check that every relative link in `README.md`, `writeup/README.md`, `writeup/agent-memory-proof.html`, and `workflow/*.md` resolves to a file.
6. Update the root `README.md`. It should link the published artifact URL, the HTML and Markdown write-ups, each diagram, and this workflow. Its "Recorded result" lines must match the new results files.
7. Republish the artifact from the HTML.
8. Give me the git commands to stage and commit the changes, with a conventional commit message under 50 characters. Don't run git yourself.

## Done when

- The proofread readout is complete, both exports are current, lint shows 0 errors, every link resolves, and the artifact is republished.
