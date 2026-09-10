#!/usr/bin/env python3
"""Execute fixture checks and expose unresolved artifact judgements.

Exit 0: every condition has supported pass evidence. 1: a supported failure.
2: judgement remains open. 3: invalid input. This never edits Results or archives.
"""
from __future__ import annotations
import argparse
import json
import pathlib
import re
import sys

from evidence import h16, section, replicate_count
from grade_eval import Evaluator


def fences(text, language='python'):
    return re.findall(r'^\s*```' + language + r'[^\n]*\n(.*?)^\s*```\s*$', text, re.M | re.S)


def tables(text):
    result, current = [], []
    for line in text.splitlines() + ['']:
        if line.lstrip().startswith('|'):
            current.append(line)
        elif current:
            result.append('\n'.join(current)); current = []
    return result


def mechanical_s05(answer):
    checks = []
    patterns = {
        'banned-words': r'\b(?:PASS|N/A|OK|no issue|nothing to flag|clean)\b',
        'silent-checks': r'\b(?:Variation|Direction|Lifetime|Surface)\b',
    }
    for name, pattern in patterns.items():
        matches = [{'text': m[0], 'line': answer.count('\n', 0, m.start()) + 1,
                    'context': answer.splitlines()[answer.count('\n', 0, m.start())]}
                   for m in re.finditer(pattern, answer, re.I)]
        checks.append({'id': 'S05.' + name, 'kind': 'lexical-scan',
            'status': 'did-not-hold' if matches else 'held', 'matches': matches,
            'expression': 'absence of ' + name,
            'detail': 'Executed text scan. Context and equivalent wording require human judgement.'})
    # These are literal coverage cues, not semantic proof of a concrete resolution.
    for rule, words in {'2': ['pricing', 'delivery', 'taxes.round_line_tax', 'adjustments'],
                        '3': ['receipt_text', 'refund_text', 'third', 'home']}.items():
        missing = [w for w in words if w not in answer.lower()]
        checks.append({'id': 'S05.rule' + rule + '-cues', 'kind': 'lexical-scan',
            'status': 'could-not-evaluate' if missing else 'held', 'missing': missing,
            'expression': 'literal decision cues',
            'detail': 'Missing cues may be paraphrased; present cues do not prove the decision. Human must verify.'})
    return checks


def load_answer(args, sid):
    if args.answer:
        answer = args.answer.read_text()
        return answer, {'path': str(args.answer), 'answer_hash': h16(answer), 'source': 'file'}
    manifest = json.loads((args.evidence / 'manifest.json').read_text())
    reps = replicate_count(manifest.get('replicates', 1))
    if not args.arm or not 1 <= args.replicate <= reps:
        raise ValueError('evidence selection needs an arm and a valid replicate')
    key = args.arm if reps == 1 else f'{args.arm}#{args.replicate}'
    scenario = manifest['scenarios'][sid]
    record = scenario['arms'][key]
    path = (args.evidence / record['answer']).resolve()
    if not path.is_relative_to(args.evidence.resolve()):
        raise ValueError('answer path escapes evidence directory')
    answer = path.read_text()
    if not answer.strip() or h16(answer) != record['answer_hash']:
        raise ValueError('recorded answer is empty or its hash does not match')
    return answer, {'source': 'manifest', 'round': manifest['round'], 'model': manifest['model'],
        'arm': key, 'path': str(path), 'answer_hash': h16(answer),
        'prompt_hash': scenario['prompt_hash'], 'condition_hash': scenario['condition_hash'],
        'skill_content_hash': scenario['skill_content_hash']}


