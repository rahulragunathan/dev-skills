# Known Issues

Open defects, most severe first. [ROADMAP.md](ROADMAP.md) carries the one-line index; this
file carries enough detail to pick an item up without digging.

Each entry has a stable ID — use it in branch names (`bugfix/ki-02-<slug>`) and in the
CHANGELOG entry that closes it. When fixed, delete it from here and from the ROADMAP index;
the record lives in [CHANGELOG.md](../CHANGELOG.md). IDs are never reused.

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
| **Almost always** | Anyone following the documented workflow hits it. |
| **Likely** | Hit whenever a common condition holds — a second machine, an overlapping run, a particular option. |
| **Rare** | Needs an unusual trigger, or only bites in combination with another failure. |

**Judge the harm, not the code path.** A wrong value computed on every run is `Rare` when it only
misleads after something else has already failed, and **a defect that is always present but
harmful only in combination is `Rare`**. Conversely, if a documented step is what triggers it,
that is `Almost always` for everyone who follows the step, however unusual it looks from outside.

**Rate both, because one number cannot carry both.** `Rare · Critical` and `Almost always · Low`
are opposite kinds of work — the first is a landmine, the second is friction — and a single
rating hides which you are looking at. Both still get fixed.

---

<a id="ki-01"></a>

## KI-01 — `<title>`

**Severity:** `<level>`
**Likelihood:** `<almost always | likely | rare>`
**Where:** [file.py:12-30](../file.py#L12-L30)

### What happens

<the defect, with a real code excerpt — copied from the file, not paraphrased>

### Example scenario

<concrete inputs → the wrong outcome, in the project's own domain terms>

### Notes for a fix

<approach, plus the constraints that would trip someone up: invariants to preserve, tests
that cover the area, related IDs worth bundling into the same pass>
