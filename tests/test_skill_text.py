"""Rules about the text of the skills themselves.

Two hazards come from how the skills are read rather than what they say:
- Claude Code replaces `$0`, `$1` ... and `$ARGUMENTS` in a skill's body with the
  words the skill was invoked with (KI-75), so any such text is rewritten.
- The Bash tool runs the user's login shell, often zsh, which reads some bash
  constructs differently (KI-74).
"""
import pathlib
import re
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
from fence import FENCE, fence  # noqa: E402
sys.path.insert(0, str(ROOT / "skills/project-docs"))
import roadmap  # noqa: E402

SKILLS = sorted(ROOT.glob("skills/*/SKILL.md"))
PLACEHOLDER = re.compile(r"\$(\d|ARGUMENTS)")

# zsh traps, matched only outside single quotes:
WORD_LIST = re.compile(r"\bfor\s+\w+\s+in\s+(\$\{|\$[A-Za-z_])")  # unquoted variable as a word list
SUBSCRIPT = re.compile(r"\$\{\w+\[\d")                              # an array index: 1-based in zsh
MODIFIER = re.compile(r"\$[A-Za-z_]\w*:[A-Za-z&]")                  # `$NAME:r` is a zsh modifier


def unquoted(line: str) -> str:
    """The line with single-quoted spans blanked out."""
    return re.sub(r"'[^']*'", "''", line)


def zsh_traps(code: str) -> list[str]:
    hits = []
    for line in code.splitlines():
        bare = unquoted(line)
        if line.lstrip().startswith("#"):
            continue
        for rx in (WORD_LIST, SUBSCRIPT, MODIFIER):
            if rx.search(bare):
                hits.append(line.strip())
                break
    return hits


class ArgumentPlaceholderTest(unittest.TestCase):
    def test_no_argument_placeholders(self):
        # Fails if any skill holds text that skill arguments would overwrite.
        found = [f"{p.relative_to(ROOT)}:{n}: {line.strip()}"
                 for p in SKILLS
                 for n, line in enumerate(p.read_text().splitlines(), 1)
                 if PLACEHOLDER.search(line)]
        self.assertEqual(found, [])


class ZshTrapLintTest(unittest.TestCase):
    def test_lint_flags_each_trap(self):
        # Fails if the lint misses a construct zsh reads differently.
        for code in ('for m in ${RUNGS?x}; do', 'for m in $RUNGS; do',
                     'echo "${EFFORT_ARGS[1]:-high}"', 'git push origin "$TAG:refs/tags/$TAG"'):
            self.assertEqual(len(zsh_traps(code)), 1, code)

    def test_lint_passes_the_portable_forms(self):
        # Fails if the lint flags the forms the skills are told to use.
        for code in ('for m in $(printf \'%s\' "$RUNGS"); do',
                     "gh api graphql -f query='query($owner:String!){x}'",
                     'git push origin "${TAG}:refs/tags/${TAG}"',
                     'X=${A[@]+"${A[@]}"}'):
            self.assertEqual(zsh_traps(code), [], code)

    def test_fences_avoid_zsh_traps(self):
        # Fails if a documented fence uses a construct zsh reads differently.
        found = [f"{p.relative_to(ROOT)}: {hit}"
                 for p in SKILLS
                 for m in FENCE.finditer(p.read_text())
                 for hit in zsh_traps(m.group(2))]
        self.assertEqual(found, [])


class FenceMarkerTest(unittest.TestCase):
    # The fences the suites run; a missing marker would leave its tests selecting nothing.
    REQUIRED = {
        "external-review": {"ladder-wrappers", "discovery", "codex-loop", "gemini-loop", "probe", "failure-probe"},
        "phase-workflow": {"first-push", "after-review", "record-check", "gate", "publish-record", "release-tag",
                           "branch-cleanup", "prune", "mid-scan", "dependency-scan"},
        "project-docs": {"roadmap-close"},
    }

    def test_required_markers_are_present(self):
        # Fails if a fence the suites run loses its marker.
        for skill, names in self.REQUIRED.items():
            text = (ROOT / "skills" / skill / "SKILL.md").read_text()
            found = set(re.findall(r"^\s*# fence: (\S+)$", text, re.M))
            self.assertEqual(names - found, set(), skill)

    def test_each_marker_names_one_fence(self):
        # Fails if two fences share a marker, so a test could run the wrong one.
        for p in SKILLS:
            names = re.findall(r"^\s*# fence: (\S+)$", p.read_text(), re.M)
            for name in set(names):
                fence(p, name)
            self.assertEqual(len(names), len(set(names)), p)


