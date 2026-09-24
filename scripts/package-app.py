#!/usr/bin/env python3
"""Stage and verify a local app, then preserve the previous bundle before swapping."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid
import sys


def validate_demo(root):
    """Require a fully inventoried, portable demo with explicit provenance."""
    root = root.resolve()
    manifest = json.loads((root / 'manifest.json').read_text())
    if manifest.get('project') != 'f0r-h3r.circlr' or not manifest.get('provenance') or not manifest.get('notices'):
        raise ValueError('Demo requires project, provenance and rights notices')
    files = manifest.get('files', {})
    actual = set()
    for path in root.rglob('*'):
        if path.is_symlink():
            raise ValueError('Bundled demo must not contain symlinks')
        if path.is_file() and path != root / 'manifest.json':
            actual.add(path.relative_to(root).as_posix())
    if not files or set(files) != actual:
        raise ValueError('Demo inventory differs from bundled files')
    for name, checksum in files.items():
        path = root / name
        if not path.resolve().is_relative_to(root) or hashlib.sha256(path.read_bytes()).hexdigest() != checksum:
            raise ValueError('Demo checksum mismatch: ' + name)
    for notice in manifest['notices']:
        if not isinstance(notice, str) or notice not in files:
            raise ValueError('Demo rights notice is missing from inventory')
    catalog = json.loads((root / 'catalog.json').read_text())
    if not isinstance(catalog, list) or not catalog:
        raise ValueError('Demo catalog is empty')
    ids = set()
    for entry in catalog:
        identifier, relative = entry.get('id'), entry.get('project')
        if not isinstance(identifier, str) or not identifier or identifier in ids:
            raise ValueError('Demo catalog identity is invalid')
        ids.add(identifier)
        if not isinstance(relative, str) or not relative.endswith('.circlr'):
            raise ValueError('Demo catalog project path is invalid')
        project_root = root / relative
        if Path(relative).is_absolute() or not project_root.resolve().is_relative_to(root):
            raise ValueError('Demo catalog project must be inside resources')
        project = json.loads((project_root / 'manifest.json').read_text())
        for asset in project.get('assets', []):
            relative = Path(asset['path'])
            path = project_root / relative
            if relative.is_absolute() or not path.resolve().is_relative_to(project_root) or not path.is_file():
                raise ValueError('Missing or external demo asset: ' + str(relative))
            if asset.get('checksum') and hashlib.sha256(path.read_bytes()).hexdigest() != asset['checksum']:
                raise ValueError('Demo asset checksum mismatch: ' + str(relative))
    return manifest


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument('binary', type=Path)
    args = parser.parse_args()
    demo_source = root / 'Resources/Demos'
    demo_manifest = validate_demo(demo_source)
    audition_worker = args.binary.with_name("circlr-audition-worker")
    if not audition_worker.is_file():
        raise ValueError("Build circlr-audition-worker beside the app binary before packaging")
    output_worker = args.binary.with_name("circlr-output-worker")
    if not output_worker.is_file():
        raise ValueError("Build circlr-output-worker beside the app binary before packaging")
    au_effect_worker = args.binary.with_name("circlr-au-effect-worker")
    if not au_effect_worker.is_file():
        raise ValueError("Build circlr-au-effect-worker beside the app binary before packaging")
    au_instrument_worker = args.binary.with_name("circlr-au-instrument-worker")
    if not au_instrument_worker.is_file():
        raise ValueError("Build circlr-au-instrument-worker beside the app binary before packaging")
    output_device_catalog = args.binary.with_name("circlr-output-device-catalog")
    if not output_device_catalog.is_file():
        raise ValueError("Build circlr-output-device-catalog beside the app binary before packaging")
    trusted_mcp_helper = args.binary.with_name("circlr-trusted-mcp-helper")
    if not trusted_mcp_helper.is_file():
        raise ValueError("Build circlr-trusted-mcp-helper beside the app binary before packaging")
    subprocess.run([sys.executable, str(root / 'scripts/build-agent-kit.py')], check=True)
    bundle_info = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
    icon_name = bundle_info['CFBundleIconFile']
    if not isinstance(icon_name, str) or Path(icon_name).name != icon_name:
        raise ValueError('CFBundleIconFile must name a bundled icon')
    icon_name = icon_name if icon_name.endswith('.icns') else icon_name + '.icns'
    icon_source = root / 'Resources' / icon_name
    if not icon_source.is_file() or icon_source.stat().st_size < 8:
        raise ValueError('Run scripts/build-icon.py before packaging')
    catalog_source = root / 'Resources/Assets.car'
    if bundle_info.get('CFBundleIconName') != 'Circlr' or not catalog_source.is_file():
        raise ValueError('Run scripts/build-icon.py to compile the Circlr icon catalog')
    dist = root / 'dist'
    dist.mkdir(exist_ok=True)
    app = dist / '써클러.app'
    stage = Path(tempfile.mkdtemp(prefix='.circlr-stage-', suffix='.app', dir=dist))
    archive = None
    try:
        (stage / 'Contents/MacOS').mkdir(parents=True)
        (stage / 'Contents/Resources').mkdir()
        shutil.copy2(args.binary, stage / 'Contents/MacOS/circlr')
        shutil.copy2(audition_worker, stage / 'Contents/MacOS/circlr-audition-worker')
        shutil.copy2(output_worker, stage / 'Contents/MacOS/circlr-output-worker')
        shutil.copy2(au_effect_worker, stage / 'Contents/MacOS/circlr-au-effect-worker')
        shutil.copy2(au_instrument_worker, stage / 'Contents/MacOS/circlr-au-instrument-worker')
        shutil.copy2(output_device_catalog, stage / 'Contents/MacOS/circlr-output-device-catalog')
        shutil.copy2(trusted_mcp_helper, stage / 'Contents/MacOS/circlr-trusted-mcp-helper')
        shutil.copy2(root / 'Resources/Info.plist', stage / 'Contents/Info.plist')
        shutil.copy2(icon_source, stage / 'Contents/Resources' / icon_name)
        shutil.copy2(catalog_source, stage / 'Contents/Resources/Assets.car')
        for notice in ('LICENSE', 'THIRD_PARTY_NOTICES.md'):
            shutil.copy2(root / notice, stage / 'Contents/Resources' / notice)
        demo_target = stage / 'Contents/Resources/Demos'
        shutil.copytree(demo_source, demo_target)
        if validate_demo(demo_target) != demo_manifest:
            raise ValueError('Bundled demo manifest differs from source')
        kit_source = root / 'Resources/Codex'
        kit_target = stage / 'Contents/Resources/Codex'
        shutil.copytree(kit_source, kit_target, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        manifest = json.loads((kit_target / 'manifest.json').read_text())
        if manifest['version'] != bundle_info['CFBundleShortVersionString']:
            raise ValueError('Agent kit version differs from app')
        for name, sha in manifest['files'].items():
            if hashlib.sha256((kit_target / name).read_bytes()).hexdigest() != sha:
                raise ValueError('Bundled agent kit differs from source: ' + name)
        if (stage / 'Contents/Resources' / icon_name).read_bytes() != icon_source.read_bytes():
            raise ValueError('Bundled icon differs from source')
        if (stage / 'Contents/Resources/Assets.car').read_bytes() != catalog_source.read_bytes():
            raise ValueError('Bundled icon catalog differs from source')
        subprocess.run(['codesign', '--force', '--sign', '-', str(stage / 'Contents/MacOS/circlr-audition-worker')], check=True)
        subprocess.run(['codesign', '--verify', '--strict', str(stage / 'Contents/MacOS/circlr-audition-worker')], check=True)
        subprocess.run(['codesign', '--force', '--sign', '-', str(stage / 'Contents/MacOS/circlr-output-worker')], check=True)
        subprocess.run(['codesign', '--force', '--sign', '-', str(stage / 'Contents/MacOS/circlr-au-effect-worker')], check=True)
        subprocess.run(['codesign', '--force', '--sign', '-', str(stage / 'Contents/MacOS/circlr-au-instrument-worker')], check=True)
        subprocess.run(['codesign', '--force', '--sign', '-', str(stage / 'Contents/MacOS/circlr-output-device-catalog')], check=True)
        subprocess.run(['codesign', '--force', '--sign', '-', str(stage / 'Contents/MacOS/circlr-trusted-mcp-helper')], check=True)
        subprocess.run(['codesign', '--verify', '--strict', str(stage / 'Contents/MacOS/circlr-au-effect-worker')], check=True)
        subprocess.run(['codesign', '--verify', '--strict', str(stage / 'Contents/MacOS/circlr-au-instrument-worker')], check=True)
        subprocess.run(['codesign', '--verify', '--strict', str(stage / 'Contents/MacOS/circlr-output-device-catalog')], check=True)
        subprocess.run(['codesign', '--verify', '--strict', str(stage / 'Contents/MacOS/circlr-trusted-mcp-helper')], check=True)
        subprocess.run(['codesign', '--force', '--sign', '-', str(stage)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(stage)], check=True)
        if app.exists():
            info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
            version = str(info['CFBundleShortVersionString'])
            assert version and all(c.isascii() and (c.isalnum() or c in '.-') for c in version)
            archives = dist / 'archive'
            archives.mkdir(exist_ok=True)
            archive = archives / ('써클러-' + version + '.app')
            if archive.exists():
                archive = archives / ('써클러-' + version + '-' + str(uuid.uuid4())[:8] + '.app')
            app.rename(archive)
        try:
            stage.rename(app)
        except Exception:
            if archive is not None and not app.exists():
                archive.rename(app)
            raise
        print(app)
        if archive is not None:
            print('보관:', archive)
    finally:
        if stage.exists():
            shutil.rmtree(stage)


if __name__ == '__main__':
    main()
