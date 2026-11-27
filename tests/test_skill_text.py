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
            self.assertIn("Never run them in the working tree or against an outside service", triage)
        with self.subTest("sanitised"):
            self.assertIn("replace real secrets, account names and local paths with synthetic values", triage)

    def test_every_source_gets_the_fields_at_intake(self):
        # Fails if a source of findings is left out of the intake rule.
        triage = section(self.text, "## Triage — verify before presenting")
        intake = triage[triage.index("every source gets a Path"):]
        for source in ("`/code-review`", "`/security-review`", "`design-review`", "dependency scan"):
            with self.subTest(source=source):
                self.assertIn(source, intake[:600])

    def test_note_labels_are_title_case(self):
        # Fails if a keyed-note label or a gate heading is in sentence case, or an old label remains.
        for label in ("*When It Fires:*", "*What Happens:*", "*Reviewer's Fix:*", "*Commentary:*"):
            with self.subTest(present=label):
                self.assertIn(label, self.text)
        with self.subTest(present="*Steps To Reproduce*"):
            self.assertIn("then *When It Fires*, *What Happens*, *Steps To Reproduce*, "
                          "*Reviewer's Fix* and *Commentary*", flat(self.text))
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

    def test_partly_rows_use_verified_ratings(self):
        # Fails if the blocking rule stops saying which ratings decide a Partly row.
        rule = flat(section(ER.read_text(), "### The blocking rule"))
        self.assertIn("For a `Partly` row, your verified ratings of the confirmed part decide", rule)


class TriagePassTwoTest(unittest.TestCase):
    """Blocking findings from the phase's second external review pass."""

    def test_merged_partly_rows_use_verified_ratings(self):
        # Fails if the disagreement rule still lets a reviewer's disproved ratings block a
        # merged Partly row.
        rule = flat(section(ER.read_text(), "### The blocking rule"))
        with self.subTest("confirmed only"):
            self.assertIn("A `Confirmed` merged row blocks only if one reviewer's three ratings block", rule)
        with self.subTest("partly"):
            self.assertIn("a `Partly` merged row is decided by your verified ratings alone", rule)


class FollowUpTest(unittest.TestCase):
    """The follow-up to the phase's review: policy gaps and presentation."""

    def changelog_entry(self):
        text = (ROOT / "CHANGELOG.md").read_text()
        start = text.index("## [2.3.0]")
        return text[start:text.index("\n## [", start + 1)]

    def test_no_happy_path_line_anywhere(self):
        # Fails if any skill, README, AGENTS.md or the 2.3.0 entry still asks for or shows the
        # reviewer's Happy Path line or its tracked-ID form.
        docs = {"skills": all_skills(), "README.md": (ROOT / "README.md").read_text(),
                "AGENTS.md": (ROOT / "AGENTS.md").read_text(), "CHANGELOG 2.3.0": self.changelog_entry()}
        for name, text in docs.items():
            for phrase in ("Happy Path: works", "Happy Path: broken", "tracked KI-nn", "Happy Path line"):
                with self.subTest(doc=name, phrase=phrase):
                    self.assertNotIn(phrase, flat(text))

    def test_trend_has_a_blocking_column(self):
        # Fails if the gate's trend is a bare count series rather than a table with Blocking.
        gate = section(ER.read_text(), "### What the user sees at the gate")
        self.assertIn("| Pass | Rows | Blocking | Outcome |", gate)

    def test_keyed_notes_open_with_blocking_and_disposition(self):
        # Fails if an example note does not open with the bare word Blocking or Non-Blocking and
        # then its Disposition, if a `*Blocking:*` label appears, or if the record's note rule
        # does not ask for the opening.
        text = ER.read_text()
        notes = [flat(n) for n in re.findall(r"^\*\*F-\d+\*\* — .*?(?=\n\n)", text, re.M | re.S)]
        with self.subTest("examples exist"):
            self.assertGreaterEqual(len(notes), 2)
        for note in notes:
            with self.subTest(note=note[:12]):
                self.assertRegex(note, r"^\*\*F-\d+\*\* — \*(Blocking|Non-Blocking)\* · \*Disposition:\* ")
        with self.subTest("no label"):
            self.assertNotIn("*Blocking:*", all_skills())
        with self.subTest("record rule"):
            record = flat(section(text, "### The phase review record"))
            self.assertIn("a keyed note for every row** — it opens with *Blocking* or *Non-Blocking*", record)
        with self.subTest("rejected"):
            self.assertIn("A `Rejected` row is *Non-Blocking*", flat(text))

    def test_plan_notes_have_no_steps(self):
        # Fails if a plan-mode example note shows Steps To Reproduce, or intake asks plan-mode
        # findings for steps (KI-105).
        text = ER.read_text()
        notes = [flat(n) for n in re.findall(r"^\*\*F-\d+\*\* — .*?(?=\n\n)", text, re.M | re.S)]
        for note in notes:
            with self.subTest(note=note[:12]):
                self.assertNotIn("Steps To Reproduce", note)
        triage = flat(section(text, "## Triage — verify before presenting"))
        with self.subTest("intake"):
            self.assertIn("**In phase and repo mode, every source gets a Path, an Area and Steps To Reproduce at intake.**", triage)