class SecurityCoverageTest(unittest.TestCase):
    """The reviews look for security problems on purpose, in every mode (Decision 9)."""

    def test_rubric_has_a_security_item_for_each_mode(self):
        # Fails if plan reviews get no security prompt, or phase/repo reviews only the bare words.
        rubric = (ROOT / "skills/external-review/SKILL.md").read_text()
        rubric = rubric[rubric.index("## Shared rubric"):rubric.index("## Modes")]
        self.assertIn("**Security", rubric)
        security = rubric[rubric.index("**Security"):]
        security = security[:security.index("\n5. ")] if "\n5. " in security else security
        for words in ("trust boundar", "secret", "injection", "path traversal", "dependency"):
            self.assertIn(words, security.lower(), words)
        for mode in ("*plan*", "*phase / repo*"):
            self.assertIn(mode, security)

    def test_phase_end_order_is_scan_then_reviews_then_security_review(self):
        # Fails if the dependency scan runs after the passes its upgrades would need, or
        # /security-review is missing from the retrospective.
        skill = (ROOT / "skills/phase-workflow/SKILL.md").read_text()
        self.assertIn("2. **Consolidation", skill)
        step = skill[skill.index("2. **Consolidation"):]
        step = step[:step.index("\n3. ")]
        names = ("the dependency scan", "`design-review` in `phase` mode", "`/simplify`",
                 "`/code-review high`", "`/security-review`")
        for name in names:
            self.assertIn(name, step)
        order = [step.index(name) for name in names]
        self.assertEqual(order, sorted(order))
        self.assertIn("# fence: dependency-scan", skill)


ER = ROOT / "skills/external-review/SKILL.md"
PW = ROOT / "skills/phase-workflow/SKILL.md"
KI_TEMPLATE_DIR = ROOT / "skills/project-docs"


def section(text: str, heading: str) -> str:
    """The text under `heading` up to the next heading of the same or a higher level."""
    level = heading.split(" ")[0]
    start = text.index(heading + "\n")
    rest = text[start + len(heading) + 1:]
    stop = re.search(r"^#{1,%d} " % len(level), rest, re.M)
    return rest[: stop.start()] if stop else rest


def flat(text: str) -> str:
    """The text with every run of whitespace as one space, so a wrapped line still matches."""
    return " ".join(text.split())


def template_levels(field: str) -> list[str]:
    return roadmap.load_scales(KI_TEMPLATE_DIR)["KI"][field]


def table_header(text: str, first_cells: str) -> list[str]:
    return roadmap._cells(next(l for l in text.splitlines() if l.startswith(first_cells)))


def all_skills() -> str:
    return "".join(p.read_text() for p in SKILLS)


