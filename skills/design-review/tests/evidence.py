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

A run is recorded only once the harness has said it finished. See
`agent_status` for why the transcript alone cannot say so.

Usage:
    evidence.py init <dir> --round N --model ID [--tests DIR] [--replicates R]
    evidence.py log-dispatch <dir> --scenario S07 --arm baseline|with-skill \
        --replicate N --agent-id ID [--replace]
    evidence.py record-log <dir> --session PARENT.jsonl
    evidence.py record <dir> --scenario S07 --arm baseline|with-skill \
        [--replicate N] --transcript agent-ID.jsonl [--session PARENT.jsonl]
    evidence.py check <dir> [--require-complete]

Run every command from the repository root: the manifest stores repository-
relative paths.

Exit 0 on success, 1 on refusal or expiry. record-log exits 2 when nothing was
refused but some logged runs are still generating. Nothing is written unless
every check passes.
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
LOG_NAME = "dispatch-log.tsv"
# Agent IDs become part of a file name, so nothing that could leave the
# directory is accepted.
AGENT_ID = re.compile(r"[A-Za-z0-9]{6,64}")
# Rows the harness writes. A model writes assistant rows, and anything it
# writes can contain the text of a notification.
HARNESS_ROW_TYPES = {"queue-operation", "attachment", "user"}


class Refusal(Exception):
    """A run that cannot be recorded. `kind` is pending, failed or invalid."""

    def __init__(self, kind: str, message: str):
        super().__init__(message)
        self.kind = kind


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
    save_manifest(ev, manifest)
    print(f"initialised {ev} — {len(scenarios)} scenarios, {len(snapshots)} skill snapshots")
    for sid, s in scenarios.items():
        print(f"  {sid}  loads {s['loads']:16} skill {s['skill_content_hash']}  "
              f"cond {s['condition_hash']}")
    return 0


def iter_rows(path: pathlib.Path):
    """Each parseable JSON row of a transcript, read one line at a time."""
    with open(path, errors="replace") as f:
        for line in f:
            if not line.strip():
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def first_user_text(path: pathlib.Path) -> str:
    """What the run was actually dispatched with."""
    for row in iter_rows(path):
        m = (row.get("message") or {}) if isinstance(row, dict) else {}
        if m.get("role") != "user":
            continue
        content = m.get("content")
        if isinstance(content, str):
            return content
        for c in content or []:
            if c.get("type") == "text":
                return c["text"]
    return ""


# Reasons that positively mean the turn stopped before it answered. A missing
# reason means nothing either way; see agent_status for why.
UNFINISHED_STOP_REASONS = {"tool_use", "max_tokens", "pause_turn"}


