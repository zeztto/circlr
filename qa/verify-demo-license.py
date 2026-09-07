#!/usr/bin/env python3
"""Audit the actual v3 delivery: every embedded file must belong to the pinned CC0 set."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if not __debug__:
    raise RuntimeError('Run this audit without Python optimization; assertions are required')


def checksum(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(project, license_folder):
    metadata = license_folder / 'manifest.json'
    assert checksum(metadata) == '11275cbfd9d933bb293dc266faf373ea65efa918ca2f6136c2f69ce88e5b804b'
    bank = json.loads(metadata.read_text()); assert bank['license'] == 'CC0-1.0'
    assert checksum(license_folder / 'LICENSE') == 'a2010f343487d3f7618affe54f789f5487602331c0a8d03f49e9a7c547cf0499'
    allowed = {item['sha256'] for item in bank['files']}
    p = json.loads((project / 'manifest.json').read_text()); assert len(p['assets']) == 6
    files = []
    for asset in p['assets']:
        relative = Path(asset['path']); assert not relative.is_absolute() and '..' not in relative.parts
        path = project / relative; assert not path.is_symlink() and path.resolve().is_relative_to(project.resolve())
        digest = checksum(path); assert digest == asset['checksum'] and digest in allowed
        files.append(relative.as_posix())
    actual = {path.relative_to(project).as_posix() for path in project.rglob('*') if path.is_file()}
    assert actual == set(files) | {'manifest.json'}, 'Unlisted media/archives in project'
    text = (project / 'manifest.json').read_text()
    assert 'NW_DG_' not in text and 'Digi Grid' not in text and '/Splice' not in text
    result = {'project': project.name, 'assets': len(files), 'sampleLicense': bank['license'],
              'allEmbeddedFilesAllowlisted': True, 'externalAssetPaths': 0, 'unlistedFiles': 0}
    old_file = ROOT / 'music/f0r-h3r/v2/f0r h3r.circlr/manifest.json'
    if old_file.exists():
        old = json.loads(old_file.read_text())
        assert not {a['checksum'] for a in old['assets']} & {a['checksum'] for a in p['assets']}
        def notes(item):
            return [[[(n['beat'], n['length'], n['pitch'], n['velocity']) for n in lane['notes']] for lane in section['lanes']] for section in item['sections']]
        assert notes(p) == notes(old)
        assert p['global'] == old['global']
        assert [s['bars'] for s in p['sections']] == [s['bars'] for s in old['sections']]
        result.update({'v2SpliceAssetsRemaining': 0, 'v2NotesAndFormPreserved': True})
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path)
    parser.add_argument('--licenses', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = verify(args.project, args.licenses or args.project.parent / 'sample-license')
    text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output: args.output.write_text(text)
    print(text, end='')
