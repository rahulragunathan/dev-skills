# ROADMAP

<!-- Vocabulary: use "Done" (never "Implemented"). Status terms: Done | In Progress | Planned | Blocked. -->

**What's next.** This file holds only work that has not happened yet, at index level. It does
not describe what shipped or how the code works today.

| Looking for | Read |
| ------------- | ------ |
| Detail on an open bug | [KNOWN_ISSUES.md](KNOWN_ISSUES.md) |
| Detail on a candidate enhancement | [ENHANCEMENTS.md](ENHANCEMENTS.md) |
| Detail on an open question | [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) |
| The phase in flight, and how it will merge | [PHASE_RECORD.md](PHASE_RECORD.md) |
| What already shipped | [CHANGELOG.md](../CHANGELOG.md) |
| What each skill does | [README.md](../README.md) |
| How the pieces fit together | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Conventions for working in this repo | [AGENTS.md](../AGENTS.md) |

The tables below are **pointers, not summaries** — ID, title, rating, link. Nothing is
described twice.

An item's whole life is a move: it enters here and its supporting file together, and on
completion is deleted from both, with the record written into CHANGELOG `[Unreleased]`. An
item dropped rather than built moves to "Decisions taken and not taken". IDs are never
reused. Nothing here looks backward — completed phases are CHANGELOG releases.

**Last Updated**: 2026-09-21

## Status

The phase in flight, and how it will merge, is in [PHASE_RECORD.md](PHASE_RECORD.md). It is not
restated here.

The `local-models` and `claude-toggle-backend` rebuild work remains held; the supporting files'
Held sections define the boundaries. Work outside them remains active, including ENH-10 through
ENH-12. The backup cluster — the active half of ENH-03 and the `drive-backup` issues — is queued
behind the current process work.

## Known Issues

Most severe first, and within a severity the most likely first. Both scales and full detail in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

