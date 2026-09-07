# ROADMAP

<!-- Vocabulary: use "Done" (never "Implemented"). Status terms: Done | In Progress | Planned | Blocked. -->

**What's next.** This file holds only work that has not happened yet, at index level. It does
not describe what shipped or how the code works today.

| Looking for | Read |
| ------------- | ------ |
| Detail on an open bug | [KNOWN_ISSUES.md](KNOWN_ISSUES.md) |
| Detail on a candidate enhancement | [ENHANCEMENTS.md](ENHANCEMENTS.md) |
| Detail on an open question | [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) |
| What already shipped | [CHANGELOG.md](../CHANGELOG.md) |
| What each skill does | [README.md](../README.md) |
| How the pieces fit together | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Conventions for working in this repo | [CLAUDE.md](../CLAUDE.md) |

The tables below are **pointers, not summaries** — ID, title, rating, link. Nothing is
described twice.

An item's whole life is a move: it enters here and its supporting file together, and on
completion is deleted from both, with the record written into CHANGELOG `[Unreleased]`. An
item dropped rather than built moves to "Decisions taken and not taken". IDs are never
reused. Nothing here looks backward — completed phases are CHANGELOG releases.

**Last Updated**: 2026-09-07 (seeded from the external repo review of 2026-09-05)

## Status

The plugin ships seven skills and is in daily use on one machine. The five bash scripts under
`claude-toggle-backend` and `claude-setup` carry the whole open bug list: the process,
review and standards skills were repaired in the phase that created this file, and their
findings are in the CHANGELOG rather than here.

**`local-models` and `claude-toggle-backend` are being rebuilt from scratch**, so their
entries below are held rather than worked. They stay filed — the defects are real and the
rebuild has to clear them — but they are out of scope for the current phase and are excluded
from its external review bundles. KI-06, KI-07, KI-08 and KI-14 belong to `claude-setup` and
are not affected — they are phase 2.

The active queue is the `backup-projects.sh` cluster and the harness that would have caught
it. Everything else is held for the rebuild: eight of the 29 bats tests pass with the
behaviour they name removed, so ENH-02 and ENH-04 wait on new code rather than on patches to
tests that cannot fail.

### Phases

**Phase 1 — `design-review` skill and process remediation** — in progress. Four enhancements
landed in it. ENH-06 and ENH-01 gave the repo the `CLAUDE.md` and `ARCHITECTURE.md` it requires
of others and cut the standards block to 2,480 words, with its environment procedures moved
into the new `project-env` skill. ENH-08 and ENH-09 then split `claude-setup` three ways: the
Drive backup into a new `drive-backup` skill and the llama.cpp shell block into
`claude-toggle-backend`, leaving `claude-setup` at 5,395 words and writing nothing outside
`~/.claude` and the Drive root.

**Phase 2 — the backup cluster.** A bats harness for `backup-projects.sh` (ENH-03, in its
active half), now scoped to the `drive-backup` skill it moved into, then KI-14, KI-06, KI-08
and KI-07, each with its reproducing test written first. KI-14 leads: while every run reports success, the other three cannot be observed
failing.

## Known Issues

Most severe first. Severity definitions and full detail in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

