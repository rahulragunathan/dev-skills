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
- `docs/ROADMAP.md` is future-tense and index-level only. Exactly these sections: **Status** (prose on where the project stands; the phase in flight is in `docs/PHASE_RECORD.md`, never here), **Known Issues**, **Enhancements**, and **Open Questions** — three pointer tables, no prose. Confidence-check findings land in Open Questions.
- No `Resolved` section and no `Notes` section. Shipped work belongs in CHANGELOG.md; standing limitations belong in ARCHITECTURE.md or the project AGENTS.md.
- **No phase ledger.** A phase ends by cutting a CHANGELOG release whose heading names it, so the release history is the phase history. ROADMAP records only what is planned; the phase in flight lives in `docs/PHASE_RECORD.md`. Version by what the phase did: minor for additive work, patch for fixes and docs, major for a break.
- The rating in a ROADMAP row mirrors the supporting file, which is authoritative, and so do its title (up to the case of the first letter) and an enhancement's Effort. The drift check verifies they agree, that ordering is descending, open questions included, and that every ID appears in both.
- Completed items are deleted from both files, not annotated in place.
- **A reference to a repo file carries a greppable fragment, never a line number**, and
  `roadmap.py check` confirms that fragment still occurs in the file it cites **exactly once** —
  greppable means one hit, and a fragment that has since been duplicated is refused as loudly as
  one that has gone:

  ```markdown
  **Where:** [preflight.sh](../skills/external-review/preflight.sh) — `timed_out "$ERR"`
  ```

  A `#Lnn` anchor is rejected anywhere in an entry, fenced examples excepted. The rest come from
  what the files actually contain:
  - the `**Where:**` field starts its line, or follows another field after a `·`, and cites at
    least one link, relative to the docs folder and never absolute;
  - a link to a **directory**, or to a Markdown doc inside `docs/`, is an existence-only
    reference and takes no fragment; any other file under `docs/` needs one;
  - a fragment holding a backtick is delimited by a longer run of backticks, as Markdown does;
  - a file shaped like a credential is never opened, so cite something else;
  - the requirement covers file links in the `**Where:**` field only, so a file mentioned in
    passing in prose needs nothing.

  Choosing the fragment is judgement — prefer a function name or a guard's condition to a whole
  line, and never a token that occurs everywhere. The four-character floor in the gate catches only the
  degenerate cases.
- An entry filed from an external review carries a provenance line naming the model ids, with Codex's effort, that found it — `Source: gpt-5.6-sol:high, gemini-3.1-pro-high — phase review, phase 4` — never the CLI name, so the attribution survives without a separate review store.

Close completed entries with the bundled helper from the repository root. It removes the
named detail entry and pointer together, preserving the surviving entries. After any roadmap
edit, run its reconciliation check for IDs, destinations, ratings and ordering:

```bash
# fence: roadmap-close
python3 "$CLAUDE_PLUGIN_ROOT/skills/project-docs/roadmap.py" close "<entry-id>" || exit 1
python3 "$CLAUDE_PLUGIN_ROOT/skills/project-docs/roadmap.py" check || exit 1
```

A refusal leaves the close incomplete. Resolve the reported inconsistency before retrying;
do not replace the helper with a hand-written slice.

## Docs split by tense

Each fact lives in one place, and the tense decides which:

- **The past:** `CHANGELOG.md`, versioned. A released section is never edited.
- **The present:** `README.md`, `docs/ARCHITECTURE.md` and the project instructions file
  (`AGENTS.md`, or `CLAUDE.md` in older repos). They describe only what the code is now.
- **The future:** the roadmap files, where the repository has them.

An item moves between them and is never copied: it enters ROADMAP and its supporting file
together, and on completion is deleted from both and written into the CHANGELOG release being
prepared, or `[Unreleased]` where none is. Two
exceptions are stated, not accidental: the instructions file keeps "Decisions taken and not
taken", so a dropped idea is not proposed again, and a ROADMAP row mirrors its entry's rating.
Where the user's or the project's own standards say something different, theirs win; otherwise both apply.

## Setting up roadmap files — only when the user asks

When the user asks for roadmap files ("set up the roadmap files here with project-docs"):

```bash
python3 "$CLAUDE_PLUGIN_ROOT/skills/project-docs/roadmap.py" init || exit 1
```

`init` creates whichever of the four files are missing, from the templates without their example
entries, and never touches one that exists. A fresh set-up passes `roadmap.py check`. Then fill
the Status section and the Last Updated line in `docs/ROADMAP.md`, drop the rows of its "Looking
for" table that point at docs the project does not have, and offer to file what is already
known: open bugs, wanted work, unsettled questions.

Never create the files to have somewhere to file a finding. Without them, a finding stays in the
table of the review that found it.

## The name check

`name_check.py` lists names in a repository's Markdown that no longer exist: backticked paths,
commands, flags and roadmap IDs, and Markdown links with their anchors.

```bash
python3 "$CLAUDE_PLUGIN_ROOT/skills/project-docs/name_check.py" --root .
```

- **It is advisory.** Fix each item it lists, or mark it with
  `<!-- name-check: ignore NAME ... -->` on the line above. Exit 1 means it listed something;
  it never blocks a merge.
- **It reads, and never runs, what it checks.** A flag is looked up in the source of the repo
  script whose command names it. Flags of external tools are not checked.
- **What counts.** A backticked path counts when it has a `/` and starts at `.`, `..`, a folder
  beside the doc or a top-level entry of the repository; then it must exist. A path written
  from `"$CLAUDE_PLUGIN_ROOT/..."` is read from the repository root. A command counts in four
  shapes: a path-shaped script, which must exist and define any `--flag` it is given; an
  interpreter followed by such a script; a bare `.py` or `.sh` name, alone or after an
  interpreter, matched against the tracked files' names (one match is that script, none is a
  missing command, two are not checked); and a bare program followed by a `--flag`, which must
  be on `PATH` or named in the repository's code. A bare script name in a span of its own is
  never reported, but binds the line's lone flags. A full or collapsed reference link,
  `[text][label]`, needs its `[label]:` definition in the same doc. A roadmap ID exists when its own detail
  file has the entry's anchor, or `CHANGELOG.md` names it; a mention elsewhere does not count.
- **It skips history and test input:** `CHANGELOG.md`, dated plans and specs, the templates, and
  Markdown under a `tests/` folder other than its README.
- **It cannot catch a false claim.** A doc can name only real things and still be wrong. That is
  what the full reads at phase end are for.
