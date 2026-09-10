#!/usr/bin/env python3
"""Read-only build106 bounce warning evidence; missing candidate captures fail closed."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/bounce-notices'
spec = importlib.util.spec_from_file_location('compact_checks', Path(__file__).with_name('check-midi-compact-evidence.py'))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)
PATH_NOTICE = '현재 서클은 출력 경로 밖입니다'
TAIL_NOTICE = '잔향이 잘릴 수 있습니다'


def load(name):
    return json.loads((OUT / (name + '.json')).read_text())


def ax(name):
    return (OUT / (name + '.ax.txt')).read_text()


def rows(text, role):
    return [line for line in text.splitlines() if re.match(r'^\s*\d+ ' + re.escape(role) + r'(?: |$)', line)]


def main():
    baseline_package, package = load('baseline/package'), load('final/package')
    assert baseline_package['build'] == '105' and package['build'] == '106'
    assert baseline_package['projectID'] == package['projectID']
    assert baseline_package['fixture'] == package['fixture']
    baseline = load('baseline/compact')
    c.guard(baseline, baseline_package, 22)
    original = c.music(baseline['manifest'])
    names = ['dual', 'settings-cancelled', 'auto', 'restored', 'reopened']
    captures = {name: load('final/' + name) for name in names}
    for name, capture in captures.items():
        c.guard(capture, package, 22)
        assert c.music(capture['manifest']) == original, name
    before = ax('baseline/compact')
    assert any(PATH_NOTICE in line for line in rows(before, 'text'))
    assert any(TAIL_NOTICE in line for line in rows(before, 'menu button'))
    assert not any(TAIL_NOTICE in line for line in rows(before, 'text'))
    dual = ax('final/dual')
    assert any(PATH_NOTICE in line for line in rows(dual, 'text'))
    assert any(TAIL_NOTICE in line for line in rows(dual, 'text'))
    assert any('여운 설정' in line for line in rows(dual, 'button'))
    settings = ax('final/settings')
    assert any('바운스 여운 초' in line for line in rows(settings, 'text field'))
    automatic = ax('final/auto')
    assert any(PATH_NOTICE in line for line in rows(automatic, 'text'))
    assert not any(TAIL_NOTICE in line for line in rows(automatic, 'text'))
    fixture = Path(package['fixture'])
    restored, reopened = captures['restored']['manifest'], captures['reopened']['manifest']
    assert restored == reopened == json.loads((fixture / 'manifest.json').read_text())
    source = fixture.with_name('studio.circlr')
    assert package['sourceSHA256'] == baseline_package['sourceSHA256']
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256']
    for asset in original['assets']:
        path = Path(asset['path'])
        assert not path.is_absolute() and '..' not in path.parts
        for folder in [fixture, source]:
            assert hashlib.sha256((folder / path).read_bytes()).hexdigest() == asset['checksum']
    job, completed = load('final/reopen-job'), load('final/reopen-completed')
    assert completed['job']['id'] == job['jobID']
    assert completed['job']['kind'] == 'open' and completed['job']['state'] == 'completed'
    assert completed['job']['path'] == str(fixture) and completed['revision'] == 22
    print(json.dumps(dict(status='passed', baselineSnapshots=1, finalSnapshots=len(captures),
                         revision=22, assets=2, musicUnchanged=True, strictReopenEquality=True,
                         simultaneousNoticeRows=True, physicalAudioAttempts=0)))


if __name__ == '__main__':
    main()
