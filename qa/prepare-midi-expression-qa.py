#!/usr/bin/env python3
"""Clone the task package with no-I/O helpers; never launch or replace a user app."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "dist/써클러.app"
OUT = ROOT / "qa/generated/midi-import-return/expression134"
HELPERS = ("circlr-output-worker", "circlr-au-effect-worker", "circlr-au-instrument-worker",
           "circlr-output-device-catalog", "circlr-audition-worker")


if __name__ == "__main__":
    info = plistlib.loads((SOURCE / "Contents/Info.plist").read_bytes())
    assert str(info["CFBundleVersion"]) == "134"
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
    (OUT / "package.json").write_text(json.dumps(dict(app=str(app), build="134",
        sourceUUID=uuid(mac / "circlr"), mainSHA256=sha(mac / "circlr"),
        helpers={name: sha(mac / name) for name in HELPERS}), ensure_ascii=False, indent=2) + "\n")
    print(app)
