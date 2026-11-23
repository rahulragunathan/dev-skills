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


if __name__ == "__main__":
    unittest.main()
