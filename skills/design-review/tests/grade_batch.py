#!/usr/bin/env python3
"""Grade a recorded batch of design-review answers with blind model graders.

grade.py executes what can be executed and leaves every failure condition open
for a reviewer. This fills those judgements the same way every time: each answer
gets a fresh grader with one versioned prompt, the grader never sees the arm,
replicate or scenario file, every verdict must quote the answer it grades, and
every verdict goes back through grade.py, which binds it to the exact answer and
condition text. A sample of answers is graded twice, so agreement between
graders is measured rather than assumed.

grade.py is run as a command rather than imported, so the command-line contract
other callers rely on is the one exercised here.

Usage, from the repository root:
    grade_batch.py prepare <evidence-dir> <grading-dir> --grader-model ID [--seed N]
    grade_batch.py log-dispatch <grading-dir> --packet ID --agent-id ID [--replace]
    grade_batch.py collect <grading-dir> --session PARENT.jsonl
    grade_batch.py agree <grading-dir>
    grade_batch.py summary <grading-dir>

Dispatch each packet as a fresh agent with no tools, sending dispatch/<ID>.txt
verbatim.

Exit 0 on success, 1 on refusal. collect exits 2 when nothing was refused but
some graders are still running; agree and summary exit 1 while any packet they
need is uncollected.
"""
from __future__ import annotations

import argparse
import collections
import datetime
import json
import pathlib
import random
import re
import secrets
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from evidence import (ARMS, LOG_NAME, Refusal, fail, finished_reply, h16,  # noqa: E402
                      load_manifest, log_dispatch, read_dispatch_log, section,
                      session_statuses, slot_key, transcript_for)

PROMPT = HERE / "grader-prompt.md"
BEGIN, END = "=====BEGIN ANSWER=====", "=====END ANSWER====="


