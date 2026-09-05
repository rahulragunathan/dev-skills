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

---

<a id="ki-01"></a>

## KI-01 — `<title>`

**Severity:** `<level>`
**Where:** [file.py:12-30](../file.py#L12-L30)

### What happens

<the defect, with a real code excerpt — copied from the file, not paraphrased>

### Example scenario

<concrete inputs → the wrong outcome, in the project's own domain terms>

### Notes for a fix

<approach, plus the constraints that would trip someone up: invariants to preserve, tests
that cover the area, related IDs worth bundling into the same pass>
