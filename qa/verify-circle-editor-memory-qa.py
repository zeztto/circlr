#!/usr/bin/env python3
"""Read-only build139 source-editor memory roundtrip comparison; no RPC or file writes."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('settings_return', Path(__file__).with_name('verify-section-settings-return-qa.py'))
previous = importlib.util.module_from_spec(spec)
spec.loader.exec_module(previous)
require = previous.require


def compare(before, after):
    a, b = before['state'], after['state']
    ma, mb = copy.deepcopy(before['manifest']), copy.deepcopy(after['manifest'])
    ha, hb = ma.pop('hierarchyView'), mb.pop('hierarchyView')
    require(ma == mb, 'Music or metadata changed, including revision/layout outside hierarchy')
    for key in ('revision', 'layoutRevision', 'activeArrangementID', 'selection', 'selectedNoteIDs'):
        require(a[key] == b[key], 'Runtime field did not return: ' + key)
    require(ha['selection'] == hb['selection'], 'Persisted source address did not return')
    require(ha['workspace'] == hb['workspace'], 'Complete source workspace did not return')
    require(ha['midiStepMode'] == hb['midiStepMode'], 'MIDI step mode did not return')
    require(ha['settingsOpen'] == hb['settingsOpen'], 'Settings visibility did not return')
    require(a['automationEditor'] == b['automationEditor'], 'Runtime automation editor did not return')
    # Navigation legitimately focuses a circle. Camera and viewport dimensions are
    # reported, not treated as editor-memory invariants or visual QA evidence.
    excluded = {'camera', 'width', 'height'}
    require({k: v for k, v in ha.items() if k not in excluded} ==
            {k: v for k, v in hb.items() if k not in excluded}, 'Additional persisted editor memory changed')
    return dict(camera='same' if ha['camera'] == hb['camera'] else 'different',
                captureSize='same' if (ha.get('width'), ha.get('height')) == (hb.get('width'), hb.get('height')) else 'different',
                runtimeZoom='same' if a['view'].get('zoom') == b['view'].get('zoom') else 'different')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path); parser.add_argument('after', type=Path)
    parser.add_argument('--build', type=int, default=139)
    parser.add_argument('--expected-revision', type=int, default=166)
    args = parser.parse_args()
    require(args.before.resolve() != args.after.resolve(), 'Two distinct saved captures required')
    before = previous.read_capture(args.before, args.build)
    after = previous.read_capture(args.after, args.build)
    require(before['state']['revision'] == after['state']['revision'] == args.expected_revision, 'Unexpected revision')
    view = compare(before, after)
    print(json.dumps(dict(status='PASS', build=args.build, projectID=previous.PROJECT_ID,
        revision=args.expected_revision, viewComparison=view,
        scope='Saved source roundtrip: exact music/revision/layout/address/note selection/full workspace/step/settings and automation state; unused no-I/O guards. Camera/size/zoom differences are reported only. First-visit canonical state, pixels, package integrity and physical audio are not verified.'), ensure_ascii=False))


if __name__ == '__main__':
    main()
