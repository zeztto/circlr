#!/usr/bin/env python3
"""Run real CoreAudio output tests with a hard deadline and process-group cleanup."""

import argparse
import os
from pathlib import Path
import signal
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", type=Path, required=True)
    parser.add_argument("--scratch", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timeout", type=float, default=60)
    args = parser.parse_args()
    if not args.worker.is_file() or not 1 <= args.timeout <= 120:
        parser.error("worker must exist and timeout must be 1–120 seconds")
    env = dict(os.environ, CIRCLR_AUDIOQUEUE_NATIVE_QA="1",
               CIRCLR_OUTPUT_WORKER=str(args.worker.resolve()))
    command = [str(ROOT / "scripts/swift-local.sh"), "test", "--scratch-path",
               str(args.scratch), "--filter", "OutputWorkerNativeAudioQueueTests"]
    with args.output.open("x", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)

        def stop_process_group():
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                log.write("\nQA_REAP_TIMEOUT: process did not exit within 5 seconds of SIGKILL\n")

        try:
            try:
                result = process.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                stop_process_group()
                log.write("\nQA_TIMEOUT: killed the test process group\n")
                result = 124
        except BaseException:
            stop_process_group()
            raise
    print(f"exit={result} log={args.output}")
    raise SystemExit(result)


if __name__ == "__main__":
    main()
