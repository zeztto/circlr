#!/usr/bin/env python3
"""Prepare isolated 0.50.0/build166 native QA inputs; never launch or stop an app.

Run from any directory. Existing evidence causes an immediate failure. If preparation
fails, the partial directory remains for inspection and is never silently replaced.
"""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
SOURCE_APP = ROOT / 'dist/써클러.app'
OUT = ROOT / 'qa/generated/outward-orbit/build166'
APP = OUT / '써클러 통합 검증.app'
SOURCE_FIXTURE = SOURCE_APP / 'Contents/Resources/Demos/f0r-h3r.circlr'
FIXTURE = OUT / 'fixtures/f0r-h3r-outward-orbit-build166.circlr'
VERSION, BUILD = '0.50.0', '166'
BUNDLE_ID = 'com.circlr.integrationqa'


def run(*command):
    subprocess.run(command, check=True)


def file_hash(path):
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def tree_hash(root):
    """Hash sorted relative paths and file bytes (symlinks by link text)."""
    digest = hashlib.sha256()
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            entry = ['symlink', relative, str(path.readlink())]
        elif path.is_file():
            entry = ['file', relative, file_hash(path)]
        else:
            continue
        digest.update((json.dumps(entry, ensure_ascii=False) + '\n').encode())
    return digest.hexdigest()


def main():
    if OUT.exists() or OUT.is_symlink():
        raise SystemExit(f'기존 QA 증거를 보존합니다: {OUT}')
    source_info = plistlib.loads((SOURCE_APP / 'Contents/Info.plist').read_bytes())
    if (source_info.get('CFBundleShortVersionString'), source_info.get('CFBundleVersion')) != (VERSION, BUILD):
        raise SystemExit('dist app이 0.50.0/build166이 아닙니다')
    raw_manifest = (SOURCE_FIXTURE / 'manifest.json').read_bytes()
    project = json.loads(raw_manifest)
    original_id = project['id']
    run('codesign', '--verify', '--deep', '--strict', str(SOURCE_APP))
    source_app_hash = tree_hash(SOURCE_APP)
    source_fixture_hash = tree_hash(SOURCE_FIXTURE)
    OUT.mkdir(parents=True, exist_ok=False)
    run('ditto', str(SOURCE_APP), str(APP))
    info_path = APP / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info.update(CFBundleIdentifier=BUNDLE_ID, CFBundleName='써클러 통합 검증',
                CFBundleDisplayName='써클러 통합 검증')
    info.pop('CFBundleDocumentTypes', None)
    info.pop('UTExportedTypeDeclarations', None)
    info.pop('UTImportedTypeDeclarations', None)
    info.pop('CFBundleURLTypes', None)
    info_path.write_bytes(plistlib.dumps(info))
    run('codesign', '--force', '--deep', '--sign', '-', str(APP))
    run('codesign', '--verify', '--deep', '--strict', str(APP))
    FIXTURE.parent.mkdir()
    shutil.copytree(SOURCE_FIXTURE, FIXTURE)
    # A distinct identity prevents the QA copy sharing the source project's session.
    project['id'] = str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr/outward-orbit/build166/f0r-h3r')).upper()
    (FIXTURE / 'manifest.json').write_text(json.dumps(project, ensure_ascii=False, indent=2) + '\n')
    comparison = dict(project, id=original_id)
    if comparison != json.loads(raw_manifest):
        raise RuntimeError('QA copy changed musical content')
    if tree_hash(SOURCE_APP) != source_app_hash or tree_hash(SOURCE_FIXTURE) != source_fixture_hash:
        raise RuntimeError('Source input changed during preparation')
    package = dict(schema='outward-orbit-qa-package-v1', version=VERSION, build=BUILD,
                   bundleID=BUNDLE_ID, app=str(APP), fixture=str(FIXTURE),
                   projectID=project['id'], sourceProjectID=original_id,
                   sourceApp=str(SOURCE_APP), sourceFixture=str(SOURCE_FIXTURE),
                   appSHA256=tree_hash(APP), fixtureSHA256=tree_hash(FIXTURE),
                   sourceAppSHA256=source_app_hash, sourceFixtureSHA256=source_fixture_hash,
                   fixtureManifestSHA256=file_hash(FIXTURE / 'manifest.json'),
                   sourceManifestSHA256=hashlib.sha256(raw_manifest).hexdigest(),
                   executableSHA256=file_hash(APP / 'Contents/MacOS' / info['CFBundleExecutable']),
                   hashAlgorithm='sha256 sorted JSON [kind, relative path, content hash or symlink target] lines',
                   signature='ad-hoc; codesign --verify --deep --strict passed',
                   fixtureChanges=['project id only'], appLaunched=False, appStopped=False)
    with (OUT / 'package.json').open('x') as handle:
        json.dump(package, handle, ensure_ascii=False, indent=2)
        handle.write('\n')
    print(json.dumps(package, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