class TriageTest(unittest.TestCase):
    """Review findings carry a Path, an Area and Steps To Reproduce, and only a blocking one
    holds up a phase."""

    def setUp(self):
        self.text = ER.read_text()
        self.rubric = section(self.text, "## Shared rubric — both reviewers get this text VERBATIM")

    def test_rubric_asks_for_path_ratings_and_steps(self):
        # Fails if a mode stops asking for Path, Area, Severity or Likelihood, phase and repo
        # mode stop asking for numbered steps, plan mode for a concrete failure, or the rubric
        # stops saying a finding is never dropped for its Path.
        r = self.rubric
        for word in ("**Path**", "**Area**", "**Severity**", "**Likelihood**"):
            with self.subTest(asks_for=word):
                self.assertIn(word, r)
        with self.subTest("every mode"):
            self.assertIn("Path, ratings and steps (every mode)", r)
        with self.subTest("phase and repo steps"):
            self.assertRegex(r, r"\*phase / repo\*: add numbered \*\*Steps To Reproduce\*\*")
        with self.subTest("plan failure"):
            self.assertRegex(r, r"\*plan\*: no numbered steps; instead say concretely what goes wrong, and when")
        with self.subTest("never dropped"):
            self.assertIn("Never drop a finding because of its Path.", r)

    def test_rubric_opens_with_the_happy_path_line(self):
        # Fails if the output contract stops putting the Happy Path line before the heading, or
        # drops the empty list's `No findings.`.
        contract = self.rubric[self.rubric.index("**Output contract"):]
        with self.subTest("line first"):
            self.assertRegex(contract, r"Open with one line before the findings heading: "
                                       r"`Happy Path: works`, or `Happy Path: broken \(findings N, M\)`")
        with self.subTest("no findings kept"):
            self.assertIn("`No findings.`", contract)

    def test_rubric_levels_match_the_template(self):
        # Fails if the rubric's Path or Area levels differ from the KI template's, or their order.
        r = self.rubric
        for field in ("Path", "Area"):
            with self.subTest(field=field):
                sentence = re.search(r"\*\*" + field + r"\*\*: (.*?)\.", r, re.S)[1]
                self.assertEqual(re.findall(r"`([^`]+)`", sentence), template_levels(field))

    def test_tables_have_a_path_column(self):
        # Fails if the findings table or the phase review record loses its Path column.
        for first in ("| # | Finding |", "| # | Pass |"):
            with self.subTest(table=first):
                self.assertIn("Path", table_header(self.text, first))

    def test_tables_have_an_area_column(self):
        # Fails if the findings table or the phase review record loses its Area column.
        for first in ("| # | Finding |", "| # | Pass |"):
            with self.subTest(table=first):
                self.assertIn("Area", table_header(self.text, first))

    def test_blocking_rule_is_stated_once_and_grouped(self):
        # Fails if the rule is restated, loses its grouping, or the worked table stops giving
        # Medium/Likely as filed, High/Happy Path/Rare as blocking, High/External/Rare as filed.
        rule = ("A confirmed finding blocks the phase when its Severity is Critical or High, "
                "**and** at least one of these holds: its Path is Happy Path; its Likelihood is "
                "Likely or Almost Always.")
        skills = all_skills()
        with self.subTest("once"):
            self.assertEqual(skills.count(rule), 1)
        worked = section(self.text, "### The blocking rule")
        rows = {tuple(c.strip() for c in l.strip("|").split("|")[:3]): l.split("|")[4].strip()
                for l in worked.splitlines() if l.startswith("| ") and "Blocks" not in l
                and "---" not in l}
        for key, want in ((("Medium", "Happy Path", "Likely"), "No: filed"),
                          (("High", "Happy Path", "Rare"), "Yes"),
                          (("High", "External Interference", "Rare"), "No: filed")):
            with self.subTest(row=key):
                self.assertEqual(rows.get(key), want)

    def test_stop_rule_uses_the_blocking_rule(self):
        # Fails if the loop stops on anything but a complete pass with no blocking finding, or
        # the old count-based stop rule survives.
        loop = flat(section(self.text, "### The loop"))
        with self.subTest("new rule"):
            self.assertIn("Stop when a pass has no blocking finding", loop)
        with self.subTest("old rule gone"):
            self.assertNotIn("no new Critical or High and fewer findings", self.text)

    def test_steps_are_evidence(self):
        # Fails if triage stops confining steps to a disposable fixture with synthetic inputs, or
        # stops sanitising them before they are published.
        triage = flat(section(self.text, "## Triage — verify before presenting"))
        with self.subTest("fixture"):
            self.assertIn("Run them only in a disposable fixture with synthetic inputs", triage)
        with self.subTest("no working tree or network"):
            self.assertIn("never in the working tree, and never against a network or outside service", triage)
        with self.subTest("sanitised"):
            self.assertIn("replace real secrets, account names and local paths with synthetic values", triage)

    def test_every_source_gets_the_fields_at_intake(self):
        # Fails if a source of findings is left out of the intake rule.
        triage = section(self.text, "## Triage — verify before presenting")
        intake = triage[triage.index("**Every source"):]
        for source in ("`/code-review`", "`/security-review`", "`design-review`", "dependency scan"):
            with self.subTest(source=source):
                self.assertIn(source, intake[:600])

    def test_note_labels_are_title_case(self):
        # Fails if a keyed-note label or a gate heading is in sentence case, or an old label remains.
        for label in ("*When It Fires:*", "*What Happens:*", "*Steps To Reproduce:*",
                      "*Reviewer's Fix:*", "*Commentary:*"):
            with self.subTest(present=label):
                self.assertIn(label, self.text)
        for old in ("*When it fires", "*What happens", "*Reviewer's fix", "*Explanation"):
            with self.subTest(absent=old):
                self.assertNotIn(old, self.text)
        gate = section(self.text, "### What the user sees at the gate")
        for heading in ("**The Trend**", "**What The New Findings Are About**", "**Your Recommendation**"):
            with self.subTest(gate=heading):
                self.assertIn(heading, gate)

    def test_unfixed_blocker_replaces_proposed(self):
        # Fails if the old name survives in any skill, or the new one is not defined.
        skills = all_skills()
        with self.subTest("old gone"):
            self.assertNotIn("Proposed: fixed in phase", skills)
        with self.subTest("new defined"):
            self.assertIn("- `Unfixed Blocker` —", self.text)

    def test_dispositions_are_title_case(self):
        # Fails if a sentence-case disposition survives in any skill.
        skills = all_skills()
        for old in ("Fixed in phase", "Already covered", "Not incorporated",
                    "Confirmed: accepted, no work planned", "Open — no roadmap files"):
            with self.subTest(absent=old):
                self.assertNotIn(old, skills)
        for new in ("`Fixed In Phase`", "`Already Covered — <where>`", "`Not Incorporated`",
                    "`Confirmed: Accepted, No Work Planned`", "`Recorded Only: No Roadmap Files`"):
            with self.subTest(present=new):
                self.assertIn(new, self.text)

    def test_disposition_order_is_stated(self):
        # Fails if the skill stops saying how a row's disposition follows from its verdict and
        # the blocking rule.
        self.assertIn("a blocking row is `Fixed In Phase`, or `Unfixed Blocker` when the loop "
                      "has stopped", flat(self.text))

    def test_reviewer_disagreement_is_judged_per_reviewer(self):
        # Fails if the skill stops forbidding a blocker made by mixing two reviewers' ratings.
        rule = flat(section(self.text, "### The blocking rule"))
        self.assertIn("Never combine one reviewer's ratings with another's", rule)


