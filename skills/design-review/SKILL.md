---
name: design-review
description: Structural design pass for plan time and phase end. Produces the module table, the expected-change and shared-state lines, and verdicts on six named checks covering SOLID, DRY, KISS and separation of concerns, with a YAGNI cap graded by cost. Optionally drives the drawio skill. Use at phase-workflow §1 and §3 step 2, or on any architectural change.
license: MIT
---

# design-review

Two modes. `plan` produces the structure section a plan carries. `phase` re-checks that
structure against the code as it now stands.

**This runs after brainstorming has settled what the thing does, never instead of it.** If you
cannot state the system's job in a sentence, you are not ready to draw boxes. Where a flow
diagram is in scope, it comes before the structure diagrams: flow informs structure, not the
reverse.

**Not every rule here is proven.** Some change what an agent produces; most record that a strong
model already did the right thing unaided. [`tests/README.md`](tests/README.md) says which.

## Mode: `plan`

Input: the design brainstorming settled, and the repo. Output goes into the **File Structure**
slot `superpowers:writing-plans` already reserves — this fills that section, it does not add one.

Produce, in order:

1. The module table.
2. The **Expected change** line.
3. The **Shared state** line.
4. Whatever checks fired, and nothing about the ones that did not.
5. Whatever diagrams pass the distinctness test below — there is no count.

Runs **before** `review-checkpoint plan`, so the table travels to the reviewers at no extra
cost. A bounded change gets one sentence in chat instead of all this. A spike gets nothing.

## Mode: `phase`

Input: the plan's approved structure section, plus the working tree. Runs at `phase-workflow`
§3 step 2, **before** `/simplify` — structure decisions change what the later passes read.

Answer three questions in writing:

1. Which file picked up a second responsibility this phase?
2. Which change required edits in more than two files that should not have needed them?
3. Is anything depending on something more concrete than it needs?

Then regenerate each diagram and compare against the generator committed at §2. Findings you do
not fix become `ENH-nn` entries.

## The module table

Cover only units this phase creates or changes. **Order rows most-stable-first** — slowest to
change at the top; whatever changes because something outside the system moved (a schema, a
vendor API, a file format) at the bottom. That ordering is what gives Direction something to
check.

```markdown
| Unit | Responsibility | Interface | Depends on |
|---|---|---|---|
| parser.py | Tokenize feed rows | parse(bytes) -> Row[] | — |
| store.py  | Persist rows       | put(Row[]) -> None  | db |

**Expected change:** new feed formats. Adding one should mean editing `parser.py` and nothing else.
**Shared state:** none.
```

- **Responsibility** is one clause.
- **Interface** is the real signature, not a description. This is the same content
  `writing-plans` wants in each task's `Interfaces: Consumes / Produces` block, written once at
  the top instead of scattered.
- **Depends on** names other units in the table, an external dependency (`db`, `s3`, an HTTP
  API), or `—`. The units *in* the table must form an acyclic graph. Two limits, stated rather
  than assumed: an external dependency is a leaf and never closes a cycle, and an **unchanged**
  internal module has no row, so a cycle running through one is invisible here — name it in the
  cell anyway when a changed unit depends on it.
- **Expected change** is written as a test, so it can be checked later: *"adding a format should
  mean editing `parser.py` and nothing else."*
- **Shared state** is `none`, or what is shared and across which boundary.

## The six checks

| Check | Question | Fires when |
| ------- | ---------- | ------------ |
| Responsibility | Does any unit have more than one reason to change? | You can name two unrelated future changes that would each require editing it. A cell needing "and" is a hint, not the test — commas and umbrella nouns hide the same thing |
| Direction | Do dependencies point one way? | Depends-on has a cycle, or a unit depends on a row **below** it — on something with more reasons to change than itself |
| Duplication | Is anything appearing a third time? | See the threshold below |
| Variation | What's likely to change, and is there a place to change it? | A named likely change with nowhere to plug the alternative in, **or** a plug-in point that only ever holds one thing |
| Lifetime | Does any state outlive one call? | Module- or class-level objects, singletons, caches, connection pools, queues, open files, closures holding mutable data, or anything registered globally — reused across calls, requests, threads or processes |
| Surface | Can a consumer use this without reading its internals? | The interface leaks internals, or forces the caller to arrange something the signature does not mention |

