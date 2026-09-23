#!/usr/bin/env python3
"""Bounded native QA for cancelling an export *during* its private WAV stage.

Start the isolated com.circlr.integrationqa app and open a saved, disposable,
long-form .circlr fixture first. This script cannot connect to the normal app.
It does not change transport or the project. If the stage window is missed, the
result is NOT_OBSERVED, never a cancellation PASS.
"""
import argparse
import hashlib
import json
from pathlib import Path
import stat
import sys
import time
import uuid
import wave

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from mcp.server import call_tool

QA_ROOT = Path.home() / 'Library/Application Support/circlr-integration-qa'
GENERATED_ROOT = ROOT / 'qa/generated'


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def validate_paths(socket, project, evidence):
    qa = QA_ROOT.resolve()
    socket, project, evidence = socket.resolve(), project.resolve(), evidence.resolve()
    require(socket == qa / 'Agent/agent.sock' and socket.is_socket(),
            'Only the listening integration-QA socket is allowed')
    require(project.is_relative_to(qa / 'fixtures') and project.suffix == '.circlr'
            and project.is_dir() and (project / 'manifest.json').is_file(),
            'Only an existing integration-QA .circlr fixture is allowed')
    require(evidence.is_relative_to(GENERATED_ROOT.resolve())
            and evidence != GENERATED_ROOT.resolve() and not evidence.exists(),
            'Evidence must be a new directory below qa/generated')
    return socket, project, evidence


def native_call(socket, name, arguments=None):
    response = call_tool(str(socket), 'circlr_' + name, arguments or {})
    payload = response['structuredContent']
    require(payload.get('ok') is True and response.get('isError') is False,
            f'circlr_{name} failed: {payload.get("error", payload)}')
    return payload['result']


def transport_state(state):
    recording = state['recording']
    return {'playing': state['playback']['playing'], 'audioRecording': recording['audio'],
            'midiRecording': recording['midi'], 'recordingBusy': recording['busy'],
            'recordingPhase': recording['phase']}


def stage_bytes(path):
    """Reject unexpected symlinks; size > WAV header proves PCM bytes were written."""
    try:
        item = path.lstat()
    except FileNotFoundError:
        return 0
    require(stat.S_ISREG(item.st_mode), 'Private WAV stage is not a regular file')
    return item.st_size


def require_job_id(value):
    require(isinstance(value, str) and len(value) == 36,
            'Native jobID must be a UUID')
    try:
        uuid.UUID(value)
    except ValueError as error:
        raise AssertionError('Native jobID must be a UUID') from error
    return value


def classify_stage_cancel(stage_size, pre_cancel_state, cancel_state):
    """Pure decision boundary: terminal-before-cancel can never be a PASS."""
    if stage_size <= 44 or pre_cancel_state != 'running':
        return 'NOT_OBSERVED'
    if cancel_state == 'completed':
        return 'NOT_OBSERVED'
    require(cancel_state == 'cancelled', f'Unexpected cancel_job result: {cancel_state}')
    return 'VERIFY_CANCELLED'


def job(socket, job_id, kind='export'):
    item = native_call(socket, 'job', {'jobID': job_id})['job']
    require(item['id'] == job_id and item['kind'] == kind,
            'Job identity or kind changed')
    return item


def wait_for_stage(socket, job_id, stage, final, timeout, poll_seconds):
    deadline = time.monotonic() + timeout
    last_job_poll = 0.0
    while time.monotonic() < deadline:
        size = stage_bytes(stage)
        if size > 44:
            current = job(socket, job_id)
            # The stage must still exist while the job is running, immediately
            # before cancel_job. A completed render can remove it in this gap.
            confirmed_size = stage_bytes(stage)
            if current['state'] == 'running' and confirmed_size > 44 and not final.exists():
                return confirmed_size, current
            if current['state'] != 'running':
                return 0, current
        now = time.monotonic()
        if now - last_job_poll >= 0.2:
            current = job(socket, job_id)
            if current['state'] != 'running':
                return 0, current
            last_job_poll = now
        time.sleep(poll_seconds)
    raise TimeoutError('Export stayed running but no data-bearing WAV stage appeared')


