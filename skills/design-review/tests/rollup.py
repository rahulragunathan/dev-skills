#!/usr/bin/env python3
"""Render the latest recorded batch per scenario, without pooling revisions or grading."""
import argparse
import pathlib
import re
from write_results import split_row, validate_table, join_row

UNITS = {'S01': [('D1', ['Responsibility']), ('D2', ['Direction'])],
         'S02': [('D3', ['Lifetime']), ('D4', ['Surface'])],
         'S03': [('D5', ['Under side', 'Over side'])],
         'S04': [('D6', ['Outcome'])],
         'S05': [(f'R{i}', [f'Rule {i}']) for i in range(1,5)],
         'S06': [('G1', ['Diagrams']), ('G2', ['Outcome'])],
         'S07': [('P1', ['Skip/partial']), ('P2', ['Mutation', 'Mutation choice']), ('P3', ['Fixture'])]}


def tally(cell):
    count = re.search(r'\((\d+/\d+)\)', cell)
    if count:
        return count[1]
    if 'Rule works' in cell or 'Rule not needed here' in cell:
        return '1/1'
    if 'Rule needed' in cell or 'Rule ineffective' in cell:
        return '0/1'
    return 'ungraded'


def render(tests):
    table = [join_row(['Unit', 'Scenario / batch', 'Without skill: observed passes', 'With skill: observed passes']),
             join_row(['---'] * 4)]
    revisions = [join_row(['Scenario', 'Prompt hash', 'Condition hash', 'Loaded skill hash', 'Record applicability']),
                 join_row(['---'] * 5)]
    for path in sorted(tests.glob('s0*.md')):
        sid = 'S' + path.name[1:3]
        lines = path.read_text().splitlines(True)
        h, headers = validate_table(lines)
        rows = []
        for line in lines[h+2:]:
            if not line.startswith('|'):
                break
            row = dict(zip(headers, split_row(line)))
            row['_round'] = int(re.search(r'round (\d+)', row['Run'])[1])
            rows.append(row)
        latest = max(r['_round'] for r in rows)
        rows = [r for r in rows if r['_round'] == latest]
        arms = []
        for prefix in ('Without skill', 'With skill'):
            found = [r for r in rows if r['Run'].startswith(prefix)]
            if len(found) != 1:
                raise ValueError(f'{sid}: latest batch must have one aggregate row per arm')
            arms.append(found[0])
        for unit, columns in UNITS[sid]:
            table.append(join_row([unit, f'[{sid}]({path.name}#results) / round {latest}'] +
                ['; '.join(c + ': ' + tally(r[c]) for c in columns) for r in arms]))
        def hash_of(cell):
            hashes = re.findall(r'\b[0-9a-f]{16}\b', cell)
            if len(hashes) != 1:
                raise ValueError(f'{sid}: ambiguous revision: {cell}')
            return hashes[0]
        if any(hash_of(arms[0][c]) != hash_of(arms[1][c]) for c in ['Prompt revision', 'Condition revision']):
            raise ValueError(f'{sid}: latest arms have different fixture revisions')
        revisions.append(join_row([sid, '`'+hash_of(arms[0]['Prompt revision'])+'`',
            '`'+hash_of(arms[0]['Condition revision'])+'`', '`'+hash_of(arms[1]['Skill git SHA · content'])+'`',
            '; '.join(r['Evidence status'] for r in arms)]))
    return ''.join(table) + '\n' + ''.join(revisions)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tests', type=pathlib.Path, default=pathlib.Path(__file__).parent)
    print(render(parser.parse_args().tests), end='')