Liskov has no row: Surface and Variation cover its practical cases. It applies wherever one
implementation stands in for another, **including protocols and duck typing**, not only
inheritance.

**Lifetime keeps its origin, because the abstract rule reads as obvious and the concrete case
does not:** a shared HTML sanitizer returned one request's body to another under threaded
workers, written by an agent that believed it was correct and found four review rounds later.

### Direction — order by stability, not by call order

**If the ordering comes from the dependency column, the check is circular** and collapses into
cycle detection: any acyclic graph can be ordered so every arrow points the same way, including
one where policy reaches into a database driver. So the ordering has to come from what each
unit *is*.

Order by **what makes it change, and how often**. Take a nightly invoice job:

| Unit | What makes it change |
| ------ | ---------------------- |
| `billing.py` | tax rules change |
| `run_nightly.py` | the job's steps change |
| `db.py` | the Postgres schema changes |
| `mailer.py` | the email vendor's API changes |

That is the row order, and none of it was read off the Depends-on column. Now suppose
`billing.py` reaches into Postgres for a tax rate. Under call-order ordering, `billing` and `db`
are both leaves under `run_nightly` — no cycle, nothing fires. Under this ordering it is row 1
depending on row 3, and what fires is concrete: the tax rules can no longer be tested or reused
without a live database, and a schema migration is now an edit to tax logic.

**"Stable" is not "important".** A generic connection-pool wrapper is more stable than a
feature-specific report module, so it sits above it — and a report type appearing in the
wrapper's Depends-on cell is the downward arrow the check is for.

### Duplication — the threshold, stated precisely

**Three occurrences justify *creating* a shared home. Two may move into a home that already
exists for another reason.**

The second half matters and the naive rule gets it wrong. If a shared module has to exist
anyway for something genuinely used three times, moving a two-way duplicate into it costs no new
file and no new indirection — and leaving two identical copies sitting beside it is worse. What
the rule forbids is *conjuring* an abstraction to serve two callers.

**When the existing home is a poor fit, leave the copies.** The tempting third option is a new
small module of its own, on the argument that folding the duplicate into the nearest existing
module would give that module a second reason to change. That argument is sound and its
conclusion is still wrong: a new file for two callers is conjuring, whatever prompted it. Two
copies of a four-line function cost less than a module, an import in every caller, and a name
everyone has to learn. Take the copies, note the decision, and let the third occurrence create
the home.

### Variation — grade the cap by cost

**YAGNI outranks SOLID**, but "no abstraction without a second implementation" is too blunt,
because abstractions do not cost the same.

- **Cheap, and defensible with one implementation:** a `Protocol` or type alias that names a
  shape. It documents the seam and forces the first implementation not to leak format-specific
  or transport-specific detail sideways. Fifteen lines, no runtime machinery.
- **Expensive, and needs a second implementation that exists or is scheduled:** an ABC with
  template methods, per-variant subpackages, entry-point discovery, config-driven registration,
  content sniffing, a factory, a plugin loader.

**The argument that wins is "cheap now, expensive later."** Answer it directly: the thing that
made past migrations expensive is rarely the missing interface, it is assumptions leaking
sideways — the CSV column names that ended up in the SQL, the S3 key parsing inside the parser.
Enforce the seam, which holds with one implementation. Decline the machinery.

## The four report rules

