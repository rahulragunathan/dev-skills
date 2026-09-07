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

## Held — `local-models` and `claude-toggle-backend` rebuild

Those two skills are being rebuilt from scratch. Entries scoped to them are **held**: still
valid, still filed, not worked until the rebuild, and excluded from external review bundles in
the meantime. Their defects are the rebuild's requirements, which is why they are not closed.
ENH-02, ENH-04 and ENH-05 are held in full; ENH-03 and ENH-07 are held in part.

---

<a id="enh-02"></a>

## ENH-02 — Cover the untested llama.cpp and toggle paths

**Priority:** High · **Effort:** ~1 day · **Held**
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

**Priority:** High · **Effort:** ~1 day · **Partly held**
**Where:** [backup-projects.sh](../skills/drive-backup/backup-projects.sh), [llama-autostart.sh](../skills/claude-toggle-backend/llama-autostart.sh)

**Scope now:** `backup-projects.sh` only. The `llama-autostart.sh` half is held for the
`claude-toggle-backend` rebuild, which will need its own harness anyway.

### What it is

Neither script has a single test. Between them they select a backup destination by globbing
cloud-storage paths, copy credential-bearing config files, take a lock, run `rsync`, generate
a LaunchAgent plist, call `launchctl`, and rewrite `~/.zshrc`.

### Why it matters

These are the highest-consequence scripts in the repo and the least covered. KI-08 writes
personal data into the wrong Drive account, KI-07 copies credentials to a synced folder
unredacted, and KI-06 disables backups indefinitely without a log line — none of which any
test would notice. In the held half, KI-22 silently truncates a hand-edited `.zshrc` from the
marker down, and nothing would catch its reintroduction after the rebuild either.

### Notes for the work

Both are testable with fakes and a sandboxed `$HOME`, the way the MLX tests already work —
fake `rsync`, `launchctl` and `pgrep`, and point `$HOME` at a temporary directory.

**Each bug gets its reproducing test before its fix**, per the TDD rule: write the test that
fails on the defect, watch it fail for that reason, then fix. The harness comes first, then
one red-green cycle per bug. The `backup-projects.sh` cluster is KI-06 (stale lock), KI-07
(credentials copied unredacted), KI-08 (destination guessed) and KI-14 (every failure logged
as `ok`) — take KI-14 first, because while every run reports success the other three cannot
be observed failing at all.

---

<a id="enh-04"></a>

## ENH-04 — Make the fakes assert a contract rather than only a shape

**Priority:** Medium · **Effort:** ~half a day · **Held**
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

**Priority:** Medium · **Effort:** ~half a day · **Held**
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

`docs/ARCHITECTURE.md` now exists, so the fold-in target is there. The user has
asked to keep both files in place until they have gone back through them, so this is not
ready to start. Read them first and decide what is durable — the design rationale probably
is, the task-by-task plan probably is not.

---

<a id="enh-07"></a>

## ENH-07 — Honour `$CLAUDE_CONFIG_DIR` in the bundled scripts

**Priority:** Low · **Effort:** ~2 hours · **Partly held**

**Where:** [backup-projects.sh](../skills/drive-backup/backup-projects.sh), [claude-setup/SKILL.md](../skills/claude-setup/SKILL.md) (inline bash), and the four scripts under [claude-toggle-backend](../skills/claude-toggle-backend) — `toggle.sh`, `llama-serve.sh`, `mlx-serve.sh`, `llama-autostart.sh`

**Scope now:** `backup-projects.sh` and `claude-setup`'s inline bash. The
`claude-toggle-backend` scripts are held for the rebuild, which should resolve the config dir
once in whatever replaces them rather than inherit four more hardcoded copies.

### What it is

Every script in the plugin resolves `$HOME/.claude` directly. Claude Code reads
`$CLAUDE_CONFIG_DIR` when it is set, so on such a machine they would disagree: the skills write
the standards and settings to one place while Claude Code reads another.

The documentation used to claim the variable was honoured, which was the defect recorded as
KI-15. That claim is gone, and no skill asserts the opposite either: the decision lives once,
in the repo `CLAUDE.md` under "Decisions taken and not taken", because it is a plugin-wide
choice rather than a step in anyone's procedure. This entry is the remaining capability, not
a bug.

### Why it matters

Low, because a single-machine setup never sets the variable and the docs no longer mislead.
It becomes real the moment a second config root is wanted — a work profile beside a personal
one on the same machine.

**The held half is the sharper one, which is why the scope split is recorded rather than
assumed.** `backup-projects.sh` writing to a stale config root copies files to the wrong
folder, which is recoverable. `toggle.sh` resolves `settings.json` the same way and *patches*
it: on a machine with the variable set it would edit a file Claude Code is not reading, so the
backend would appear to switch and would not, with no error. That is the shared-state file
three skills already write, and KI-01 is what a bad write to it costs.

### Notes for the work

One resolver near the top of each script, `CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"`,
substituted for the hardcoded paths: ten occurrences over eight distinct paths in
`backup-projects.sh`; six over three in `claude-setup`'s inline bash, which are the
`skills` and `localclaude-plugins` symlinks and one backup of the first — Claude Code would
look for those under the relocated root, so they count; and four in `toggle.sh` once the held
half is unblocked. **`~/.claude.json` is not under the config dir** and stays as it
is; check that against the current Claude Code behaviour before assuming either way. Do this
inside the ENH-03 harness so the substitution has tests, rather than as a blind rename.

Deferred from the phase that closed KI-15, to keep the fix beside its tests.
