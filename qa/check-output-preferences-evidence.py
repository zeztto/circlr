#!/usr/bin/env python3
"""Read-only build109 QA-injected output preferences evidence, not device validation."""
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/output-preferences'
spec = importlib.util.spec_from_file_location('compact_checks', Path(__file__).with_name('check-midi-compact-evidence.py'))
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)


def load(name):
    return json.loads((OUT / (name + '.json')).read_text())


def injection(candidate):
    package = load(candidate + '/package')
    value = load(candidate + '/qa-injection')
    assert package['build'] == '109'
    assert value['qaOnlyMock'] is True and value['candidate'] == candidate
    scenario = value.get('scenario', candidate)
    assert value['preferenceContract']['suite'] == 'com.circlr.integrationqa'
    assert value['preferenceContract']['key'] == 'circlr.playback.outputDeviceUID'
    assert 'deny stub exits78' in value['physicalOutputWorker']
    assert value['catalogExit'] == (70 if scenario == 'failure' else 0)
    assert value['delaySeconds'] == (4 if scenario == 'delay' else 0)
    assert [d['uid'] for d in value['catalog']['devices']] == (['qa-output-a'] if scenario == 'missing' else ['qa-output-a', 'qa-output-b'])
    for name, digest in value['mockHelperSHA256'].items():
        assert hashlib.sha256((Path(package['app']) / 'Contents/MacOS' / name).read_bytes()).hexdigest() == digest
    for name, digest in value['productionHelperSHA256'].items():
        assert hashlib.sha256((OUT / candidate / 'production-helpers' / name).read_bytes()).hexdigest() == digest
    return package


def capture(candidate, name, package, baseline):
    value = load(candidate + '/' + name)
    c.guard(value, package, baseline['musicRevision'])
    assert c.music(value['manifest']) == c.music(baseline), (candidate, name)
    return value


def check_assets(package, baseline):
    fixture = Path(package['fixture'])
    assert hashlib.sha256((fixture.with_name('studio.circlr') / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256']
    for asset in baseline['assets']:
        path = Path(asset['path']); assert not path.is_absolute() and '..' not in path.parts
        assert hashlib.sha256((fixture / path).read_bytes()).hexdigest() == asset['checksum']


def main():
    packages = {name: injection(name) for name in ['success3','missing3','failure4','delay4']}
    baseline = load('success3/fixture-initial')
    captures = {name:capture('success3', name, packages['success3'], baseline)
                for name in ['before','selected','guards','restored','reopened']}
    capture('missing3', 'missing', packages['missing3'], baseline)
    for package in packages.values():
        check_assets(package, baseline)
    fixture = Path(packages['success3']['fixture'])
    assert captures['restored']['manifest'] == captures['reopened']['manifest'] == json.loads((fixture / 'manifest.json').read_text())
    for name,label in [('settings','QA 출력 B'),('selected-a','QA 출력 A'),('selected','QA 출력 B'),('command-entry','QA 출력 B')]:
        text = (OUT / 'success3' / (name + '.ax.txt')).read_text()
        assert 'Value: ' + label + ', ID: output-preferences-device' in text
        assert '실제 출력 장치: 아직 확인되지 않음' in text
    tab = (OUT / 'success3/tab.ax.txt').read_text().split('The focused UI element is')[-1]
    assert 'button 다시 조회' in tab
    escaped = (OUT / 'success3/escaped.ax.txt').read_text()
    assert 'output-preferences-device' not in escaped and 'container 앨범 서클 캔버스' in escaped.split('The focused UI element is')[-1]
    missing = (OUT / 'missing3/missing.ax.txt').read_text()
    assert '저장된 출력 장치 · 미연결' in missing and '다른 장치로 자동 대체하지 않습니다' in missing
    for name in ['settings','selected-a','selected','tab','escaped','command-entry']:
        assert (OUT / 'success3' / (name + '.jpg')).read_bytes().startswith(b'\xff\xd8\xff')
    capture('failure4', 'failure', packages['failure4'], baseline)
    for name in ['completed', 'cancel-observed']:
        capture('delay4', name, packages['delay4'], baseline)
        text = (OUT / 'delay4' / (name + '.ax.txt')).read_text()
        assert 'Value: QA 출력 B, ID: output-preferences-device' in text
        assert 'button 다시 조회' in text and 'button 조회 취소' not in text
    for name in ['failure', 'retry']:
        text = (OUT / 'failure4' / (name + '.ax.txt')).read_text()
        assert '출력 장치를 조회하지 못했습니다' in text and 'button 다시 조회' in text
        assert 'Value: 시스템 기본값, ID: output-preferences-device' in text
    timing = load('delay4/cancel-timing')
    assert timing['helperDelaySeconds'] == load('delay4/qa-injection')['delaySeconds'] == 4
    assert 0 < timing['elapsedMs'] < timing['helperDelaySeconds'] * 1000
    assert timing['method'] == 'native retry button then same-position cancel button'
    assert timing['returnedToRetry'] is True and timing['loadingStillVisible'] is False
    restored_preferences = (OUT / 'delay4/preferences-restored.ax.txt').read_text()
    assert 'Value: 시스템 기본값, ID: output-preferences-device' in restored_preferences
    assert '선택: 시스템 기본값' in restored_preferences
    # loading/cancelled captures were already completed after CUA delay; not cancellation evidence.
    print(json.dumps(dict(status='passed', candidates=['success3','missing3','failure4','delay4'],
        snapshots=9, qaInjectedCatalog=True, physicalDeviceSelectionVerified=False,
        cancellationElapsedMs=timing['elapsedMs'], restoredSystemDefaultAX=True,
        strictReopenEquality=True, assets=2, musicRevision=14, physicalAudioAttempts=0)))


if __name__ == '__main__':
    main()
