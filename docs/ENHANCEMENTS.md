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

<a id="enh-14"></a>

## ENH-14 — Share recorded-answer validation between evidence and grading

**Priority:** Medium · **Effort:** ~1 day
**Where:** [evidence.py](../skills/design-review/tests/evidence.py) · **Regression net:** `skills/design-review/tests/evidence.bats`

### What it is

Extract one answer reader that checks containment, presence, nonempty text and the recorded hash, and use it from the evidence and grading tools. Grade selection already reuses evidence.slot_key; answer validation still has separate implementations.

### Why it matters

Different readers can accept different evidence for the same manifest record.

### Notes for the work

Preserve evidence.py and grade_batch.py commands, exit codes and manifest formats. This crosses tools outside the small QC edits; test missing, empty, changed and escaping paths at every caller. Source: QC Tier 5, grade.py reuse.

---

<a id="enh-15"></a>

## ENH-15 — Probe independent reviewers concurrently

**Priority:** Medium · **Effort:** ~1 day
**Where:** [preflight.sh](../skills/external-review/preflight.sh) · **Regression net:** `skills/external-review/tests/preflight.bats`

### What it is

Run the Codex and Gemini availability ladders concurrently, with one deadline per reviewer and deterministic reporting after both finish.

### Why it matters

Sequential probes make a slow unavailable reviewer delay discovery of the other reviewer.

### Notes for the work

Keep per-reviewer readiness, quota and incomplete-turn semantics, high effort flags, exit status and partial coverage accounting. Timeout classification and duplicate final-rung output were fixed in the QC pass. Concurrent collection requires a separate change. Source: QC Tier 5, preflight reuse.

---

<a id="enh-16"></a>

## ENH-16 — Emit shared answer evidence once in grading JSON

**Priority:** Medium · **Effort:** ~1 day
**Where:** [grade.py](../skills/design-review/tests/grade.py) · **Regression net:** `skills/design-review/tests/grade.bats`

### What it is

Store the full extracted answer evidence once per report and reference it from questions instead of serializing one copy per condition.

### Why it matters

Repeating a long answer enlarges reports and packets without adding evidence.

### Notes for the work

Audit all consumers and provide a migration for existing reports before changing the JSON layout. Keep tonight's batch interface intact. The separate --production coverage gap is now covered by a CLI regression. Source: QC Tier 5, grading output size.

---

<a id="enh-17"></a>

## ENH-17 — Give roadmap rating scales one source

**Priority:** Medium · **Effort:** ~1 day
**Where:** [roadmap.py](../skills/phase-workflow/roadmap.py) · **Regression net:** `skills/phase-workflow/tests/roadmap.bats`

### What it is

Make the issue severity, likelihood and enhancement priority scales shared between the templates and the roadmap validator.

### Why it matters

Editing a template can leave a valid documented rating rejected by hardcoded Python ranks.

### Notes for the work

Choose structured shared data or a validated template reader. Test ordering and unknown ratings, preserving existing entry IDs, links and CLI refusals. Source: QC Tier 5, roadmap rating duplication.

---

<a id="enh-18"></a>

## ENH-18 — Evaluate an isolated subprocess alternative to the fixture interpreter

**Priority:** Medium · **Effort:** ~1 day
**Where:** [grade_eval.py](../skills/design-review/tests/grade_eval.py) · **Regression net:** `skills/design-review/tests/grade.bats`

### What it is

Compare the bounded expression interpreter with an isolated subprocess using controlled import stubs, explicit resource limits and a defined fixture execution boundary.

### Why it matters

A growing interpreter and scenario-shaped allowlists increase maintenance and semantic gaps.

### Notes for the work

A subprocess alone is not isolation. Preserve the prohibition on arbitrary filesystem or network effects, retain unsupported-input diagnostics, and measure against the same hand-checked fixtures before choosing an approach. This is an architecture decision, not permission to execute untrusted answers. Source: QC Tier 5, interpreter altitude.

---

<a id="enh-19"></a>

## ENH-19 — Declare scenario grading rules as scenario data

**Priority:** Medium · **Effort:** ~1 day
**Where:** [grade.py](../skills/design-review/tests/grade.py) · **Regression net:** `skills/design-review/tests/grade.bats`

### What it is

Move scenario-specific condition mappings and mechanical grading definitions into validated scenario data with a revision and hash policy.

