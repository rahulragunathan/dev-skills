# Enhancements

Candidate work, highest priority first. [ROADMAP.md](ROADMAP.md) carries the one-line index;
this file carries enough detail to pick an item up without digging.

Each entry has a stable ID — use it in branch names (`feature/enh-01-<slug>`) and in the
CHANGELOG entry that closes it. When an item ships, delete it from here and from the ROADMAP
index; the record lives in [CHANGELOG.md](../CHANGELOG.md). An item dropped rather than built
moves to "Decisions taken and not taken" in [CLAUDE.md](../CLAUDE.md). IDs are never reused.

## Priority

Priority is about value, not urgency. Effort is a rough estimate — a session, or days.

| Level | Means |
| ------- | ------- |
| **High** | Closes a gap hit during real use. |
| **Medium** | Worth doing when the area is already open. Removes a sharp edge or a duplication. |
| **Low** | Tidying. Do it while passing through. |

---

<a id="enh-01"></a>

## ENH-01 — Slim the global standards by moving procedures into skills

**Priority:** High · **Effort:** ~1 session
**Where:** [claude-setup/SKILL.md](../skills/claude-setup/SKILL.md) · **Regression net:** the managed-block `diff` in `claude-setup`

### What it is

The global standards block is about 2,750 words and sits in every session's context. Two
sections are procedures rather than prohibitions and can move behind a skill:

