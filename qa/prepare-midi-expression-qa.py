#!/usr/bin/env python3
"""Clone the task package with no-I/O helpers; never launch or replace a user app."""
import hashlib
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "dist/써클러.app"
HELPERS = ("circlr-output-worker", "circlr-au-effect-worker", "circlr-au-instrument-worker",
           "circlr-output-device-catalog", "circlr-audition-worker")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=int, default=134)
    parser.add_argument("--candidate", default="expression134")
    args = parser.parse_args()
    assert args.build > 0 and re.fullmatch(r"[a-z0-9-]{1,32}", args.candidate)
    OUT = ROOT / "qa/generated/midi-import-return" / args.candidate
    info = plistlib.loads((SOURCE / "Contents/Info.plist").read_bytes())
    assert str(info["CFBundleVersion"]) == str(args.build)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(SOURCE)], check=True)
    OUT.mkdir(parents=True, exist_ok=False)
    app = OUT / "써클러 통합 검증.app"
    shutil.copytree(SOURCE, app)
    info.update(CFBundleIdentifier="com.circlr.integrationqa", CFBundleName="써클러 통합 검증",
                CFBundleDisplayName="써클러 통합 검증")
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    mac = app / "Contents/MacOS"
    with tempfile.TemporaryDirectory(prefix="circlr-no-io-") as directory:
        stub = Path(directory) / "worker.c"
        stub.write_text("int main(void) { return 78; }\n")
        for name in HELPERS:
            target = mac / name
            target.unlink()
            subprocess.run(["clang", str(stub), "-o", str(target)], check=True)
            subprocess.run(["codesign", "--force", "--sign", "-", str(target)], check=True)
            assert subprocess.run([str(target)]).returncode == 78
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    uuid = lambda path: subprocess.check_output(["dwarfdump", "--uuid", str(path)], text=True).split()[1]
    assert uuid(mac / "circlr") == uuid(SOURCE / "Contents/MacOS/circlr")
    sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    (OUT / "package.json").write_text(json.dumps(dict(app=str(app), build=str(args.build),
        sourceUUID=uuid(mac / "circlr"), mainSHA256=sha(mac / "circlr"),
        helpers={name: sha(mac / name) for name in HELPERS}), ensure_ascii=False, indent=2) + "\n")
    print(app)
