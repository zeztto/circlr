#!/usr/bin/env python3
"""Read-only build113 rapid arrangement input evidence; incomplete captures fail closed."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/arrangement-input'
spec = importlib.util.spec_from_file_location('continuation_checks', Path(__file__).with_name('check-arrangement-continuation-evidence.py'))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c = base.c


def load(path):
    return json.loads(path.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', default='final')
    args = parser.parse_args()
    assert args.candidate == 'final'
    final = OUT / args.candidate
    seed = load(OUT / 'baseline/fixture-initial.json')
    scenario = load(OUT / 'baseline/scenario.json')
    package = load(final / 'package.json')
    assert package['build'] == '113' and seed['musicRevision'] == 14
    assert hashlib.sha256(Path(scenario['sourceSeed']).read_bytes()).hexdigest() == scenario['sourceSeedSHA256']
    source_seed = load(Path(scenario['sourceSeed']))
    source_seed.update(id=seed['id'], name='편곡 입력 즉시 반응 검증')
    assert source_seed == seed, 'Only project ID and name may differ from build112 seed'
    original = c.music(seed)
    revisions = {'before':17, 'rapid-cloned':18, 'continued':18, 'rapid-renamed':18,
                 'cancelled':18, 'rename-undo':19, 'clone-undo':20,
                 'restored':20, 'reopened':20}
    captures = {name:load(final / (name + '.json')) for name in revisions}
    source_id = scenario['currentArrangementID']
    owner_id = next(o['id'] for o in seed['album']['compositions'] if source_id in o['arrangementIDs'])
    cloned, mapping = base.duplicate_expected(seed, captures['rapid-cloned']['manifest'],
                                             source_id, owner_id, '빠른 복제 대안')
    renamed = copy.deepcopy(cloned)
    renamed['arrangements'][-1]['name'] = '빠른 이름 변경'
    for name, capture in captures.items():
        c.guard(capture, package, revisions[name])
        expected = original
        if name in ['rapid-cloned', 'continued', 'rename-undo']: expected = cloned
        elif name in ['rapid-renamed', 'cancelled']: expected = renamed
        assert c.music(capture['manifest']) == expected, name
    continued = captures['continued']
    assert continued['state']['selection']['music'] == dict(arrangementID=cloned['activeArrangementID'],
        useID=mapping[scenario['targetUseID']], nodeID=scenario['nodeID'])
    expected_workspace = copy.deepcopy(captures['before']['manifest']['hierarchyView']['workspace'])
    expected_workspace['original'] = False
    expected_workspace.pop('connection', None)
    expected_workspace.pop('transitionID', None)
    assert continued['manifest']['hierarchyView']['workspace'] == expected_workspace
    for name, value in [('rapid-duplicate-input', '빠른 복제 대안'), ('rapid-rename-input', '빠른 이름 변경')]:
        text = (final / (name + '.ax.txt')).read_text()
        focus = text.split('The focused UI element is')[-1]
        assert 'text field' in focus and ('Value: ' + value) in focus
        assert ('Description: 새 편곡안 이름' if name == 'rapid-duplicate-input' else 'Description: 현재 편곡안 이름') in focus
    candidate_ax = (final / 'rapid-candidate-input.ax.txt').read_text()
    assert '복제 원본 · #2 · 다른 후보 · 이어 편집 없음' in candidate_ax
    assert '1개 결과' in candidate_ax
    focus = candidate_ax.split('The focused UI element is')[-1]
    assert 'Description: 새 편곡안 이름' in focus and 'Value: 두 번째 후보 확인' in focus
    cancelled_ax = (final / 'cancelled.ax.txt').read_text()
    focus = cancelled_ax.split('The focused UI element is')[-1]
    assert 'Description: 편곡안 검색' in focus and 'Value: #2' in focus
    assert 'Description: 새 편곡안 이름' not in cancelled_ax
    reset_ax = (final / 'reset.ax.txt').read_text()
    focus = reset_ax.split('The focused UI element is')[-1]
    assert 'Description: 편곡안 검색' in focus and 'Value:' not in focus
    assert '3개 결과' in reset_ax
    for name in ['before', 'rapid-duplicate-input', 'rapid-rename-input', 'continued',
                 'rapid-candidate-input', 'cancelled', 'reset']:
        assert (final / (name + '.jpg')).read_bytes().startswith(b'\xff\xd8\xff')
    injection = load(final / 'qa-injection.json')
    assert injection['candidate'] == args.candidate and injection['qaOnlyMock'] and injection['denyOutput']
    assert injection['outputWorkerExit'] == 78 and injection['strictSignatureVerified']
    assert set(injection['productionHelperSHA256']) == set(injection['packagedHelperSHA256']) == {
        'circlr-output-worker', 'circlr-au-effect-worker', 'circlr-au-instrument-worker', 'circlr-output-device-catalog'}
    for helper, digest in injection['packagedHelperSHA256'].items():
        assert hashlib.sha256((Path(package['app']) / 'Contents/MacOS' / helper).read_bytes()).hexdigest() == digest
        if helper != 'circlr-output-worker': assert injection['productionHelperSHA256'][helper] == digest
    assert hashlib.sha256(Path(injection['preservedOutputWorker']).read_bytes()).hexdigest() == injection['productionHelperSHA256']['circlr-output-worker']
    stub = final / 'deny-output.c'
    assert hashlib.sha256(stub.read_bytes()).hexdigest() == injection['stubSourceSHA256']
    assert stub.read_text().strip() == 'int main(void){return 78;}'
    source = Path(scenario['source'])
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == scenario['sourceSHA256']
    fixture = Path(package['fixture'])
    for asset in seed['assets']:
        relative = Path(asset['path'])
        assert relative.parts and not relative.is_absolute() and '..' not in relative.parts
        for root in [fixture, source]:
            assert hashlib.sha256((root / relative).read_bytes()).hexdigest() == asset['checksum']
    assert captures['restored']['manifest'] == captures['reopened']['manifest'] == load(fixture / 'manifest.json')
    job = captures['reopened']['state']['job']
    assert job['kind'] == 'open' and job['state'] == 'completed' and job['path'] == str(fixture) and job['progress'] == 1
    print(json.dumps(dict(status='passed', candidate=args.candidate, snapshots=len(captures),
        exactClone=True, exactRename=True, candidateBInputAndCancelVerified=True, candidateBCommitVerified=False, resetAXOnly=True, continuationPreserved=True, strictUndoMusic=True,
        strictReopenEquality=True, assets=2, physicalAudioAttempts=0, koreanIMECompositionVerified=False)))


if __name__ == '__main__':
    main()