### Why it matters

Python rules and scenario prose can diverge while a grader still appears bound to the right condition hash.

### Notes for the work

The S05 banned-word scan now reads its rule text; other mappings remain in Python. Design the data format and evidence expiry policy before migrating, preserve historical artifacts, and do not silently reinterpret existing hashes. Source: QC Tier 5, per-scenario rule altitude.

---

<a id="enh-20"></a>

## ENH-20 — Run mutation audits in a disposable checkout

**Priority:** Medium · **Effort:** ~1 day
**Where:** [mutation-restore.sh](../skills/phase-workflow/mutation-restore.sh) · **Regression net:** `skills/phase-workflow/tests/phase-git.bats`

### What it is

Apply mutations and run both test commands in an isolated disposable checkout of the named task commit.

### Why it matters

Isolation avoids exposing the main checkout to mutations and generated test output, reducing reliance on restoration after damage.

### Notes for the work

Define dependency and ignored-file availability, command working directories, cleanup and assertion-red reporting. Preserve current SHA validation and do not certify fixture or collection failures. Source: QC Tier 5, mutation audit altitude.

---

<a id="enh-21"></a>

## ENH-21 — Reconcile bundle and export scope exclusions

**Priority:** Medium · **Effort:** ~1 day
**Where:** [capture.sh](../skills/external-review/capture.sh) · **Regression net:** `skills/external-review/tests/capture.bats`

### What it is

Define one supported scope-exclusion contract for capture bundles and Codex exports, and check that both select the same in-scope paths.

### Why it matters

The same --exclude spelling currently drives Git pathspec filtering and literal path pruning, so a caller can assume agreement that is not checked.

### Notes for the work

Choose whether to restrict the shared vocabulary or implement matching semantics. Test directories, wildcard-looking names, case, symlinks, repeated exclusions and paths matching nothing; retain the distinction between scope control and read isolation. Source: QC Tier 5, exclusion altitude.

---

<a id="enh-22"></a>

## ENH-22 — Validate verbatim judgement evidence in grade.py

**Priority:** Medium · **Effort:** ~1 day
**Where:** [grade.py](../skills/design-review/tests/grade.py) · **Regression net:** `skills/design-review/tests/grade_batch.bats`

### What it is

Move the rule requiring judgement evidence to quote the answer verbatim from grade_batch.py into grade.py judgement validation, so human and model reviewers meet the same rule.

### Why it matters

The current entry points impose different evidence requirements on otherwise equivalent judgements.

### Notes for the work

Deferred by the user after Claude's grading-tool review. Define allowed multi-excerpt notation, preserve hash binding and explicit disputes, and test both direct judgements and batch collection before migrating the validator.

---

<a id="enh-23"></a>

## ENH-23 — Calibrate graders with blind hand-graded anchors

**Priority:** Medium · **Effort:** ~1 day
**Where:** [grade_batch.py](../skills/design-review/tests/grade_batch.py) · **Regression net:** `skills/design-review/tests/grade_batch.bats`

### What it is

Mix a few hand-graded answers into grading packets without marking them for graders, and report how often graders agree with the reference judgements.

### Why it matters

Agreement between model graders does not establish grader quality when both share a mistake.

### Notes for the work

Deferred by the user after Claude's grading-tool review. Retain reference provenance and rationale, control anchor exposure and revisions, and report condition-level denominators without using anchors as experimental answers.

---

<a id="enh-24"></a>

## ENH-24 — Report agreement with condition base rates and a fixed repeat fraction

**Priority:** Medium · **Effort:** ~1 day
**Where:** [grade_batch.py](../skills/design-review/tests/grade_batch.py) · **Regression net:** `skills/design-review/tests/grade_batch.bats`

### What it is

Exclude conditions decided by the harness from grader agreement, report each condition's pass/fail base rate, and repeat a prespecified fraction of answers instead of one per scenario and arm.

### Why it matters

A high raw agreement rate can reflect mechanical decisions or an overwhelmingly common verdict rather than consistent judgement.

### Notes for the work

Deferred by the user after Claude's grading-tool review. Specify repeat sampling and denominators before dispatch, distinguish disputed mechanical decisions, preserve per-grader results, and avoid changing an in-flight grading.json format.

---

<a id="enh-25"></a>

## ENH-25 — Measure how much answers reveal their experimental arm

