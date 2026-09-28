# Working conventions

The user's global standards live in each agent's global instructions file and are not restated
here. This file carries only what is specific to this repository. Structure is in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## What makes this repo different

**The skills combine instructions with tested shell and Python helpers.** Tests cover
executable behavior; prose can still contradict another file without a test failing. Whenever
you change a rule, grep for every place that states it and fix them together — the recurring
failure here has been fixing one site and leaving the others asserting the old rule.

**The rules this repo defines also govern this repo.** A change to `phase-workflow` changes
how the next phase of this repo itself runs. Read a rule you are editing as something you
will be held to immediately, not as documentation of someone else's process.

**Skills state the SOP, not its history.** No "previously", no rationale for a superseded
version, no record of what a past review found. That belongs in `CHANGELOG.md`. Keep a
rationale only where its absence would leave the instruction ambiguous.

**Skills do not explain how standard tools work.** `git`, `gh`, `pytest` and shell behaviour
anyone can read in a man page is out of scope. Project methodology and the specific nuances
people get wrong are in scope.

## Roadmap hygiene

The taxonomy is in `phase-workflow`. One thing specific to this repo:

**Check the index against the detail after every edit.** ROADMAP rows drifting from the
`KNOWN_ISSUES` / `ENHANCEMENTS` / `OPEN_QUESTIONS` entries they point at is the most common
defect in these files, and it is mechanical to catch.

## Decisions taken and not taken

**Machine setup lives outside this repo.** `claude-setup`, `claude-toggle-backend`,
`drive-backup`, `local-models` and `project-env` left in v2.0.0 for private repos of their own,
with a separate hub holding the bootstrap script and the global standards. The skills here must
work in any repo, on any machine, and under Codex as well as Claude Code, so they name no
setup skill and assume nothing it installs.


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
