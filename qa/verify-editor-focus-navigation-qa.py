#!/usr/bin/env python3
"""Read-only music/address invariants for editor focus QA; workspace changes are allowed."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('focus_capture_guard', Path(__file__).with_name('verify-section-settings-return-qa.py'))
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)
require = guard.require


def changed_paths(a, b, prefix='hierarchyView'):
    if isinstance(a, dict) and isinstance(b, dict):
        result = []
        for key in sorted(set(a) | set(b)):
            path = prefix + '.' + key
            if key not in a or key not in b:
                result.append(path)
            else:
                result.extend(changed_paths(a[key], b[key], path))
        return result
    return [] if a == b else [prefix]


def audit(before_path, after_path, before_ax, after_ax, build, revision):
    require(before_path.resolve() != after_path.resolve(), 'Distinct saved captures required')
    before, after = [guard.read_capture(path, build) for path in (before_path, after_path)]
    a, b = before['state'], after['state']
    require(a['revision'] == b['revision'] == revision, 'Unexpected music revision')
    for key in ('layoutRevision', 'activeArrangementID', 'selection', 'selectedNoteIDs'):
        require(a[key] == b[key], 'Runtime invariant changed: ' + key)
    ma, mb = before['manifest'], after['manifest']
    require({k: v for k, v in ma.items() if k != 'hierarchyView'} ==
            {k: v for k, v in mb.items() if k != 'hierarchyView'}, 'Music/data/assets changed')
    require(ma['hierarchyView']['selection'] == mb['hierarchyView']['selection'], 'Saved address changed')
    require(len({asset['id'] for asset in ma['assets']}) == len(ma['assets']), 'Duplicate asset IDs')
    for asset in ma['assets']:
        path = Path(asset['path'])
        require(not path.is_absolute() and '..' not in path.parts, 'Unsafe asset path')
        require(hashlib.sha256((guard.FIXTURE / path).read_bytes()).hexdigest() == asset['checksum'], 'Asset checksum mismatch')
    ax_evidence = []
    for path in (before_ax, after_ax):
        raw = path.read_bytes()
        require(bool(raw.decode('utf-8').strip()), 'Empty AX text')
        ax_evidence.append(dict(path=str(path.resolve()), sha256=hashlib.sha256(raw).hexdigest(), bytes=len(raw)))
    return dict(status='PASS_MUSIC_ADDRESS_ONLY', build=build, revision=revision,
        projectID=guard.PROJECT_ID, address=a['selection'], assetCount=len(ma['assets']),
        workspaceChanges=changed_paths(ma['hierarchyView'], mb['hierarchyView']),
        captures=[dict(path=str(path.resolve()), sha256=hashlib.sha256(path.read_bytes()).hexdigest())
                  for path in (before_path, after_path)], axEvidence=ax_evidence,
        scope='Exact music/revision/layout/address/note selection/data/assets with saved-capture identity and unused no-I/O guards. Workspace/cursor/camera differences allowed and reported. AX text is loaded and hashed only: native focus, key delivery, StepValue changes and visual correctness require independent AX/UI review. No app/RPC or file writes.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path); parser.add_argument('after', type=Path)
    parser.add_argument('--before-ax', type=Path, required=True)
    parser.add_argument('--after-ax', type=Path, required=True)
    parser.add_argument('--build', type=int, default=140)
    parser.add_argument('--expected-revision', type=int, default=166)
    args = parser.parse_args()
    print(json.dumps(audit(args.before, args.after, args.before_ax, args.after_ax,
                           args.build, args.expected_revision), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