class PolicyGapTest(unittest.TestCase):
    """The policy gaps the phase's review filed, fixed in its follow-up."""

    def setUp(self):
        self.er = flat(ER.read_text())
        self.pw = PW.read_text()

    def test_ki_97_the_fixture_is_named(self):
        # Fails if triage runs reviewer steps without naming a confined fixture, or without
        # refusing a step that reaches outside it.
        step = self.er[self.er.index("2. **Steps To Reproduce are evidence"):self.er.index("3. **In phase and repo mode")]
        for part in ("`mktemp -d`", "a scratch `HOME`", "no credential variables", "no network",
                     "Refuse a step that reads or writes outside that folder, or that fetches and runs code"):
            with self.subTest(part=part):
                self.assertIn(part, step)

    def test_ki_107_the_whole_record_is_sanitised(self):
        # Fails if sanitising before publication still covers only the steps.
        self.assertIn("sanitise all of it, not only the steps", self.er)
        self.assertIn("the reviewer's quoted fix included", self.er)

    def test_ki_98_step_2_reaches_intake_and_the_rule(self):
        # Fails if phase-workflow §3 step 2 does not send its findings through intake and the
        # blocking rule, or if the dependency-scan carve-out survives.
        step = self.pw[self.pw.index("2. **Consolidation"):self.pw.index("3. **Red record check")]
        for link in ("../external-review/SKILL.md#triage--verify-before-presenting",
                     "../external-review/SKILL.md#the-blocking-rule"):
            with self.subTest(link=link):
                self.assertIn(link, step)
        with self.subTest("no carve-out"):
            self.assertNotIn("keeps its own policy", self.er)

    def test_ki_99_repo_mode_blocking_rows_have_a_disposition(self):
        # Fails if a blocking row in a repo review has no disposition.
        self.assertIn("In repo mode there is no loop and no fix on the branch, so a blocking row is `Unfixed Blocker`", self.er)

    def test_ki_100_one_path_per_row(self):
        # Fails if the Path column still lets a reviewer name several Paths for one row.
        self.assertIn("A row has one Path per reviewer", self.er)
        self.assertNotIn("name each, the one that blocks first", self.er)

    def test_ki_103_accepted_rows_get_no_entry(self):
        # Fails if step 4 still files every triaged finding, accepted and rejected ones included.
        bullet = flat(next(l for l in self.pw.splitlines() if "every finding triaged out of steps 1–3" in l))
        self.assertIn("a `Rejected` or `Confirmed: Accepted, No Work Planned` row gets none", bullet)

    def test_ki_104_the_users_change_has_a_form(self):
        # Fails if the disposition order does not say how a row the user changed is written, or
        # the form is not chronological: what the row was first, then what the user made it.
        order = self.er[self.er.index("**Disposition order.**"):self.er.index("- `Fixed In Phase` —")]
        self.assertIn("`Originally <old>; <new> On User's Call`", order)
        self.assertIn("describe the default", order)

    def test_the_users_change_reads_in_order_everywhere(self):
        # Fails if the old `<new> — was <old>` form survives in a skill, the loop or the release notes.
        for name, text in (("external-review", self.er), ("phase-workflow", self.pw),
                           ("CHANGELOG", (ROOT / "CHANGELOG.md").read_text())):
            with self.subTest(name):
                self.assertNotIn("was <old>, the user's call", text)
                self.assertNotIn("— was Filed, the user's call", text)

    def test_ki_106_merged_ratings_are_attributed_and_filed_whole(self):
        # Fails if Likelihood has no attribution rule for disagreeing reviewers, or a filed
        # merged row has no rule for which ratings it takes.
        with self.subTest("likelihood"):
            self.assertIn("When the two reviewers disagree on Likelihood, record both, attributed like Severity", self.er)
        with self.subTest("filing"):
            self.assertIn("A filed merged row takes one whole set of three ratings, never a mix", self.er)

    def test_ki_108_incomplete_pass_blockers_have_a_disposition(self):
        # Fails if a confirmed blocker from an incomplete pass has no disposition while the
        # retry waits.
        self.assertIn("While it waits, a confirmed blocking row from it is `Unfixed Blocker`", self.er)

    def test_ki_111_codex_loop_writes_its_state(self):
        # Fails if the Codex loop leaves no end state for progress to read.
        text = ER.read_text()
        fence = text[text.index("# fence: codex-loop"):text.index("# fence: gemini-loop")]
        for state in ("done", "failed", "unavailable"):
            with self.subTest(state=state):
                self.assertIn(f'echo {state} > "$STATE"', fence)

    def test_ki_110_no_fix_fallback_is_title_case(self):
        # Fails if the fallback for a reviewer who gave no fix is still lowercase.
        self.assertIn("`None Offered`", self.er)
        self.assertNotIn("`none offered`", self.er)

    def test_unfixed_blocker_covers_every_case(self):
        # Fails if the Unfixed Blocker definition still names only a stopped loop, though repo
        # mode and an incomplete pass use it too.
        bullet = flat(next(l for l in ER.read_text().splitlines() if l.startswith("- `Unfixed Blocker` —")))
        for case in ("the pass the loop stopped on", "an incomplete pass whose retry is pending", "a repo review"):
            with self.subTest(case=case):
                self.assertIn(case, bullet)

    def test_filed_merged_rows_take_one_defined_set(self):
        # Fails if a non-blocking merged row has no defined set of ratings to file, or the Path
        # rule leaves two reviewers' Paths unresolved.
        er = flat(ER.read_text())
        with self.subTest("filing"):
            self.assertIn("else the set that decided a blocking disposition, else the set of the "
                          "reviewer with the higher Severity", er)
        with self.subTest("path"):
            self.assertIn("A row has one Path per reviewer", er)

    def test_the_fixture_gets_the_code_one_way(self):
        # Fails if the fixture rule gives no way to bring the code under review into the folder.
        self.assertIn("`git clone --no-hardlinks`", flat(ER.read_text()))


