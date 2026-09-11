#!/usr/bin/env python3
"""Read-only build94 preparation checks; no app calls."""
import copy
import hashlib
import math
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/console-height'


def main():
    load = lambda name: json.loads((OUT / 'baseline' / (name + '.json')).read_text())
    package = load('package'); origin = load('fixture-origin'); initial = load('fixture-initial')
    evidence = Path(origin['sourceEvidence'])
    assert hashlib.sha256(evidence.read_bytes()).hexdigest() == origin['sourceEvidenceSHA256']
    original = json.loads(evidence.read_text())['manifest']
    assert original['id'] == origin['sourceProjectID'] != initial['id'] == package['projectID']
    original['id'] = initial['id']
    assert original == initial and initial['musicRevision'] == origin['sourceRevision'] == 62
    fixture = Path(package['fixture']); source = fixture.with_name('studio.circlr')
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256'] == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assert len(initial['assets']) == 2
    for asset in initial['assets']:
        path = Path(asset['path'])
        assert not path.is_absolute() and '..' not in path.parts
        for directory in [fixture, source]:
            assert hashlib.sha256((directory / path).read_bytes()).hexdigest() == asset['checksum']
    native(initial, package)



def music(value):
    value = copy.deepcopy(value)
    value.pop('hierarchyView', None); value.pop('musicRevision', None)
    colors = value.get('circleColors')
    if colors is not None:
        assert len(colors) % 2 == 0
        value['circleColors'] = {json.dumps(colors[i], sort_keys=True): colors[i+1] for i in range(0, len(colors), 2)}
        assert len(value['circleColors']) * 2 == len(colors)
    return value


def native(initial, package):
    heights = {'before': 192.5, 'compact': 110.5, 'drag-maximum': 250.5, 'drag-minimum': 110.5,
               'key-large': 250.5, 'key-default': 192.5, 'collapsed': 34, 'expanded': 110.5,
               'log-scrolled': 110.5, 'router': 110.5, 'audio-returned': 110.5, 'command-executed': 110.5, 'saved': 110.5, 'reopened': 110.5}
    names = ['baseline/before', 'final/before', 'final/compact', 'final/menu-compact']
    names += ['final-shortcuts/' + n for n in heights]
    captures = {n: json.loads((OUT / (n + '.json')).read_text()) for n in names}
    latest = json.loads((OUT / 'final-shortcuts/package.json').read_text())
    assert 'B3A0BC3E-3D1A-3A77-A9FB-37DED0608EB3' in latest['uuid']
    for name, capture in captures.items():
        state = capture['state']
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
        assert state['runtime']['build'] == ('93' if name.startswith('baseline/') else '94')
        assert state['projectID'] == capture['manifest']['id'] == package['projectID'] == latest['projectID']
        assert state['path'] == package['fixture'] and not state['dirty']
        assert state['revision'] == capture['manifest']['musicRevision'] == 62
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['playback']['playing'] and not any(state['recording'][k] for k in ['audio', 'midi', 'busy'])
        assert music(capture['manifest']) == music(initial), name
        h = heights[name.split('/')[1]] if name.startswith('final-shortcuts/') else (110.5 if name == 'final/menu-compact' else 192.5)
        assert state['view']['consoleBounds'] == [20, 655-h, 794, h], name
        assert state['view']['consoleOpen'] == (name != 'final-shortcuts/collapsed')
        assert math.isclose(state['view']['zoom'], captures['final-shortcuts/before']['state']['view']['zoom'], abs_tol=1e-10, rel_tol=0), name
    assert captures['final-shortcuts/before']['state']['view']['consoleBounds'][3] - captures['final-shortcuts/compact']['state']['view']['consoleBounds'][3] == 82
    saved = captures['final-shortcuts/saved']['manifest']
    assert saved == captures['final-shortcuts/reopened']['manifest']
    assert json.loads((Path(package['fixture']) / 'manifest.json').read_text()) == saved
    job = json.loads((OUT / 'final-shortcuts/reopen-job.json').read_text())
    assert job['revision'] == 62 and job['job']['kind'] == 'open'
    assert job['job']['state'] == 'completed' and job['job']['path'] == package['fixture']
    draft_names = ['compact', 'drag-maximum', 'drag-minimum', 'key-large', 'key-default',
                   'expanded', 'log-scrolled', 'router', 'audio-returned']
    for name in draft_names:
        text = (OUT / 'final-shortcuts' / (name + '.ax.txt')).read_text()
        assert 'text field (settable) Value: state, Placeholder:' in text, name
    executed = (OUT / 'final-shortcuts/command-executed.ax.txt').read_text()
    assert '콘솔 > state' in executed and 'r62 · 3트랙 · 2섹션' in executed
    assert 'text field (settable) Value: state, Placeholder:' not in executed
    print(json.dumps({'status': 'passed', 'baselineSnapshots': 1, 'initialCandidateSnapshots': 3,
                      'finalCandidateSnapshots': len(heights), 'candidateAXChecked': len(draft_names)+1,
                      'preservedAssets': 2, 'physicalAudioAttempts': 0, 'consoleHeightReduction': 82,
                      'packageUUID': latest['uuid']}, ensure_ascii=False))



if __name__ == "__main__":
    main()
