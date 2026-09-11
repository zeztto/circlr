#!/usr/bin/env python3
"""Candidate output-worker IPC smoke; sends only stop and EOF, never play/prepare."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import selectors
import subprocess
import tempfile
import time
import uuid


class Wire:
    def __init__(self, process, session):
        self.session = session
        self.sequence = 0
        self.pending = b""
        self.fd = process.stdout.fileno()
        self.selector = selectors.DefaultSelector()
        self.selector.register(process.stdout, selectors.EVENT_READ)

    def receive(self, timeout):
        deadline = time.monotonic() + timeout
        while b"\n" not in self.pending:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not self.selector.select(remaining):
                raise TimeoutError("worker response timeout")
            data = os.read(self.fd, 4096)
            if not data:
                raise RuntimeError("unexpected worker EOF")
            self.pending += data
            if len(self.pending) > 16384:
                raise RuntimeError("oversized worker response")
        line, self.pending = self.pending.split(b"\n", 1)
        packet = json.loads(line)
        self.sequence += 1
        if (packet.get("version") != 1 or packet.get("session", "").lower() != self.session.lower()
                or packet.get("sequence") != self.sequence):
            raise RuntimeError("protocol/session/sequence mismatch")
        return packet


def smoke(helper, mode, timeout):
    start = time.monotonic()
    result = {"mode": mode, "status": "FAIL", "session": str(uuid.uuid4()), "events": [],
              "cleanup_actions": [], "physical_io_requested": False}
    process = None
    wire = None
    directory = Path(tempfile.mkdtemp(prefix="circlr-r30-lifecycle-"))
    os.chmod(directory, 0o700)
    try:
        process = subprocess.Popen([str(helper), "--session", result["session"], "--directory", str(directory)],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        result["owned_pid"] = process.pid
        wire = Wire(process, result["session"])
        hello = wire.receive(timeout)
        result["events"].append(hello)
        if hello.get("payload") != {"helloCapabilities": {"outputDeviceSelection": True}}:
            raise RuntimeError("unexpected hello capabilities")
        if mode == "stop_then_eof":
            command = {"version": 1, "session": result["session"], "sequence": 1,
                       "payload": {"stop": {"run": result["session"]}}}
            process.stdin.write(json.dumps(command).encode() + b"\n")
            process.stdin.flush()
            response = wire.receive(timeout)
            result["events"].append(response)
            run = response.get("payload", {}).get("stopped", {}).get("run", "")
            if run.lower() != result["session"].lower() or set(response.get("payload", {})) != {"stopped"}:
                raise RuntimeError("unexpected stop acknowledgement")
        process.stdin.close()
        result["cleanup_actions"].append("stdin_eof")
        result["exit_code"] = process.wait(timeout=timeout)
        if result["exit_code"] != 0:
            raise RuntimeError("worker exited unsuccessfully")
        result["status"] = "PASS"
    except Exception as error:
        result["error"] = f"{type(error).__name__}: {error}"
    finally:
        if process is not None:
            if process.stdin and not process.stdin.closed:
                try:
                    process.stdin.close()
                except (BrokenPipeError, OSError):
                    pass
                result["cleanup_actions"].append("stdin_eof")
            if process.poll() is None:
                try:
                    process.wait(timeout=0.5)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    result["cleanup_actions"].append("owned_process_term")
                    try:
                        process.wait(timeout=0.5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        result["cleanup_actions"].append("owned_process_kill")
                        try:
                            process.wait(timeout=1)
                        except subprocess.TimeoutExpired:
                            result["error"] = "owned process did not reap after SIGKILL"
            result["exit_code"] = process.poll()
            result["process_reaped"] = process.returncode is not None
            if not result["process_reaped"]:
                result["status"] = "FAIL"
            if wire:
                wire.selector.close()
            process.stdout.close()
        try:
            # Neither mode should create files; preserve unexpected evidence instead of deleting it.
            directory.rmdir()
            result["directory_removed"] = True
        except OSError as error:
            result.update(status="FAIL", directory_removed=False, preserved_directory=str(directory),
                          cleanup_error=str(error))
        result["elapsed_seconds"] = round(time.monotonic() - start, 3)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path, help="Explicit candidate .app package; never auto-detected")
    parser.add_argument("--timeout", type=float, default=2, help="Per response/exit deadline, 0 < seconds <= 10")
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or not 0 < args.timeout <= 10:
        parser.error("timeout must be finite and in (0, 10]")
    app = args.app.resolve(strict=True)
    helper = app / "Contents/MacOS/circlr-output-worker"
    if app.suffix != ".app" or not helper.is_file() or not os.access(helper, os.X_OK):
        parser.error("candidate must contain executable Contents/MacOS/circlr-output-worker")
    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    digest = hashlib.sha256(helper.read_bytes()).hexdigest()
    report = {"schema": "r30-audio-lifecycle-v1", "app": str(app), "helper": str(helper),
              "helper_sha256": digest, "version": info.get("CFBundleShortVersionString"),
              "build": info.get("CFBundleVersion"), "scope": "IPC only; Q06/Q07 remain NOT_RUN",
              "cases": [smoke(helper, mode, args.timeout) for mode in ("hello_then_eof", "stop_then_eof")]}
    report["helper_sha256_after"] = hashlib.sha256(helper.read_bytes()).hexdigest()
    report["status"] = "PASS" if (all(case["status"] == "PASS" for case in report["cases"])
                                     and report["helper_sha256_after"] == digest) else "FAIL"
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
