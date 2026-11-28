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
| How the code works now | [README.md](../README.md), [ARCHITECTURE.md](ARCHITECTURE.md), [AGENTS.md](../AGENTS.md) |
| Ideas considered and dropped | "Decisions taken and not taken" in [AGENTS.md](../AGENTS.md) |

The tables below are **pointers, not summaries** — ID, title, rating, link. Nothing is
described twice.

An item's whole life is a move: it enters here and its supporting file together, and on
completion is deleted from both, with the record written into the CHANGELOG release being
prepared, or `[Unreleased]` where none is. An
item dropped rather than built moves to "Decisions taken and not taken". IDs are never
reused. Nothing here looks backward — completed phases are CHANGELOG releases.

**Last Updated**: `<YYYY-MM-DD>` (`<what changed>`)

## Status

<!-- Two or three sentences: where the project stands, and what the active queue is. The
phase in flight is in docs/PHASE_RECORD.md and is not named here. -->

## Known Issues

Most severe first, and within a severity the most likely first. Both scales and full detail in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

| ID | Issue | Likelihood | Severity |
| ---- | ------- | ---------- | ---------- |
| [KI-01](KNOWN_ISSUES.md#ki-01) | `<title>` | Almost Always / Likely / Rare | Critical / High / Medium / Low |

## Enhancements

Highest priority first. Priority definitions and full detail in [ENHANCEMENTS.md](ENHANCEMENTS.md).

| ID | Enhancement | Priority | Effort |
| ---- | ------------- | ---------- | -------- |
| [ENH-01](ENHANCEMENTS.md#enh-01) | `<title>` | High / Medium / Low | ~hours / ~days |

## Open Questions

Decisions first, then verification gaps, then accepted risks. Kind definitions and the
reasoning behind each in [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

| ID | Question | Kind |
| ---- | ---------- | ------ |
| [UNK-01](OPEN_QUESTIONS.md#unk-01) | <the question, as a question> | Decision / Verification / Risk |
