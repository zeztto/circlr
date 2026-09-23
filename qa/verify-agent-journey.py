#!/usr/bin/env python3
"""Exercise the current stdio MCP adapter against an already-open integration QA song.

The caller must launch the isolated QA app and open a disposable project inside its
Application Support fixtures directory. This script never contacts the production socket.
"""
import argparse
import hashlib
import json
from pathlib import Path
import selectors
import subprocess
import sys
import time
import wave

ROOT = Path(__file__).resolve().parents[1]
QA_ROOT = Path.home() / 'Library/Application Support/circlr-integration-qa'
SOCKET = QA_ROOT / 'Agent/agent.sock'
REQUIRED = {'circlr_snapshot', 'circlr_inspect', 'circlr_apply', 'circlr_undo',
            'circlr_save', 'circlr_open', 'circlr_export', 'circlr_bounce',
            'circlr_job', 'circlr_events'}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--build', default='184')
    options = parser.parse_args()
    project = options.project.resolve()
    evidence = options.evidence.resolve()
    if not project.is_relative_to(QA_ROOT / 'fixtures') or project.suffix != '.circlr' or not project.is_dir():
        raise SystemExit('Only a disposable integration-QA fixture is allowed')
    if evidence.exists() or (QA_ROOT / 'fixtures' / f'{project.stem}-agent-export.wav').exists():
        raise SystemExit('Preserve existing QA evidence and export; use a new name')
    evidence.mkdir(parents=True)
    before_manifest = sha256(project / 'manifest.json')
    export = QA_ROOT / 'fixtures' / f'{project.stem}-agent-export.wav'
    child = subprocess.Popen(
        [sys.executable, str(ROOT / 'mcp/server.py'), '--socket', str(SOCKET)],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, bufsize=1,
    )
    sequence = 0
    reader = selectors.DefaultSelector()
    reader.register(child.stdout, selectors.EVENT_READ)
    report = {'schema': 'circlr-agent-journey-qa-v1', 'build': options.build,
              'project': str(project), 'beforeManifestSHA256': before_manifest,
              'checks': []}

    def message(method, params=None, notification=False):
        nonlocal sequence
        sequence += 1
        packet = {'jsonrpc': '2.0', 'method': method}
        if not notification:
            packet['id'] = sequence
        if params is not None:
            packet['params'] = params
        child.stdin.write(json.dumps(packet, ensure_ascii=False) + '\n')
        child.stdin.flush()
        if notification:
            return None
        if not reader.select(timeout=30):
            raise TimeoutError(f'MCP adapter did not answer {method} within 30 seconds')
        line = child.stdout.readline()
        if not line:
            raise RuntimeError(f'MCP adapter closed while answering {method}; exit code {child.poll()}')
        reply = json.loads(line)
        if 'error' in reply:
            raise RuntimeError(reply)
        return reply['result']

    def call(name, arguments=None, expect_error=False):
        result = message('tools/call', {'name': 'circlr_' + name,
                                        'arguments': arguments or {}})
        if bool(result.get('isError')) != expect_error:
            raise AssertionError(result)
        payload = result.get('structuredContent') or json.loads(result['content'][0]['text'])
        return payload if expect_error else payload['result']

    def scope(state):
        return {'projectID': state['projectID'], 'expectedRevision': state['revision']}

    def wait(job, seconds=180):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            value = call('job', {'jobID': job['jobID']})['job']
            if value['state'] != 'running':
                return value
            time.sleep(0.5)
        raise TimeoutError(job)

    try:
        initialized = message('initialize', {'protocolVersion': '2025-11-25',
                       'capabilities': {}, 'clientInfo': {'name': 'circlr-agent-journey-qa', 'version': '1'}})
        message('notifications/initialized', notification=True)
        catalog = {tool['name'] for tool in message('tools/list')['tools']}
        assert initialized['protocolVersion'] == '2025-11-25' and REQUIRED <= catalog
        report['toolCount'] = len(catalog)
        state = call('snapshot')
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
        assert state['runtime']['build'] == options.build
        assert not state['dirty']
        if state['path'] != str(project):
            opened_fixture = wait(call('open', {**scope(state), 'path': str(project)}), seconds=30)
            assert opened_fixture['state'] == 'completed', opened_fixture
            state = call('snapshot')
        assert state['path'] == str(project) and not state['dirty']
        report['checks'].append('stdio initialize, current catalog and isolated native app')

        arrangement = state['activeArrangementID']
        use = state['arrangements'][0]['uses'][0]['id']
        track = state['tracks'][0]['id']
        section = call('inspect', {'arrangementID': arrangement, 'useID': use})
        lane = next(item for item in section['lanes'] if item['trackID'] == track)
        original_notes = lane['notes']
        pitch = next(p for p in range(95, 80, -1) if not any(n['beat'] == 0 and n['pitch'] == p for n in original_notes))
        operation = {'kind': 'set_step', 'arrangementID': arrangement, 'useID': use,
                     'laneID': lane['id'], 'stepIndex': 0, 'pitch': pitch,
                     'enabled': True, 'subdivisions': 4, 'velocity': 64, 'gate': 1}
        edited = call('apply', {**scope(state), 'operations': [operation]})
        assert edited['revision'] == state['revision'] + 1
        changed = call('inspect', {'arrangementID': arrangement, 'useID': use})
        new_notes = next(item['notes'] for item in changed['lanes'] if item['id'] == lane['id'])
        assert len(new_notes) == len(original_notes) + 1
        assert any(n['beat'] == 0 and n['pitch'] == pitch for n in new_notes)
        stale = call('apply', {**scope(state), 'operations': [operation]}, expect_error=True)
        assert 'stale_revision' in stale['error']
        restored_state = call('undo', scope(edited))
        restored = call('inspect', {'arrangementID': arrangement, 'useID': use})
        assert next(item['notes'] for item in restored['lanes'] if item['id'] == lane['id']) == original_notes
        report['checks'].append('typed step edit, stale rejection and exact Undo')

        applied = call('apply', {**scope(restored_state), 'operations': [operation]})
        applied_section = call('inspect', {'arrangementID': arrangement, 'useID': use})
        applied_notes = next(item['notes'] for item in applied_section['lanes'] if item['id'] == lane['id'])
        assert len(applied_notes) == len(original_notes) + 1
        saved = call('save', scope(applied))
        assert not saved['dirty'] and saved['revision'] == applied['revision']
        saved_manifest = sha256(project / 'manifest.json')
        assert saved_manifest != before_manifest
        report['checks'].append('agent edit persisted to disposable project')

        opened = wait(call('open', {**scope(saved), 'path': str(project)}), seconds=30)
        assert opened['state'] == 'completed', opened
        reopened = call('snapshot')
        assert reopened['projectID'] == state['projectID'] and reopened['revision'] == saved['revision']
        assert sha256(project / 'manifest.json') == saved_manifest
        reopened_section = call('inspect', {'arrangementID': arrangement, 'useID': use})
        assert next(item['notes'] for item in reopened_section['lanes'] if item['id'] == lane['id']) == applied_notes
        report['checks'].append('native reopen preserves exact MIDI notes and manifest')

        exported = wait(call('export', {**scope(reopened), 'path': str(export)}))
        assert exported['state'] == 'completed' and export.is_file()
        with wave.open(str(export), 'rb') as wav:
            format_info = {'channels': wav.getnchannels(), 'sampleRate': wav.getframerate(),
                           'bitsPerSample': wav.getsampwidth() * 8, 'frames': wav.getnframes()}
            assert format_info['channels'] == 2 and format_info['sampleRate'] == 48000
            assert format_info['bitsPerSample'] == 24 and format_info['frames'] > 48000
            nonzero = False
            while frame := wav.readframes(8192):
                nonzero |= any(frame)
            assert nonzero
        report['checks'].append('native WAV export is 48 kHz stereo 24-bit and nonzero')

        bounced = wait(call('bounce', {**scope(reopened), 'arrangementID': arrangement,
                                      'useID': use, 'trackID': track}))
        assert bounced['state'] == 'completed' and bounced.get('nodeID'), bounced
        after_bounce = call('snapshot')
        assert after_bounce['revision'] == reopened['revision'] + 1
        final = call('save', scope(after_bounce))
        assert not final['dirty']
        report['checks'].append('native track bounce and save complete')
        events = call('events', {'afterSequence': 0})
        report.update(projectID=state['projectID'], initialRevision=state['revision'],
                      finalRevision=final['revision'], arrangementID=arrangement,
                      useID=use, laneID=lane['id'], trackID=track, editedPitch=pitch,
                      initialNoteCount=len(original_notes), editedNoteCount=len(applied_notes),
                      savedManifestSHA256=saved_manifest,
                      finalManifestSHA256=sha256(project / 'manifest.json'),
                      exportPath=str(export), exportSHA256=sha256(export),
                      exportFormat=format_info, bouncedNodeID=bounced['nodeID'],
                      eventCount=len(events.get('events', [])))
        (evidence / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        print(json.dumps(report, ensure_ascii=False))
    finally:
        reader.close()
        child.stdin.close()
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=5)


if __name__ == '__main__':
    main()
