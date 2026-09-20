# Known Issues

Open defects, most severe first. [ROADMAP.md](ROADMAP.md) carries the one-line index; this
file carries enough detail to pick an item up without digging.

Each entry has a stable ID — use it in branch names (`bugfix/ki-02-<slug>`) and in the
CHANGELOG entry that closes it. When fixed, delete it from here and from the ROADMAP index;
the record lives in [CHANGELOG.md](../CHANGELOG.md). IDs are never reused.

Every entry carries its own source line; they come from several review passes, not one.
KI-01 through KI-27 came from the repo review of 2026-09-05, KI-28 through KI-32 from phase
review pass 5 on 2026-09-07, and KI-33 from pass 6 on 2026-09-08. Findings about
`phase-workflow`, `external-review` and the global standards were remediated in the passes that
found them and are in the CHANGELOG rather than here.

## Severity

| Level | Means |
| ------- | ------- |
| **Critical** | Loses or corrupts data, or sends wrong information to real recipients. |
| **High** | Silently produces a wrong result, or reports success without doing the work. |
| **Medium** | Wrong under conditions the operator can notice or work around. |
| **Low** | Cosmetic, or wrong in a field nothing consumes. |

## Held — `local-models` and `claude-toggle-backend` rebuild

Those two skills are being rebuilt from scratch, so every entry scoped to them is **held**:
still valid, still filed, not worked until the rebuild, and excluded from external review
bundles in the meantime. They are not closed because they are the rebuild's requirements — the
new code has to clear them, and deleting them would lose the specification.

Held: KI-01 through KI-05, KI-09 through KI-13, and KI-16 through KI-27, with two
exceptions. **KI-22 is held only in its `claude-toggle-backend` half**; the same defect in
`claude-setup` is fixed. **KI-16 is held only in its `local-models` half**; the missing
`~/.zshrc` installer behind it is machine setup and is in scope.

Active: **KI-06, KI-07, KI-08, KI-14 and KI-28 through KI-34** — the `drive-backup` cluster,
scheduled as its own phase with a bats harness (ENH-03). Held is the default for the two skills
being rebuilt, not for everything else.

**An entry naming a held skill is not automatically held.** Several were filed against a
defect that appears in both a held script and a `claude-setup` one; check the "Where" lines
against the skill boundary rather than the title. KI-22 and KI-16 are both such cases, and
KI-16 shows the second shape: a held skill's *documentation* describing a real gap in
machine setup, which is not held.

---

<a id="ki-01"></a>

## KI-01 — `settings.json` is truncated before it is rewritten

