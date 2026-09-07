#!/usr/bin/env python3
"""Build the self-contained versioned agent kit from maintained source files."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil


def main():
    root = Path(__file__).resolve().parents[1]
    kit = root / 'Resources/Codex'
    shutil.copyfile(root / 'mcp/server.py', kit / 'skills/circlr-studio/scripts/mcp_server.py')
    version = plistlib.loads((root / 'Resources/Info.plist').read_bytes())['CFBundleShortVersionString']
    files = {}
    for path in sorted(kit.rglob('*')):
        if path.is_symlink():
            raise ValueError('Symlinks are not bundle inputs: ' + str(path))
        if path.is_file() and path.name != 'manifest.json' and '__pycache__' not in path.parts and path.suffix != '.pyc':
            files[str(path.relative_to(kit))] = hashlib.sha256(path.read_bytes()).hexdigest()
    (kit / 'manifest.json').write_text(json.dumps({'schema': 'circlr-agent-kit-v1', 'version': version, 'files': files}, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'version': version, 'files': len(files), 'path': str(kit)}))


if __name__ == '__main__':
    main()
