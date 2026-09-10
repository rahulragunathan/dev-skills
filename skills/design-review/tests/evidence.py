#!/usr/bin/env python3
"""Assemble and check a batch of design-review pressure-test evidence.

A batch is only worth grading if every answer in it was produced against the
same skill text, and if that text is still the text in the repository. Two
batches failed that test without anyone noticing: one mixed baselines from an
earlier round with with-skill answers from a later one, and one recorded a
single repository SHA that could not say which scenario had gone stale.

So provenance is tracked per scenario, never per repository. Each scenario
records the skill it loads, that file's git SHA and content hash, its prompt
hash and its grading-condition hash. `check` recomputes all of them and names
exactly the scenarios that must be re-run.

Usage:
    evidence.py init <dir> --round N --model ID [--tests DIR]
    evidence.py record <dir> --scenario S07 --arm baseline|with-skill \
        --transcript FILE
    evidence.py check <dir> [--require-complete]

Exit 0 on success, 1 on refusal or expiry. Nothing is written unless every
check passes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import sys

ARMS = ("baseline", "with-skill")


def fail(msg: str) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(1)


def h16(text: str) -> str:
    """The project's content hash: sha256 of the text, first 16 hex digits."""
    return hashlib.sha256(text.encode()).hexdigest()[:16]


def section(text: str, heading: str) -> str:
    m = re.search(rf'^## {re.escape(heading)}\n(.*?)(?=^## |\Z)', text, re.M | re.S)
    return m.group(1).strip() if m else ""


def unquote(block: str) -> str:
    """A scenario stores its prompt as a blockquote; the subagent gets it bare."""
    return "\n".join(re.sub(r'^> ?', '', l) for l in block.splitlines()).strip()


def git_sha(path: pathlib.Path) -> str:
    r = subprocess.run(["git", "log", "-1", "--format=%h", "--", str(path)],
                       capture_output=True, text=True)
    return r.stdout.strip() or "unknown"


def loads_of(text: str, name: str) -> str:
    # Declared, never inferred. Guessing from prose is right until a scenario
    # merely mentions the other skill, and then it is silently wrong about the
    # one thing this file exists to track.
    m = re.search(r'^\*\*Loads:\*\*\s*(\S+)', text, re.M)
    if not m:
        fail(f"{name}: no '**Loads:**' line; declare which skill the run loads")
    return m.group(1)


def scan(tests: pathlib.Path) -> dict:
    out = {}
    for f in sorted(tests.glob("s0*.md")):
        text = f.read_text()
        sid = "S" + f.name[1:3]
        skill = loads_of(text, f.name)
        spath = pathlib.Path("skills") / skill / "SKILL.md"
        if not spath.is_file():
            fail(f"{sid}: {spath} does not exist")
        prompt = unquote(section(text, "Prompt"))
        if not prompt:
            fail(f"{sid}: no '## Prompt' section")
        cond = section(text, "Failure conditions")
        if not cond:
            fail(f"{sid}: no '## Failure conditions' section")
        out[sid] = {
            "file": str(f),
            "loads": skill,
            "skill_path": str(spath),
            "skill_git_sha": git_sha(spath),
            "skill_content_hash": h16(spath.read_text()),
            "prompt_hash": h16(prompt),
            "condition_hash": h16(cond),
            "arms": {},
            "_prompt": prompt,
            "_skill_text": spath.read_text(),
        }
    if not out:
        fail(f"no scenario files under {tests}")
    return out


def replicate_count(value):
    if type(value) is not int or value < 1:
        fail("replicates must be a positive integer")
    return value