class PhaseWorkflowPointerTest(unittest.TestCase):
    def test_phase_workflow_points_at_the_blocking_rule(self):
        # Fails if §3 step 5 stops linking external-review's blocking rule, or restates it.
        text = PW.read_text()
        step = text[text.index("5. **External review loop:**"):text.index("6. **Post-fix drift re-check")]
        with self.subTest("links"):
            self.assertIn("(../external-review/SKILL.md#the-blocking-rule)", step)
        with self.subTest("no restatement"):
            self.assertNotIn("Critical or High", step)


class TriagePassOneTest(unittest.TestCase):
    """Blocking findings from the phase's first external review pass."""

    def test_summaries_name_every_blocking_likelihood(self):
        # Fails if README or AGENTS.md summarises the blocking rule without Almost Always, or
        # without saying the finding must be confirmed.
        for name in ("README.md", "AGENTS.md"):
            text = flat((ROOT / name).read_text())
            with self.subTest(doc=name):
                self.assertIn("Likely or Almost Always", text)
                self.assertRegex(text, r"confirmed Critical or High")

    def test_happy_path_line_can_cite_tracked_ids(self):
        # Fails if a reviewer has no way to name an already-tracked entry that breaks the
        # Happy Path, since tracked entries are not re-reported as findings.
        text = flat(ER.read_text())
        with self.subTest("rubric"):
            self.assertIn("`Happy Path: broken (tracked KI-nn)`", text)
        with self.subTest("gate keeps tracked IDs"):
            self.assertIn("tracked IDs stay as they are", text)

    def test_partly_rows_use_verified_ratings(self):
        # Fails if the blocking rule stops saying which ratings decide a Partly row.
        rule = flat(section(ER.read_text(), "### The blocking rule"))
        self.assertIn("For a `Partly` row, your verified ratings of the confirmed part decide", rule)


if __name__ == "__main__":
    unittest.main()