class PassFourTest(unittest.TestCase):
    """The blocking finding and the partly fixed entries from the follow-up's review."""

    def setUp(self):
        self.er = flat(ER.read_text())
        self.pw = flat(PW.read_text())

    def test_the_fixture_clone_has_no_origin(self):
        # Fails if the fixture's clone keeps `origin` pointing at the real repository (F-35).
        self.assertIn("then remove its `origin` (`git -C <folder>/repo remote remove origin`)", self.er)

    def test_only_filed_rows_reach_the_roadmap(self):
        # Fails if §3's opening or step 2 still sends every non-blocking row to the roadmap files.
        step2 = self.pw[self.pw.index("2. **Consolidation"):self.pw.index("3. **Red record check")]
        with self.subTest("step 2"):
            self.assertIn("a blocking one is fixed in the phase, and the rest take their disposition from "
                          "the same rule; only a `Filed` row gets a roadmap entry", step2)
        with self.subTest("opening"):
            self.assertIn("Findings from every step enter the review record, and those dispositioned "
                          "`Filed` land in the roadmap files", self.pw)

    def test_a_plan_finding_files_its_concrete_failure(self):
        # Fails if a plan finding filed as a KI has nothing to put in Steps To Reproduce.
        self.assertIn("A KI filed from a plan review has no steps to inherit: its *Steps To Reproduce* "
                      "section gives the concrete failure", self.er)

    def test_equal_severity_has_a_tie_break(self):
        # Fails if a merged row whose reviewers tie on Severity has no rule for which set is filed.
        self.assertIn("On a tie, take the set with the higher Likelihood, then the Path that blocks first", self.er)

    def test_a_completed_retry_settles_the_waiting_rows(self):
        # Fails if nothing says what happens to a waiting Unfixed Blocker once the retry completes,
        # or the disposition order omits the waiting case.
        with self.subTest("transition"):
            self.assertIn("When the retry completes, those rows are settled as for any complete pass, "
                          "and that is not a change by the user", self.er)
        with self.subTest("order"):
            self.assertIn("or `Unfixed Blocker` when the loop has stopped or an incomplete pass awaits its retry", self.er)


