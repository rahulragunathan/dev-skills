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

**Last Updated**: 2026-11-22

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
| [KI-47](KNOWN_ISSUES.md#ki-47) | Grading packets omit information their conditions require | Almost always | High |
| [KI-48](KNOWN_ISSUES.md#ki-48) | S07's with-skill arm is handed the answer to the condition it is graded on | Almost always | High |
| [KI-60](KNOWN_ISSUES.md#ki-60) | Helper commands need `CLAUDE_PLUGIN_ROOT`, which a Codex install does not set | Almost always | High |
| [KI-37](KNOWN_ISSUES.md#ki-37) | A replaced evidence slot keeps its old grade | Rare | High |
| [KI-38](KNOWN_ISSUES.md#ki-38) | An assertion the test expects to fail still grades as did-not-hold | Rare | High |
| [KI-49](KNOWN_ISSUES.md#ki-49) | The headline tally mixes two skills | Almost always | Medium |
| [KI-50](KNOWN_ISSUES.md#ki-50) | S05's fixture contradicts itself | Almost always | Medium |
| [KI-36](KNOWN_ISSUES.md#ki-36) | A grader quote of a table cell that holds a pipe is refused | Likely | Medium |
| [KI-39](KNOWN_ISSUES.md#ki-39) | `print` with an f-string argument still hides later guards | Likely | Medium |
| [KI-51](KNOWN_ISSUES.md#ki-51) | Rejected grading attempts are not retained | Likely | Medium |
| [KI-41](KNOWN_ISSUES.md#ki-41) | Converting a large sequence to text has no size bound | Rare | Medium |
| [KI-44](KNOWN_ISSUES.md#ki-44) | A stale dispatch log gives a misleading replacement message | Rare | Low |

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
| [ENH-32](ENHANCEMENTS.md#enh-32) | Drop explanations of standard tool behaviour from the skills | Low | ~2 hours |

## Open Questions

Decisions first, then verification gaps, then accepted risks. Kind definitions and the
reasoning behind each in [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

| ID | Question | Kind |
| ---- | ---------- | ------ |
| [UNK-04](OPEN_QUESTIONS.md#unk-04) | Does an undefined input-format check bound a shared cache's keys? | Decision |
| [UNK-05](OPEN_QUESTIONS.md#unk-05) | What drives repeat review findings? | Verification |