| ID | Issue | Severity |
| ---- | ------- | ---------- |
| [KI-01](KNOWN_ISSUES.md#ki-01) | `settings.json` is truncated before it is rewritten | Critical |
| [KI-22](KNOWN_ISSUES.md#ki-22) | The marker strip can truncate `.zshrc` | Critical |
| [KI-02](KNOWN_ISSUES.md#ki-02) | A failed switch leaves the config pointing at a stopped server | High |
| [KI-03](KNOWN_ISSUES.md#ki-03) | A PID file is trusted without checking what the process is | High |
| [KI-04](KNOWN_ISSUES.md#ki-04) | The stray-process sweep kills servers this plugin did not start | High |
| [KI-05](KNOWN_ISSUES.md#ki-05) | The "one model resident" guarantee does not hold for direct starts | High |
| [KI-06](KNOWN_ISSUES.md#ki-06) | A stale lock silently disables every later backup | High |
| [KI-07](KNOWN_ISSUES.md#ki-07) | Credentials are copied to Drive with no scan or warning | High |
| [KI-08](KNOWN_ISSUES.md#ki-08) | Backup destination discovery picks the first Drive account it finds | High |
| [KI-09](KNOWN_ISSUES.md#ki-09) | `toggle.bats` "clears env" never asserts that the env was cleared | High |
| [KI-10](KNOWN_ISSUES.md#ki-10) | The MLX switch test does not pin the auth token | High |
| [KI-11](KNOWN_ISSUES.md#ki-11) | The MLX start test cannot detect a wrong server invocation | High |
| [KI-12](KNOWN_ISSUES.md#ki-12) | The stop test passes even if nothing is stopped | High |
| [KI-13](KNOWN_ISSUES.md#ki-13) | Test cleanup kills unrelated processes on the machine | High |
| [KI-14](KNOWN_ISSUES.md#ki-14) | Every backup failure is logged as `ok` and exits 0 | High |
| [KI-16](KNOWN_ISSUES.md#ki-16) | `HF_HOME` is exported by an orphaned `~/.zshrc` block no skill installs | Medium |
| [KI-17](KNOWN_ISSUES.md#ki-17) | The machine is documented as both 64 GB and 24 GB | Medium |
| [KI-18](KNOWN_ISSUES.md#ki-18) | `toggle.sh` needs `python3` and never checks for it | Medium |
| [KI-19](KNOWN_ISSUES.md#ki-19) | Port selection releases the socket before the server binds | Medium |
| [KI-20](KNOWN_ISSUES.md#ki-20) | LaunchAgent plist values are not XML-escaped | Medium |
| [KI-21](KNOWN_ISSUES.md#ki-21) | Uninstall says the server is left alone, then stops it | Medium |
| [KI-23](KNOWN_ISSUES.md#ki-23) | "detect llama-cpp by marker" passes without any marker handling | Medium |
| [KI-24](KNOWN_ISSUES.md#ki-24) | "status runs clean" asserts neither server's status line | Medium |
| [KI-25](KNOWN_ISSUES.md#ki-25) | "auto-picks a numeric free port" accepts any number | Medium |
| [KI-26](KNOWN_ISSUES.md#ki-26) | The foreground test asserts only the model file | Medium |
| [KI-27](KNOWN_ISSUES.md#ki-27) | Status tests depend on the host's real processes | Low |

## Enhancements

Highest priority first. Priority definitions and full detail in [ENHANCEMENTS.md](ENHANCEMENTS.md).

| ID | Enhancement | Priority | Effort |
| ---- | ------------- | ---------- | -------- |
| [ENH-02](ENHANCEMENTS.md#enh-02) | Cover the untested llama.cpp and toggle paths | High | ~1 day |
| [ENH-03](ENHANCEMENTS.md#enh-03) | Test the two destructive scripts that have no tests at all | High | ~1 day |
| [ENH-04](ENHANCEMENTS.md#enh-04) | Make the fakes assert a contract rather than only a shape | Medium | ~half a day |
| [ENH-05](ENHANCEMENTS.md#enh-05) | Fold the MLX plan and spec into the permanent docs | Medium | ~half a day |
| [ENH-07](ENHANCEMENTS.md#enh-07) | Honour `$CLAUDE_CONFIG_DIR` in the bundled scripts | Low | ~2 hours |

## Open Questions

Decisions first, then verification gaps, then accepted risks. Kind definitions and the
reasoning behind each in [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

| ID | Question | Kind |
| ---- | ---------- | ------ |
| [UNK-02](OPEN_QUESTIONS.md#unk-02) | No test in this repo can be shown to discriminate from git history alone | Risk |