def cmd_init(args) -> int:
    replicate_count(args.replicates)
    ev = pathlib.Path(args.dir)
    if ev.exists() and any(ev.iterdir()):
        fail(f"refusing: {ev} exists and is not empty; a batch is never appended to")
    scenarios = scan(pathlib.Path(args.tests))
    (ev / "answers").mkdir(parents=True)
    snapshots = {}
    for sid, s in scenarios.items():
        (ev / f"{sid}-prompt.txt").write_text(s.pop("_prompt") + "\n")
        snapshots[s["loads"]] = s.pop("_skill_text")
    for skill, text in snapshots.items():
        (ev / f"loaded-{skill}.md").write_text(text)
    manifest = {
        "round": args.round,
        "date": args.date,
        "model": args.model,
        "arms": list(ARMS),
        # How many runs per arm. One run cannot separate "the rule is needed"
        # from "that run drew badly", which is how two units were graded wrong.
        "replicates": args.replicates,
        "scenarios": scenarios,
    }
    (ev / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"initialised {ev} — {len(scenarios)} scenarios, {len(snapshots)} skill snapshots")
    for sid, s in scenarios.items():
        print(f"  {sid}  loads {s['loads']:16} skill {s['skill_content_hash']}  "
              f"cond {s['condition_hash']}")
    return 0


