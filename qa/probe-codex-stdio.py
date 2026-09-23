#!/usr/bin/env python3
"""Bounded, credential-free Codex App Server initialize probe.

This checks only the installed CLI's stdio handshake. It never starts a model
turn, requests account details, or records raw server output.
"""

import argparse
import json
import os
import selectors
import shutil
import subprocess
import time


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cli", default=shutil.which("codex"))
    parser.add_argument("--timeout", type=float, default=10.0)
    args = parser.parse_args()
    if not args.cli or not os.path.isfile(args.cli):
        parser.error("an installed Codex CLI executable is required")
    if not 0 < args.timeout <= 30:
        parser.error("timeout must be in (0, 30] seconds")

    child = subprocess.Popen(
        [args.cli, "app-server", "--stdio"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=0,
    )
    selector = selectors.DefaultSelector()
    assert child.stdin is not None and child.stdout is not None
    selector.register(child.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + args.timeout
    pending = bytearray()
    try:
        request = {
            "id": 1,
            "method": "initialize",
            "params": {"clientInfo": {"name": "circlr-qa", "title": "circlr QA", "version": "0.80.0"}},
        }
        child.stdin.write((json.dumps(request, separators=(",", ":")) + "\n").encode())
        child.stdin.flush()
        while time.monotonic() < deadline:
            for key, _ in selector.select(min(0.2, max(0, deadline - time.monotonic()))):
                chunk = os.read(key.fd, 65536)
                if not chunk:
                    raise RuntimeError("App Server closed stdio before initialize")
                pending.extend(chunk)
                if len(pending) > 1_048_576:
                    raise RuntimeError("initialize response exceeded 1 MiB")
                while b"\n" in pending:
                    line, _, rest = pending.partition(b"\n")
                    pending = bytearray(rest)
                    packet = json.loads(line)
                    if packet.get("id") != 1:
                        continue
                    result = packet.get("result")
                    print(json.dumps({
                        "initializeSucceeded": isinstance(result, dict),
                        "resultKeys": sorted(result) if isinstance(result, dict) else [],
                        "errorCode": packet.get("error", {}).get("code")
                        if isinstance(packet.get("error"), dict) else None,
                    }, sort_keys=True))
                    if not isinstance(result, dict):
                        raise RuntimeError("App Server rejected initialize")
                    return
        raise TimeoutError("App Server initialize response timed out")
    finally:
        selector.close()
        if child.poll() is None:
            child.terminate()
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait(timeout=5)


if __name__ == "__main__":
    main()