def wait_terminal(socket, job_id, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        current = job(socket, job_id)
        if current['state'] != 'running':
            return current
        time.sleep(0.1)
    raise TimeoutError('Export did not reach a terminal state in time')


def wait_stage_cleanup(stage, final, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        require(not final.exists(), 'Cancelled export published a final WAV')
        if not stage.exists():
            return
        time.sleep(0.05)
    raise TimeoutError('Cancelled private WAV stage was not removed in time')


def verify_wav(path):
    with wave.open(str(path), 'rb') as audio:
        info = {'channels': audio.getnchannels(), 'sampleRate': audio.getframerate(),
                'bitsPerSample': audio.getsampwidth() * 8, 'frames': audio.getnframes()}
        require(info['channels'] == 2 and info['sampleRate'] == 48000
                and info['bitsPerSample'] == 24 and info['frames'] > 48000,
                f'Retry WAV format is invalid: {info}')
        signal = False
        while frames := audio.readframes(8192):
            if any(frames):
                signal = True
                break
        require(signal, 'Retry WAV has no audio signal')
    return info


def run(socket, project, evidence, build, stage_timeout=180, terminal_timeout=180,
        cleanup_timeout=30, settle_seconds=2, poll_seconds=0.01):
    socket, project, evidence = validate_paths(socket, project, evidence)
    require(stage_timeout > 0 and terminal_timeout > 0 and cleanup_timeout > 0
            and settle_seconds >= 0 and poll_seconds > 0, 'Invalid QA timeout')
    report = {'schema': 'circlr-agent-stage-cancel-qa-v1', 'status': 'FAIL',
              'build': build, 'project': str(project), 'socket': str(socket),
              'checks': [], 'limitations': [
                  'Only native export staging is covered; bounce staging is not exercised.',
                  'Physical audio output and GUI behavior are not observed.']}
    evidence.mkdir(parents=True, exist_ok=False)
    active_ids = []
    try:
        state = native_call(socket, 'snapshot')
        require(state['runtime']['bundleID'] == 'com.circlr.integrationqa'
                and state['runtime']['build'] == build
                and state['runtime']['capabilities'].get('jobCancellation') == 1,
                'The socket must belong to the requested integration-QA build')
        require(Path(state['path']).resolve() == project and state['projectID'] and not state['dirty'],
                'The active project must be the saved disposable fixture')
        initial_revision = state['revision']
        initial_layout = state['layoutRevision']
        initial_manifest = sha256(project / 'manifest.json')
        initial_transport = transport_state(state)
        report.update(projectID=state['projectID'], initialRevision=initial_revision,
                      initialLayoutRevision=initial_layout,
                      beforeManifestSHA256=initial_manifest,
                      beforeTransport=initial_transport)
        report['checks'].append('exact isolated build and saved QA fixture')

        final = (QA_ROOT.resolve() / 'fixtures' / f'.circlr-stage-cancel-{uuid.uuid4().hex}.wav')
        require(not final.exists(), 'QA export destination already exists')
        started = native_call(socket, 'export', {'projectID': state['projectID'],
                              'expectedRevision': initial_revision, 'path': str(final)})
        job_id = require_job_id(started['jobID'])
        require(started['state'] == 'running',
                f'Export did not start: {started}')
        active_ids.append(job_id)
        stage = final.parent / f'.circlr-agent-{job_id}.wav'
        report.update(jobID=job_id, exportPath=str(final), stagingPath=str(stage))
        size, current = wait_for_stage(socket, job_id, stage, final, stage_timeout, poll_seconds)
        report.update(stageBytesAtDecision=size, jobAtStageDecision=current)
        if size == 0:
            require(current['state'] == 'completed',
                    f'Export terminated before stage observation: {current}')
            require(final.is_file(), 'Completed export has no final WAV')
            active_ids.remove(job_id)
            report['status'] = 'NOT_OBSERVED'
            report['reason'] = 'Export completed before a data-bearing stage could be observed while running'
            report['completedExportSHA256'] = sha256(final)
            return report
        report['checks'].append('data-bearing private WAV stage observed with exact job running')

        cancelled = native_call(socket, 'cancel_job', {'projectID': state['projectID'],
                                                       'jobID': job_id})['job']
        decision = classify_stage_cancel(size, current['state'], cancelled['state'])
        report['cancelResponse'] = cancelled
        if decision == 'NOT_OBSERVED':
            require(final.is_file(), 'Completed export has no final WAV')
            active_ids.remove(job_id)
            report['status'] = decision
            report['reason'] = 'Stage was seen, but the job completed before cancellation took effect'
            report['completedExportSHA256'] = sha256(final)
            return report
        terminal = wait_terminal(socket, job_id, terminal_timeout)
        require(terminal['state'] == 'cancelled', f'Cancelled job changed state: {terminal}')
        active_ids.remove(job_id)
        repeated = native_call(socket, 'cancel_job', {'projectID': state['projectID'],
                                                      'jobID': job_id})['job']
        require(repeated['id'] == job_id and repeated['state'] == 'cancelled',
                f'Cancellation was not idempotent: {repeated}')
        report['checks'].append('exact job cancelled and repeated cancellation is idempotent')

        wait_stage_cleanup(stage, final, cleanup_timeout)
        time.sleep(settle_seconds)
        after = native_call(socket, 'snapshot')
        require(Path(after['path']).resolve() == project
                and after['projectID'] == state['projectID']
                and after['revision'] == initial_revision
                and after['layoutRevision'] == initial_layout
                and not after['dirty'], 'Project changed after stage cancellation')
        require(sha256(project / 'manifest.json') == initial_manifest,
                'Manifest changed after stage cancellation')
        require(transport_state(after) == initial_transport,
                'Transport or recording changed after stage cancellation')
        require(not stage.exists() and not final.exists(),
                'Cancelled job wrote a late staging or final WAV')
        require(job(socket, job_id)['state'] == 'cancelled',
                'Cancelled job state changed after settling')
        report['checks'].append('no late WAV or document/transport mutation')

        retry = final.with_name(final.stem + '-retry.wav')
        require(not retry.exists(), 'QA retry destination already exists')
        retry_start = native_call(socket, 'export', {'projectID': state['projectID'],
                                  'expectedRevision': initial_revision, 'path': str(retry)})
        retry_id = require_job_id(retry_start['jobID'])
        require(retry_start['state'] == 'running' and retry_id != job_id,
                f'Retry did not start as a new job: {retry_start}')
        active_ids.append(retry_id)
        retry_terminal = wait_terminal(socket, retry_id, terminal_timeout)
        require(retry_terminal['state'] == 'completed' and retry.is_file(),
                f'Retry export did not complete: {retry_terminal}')
        active_ids.remove(retry_id)
        retry_format = verify_wav(retry)
        final_state = native_call(socket, 'snapshot')
        require(Path(final_state['path']).resolve() == project
                and final_state['projectID'] == state['projectID']
                and final_state['revision'] == initial_revision
                and final_state['layoutRevision'] == initial_layout
                and not final_state['dirty']
                and sha256(project / 'manifest.json') == initial_manifest,
                'Retry export changed the saved project')
        require(transport_state(final_state) == initial_transport,
                'Retry export changed transport or recording')
        require(not stage.exists() and not final.exists(),
                'Cancelled job wrote a WAV after retry completed')
        report.update(status='PASS_BOUNDED_NATIVE_STAGE_CANCEL',
                      settleSeconds=settle_seconds, terminalJob=terminal,
                      retryJob=retry_terminal, retryPath=str(retry),
                      retrySHA256=sha256(retry), retryFormat=retry_format,
                      afterManifestSHA256=sha256(project / 'manifest.json'),
                      afterTransport=transport_state(final_state))
        report['checks'].append('new export succeeds as 48 kHz stereo 24-bit nonzero WAV')
        return report
    except Exception as error:
        report['error'] = repr(error)
        return report
    finally:
        for job_id in active_ids:
            try:
                current = job(socket, job_id)
                if current['state'] == 'running':
                    native_call(socket, 'cancel_job', {'projectID': report['projectID'],
                                                       'jobID': job_id})
                    report.setdefault('cleanupCancelled', []).append(job_id)
            except Exception as cleanup_error:
                report.setdefault('cleanupErrors', []).append(repr(cleanup_error))
        (evidence / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--socket', type=Path, required=True)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--stage-timeout', type=float, default=180)
    parser.add_argument('--terminal-timeout', type=float, default=180)
    parser.add_argument('--cleanup-timeout', type=float, default=30)
    parser.add_argument('--settle-seconds', type=float, default=2)
    parser.add_argument('--poll-seconds', type=float, default=0.01)
    args = parser.parse_args()
    report = run(args.socket, args.project, args.evidence, args.build,
                 args.stage_timeout, args.terminal_timeout, args.cleanup_timeout,
                 args.settle_seconds, args.poll_seconds)
    print(json.dumps(report, ensure_ascii=False))
    raise SystemExit(exit_code_for_status(report['status']))


def exit_code_for_status(status):
    return {'PASS_BOUNDED_NATIVE_STAGE_CANCEL': 0, 'NOT_OBSERVED': 3}.get(status, 1)


if __name__ == '__main__':
    main()