def first_user_text(path: pathlib.Path) -> str:
    """What the run was actually dispatched with."""
    for line in path.read_text(errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        m = row.get("message") or {}
        if m.get("role") != "user":
            continue
        content = m.get("content")
        if isinstance(content, str):
            return content
        for c in content or []:
            if c.get("type") == "text":
                return c["text"]
    return ""


def read_transcript(path: pathlib.Path) -> tuple[str, int, bool]:
    """Final assistant text, how many tools the run used, and whether it finished.

    A transcript copied while the agent is still working ends on a tool call or
    a thinking block, and its last text is whatever preamble the run opened
    with. That reads as a valid short answer, so completeness is checked here
    rather than left to whoever looks at the byte count.
    """
    last_msg_complete = False
    texts, tools = [], 0
    for line in path.read_text(errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            return (texts[-1] if texts else ""), tools, False
        m = row.get("message") or {}
        if m.get("role") != "assistant":
            continue
        content = m.get("content")
        if isinstance(content, str):
            texts.append(content)
            last_msg_complete = m.get("stop_reason") == "end_turn"
            continue
        msg_text, msg_tool = False, False
        for c in content or []:
            if c.get("type") == "text":
                texts.append(c["text"])
                msg_text = True
            elif c.get("type") == "tool_use":
                tools += 1
                msg_tool = True
        # A message carrying both a preamble and a tool call is a run still in
        # flight, not an answer. Treating any text as completion recorded four
        # of round 4's answers as their opening sentence.
        last_msg_complete = msg_text and not msg_tool and m.get("stop_reason") == "end_turn"
    return (texts[-1] if texts else ""), tools, last_msg_complete


def cmd_record(args) -> int:
    ev = pathlib.Path(args.dir)
    mpath = ev / "manifest.json"
    if not mpath.is_file():
        fail(f"no manifest under {ev}; run init first")
    manifest = json.loads(mpath.read_text())
    replicate_count(manifest.get("replicates", 1))
    if args.scenario not in manifest["scenarios"]:
        fail(f"refusing: unknown scenario {args.scenario}")
    tpath = pathlib.Path(args.transcript)
    body, tools, finished = read_transcript(tpath)
    if not body.strip():
        fail(f"refusing: {args.transcript} carries no assistant answer")
    if not finished:
        fail(f"refusing: {args.transcript} is incomplete — its last assistant "
             f"message is not an answer, so the run had not finished when it "
             f"was captured")
    # The run must have been dispatched with the prompt this batch recorded. A
    # hand-assembled paste that drops a section leaves the answer looking valid
    # while it answers a different question — that is the S01 failure, and it
    # was caught last time only because a hash happened to be compared by hand.
    want = (ev / f"{args.scenario}-prompt.txt").read_text().strip()
    got = first_user_text(tpath)
    if want and want not in got:
        fail(f"refusing: {args.transcript} was not dispatched with "
             f"{args.scenario}-prompt.txt; the recorded prompt is not in the "
             f"first user message")
    # A baseline that reached for the skill under test is not a baseline. This
    # is the S02 contamination, which was previously caught only by eye.
    if args.arm == "baseline" and tools > 0:
        fail(f"refusing: baseline is contaminated — {tools} tool use(s) in {args.transcript}")
    reps = replicate_count(manifest.get("replicates", 1))
    if not (1 <= args.replicate <= reps):
        fail(f"refusing: replicate {args.replicate} is outside the batch's "
             f"declared count of {reps}")
    key = args.arm if reps == 1 else f"{args.arm}#{args.replicate}"
    suffix = args.arm if reps == 1 else f"{args.arm}-{args.replicate}"
    tgt = ev / "answers" / f"{args.scenario}-{suffix}.md"
    # Hash what is written, not what was parsed. Hashing the pre-normalized body
    # made `check` report every untouched answer as edited.
    normalized = body.rstrip("\n") + "\n"
    tgt.write_text(normalized)
    manifest["scenarios"][args.scenario]["arms"][key] = {
        "answer": f"answers/{tgt.name}",
        "answer_hash": h16(normalized),
        "tool_uses": tools,
        "transcript": pathlib.Path(args.transcript).name,
    }
    mpath.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"recorded {args.scenario} {key}: {len(body)} bytes, {tools} tool uses")
    return 0


def cmd_check(args) -> int:
    ev = pathlib.Path(args.dir)
    mpath = ev / "manifest.json"
    if not mpath.is_file():
        fail(f"no manifest under {ev}")
    manifest = json.loads(mpath.read_text())
    replicate_count(manifest.get("replicates", 1))
    ok = True
    for sid, s in sorted(manifest["scenarios"].items()):
        reasons = []
        spath = pathlib.Path(s["skill_path"])
        if not spath.is_file():
            reasons.append("skill file is gone")
        elif h16(spath.read_text()) != s["skill_content_hash"]:
            reasons.append(f"{s['loads']} changed")
        f = pathlib.Path(s["file"])
        if not f.is_file():
            reasons.append("scenario file is gone")
        else:
            text = f.read_text()
            if h16(section(text, "Failure conditions")) != s["condition_hash"]:
                reasons.append("grading conditions changed")
            if h16(unquote(section(text, "Prompt"))) != s["prompt_hash"]:
                reasons.append("prompt changed")
        # Verify the answers, not only the keys that name them. Checking the
        # manifest alone reported a batch current with every answer file
        # deleted, which is the one thing a completeness check exists to catch.
        for arm, rec in sorted(s.get("arms", {}).items()):
            ap = ev / rec.get("answer", "")
            if not ap.is_file():
                reasons.append(f"{arm} answer file is missing")
            elif not ap.read_text().strip():
                reasons.append(f"{arm} answer file is empty")
            elif "answer_hash" in rec and h16(ap.read_text()) != rec["answer_hash"]:
                reasons.append(f"{arm} answer changed after it was recorded")
        if args.require_complete:
            reps = replicate_count(manifest.get("replicates", 1))
            want = ([a for a in ARMS] if reps == 1
                    else [f"{a}#{i}" for a in ARMS for i in range(1, reps + 1)])
            missing = [k for k in want if k not in s.get("arms", {})]
            if missing:
                reasons.append("missing " + ", ".join(missing))
        if reasons:
            ok = False
            print(f"{sid}  EXPIRED — {'; '.join(reasons)}")
        else:
            print(f"{sid}  current")
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("init")
    p.add_argument("dir")
    p.add_argument("--round", type=int, required=True)
    p.add_argument("--model", required=True)
    p.add_argument("--date", default="")
    p.add_argument("--tests", default="skills/design-review/tests")
    p.add_argument("--replicates", type=int, default=1)
    p.set_defaults(fn=cmd_init)

    p = sub.add_parser("record")
    p.add_argument("dir")
    p.add_argument("--scenario", required=True)
    p.add_argument("--arm", required=True, choices=list(ARMS))
    p.add_argument("--replicate", type=int, default=1)
    p.add_argument("--transcript", required=True)
    p.set_defaults(fn=cmd_record)

    p = sub.add_parser("check")
    p.add_argument("dir")
    p.add_argument("--require-complete", action="store_true")
    p.set_defaults(fn=cmd_check)

    args = ap.parse_args()
    if getattr(args, "date", None) == "":
        import datetime
        args.date = datetime.date.today().isoformat()
    return args.fn(args)


if __name__ == "__main__":
    raise SystemExit(main())
