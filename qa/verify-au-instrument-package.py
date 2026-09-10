#!/usr/bin/env python3
"""Package Release in a temporary project and run opt-in AU instrument PCM integration, never user's dist."""
import argparse
import json
import os
from pathlib import Path
import runpy
import re
import shutil
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, default=ROOT / '.build/integration-release/release/circlr')
    parser.add_argument('--scratch-path', type=Path, default=ROOT / '.build/integration-tests')
    parser.add_argument('--log', type=Path, help='Exclusive new combined stdout/stderr log')
    args = parser.parse_args()
    log = args.log.open('x') if args.log else None
    records = []
    def run(command, timeout=30, env=None):
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, start_new_session=True)
        try:
            output, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate(timeout=5)
            if log: log.write(output); log.flush()
            raise RuntimeError(f'Command exceeded {timeout}s: {command[0]}')
        if log: log.write(output); log.flush()
        records.append({'command': str(command[0]), 'returncode': process.returncode})
        if process.returncode:
            if not log: print(output, file=sys.stderr)
            raise RuntimeError(f'Command failed ({process.returncode}): {command[0]}')
        return output
    try:
        with tempfile.TemporaryDirectory(prefix='circlr-au-instrument-package-qa-') as temp:
            root = Path(temp)
            (root / 'scripts').mkdir(); (root / 'mcp').mkdir()
            for name in ['package-app.py', 'build-agent-kit.py']:
                shutil.copy2(ROOT / 'scripts' / name, root / 'scripts' / name)
            shutil.copy2(ROOT / 'mcp/server.py', root / 'mcp/server.py')
            shutil.copytree(ROOT / 'Resources', root / 'Resources', ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
            binary = args.binary.resolve()
            run([sys.executable, str(root / 'scripts/package-app.py'), str(binary)])
            app = root / 'dist/써클러.app'
            helper = app / 'Contents/MacOS/circlr-au-instrument-worker'
            sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
            assert sections(binary.with_name(helper.name)) == sections(helper), 'Packaged helper Mach-O sections changed'
            assert os.access(helper, os.X_OK)
            run(['codesign', '--verify', '--deep', '--strict', str(app)])
            uuid = run(['dwarfdump', '--uuid', str(helper)]).strip()
            env = dict(os.environ, CIRCLR_AU_INSTRUMENT_WORKER_TEST_EXECUTABLE=str(helper))
            output = run([str(ROOT / 'scripts/swift-local.sh'), 'test', '--skip-build', '--scratch-path',
                          str(args.scratch_path.resolve()), '--filter', 'AUInstrumentWorkerIntegrationTests.testSoundBankAndCapturedSamplerMatchOfflineReference'], timeout=120, env=env)
            metrics = [line for line in output.splitlines() if line.startswith('AU_INSTRUMENT_PCM_MATCH ')]
            assert len(metrics) == 4, 'Expected four instrument PCM comparisons; skipped or missing test is not a pass'
            assert len(set(metrics)) == 4, 'Duplicate instrument PCM measurements'
            assert re.search(r'Executed 1 tests?, with 0 failures', output), 'Instrument integration test did not pass'
            print(json.dumps({'status': 'passed', 'packagedHelperUUID': uuid, 'pcmMeasurements': metrics,
                              'commands': records, 'physicalAudio': 'not requested', 'temporaryPackage': True}, ensure_ascii=False))
    finally:
        if log: log.close()


if __name__ == '__main__':
    main()
