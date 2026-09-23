#!/usr/bin/env python3
"""Copy a signed QA app and demo with one distant layout-only satellite.

The source app and bundled demo are read-only. Existing QA output is never
overwritten, even after a partial preparation failure.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def tree_digest(root):
    hasher = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            entry = ["symlink", relative, str(path.readlink())]
        elif path.is_file():
            entry = ["file", relative, digest(path)]
        else:
            continue
        hasher.update((json.dumps(entry, ensure_ascii=False) + "\n").encode())
    return hasher.hexdigest()


def run(*args):
    subprocess.run(args, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", required=True, type=int)
    parser.add_argument("--runtime-root", type=Path,
                        help="Documents 접근 요청 없이 실행할 별도 QA 사본의 부모 폴더")
    args = parser.parse_args()
    if args.build <= 190:
        parser.error("port-focus QA starts at build 191")
    source_app = ROOT / "dist/써클러.app"
    source_demo = source_app / "Contents/Resources/Demos/f0r-h3r.circlr"
    destination = ROOT / "qa/generated/port-focus" / f"build{args.build}"
    qa_app = destination / "써클러 포트 검증.app"
    fixture = destination / "fixtures" / f"f0r-h3r-port-focus-build{args.build}.circlr"
    runtime_destination = args.runtime_root.expanduser() / f"build{args.build}" if args.runtime_root else None
    if destination.exists() or destination.is_symlink():
        parser.error(f"기존 QA 증거를 보존합니다: {destination}")
    if runtime_destination is not None:
        if not runtime_destination.is_absolute():
            parser.error("--runtime-root는 절대 경로여야 합니다")
        if runtime_destination.exists() or runtime_destination.is_symlink():
            parser.error(f"기존 실행용 QA 사본을 보존합니다: {runtime_destination}")
    info = plistlib.loads((source_app / "Contents/Info.plist").read_bytes())
    if (info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")) != ("0.80.0", str(args.build)):
        parser.error("dist 앱의 버전/build가 요청과 다릅니다")
    run("codesign", "--verify", "--deep", "--strict", str(source_app))
    source_app_hash = tree_digest(source_app)
    source_demo_hash = tree_digest(source_demo)
    source_manifest = (source_demo / "manifest.json").read_bytes()
    original = json.loads(source_manifest)
    project = copy.deepcopy(original)
    section = project["sections"][0]
    outlier = next(node["id"] for node in section["graph"]["nodes"] if node["id"].startswith("fx:"))
    positions = section["graph"]["layout"]["positions"]
    before = copy.deepcopy(positions[outlier])
    after = {"x": 12000, "y": 0}
    if before == after:
        parser.error("outlier 위치가 이미 사용 중입니다")
    positions[outlier] = after
    project["id"] = str(uuid.uuid5(uuid.NAMESPACE_URL, f"circlr/port-focus/build{args.build}/f0r-h3r")).upper()
    # The fixture is musical-content identical: only the project identity and
    # one saved visual position differ from the bundled demo.
    comparison = copy.deepcopy(project)
    comparison["id"] = original["id"]
    comparison["sections"][0]["graph"]["layout"]["positions"][outlier] = before
    if comparison != original:
        raise RuntimeError("QA fixture changed content outside identity/layout")
    destination.mkdir(parents=True, exist_ok=False)
    run("ditto", str(source_app), str(qa_app))
    qa_info_path = qa_app / "Contents/Info.plist"
    qa_info = plistlib.loads(qa_info_path.read_bytes())
    qa_info.update(CFBundleIdentifier="com.circlr.portfocusqa", CFBundleName="써클러 포트 검증",
                   CFBundleDisplayName="써클러 포트 검증")
    for key in ("CFBundleDocumentTypes", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations", "CFBundleURLTypes"):
        qa_info.pop(key, None)
    qa_info_path.write_bytes(plistlib.dumps(qa_info))
    run("codesign", "--force", "--deep", "--sign", "-", str(qa_app))
    run("codesign", "--verify", "--deep", "--strict", str(qa_app))
    fixture.parent.mkdir()
    shutil.copytree(source_demo, fixture)
    (fixture / "manifest.json").write_text(json.dumps(project, ensure_ascii=False, indent=2) + "\n")
    if tree_digest(source_app) != source_app_hash or tree_digest(source_demo) != source_demo_hash:
        raise RuntimeError("QA 준비 중 원본이 변경됐습니다")
    runtime = None
    if runtime_destination is not None:
        runtime_destination.mkdir(parents=True, exist_ok=False)
        runtime_app = runtime_destination / qa_app.name
        runtime_fixture = runtime_destination / fixture.name
        run("ditto", str(qa_app), str(runtime_app))
        shutil.copytree(fixture, runtime_fixture)
        run("codesign", "--verify", "--deep", "--strict", str(runtime_app))
        if tree_digest(runtime_app) != tree_digest(qa_app) or tree_digest(runtime_fixture) != tree_digest(fixture):
            raise RuntimeError("실행용 QA 사본이 원본 QA 사본과 다릅니다")
        runtime = {"app": str(runtime_app), "fixture": str(runtime_fixture),
                   "appSHA256": tree_digest(runtime_app),
                   "fixtureSHA256": tree_digest(runtime_fixture)}
    package = {
        "schema": "circlr-port-focus-qa-v1", "version": "0.80.0", "build": str(args.build),
        "app": str(qa_app), "fixture": str(fixture), "bundleID": qa_info["CFBundleIdentifier"],
        "sourceAppSHA256": source_app_hash, "sourceDemoSHA256": source_demo_hash,
        "qaAppSHA256": tree_digest(qa_app), "qaFixtureSHA256": tree_digest(fixture),
        "sourceManifestSHA256": hashlib.sha256(source_manifest).hexdigest(),
        "fixtureManifestSHA256": digest(fixture / "manifest.json"),
        "sectionID": section["id"], "outlierNodeID": outlier,
        "outlierBefore": before, "outlierAfter": after,
        "fixtureChanges": ["project identity", "one section graph layout position"],
        "signature": "ad-hoc; strict deep verification passed", "appLaunched": False,
        "runtimeCopy": runtime,
    }
    with (destination / "package.json").open("x") as output:
        json.dump(package, output, ensure_ascii=False, indent=2)
        output.write("\n")
    print(json.dumps(package, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
