#!/usr/bin/env python3
"""Bounded native MCP QA for job-only cancellation in an isolated circlr app.

The caller starts the integration-QA app and opens a disposable, saved .circlr
fixture first. This script never opens a project, starts/stops playback, or uses
the user's normal app socket. Choose a sufficiently long song: the export must
show nonzero render progress while still running before it can be cancelled.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from mcp.server import call_tool

QA_ROOT = Path.home() / 'Library/Application Support/circlr-integration-qa'
GENERATED_ROOT = ROOT / 'qa/generated'


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_paths(socket, project, evidence):
    socket = socket.resolve()
    project = project.resolve()
    evidence = evidence.resolve()
    require(socket == (QA_ROOT / 'Agent/agent.sock').resolve(), 'Only the integration-QA socket is allowed')
    require(socket.is_socket(), 'The integration-QA socket is not listening')
    require(project.is_relative_to((QA_ROOT / 'fixtures').resolve()) and project.suffix == '.circlr'
            and project.is_dir() and (project / 'manifest.json').is_file(),
            'Only an existing integration-QA .circlr fixture is allowed')
    require(evidence.is_relative_to(GENERATED_ROOT.resolve()) and evidence != GENERATED_ROOT.resolve()
            and not evidence.exists(), 'Evidence must be a new directory below qa/generated')
    return socket, project, evidence


def native_call(socket, name, arguments=None):
    response = call_tool(str(socket), 'circlr_' + name, arguments or {})
    payload = response['structuredContent']
    require(payload.get('ok') is True and response.get('isError') is False,
            f'circlr_{name} failed: {payload.get("error", payload)}')
    return payload['result']


def transport_state(state):
    playback = state['playback']
    recording = state['recording']
    return {'playing': playback['playing'], 'audioRecording': recording['audio'],
            'midiRecording': recording['midi'], 'recordingBusy': recording['busy'],
            'recordingPhase': recording['phase']}


def wait_for_render_progress(socket, job_id, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        job = native_call(socket, 'job', {'jobID': job_id})['job']
        require(job['id'] == job_id and job['kind'] == 'export',
                'Job identity or kind changed while rendering')
        require(job['state'] == 'running', f'Export ended before a cancellable render window: {job}')
        progress = job.get('progress', 0)
        if isinstance(progress, (int, float)) and 0 < progress < 1:
            return job
        time.sleep(0.1)
    raise TimeoutError('Export did not reach nonzero running render progress in time')


def wait_terminal(socket, job_id, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        job = native_call(socket, 'job', {'jobID': job_id})['job']
        require(job['id'] == job_id, 'Job identity changed after cancellation')
        if job['state'] != 'running':
            return job
        time.sleep(0.2)
    raise TimeoutError('Cancelled job did not reach a terminal state in time')


def run(socket, project, evidence, build, require_playing=False,
        progress_timeout=30, terminal_timeout=30, settle_seconds=2):
    socket, project, evidence = validate_paths(socket, project, evidence)
    report = {'schema': 'circlr-agent-cancel-qa-v1', 'status': 'FAIL',
              'build': build, 'project': str(project), 'socket': str(socket), 'checks': [],
              'limitations': ['This verifies a single native export job, not AI-session permission revocation.',
                              'Movie capture and audible output are not observed by this MCP snapshot.']}
    evidence.mkdir(parents=True, exist_ok=False)
    job_id = None
    try:
        state = native_call(socket, 'snapshot')
        require(state['runtime']['bundleID'] == 'com.circlr.integrationqa', 'Not the isolated QA app')
        require(state['runtime']['build'] == build, 'QA app build differs from the required build')
        require(state['runtime']['capabilities'].get('jobCancellation') == 1,
                'QA app lacks jobCancellation=1')
        require(Path(state['path']).resolve() == project and state['projectID'],
                'The active QA project differs from the selected fixture')
        require(not state['dirty'], 'Save the disposable fixture before this QA')
        before_revision = state['revision']
        before_transport = transport_state(state)
        require(not require_playing or before_transport['playing'],
                '--require-playing needs established native playback before this script')
        before_manifest = sha256(project / 'manifest.json')
        report.update(projectID=state['projectID'], revision=before_revision,
                      beforeManifestSHA256=before_manifest, beforeTransport=before_transport)
        report['checks'].append('isolated build, capability and exact saved fixture')

        export = (QA_ROOT / 'fixtures' / f'.circlr-cancel-qa-{uuid.uuid4().hex}.wav').resolve()
        require(export.parent == (QA_ROOT / 'fixtures').resolve() and not export.exists(),
                'Cancellation export destination is not new inside QA fixtures')
        report['exportPath'] = str(export)
        request = native_call(socket, 'export', {'projectID': state['projectID'],
                              'expectedRevision': before_revision, 'path': str(export)})
        job_id = request['jobID']
        require(request['state'] == 'running' and isinstance(job_id, str) and job_id,
                f'Export did not return a running job: {request}')
        report['jobID'] = job_id
        active = wait_for_render_progress(socket, job_id, progress_timeout)
        report['progressAtCancel'] = active['progress']
        report['checks'].append('native export observed running with nonzero render progress')

        cancelled = native_call(socket, 'cancel_job', {'projectID': state['projectID'],
                                                       'jobID': job_id})
        require(cancelled['job']['id'] == job_id and cancelled['job']['state'] == 'cancelled',
                f'Job-only cancellation did not cancel exact job: {cancelled}')
        terminal = wait_terminal(socket, job_id, terminal_timeout)
        require(terminal['state'] == 'cancelled', f'Cancelled job changed terminal state: {terminal}')
        again = native_call(socket, 'cancel_job', {'projectID': state['projectID'],
                                                   'jobID': job_id})
        require(again['job']['id'] == job_id and again['job']['state'] == 'cancelled',
                f'Repeated cancellation was not idempotent: {again}')
        report['checks'].append('exact job cancellation reaches terminal state and is idempotent')

        stage = export.parent / f'.circlr-agent-{job_id}.wav'
        time.sleep(settle_seconds)
        after = native_call(socket, 'snapshot')
        require(after['projectID'] == state['projectID'] and Path(after['path']).resolve() == project,
                'Active project changed after cancellation')
        require(after['revision'] == before_revision and not after['dirty'],
                'Music revision or dirty state changed after cancellation')
        require(sha256(project / 'manifest.json') == before_manifest,
                'Fixture manifest changed after cancellation')
        require(transport_state(after) == before_transport,
                'Playback/recording state changed during job-only cancellation')
        require(not export.exists() and not stage.exists(),
                'Cancelled export published a final or staging WAV')
        final_job = native_call(socket, 'job', {'jobID': job_id})['job']
        require(final_job['state'] == 'cancelled', 'Job state changed after settle period')
        report.update(status='PASS_BOUNDED_NATIVE_CANCEL', afterTransport=transport_state(after),
                      afterManifestSHA256=sha256(project / 'manifest.json'),
                      terminalJob=final_job, stagingPath=str(stage), settleSeconds=settle_seconds)
        report['checks'].append('no late final/staging WAV, music mutation or transport-state change')
        return report
    except Exception as error:
        report['error'] = repr(error)
        if job_id:
            try:
                current = native_call(socket, 'job', {'jobID': job_id})['job']
                report['jobAtFailure'] = current
                if current['state'] == 'running':
                    report['cleanupCancel'] = native_call(socket, 'cancel_job',
                        {'projectID': report['projectID'], 'jobID': job_id})['job']['state']
            except Exception as cleanup_error:
                report['cleanupError'] = repr(cleanup_error)
        raise
    finally:
        (evidence / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--socket', type=Path, required=True, help='Isolated integration-QA app socket')
    parser.add_argument('--project', type=Path, required=True, help='Already-open disposable .circlr fixture')
    parser.add_argument('--evidence', type=Path, required=True, help='New directory inside qa/generated')
    parser.add_argument('--build', required=True, help='Exact CFBundleVersion required')
    parser.add_argument('--require-playing', action='store_true', help='Require playback to be active and remain active')
    args = parser.parse_args()
    result = run(args.socket, args.project, args.evidence, args.build, args.require_playing)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
