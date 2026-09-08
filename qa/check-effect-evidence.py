#!/usr/bin/env python3
"""Read recorded native effect-editing evidence and verify the final package. No app writes."""
from pathlib import Path
import hashlib
import importlib.util
import json
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/effect-editing'
FIELDS = ['name', 'tracks', 'assets', 'sections', 'arrangements', 'signal', 'patterns', 'portLayout']


def read(name):
    return json.loads((OUT / (name + '.json')).read_text())


def effect(name):
    nodes = read(name)['manifest']['arrangements'][0]['uses'][0]['graphEdits']['addedNodes']
    return next(n['content']['effect']['_0'] for n in nodes if n['name'] == '검증 필터')


def same(first, second):
    a, b = read(first)['manifest'], read(second)['manifest']
    for field in FIELDS:
        assert a[field] == b[field], (first, second, field)


def main():
    assert read('typed')['state']['revision'] == read('initial')['state']['revision']
    assert read('committed')['state']['revision'] == read('initial')['state']['revision'] + 1
    assert abs(40 * 500 ** effect('committed')['amount'] - 1200) < 1e-8
    same('committed', 'invalid')
    same('initial', 'undo-number')
    assert '범위: 40–20,000 Hz' in (OUT / 'invalid-ax.txt').read_text()
    assert read('escaped')['state']['playback']['editorAddress'] == read('committed')['state']['playback']['editorAddress']
    for prefix in ['', 'keyboard-']:
        same(prefix + 'external', prefix + 'stale')
        assert read(prefix + 'external')['state']['revision'] == read(prefix + 'stale')['state']['revision']
        assert '효과가 변경되었습니다' in (OUT / (prefix + 'stale-ax.txt')).read_text()
    compressor = effect('keyboard-ratio')
    assert compressor['kind'] == 'compressor' and compressor['amount'] == 0.6 and compressor['secondary'] == 0.2
    assert read('keyboard-ratio')['state']['revision'] == read('keyboard-compressor')['state']['revision'] + 2
    assert '4.5' in (OUT / 'keyboard-tab-ax.txt').read_text()
    assert effect('keyboard-undo-ratio')['secondary'] == 0.25 and effect('keyboard-undo-ratio')['amount'] == 0.6
    for first, second in [('keyboard-ratio', 'keyboard-undo-external'), ('keyboard-compressor', 'keyboard-undo-threshold'),
                          ('keyboard-before', 'keyboard-restored'), ('mouse-active-drag', 'mouse-undo-key'),
                          ('mouse-before', 'mouse-restored'), ('initial', 'mouse-restored'), ('initial', 'reopened')]:
        same(first, second)
    assert read('mouse-active-drag')['state']['revision'] == read('mouse-before')['state']['revision'] + 1
    assert effect('mouse-active-drag')['amount'] > 0.7
    assert read('mouse-key')['state']['revision'] == read('mouse-active-drag')['state']['revision'] + 1
    assert abs(effect('mouse-key')['amount'] - effect('mouse-active-drag')['amount'] - 0.01) < 1e-10
    assert read('mouse-key')['state']['selection'] == read('mouse-before')['state']['selection']
    assert 'Details: 894.427 Hz' in (OUT / 'final-before-ax.txt').read_text()
    au = (OUT / 'audio-unit-ax.txt').read_text()
    assert 'Value: Audio Unit' in au and '슬라이더' not in au and 'Amount' not in au
    # Inactive-window drag attempts were no-ops; they are not successful drag evidence.
    assert read('mouse-drag')['state']['revision'] == read('mouse-before')['state']['revision']
    assert not read('reopened')['state']['dirty'] and read('reopened')['state']['job']['state'] == 'completed'
    package = read('mouse/package')
    snapshots = []
    for path in OUT.glob('*.json'):
        data = json.loads(path.read_text())
        if 'state' not in data or not isinstance(data['state'], dict):
            continue
        s = data['state']; snapshots.append(path.stem)
        assert s['runtime']['bundleID'] == 'com.circlr.integrationqa' and s['runtime']['version'] == '0.20.0'
        assert s['projectID'] == package['projectID'] and s['path'] == package['fixture']
        assert not s['recording']['busy'] and not s['recording']['midi']
    app = Path(package['app']); binary = app / 'Contents/MacOS/circlr'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleVersion'] == '28'
    source = ROOT / '.build/integration-release/release/circlr'
    expected = '456B4223-8356-361A-8ECF-0AC1E8C65B01'
    for path in [source, binary]:
        assert expected in subprocess.check_output(['dwarfdump', '--uuid', str(path)], text=True)
    spec = importlib.util.spec_from_file_location('import_evidence', ROOT / 'qa/check-import-evidence.py')
    helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
    assert helper.sections(source) == helper.sections(binary)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    kit = app / 'Contents/Resources/Codex'; manifest = json.loads((kit / 'manifest.json').read_text())
    assert manifest['version'] == '0.20.0' and len(manifest['files']) == 25
    for path, digest in manifest['files'].items():
        assert hashlib.sha256((kit / path).read_bytes()).hexdigest() == digest
    original = Path(package['fixture']).with_name('studio.circlr') / 'manifest.json'
    assert hashlib.sha256(original.read_bytes()).hexdigest() == package['sourceSHA256']
    assert 'Executed 259 tests, with 0 failures' in (OUT / 'keyboard-swift-tests.log').read_text()
    assert 'Ran 26 tests' in (OUT / 'python-tests.log').read_text() and '\nOK\n' in (OUT / 'python-tests.log').read_text()
    assert 'Build complete!' in (OUT / 'release-mouse.log').read_text()
    result = dict(status='passed', snapshots=len(snapshots), swiftTests=259, pythonTests=26,
                  sections=len(helper.sections(source)), kitFiles=25, uuid=expected,
                  inactiveDrag='not_verified', activeDrag='passed', keyboardAndTab='passed')
    (OUT / 'verification.json').write_text(json.dumps(result, indent=2) + '\n'); print(json.dumps(result))


if __name__ == '__main__':
    main()