- `### Python environment` and `### Node environment` — roughly 950 words, about 35% of the
  file. They matter only when creating or repairing an environment, which is a moment the
  user always notices. Move them into a new `localclaude:project-env` skill, leaving a
  two-line stub carrying the prohibition ("no virtualenv or `node_modules` ever lives inside
  Drive") and the script names.
- The roadmap taxonomy — roughly 600 words restating what `phase-workflow` and the four
  templates already define. Cut to a pointer plus the rules that apply outside a phase.

### Why it matters

The block is resident on every request, so its length is a permanent cost paid whether or not
any of it is relevant. The test to apply is: **a prohibition stays resident, a procedure moves
to a skill.** You need "never put a venv in Drive" before you know you need it; you do not
need the `standardize-python-envs.sh` argument order until you are running it.

### Notes for the work

Every edit lands in two places — the canonical block in `claude-setup/SKILL.md` and the live
`~/.claude/CLAUDE.md` — and the two must stay byte-identical inside the markers. A skill's
own `description` is itself resident, so moving 950 words behind a ~60-word description is a
clear win while adding many small skills would not be. Related: KI-15, which is another
`claude-setup` claim the scripts do not honour, and worth folding into the same pass.

---

<a id="enh-02"></a>

## ENH-02 — Cover the untested llama.cpp and toggle paths

**Priority:** High · **Effort:** ~1 day
**Where:** [llama-serve.bats](../skills/claude-toggle-backend/tests/llama-serve.bats), [toggle.bats](../skills/claude-toggle-backend/tests/toggle.bats)

### What it is

`llama-serve.bats` holds four tests, all covering status. There is no coverage for start,
readiness polling, timeout, crash, stop or kill, foreground mode, explicit versus last-used
model resolution, Metal flags, free-port selection, or the arguments actually passed to
`llama-server`.

`toggle.bats` has no coverage for the Ollama or llama-cpp switch paths, a failed server
start, malformed or unwritable settings, credential-key clearing, effort and model values,
write atomicity, rollback, concurrency, or stale PID and port state.

### Why it matters

`mlx-serve.bats` has 16 tests against the same shape of script, so the gap is uneven rather
than deliberate. The untested paths are the destructive ones: stopping servers, killing
processes and rewriting `settings.json`. KI-01, KI-02, KI-03 and KI-04 all sit in code with
no test that would notice a regression.

### Notes for the work

The MLX tests are the model to copy — fakes for `curl` and the server binary, plus a helper
that sets up `$HOME`. Fix KI-11's fake first so it records its argv, then the argument
assertions this needs come for free. Bundle with KI-09, KI-10, KI-23, KI-24, KI-25 and
KI-26, which are discrimination failures in the tests that already exist; adding coverage
around them without fixing them first just adds more tests that cannot fail.

---

<a id="enh-03"></a>

## ENH-03 — Test the two destructive scripts that have no tests at all

**Priority:** High · **Effort:** ~1 day
**Where:** [backup-projects.sh](../skills/claude-setup/backup-projects.sh), [llama-autostart.sh](../skills/claude-toggle-backend/llama-autostart.sh)

### What it is

Neither script has a single test. Between them they select a backup destination by globbing
cloud-storage paths, copy credential-bearing config files, take a lock, run `rsync`, generate
a LaunchAgent plist, call `launchctl`, and rewrite `~/.zshrc`.

### Why it matters

These are the highest-consequence scripts in the repo and the least covered. KI-22 is a path
where a hand-edited `.zshrc` is silently truncated from the marker down, and nothing would
catch its reintroduction. KI-08 writes personal data into the wrong Drive account, and KI-06
disables backups indefinitely without a log line.

### Notes for the work

Both are testable with fakes and a sandboxed `$HOME`, the way the MLX tests already work —
fake `rsync`, `launchctl` and `pgrep`, and point `$HOME` at a temporary directory. The
`.zshrc` rewriting is the highest-value target because it is destructive and pure text
manipulation, so it needs no fakes at all. Fix KI-22 first and let the test be written
against the fix.

---

<a id="enh-04"></a>

## ENH-04 — Make the fakes assert a contract rather than only a shape

**Priority:** Medium · **Effort:** ~half a day
**Where:** [tests/fakes/](../skills/claude-toggle-backend/tests/fakes/)

### What it is

The fake `curl` reports ready only when `FAKE_CURL_READY=1`, failing with exit 7 otherwise, and
the fake `vllm-mlx` ignores every argument. Eleven tests depend on them: toggle's "switch to mlx" and "blind toggle", and MLX's non-Apple-Silicon,
missing-binary, no-repo, not-in-cache, succeeds, never-ready, crashes, stop and foreground
cases. None verifies a real HTTP response or a real `vllm-mlx` invocation contract.

### Why it matters

A fake that ignores its arguments cannot fail when the arguments are wrong, which is what
makes KI-11 and KI-26 possible. The fakes are not the defect — faking at the process boundary
is the right approach — but they currently record nothing, so no test downstream of them can
assert on an invocation.

### Notes for the work

Have each fake append its argv and environment to a file under the test's temporary `$HOME`,
then assert on that file. That keeps the tests hermetic while making the invocation
observable.

**Also recorded here:** the review's inventory of which tests genuinely discriminate — the 21
sound ones are toggle's four detection cases plus blind toggle; MLX's platform,
missing-binary, three resolution, forced-port, two model-error, timeout, crash,
stopped-status and stopped-port cases; and all four llama tests. Useful as the baseline when
working through ENH-02, so effort goes to the eight that do not: KI-09, KI-10, KI-23 and KI-24
in `toggle.bats`, KI-11, KI-12, KI-25 and KI-26 in `mlx-serve.bats`. 21 + 8 = the 29 tests.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="enh-05"></a>

## ENH-05 — Fold the MLX plan and spec into the permanent docs

**Priority:** Medium · **Effort:** ~half a day
**Where:** [docs/superpowers/plans/2026-07-26-mlx-backend.md](superpowers/plans/2026-07-26-mlx-backend.md), [docs/superpowers/specs/2026-07-26-mlx-backend-design.md](superpowers/specs/2026-07-26-mlx-backend-design.md)

### What it is

The MLX backend shipped — `mlx-serve.sh` exists and 16 bats tests cover it — but its plan
(35 KB) and design spec (11 KB) still sit under `docs/superpowers/`. The durable content in
them belongs in the permanent docs; the working artifacts should then go.

### Why it matters

They are the only two backward-looking documents outside CHANGELOG, which breaks the
tense split the standards define: CHANGELOG is the past, README and ARCHITECTURE are the
present, the roadmap files are the future. Anyone reading `docs/` today finds a plan for work
that is already done and cannot tell that from the file.

### Notes for the work

Depends on ENH-06, which creates the ARCHITECTURE.md they would fold into. The user has
asked to keep both files in place until they have gone back through them, so this is not
ready to start. Read them first and decide what is durable — the design rationale probably
is, the task-by-task plan probably is not.

---

<a id="enh-06"></a>

## ENH-06 — Give the repo the ARCHITECTURE.md and CLAUDE.md it requires of others

**Priority:** Low · **Effort:** ~half a day
**Where:** repo root and [docs/](.)

### What it is

`phase-workflow` requires every project to carry a project `CLAUDE.md` and a
`docs/ARCHITECTURE.md` with an embedded diagram. This repo has neither, while being the repo
that defines the rule.

### Why it matters

Mostly consistency, which is why this is Low. It becomes more than that once
`design-review` is in use: that skill produces a module map at plan time and expects
ARCHITECTURE.md to record and explain it, so the first phase to touch this repo's structure
will want the file to exist.

### Notes for the work

The project `CLAUDE.md` should carry the "Decisions taken and not taken" section, which
already has its first entry waiting: the unpushed-gate alternative recorded in UNK-01.
ARCHITECTURE.md wants a module map generated by the `drawio` skill, at
`docs/build_architecture.py` → `docs/architecture.{drawio,png}`, per the paths
`design-review` defines. Blocks ENH-05.

**Source:** gpt-5.6-sol — repo review, 2026-09-05 (partially remediated in the same phase,
which created the four roadmap files).
