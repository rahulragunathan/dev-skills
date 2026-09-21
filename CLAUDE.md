# localclaude — working conventions

Global standards live in `~/.claude/CLAUDE.md` and are not restated here. This file carries
only what is specific to this repository. Structure is in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## What makes this repo different

**The eight skills combine instructions with tested shell and Python helpers.** Tests cover
executable behavior; prose can still contradict another file without a test failing. Whenever you change a rule, grep for
every place that states it and fix them together — the recurring failure here has been fixing
one site and leaving the others asserting the old rule.

**The rules this repo defines also govern this repo.** A change to `phase-workflow` changes
how the next phase of `localclaude` itself runs. Read a rule you are editing as something you
will be held to immediately, not as documentation of someone else's process.

**Skills state the SOP, not its history.** No "previously", no rationale for a superseded
version, no record of what a past review found. That belongs in `CHANGELOG.md`. Keep a
rationale only where its absence would leave the instruction ambiguous.

**Skills do not explain how standard tools work.** `git`, `gh`, `pytest` and shell behaviour
anyone can read in a man page is out of scope. Project methodology and the specific nuances
people get wrong are in scope.

## This repo owns the standards other repos receive

`claude-setup/SKILL.md` holds the **canonical** global standards block; `~/.claude/CLAUDE.md`
on any machine holds an installed copy. Editing the block here changes every machine on its
next `claude-setup` run, so treat it as shipping, not as editing a note to yourself.

`claude-setup` step 3 owns the reconcile-and-verify procedure. Follow it there rather than
from memory: a wrong slice corrupts the file loaded into every session, which has happened
once.

## Roadmap hygiene

The taxonomy is in the global standards and `phase-workflow`. Two things specific to this
repo:

**Check the index against the detail after every edit.** ROADMAP rows drifting from the
`KNOWN_ISSUES` / `ENHANCEMENTS` / `OPEN_QUESTIONS` entries they point at is the most common
defect in these files, and it is mechanical to catch.

**Held is not closed.** `local-models` and `claude-toggle-backend` are being rebuilt, so their
entries stay filed and unworked: they are the rebuild's requirements. Never close one, and keep
them out of external review until the rebuild lands:
`--exclude skills/local-models --exclude skills/claude-toggle-backend`. The Held sections in
`KNOWN_ISSUES.md` and `ENHANCEMENTS.md` say which entries are held and how to tell.

**`drive-backup` is out of scope for external review while the process phase runs.** It is not
held — KI-06, KI-07, KI-08, KI-14 and KI-28 through KI-34 are active — but it has its own phase
with its own `bats` harness (ENH-03), and reviewing it now spends findings on code nobody is
about to touch while the real ones compete for attention. Exclude it with
`--exclude skills/drive-backup`. Anything found there meanwhile is filed, never fixed in this
phase.

Both exclusions follow `external-review`'s rule for an out-of-scope area — remove the files
from the bundle **and** name the exclusion in the preamble — which is stated there and not
restated here. The reason it is a rule at all is this repo: pass 8 named `drive-backup` in the
preamble alone, the files went in the bundle anyway, and the reviewer reported on them.

## Decisions taken and not taken

**Historical red-state evidence is not required, and not recoverable here.** This repository's
history begins with implementation and tests together at the v1.8.0 import, so no test's red
state can be recovered from a commit. The answer was to do nothing: the mutation check in
`phase-workflow` §3 step 3 breaks the named behaviour now and confirms the test fails on the
named assertion, which works whatever the history contains. Closed as UNK-02, 2026-09-21. The
2026-09-20 phase measured the limit of that substitute — a mutation can show an assertion is
load-bearing, but not that a conversion preserved its meaning, and it cannot falsify a
disjunction by negating one operator.

**The phase gate is a PR ready for review — not uncommitted work.** The rejected alternative
was holding a phase's work unpushed in the working tree so the user saw it before anything
landed. Dropped because the retrospective points `git checkout`, worktree and stash operations
at that same tree, and `git reflog` recovers only what was committed. Per-task commits behind a
draft PR give the same visibility with none of the exposure, and the full diff stays available
as `git diff "origin/$DEFAULT_BRANCH"...HEAD`.

**External review has no pass ceiling.** A fixed number was tried and dropped: how many passes
a phase needs depends on what the findings are and which way the count is moving, neither of
which is knowable at the start. Each pass ends with the trend and a recommendation, and the
user decides.

**A reviewer always emits a findings list, empty if it found nothing.** Absent output means the
review did not run, and nothing else does. Without this, a quota failure and a clean pass look
identical.

**`$CLAUDE_CONFIG_DIR` is not supported, and this is the only place that says so.** The docs
claimed it was while every script resolved `$HOME/.claude` directly. Rather than thread a
resolver through code that has no tests, the claim was removed; the capability is ENH-07, to be
done inside the backup test harness. The prohibition is deliberately not repeated in
`claude-setup`: that skill neither reads the variable nor writes it, and a plugin-wide decision
restated inside one skill's steps is how the same fact ends up in four files disagreeing.
`drive-backup` notes it only as a fact about the script it ships.

**No `development-standards` skill.** Proposed for the `## Development process` and
`### Subagents` sections, which are the largest in the standards block. Rejected: what remains
after the procedures move out is almost entirely prohibitions, and a prohibition only works
while it is resident — a skill you have to invoke cannot stop you doing something you did not
know was forbidden. The procedures that could move already have owners (`phase-workflow`,
`design-review`, `external-review`), so a new skill would be a third home for material that
has two. `project-env` earned its place because it had a clear invocation moment; "development
standards" has none.

**Markdown-lint setup stays in `claude-setup`.** It is tooling installation, which is what that
skill does, and folding it into `project-env` would give that skill a second reason to change
for the sake of one 500-word step. Two occurrences do not justify a new home.

**Triage subagents may gather evidence.** The global standards forbid using a subagent to
verify correctness, because a copy of the same model confirms rather than checks. The narrow
exception is a subagent that returns quoted file lines or command output while the judgement
stays with the main agent — that parallelises lookup without asking yourself whether you were
right.

**Codex uses a pruned export for review scope.** `external-review` invokes it at the root
returned by `codex-root.sh`, with `--skip-git-repo-check`. The export contains regular files
from HEAD, no Git history, and no symlinks. Phase diffs and plans travel as inlined text.
This prevents routine exploration inside that root from including excluded files. It is not
read isolation: the sandbox still permits reads elsewhere, including the source repository.
Secrets that require isolation must be outside the reviewer's accessible filesystem.
