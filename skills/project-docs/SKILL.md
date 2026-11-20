---
name: project-docs
version: 1.0.0
description: The roadmap files (docs/ROADMAP.md with KNOWN_ISSUES, ENHANCEMENTS and OPEN_QUESTIONS), their templates and roadmap.py, and the rules for a project's docs. Use when the user asks to set up roadmap files, when filing, closing or checking a KI, ENH or UNK entry, and during a phase's documentation pass.
license: MIT
---

# project-docs

The roadmap files are optional. A repository has them only when the user asked for them.

## Roadmap file rules (summary — the templates are canonical)

- Fixed vocabulary: **Done** (never "Implemented"), consistent status terms throughout.
- `docs/ROADMAP.md` is future-tense and index-level only. Exactly these sections: **Status** (prose, plus a short note on the phase in flight or planned — often none), **Known Issues**, **Enhancements**, and **Open Questions** — three pointer tables, no prose. Confidence-check findings land in Open Questions.
- No `Resolved` section and no `Notes` section. Shipped work belongs in CHANGELOG.md; standing limitations belong in ARCHITECTURE.md or the project AGENTS.md.
- **No phase ledger.** A phase ends by cutting a CHANGELOG release whose heading names it, so the release history is the phase history. ROADMAP records only what is in flight or planned. Version by what the phase did: minor for additive work, patch for fixes and docs, major for a break.
- The rating in a ROADMAP row mirrors the supporting file, which is authoritative. The drift check verifies they agree, that ordering is descending, and that every ID appears in both.
- Completed items are deleted from both files, not annotated in place.
- **A reference to a repo file carries a greppable fragment, never a line number**, and
  `roadmap.py check` confirms that fragment still occurs in the file it cites **exactly once** —
  greppable means one hit, and a fragment that has since been duplicated is refused as loudly as
  one that has gone:

  ```markdown
  **Where:** [preflight.sh](../skills/external-review/preflight.sh) — `timed_out "$ERR"`
  ```

  A `#Lnn` anchor is rejected anywhere in an entry, fenced examples excepted. Three further
  rules come from what the files actually contain: a link whose target is a **directory** is an
  existence-only reference and takes no fragment; a fragment **cannot contain a backtick**, so
  quote something else from the same file; and the requirement covers file links in the
  `**Where:**` field only, so a file mentioned in passing in prose needs nothing. Choosing the
  fragment is judgement — prefer a function name or a guard's condition to a whole line, and
  never a token that occurs everywhere. The four-character floor in the gate catches only the
  degenerate cases.
- An entry filed from an external review carries a provenance line naming the model ids that found it — `Source: gpt-5.6-sol, gemini-3.1-pro-high — phase review, phase 4` — never the CLI name, so the attribution survives without a separate review store.

Close completed entries with the bundled helper from the repository root. It removes the
named detail entry and pointer together, preserving the surviving entries. After any roadmap
edit, run its reconciliation check for IDs, destinations, ratings and ordering:

```bash
python3 "$CLAUDE_PLUGIN_ROOT/skills/project-docs/roadmap.py" close "<entry-id>" || exit 1
python3 "$CLAUDE_PLUGIN_ROOT/skills/project-docs/roadmap.py" check || exit 1
```

A refusal leaves the close incomplete. Resolve the reported inconsistency before retrying;
do not replace the helper with a hand-written slice.