**Severity:** Critical
**Likelihood:** Rare
**Where:** [toggle.sh:117-119](../skills/claude-toggle-backend/toggle.sh#L117-L119)

### What happens

The backend switch rewrites the settings file in place:

```python
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
```

`open(path, "w")` truncates immediately. If `json.dump` raises, or the process is killed
between truncation and the final write, `~/.claude/settings.json` is left empty or partial.
That file holds the permission allowlist, `enabledPlugins`, `model` and `effortLevel`.

### Example scenario

`toggle.sh mlx` is interrupted with Ctrl-C in the instant after truncation. The next Claude
Code start finds an empty settings file, so every allow-listed command begins prompting
again and the plugin set is gone.

### Notes for a fix

Write to a temporary file in the same directory, then `os.replace()` onto the target —
`replace` is atomic within a filesystem. Keep the existing behaviour of preserving unknown
keys. Related: KI-02, which is the same switch failing for a different reason.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-22"></a>

## KI-22 — the marker strip can truncate `.zshrc`

**Severity:** Critical · **Partly fixed**
**Likelihood:** Rare
**Where:** [llama-autostart.sh:75](../skills/claude-toggle-backend/llama-autostart.sh#L75)

**Fixed in `claude-toggle-backend`'s alias block, held in `llama-autostart.sh`.** The
shell-block installer that had the same defect was hardened — it requires both markers, backs
the file up, and writes through `mktemp` — and then moved out of `claude-setup` into
`claude-toggle-backend` with ENH-09. `claude-setup` no longer writes `~/.zshrc` at all. `llama-autostart.sh` still carries the original pattern and is
held for the rebuild — which must not reintroduce it.

### What happens

```bash
awk '/# >>> localclaude autostart-alias/{s=1} /# <<< localclaude autostart-alias/{s=0;next} !s' "$HOME/.zshrc" > "$HOME/.zshrc.tmp" && mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
```

The guard before this only checks that the **opening** marker exists. If the closing marker
has been removed by hand, `s` stays 1 to end of file and every line after the opening marker
is dropped. The temporary path `$HOME/.zshrc.tmp` is also fixed, so a concurrent writer can
be clobbered.

### Example scenario

The user tidies `.zshrc` by hand and deletes the closing marker line while keeping the alias.
Running uninstall silently deletes everything below that point, including unrelated exports,
`PATH` edits, and any later managed blocks.

### Notes for a fix

Require both markers before editing, and refuse with a message when only one is present.
Write to `mktemp` output rather than a fixed name. Back the file up before rewriting. Copy the
hardened block from `claude-toggle-backend/SKILL.md` under *Shell aliases*, which does all three
and is verified against a hand-deleted closing marker.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-45"></a>

## KI-45 — a failing `[[ ]]` assertion in mid-test does not fail its bats test

**Severity:** High
**Likelihood:** Almost always
**Where:** every `*.bats` suite under `skills/`, for example
[evidence.bats](../skills/design-review/tests/evidence.bats),
[preflight.bats](../skills/external-review/tests/preflight.bats)

### What happens

Under Bats 1.14.0 a `[[ ... ]]` conditional that evaluates false does not stop the test unless
it is the test's last command. A false `[ ... ]` test or a failing ordinary command does stop
it. So every `[[ ... ]]` assertion written before the final line of a test is checked by the
reader only, never by the suite.

Measured by [bats_assertions.py](../skills/phase-workflow/bats_assertions.py), which reports each
assertion and whether another command follows it in its test. Across the four skills in scope —
`claude-setup`, `design-review`, `external-review`, `phase-workflow` — there are 309 tests and
**123 `[[ ... ]]` assertions, 68 of them mid-test**.

The counts first recorded here (325 tests, 145 assertions, 78 mid-test) were produced by reading
rather than by a tool, and are superseded. `claude-toggle-backend` is held and being rebuilt, so
its assertions are neither counted nor converted: its tests are replaced by the rebuild rather
than repaired.

### Example scenario

`rollup.bats` asserted three tallies and a row count. After round 9 changed every tally, the
suite still reported the test as passing, because only the last assertion was evaluated. The
stale expectations surfaced only when the last line happened to fail.

### Notes for a fix

Write assertions so they fail the test wherever they sit: `[ ... ]`, or a pipeline such as
`printf '%s\n' "$output" | grep -q PATTERN`, or the `bats-assert` helpers. Convert the 68
mid-test conditionals, then confirm the conversion by making each one false once and watching
its test fail. Until then, treat a green suite as weaker evidence than its count suggests.

**Source:** claude-opus-5 — found while updating the Results tables after round 9, 2026-09-15.

---

<a id="ki-07"></a>

## KI-07 — credentials are copied to Drive with no scan or warning

**Severity:** High
**Likelihood:** Almost always
**Where:** [backup-projects.sh:107-120](../skills/drive-backup/backup-projects.sh#L107-L120)

### What happens

The config snapshot copies these verbatim:

```bash
cfg_files=(
  "$HOME/.claude/settings.json"
  "$HOME/.claude.json"
  "$HOME/Library/Application Support/Claude/claude_desktop_config.json"
```

`settings.json` holds `env.ANTHROPIC_AUTH_TOKEN` and `env.ANTHROPIC_API_KEY` — written there
by [toggle.sh:112-115](../skills/claude-toggle-backend/toggle.sh#L112-L115) — and
`claude_desktop_config.json` commonly holds MCP server credentials. Nothing scans, redacts or
warns.

### Example scenario

The user switches to a local backend, which writes an auth token into `settings.json`. The
next Stop hook copies that file to a cloud-synced folder, where it is retained, versioned and
indexed by the sync provider.

### Notes for a fix

Decide the policy first: either redact known credential keys on copy, or state plainly in
`claude-setup/SKILL.md` that the backup contains secrets and the destination must be treated
accordingly. Redaction has a cost — `~/.claude.json` is backed up precisely because its state
is otherwise unrecoverable, so stripping fields makes the copy less useful for restore.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-09"></a>

## KI-09 — `toggle.bats` "clears env" never asserts that the env was cleared

**Severity:** High
**Likelihood:** Almost always
**Where:** [toggle.bats:36-44](../skills/claude-toggle-backend/tests/toggle.bats#L36-L44)

### What happens

```bash
run python3 -c '...;print(c["permissions"]["allow"][0]);print(c.get("env",{}).get("ANTHROPIC_BASE_URL",""))'
[[ "$output" == *"Bash(ls:*)"* ]]
[ "$(cat "$HOME/.claude/local-backend")" = "anthropic" ]
```

The script prints `ANTHROPIC_BASE_URL` on the second line and nothing asserts on it. The only
output assertion covers the permissions entry.

### Example scenario

The `env.pop` loop in `toggle.sh` is deleted, so switching to `anthropic` leaves
`ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN` and `ANTHROPIC_API_KEY` in place. The test named
"clears env" still passes, and Claude Code keeps talking to a stopped local server.

### Notes for a fix

Assert the printed value is empty, and assert on all three keys rather than one. Then run the
mutation check from `phase-workflow` §3 step 3 to confirm the test goes red for that reason.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-10"></a>

## KI-10 — the MLX switch test does not pin the auth token

**Severity:** High
**Likelihood:** Almost always
**Where:** [toggle.bats:45](../skills/claude-toggle-backend/tests/toggle.bats#L45)

### What happens

The test is named for `token=mlx` but the repo id under test is
`mlx-community/Qwen2.5-Coder-14B-Instruct-4bit`, which itself contains the substring `mlx`.
A substring assertion against the combined output is therefore satisfied by the model line
whatever the token holds.

**Verification state:** reasoned from the test name and the fixture repo id. The assertion
lines below line 45 were not read. Confirm before fixing.

### Example scenario

`TOKEN="mlx"` in `toggle.sh` is changed to any other string. The test still passes because
`mlx` appears in the repo id printed on another line.

### Notes for a fix

Assert `ANTHROPIC_AUTH_TOKEN` on its own, against an exact value, rather than searching the
combined output. Pick a fixture repo id that does not contain the token string, so the test
cannot be satisfied by the wrong line.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-11"></a>

## KI-11 — the MLX start test cannot detect a wrong server invocation

**Severity:** High
**Likelihood:** Almost always
**Where:** [mlx-serve.bats:61-69](../skills/claude-toggle-backend/tests/mlx-serve.bats#L61-L69)

### What happens

```bash
[ -f "$HOME/.claude/mlx-server.pid" ]
[ "$(cat "$HOME/.claude/mlx-server.model")" = "$REPO" ]
[ "$(cat "$HOME/.claude/mlx-last-model")" = "$REPO" ]
```

The fake `vllm-mlx` ignores every argument and the fake `curl` always reports ready, so
nothing observes the host, port, `HF_HOME`, or the `serve` subcommand actually passed.

### Example scenario

The `--port` flag is dropped from the real invocation. The fake ignores arguments, the PID
and model files are still written, and the test passes while the server would bind the wrong
port in reality.

### Notes for a fix

Have the fake record its argv to a file and assert on it. That converts the fake from a stub
into a contract check without needing a real server.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-12"></a>

## KI-12 — the stop test passes even if nothing is stopped

**Severity:** High
**Likelihood:** Almost always
**Where:** [mlx-serve.bats:85-91](../skills/claude-toggle-backend/tests/mlx-serve.bats#L85-L91)

### What happens

```bash
run bash "$SCRIPT_DIR/mlx-serve.sh" stop
[ "$status" -eq 0 ]
[ ! -f "$HOME/.claude/mlx-server.pid" ]
```

`do_stop` runs `rm -f "$PID_FILE" "$PORT_FILE" "$MODEL_FILE"` unconditionally, outside the
`is_alive` branch. So the only assertion beyond exit status is satisfied whether or not the
process was signalled. The test is named "removes state **and reports**" and asserts nothing
about the report.

### Example scenario

The `kill` calls are removed from `do_stop`. The PID file is still deleted, the test passes,
and the server keeps running with its state file gone — now unstoppable by the script.

### Notes for a fix

Assert the process is gone (`! kill -0 "$pid"`) and that the "Stopped vllm-mlx (pid …)" line
appears in the output. Capture the PID before calling stop.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-14"></a>

## KI-14 — every backup failure is logged as `ok` and exits 0

**Severity:** High
**Likelihood:** Almost always
**Where:** [backup-projects.sh:133](../skills/drive-backup/backup-projects.sh#L133)

### What happens

```bash
echo "$(ts) ok (rc=$rc_any) ->$synced -> $dest" >> "$log"
```

The literal word `ok` is written whatever `rc_any` holds, and the script ends with a bare
`exit 0`. The no-destination path also exits 0 after logging `ERROR`.

### Example scenario

Drive is unmounted, so every `rsync` fails. The log fills with `ok (rc=23)` lines. Grepping
the log for failures finds nothing, and the Stop hook reports success.

### Notes for a fix

Keep the exit code and correct the log line. **That alone is not sufficient**: rsync exit 24 is
*partial transfer due to vanished source files*, not "the transcript grew while we read it" as
the operating notes claim, and the script excludes 24 from `rc_any`. A run that lost files to a
vanishing source would still be logged `ok` after the log word is fixed. Retain the partial
status, report which inputs vanished, and correct the description in
[drive-backup/SKILL.md](../skills/drive-backup/SKILL.md) at the same time.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-28"></a>

## KI-28 — `drive-backup` uses `$CODE_ROOT` without defining it

**Severity:** High
**Likelihood:** Almost always
**Where:** [drive-backup/SKILL.md:51](../skills/drive-backup/SKILL.md#L51)

### What happens

Step 1 sets `BACKUP_DEST="$CODE_ROOT/Claude-Projects"`, but `CODE_ROOT` is defined in
`claude-setup` step 4 and nowhere in `drive-backup`. The skill advertises itself as the way to
install the backup on a machine, so it will be invoked directly.

### Example scenario

A user runs `/localclaude:drive-backup` on a new machine without running `claude-setup` first.
`$CODE_ROOT` is empty, `BACKUP_DEST` becomes `/Claude-Projects`, and `mkdir -p` either fails or
creates directories at the volume root.

### Notes for a fix

Copy the `CODE_ROOT` detection from `claude-setup` step 4 into `drive-backup`, or make the skill
refuse with a clear message when the variable is unset. **Introduced by ENH-08**, which split
this skill out of `claude-setup` and left the variable behind.

**Source:** gemini-3.1-pro-high — phase review pass 5, 2026-09-08.

---

<a id="ki-29"></a>

## KI-29 — the "already set up" shortcut accepts a hook pointing at the old path

**Severity:** High
**Likelihood:** Almost always
**Where:** [drive-backup/SKILL.md:87-89](../skills/drive-backup/SKILL.md#L87-L89)

### What happens

The idempotence check passes when the `Stop` hook "calls `backup-projects.sh`". A hook still
pointing at the pre-ENH-08 `skills/claude-setup/backup-projects.sh` satisfies that string test,
so the shortcut seeds once and leaves every later turn backing up nothing.

### Example scenario

A machine set up before the split is re-run through the skill. The check passes, the seed run
writes a fresh `rc=0` line, and the log then stops growing — which KI-14 makes indistinguishable
from success.

### Notes for a fix

Compare the hook's command against the exact current path, not a substring, and require a log
line newer than the seed run.

**Source:** gpt-6-astra — phase review pass 5, 2026-09-08.

---

<a id="ki-30"></a>

## KI-30 — two machines overwrite each other's config snapshot

**Severity:** High
**Likelihood:** Almost always
**Where:** [backup-projects.sh:112-129](../skills/drive-backup/backup-projects.sh#L112-L129)

### What happens

The config snapshot writes `settings.json`, `history.jsonl`, `.claude.json` and
`projects-backup.dest` into one shared `Config/` directory on Drive. Every machine writes the
same filenames to the same synced destination.

### Example scenario

A laptop and a desktop both run the hook. Whichever ran last owns `Config/settings.json`, so the
other machine's allowlist and its per-project approval state are gone from the backup — the one
thing the snapshot exists to make recoverable.

### Notes for a fix

Namespace by a stable machine identifier (`Config/<hostname>/…`), keeping each machine
independently restorable.

**Source:** gpt-6-astra — phase review pass 5, 2026-09-08.

---

<a id="ki-02"></a>

## KI-02 — a failed switch leaves the config pointing at a stopped server

**Severity:** High
**Likelihood:** Likely
**Where:** [toggle.sh:63-96](../skills/claude-toggle-backend/toggle.sh#L63-L96)

### What happens

Each branch stops the other backend before starting its own:

```bash
mlx)
  bash "$SCRIPT_DIR/llama-serve.sh" stop >/dev/null 2>&1 || true
  bash "$SCRIPT_DIR/mlx-serve.sh" start "$MODEL_ARG"
```

Under `set -euo pipefail`, a failed `start` aborts the script before the settings write. The
old server is already stopped and the settings still name its URL.

### Example scenario

`toggle.sh mlx` is run with the MLX model not in the HF cache. `mlx-serve.sh start` exits
non-zero, the script stops, and `settings.json` still points at `http://127.0.0.1:8730` with
`llama-server` no longer running. Claude Code then fails on every request until the user
notices and switches back by hand.

### Notes for a fix

Start the new server first, verify readiness, write settings, and only then stop the old
one. Where that is impossible because both want the same port, capture enough state to roll
back to the previous backend on failure.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-05"></a>

## KI-05 — the "one model resident" guarantee does not hold for direct starts

**Severity:** High
**Likelihood:** Likely
**Where:** [local-models/SKILL.md:175](../skills/local-models/SKILL.md#L175), [local-models/SKILL.md:81](../skills/local-models/SKILL.md#L81)

### What happens

The skill states the backends are "mutually exclusive at runtime (one model resident)". That
is enforced only inside `toggle.sh`, which stops the other server before starting its own.
Calling `llama-serve.sh start` or `mlx-serve.sh start` directly bypasses it entirely.
Switching away from Ollama also does not unload Ollama's resident model, which idles out on
its own schedule.

### Example scenario

`mlx-serve.sh start <repo>` is run directly while `llama-server` holds a 22 GB model. Both
stay resident, the machine swaps hard, and the documented guarantee gave no warning.

### Notes for a fix

Either move the mutual stop into the two serve scripts so it holds however they are invoked,
or narrow the claim in the docs to "`toggle.sh` enforces this; direct starts do not". The
second is a one-line change and is honest.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-08"></a>

## KI-08 — backup destination discovery picks the first Drive account it finds

**Severity:** High
**Likelihood:** Likely
**Where:** [backup-projects.sh:47-67](../skills/drive-backup/backup-projects.sh#L47-L67), [drive-backup/SKILL.md](../skills/drive-backup/SKILL.md)

### What happens

```bash
for c in "$HOME/Library/CloudStorage/"GoogleDrive-*"/My Drive/AnswerRocket/Code/Claude-Projects" \
         "$HOME/Library/CloudStorage/"GoogleDrive-*"/My Drive/Code/Claude-Projects" \
  [ -d "$c" ] && { dest="$c"; break; }
```

With two signed-in Google accounts the glob expands to both, and the first match by glob
order wins. The same first-match approach picks the skills source directory during setup.

### Example scenario

A personal and a work Drive are both mounted. Glob order puts the work account first, so
personal transcripts, plans and the config snapshot are written into the work Drive.

### Notes for a fix

`~/.claude/projects-backup.dest` already takes precedence and is the intended escape hatch,
so the fix is mostly about failing loudly: when the glob matches more than one candidate,
refuse to guess and tell the user to write the path to that file. Same treatment for the
skills-source discovery in `claude-setup`.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-13"></a>

## KI-13 — test cleanup kills unrelated processes on the machine

**Severity:** High
**Likelihood:** Likely
**Where:** [mlx-serve.bats:111](../skills/claude-toggle-backend/tests/mlx-serve.bats#L111)

### What happens

```bash
kill "$bg" 2>/dev/null || true
pkill -f 'sleep 300' 2>/dev/null || true
```

`pkill -f 'sleep 300'` matches any process on the machine whose command line contains that
string, not only the fake daemon this test started.

### Example scenario

The user has a shell running `sleep 300` in an unrelated terminal, or any script that shells
out to it. Running the test suite kills it.

### Notes for a fix

Kill only the recorded PID, and use a distinctive sentinel in the fake's command line if a
pattern match is genuinely needed. A process group started by the test is cleaner: kill the
group rather than searching by name.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-33"></a>

## KI-33 — symlinked backup inputs are skipped without a failure status

**Severity:** High
**Likelihood:** Likely
**Where:** [backup-projects.sh:101-102](../skills/drive-backup/backup-projects.sh#L101-L102), [backup-projects.sh:123-129](../skills/drive-backup/backup-projects.sh#L123-L129)

### What happens

The transfers use `rsync -rt`, with neither `-l` (recreate symlinks) nor `-L` (follow them). A
symlink inside a source tree, or an individually listed config file that is a symlink, is
skipped with a "skipping non-regular file" warning on stdout — which the `Stop` hook discards to
`/dev/null`. Nothing reaches the log and `rc_any` is unaffected.

### Example scenario

A config file under `~/.claude` is a symlink to a file kept elsewhere. It is silently absent
from every backup, and the log says `ok` each time. The omission is discovered only when the
backup is used to restore a machine.

### Notes for a fix

Decide the policy explicitly rather than inheriting rsync's default — `-l` to preserve the links
or `-L` to copy their targets — and report anything omitted. Separate from KI-14: that entry is
about the log word, this one is about inputs never attempted.

**Source:** gpt-6-astra — phase review pass 6, 2026-09-08.

---

<a id="ki-03"></a>

## KI-03 — a PID file is trusted without checking what the process is

**Severity:** High
**Likelihood:** Rare
**Where:** [llama-serve.sh:31-35](../skills/claude-toggle-backend/llama-serve.sh#L31-L35), [mlx-serve.sh:51-55](../skills/claude-toggle-backend/mlx-serve.sh#L51-L55)

### What happens

```bash
is_alive() {
  [ -f "$PID_FILE" ] || return 1
  local pid; pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}
```

`kill -0` proves only that *some* process with that number exists and is signalable. Nothing
confirms the executable is `llama-server` or `vllm-mlx`. `do_stop` then sends `TERM` and
`KILL` to it.

### Example scenario

The server is killed by the OS during a memory spike and the stale PID file survives. The
kernel later reuses that PID for the user's editor. The next `toggle.sh anthropic` calls
`do_stop`, which signals the editor and kills it.

### Notes for a fix

Before signalling, confirm the process command matches — `ps -o comm= -p "$pid"` on macOS —
and treat a mismatch as a stale file to delete rather than a process to kill. Reject a PID
file whose content is not a positive integer, which also removes the negative-PID path where
`kill` would target a process group.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-04"></a>

## KI-04 — the stray-process sweep kills servers this plugin did not start

**Severity:** High
**Likelihood:** Rare
**Where:** [llama-serve.sh:49-57](../skills/claude-toggle-backend/llama-serve.sh#L49-L57), [mlx-serve.sh:67-75](../skills/claude-toggle-backend/mlx-serve.sh#L67-L75)

### What happens

```bash
local stray; stray="$(pgrep -f 'llama-server -m' 2>/dev/null || true)"
if [ -n "$stray" ]; then
  for p in $stray; do kill "$p" 2>/dev/null || true; done
```

Every matching process owned by the user is killed. The code comment says this is deliberate
("e.g. one launched outside this script"), so the defect is that the behaviour is undocumented
for the user, not that it is unintentional.

### Example scenario

A `llama-server` is running by hand on a different port for an unrelated experiment.
Switching the Claude Code backend to `anthropic` kills it without warning, and nothing in the
skill documentation says it will.

### Notes for a fix

Two options, and the choice is the user's. Either narrow the sweep to processes whose port or
PID file this plugin owns, or keep the sweep and document it plainly in
`claude-toggle-backend/SKILL.md`, including in the `stop` command's output. Decide before
touching the code.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-06"></a>

## KI-06 — a stale lock silently disables every later backup

**Severity:** High
**Likelihood:** Rare
**Where:** [backup-projects.sh:73-77](../skills/drive-backup/backup-projects.sh#L73-L77)

### What happens

```bash
lock="${TMPDIR:-/tmp}/claude-projects-backup.lock"
if ! mkdir "$lock" 2>/dev/null; then
  exit 0   # a run is already in progress
fi
trap 'rmdir "$lock" 2>/dev/null' EXIT
```

The `EXIT` trap does not fire on `SIGKILL` or on power loss. A surviving lock directory makes
every later run take the `exit 0` path, writing nothing to the log. The Stop hook discards
output, so nothing surfaces.

### Example scenario

The machine loses power mid-backup. Every subsequent Stop hook exits successfully and copies
nothing. Transcripts stop reaching Drive and the first sign is a missing project weeks later.

### Notes for a fix

Record the PID in the lock and treat a lock whose PID is not alive as stale. Log the skip
rather than exiting silently, so `projects-backup.log` shows the reason. Note that `TMPDIR`
on macOS is per-user and cleared periodically, so the lock is not permanent — the silent exit
is the defect, not the lock's lifetime. Related: KI-14, the same file reporting `ok` on
failure.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-37"></a>

## KI-37 — a replaced evidence slot keeps its old grade

**Severity:** High
**Likelihood:** Rare
**Where:** [grade_batch.py:264-266](../skills/design-review/tests/grade_batch.py#L264-L266)

### What happens

`collect` treats a packet as already collected when its judgement and report exist for the
logged grader. It does not compare the packet's answer hash with the answer the evidence batch
now records. If a run is replaced after `prepare`, its old grade stays, and `agree` and
`summary` count it for an answer that is no longer in the batch.

### Example scenario

A with-skill run is found contaminated after grading starts and is re-run with
`evidence.py log-dispatch --replace`. The evidence check passes again, `collect` reports every
packet as already collected, and the summary reports the voided answer's grade.

### Notes for a fix

Before accepting a cached grade, compare the packet's `answer_hash` with the manifest entry for
its slot, and refuse with a message to prepare a new grading directory. Astra's F-06 fixed the
currentness check for uncached packets only. Until this is fixed, complete the evidence batch
before `prepare` and never replace a slot afterwards.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-38"></a>

## KI-38 — an assertion the test expects to fail still grades as did-not-hold

**Severity:** High
**Likelihood:** Rare
**Where:** [grade_eval.py:270-290](../skills/design-review/tests/grade_eval.py#L270-L290)

### What happens

An `assert` inside `with pytest.raises(AssertionError):`, or inside a `try` whose handler
catches `AssertionError`, is evaluated as an ordinary guard. When it evaluates False, the
executed check reports did-not-hold, although that failure is what the test expects.

### Example scenario

A replacement test checks that a helper rejects bad input by asserting inside
`pytest.raises(AssertionError)`. The executed check reports the assertion as did-not-hold, and a
grader reads it as a broken fixture.

### Notes for a fix

Treat a guard whose failure is expected by the enclosing context manager or handler as
could-not-evaluate. The behaviour predates the overnight QC passes.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-16"></a>

## KI-16 — `HF_HOME` is exported by an orphaned `~/.zshrc` block no skill installs

**Severity:** Medium · **Partly held**
**Likelihood:** Almost always
**Where:** [local-models/SKILL.md:15](../skills/local-models/SKILL.md#L15), [local-models/SKILL.md:28](../skills/local-models/SKILL.md#L28), [claude-toggle-backend/SKILL.md](../skills/claude-toggle-backend/SKILL.md) (the managed block)

**The doc half is held; the installer half is not.** The two false sentences are in
`local-models`, which is being rebuilt. The missing installer is machine setup and is in scope
now — an entry naming a held skill is not automatically held.

### What happens

`local-models` says twice that `HF_HOME=$LOCAL_MODELS_DIR` is "set globally in `~/.zshrc`" by
the plugin's managed block. The plugin's managed block exports only `LLAMACPP_PORT=8730`.

But `HF_HOME` *is* exported on the development machine, by a second block that carries
`localclaude` branding and that **no skill in this repo installs**:

```bash
# >>> localclaude HF_HOME >>>
export HF_HOME="$HOME/Local-Models"
# <<< localclaude HF_HOME <<<
```

`git log -S"localclaude HF_HOME" --all` returns nothing, so it was never installed by code —
it was hand-written and branded as though it had been.

### Example scenario

This is why the defect survived a review. Anyone verifying the claim on the machine that has
the orphan runs the skill's own check, `echo $HF_HOME`, sees `~/Local-Models`, and concludes
the docs are right. On a machine set up from the skills as written, the same check prints
nothing and the install reads as broken. The practical impact stays limited because the skill
passes `HF_HOME` explicitly on every `hf` command, so downloads land correctly either way.

### Notes for a fix

Two separable pieces:

- **Installer (in scope).** Decide whether `HF_HOME` belongs in the managed block that
  `claude-toggle-backend` now owns. If yes, add it there with the rest of the shell block so
  one writer owns the file. If no, delete the orphan from `~/.zshrc` so no machine disagrees
  with the repo.
- **Docs (held).** Correct the two `local-models` sentences to match whichever way the
  installer goes. The rebuild should not restate the claim without an installer behind it.

**A branded block with no installer is the failure mode to look for**, not just this variable.
The marker text asserts an owner, so the next person to touch `~/.zshrc` — including the
hardened strip — reasons about it as managed code when nothing generates it.

**Source:** gpt-5.6-sol — repo review, 2026-09-05; orphan found 2026-09-07 while auditing the
`~/.zshrc` writers after ENH-09.

---

<a id="ki-17"></a>

## KI-17 — the machine is documented as both 64 GB and 24 GB

**Severity:** Medium
**Likelihood:** Almost always
**Where:** [local-models/SKILL.md:55](../skills/local-models/SKILL.md#L55), [claude-toggle-backend/SKILL.md:17](../skills/claude-toggle-backend/SKILL.md#L17), [claude-toggle-backend/SKILL.md:88](../skills/claude-toggle-backend/SKILL.md#L88), [claude-toggle-backend/SKILL.md:115](../skills/claude-toggle-backend/SKILL.md#L115)

### What happens

`local-models` records the machine as an **Apple M4 Max, 64 GB** and adds *"this line has
been wrong before"*. `claude-toggle-backend` states a **24 GB** constraint three times, and
[toggle.sh:16](../skills/claude-toggle-backend/toggle.sh#L16) repeats it in a comment on the
Ollama default.

### Example scenario

`gemma4:latest` is chosen as the Ollama default because it "fits 24 GB with headroom", when
the machine has 64 GB and could hold a far stronger model. Line 115 warns that a ~23 GB model
"leaves ~1 GB free and will swap/OOM" — false on a 64 GB machine, so a good model is being
avoided for no reason.

### Notes for a fix

Pick one source of truth. `local-models` already says to trust the detected value over
anything written down, so the sizing lines in `claude-toggle-backend` should either read the
detected value or point at `local-models` instead of restating a number.

**Verification note:** the first check of this finding used Claude Code's shadowed `grep`,
whose injected `--ignore-files` and exclude defaults returned no matches, and it was briefly
recorded as not reproduced. `/usr/bin/grep` shows all four lines. Use the system grep when a
negative result is meant as evidence.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-21"></a>

## KI-21 — uninstall says the server is left alone, then stops it

**Severity:** Medium
**Likelihood:** Almost always
**Where:** [llama-autostart.sh:70-78](../skills/claude-toggle-backend/llama-autostart.sh#L70-L78)

### What happens

```bash
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
...
echo "Uninstalled $LABEL (removed plist; auto-start disabled). The running server, if any, is left alone — stop it with llama-cpp-down."
```

`bootout` terminates the LaunchAgent's process. When the running server was started by the
agent, which is the normal case, the message is wrong.

### Example scenario

The user runs uninstall intending to keep the current session's server alive, reads the
message confirming that, and finds Claude Code failing on the next request.

### Notes for a fix

Either correct the message, or detect whether the running server is the agent's child and say
which happened. The message is the cheaper fix and the honest one.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-23"></a>

## KI-23 — "detect llama-cpp by marker" passes without any marker handling

**Severity:** Medium
**Likelihood:** Almost always
**Where:** [toggle.bats:25](../skills/claude-toggle-backend/tests/toggle.bats#L25), [toggle.sh:36](../skills/claude-toggle-backend/toggle.sh#L36)

### What happens

`current_backend` falls back to `llama-cpp` when the marker is missing or unrecognised:

```python
print(marker if marker in ("mlx", "llama-cpp") else "llama-cpp")
```

The test sets the marker to `llama-cpp` and expects `llama-cpp`, which the fallback already
produces. The very next test asserts the same output for the missing-marker case, so two
tests cover one behaviour and neither distinguishes it.

### Example scenario

Marker reading is removed entirely. The `llama-cpp` test still passes; only the `mlx` test
goes red, so the failure understates what broke.

### Notes for a fix

Change the fallback default, or assert the llama-cpp case against a marker value that the
fallback would not produce. Keep the missing-marker test, which is the one that genuinely
covers the default.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-24"></a>

## KI-24 — "status runs clean" asserts neither server's status line

**Severity:** Medium
**Likelihood:** Almost always
**Where:** [toggle.bats:30-34](../skills/claude-toggle-backend/tests/toggle.bats#L30-L34)

### What happens

```bash
run bash "$SCRIPT_DIR/toggle.sh" status
[ "$status" -eq 0 ]
[[ "$output" == *"current backend"* ]]
```

The comment above the test says it *"exercises the full status path: toggle.sh status calls
both llama-serve.sh and mlx-serve.sh status — both must return 0"*. Neither call is asserted.

### Example scenario

The `mlx-serve.sh status` line is deleted from `toggle.sh`. The test passes, and the comment
still claims the path is covered.

### Notes for a fix

Assert on a distinctive string from each server's status output. Then fix the comment, or
delete it — a comment claiming coverage the test does not provide is worse than no comment.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-25"></a>

## KI-25 — "auto-picks a numeric free port" accepts any number

**Severity:** Medium
**Likelihood:** Almost always
**Where:** [mlx-serve.bats:43-46](../skills/claude-toggle-backend/tests/mlx-serve.bats#L43-L46)

### What happens

```bash
run bash "$SCRIPT_DIR/mlx-serve.sh" __port
[ "$status" -eq 0 ]; [[ "$output" =~ ^[0-9]+$ ]]
```

Any digits satisfy the assertion, including a hard-coded constant.

### Example scenario

`pick_port` is replaced with `echo 8740`. The test passes even if 8740 is permanently
occupied, which is exactly the condition the scan exists to avoid.

### Notes for a fix

Occupy the first candidate port in the test, then assert the returned port differs from it.
That makes the scan the only implementation that can pass.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-26"></a>

## KI-26 — the foreground test asserts only the model file

**Severity:** Medium
**Likelihood:** Almost always
**Where:** [mlx-serve.bats:104](../skills/claude-toggle-backend/tests/mlx-serve.bats#L104)

### What happens

The foreground path writes the PID file, the port file, the last-model state and finally
`exec`s the server with its full argument list. The test asserts the model file alone.

**Verification state:** reasoned from the surrounding tests' pattern; this test body was not
read in full. Confirm before fixing.

### Example scenario

The `exec` is dropped so the server runs as a child rather than replacing the shell. Signal
handling changes and the test stays green.

### Notes for a fix

Assert the port file, the last-model file, and the recorded argv (see KI-11, which needs the
same argv-recording fake). Bundle these two into one pass.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-46"></a>

## KI-46 — the phase cleanup cannot delete a squash-merged branch

**Severity:** Medium
**Likelihood:** Almost always
**Where:** [phase-workflow/SKILL.md](../skills/phase-workflow/SKILL.md) §4 step 7 (local prune),
[publish-release.sh](../skills/phase-workflow/publish-release.sh) (branch deletion)

### What happens

§2 step 3 records the first allowed merge method, trying `squash` before `rebase` and `merge`.
§4 merges with that method, then prunes local branches whose upstream is gone using
`git branch -d`.

A squash merge writes a new commit with no ancestry to the branch it came from, so `-d` refuses
that branch however completely its work landed. The step reports `RETAINED — branch deletion
failed; inspect it by hand` and exits 1.

The comment above the line states the premise it rests on:

> `-d` refuses a branch holding unmerged work, which is exactly the retain rule.

That holds for a merge commit and for a rebase. It does not hold for a squash — the method the
preflight selects first. `publish-release.sh` carries the same call under the message
`BRANCH HOLDS UNMERGED WORK — retaining it`, which is likewise false in this case.

### Example scenario

PRs #2 and #3, squash-merged as v1.10.1 and the ENH-27 entry. `git branch -d` refused both
while `git diff <branch> main` was empty for both, so no work was outstanding in either.
Reproduced from scratch: `git merge --squash` a branch, confirm the diff against the default
branch is empty, and `git branch -d` still exits 1.

### Why it matters past the false alarm

It fails safe — the branch is retained and nothing is lost, which is why this is Medium and not
High. The cost is that the guard fires on every squash-merged phase, and the block bolds
**Never -D here** while leaving no other way past it. A guard that is wrong every time is the
kind an operator learns to force past, and `-D` is the one command in that block that really can
discard commits that were never pushed.

### Notes for a fix

**The block already has the answer before it deletes anything.** It has confirmed
`MERGED_HEAD = APPROVED_SHA` and `REMOTE_HEAD = APPROVED_SHA`. A local branch still pointing at
`APPROVED_SHA` therefore holds nothing absent from the remote, and is safe to delete outright.

Where a general test is wanted, `git cherry <default> <branch>` discriminates correctly: it marks
a commit `-` when an equivalent change is already upstream and `+` when it is not. Verified both
ways — a squash-merged branch shows only `-`, and a branch carrying one genuinely unmerged commit
shows `+`. `[ -z "$(git diff <branch> <default>)" ]` also discriminates, comparing trees rather
than commits.

Keep the retain rule; replace only the test it rests on, and give the refusal message the reason
it retained. The fix touches `phase-git.bats`, which executes the SKILL.md fences directly, so it
needs a red test per arm first: one squash-merged branch that must be deleted, one branch with an
unpushed commit that must be retained.

**Source:** claude-opus-5 — found while cleaning up after the v1.10.1 merge, 2026-09-16.

---

<a id="ki-18"></a>

## KI-18 — `toggle.sh` needs `python3` and never checks for it

**Severity:** Medium
**Likelihood:** Likely
**Where:** [toggle.sh:27](../skills/claude-toggle-backend/toggle.sh#L27), [README.md:30](../README.md#L30)

### What happens

`toggle.sh` shells out to `python3` for backend detection and for the settings write. There is
no `command -v python3` preflight anywhere in the script. README states the opposite:
*"Each skill checks the tools its current task needs and, if one is missing, stops and gives
you the install command rather than failing mid-run."*

### Example scenario

On a Mac without Command Line Tools installed, `toggle.sh status` fails with a raw
`command not found: python3` partway through, after the stop calls have already run.

### Notes for a fix

Add the preflight beside the existing `[ -f "$SETTINGS" ]` check, with the install hint
(`xcode-select --install`). Alternatively drop the Python dependency: the JSON edits are
small enough for `jq`, which would then need its own preflight.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-31"></a>

## KI-31 — the lock drops the last backup of a session

**Severity:** Medium
**Likelihood:** Likely
**Where:** [backup-projects.sh:75-79](../skills/drive-backup/backup-projects.sh#L75-L79)

### What happens

An overlapping invocation exits immediately, on the assumption that the run already in progress
captures the newest state. It does not: a run that has already copied `Code/` and is working
through Cowork will not pick up a turn that finishes afterwards.

### Example scenario

The final turn of a session ends while a backup is mid-flight. Its transcript is never copied,
and no later turn triggers the hook because the session is over.

### Notes for a fix

Record a pending rerun when the lock is held and run once more on release. Distinct from KI-06,
which is about a lock left behind by a killed process.

**Source:** gpt-6-astra — phase review pass 5, 2026-09-08.

---

<a id="ki-36"></a>

## KI-36 — a grader quote of a table cell that holds a pipe is refused

**Severity:** Medium
**Likelihood:** Likely
**Where:** [grade_batch.py:188-194](../skills/design-review/tests/grade_batch.py#L188-L194)

### What happens

Answers are Markdown. In a table cell a pipe must be written `\|`, including inside a code
span, and renderers display it as `|`. `unquoted()` compares the grader's quote with the raw
answer text, so a quote of the rendered cell (`str | None`) does not match `str \| None`, and
`collect` refuses the judgement.

### Example scenario

In round 9 the repeat grader for S02 baseline replicate 2 quoted
`normalise_prefix(sku: str) -> str | None` from a module table. The grade was refused and
replaced, so its verdict, a Lifetime fail, is missing from the 40/40 agreement count.

### Notes for a fix

Replace `\|` with `|` in both the quote and the answer before matching; doing it on both sides
keeps raw quotes matching. `&#124;` is no alternative for authors, because entities are not
decoded inside code spans.

**Source:** claude-opus-5 — round-9 grading, 2026-09-14.

---

<a id="ki-39"></a>

## KI-39 — `print` with an f-string argument still hides later guards

**Severity:** Medium
**Likelihood:** Likely
**Where:** [grade_eval.py:42-47](../skills/design-review/tests/grade_eval.py#L42-L47)

### What happens

The fixture interpreter supports `print` with plain arguments but cannot evaluate an f-string
(`ast.JoinedStr`). A `print(f"x={x}")` diagnostic leaves the rest of the test body unknown, so
later independent guards report could-not-evaluate. QC test T3-2 covers only
`print("debug", x)`.

### Example scenario

A replacement test prints `f"window={start}"` before its property assertions. The executed
checks lose every assertion after the print, and the grader gets no executed evidence for
fixture validity.

### Notes for a fix

Evaluate `JoinedStr` and `FormattedValue` under the same size bound as string concatenation,
or skip a bare `print` statement without evaluating its arguments. Add an f-string case to
T3-2.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-40"></a>

## KI-40 — the roadmap check fails on freshly seeded roadmap files

**Severity:** Medium
**Likelihood:** Likely
**Where:** [phase-workflow/SKILL.md:454-455](../skills/phase-workflow/SKILL.md#L454-L455)

### What happens

The procedure runs `roadmap.py check || exit 1` after every roadmap edit. Roadmap files seeded
from the bundled templates still hold placeholder rows, which the check rejects, so the first
roadmap edit in a new repository stops the procedure.

### Example scenario

A new project seeds its roadmap files and the first phase files one known issue. The check
fails on the template placeholders, not on the new entry.

### Notes for a fix

Seed templates that pass the check, or let the check accept untouched placeholder rows. Add a
bats case that seeds the templates and runs the check.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-19"></a>

## KI-19 — port selection releases the socket before the server binds

**Severity:** Medium
**Likelihood:** Rare
**Where:** [llama-serve.sh:85-92](../skills/claude-toggle-backend/llama-serve.sh#L85-L92), [mlx-serve.sh:80](../skills/claude-toggle-backend/mlx-serve.sh#L80)

### What happens

`pick_port` bind-tests candidate ports in a short-lived Python process, closes the socket, and
prints the number. The server binds it some moments later. Anything else on the machine may
take the port in between. The `port` command also prints whatever the port file holds without
confirming a process is listening.

### Example scenario

A dev server starts in another terminal during the gap and takes 8730. `llama-server` then
fails to bind, and `toggle.sh` has already stopped the previous backend (see KI-02).

### Notes for a fix

Retry the whole select-and-bind sequence on failure rather than trying to make the check
atomic, which is not possible from a separate process. For `port`, verify liveness before
printing, or say the value is last-known rather than current.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-20"></a>

## KI-20 — LaunchAgent plist values are not XML-escaped

**Severity:** Medium
**Likelihood:** Rare
**Where:** [llama-autostart.sh:28-35](../skills/claude-toggle-backend/llama-autostart.sh#L28-L35)

### What happens

The plist is a heredoc with shell interpolation straight into `<string>` elements:

```bash
cat > "$PLIST" <<PLIST
  <key>Label</key><string>$LABEL</string>
```

`&`, `<` and `>` in an interpolated path or value produce invalid XML.

### Example scenario

The plugin is installed under a path containing `&` — a Drive folder named `R&D`, for
instance. `launchctl` then refuses the plist with a parse error that does not name the cause.

### Notes for a fix

Escape the five XML entities before interpolation, or build the plist with `plutil` /
`PlistBuddy` rather than string concatenation. Low likelihood on the current machine, cheap to
fix.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-32"></a>

## KI-32 — repository approval state is no longer in the file the backup collects

**Severity:** Medium
**Likelihood:** Rare
**Where:** [drive-backup/SKILL.md:29-32](../skills/drive-backup/SKILL.md#L29-L32), [claude-setup/REFERENCE.md:21](../skills/claude-setup/REFERENCE.md#L21)

### What happens

Both files say the invisible per-project "always allow" state lives in `~/.claude.json`, and the
snapshot collects that file on those grounds. Current Claude Code records persistent repository
approvals in each repo's `.claude/settings.local.json`, which the snapshot does not collect.

### Example scenario

A machine is rebuilt from the backup. The global allowlist returns; every per-repository
approval the user clicked does not, and the claim in the docs says otherwise.

### Notes for a fix

Verify where the current version stores this, version-scope the legacy sentence, and decide
explicitly whether repo-local approval state belongs in a Drive backup at all — it is per-repo
state that arguably belongs in the repo.

**Source:** gpt-6-astra — phase review pass 5, 2026-09-08.

---

<a id="ki-34"></a>

## KI-34 — a destination inside a source tree nests backups recursively

**Severity:** Medium
**Likelihood:** Rare
**Where:** [backup-projects.sh:48-71](../skills/drive-backup/backup-projects.sh#L48-L71), [backup-projects.sh:94-102](../skills/drive-backup/backup-projects.sh#L94-L102)

### What happens

An explicitly configured destination is accepted if the directory merely exists. Nothing checks
that it sits outside the trees being copied, so a destination such as
`~/.claude/projects/archive` is taken, and the run then copies `~/.claude/projects` — including
that archive — into the archive's own `Code/` directory.

### Example scenario

A user points `projects-backup.dest` at a folder inside `~/.claude/projects` to keep everything
together. Each run copies the previous run's copy, the tree grows a level deeper every turn
until the disk fills, and the log says `ok` throughout.

### Notes for a fix

Resolve source and destination to physical paths with `pwd -P` before copying and refuse when
either contains the other, including overlap reached through a directory symlink.

**Source:** gpt-6-astra — phase review pass 7, 2026-09-08.

---

<a id="ki-41"></a>

## KI-41 — converting a large sequence to text has no size bound

**Severity:** Medium
**Likelihood:** Rare
**Where:** [grade_eval.py:49](../skills/design-review/tests/grade_eval.py#L49) (`SAFE_CALLS`)

### What happens

Repetition and concatenation are bounded before allocation, but `str()` of a large list is not,
and a grade run has no timeout. A fixture that builds a list of long strings within the
sequence bound and converts it to text can allocate from tens of megabytes to many gigabytes.

### Example scenario

An answer's test builds a long list of long strings and formats it into a message. `prepare`
stalls on that answer or exhausts memory, and the whole batch waits.

### Notes for a fix

Bound the rendered size of `str`, `repr` and formatting, and run each grade with a timeout.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-42"></a>

## KI-42 — one edited dispatch file stops `collect` for every packet

**Severity:** Medium
**Likelihood:** Rare
**Where:** [grade_batch.py:261-263](../skills/design-review/tests/grade_batch.py#L261-L263)

### What happens

`collect` checks every logged packet's dispatch hash before it collects any, and exits on the
first mismatch. One edited `dispatch/<ID>.txt` blocks every other finished grade. The README's
advice, to prepare a new grading directory, also discards every grade already collected.

### Example scenario

An editor normalises line endings when a packet file is opened and saved. The next `collect`
refuses the batch, although 83 of 84 packets are intact.

### Notes for a fix

Report the edited packet as refused and continue with the others, so only that packet needs
attention.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-43"></a>

## KI-43 — a ready reviewer probe reads as TIMEOUT when stderr mentions a timeout

**Severity:** Medium
**Likelihood:** Rare
**Where:** [preflight.sh:119](../skills/external-review/preflight.sh#L119)

### What happens

The probe checks `timed_out "$ERR"` before it checks exit 0 and the answer `ready`. A probe
that succeeds but writes a warning containing "timed out" to stderr is reported as
`TIMEOUT — inconclusive`.

### Example scenario

A CLI logs a retried network call ("request timed out, retrying") and then answers `ready`.
Preflight reports the reviewer as inconclusive, and the review runs with less coverage than it
could have.

### Notes for a fix

Classify exit 0 with the answer `ready` first, then timeouts. Found by reading the
classification order; not reproduced with a real CLI.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-27"></a>

## KI-27 — status tests depend on the host's real processes

**Severity:** Low
**Likelihood:** Likely
**Where:** [llama-serve.bats:7](../skills/claude-toggle-backend/tests/llama-serve.bats#L7)

### What happens

The status tests call the host's real `pgrep` rather than a fake, so any unrelated
`llama-server` process on the machine changes their result.

### Example scenario

A developer has a `llama-server` running for their own use. The suite reports a failure that
has nothing to do with the change under test, or hides one that does.

### Notes for a fix

Put a fake `pgrep` on `PATH` in the test helper, as the suite already does for `curl` and
`vllm-mlx`. Related: KI-13, which is the other place these tests reach outside their sandbox.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-44"></a>

## KI-44 — a stale dispatch log gives a misleading replacement message

**Severity:** Low
**Likelihood:** Rare
**Where:** [evidence.py:565-566](../skills/design-review/tests/evidence.py#L565-L566)

### What happens

When a run is replaced through `record` while the dispatch log still names the old agent, the
check reports "replacement dispatch has not been recorded". The replacement was recorded; the
dispatch log is what is out of date.

### Example scenario

An operator re-runs `record` several times after the message. The fix was to log the new agent
with `log-dispatch --replace`.

### Notes for a fix

Name both agent IDs in the message and say which command brings the log and the manifest back
in line.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.
