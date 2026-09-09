#!/usr/bin/env python3
"""Verify build 43 UI responsiveness evidence separately from real audio completion."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import re
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/audition-worker'
FINAL = OUT / 'elapsed'
KEYS = ['name', 'global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'signal', 'portLayout', 'circleLayout']


def capture(name, revision):
    value = json.loads((OUT / (name + '.json')).read_text())
    state = value['state']
    assert state['revision'] == revision and not state['dirty']
    assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
    assert state['projectID'] == '32B4C93C-E4F6-5561-BDCD-CEEB9951528B'
    assert state['output']['attempts'] == 0 and not state['recording']['busy'] and not state['recording']['midi']
    return value


def normalized(project, key):
    value = copy.deepcopy(project.get(key))
    if key == 'portLayout' and value is not None:
        value.pop('revision', None)
    return value


def notes(project):
    use = project['arrangements'][0]['uses'][0]
    return next(l for l in use['addedLanes'] if l['id'] == '055F3787-2B9D-4DD1-9752-56106F8D94F5')['notes']


if __name__ == '__main__':
    before = capture('before', 14)['manifest']
    for name, revision in [('first-restored', 20), ('final-before', 20), ('final-restored', 24), ('final-reopened', 24)]:
        project = capture(name, revision)['manifest']
        for key in KEYS:
            assert normalized(project, key) == normalized(before, key), (name, key)
    for name, revision in [('note-added', 15), ('cancelled', 15), ('edited', 16), ('latest-cancelled', 17), ('final-cancelled', 21), ('final-latest', 22), ('final-reopened', 24)]:
        value = capture(name, revision)
        status = value['state']['audition']
        assert status['attempts'] == 1 and status['heldNotes'] == 0
        assert status['phase'] == ('preparing' if name == 'note-added' else 'stopping')
    first = capture('note-added', 15)
    assert len(notes(first['manifest'])) == len(notes(before)) + 1
    edited = capture('edited', 16)
    new = next(n for n in notes(edited['manifest']) if n['id'] not in {n['id'] for n in notes(before)})
    assert (new['pitch'], new['beat'], new['velocity']) == (72, 3, 82)
    assert '지연되어' in capture('cancelled', 15)['state']['audition']['message']
    initial = capture('final-cancelled', 21)['state']['audition']
    latest = capture('final-latest', 22)['state']['audition']
    assert initial['elapsedSeconds'] >= 1 and latest['elapsedSeconds'] >= initial['elapsedSeconds']
    assert 'message' not in initial  # Manual Space cancellation preceded the native timeout.
    for name in ['note-added', 'final-request']:
        ax = (OUT / (name + '-ax.txt')).read_text()
        assert 'Description: 미리 듣기 취소' in ax and '준비 중 · 0초' in ax
    closed = (OUT / 'final-console-closed-ax.txt').read_text()
    assert 'Description: 미리 듣기 취소' in closed
    stack = (OUT / 'audition-stack.txt').read_text()
    threads = re.split(r'(?=^    \d+ Thread_)', stack, flags=re.MULTILINE)
    main = next(t for t in threads if 'com.apple.main-thread' in t)
    blocked = next(t for t in threads if 'LiveSampler.init' in t)
    assert main != blocked and '-[NSApplication run]' in main and 'LiveSampler.init' not in main
    assert 'AuditionTransport.prepare' in blocked and 'HALC_ProxyIOContext::_TellServerAboutStreamUsage' in blocked
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in before['assets']:
        for folder in [source, source.with_name('audition-worker.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    app = FINAL / '써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('43', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    hashes = json.loads((FINAL / 'source-hashes.json').read_text())
    assert len(hashes) == 8
    for name, digest in hashes.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest
    kit = app / 'Contents/Resources/Codex'
    manifest = json.loads((kit / 'manifest.json').read_text())
    assert len(manifest['files']) == 25
    for name, digest in manifest['files'].items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    screenshots = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in OUT.glob('*.jpg')}
    assert len(screenshots) == 6
    result = dict(status='passed', revision=24, sourceFiles=8, kitFiles=25, executableSections=37,
                  physicalAuditionCompletion='not_verified', screenshots=screenshots)
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))