**Priority:** Medium · **Effort:** ~1 day
**Where:** [grade_batch.py](../skills/design-review/tests/grade_batch.py) · **Regression net:** `skills/design-review/tests/grade_batch.bats`

### What it is

Measure arm leakage from answer content, for example by asking graders to guess the arm and reporting accuracy against the hidden assignment.

### Why it matters

Removing arm labels from a packet does not show that its wording conceals whether the skill was loaded.

### Notes for the work

Deferred by the user after Claude's grading-tool review. Decide when to elicit guesses so they do not prime grading, keep assignment keys separate, and report guesses with denominators and uncertainty rather than asserting that packets are blind.

---

<a id="enh-26"></a>

## ENH-26 — Test the conversion of a helper's evaluation gap into an opaque call

**Priority:** Medium · **Effort:** ~1 hour
**Where:** [grade_eval.py:158-162](../skills/design-review/tests/grade_eval.py#L158-L162) · **Regression net:** `skills/design-review/tests/grade.bats`

### What it is

Add a `grade.bats` case where an imported helper stops at an unsupported statement, and assert that bindings the call could change become unknown afterwards.

### Why it matters

Astra's F-02 added this conversion, but reverting the hunk leaves the suite green, so nothing protects it.

### Notes for the work

Found in Claude's adversarial review of the overnight passes, 2026-09-14. Write the test against HEAD, then confirm it fails for its named reason with the hunk reverted.

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

---

<a id="enh-10"></a>

## ENH-10 — make the project-env name mapping unambiguous

**Priority:** Low · **Effort:** ~2 hours
**Where:** [project-env/SKILL.md:18-21](../skills/project-env/SKILL.md#L18-L21)

### What it is

The env name is the project path relative to the code root with separators flattened to `_`.
That is not injective: `Code/a/b` and `Code/a_b` both become `a_b`, so two projects can name the
same environment.

### Why it matters

Low, because the collision needs a project whose directory name already contains an underscore
at the right position. When it happens, two projects silently share one `.venv`, and the symptom
is a dependency appearing from nowhere. The skill requires inspecting candidate projects for shared destinations before adopting an
existing env, and stopping if ownership remains uncertain. Nothing in the environment records
its owner, so that manual check does not replace an unambiguous naming scheme.

### Notes for the work

Append a short digest of the normalized path, or encode the separator. Either changes existing
env names, so it needs a migration path in `standardize-*-envs.sh` rather than a rename in the
docs.

**Source:** gpt-6-astra — phase review pass 5, 2026-09-08.

---

<a id="enh-11"></a>

## ENH-11 — reconcile an existing global markdownlint config instead of skipping it

**Priority:** Low · **Effort:** ~1 hour
**Where:** [claude-setup/SKILL.md](../skills/claude-setup/SKILL.md) step 3b

### What it is

Step 3b writes `~/.markdownlint.jsonc` only when the file is absent. A machine with an existing
config keeps it, so the four rules the step says "have to be set" are not set, and a re-run
reports success.

### Why it matters

Same class as the standards block: the skill is supposed to bring a stale machine up to the
current standard, and here it silently does not. The consequence is mild — lint findings that
disagree with the house style — but the pattern is the one this skill exists to avoid.

### Notes for the work

Merge the four required keys into an existing config, preserving unrelated rules, the same way
step 2 merges `settings.json`.

**Source:** gpt-6-astra — phase review pass 5, 2026-09-08.

---

<a id="enh-12"></a>

## ENH-12 — feed the Gemini prompt through stdin rather than argv

**Priority:** Low · **Effort:** ~1 hour
**Where:** [external-review/SKILL.md](../skills/external-review/SKILL.md) Gemini invocation

### What it is

The prompt is passed as `agy -p "$(cat …)"`, so the whole bundle travels as a command-line
argument and is bounded by `ARG_MAX` (~1 MB on macOS).

### Why it matters

Low today: the chunk ceiling is now ~120,000 characters for timeout reasons, well under the
limit. It becomes real if the ceiling is ever raised, and the failure mode is `argument list too
long` rather than anything that reads as a review problem.

### Notes for the work

Check whether `agy` accepts a prompt on stdin or from a file flag. If it does, use it; if not,
record that argv is the only channel and keep the chunk ceiling as the control.

**Source:** gemini-3.1-pro-high — phase review pass 5, 2026-09-08.
