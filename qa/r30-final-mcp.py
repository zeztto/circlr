#!/usr/bin/env python3
"""Build159 disposable fixture native data QA. No playback or GUI automation."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from mcp.server import call_tool

SOCKET = str(Path.home() / 'Library/Application Support/circlr-integration-qa/Agent/agent.sock')
FIXTURE = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/release030-final.circlr'
OUT = ROOT / 'qa/generated/r30/final159-mcp'
REPORT = {'schema': 'r30-final-mcp-v1', 'checks': [], 'physicalAudioRequested': False,
          'remaining': ['GUI parity', 'GUI Redo (MCP has no Redo)', 'GUI scope visibility']}


def call(name, args=None, error=False):
    value = call_tool(SOCKET, 'circlr_' + name, args or {})['structuredContent']
    assert bool(value.get('ok')) != error, value
    return value if error else value['result']


def write(name, args=None):
    state = call('snapshot')
    return call(name, dict(projectID=state['projectID'], expectedRevision=state['revision'], **(args or {})))


def dump(name, value):
    (OUT / (name + '.json')).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def checkpoint(name):
    write('save')
    state = call('snapshot')
    assert state['path'] == str(FIXTURE) and state['runtime']['build'] == '159'
    assert state['output']['attempts'] == state['audition']['attempts'] == 0
    manifest = json.loads((FIXTURE / 'manifest.json').read_text())
    for asset in manifest['assets']:
        relative = Path(asset['path'])
        assert not relative.is_absolute() and '..' not in relative.parts
        assert hashlib.sha256((FIXTURE / relative).read_bytes()).hexdigest() == asset['checksum']
    dump(name, {'state': state, 'manifest': manifest})
    return manifest


def musical(value):
    value = copy.deepcopy(value)
    value.pop('musicRevision', None)
    # Arrangement selection deliberately navigates to its owner; camera/selection
    # restoration is a separate GUI contract, not part of the musical comparison.
    value.pop('hierarchyView', None)
    return value


def find(items, identifier):
    return next(item for item in items if item['id'] == identifier)


def apply(operation):
    return write('apply', {'operations': [operation]})


def undo_to(baseline, name):
    state = call('snapshot')
    write('undo', {'expectedLayoutRevision': state['layoutRevision']})
    assert musical(checkpoint(name)) == musical(baseline), name


def main():
    OUT.mkdir(parents=True, exist_ok=False)
    state = call('snapshot')
    assert state['projectID'] == 'R30-project' and state['revision'] == 1
    assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
    baseline = checkpoint('00-baseline')
    common = dict(kind='edit_sustain', arrangementID='R30-arrangement', useID='R30-use-Verse',
                  laneID='R30-Verse-lane-synth', sustainChange=dict(kind='insert', beat=1, rawValue=96))
    for original, label in [(False, 'use'), (True, 'original')]:
        apply(dict(common, original=original))
        changed = checkpoint('01-' + label)
        oldsection = find(baseline['sections'], 'R30-section-Verse')
        section = find(changed['sections'], 'R30-section-Verse')
        olduse = find(baseline['arrangements'][0]['uses'], 'R30-use-Verse')
        use = find(changed['arrangements'][0]['uses'], 'R30-use-Verse')
        if original:
            assert use == olduse
            lane = find(section['lanes'], 'R30-Verse-lane-synth')
            assert lane['sustain']['events'][0]['rawValue'] == 96
            expected = copy.deepcopy(section)
            find(expected['lanes'], lane['id']).pop('sustain')
            assert expected == oldsection
        else:
            assert changed['sections'] == baseline['sections']
            lane = use['laneOverrides']['R30-Verse-lane-synth']
            assert lane['sustain']['events'][0]['rawValue'] == 96
            expected = copy.deepcopy(use)
            expected['laneOverrides'][lane['id']].pop('sustain')
            assert expected == olduse
        assert changed['patterns'] == baseline['patterns'] and changed['assets'] == baseline['assets']
        undo_to(baseline, '02-' + label + '-undo')
        REPORT['checks'].append(label + ' sustain targets only expected lane; Undo restores entire manifest except musicRevision')
    apply(dict(kind='edit_sustain', patternID='R30-shared-drums', trackID='R30-track-drums',
               sustainChange=dict(kind='insert', beat=1, rawValue=96)))
    shared = checkpoint('03-shared')
    assert shared['sections'] == baseline['sections'] and shared['arrangements'] == baseline['arrangements']
    pattern = find(shared['patterns'], 'R30-shared-drums')
    assert pattern['sustain']['events'][0]['rawValue'] == 96
    for name in ('Verse', 'Chorus'):
        inspect = call('inspect', {'arrangementID': 'R30-arrangement', 'useID': 'R30-use-' + name})
        dump('03-shared-effective-' + name, inspect)
        source = find(inspect['graph']['nodes'], 'R30-' + name + '-drums-source')
        assert source['settings']['rhythm']['value']['patternID'] == pattern['id']
    undo_to(baseline, '04-shared-undo')
    REPORT['checks'].append('Shared pattern sustain changes one referenced pattern, preserves original sections/uses; Verse and Chorus reference it; Undo exact restore')
    apply(dict(kind='duplicate_arrangement', compositionID='R30-composition', arrangementID='R30-arrangement', name='Q05 왕복'))
    duplicate = checkpoint('05-duplicate')
    new = next(a for a in duplicate['arrangements'] if a['id'] != 'R30-arrangement')
    assert duplicate['activeArrangementID'] == baseline['activeArrangementID']
    assert duplicate['sections'] == baseline['sections'] and duplicate['assets'] == baseline['assets']
    for identifier in (new['id'], 'R30-arrangement'):
        apply(dict(kind='select_arrangement', compositionID='R30-composition', arrangementID=identifier))
        assert call('snapshot')['activeArrangementID'] == identifier
    checkpoint('06-arrangement-roundtrip')
    for _ in range(3):
        state = call('snapshot')
        write('undo', {'expectedLayoutRevision': state['layoutRevision']})
    assert musical(checkpoint('07-arrangement-undo')) == musical(baseline)
    REPORT['checks'].append('Duplicate preserves shared sections/assets and selection; select new/back; 3 Undo restore musical baseline; hierarchyView remains at composition')
    before = checkpoint('08-rejection-before')
    state = call('snapshot')
    revision = dict(projectID=state['projectID'], expectedRevision=state['revision'])
    stale = call('apply', dict(revision, expectedRevision=state['revision'] - 1,
                 operations=[dict(kind='rename_project', name='MUST NOT APPLY')]), error=True)
    assert 'stale_revision' in stale['error']
    invalid = call('apply', dict(revision, operations=[dict(kind='rename_project', name='MUST NOT APPLY'),
                   dict(kind='set_node', arrangementID='R30-arrangement', useID='R30-use-Verse', nodeID='missing', muted=True)]), error=True)
    dump('09-rejections', {'stale': stale, 'failedBatch': invalid})
    assert checkpoint('10-rejection-after') == before
    REPORT['checks'].append('Stale revision and failed batch preserve exact persisted manifest including revision')
    path = OUT / 'must-not-exist-cancelled.wav'
    job = write('export', {'path': str(path)})
    call('stop')
    for _ in range(30):
        terminal = call('job', {'jobID': job['jobID']})['job']
        if terminal['state'] != 'running':
            break
        time.sleep(1)
    assert terminal['state'] == 'cancelled', terminal
    time.sleep(2)
    assert not path.exists()
    assert checkpoint('11-stop-after') == before
    dump('12-stop', {'request': job, 'terminal': terminal, 'lateFileExists': path.exists()})
    REPORT['checks'].append('Native export then STOP cancels job; no file or late manifest change after terminal + 2 seconds')
    REPORT['finalState'] = call('snapshot')
    REPORT['status'] = 'PASS_BOUNDED_DATA_QA'
    dump('report', REPORT)
    print(json.dumps(REPORT, ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        REPORT.update(status='FAIL', error=repr(error))
        if OUT.exists():
            dump('report', REPORT)
        raise
