# Phase record

**The phase in flight, and nothing else.** Written at `phase-workflow` §2 step 3, preserved across
sessions, and read back at §4 for `MERGE_METHOD`. Later checks do not replace it: it pins what was
decided at phase start so a repository setting changed mid-phase cannot silently alter the merge.

This file is **overwritten** at each phase start, never appended. Accumulated records would be the
phase ledger the roadmap rules forbid — the release history is the phase history. When no phase is
in flight the body is the single line `No phase in flight.`

---

No phase in flight.