| ID | Issue | Likelihood | Severity |
| ---- | ------- | ---------- | ---------- |
| [KI-01](KNOWN_ISSUES.md#ki-01) | `settings.json` is truncated before it is rewritten | Rare | Critical |
| [KI-22](KNOWN_ISSUES.md#ki-22) | The marker strip can truncate `.zshrc` | Rare | Critical |
| [KI-07](KNOWN_ISSUES.md#ki-07) | Credentials are copied to Drive with no scan or warning | Almost always | High |
| [KI-09](KNOWN_ISSUES.md#ki-09) | `toggle.bats` "clears env" never asserts that the env was cleared | Almost always | High |
| [KI-10](KNOWN_ISSUES.md#ki-10) | The MLX switch test does not pin the auth token | Almost always | High |
| [KI-11](KNOWN_ISSUES.md#ki-11) | The MLX start test cannot detect a wrong server invocation | Almost always | High |
| [KI-12](KNOWN_ISSUES.md#ki-12) | The stop test passes even if nothing is stopped | Almost always | High |
| [KI-14](KNOWN_ISSUES.md#ki-14) | Every backup failure is logged as `ok` and exits 0 | Almost always | High |
| [KI-28](KNOWN_ISSUES.md#ki-28) | `drive-backup` uses `$CODE_ROOT` without defining it | Almost always | High |
| [KI-29](KNOWN_ISSUES.md#ki-29) | The "already set up" shortcut accepts a hook on the old path | Almost always | High |
| [KI-30](KNOWN_ISSUES.md#ki-30) | Two machines overwrite each other's config snapshot | Almost always | High |
| [KI-47](KNOWN_ISSUES.md#ki-47) | Grading packets omit information their conditions require | Almost always | High |
| [KI-48](KNOWN_ISSUES.md#ki-48) | S07's with-skill arm is handed the answer it is graded on | Almost always | High |
| [KI-02](KNOWN_ISSUES.md#ki-02) | A failed switch leaves the config pointing at a stopped server | Likely | High |
| [KI-05](KNOWN_ISSUES.md#ki-05) | The "one model resident" guarantee does not hold for direct starts | Likely | High |
| [KI-08](KNOWN_ISSUES.md#ki-08) | Backup destination discovery picks the first Drive account it finds | Likely | High |
| [KI-13](KNOWN_ISSUES.md#ki-13) | Test cleanup kills unrelated processes on the machine | Likely | High |
| [KI-33](KNOWN_ISSUES.md#ki-33) | Symlinked backup inputs are skipped without a failure status | Likely | High |
| [KI-03](KNOWN_ISSUES.md#ki-03) | A PID file is trusted without checking what the process is | Rare | High |
| [KI-04](KNOWN_ISSUES.md#ki-04) | The stray-process sweep kills servers this plugin did not start | Rare | High |
| [KI-06](KNOWN_ISSUES.md#ki-06) | A stale lock silently disables every later backup | Rare | High |
| [KI-37](KNOWN_ISSUES.md#ki-37) | A replaced evidence slot keeps its old grade | Rare | High |
| [KI-38](KNOWN_ISSUES.md#ki-38) | An assertion the test expects to fail still grades as did-not-hold | Rare | High |
| [KI-16](KNOWN_ISSUES.md#ki-16) | `HF_HOME` is exported by an orphaned `~/.zshrc` block no skill installs | Almost always | Medium |
| [KI-17](KNOWN_ISSUES.md#ki-17) | The machine is documented as both 64 GB and 24 GB | Almost always | Medium |
| [KI-21](KNOWN_ISSUES.md#ki-21) | Uninstall says the server is left alone, then stops it | Almost always | Medium |
| [KI-23](KNOWN_ISSUES.md#ki-23) | "detect llama-cpp by marker" passes without any marker handling | Almost always | Medium |
| [KI-24](KNOWN_ISSUES.md#ki-24) | "status runs clean" asserts neither server's status line | Almost always | Medium |
| [KI-25](KNOWN_ISSUES.md#ki-25) | "auto-picks a numeric free port" accepts any number | Almost always | Medium |
| [KI-26](KNOWN_ISSUES.md#ki-26) | The foreground test asserts only the model file | Almost always | Medium |
| [KI-49](KNOWN_ISSUES.md#ki-49) | The headline tally mixes two skills | Almost always | Medium |
| [KI-31](KNOWN_ISSUES.md#ki-31) | The lock drops the last backup of a session | Likely | Medium |
| [KI-18](KNOWN_ISSUES.md#ki-18) | `toggle.sh` needs `python3` and never checks for it | Likely | Medium |
| [KI-36](KNOWN_ISSUES.md#ki-36) | A grader quote of a table cell that holds a pipe is refused | Likely | Medium |
| [KI-39](KNOWN_ISSUES.md#ki-39) | `print` with an f-string argument still hides later guards | Likely | Medium |
| [KI-40](KNOWN_ISSUES.md#ki-40) | The roadmap check fails on freshly seeded roadmap files | Likely | Medium |
| [KI-55](KNOWN_ISSUES.md#ki-55) | The plan review cannot run while the plan is inside the repository | Likely | Medium |
| [KI-50](KNOWN_ISSUES.md#ki-50) | S05's fixture contradicts itself | Likely | Medium |
| [KI-51](KNOWN_ISSUES.md#ki-51) | Rejected grading attempts are not retained | Likely | Medium |
| [KI-32](KNOWN_ISSUES.md#ki-32) | Repository approval state is not in the file the backup collects | Rare | Medium |
| [KI-34](KNOWN_ISSUES.md#ki-34) | A destination inside a source tree nests backups recursively | Rare | Medium |
| [KI-19](KNOWN_ISSUES.md#ki-19) | Port selection releases the socket before the server binds | Rare | Medium |
| [KI-20](KNOWN_ISSUES.md#ki-20) | LaunchAgent plist values are not XML-escaped | Rare | Medium |
| [KI-41](KNOWN_ISSUES.md#ki-41) | Converting a large sequence to text has no size bound | Rare | Medium |
| [KI-42](KNOWN_ISSUES.md#ki-42) | One edited dispatch file stops `collect` for every packet | Rare | Medium |
| [KI-43](KNOWN_ISSUES.md#ki-43) | A ready reviewer probe reads as TIMEOUT when stderr mentions a timeout | Rare | Medium |
| [KI-27](KNOWN_ISSUES.md#ki-27) | Status tests depend on the host's real processes | Likely | Low |
| [KI-44](KNOWN_ISSUES.md#ki-44) | A stale dispatch log gives a misleading replacement message | Rare | Low |

## Enhancements

Highest priority first. Priority definitions and full detail in [ENHANCEMENTS.md](ENHANCEMENTS.md).

| ID | Enhancement | Priority | Effort |
| ---- | ------------- | ---------- | -------- |
| [ENH-02](ENHANCEMENTS.md#enh-02) | Cover the untested llama.cpp and toggle paths | High | ~1 day |
| [ENH-03](ENHANCEMENTS.md#enh-03) | Test the two destructive scripts that have no tests at all | High | ~1 day |
| [ENH-04](ENHANCEMENTS.md#enh-04) | Make the fakes assert a contract rather than only a shape | Medium | ~half a day |
| [ENH-05](ENHANCEMENTS.md#enh-05) | Fold the MLX plan and spec into the permanent docs | Medium | ~half a day |
| [ENH-14](ENHANCEMENTS.md#enh-14) | Share recorded-answer validation between evidence and grading | Medium | ~1 day |
| [ENH-15](ENHANCEMENTS.md#enh-15) | Probe independent reviewers concurrently | Medium | ~1 day |
| [ENH-16](ENHANCEMENTS.md#enh-16) | Emit shared answer evidence once in grading JSON | Medium | ~1 day |
| [ENH-17](ENHANCEMENTS.md#enh-17) | Give roadmap rating scales one source | Medium | ~1 day |
| [ENH-18](ENHANCEMENTS.md#enh-18) | Evaluate an isolated subprocess alternative to the fixture interpreter | Medium | ~1 day |
| [ENH-19](ENHANCEMENTS.md#enh-19) | Declare scenario grading rules as scenario data | Medium | ~1 day |
| [ENH-20](ENHANCEMENTS.md#enh-20) | Run mutation audits in a disposable checkout | Medium | ~1 day |
| [ENH-21](ENHANCEMENTS.md#enh-21) | Reconcile bundle and export scope exclusions | Medium | ~1 day |
| [ENH-22](ENHANCEMENTS.md#enh-22) | Validate verbatim judgement evidence in grade.py | Medium | ~1 day |
| [ENH-23](ENHANCEMENTS.md#enh-23) | Calibrate graders with blind hand-graded anchors | Medium | ~1 day |
| [ENH-24](ENHANCEMENTS.md#enh-24) | Report agreement with condition base rates and a fixed repeat fraction | Medium | ~1 day |
| [ENH-25](ENHANCEMENTS.md#enh-25) | Measure how much answers reveal their experimental arm | Medium | ~1 day |
| [ENH-26](ENHANCEMENTS.md#enh-26) | Test the conversion of a helper's evaluation gap into an opaque call | Medium | ~1 hour |
| [ENH-27](ENHANCEMENTS.md#enh-27) | Lint the markdown templates that live inside fences | Medium | ~1 hour |
| [ENH-28](ENHANCEMENTS.md#enh-28) | Let `publish-release.sh` verify remote presence itself | Medium | ~2 hours |
| [ENH-10](ENHANCEMENTS.md#enh-10) | Make the project-env name mapping unambiguous | Low | ~2 hours |
| [ENH-11](ENHANCEMENTS.md#enh-11) | Reconcile an existing global markdownlint config | Low | ~1 hour |
| [ENH-12](ENHANCEMENTS.md#enh-12) | Feed the Gemini prompt through stdin rather than argv | Low | ~1 hour |
| [ENH-07](ENHANCEMENTS.md#enh-07) | Honour `$CLAUDE_CONFIG_DIR` in the bundled scripts | Low | ~2 hours |
| [ENH-29](ENHANCEMENTS.md#enh-29) | Evaluate every gone branch before reporting | Low | ~1 hour |
| [ENH-31](ENHANCEMENTS.md#enh-31) | Report an entry that omits its `**Where:**` field entirely | Low | ~1 hour |

## Open Questions

Decisions first, then verification gaps, then accepted risks. Kind definitions and the
reasoning behind each in [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

| ID | Question | Kind |
| ---- | ---------- | ------ |
| [UNK-04](OPEN_QUESTIONS.md#unk-04) | Does an undefined input-format check bound a shared cache's keys? | Decision |
| [UNK-03](OPEN_QUESTIONS.md#unk-03) | Verify installed Claude Code permission behavior | Verification |
