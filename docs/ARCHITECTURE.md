# Architecture

How this plugin is put together today. Planned work is in [ROADMAP.md](ROADMAP.md); what
already shipped is in [CHANGELOG.md](../CHANGELOG.md).

## What this is

A plugin of four agent skills. Each exposes a `SKILL.md` that the agent reads and follows.
Shell helpers implement review capture, reviewer preflight, mutation restoration and release
checks. Python helpers rank the reviewer models, handle reviewer deadlines, set up and edit
roadmap files, check the names docs mention, and run the design-review test tooling.
`docs/build_architecture.py` generates the module diagram.

There is no application entry point. A module here is a skill directory, with an invocation as
its interface. Verification covers both executable behavior and agreement between the
instructions and the commands they tell a reader to run.

![Module map](architecture.png)

Regenerate the diagram from its source rather than editing the XML:

```bash
python3 docs/build_architecture.py
python3 ~/.claude/skills/drawio/scripts/validate.py docs/architecture.drawio
python3 ~/.claude/skills/drawio/scripts/render_png.py docs/architecture.drawio
```

## Module table

Ordered most-stable-first: what sits at the top changes only when the user changes their mind,
what sits at the bottom changes when someone else ships a new CLI.

| Unit | Responsibility | Interface | Depends on |
| --- | --- | --- | --- |
| `phase-workflow` | Run a phase from plan review to merge | the `phase-workflow` skill | `design-review`, `project-docs`, `external-review`, `gh` |
| `project-docs` | Keep a project's docs by tense, its roadmap files on request, and the name check | the `project-docs` skill; `roadmap.py`, `name_check.py` | `git` |
| `design-review` | Decide structure at plan time and re-check it at phase end | the `design-review` skill, `plan` or `phase` mode | `drawio` skill |
| `external-review` | Get a review from other models of a plan, a phase diff or the repo | the `external-review` skill, `plan`, `phase` or `repo` mode | `project-docs`, `codex`, `agy` |

**Expected change:** a new external reviewer. Adding one edits `external-review`, and today
also `phase-workflow`, which names the reviewer pair in its skip rules — that second edit is the
coupling to remove if this expectation is to hold.

**Shared state:** none inside the plugin. The skills write to the repository they run in and
to temporary directories. The one exception is the docs pass, which also updates docs about the
project kept in the folder that holds the repository; the hand-off names each such edit, since
the phase diff cannot show it.

## How the four fit together

`phase-workflow` orchestrates; `design-review`, `project-docs` and `external-review` are called
by it at defined points and are useful on their own. `external-review` also files through
`project-docs` where a repository has roadmap files. The dependency is mostly one way:
`external-review repo` runs on a repository that has never seen a phase. It is not clean,
though — `design-review` and `external-review` reference workflow stages by number and
`phase-workflow` names the reviewer pair, so the skills are more coupled than the call graph
suggests.

Machine setup — permissions, the global standards, backups, local model backends and project
environments — lives outside this plugin, so these skills assume nothing it installs.

## External tools

`codex`, `agy` and the `drawio` skill are each invoked by exactly one skill, and a missing one
degrades that step rather than blocking the workflow. `external-review` reports its
[coverage classification](../skills/external-review/SKILL.md#coverage-classification);
`design-review` records "no diagram" and carries on. **`gh` is the exception and is required:**
`phase-workflow` cannot open or merge a PR without it, so it is preflighted before the first
phase-start mutation rather than discovered at merge time.

The reviewers are also the one place this repository sends its own source to a third party.
The bundle procedure in `external-review` excludes credential-shaped files, skips symlinks
before reading them, and disables diff conversion filters, in every mode.

## Testing

The suites run against scratch repositories and temporary directories:

| Skill | Executable checks |
| --- | --- |
| `external-review` | bundle capture, pruned export, documented Codex invocation, preflight, both model ladders |
| `phase-workflow` | mutation restoration, release checks, documented release and cleanup commands, bats assertion enumeration |
| `project-docs` | roadmap set-up, edits, rating scales and reference verification; the name check |
| `design-review` | transcript handling, fixture evaluation, Results writer, rollup tooling |
| repo | the plugin name appears only in the manifests, README, CHANGELOG and phase record; nothing names the roadmap machinery's old paths |

Run them with:

```bash
bats skills/*/tests
python3 -m unittest discover tests
```

All tests must pass; none is intentionally left red.

The skills themselves are prose, so they are tested by running scenarios against a fresh
agent: `design-review/tests/` holds seven, each with failure conditions written to judge the
design an agent *produces* rather than what it says about it.
