"""Live playback/follow scenarios through the existing local QA command interface."""
import importlib.util
import json
from pathlib import Path
import time

spec = importlib.util.spec_from_file_location('playback_native', Path(__file__).with_name('playback-native.py'))
native = importlib.util.module_from_spec(spec); spec.loader.exec_module(native)
call, QA = native.call, native.QA
report = {'checks': [], 'samples': {}}


def sample(name):
    state = call('snapshot')
    assert state['path'] == str(QA / 'f0r-h3r.circlr')
    assert state['runtime']['bundleID'] == 'com.circlr.hierarchyqa'
    report['samples'][name] = state
    return state


def wait_for(predicate, timeout=60):
    deadline = time.monotonic()+timeout
    while time.monotonic() < deadline:
        state = call('snapshot')
        if predicate(state): return state
        time.sleep(1)
    raise AssertionError('Native state did not reach the expected condition')


def main():
    initial = sample('initial'); assert not initial['dirty']
    call('focus', {'minimized': False})
    assert not call('snapshot')['playback'].get('windowOccluded', False), 'Show the QA window in front before testing visible animation'
    call('stop'); call('focus', {'follow': True}); started = time.monotonic(); call('play')
    wait_for(lambda s: s['playback']['playing'], timeout=180)
    report['playback_start_wait_seconds'] = time.monotonic()-started
    time.sleep(1)
    first = sample('following-a')
    assert first['playback']['follow'] == 'following'
    assert first['playback']['focusedSection'] == first['playback']['currentSection']
    assert first['playback']['nodes'] and first['playback']['edges']
    assert first['selection'] == initial['selection']
    time.sleep(1)
    second = sample('following-b')
    delta = second['playback']['frameCount']-first['playback']['frameCount']
    assert delta > 25, delta
    assert second['playback']['seconds'] > first['playback']['seconds']
    assert second['playback']['phases'] != first['playback']['phases']
    assert second['dirty'] is False and second['revision'] == initial['revision']
    report['checks'].append('Real playback, active node/edge signals and changing phases; selection/music unchanged')
    report['frames_between_samples'] = delta

    call('focus')
    time.sleep(1)
    paused = sample('manual-focus')
    assert paused['playback']['follow'] == 'suspended'
    call('focus', {'follow': True}); time.sleep(1)
    resumed = sample('resumed')
    assert resumed['playback']['follow'] == 'following'
    assert resumed['playback']['focusedSection'] == resumed['playback']['currentSection']
    report['checks'].append('Explicit camera focus suspends follow; follow=true resumes without music mutation')

    call('focus'); time.sleep(0.4)
    call('focus', {'follow': True}); time.sleep(0.1)
    call('focus', {'minimized': True}); time.sleep(0.5)
    hidden = sample('minimized-a'); time.sleep(1)
    hidden_later = sample('minimized-b')
    assert hidden['playback']['animated'] is False
    assert hidden_later['playback']['seconds'] > hidden['playback']['seconds']
    assert hidden_later['playback']['frameCount'] == hidden['playback']['frameCount']
    call('focus', {'minimized': False}); time.sleep(1)
    restored = sample('restored')
    assert restored['playback']['frameCount'] > hidden_later['playback']['frameCount']
    if resumed['playback']['currentSection'] == restored['playback']['currentSection']:
        a, b = resumed['playback']['camera'], restored['playback']['camera']
        assert abs(a['zoom']-b['zoom']) < 0.000001
        assert all(abs(a['pan'][axis]-b['pan'][axis]) < 0.000001 for axis in ['x', 'y'])
    report['checks'].append('Minimized playback continues while display frames stop; restoring completes the interrupted camera transition')

    old_section = restored['playback']['currentSection']
    wait_for(lambda s: s['playback']['currentSection'] != old_section, timeout=25)
    time.sleep(1)
    moved = sample('next-section')
    assert moved['playback']['focusedSection'] == moved['playback']['currentSection']
    assert moved['playback']['camera'] != restored['playback']['camera']
    report['checks'].append('Camera follows the next actual section at its playback boundary')

    track = moved['tracks'][0]
    call('apply', {'operations': [{'kind': 'set_track', 'trackID': track['id'], 'gain': track['gain']*0.99}]}, write=True)
    time.sleep(0.3)
    stale = sample('stale')
    assert stale['playback']['stale'] is True
    assert not stale['playback']['nodes'] and not stale['playback']['edges'] and not stale['playback']['phases']
    call('stop'); call('undo', write=True); call('save', write=True)
    time.sleep(0.3)
    final = sample('stopped')
    assert final['playback']['playing'] is False and final['playback']['animated'] is False
    assert not final['playback']['nodes'] and not final['playback']['edges']
    assert final['tracks'] == initial['tracks'] and not final['dirty']
    report['checks'].append('Stale music revision clears visual signals; stop clears animation; Undo restores tracks')
    print(json.dumps({'checks': report['checks'], 'frames_between_samples': delta}, ensure_ascii=False))


if __name__ == '__main__':
    try:
        main(); report['status'] = 'passed'
    except BaseException as error:
        report['status'] = 'failed'; report['error'] = repr(error)
        raise
    finally:
        (QA / 'native-scenarios.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
