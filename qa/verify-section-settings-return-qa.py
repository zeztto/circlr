#!/usr/bin/env python3
"""Pure saved-capture roundtrip comparator. Never connects to an app or mutates files."""
import argparse
import copy
import json
from pathlib import Path

PROJECT_ID = '850B9812-38E4-567C-ACD8-B47A6370128D'
FIXTURE = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/midi-import-feedback.circlr'


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def read_capture(path, build):
    capture = json.loads(path.read_text())
    state, manifest = capture['state'], capture['manifest']
    require(state['projectID'] == manifest['id'] == PROJECT_ID, 'Wrong fixture identity')
    require(state['path'] == str(FIXTURE), 'Wrong fixture path')
    require(state['revision'] == manifest['musicRevision'], 'Capture/save revision mismatch')
    require(state['runtime']['bundleID'] == 'com.circlr.integrationqa', 'Wrong app bundle')
    require(str(state['runtime']['build']) == str(build), 'Wrong runtime build')
    for key in ('output', 'audition'):
        require(state[key]['attempts'] == 0 and state[key]['phase'] == 'idle', key + ' is not unused/idle')
    require(state['audition']['heldNotes'] == 0, 'Held audition notes')
    require(not state['playback']['playing'], 'Playback active')
    require(not any(state['recording'][k] for k in ('busy', 'audio', 'midi')), 'Recording active')
    require(not state.get('job') or state['job']['state'] != 'running', 'Audio job active')
    require(not state['dirty'], 'Capture not saved')
    hierarchy = manifest['hierarchyView']; workspace = hierarchy['workspace']
    for key in ('page', 'editor', 'selection', 'original', 'automationParameter', 'automationViewport'):
        require(key in workspace, 'Missing workspace field: ' + key)
    require(isinstance(workspace['editor'], dict) and isinstance(workspace['selection'], dict), 'Invalid editor/selection object')
    for key in ('selection', 'midiStepMode', 'settingsOpen', 'camera'):
        require(key in hierarchy, 'Missing hierarchy field: ' + key)
    require(state['selection'] == hierarchy['selection'], 'Runtime and saved address disagree')
    require(isinstance(state['selectedNoteIDs'], list), 'Invalid selected note IDs')
    require(isinstance(state['automationEditor'], dict), 'Missing runtime automation editor')
    return capture


def compare(before, after):
    a, b = before['state'], after['state']
    ma, mb = copy.deepcopy(before['manifest']), copy.deepcopy(after['manifest'])
    ha, hb = ma.pop('hierarchyView'), mb.pop('hierarchyView')
    # Pure settings roundtrip excludes only view, not revision or any musical metadata.
    require(ma == mb, 'Music/metadata changed; this comparator does not permit edit/Undo revision changes')
    for key in ('revision', 'layoutRevision', 'activeArrangementID', 'selection', 'selectedNoteIDs'):
        require(a[key] == b[key], 'Runtime field did not return: ' + key)
    wa, wb = ha['workspace'], hb['workspace']
    for key in ('page', 'original', 'editor', 'selection', 'automationParameter', 'automationViewport', 'pitchBend'):
        # Optional pitch state must retain both presence and value.
        require((key in wa) == (key in wb) and wa.get(key) == wb.get(key), 'Workspace field did not return: ' + key)
    require(wa == wb, 'Additional workspace fields changed')
    require(ha == hb, 'Full hierarchy/camera/settings/step state did not return')
    require(a['automationEditor'] == b['automationEditor'], 'Runtime automation editor did not return')
    require(a['view'] == b['view'], 'Runtime view did not return')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path); parser.add_argument('after', type=Path)
    parser.add_argument('--build', type=int, default=138)
    parser.add_argument('--shape-only', action='store_true', help='Validate inputs/no-I/O only; makes no roundtrip claim')
    args = parser.parse_args()
    before = read_capture(args.before, args.build); after = read_capture(args.after, args.build)
    if not args.shape_only:
        require(args.before.resolve() != args.after.resolve(), 'Two independently saved captures required')
        compare(before, after)
    print(json.dumps(dict(status='SHAPE_ONLY' if args.shape_only else 'PASS', build=args.build,
        projectID=PROJECT_ID, beforeRevision=before['state']['revision'], afterRevision=after['state']['revision'],
        scope='Saved capture format/identity/no-I/O only; no roundtrip verified' if args.shape_only else
        'Pure roundtrip: exact music/revision/address/note selection, complete persisted workspace/hierarchy, runtime automation/view. Does not verify GUI pixels, package signing, physical audio or changed-music return scenarios.'), ensure_ascii=False))


if __name__ == '__main__':
    main()