class BookkeepingFixTest(unittest.TestCase):
    """Document fixes to the release's bookkeeping files land after the last pass without another."""

    def rule(self):
        text = flat(ER.read_text())
        start = text.index("**After the last pass, only bookkeeping lands:**")
        return text[start:text.index("### What the user sees at the gate", start)]

    def test_confirmed_document_fixes_need_no_pass(self):
        # Fails if a confirmed reviewer fix to the bookkeeping files still needs a narrow pass, or
        # phase-workflow's post-review rule does not allow it.
        rule = self.rule()
        self.assertIn("Make it without another pass", rule)
        pw = flat(PW.read_text())
        self.assertIn("and the document fixes to this release's `CHANGELOG.md` entry, the roadmap files and "
                      "the phase record that external-review's", pw)

    def test_a_document_fix_is_tied_to_a_verified_finding(self):
        # Fails if a document fix may land without the reviewer finding that asked for it, without
        # the triager verifying and agreeing, or without its commit naming the row.
        rule = self.rule()
        for clause in ("that one reviewer finding asks for, and that you verify and agree with",
                       "Nothing lands as a document fix without the finding that asked for it",
                       "its commit message names the row"):
            with self.subTest(clause=clause):
                self.assertIn(clause, rule)

    def test_a_document_fix_has_bounds(self):
        # Fails if the rule stops limiting CHANGELOG to this release, or lets a document fix close an
        # entry or change a value the workflow reads.
        rule = self.rule()
        for clause in ("this release's `CHANGELOG.md` entry", "or an entry's ratings",
                       "It never closes or deletes an entry, changes what an entry covers, or changes a value "
                       "the workflow reads: the phase-record keys set at phase start, `ORIGIN_URL`, "
                       "`ORIGIN_PUSH_URL`, `REPO`, `DEFAULT_BRANCH`, `PHASE_BRANCH` and `MERGE_METHOD`; those "
                       "need a narrow pass"):
            with self.subTest(clause=clause):
                self.assertIn(clause, rule)
        with self.subTest("patch check"):
            self.assertIn("a document fix to this release's `CHANGELOG.md` entry, the roadmap files or the "
                          "phase record whose commit, in the log the check prints, names its finding", flat(PW.read_text()))

    def test_a_document_fix_fits_the_loop(self):
        # Fails if a document fix's blocking status, its effect on the stop rule, or its evidence in
        # place of a failing test is left unstated, or the stop rule and Fixed In Phase contradict it.
        er = flat(ER.read_text())
        rule = self.rule()
        for clause in ("whatever its blocking status",
                       "a pass whose only blocking rows are document fixes stops as if it had none",
                       "in place of a failing test its note gives the claim or wording it corrects and the source "
                       "you checked it against, and says whether it landed after the last pass",
                       "On a pass the loop continues past, it is made with that pass's fixes, so the next pass "
                       "reviews it"):
            with self.subTest(clause=clause):
                self.assertIn(clause, rule)
        with self.subTest("definition"):
            self.assertIn("with a failing test written first, or a document fix, which has its own evidence", er)
        with self.subTest("stop rule"):
            self.assertIn("that pass's findings are not fixed, document fixes aside", er)

    def test_the_adjacent_rules_carry_the_exception(self):
        # Fails if the disposition order, Unfixed Blocker, the stop rule, the record's fixed-row
        # evidence or phase-workflow's step 5 still contradict the document-fix exception.
        er = flat(ER.read_text())
        pw = flat(PW.read_text())
        for clause in ("In phase mode, on a complete pass, a document fix is the exception: it is `Fixed In "
                       "Phase` whether or not it blocks, and whether or not the loop has stopped",
                       "In repo mode there is no loop and no fix on the branch",
                       "fix the other blocking rows, each with a failing test first, make the pass's document "
                       "fixes in the same commit",
                       "file the other deferred rows",
                       "its Commit and its evidence (a test, or *Checked Against* for a document fix)",
                       "the source you checked it against, and whether it landed after the last pass",
                       "since every fix but a document fix needs another review pass",
                       "Stop when a pass has no blocking finding other than a document fix",
                       "Other deferred rows are filed before the gate; other blocking rows go to the gate",
                       "*Checked Against:* for a document fix, in place of *Scenarios*"):
            with self.subTest(clause=clause):
                self.assertIn(clause, er)
        for clause in ("a changed phase-record key the workflow reads, one of those set at phase start such as "
                       "`MERGE_METHOD`, included",
                       "Only a finding that [blocks the phase](../external-review/SKILL.md#the-blocking-rule), or a document fix, is fixed here",
                       "a document fix gives the source it was checked against instead"):
            with self.subTest(clause=clause):
                self.assertIn(clause, pw)


