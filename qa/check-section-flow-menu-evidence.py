#!/usr/bin/env python3
"""Check stored build98 state transitions; AX hover is never evidence of a checkmark."""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/section-flow-menu'


def main():
    load = lambda n: json.loads((OUT / (n + '.json')).read_text())
    package = load('package'); end_package = load('end-package'); scenario = load('scenario')
    captures = {n: load(n) for n in ['before', 'single-selected', 'end-selected', 'end-undo']}
    initial = load('end-initial')
    assert captures['before']['manifest'] == captures['single-selected']['manifest']
    arrangement = next(a for a in captures['before']['manifest']['arrangements'] if a['id'] == scenario['arrangementID'])
    assert arrangement['chosenEdges'] == {}
    assert not next(u for u in arrangement['uses'] if u['id'] == scenario['fromUseID'])['isEnd']
    assert [e['id'] for e in arrangement['edges'] if e['from'] == scenario['fromUseID']] == [scenario['edgeID']]
    expected = copy.deepcopy(initial)
    arrangement = next(a for a in expected['arrangements'] if a['id'] == scenario['arrangementID'])
    use = next(u for u in arrangement['uses'] if u['id'] == scenario['fromUseID'])
    assert use['isEnd'] and arrangement['chosenEdges'][use['id']] == scenario['edgeID']
    use['isEnd'] = False; expected['musicRevision'] += 1
    assert captures['end-selected']['manifest'] == expected
    expected = copy.deepcopy(initial); expected['musicRevision'] += 2
    assert captures['end-undo']['manifest'] == expected
    for name, capture in captures.items():
        pkg = end_package if name.startswith('end-') else package
        state = capture['state']; manifest = capture['manifest']
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa' and state['runtime']['build'] == pkg['build'] == '98'
        assert state['projectID'] == manifest['id'] == pkg['projectID']
        assert state['path'] == pkg['fixture'] and not state['dirty']
        assert state['revision'] == manifest['musicRevision'] == {'before':14,'single-selected':14,'end-selected':15,'end-undo':16}[name]
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['playback']['playing'] and not any(state['recording'][k] for k in ['audio','midi','busy'])
        assert len(manifest['assets']) == 2
        for asset in manifest['assets']:
            path = Path(asset['path'])
            assert not path.is_absolute() and '..' not in path.parts
            assert hashlib.sha256((Path(pkg['fixture']) / path).read_bytes()).hexdigest() == asset['checksum']
    source = Path(package['fixture']).with_name('studio.circlr')
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256'] == end_package['sourceSHA256'] == scenario['sourceSHA256']
    for asset in captures['before']['manifest']['assets']:
        assert hashlib.sha256((source / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    assert '끝 해제 후 재생할 연결' in (OUT / 'end-menu.ax.txt').read_text()
    print(json.dumps({'status':'passed','snapshots':4,'preservedAssets':2,'physicalAudioAttempts':0,
                      'checkmarkVisualVerified':False,'menuCopyAXChecked':True},ensure_ascii=False))


if __name__ == '__main__':
    main()