def read_transcript(path: pathlib.Path) -> tuple[str, int, bool]:
    """Final assistant text, how many tools the run used, and whether it ends on an answer.

    Whether the run finished is agent_status's question. This one is narrower:
    a run that ends on a tool call, or on a preamble beside one, has no answer
    to record even when the harness says it stopped.
    """
    ends_with_answer = False
    texts, tools = [], 0
    for line in path.read_text(errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            return (texts[-1] if texts else ""), tools, False
        m = row.get("message") or {}
        if m.get("role") == "user":
            ends_with_answer = False
        if m.get("role") != "assistant":
            continue
        content = m.get("content")
        if isinstance(content, str):
            texts.append(content)
            ends_with_answer = m.get("stop_reason") not in UNFINISHED_STOP_REASONS
            continue
        msg_text, msg_tool = False, False
        message_texts = []
        for c in content or []:
            if c.get("type") == "text":
                message_texts.append(c["text"])
                msg_text = True
            elif c.get("type") == "tool_use":
                tools += 1
                msg_tool = True
        if message_texts:
            texts.append("\n".join(message_texts))
        # A message carrying both a preamble and a tool call is a run still in
        # flight, not an answer. Treating any text as completion recorded four
        # of round 4's answers as their opening sentence.
        ends_with_answer = (msg_text and not msg_tool
                             and m.get("stop_reason") not in UNFINISHED_STOP_REASONS)
    return (texts[-1] if texts else ""), tools, ends_with_answer


def _strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for v in value.values():
            yield from _strings(v)
    elif isinstance(value, list):
        for v in value:
            yield from _strings(v)


def session_statuses(session: pathlib.Path) -> dict[str, str]:
    """Every agent's last reported status, from one pass over the session.

    The transcript cannot say whether a run finished. Claude Code writes each
    content block as it streams, before the stop reason arrives, so the final
    answer row usually has no stop_reason: 71 of 80 finished runs measured had
    none. The harness does say: when an agent stops it writes a task
    notification with a status into the dispatching session's transcript.

    Only a string that starts with the notification counts, and only its header
    before <result>. An agent's answer is quoted inside its own notification,
    so nothing it writes there can pass for another agent's status. A resumed
    agent notifies again, so the last status wins. The session grows with every
    notification, which is why it is read once rather than once per agent.
    """
    statuses: dict[str, str] = {}
    if not session.is_file():
        return statuses
    with open(session, errors="replace") as f:
        for line in f:
            if "<task-notification>" not in line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(row, dict) or row.get("type") not in HARNESS_ROW_TYPES:
                continue
            for text in _strings(row):
                head = text.lstrip()
                if not head.startswith("<task-notification>"):
                    continue
                head = head.split("<result>", 1)[0]
                tid = re.search(r"<task-id>([^<]*)</task-id>", head)
                st = re.search(r"<status>([^<]*)</status>", head)
                if tid and st:
                    statuses[tid.group(1).strip()] = st.group(1).strip()
    return statuses


def agent_status(session: pathlib.Path, agent_id: str) -> str | None:
    """The last status the harness reported for one agent, or None."""
    return session_statuses(session).get(agent_id)


def load_manifest(ev: pathlib.Path) -> dict:
    mpath = ev / "manifest.json"
    if not mpath.is_file():
        fail(f"no manifest under {ev}; run init first")
    manifest = json.loads(mpath.read_text())
    replicate_count(manifest.get("replicates", 1))
    return manifest


def save_manifest(ev: pathlib.Path, manifest: dict) -> None:
    (ev / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


def slot_key(arm: str, replicate: int, reps: int) -> str:
    return arm if reps == 1 else f"{arm}#{replicate}"


def slot_errors(manifest: dict, sid: str, arm: str, replicate) -> list[str]:
    """Why a slot cannot belong to this batch."""
    reps = manifest.get("replicates", 1)
    errors = []
    if sid not in manifest["scenarios"]:
        errors.append(f"unknown scenario {sid}")
    if arm not in ARMS:
        errors.append(f"unknown arm {arm}")
    if not str(replicate).isdigit() or not 1 <= int(replicate) <= reps:
        errors.append(f"replicate {replicate} is outside the batch's declared count of {reps}")
    return errors


def transcript_for(session: pathlib.Path, agent_id: str) -> pathlib.Path:
    """Where the harness keeps an agent's transcript: beside its parent session."""
    return session.parent / session.name.removesuffix(".jsonl") / "subagents" / f"agent-{agent_id}.jsonl"


def session_for(transcript: pathlib.Path) -> pathlib.Path | None:
    """The session that dispatched a transcript kept where the harness put it."""
    if transcript.parent.name != "subagents":
        return None
    parent = transcript.parent.parent
    return parent.parent / f"{parent.name}.jsonl"


def finished_reply(statuses: dict[str, str], agent_id: str, transcript: pathlib.Path,
                   dispatched: str, dispatched_name: str) -> tuple[str, int]:
    """The final reply and tool count of a run the harness says finished. Raises Refusal.

    Recording and grading both use this, so a lesson about what "finished" means
    lands once. `dispatched` is text the run's first message must contain.
    """
    status = statuses.get(agent_id)
    if status is None:
        raise Refusal("pending", f"no completion notification for agent {agent_id}: it is "
                                 f"still running, or this is not the session that dispatched it")
    if status != "completed":
        raise Refusal("failed", f"the harness reported agent {agent_id} {status}; dispatch it again")
    if not transcript.is_file():
        raise Refusal("invalid", f"{transcript} does not exist")
    body, tools, ends_with_answer = read_transcript(transcript)
    if not body.strip():
        raise Refusal("invalid", f"{transcript.name} carries no assistant answer")
    if not ends_with_answer:
        raise Refusal("invalid", f"{transcript.name} is incomplete — its last assistant "
                                 f"message is not an answer")
    if dispatched.strip() and dispatched.strip() not in first_user_text(transcript):
        raise Refusal("invalid", f"{transcript.name} was not dispatched with {dispatched_name}")
    return body, tools


def record_run(ev: pathlib.Path, manifest: dict, sid: str, arm: str, replicate: int,
               session: pathlib.Path, agent_id: str, transcript: pathlib.Path | None = None,
               statuses: dict[str, str] | None = None) -> str:
    """Record one run into `manifest` and write its answer. Raises Refusal.

    The transcript is found where the harness keeps it unless given. Pass
    `statuses` from session_statuses when recording many runs from one session.
    The caller saves the manifest, so a batch of runs is written once.
    """
    errors = slot_errors(manifest, sid, arm, replicate)
    if errors:
        raise Refusal("invalid", "; ".join(errors))
    transcript = transcript or transcript_for(session, agent_id)
    # The run must have been dispatched with the prompt this batch recorded. A
    # hand-assembled paste that drops a section leaves the answer looking valid
    # while it answers a different question — that is the S01 failure, and it
    # was caught last time only because a hash happened to be compared by hand.
    body, tools = finished_reply(
        statuses if statuses is not None else session_statuses(session), agent_id, transcript,
        (ev / f"{sid}-prompt.txt").read_text(), f"{sid}-prompt.txt")
    # A baseline that reached for the skill under test is not a baseline. This
    # is the S02 contamination, which was previously caught only by eye.
    if arm == "baseline" and tools > 0:
        raise Refusal("invalid", f"baseline is contaminated — {tools} tool use(s) in "
                                 f"{transcript.name}; dispatch a new run for this slot")
    key = slot_key(arm, replicate, manifest.get("replicates", 1))
    tgt = ev / "answers" / f"{sid}-{key.replace('#', '-')}.md"
    # Hash what is written, not what was parsed. Hashing the pre-normalized body
    # made `check` report every untouched answer as edited.
    normalized = body.rstrip("\n") + "\n"
    tgt.write_text(normalized)
    manifest["scenarios"][sid]["arms"][key] = {
        "answer": f"answers/{tgt.name}",
        "answer_hash": h16(normalized),
        "tool_uses": tools,
        "transcript": transcript.name,
        "agent_id": agent_id,
    }
    return key


def cmd_record(args) -> int:
    ev = pathlib.Path(args.dir)
    manifest = load_manifest(ev)
    transcript = pathlib.Path(args.transcript)
    m = re.fullmatch(rf"agent-({AGENT_ID.pattern})\.jsonl", transcript.name)
    if not m:
        fail(f"refusing: cannot tell which agent produced {transcript.name}; the "
             f"harness names transcripts agent-<id>.jsonl")
    session = pathlib.Path(args.session) if args.session else session_for(transcript)
    if session is None:
        fail(f"refusing: {transcript} is not under a session's subagents directory; "
             f"pass --session with the transcript of the session that dispatched it")
    try:
        key = record_run(ev, manifest, args.scenario, args.arm, args.replicate,
                         session, m.group(1), transcript=transcript)
    except Refusal as r:
        fail(f"refusing: {r}")
    save_manifest(ev, manifest)
    rec = manifest["scenarios"][args.scenario]["arms"][key]
    print(f"recorded {args.scenario} {key}: {rec['tool_uses']} tool uses")
    return 0


def read_dispatch_log(path: pathlib.Path, ncols: int, row_errors) -> list[list[str]]:
    """Every line of a dispatch log, validated as a whole before any is used.

    The last column is the agent ID and the others name what it was dispatched
    for. A half-applied log leaves a batch looking further along than the log
    that produced it, so one bad line refuses them all. A missing log is empty.
    """
    if not path.is_file():
        return []
    rows, errors, keys, agents = [], [], set(), set()
    for n, line in enumerate(path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        cols = line.split("\t")
        if len(cols) != ncols:
            errors.append(f"line {n}: expected {ncols} tab-separated columns, found {len(cols)}")
            continue
        *key, agent = cols
        errors += [f"line {n}: {e}" for e in row_errors(cols)]
        if not AGENT_ID.fullmatch(agent):
            errors.append(f"line {n}: agent ID {agent!r} is not a harness agent ID")
        if tuple(key) in keys:
            errors.append(f"line {n}: {' '.join(key)} is logged twice")
        if agent in agents:
            errors.append(f"line {n}: agent {agent} is logged twice")
        keys.add(tuple(key))
        agents.add(agent)
        rows.append(cols)
    if errors:
        fail("refusing: the dispatch log is malformed; nothing was used\n  " + "\n  ".join(errors))
    return rows


def log_dispatch(path: pathlib.Path, ncols: int, row_errors, key: list[str], agent_id: str,
                 replace: bool) -> None:
    """Add one dispatch to a log, or supersede the one already logged for `key`."""
    if not AGENT_ID.fullmatch(agent_id):
        fail(f"refusing: agent ID {agent_id!r} is not a harness agent ID")
    rows = read_dispatch_log(path, ncols, row_errors)
    if any(r[-1] == agent_id for r in rows):
        fail(f"refusing: agent {agent_id} is already in the log")
    prior = [i for i, r in enumerate(rows) if r[:-1] == key]
    if prior and not replace:
        fail(f"refusing: {' '.join(key)} was already dispatched as {rows[prior[0]][-1]}; "
             f"pass --replace to supersede it")
    if prior:
        rows[prior[0]] = [*key, agent_id]
    else:
        rows.append([*key, agent_id])
    path.write_text("".join("\t".join(r) + "\n" for r in rows))


def read_log(ev: pathlib.Path, manifest: dict) -> list[tuple[str, str, int, str]]:
    rows = read_dispatch_log(ev / LOG_NAME, 4, lambda c: slot_errors(manifest, *c[:3]))
    return [(sid, arm, int(rep), agent) for sid, arm, rep, agent in rows]


def cmd_log_dispatch(args) -> int:
    ev = pathlib.Path(args.dir)
    manifest = load_manifest(ev)
    errors = slot_errors(manifest, args.scenario, args.arm, args.replicate)
    if errors:
        fail("refusing: " + "; ".join(errors))
    log_dispatch(ev / LOG_NAME, 4, lambda c: slot_errors(manifest, *c[:3]),
                 [args.scenario, args.arm, str(args.replicate)], args.agent_id, args.replace)
    print(f"logged {args.scenario} {args.arm} {args.replicate} -> {args.agent_id}")
    return 0


def cmd_record_log(args) -> int:
    ev = pathlib.Path(args.dir)
    manifest = load_manifest(ev)
    if not (ev / LOG_NAME).is_file():
        fail(f"no {LOG_NAME} under {ev}; log each dispatch with log-dispatch")
    entries = read_log(ev, manifest)
    session = pathlib.Path(args.session)
    if not session.is_file():
        fail(f"refusing: session transcript {session} does not exist")
    statuses = session_statuses(session)
    reps = manifest.get("replicates", 1)
    counts = {"recorded": 0, "already": 0, "pending": 0, "refused": 0}
    for sid, arm, rep, agent in entries:
        label = f"{sid} {slot_key(arm, rep, reps)}"
        prior = manifest["scenarios"][sid]["arms"].get(slot_key(arm, rep, reps))
        if prior and prior.get("agent_id") == agent:
            print(f"  already recorded  {label}")
            counts["already"] += 1
            continue
        try:
            record_run(ev, manifest, sid, arm, rep, session, agent, statuses=statuses)
        except Refusal as r:
            kind = "pending" if r.kind == "pending" else "refused"
            print(f"  {'pending' if kind == 'pending' else 'REFUSED':17} {label}: {r}")
            counts[kind] += 1
            continue
        counts["recorded"] += 1
        print(f"  {'replaced' if prior else 'recorded':17} {label} from agent {agent}")
    if counts["recorded"]:
        save_manifest(ev, manifest)
    print(f"{counts['recorded']} recorded, {counts['already']} already recorded, "
          f"{counts['pending']} pending, {counts['refused']} refused")
    if counts["refused"]:
        return 1
    return 2 if counts["pending"] else 0


def cmd_check(args) -> int:
    ev = pathlib.Path(args.dir)
    manifest = load_manifest(ev)
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
            reps = manifest.get("replicates", 1)
            want = [slot_key(a, i, reps) for a in ARMS for i in range(1, reps + 1)]
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

    p = sub.add_parser("log-dispatch")
    p.add_argument("dir")
    p.add_argument("--scenario", required=True)
    p.add_argument("--arm", required=True, choices=list(ARMS))
    p.add_argument("--replicate", type=int, required=True)
    p.add_argument("--agent-id", required=True)
    p.add_argument("--replace", action="store_true")
    p.set_defaults(fn=cmd_log_dispatch)

    p = sub.add_parser("record-log")
    p.add_argument("dir")
    p.add_argument("--session", required=True)
    p.set_defaults(fn=cmd_record_log)

    p = sub.add_parser("record")
    p.add_argument("dir")
    p.add_argument("--scenario", required=True)
    p.add_argument("--arm", required=True, choices=list(ARMS))
    p.add_argument("--replicate", type=int, default=1)
    p.add_argument("--transcript", required=True)
    p.add_argument("--session")
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