def build_report(scenario, answer, provenance, production, judgements=None):
    sid = 'S' + scenario.name[1:3]
    condition_text = section(scenario.read_text(), 'Failure conditions')
    if not condition_text:
        raise ValueError('scenario has no Failure conditions')
    conditions = list(re.finditer(r'^(\d+[a-z]?)\.\s+\*\*([^*]+)\*\*', condition_text, re.M))
    if not conditions:
        raise ValueError('scenario has no numbered failure conditions')
    defaults = ['previous_day_window', 'in_window', 'account_timezone'] if sid == 'S07' else []
    checks = Evaluator(defaults + production).run(fences(answer))
    if sid == 'S05':
        checks.extend(mechanical_s05(answer))
    evidence = {'tables': tables(answer), 'python': fences(answer),
                'diagrams': fences(answer, 'mermaid'), 'diffs': fences(answer, 'diff'),
                'answer': answer}
    questions = []
    for i, condition in enumerate(conditions):
        end = conditions[i+1].start() if i+1 < len(conditions) else len(condition_text)
        questions.append({'id': condition[1], 'title': condition[2].strip(' —'),
            'question': condition_text[condition.start():end].strip(),
            'status': 'open', 'evidence': evidence})
    if sid == 'S07' and any(c['kind'] == 'fixture-assertion' and c['status'] == 'did-not-hold' for c in checks):
        next(q for q in questions if q['id'] == '3').update(status='fail',
            basis='executed fixture assertion did not hold',
            check_ids=[c['id'] for c in checks if c['status'] == 'did-not-hold'])
    if not answer.strip():
        checks.append({'id': 'artifact-present', 'kind': 'text-scan', 'status': 'did-not-hold',
                       'expression': 'answer contains a required artifact', 'detail': 'answer is empty'})
        for q in questions:
            q.update(status='fail', basis='executed empty-artifact check')
    result = {'scenario': sid, 'provenance': provenance, 'answer_hash': h16(answer),
        'condition_hash': h16(condition_text), 'checks': checks, 'questions': questions,
        'limitations': ['Pure fixture expressions only; production code and pytest fixtures are never run.',
            'Unknown imports, host timezone, unsupported control flow and missing inputs remain evaluation gaps.',
            'Lexical matches are facts for a grader; context, paraphrases and design placement need human judgement.',
            'A held fixture guard proves a prerequisite, not mutation discrimination or a scenario pass.']}
    if judgements is not None:
        if not judgements.get('reviewer', '').strip() or any(judgements.get(k) != result[k]
                for k in ('answer_hash', 'condition_hash')):
            raise ValueError('judgements require reviewer and matching answer_hash and condition_hash')
        by_id = {q['id']: q for q in questions}
        for key, judgement in judgements.get('judgements', {}).items():
            if key not in by_id or judgement.get('verdict') not in ('pass', 'fail') \
                    or not judgement.get('reason', '').strip() or not judgement.get('evidence', '').strip():
                raise ValueError('each judgement needs a known condition, pass/fail, reason and extracted evidence')
            q = by_id[key]
            if q['status'] == 'fail' and judgement['verdict'] == 'pass':
                # An executed failure is not waved away, but it can be disputed.
                # S07 asks the answer to diagnose a supplied broken guard, so a
                # correct answer quotes that guard, and the evaluator cannot tell
                # quoted code from authored code. Dissent is allowed only when it
                # names the checks it disputes, and they actually failed.
                failed = {c['id'] for c in checks if c['status'] == 'did-not-hold'}
                disputed = judgement.get('disputes') or []
                if not disputed or not set(disputed) <= failed:
                    raise ValueError('overriding an executed failure requires "disputes" '
                                     'naming the failing check ids it disputes')
                q['overrides'] = list(disputed)
            q.update(status=judgement['verdict'], human={'reviewer': judgements['reviewer'], **judgement})
    result['verdict'] = ('fail' if any(q['status']=='fail' for q in questions) else
                         'pass' if all(q['status']=='pass' for q in questions) else 'open')
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--scenario', type=pathlib.Path, required=True)
    source = p.add_mutually_exclusive_group(required=True)
    source.add_argument('--answer', type=pathlib.Path)
    source.add_argument('--evidence', type=pathlib.Path)
    p.add_argument('--arm', choices=['baseline', 'with-skill'])
    p.add_argument('--replicate', type=int, default=1)
    p.add_argument('--production', action='append', default=[], help='additional production call name')
    p.add_argument('--judgements', type=pathlib.Path)
    p.add_argument('--json', action='store_true')
    args = p.parse_args()
    try:
        answer, provenance = load_answer(args, 'S' + args.scenario.name[1:3])
        condition_hash = h16(section(args.scenario.read_text(), 'Failure conditions'))
        if provenance.get('condition_hash', condition_hash) != condition_hash:
            raise ValueError('recorded conditions differ; select the archived scenario revision')
        result = build_report(args.scenario, answer, provenance, args.production,
                              json.loads(args.judgements.read_text()) if args.judgements else None)
    except (ValueError, KeyError, OSError) as exc:
        print(str(exc), file=sys.stderr); return 3
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"{result['scenario']}: {result['verdict']}\nAnswer: {result['answer_hash']}  Conditions: {result['condition_hash']}")
        for check in result['checks']:
            print(f"{check['id']}: {check['status']} — {check['expression']}\n  {check['detail']}")
            for match in check.get('matches', []):
                print(f"  line {match['line']}: {match['context']}")
        for question in result['questions']:
            print(f"\n{question['id']}: {question['status']} — {question['question']}")
            if 'human' in question:
                print('Human judgement: ' + json.dumps(question['human']))
            print('Extracted tables:\n' + '\n\n'.join(question['evidence']['tables']))
        print('\nAnswer evidence:\n' + answer)
        print('\nLimits:\n' + '\n'.join(result['limitations']))
    return {'pass': 0, 'fail': 1, 'open': 2}[result['verdict']]


if __name__ == '__main__':
    raise SystemExit(main())
