# Known Issues

Open defects, most severe first. [ROADMAP.md](ROADMAP.md) carries the one-line index; this
file carries enough detail to pick an item up without digging.

Each entry has a stable ID — use it in branch names (`bugfix/ki-02-<slug>`) and in the
CHANGELOG entry that closes it. When fixed, delete it from here and from the ROADMAP index;
the record lives in [CHANGELOG.md](../CHANGELOG.md). IDs are never reused.

Every entry below came from the external repo review of 2026-09-05 and carries its source
line. Findings about `phase-workflow`, `external-review` and the global standards were
remediated in the same phase and are not listed here — they are in the CHANGELOG.

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

Active: **KI-06, KI-07, KI-08 and KI-14** — the `backup-projects.sh` cluster, scheduled as its
own phase with a bats harness (ENH-03).

**An entry naming a held skill is not automatically held.** Several were filed against a
defect that appears in both a held script and a `claude-setup` one; check the "Where" lines
against the skill boundary rather than the title. KI-22 and KI-16 are both such cases, and
KI-16 shows the second shape: a held skill's *documentation* describing a real gap in
machine setup, which is not held.

---

<a id="ki-01"></a>

## KI-01 — `settings.json` is truncated before it is rewritten

**Severity:** Critical
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
**Where:** [llama-autostart.sh:75](../skills/claude-toggle-backend/llama-autostart.sh#L75)

**Fixed in `claude-setup`, held in `claude-toggle-backend`.** The shell-block installer at
`claude-setup` step 7 had the same defect and now requires both markers, backs the file up,
and writes through `mktemp`. `llama-autostart.sh` still carries the original pattern and is
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
`claude-setup` step 7 block, which now does all three and is verified against a hand-deleted
closing marker.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-02"></a>

## KI-02 — a failed switch leaves the config pointing at a stopped server

**Severity:** High
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

<a id="ki-03"></a>

## KI-03 — a PID file is trusted without checking what the process is

**Severity:** High
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

<a id="ki-05"></a>

## KI-05 — the "one model resident" guarantee does not hold for direct starts

**Severity:** High
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

<a id="ki-06"></a>

## KI-06 — a stale lock silently disables every later backup

**Severity:** High
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

<a id="ki-07"></a>

## KI-07 — credentials are copied to Drive with no scan or warning

**Severity:** High
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

<a id="ki-08"></a>

## KI-08 — backup destination discovery picks the first Drive account it finds

**Severity:** High
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

<a id="ki-09"></a>

## KI-09 — `toggle.bats` "clears env" never asserts that the env was cleared

**Severity:** High
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

<a id="ki-13"></a>

## KI-13 — test cleanup kills unrelated processes on the machine

**Severity:** High
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

<a id="ki-14"></a>

## KI-14 — every backup failure is logged as `ok` and exits 0

**Severity:** High
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

Write `ok` only when `rc_any` is 0 and `failed` otherwise, so the log is greppable. Keep
`exit 0` if the hook must never block the session, but make the log the honest record.
Related: KI-06.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.

---

<a id="ki-16"></a>

## KI-16 — `HF_HOME` is exported by an orphaned `~/.zshrc` block no skill installs

**Severity:** Medium · **Partly held**
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

<a id="ki-18"></a>

## KI-18 — `toggle.sh` needs `python3` and never checks for it

**Severity:** Medium
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

<a id="ki-19"></a>

## KI-19 — port selection releases the socket before the server binds

**Severity:** Medium
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

<a id="ki-21"></a>

## KI-21 — uninstall says the server is left alone, then stops it

**Severity:** Medium
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

<a id="ki-27"></a>

## KI-27 — status tests depend on the host's real processes

**Severity:** Low
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
