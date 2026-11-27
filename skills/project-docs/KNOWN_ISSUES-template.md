# Known Issues

Open defects, most severe first. [ROADMAP.md](ROADMAP.md) carries the one-line index; this
file carries enough detail to pick an item up without digging.

Each entry has a stable ID — use it in branch names (`bugfix/ki-02-<slug>`) and in the
CHANGELOG entry that closes it. How an entry enters and closes is in [ROADMAP.md](ROADMAP.md).

`roadmap.py check` reads these levels, Severity, Likelihood, Path and Area below, in row order,
from the template bundled with `project-docs`. In a project's own copy the tables are for
reading: editing them changes nothing. Severity and Likelihood are required, and ROADMAP mirrors
them. Path and Area are optional for now; check validates them when present, and ROADMAP does not
mirror them.

**Steps To Reproduce** say how to make the defect happen, from a clean start. **Example
Scenario** says why it matters, in the project's own terms.

## Severity

| Level | Means |
| ------- | ------- |
| **Critical** | Loses or corrupts data, or sends wrong information to real recipients. |
| **High** | Silently produces a wrong result, or reports success without doing the work. |
| **Medium** | Wrong under conditions the operator can notice or work around. |
| **Low** | Cosmetic, or wrong in a field nothing consumes. |

**Severity is the consequence if it fires, and nothing about how often.**

## Likelihood

| Level | Means |
| ------- | ------- |
| **Almost Always** | Anyone following the documented workflow hits it. |
| **Likely** | Hit whenever a common condition holds — a second machine, an overlapping run, a particular option. |
| **Rare** | Needs an unusual trigger, or only bites in combination with another failure. |

**Judge the harm, not the code path.** A wrong value computed on every run is `Rare` when it only
misleads after something else has already failed, and **a defect that is always present but
harmful only in combination is `Rare`**. Conversely, if a documented step is what triggers it,
that is `Almost Always` for everyone who follows the step, however unusual it looks from outside.

**Rate both, because one number cannot carry both.** `Rare · Critical` and `Almost Always · Low`
are opposite kinds of work — the first is a landmine, the second is friction — and a single
rating hides which you are looking at. Both still get fixed.

## Path

| Level | Means |
| ------- | ------- |
| **Happy Path** | The documented workflow, run normally, with ordinary inputs. |
| **Unusual Input** | Odd but legal data: strange names, exotic formats, a rarely used option. |
| **External Interference** | Another process or user writing the same files, a crash or kill mid-run, a hostile local writer, a filesystem quirk. |

## Area

| Level | Means |
| ------- | ------- |
| **Code** | The defect is in code that runs. |
| **Docs** | The defect is in prose: a skill, a README, a comment. |
| **Tests** | The defect is in a test or its fixture. |

**Path is what kind of use reaches the defect; Area is what kind of file holds it.** A README step
that breaks the workflow is `Docs` on the `Happy Path`.

---

<a id="ki-01"></a>

## KI-01 — `<title>`

**Severity:** <Critical | High | Medium | Low>
**Likelihood:** <Almost Always | Likely | Rare>
**Path:** <Happy Path | Unusual Input | External Interference>
**Area:** <Code | Docs | Tests>
**Where:** [file.py](../file.py) — `def the_function_that_is_wrong(`

### What Happens

<the defect, with a real code excerpt — copied from the file, not paraphrased>

### Steps To Reproduce

1. <from a clean checkout or a fresh fixture: the action, with its input>
2. <the next action, if any>
3. <what you see, against what you should see>

### Example Scenario

<concrete inputs → the wrong outcome, in the project's own domain terms>

### Notes For A Fix

<approach, plus the constraints that would trip someone up: invariants to preserve, tests
that cover the area, related IDs worth bundling into the same pass>
