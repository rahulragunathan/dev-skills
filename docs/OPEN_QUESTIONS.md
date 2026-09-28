# Open Questions

Things not yet settled, decisions first. [ROADMAP.md](ROADMAP.md) carries the one-line index;
this file carries the reasoning.

These are not work items. Each is a decision waiting to be made, a gap in what the tests
prove, or a risk knowingly carried. An entry that turns out to describe defined wrong
behavior with a known fix is a bug — move it to [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

Each entry has a stable ID. When one is settled it leaves this file: into the code plus a
CHANGELOG entry if it changed anything, into KNOWN_ISSUES or ENHANCEMENTS if it became work,
or into "Decisions taken and not taken" in [AGENTS.md](../AGENTS.md) if the answer was to do
nothing. IDs are never reused.

## Kind

| Kind | Means |
| ------ | ------- |
| **Decision** | The code does something defensible, but nobody has chosen whether it is right. Asks for an answer. |
| **Verification** | The behavior is probably correct and nothing proves it. Asks for a test, or a deliberate acceptance. |
| **Risk** | Known, understood, accepted for now. Asks for nothing until circumstances change. |

---

<a id="unk-04"></a>

## UNK-04 — does an undefined input-format check bound a shared cache's keys?

**Kind:** Decision

### The question

S02 Lifetime fails "an unbounded shared cache". The fixture's `taxonomy.category_for` cache is
keyed by SKU prefixes from merchant files. Some designs keep that cache unbounded and say the
prefix is format-checked first, without defining the format. A defined format, such as three
uppercase letters, bounds the keys; an undefined one does not show a bound.

### Why it matters

Graders split on this argument. The round-7 correction failed with-skill replicate 3 for it. In
round 9 the graders failed with-skill replicate 3 for it, but passed baseline replicate 2, whose
design differs mainly by naming a `normalise_prefix` function. S02 Lifetime tallies depend on
the answer.

### What would settle it

Choose one reading and write it into the S02 Lifetime condition: either a key bound must be
stated (a maxsize, a finite key set or a defined format), or a named normalisation step is
enough. The reworded condition changes the condition hash, so the affected rows would need
re-grading against it.

**Source:** claude-opus-5 — round-9 grading, 2026-09-14.

---

<a id="unk-03"></a>

## UNK-03 — verify the installed Claude Code permission behavior

**Kind:** Verification

### The question

The [current permission reference](https://code.claude.com/docs/en/permissions) documents
`Bash(cmd*)` as a broader wildcard and `Bash(cmd:*)` as equivalent to `Bash(cmd *)`.
Setup now follows that contract. The installed extension's actual prompt behavior has not
been verified in an isolated session.

### Why it matters

The docs must not treat a broader wildcard as inert. Runtime matching and extension reload
behavior can also differ by version, so documentation alone cannot establish this machine's
behavior.

### What would settle it

Write both forms into a scratch configuration, start an isolated session, and observe command
matching without changing the user's live configuration. Record the CLI and extension versions.

**Source:** gpt-6-astra — phase review pass 5, 2026-09-08; documentation checked during the
2026-09-10 adversarial review. Live permission-session verification remains open.
