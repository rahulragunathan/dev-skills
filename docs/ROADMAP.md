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
completion is deleted from both, with the record written into the CHANGELOG release being
prepared. An
item dropped rather than built moves to "Decisions taken and not taken". IDs are never
reused. Nothing here looks backward — completed phases are CHANGELOG releases.

**Last Updated**: 2026-11-26

## Status

The phase in flight, and how it will merge, is in [PHASE_RECORD.md](PHASE_RECORD.md). It is not
restated here.

A new programme is under way: the skills here are being redesigned to work in any repo and under
Codex as well as Claude Code. Most open items below close with that redesign rather than being
fixed one by one.

## Known Issues

Most severe first, and within a severity the most likely first. Both scales and full detail in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

| ID | Issue | Likelihood | Severity |
| ---- | ------- | ---------- | ---------- |
| [KI-80](KNOWN_ISSUES.md#ki-80) | First push and prune act on a branch name that can move after the check | Rare | Critical |
| [KI-47](KNOWN_ISSUES.md#ki-47) | Grading packets omit information their conditions require | Almost Always | High |
| [KI-48](KNOWN_ISSUES.md#ki-48) | S07's with-skill arm is handed the answer to the condition it is graded on | Almost Always | High |
| [KI-60](KNOWN_ISSUES.md#ki-60) | Helper commands need `CLAUDE_PLUGIN_ROOT`, which a Codex install does not set | Almost Always | High |
| [KI-37](KNOWN_ISSUES.md#ki-37) | A replaced evidence slot keeps its old grade | Rare | High |
| [KI-38](KNOWN_ISSUES.md#ki-38) | An assertion the test expects to fail still grades as did-not-hold | Rare | High |
| [KI-77](KNOWN_ISSUES.md#ki-77) | A root lockfile covers every manifest below it | Rare | High |
| [KI-84](KNOWN_ISSUES.md#ki-84) | A dependency file whose name differs only in case can overwrite another | Rare | High |
| [KI-87](KNOWN_ISSUES.md#ki-87) | The dependency scan still misreads some manifests | Rare | High |
| [KI-49](KNOWN_ISSUES.md#ki-49) | The headline tally mixes two skills | Almost Always | Medium |
| [KI-50](KNOWN_ISSUES.md#ki-50) | S05's fixture contradicts itself | Almost Always | Medium |
| [KI-51](KNOWN_ISSUES.md#ki-51) | Rejected grading attempts are not retained | Likely | Medium |
| [KI-36](KNOWN_ISSUES.md#ki-36) | A grader quote of a table cell that holds a pipe is refused | Likely | Medium |
| [KI-39](KNOWN_ISSUES.md#ki-39) | `print` with an f-string argument still hides later guards | Likely | Medium |
| [KI-41](KNOWN_ISSUES.md#ki-41) | Converting a large sequence to text has no size bound | Rare | Medium |
| [KI-76](KNOWN_ISSUES.md#ki-76) | The probe's error classes still match loose substrings | Rare | Medium |
| [KI-79](KNOWN_ISSUES.md#ki-79) | A symlinked folder above the docs folder still redirects the roadmap tools | Rare | Medium |
| [KI-81](KNOWN_ISSUES.md#ki-81) | The osv-scanner configuration is read by pattern, not as TOML | Rare | Medium |
| [KI-88](KNOWN_ISSUES.md#ki-88) | Check's table and metadata rules still differ from Markdown in places | Rare | Medium |
| [KI-90](KNOWN_ISSUES.md#ki-90) | The origin check strips a fetch URL's trailing newline | Rare | Medium |
| [KI-92](KNOWN_ISSUES.md#ki-92) | Requirements reading still differs from pip in markers, extras, encodings and hash lists | Rare | Medium |
| [KI-93](KNOWN_ISSUES.md#ki-93) | One unreadable part of a scanner answer still hides readable advisories | Rare | Medium |
| [KI-94](KNOWN_ISSUES.md#ki-94) | Report lines that start with a committed path can pass for findings | Rare | Medium |
| [KI-95](KNOWN_ISSUES.md#ki-95) | Publish-record still reads a short hex answer as a moved head | Rare | Medium |
| [KI-109](KNOWN_ISSUES.md#ki-109) | The optional-field reader still differs from Markdown in three ways | Rare | Medium |
| [KI-82](KNOWN_ISSUES.md#ki-82) | The zsh lint misses traps hidden by quotes and other subscripts | Likely | Low |
| [KI-44](KNOWN_ISSUES.md#ki-44) | A stale dispatch log gives a misleading replacement message | Rare | Low |
| [KI-78](KNOWN_ISSUES.md#ki-78) | Index rows are not bound to their section | Rare | Low |
| [KI-83](KNOWN_ISSUES.md#ki-83) | The name check misses multi-line reference definitions and counts test fixtures as scripts | Rare | Low |
| [KI-85](KNOWN_ISSUES.md#ki-85) | The release test reads only plain X.Y.Z headings | Rare | Low |
| [KI-89](KNOWN_ISSUES.md#ki-89) | Progress calls a finished Gemini attempt running when its answer could not be moved | Rare | Low |
| [KI-96](KNOWN_ISSUES.md#ki-96) | The Gemini prompt measurement can still accept a count it should refuse | Rare | Low |
| [KI-91](KNOWN_ISSUES.md#ki-91) | Init and close can lose their caller's signal handler while registering their own | Rare | Low |
| [KI-102](KNOWN_ISSUES.md#ki-102) | An empty Likelihood reads the Path line below it as its value | Rare | Low |

## Enhancements

Highest priority first. Priority definitions and full detail in [ENHANCEMENTS.md](ENHANCEMENTS.md).

| ID | Enhancement | Priority | Effort |
| ---- | ------------- | ---------- | -------- |
| [ENH-14](ENHANCEMENTS.md#enh-14) | Share recorded-answer validation between evidence and grading | Medium | ~1 day |
| [ENH-16](ENHANCEMENTS.md#enh-16) | Emit shared answer evidence once in grading JSON | Medium | ~1 day |
| [ENH-18](ENHANCEMENTS.md#enh-18) | Evaluate an isolated subprocess alternative to the fixture interpreter | Medium | ~1 day |
| [ENH-20](ENHANCEMENTS.md#enh-20) | Run mutation audits in a disposable checkout | Medium | ~1 day |
| [ENH-21](ENHANCEMENTS.md#enh-21) | Reconcile bundle and export scope exclusions | Medium | ~1 day |
| [ENH-22](ENHANCEMENTS.md#enh-22) | Validate verbatim judgement evidence in grade.py | Medium | ~1 day |
| [ENH-23](ENHANCEMENTS.md#enh-23) | Calibrate graders with blind hand-graded anchors | Medium | ~1 day |
| [ENH-26](ENHANCEMENTS.md#enh-26) | Test the conversion of a helper's evaluation gap into an opaque call | Medium | ~1 hour |
| [ENH-28](ENHANCEMENTS.md#enh-28) | Let `publish-release.sh` verify remote presence itself | Medium | ~2 hours |
| [ENH-38](ENHANCEMENTS.md#enh-38) | Name security in design-review's plan-time checks | Medium | ~2 hours |
| [ENH-40](ENHANCEMENTS.md#enh-40) | Make Path required in the roadmap check | Medium | ~2 hours |
| [ENH-41](ENHANCEMENTS.md#enh-41) | Make the triage wording tests pin the whole policy | Medium | ~2 hours |
| [ENH-32](ENHANCEMENTS.md#enh-32) | Drop explanations of standard tool behaviour from the skills | Low | ~2 hours |
| [ENH-39](ENHANCEMENTS.md#enh-39) | Make the tests pass 3 found weak fail for their named reason | Low | ~2 hours |

## Open Questions

Decisions first, then verification gaps, then accepted risks. Kind definitions and the
reasoning behind each in [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

| ID | Question | Kind |
| ---- | ---------- | ------ |
| [UNK-04](OPEN_QUESTIONS.md#unk-04) | Does an undefined input-format check bound a shared cache's keys? | Decision |
| [UNK-05](OPEN_QUESTIONS.md#unk-05) | What drives repeat review findings? | Verification |