def run_grade(scenario_file: str, ev: pathlib.Path, arm: str, rep: int,
              judgements: pathlib.Path | None = None) -> dict:
    cmd = [sys.executable, str(HERE / "grade.py"), "--scenario", scenario_file,
           "--evidence", str(ev), "--arm", arm, "--replicate", str(rep), "--json"]
    if judgements:
        cmd += ["--judgements", str(judgements)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    # grade.py exits 0, 1 or 2 with a report. Anything else is not a grade.
    if r.returncode not in (0, 1, 2) or not r.stdout.strip().startswith("{"):
        raise Refusal("invalid", f"grade.py refused {scenario_file} {arm} {rep}: "
                                 f"{(r.stderr or r.stdout).strip()}")
    return json.loads(r.stdout)


def require_current(ev: pathlib.Path) -> None:
    r = subprocess.run([sys.executable, str(HERE / "evidence.py"), "check", str(ev),
                        "--require-complete"], capture_output=True, text=True)
    if r.returncode != 0:
        fail(f"refusing: evidence batch {ev} is not complete and current:\n{r.stdout}{r.stderr}")


def load_grading(out: pathlib.Path) -> dict:
    path = out / "grading.json"
    if not path.is_file():
        fail(f"no grading.json under {out}; run prepare first")
    return json.loads(path.read_text())


def packet_errors(grading: dict):
    return lambda cols: [] if cols[0] in grading["packets"] else [f"unknown packet {cols[0]}"]


def recorded_answer(ev: pathlib.Path, manifest: dict, packet: dict) -> str:
    rec = manifest["scenarios"][packet["scenario"]]["arms"][
        slot_key(packet["arm"], packet["replicate"], manifest.get("replicates", 1))]
    answer = (ev / rec["answer"]).read_text()
    if h16(answer) != packet["answer_hash"]:
        raise Refusal("invalid", "the recorded answer changed since prepare")
    return answer


def packet_text(pid: str, conditions: str, report: dict, answer: str) -> str:
    checks = []
    for c in report["checks"]:
        checks.append(f"- {c['id']} [{c['status']}] {c['expression']}: {c['detail']}")
        for m in c.get("matches", [])[:10]:
            checks.append(f"  - line {m['line']}: {m['context'].strip()}")
    failed = [f"condition {q['id']} (checks: {', '.join(q.get('check_ids', []))})"
              for q in report["questions"] if q["status"] == "fail"]
    return "\n".join([
        f"# Packet {pid}", "",
        "## Failure conditions", "", conditions, "",
        "## Conditions to judge", "", ", ".join(q["id"] for q in report["questions"]), "",
        "## Executed checks", "",
        "\n".join(checks) if checks else "None. This scenario has no executable checks.", "",
        "Conditions the harness already failed: " + ("; ".join(failed) if failed else "none."), "",
        "## Answer", "",
        "The answer is everything between the two marker lines.", "",
        BEGIN, answer.rstrip("\n"), END, ""])


def cmd_prepare(args) -> int:
    ev, out = pathlib.Path(args.evidence), pathlib.Path(args.grading)
    if out.exists() and any(out.iterdir()):
        fail(f"refusing: {out} exists and is not empty; grades from two preparations "
             f"cannot share a directory")
    require_current(ev)
    manifest = load_manifest(ev)
    reps = manifest.get("replicates", 1)
    seed = args.seed if args.seed is not None else secrets.randbelow(2**31)
    rng = random.Random(seed)
    runs = []
    for sid, s in sorted(manifest["scenarios"].items()):
        for arm in ARMS:
            runs += [(sid, s["file"], arm, rep, 1) for rep in range(1, reps + 1)]
            runs.append((sid, s["file"], arm, rng.randint(1, reps), 2))
    rng.shuffle(runs)
    prompt = PROMPT.read_text()
    (out / "dispatch").mkdir(parents=True)
    packets: dict[str, dict] = {}
    reports: dict[tuple, dict] = {}
    for sid, sfile, arm, rep, grading_pass in runs:
        pid = secrets.token_hex(4)
        while pid in packets:
            pid = secrets.token_hex(4)
        # A repeat grades the same answer, so it shares the first packet's report.
        if (sfile, arm, rep) not in reports:
            try:
                reports[(sfile, arm, rep)] = run_grade(sfile, ev, arm, rep)
            except Refusal as r:
                fail(f"refusing: {r}")
        report = reports[(sfile, arm, rep)]
        answer = pathlib.Path(report["provenance"]["path"]).read_text()
        conditions = section(pathlib.Path(sfile).read_text(), "Failure conditions")
        text = prompt.rstrip("\n") + "\n\n" + packet_text(pid, conditions, report, answer)
        (out / "dispatch" / f"{pid}.txt").write_text(text)
        packets[pid] = {"scenario": sid, "scenario_file": sfile, "arm": arm, "replicate": rep,
                        "pass": grading_pass,
                        "condition_ids": [q["id"] for q in report["questions"]],
                        "answer_hash": report["answer_hash"],
                        "condition_hash": report["condition_hash"],
                        "dispatch_hash": h16(text)}
    grading = {"evidence": str(ev.resolve()), "grader_model": args.grader_model,
               "prompt_hash": h16(prompt), "seed": seed,
               "created": datetime.date.today().isoformat(), "packets": packets}
    (out / "grading.json").write_text(json.dumps(grading, indent=2) + "\n")
    repeats = sum(1 for p in packets.values() if p["pass"] == 2)
    print(f"prepared {len(packets)} packets in {out}: {len(packets) - repeats} answers, "
          f"{repeats} graded twice (seed {seed})")
    return 0


def cmd_log_dispatch(args) -> int:
    out = pathlib.Path(args.grading)
    grading = load_grading(out)
    if args.packet not in grading["packets"]:
        fail(f"refusing: unknown packet {args.packet}")
    log_dispatch(out / LOG_NAME, 2, packet_errors(grading), [args.packet], args.agent_id,
                 args.replace)
    print(f"logged packet {args.packet} -> {args.agent_id}")
    return 0


def extract_json(text: str):
    candidates = [text.strip(), *re.findall(r"```(?:json)?\s*\n(.*?)```", text, re.S)]
    if "{" in text and "}" in text:
        candidates.append(text[text.index("{"):text.rindex("}") + 1])
    for c in candidates:
        try:
            return json.loads(c)
        except ValueError:
            continue
    return None


def unquoted(quote: str, answer: str) -> list[str]:
    """Passages of `quote` that do not appear in `answer`, ignoring spacing."""
    flat = " ".join(answer.split())
    parts = [" ".join(p.split()).strip(" \"'`“”‘’")
             for p in re.split(r"\.\.\.|…", quote)]
    parts = [p for p in parts if p]
    return [p for p in parts if p not in flat] if parts else ["(no quoted text)"]


def collect_one(out: pathlib.Path, grading: dict, ev: pathlib.Path, manifest: dict, pid: str,
                agent: str, session: pathlib.Path, statuses: dict[str, str]) -> dict:
    packet = grading["packets"][pid]
    # Graders receive the whole packet, not just the prompt, so the packet is
    # what must be unchanged since prepare.
    dispatched = (out / "dispatch" / f"{pid}.txt").read_text()
    if h16(dispatched) != packet["dispatch_hash"]:
        raise Refusal("invalid", f"packet {pid} was edited after prepare; prepare a new "
                                 f"grading directory")
    body, tools = finished_reply(statuses, agent, transcript_for(session, agent), dispatched,
                                 f"packet {pid}")
    # A grader that used a tool could have read the key or another answer, so
    # its verdict is not blind.
    if tools:
        raise Refusal("invalid", f"grader {agent} used {tools} tool(s); graders must see only "
                                 f"their packet. Dispatch a new grader")
    reply = extract_json(body)
    judged = reply.get("judgements") if isinstance(reply, dict) else None
    if not isinstance(judged, dict):
        raise Refusal("invalid", f"grader {agent} did not reply with a judgements object")
    if set(judged) != set(packet["condition_ids"]):
        raise Refusal("invalid", f"grader {agent} judged {sorted(judged)}; the packet asks "
                                 f"for {packet['condition_ids']}")
    answer = recorded_answer(ev, manifest, packet)
    kept = {}
    for cid, j in judged.items():
        if not isinstance(j, dict) or j.get("verdict") not in ("pass", "fail"):
            raise Refusal("invalid", f"condition {cid}: verdict must be pass or fail")
        for field in ("reason", "evidence"):
            if not isinstance(j.get(field), str) or not j[field].strip():
                raise Refusal("invalid", f"condition {cid}: {field} is missing")
        missing = unquoted(j["evidence"], answer)
        if missing:
            raise Refusal("invalid", f"condition {cid}: evidence is not quoted from the "
                                     f"answer: {missing[0][:80]!r}")
        disputes = j.get("disputes", [])
        if not isinstance(disputes, list) or not all(isinstance(d, str) for d in disputes):
            raise Refusal("invalid", f"condition {cid}: disputes must be a list of check IDs")
        kept[cid] = {k: j[k] for k in ("verdict", "reason", "evidence", "disputes") if k in j}
    jpath = out / "judgements" / f"{pid}.json"
    jpath.write_text(json.dumps({
        "reviewer": f"{grading['grader_model']} grader, prompt {grading['prompt_hash']}",
        "answer_hash": packet["answer_hash"], "condition_hash": packet["condition_hash"],
        "judgements": kept, "packet": pid, "agent_id": agent}, indent=2) + "\n")
    try:
        return run_grade(packet["scenario_file"], ev, packet["arm"], packet["replicate"], jpath)
    except Refusal:
        jpath.unlink()
        raise


def cmd_collect(args) -> int:
    out = pathlib.Path(args.grading)
    grading = load_grading(out)
    if h16(PROMPT.read_text()) != grading["prompt_hash"]:
        fail("refusing: grader-prompt.md changed since prepare; grades from two prompts "
             "cannot be compared. Prepare a new grading directory")
    if not (out / LOG_NAME).is_file():
        fail(f"no {LOG_NAME} under {out}; log each dispatch with log-dispatch")
    counts = collections.Counter()
    todo = []
    for pid, agent in read_dispatch_log(out / LOG_NAME, 2, packet_errors(grading)):
        jpath, rpath = out / "judgements" / f"{pid}.json", out / "reports" / f"{pid}.json"
        if rpath.is_file() and jpath.is_file() and \
                json.loads(jpath.read_text()).get("agent_id") == agent:
            print(f"  already collected  {pid}")
            counts["already"] += 1
        else:
            todo.append((pid, agent))
    # Checking the batch and scanning the session are the costly part, and late
    # in a batch there is usually nothing left to collect.
    if todo:
        ev = pathlib.Path(grading["evidence"])
        require_current(ev)
        session = pathlib.Path(args.session)
        if not session.is_file():
            fail(f"refusing: session transcript {session} does not exist")
        manifest, statuses = load_manifest(ev), session_statuses(session)
        (out / "judgements").mkdir(exist_ok=True)
        (out / "reports").mkdir(exist_ok=True)
        for pid, agent in todo:
            try:
                report = collect_one(out, grading, ev, manifest, pid, agent, session, statuses)
            except Refusal as r:
                pending = r.kind == "pending"
                print(f"  {'pending' if pending else 'REFUSED':18} {pid}: {r}")
                counts["pending" if pending else "refused"] += 1
                continue
            (out / "reports" / f"{pid}.json").write_text(json.dumps(report, indent=2) + "\n")
            print(f"  collected          {pid}: {report['verdict']}")
            counts["collected"] += 1
    print(f"{counts['collected']} collected, {counts['already']} already collected, "
          f"{counts['pending']} pending, {counts['refused']} refused")
    if counts["refused"]:
        return 1
    return 2 if counts["pending"] else 0


def graded(out: pathlib.Path, pid: str) -> dict | None:
    """A collected packet's condition statuses, or None if it is not collected."""
    path = out / "reports" / f"{pid}.json"
    if not path.is_file():
        return None
    return {q["id"]: q["status"] for q in json.loads(path.read_text())["questions"]}


def by_answer(grading: dict):
    return sorted(grading["packets"].items(),
                  key=lambda kv: (kv[1]["scenario"], kv[1]["arm"], kv[1]["replicate"]))


def cmd_agree(args) -> int:
    out = pathlib.Path(args.grading)
    grading = load_grading(out)
    first = {(p["scenario"], p["arm"], p["replicate"]): pid
             for pid, p in grading["packets"].items() if p["pass"] == 1}
    per: dict[tuple, list[int]] = {}
    disagreements, missing = [], []
    for pid, p in by_answer(grading):
        if p["pass"] != 2:
            continue
        a = graded(out, first[(p["scenario"], p["arm"], p["replicate"])])
        b = graded(out, pid)
        if a is None or b is None:
            missing.append(pid)
            continue
        for cid in p["condition_ids"]:
            tally = per.setdefault((p["scenario"], cid), [0, 0])
            tally[1] += 1
            if a.get(cid) == b.get(cid):
                tally[0] += 1
            else:
                disagreements.append((p["scenario"], p["arm"], p["replicate"], cid,
                                      a.get(cid), b.get(cid)))
    print("| Scenario | Condition | Agreed |")
    print("| --- | --- | --- |")
    for (sid, cid), (agreed, total) in per.items():
        print(f"| {sid} | {cid} | {agreed}/{total} |")
    agreed, total = sum(t[0] for t in per.values()), sum(t[1] for t in per.values())
    print(f"\nOverall: {agreed}/{total} condition verdicts agreed.")
    for sid, arm, rep, cid, v1, v2 in disagreements:
        print(f"  disagreed: {sid} {arm} replicate {rep}, condition {cid}: {v1} then {v2}")
    if missing:
        print(f"\n{len(missing)} repeat(s) or their first grade not yet collected.")
        return 1
    return 0


def cmd_summary(args) -> int:
    out = pathlib.Path(args.grading)
    grading = load_grading(out)
    counts: dict[tuple, dict] = {}
    missing = 0
    for pid, p in by_answer(grading):
        if p["pass"] != 1:
            continue
        got = graded(out, pid)
        if got is None:
            missing += 1
            continue
        passed = {c: got.get(c) == "pass" for c in p["condition_ids"]}
        passed["all conditions"] = all(passed.values())
        for cid, ok in passed.items():
            tally = counts.setdefault((p["scenario"], cid), {a: [0, 0] for a in ARMS})[p["arm"]]
            tally[1] += 1
            tally[0] += ok
    print("| Scenario | Condition | Baseline passes | With-skill passes |")
    print("| --- | --- | --- | --- |")
    for (sid, cid), arms in counts.items():
        b, w = arms["baseline"], arms["with-skill"]
        print(f"| {sid} | {cid} | {b[0]}/{b[1]} | {w[0]}/{w[1]} |")
    if missing:
        print(f"\n{missing} packet(s) not yet collected; these counts are partial.")
        return 1
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("prepare")
    p.add_argument("evidence")
    p.add_argument("grading")
    p.add_argument("--grader-model", required=True)
    p.add_argument("--seed", type=int)
    p.set_defaults(fn=cmd_prepare)
    p = sub.add_parser("log-dispatch")
    p.add_argument("grading")
    p.add_argument("--packet", required=True)
    p.add_argument("--agent-id", required=True)
    p.add_argument("--replace", action="store_true")
    p.set_defaults(fn=cmd_log_dispatch)
    p = sub.add_parser("collect")
    p.add_argument("grading")
    p.add_argument("--session", required=True)
    p.set_defaults(fn=cmd_collect)
    for name, fn in (("agree", cmd_agree), ("summary", cmd_summary)):
        p = sub.add_parser(name)
        p.add_argument("grading")
        p.set_defaults(fn=fn)
    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    raise SystemExit(main())