1. **Only what fired gets a line.** A check with nothing to say is silent — not summarized, not
   listed, not named. Naming the silent ones collectively ("Responsibility, Direction, Lifetime
   and Surface are all fine") is the same padding compressed into one sentence.
2. **A fired check states its resolution, not the observation.** *"store.py also formatted dates
   → moved to parser"*, never *"SRP: worth watching."*
3. **A check that fires and is deliberately not acted on still gets its line, with the reason.**
   That is where the duplication-at-two decision is recorded so the next phase does not
   re-litigate it.
4. **Never write `PASS`, `N/A`, `OK`, "no issue", "nothing to flag", or "clean".** Those are the
   words that appear when nothing was examined.

**When nothing fires at all**, the artifact is the table plus one line: *"No check fired."* That
is a statement about the run, not a verdict per check, so it does not conflict with rules 1
and 4. It is the **only** permitted summary, and only when nothing fired.

## Diagrams

Architectural work only. Bounded changes get the one-sentence note; spikes get nothing.

**Each diagram earns its place by showing something no other diagram shows.** There is no
number to hit. The test:

> Name something in this diagram that is not in any of the others. A system diagram that is the
> module map with a boundary box round it is not a second diagram. Three module maps for three
> genuinely separate subsystems are three diagrams.

**The cost is recurring, not upfront.** Drawing one is cheap. Every phase end after that
regenerates it, diffs it against its committed generator, and drift-checks the identifiers it
names (`phase-workflow` §3 step 4). A diagram nobody reads still has to be maintained, and a
stale one is worse than none. That is the real constraint, and it is a better one than a count:
draw what answers a question someone will ask, and retire it when it stops answering one.

| Level | When | Files |
| ------- | ------ | ------- |
| System | More than one deployable, or a real external boundary | `docs/build_system.py` → `docs/system.{drawio,png}` |
| Modules | Structure changes inside a deployable | `docs/build_architecture.py` → `docs/architecture.{drawio,png}` |
| Flow | A pipeline, request path, or ordering changes | `docs/build_<topic>_flow.py` → `docs/<topic>-flow.{drawio,png}` |

**Produce versus edit.** All of the above governs diagrams the plan *produces*. Correcting an
existing diagram that this phase made factually wrong is drift repair and is always in scope,
however many it touches. A single new edge on an already-documented diagram is an edit, not a
new diagram — and the edit is bounded: if its diff shows more than that edge and whatever
waypoint nudge it needs, it went too far.

A plan carrying diagrams at three abstraction levels usually holds more than one phase of
design. Worth noticing; not a rule.

**Two homes, because §1 runs before the branch does.** §1 builds and renders into the scratchpad
and the plan links that PNG; the plan's front matter records the generator filenames it
produced. §2 moves each generator into `docs/` as task one, and that committed generator is the
baseline `phase` mode compares against.

**Four things that are easy to get wrong:**

- **Never mark a box "new".** A new-in-this-phase marker is a diff, and it goes stale the moment
  the phase lands — leaving a diagram that quietly describes the wrong phase. The plan text
  already says what is new. *(Found by the s06 baseline run, which volunteered it unprompted.)*
- **The reviewers never see the diagram.** `agy -p` is text-only and told not to use tools, and
  a scratchpad PNG is not in the repo for Codex either. The table travels; the diagram does not.
- **Drift-check the generator, not the PNG.** Box and edge labels are string literals naming
  modules and files, so they drop into the existing identifier check. A PNG is opaque to it.
- **Catch a stale render mechanically:** regenerate, then `git status`. If the PNG changes, it
  was already out of date with its own source.
- **One render, not two.** The `drawio` skill is explicit: emit one colour per thing and do not
  hand-author a dark variant, because draw.io inverts for its own dark theme. `render_png.py
  --theme` exists if a specific doc needs both.

**No `drawio` on the machine** means: write the table, skip the diagram, record "no diagram" in
the plan's front matter, and say so in writing. Best-effort tool, non-negotiable step.

## Evidence

Every rule here has been run against a fresh Opus subagent with the skill loaded and without it.
Results, and which rules a strong model already follows unaided, are in
[`tests/README.md`](tests/README.md). **Do not present an unproven rule as a tested one** — that
file says which is which.

Two rules here were written *by* those runs rather than confirmed by them: the produce-versus-edit
distinction, and never marking a diagram box "new".
