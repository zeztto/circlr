#!/usr/bin/env python3
"""Build/run the offline tail probe into a NEW output directory; never overwrite.

Example:
  python3 qa/probe-bounce-tail.py qa/generated/bounce-tail-20260910
Use --skip-build only when the selected scratch already contains current modules.
Generated executable, WAV, logs and result.json are evidence, not product assets.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new evidence directory (must not exist)")
    parser.add_argument("--scratch", type=Path, default=ROOT / ".build/bounce-audio-tests")
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    output = args.output.resolve()
    scratch = args.scratch.resolve()
    output.mkdir(parents=True, exist_ok=False)
    commands = []

    def run(command, log):
        commands.append(command)
        with (output / log).open("x") as handle:
            subprocess.run(command, cwd=ROOT, stdout=handle, stderr=subprocess.STDOUT, check=True)

    if not args.skip_build:
        run([str(ROOT / "scripts/swift-local.sh"), "build", "--scratch-path", str(scratch), "--target", "CirclrAudio"], "build.log")
    build = scratch / "debug"
    if not (build / "Modules/CirclrAudio.swiftmodule").exists():
        candidates = [p.parent.parent for p in scratch.glob("*/debug/Modules/CirclrAudio.swiftmodule")]
        if len(candidates) != 1:
            raise RuntimeError("Current compiled modules not found; run without --skip-build")
        build = candidates[0]
    objects = []
    for module in ("CirclrCore", "CirclrAudio", "CirclrRealtime"):
        found = sorted((build / (module + ".build")).glob("*.o"))
        if not found:
            raise RuntimeError(f"Missing compiled objects: {module}")
        objects.extend(str(path) for path in found)
    swiftc = shutil.which("swiftc")
    if not swiftc:
        raise RuntimeError("swiftc is required (same PATH toolchain as scripts/swift-local.sh)")
    executable = output / "probe"
    run([swiftc, "-parse-as-library", "-I", str(build / "Modules"), "-I", str(build / "CirclrRealtime.build"),
         str(ROOT / "qa/probe-bounce-tail.swift"), *objects, "-o", str(executable)], "compile.log")
    run([str(executable), str(output)], "probe.log")
    report = json.loads((output / "probe.log").read_text())
    with (output / "result.json").open("x") as handle:
        json.dump(report, handle, indent=2); handle.write("\n")
    with (output / "commands.json").open("x") as handle:
        json.dump({"scratch": str(scratch), "skipBuild": args.skip_build, "commands": commands}, handle, indent=2)
        handle.write("\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