class PassNineTest(unittest.TestCase):
    def setUp(self):
        self.er = flat(ER.read_text())

    def test_ki_126_the_rule_s_neighbours_fit_it(self):
        # Fails if the gate still denies the unreviewed document fix, the loop asks when rather than
        # whether a fix landed after the last pass, Checked Against demands a wrong claim from a
        # wording fix, or loop step 4 sends a document fix the user asks for to another pass.
        for clause in ("Nothing is fixed-and-unreviewed but a document fix made after the last pass, "
                       "which the hand-off names with its *Checked Against*",
                       "*Checked Against:* for a document fix, in place of *Scenarios*: the claim or wording "
                       "it corrects",
                       "Any other fix the user then asks for needs another pass"):
            with self.subTest(clause=clause):
                self.assertIn(clause, self.er)
        for gone in ("says when it landed", "the claim that was wrong", "Nothing is fixed-and-unreviewed. ",
                     "A fix the user then asks for"):
            with self.subTest(gone=gone):
                self.assertNotIn(gone, self.er)

    def test_ki_122_a_mixed_finding_is_split(self):
        # Fails if a finding asking for a document fix and another change can be marked Fixed In Phase
        # once only its document half is done.
        start = self.er.index("**After the last pass, only bookkeeping lands:**")
        rule = self.er[start:self.er.index("### What the user sees at the gate", start)]
        self.assertIn("A finding that asks for a document fix and for any other change is split at triage "
                      "into two rows that share its ID", rule)
        self.assertIn("the rest, which takes its own disposition from the blocking rule", rule)
        self.assertIn("- `Fixed In Phase` — the whole row is fixed:", self.er)
        # Fails if the split's two rows can be counted as two findings in the pass's counts.
        self.assertIn("The two rows are one finding in the pass's counts", rule)

    def test_the_users_change_names_the_rule_s_disposition(self):
        # Fails if a row the user changed twice has no rule for what `<old>` is.
        order = self.er[self.er.index("**Disposition order.**"):self.er.index("- `Fixed In Phase` —")]
        self.assertIn("`<old>` is the disposition the rule gave the row", order)

    def test_the_post_review_log_states_its_merge_handling(self):
        # Fails if the log relies on a newer git's default merge diff, or a merge can bring in a
        # document fix whose finding no message names.
        pw = flat(PW.read_text())
        # KI-127: --diff-merges needs Git 2.31; `-m --first-parent` gives the same patch on 2.30.
        self.assertIn("log -p -m --first-parent", pw)
        self.assertNotIn("--diff-merges", pw)
        self.assertIn("a merge's message names every finding it brings in", pw)

    def test_a_wording_fix_is_checked_against_a_source(self):
        # Fails if a wording fix can cite only the reviewer's request as its evidence.
        self.assertNotIn("for a wording fix, the reviewer's request", self.er)

    def test_ki_125_the_last_drift_check_runs_roadmap_check(self):
        # Fails if step 6 after the last pass checks only new filings, so an existing entry a document
        # fix re-rated can disagree with its ROADMAP row at the gate.
        pw = flat(PW.read_text())
        step = pw[pw.index("6. **Post-fix drift re-check"):pw.index("7. **")]
        self.assertIn("After the last pass, where the roadmap files exist, run `roadmap.py check`", step)
        self.assertIn("an existing entry a document fix re-rated", step)
        self.assertNotIn("confirm only that every filing", step)


if __name__ == "__main__":
    unittest.main()
