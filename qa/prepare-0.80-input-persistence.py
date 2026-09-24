#!/usr/bin/env python3
"""Prepare (only) an isolated build239 GUI QA copy after lead clearance.

This script never launches Circlr or changes macOS audio devices. It refuses to
overwrite an existing QA copy, and records original/copy binary integrity.
"""

import hashlib
import json
import os
import plistlib
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "qa/generated/r80-build239-input-persistence"
SOURCE = ROOT / "dist/써클러.app"
QA_ROOT = ROOT / ".build/build239-input-persistence"
APP = QA_ROOT / "써클러 build239 입력 지속성 검증.app"
BUNDLE_ID = "com.circlr.build239inputqa"
EXPECTED_EXE = "f87136cef6f5453bcfd7aa034cb75bf4d49873efea267a6aad8d0b166ace9314"


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree(path: Path) -> dict[str, str]:
    result = {}
    for item in sorted(path.rglob("*")):
        relative = item.relative_to(path).as_posix()
        if item.is_symlink():
            result[relative] = "SYMLINK:" + os.readlink(item)
        elif item.is_file():
            result[relative] = sha(item)
    return result


def run(*args: str) -> None:
    subprocess.run(args, check=True)


def main() -> None:
    assert SOURCE.is_dir(), f"Missing source app: {SOURCE}"
    assert not QA_ROOT.exists(), f"QA root already exists; refusing overwrite: {QA_ROOT}"
    info = plistlib.loads((SOURCE / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "com.circlr.desktop"
    assert info["CFBundleShortVersionString"] == "0.80.0"
    assert info["CFBundleVersion"] == "239"
    run("codesign", "--verify", "--deep", "--strict", str(SOURCE))
    before = tree(SOURCE)
    assert before["Contents/MacOS/circlr"] == EXPECTED_EXE

    QA_ROOT.mkdir(parents=True, mode=0o700)
    run("ditto", str(SOURCE), str(APP))
    qa_info_path = APP / "Contents/Info.plist"
    qa_info = plistlib.loads(qa_info_path.read_bytes())
    qa_info.update(
        CFBundleIdentifier=BUNDLE_ID,
        CFBundleName="써클러 build239 입력 지속성 검증",
        CFBundleDisplayName="써클러 build239 입력 지속성 검증",
    )
    for key in (
        "CFBundleDocumentTypes",
        "UTExportedTypeDeclarations",
        "UTImportedTypeDeclarations",
        "CFBundleURLTypes",
    ):
        qa_info.pop(key, None)
    qa_info_path.write_bytes(plistlib.dumps(qa_info))
    run("codesign", "--force", "--deep", "--sign", "-", str(APP))
    run("codesign", "--verify", "--deep", "--strict", str(APP))

    assert tree(SOURCE) == before, "Original bundle changed during clone"
    after = tree(APP)
    unchanged = {
        rel: digest
        for rel, digest in before.items()
        if rel.startswith("Contents/Resources/")
        or (rel.startswith("Contents/MacOS/") and rel != "Contents/MacOS/circlr")
    }
    assert all(after.get(rel) == digest for rel, digest in unchanged.items())
    result = {
        "source": str(SOURCE),
        "qaApp": str(APP),
        "qaBundleID": BUNDLE_ID,
        "sourceVersion": "0.80.0",
        "sourceBuild": "239",
        "sourceExecutableSHA256": before["Contents/MacOS/circlr"],
        "qaExecutableSHA256": after["Contents/MacOS/circlr"],
        "sourceManifestSHA256": before["Contents/Resources/Demos/manifest.json"],
        "resourcesAndHelpersByteIdentical": True,
        "resourceCount": sum(rel.startswith("Contents/Resources/") for rel in unchanged),
        "helperCount": sum(rel.startswith("Contents/MacOS/") for rel in unchanged),
        "sourceUnchangedAfterCopy": True,
        "codesignDeepStrict": True,
    }
    EVIDENCE.mkdir(parents=True, mode=0o700, exist_ok=True)
    output = EVIDENCE / "bundle-integrity.json"
    assert not output.exists(), f"Refusing overwrite: {output}"
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
