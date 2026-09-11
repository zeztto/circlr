#!/usr/bin/env python3
"""Read-only assertions over actual output-connection QA observations."""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent / 'generated/output'


def state(name):
    return json.loads((OUT / (name + '.json')).read_text())['state']


if __name__ == '__main__':
    # The first candidate proves a real timeout and GUI Space cancellation on one device call.
    first = [state(x) for x in ['cold-start', 'timed-out', 'retry-waiting', 'space-cancelled', 'before-final-app']]
    assert len({x['output']['attemptID'] for x in first}) == 1
    assert [x['output']['request'] for x in first] == ['waiting', 'timedOut', 'waiting', 'cancelled', 'cancelled']
    assert first[-1]['output']['phase'] == 'ready' and not first[-1]['playback']['playing']
    # The final binary must restore focus when following playback removes its MIDI editor.
    current = [state(x) for x in ['focus-start', 'focus-cancelled', 'focus-ready', 'focus-playing', 'focus-stopped']]
    assert len({x['output']['attemptID'] for x in current}) == 1
    assert all(x['output']['attempts'] == 1 for x in first + current)
    assert current[0]['output']['request'] == 'waiting'
    assert current[1]['output']['request'] == 'cancelled' and not current[1]['playback']['playing']
    assert current[2]['output']['phase'] == 'ready' and current[2]['output']['request'] == 'cancelled'
    assert not current[2]['playback']['playing']
    p = current[3]['playback']
    assert p['playing'] and p['seconds'] > 0 and p['animated'] and not p['windowOccluded']
    assert p['canvasKeyboardFocus'] and not p['editorFrame']
    assert not current[4]['playback']['playing'] and current[4]['playback']['canvasKeyboardFocus']
    assert state('focus-before-play')['playback']['editorFrame']
    console = state('console-playing')['playback']
    assert console['playing'] and not console['canvasKeyboardFocus'] and not console['editorFrame']
    console_ax = (OUT / 'console-space-ax.txt').read_text()
    assert 'Description: 재생 정지' in console_ax and 'Value: ㅌ , Placeholder: help' in console_ax
    final = json.loads((OUT / 'final-save.json').read_text())
    baseline = json.loads((OUT / 'before.json').read_text())['manifest']
    for key in ['tracks', 'sections', 'arrangements', 'assets', 'portLayout', 'musicRevision']:
        assert final['manifest'][key] == baseline[key], key
    assert all(not x['recording']['busy'] and x['revision'] == 14 and x['layoutRevision'] == 4 for x in first + current)
    assert not final['state']['playback']['playing'] and not final['state']['dirty']
    result = {'singleAttempt': True, 'lateCompletionDidNotPlay': True, 'canvasFocusRestored': True,
              'spaceStopped': True, 'musicPreserved': True, 'actualConnectionSeconds': current[2]['output']['elapsedSeconds']}
    (OUT / 'verification.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
