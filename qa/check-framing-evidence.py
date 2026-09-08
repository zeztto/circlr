#!/usr/bin/env python3
"""Validate recorded native geometry and interaction evidence, without controlling the app."""
import json
import math
from pathlib import Path

OUT = Path(__file__).resolve().parent / 'generated/framing'


def state(name):
    return json.loads((OUT / (name + '.json')).read_text())['state']


def overlaps(a, b):
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


def validate_frame(s):
    p = s['playback']; labels = p['labels']; circles = p['labelCircles']; view = p['workspaceViewport']
    assert p['playing'] and p['follow'] == 'following' and not p['editorFrame']
    assert p['animated'] and not p['windowOccluded'] and p['windowVisible']
    assert len(circles) == 8 and len(labels) == 8
    assert {json.dumps(x['address'], sort_keys=True) for x in circles} == {json.dumps(x['address'], sort_keys=True) for x in labels}
    for i, label in enumerate(labels):
        rect = label['rect']
        assert view[0] <= rect[0] and view[1] <= rect[1] and rect[0] + rect[2] <= view[0] + view[2] and rect[1] + rect[3] <= view[1] + view[3]
        assert all(not overlaps(rect, other['rect']) for other in labels[i+1:])
        for circle in circles:
            if circle['address'] == label['address']:
                continue
            x, y = circle['center']
            near_x, near_y = max(rect[0], min(rect[0] + rect[2], x)), max(rect[1], min(rect[1] + rect[3], y))
            assert math.hypot(x-near_x, y-near_y) >= circle['radius'] + 4 - 1e-6
    assert s['revision'] == 15 and s['layoutRevision'] == 4 and not s['recording']['busy']
    return dict(canvas=p['canvasSize'], viewport=view, zoom=p['camera']['zoom'], labels=len(labels), minimumRadius=min(c['radius'] for c in circles))


if __name__ == '__main__':
    result = {name: validate_frame(state(name)) for name in ['large-open', 'large-closed', 'small-closed', 'small-open']}
    edit = state('editing-live')['playback']
    assert edit['playing'] and edit['follow'] == 'suspended' and edit['editorAddress']['music']['nodeID'] == 'midi:055F3787-2B9D-4DD1-9752-56106F8D94F5'
    assert edit['editorFrame'][2] > 700
    resumed = state('resumed')['playback']
    assert resumed['playing'] and resumed['follow'] == 'following' and not resumed['editorFrame']
    wheel = state('wheel-suspended')['playback']
    assert wheel['playing'] and wheel['follow'] == 'suspended'
    assert wheel['camera']['zoom'] > state('small-open')['playback']['camera']['zoom']
    pointer = state('pointer-editing-live')['playback']
    assert pointer['playing'] and pointer['follow'] == 'suspended'
    assert pointer['editorAddress'] == edit['editorAddress'] and pointer['editorFrame'][2] > 700
    final = json.loads((OUT / 'final-save.json').read_text())
    baseline = json.loads((OUT / 'before-revised-app.json').read_text())['manifest']
    for key in ['tracks', 'sections', 'arrangements', 'assets', 'portLayout']:
        assert final['manifest'][key] == baseline[key], key
    # One temporary eight-repeat QA edit and its Undo advance the monotonic music revision.
    assert baseline['musicRevision'] == 14 and final['manifest']['musicRevision'] == 16
    assert final['state']['revision'] == 16 and final['state']['layoutRevision'] == 4
    assert not final['state']['playback']['playing'] and not final['state']['recording']['busy']
    (OUT / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))
