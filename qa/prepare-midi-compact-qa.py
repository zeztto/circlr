#!/usr/bin/env python3
"""Create build99 baseline once; package build100 candidates without resetting music.

  python3 qa/prepare-midi-compact-qa.py --baseline
  python3 qa/prepare-midi-compact-qa.py --candidate final

The common packager copies the two authored assets, then the baseline imports the
preserved workflow-visibility reopened document under a new project identity.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
NAME = 'midi-compact'
OUT = p.ROOT / 'qa/generated' / NAME


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--baseline', action='store_true', help='First creation only, from build99 release')
    mode.add_argument('--candidate', help='New build100 package folder; preserve the existing fixture')
    args = parser.parse_args()
    if args.candidate:
        assert re.fullmatch('[a-z0-9-]{1,32}', args.candidate)
        assert args.candidate != 'baseline', 'baseline is reserved for the original build99 package'
        assert (OUT / 'baseline/package.json').is_file(), 'Create --baseline first'
    p.NAME = NAME
    p.BUILD = '99' if args.baseline else '100'
    p.FIXTURE = p.SOURCE.with_name(NAME + '.circlr')
    # Baseline must enter the common FIRST-CREATION path, not its candidate path.
    p.OUT = OUT / 'baseline' if args.baseline else OUT
    p.APP = p.OUT / '써클러 통합 검증.app'
    fixture_before = (p.FIXTURE / 'manifest.json').read_bytes() if args.candidate else None
    original_argv = sys.argv
    try:
        sys.argv = [original_argv[0]] + ([] if args.baseline else ['--candidate', args.candidate])
        p.main()
    finally:
        sys.argv = original_argv
    if args.candidate:
        assert (p.FIXTURE / 'manifest.json').read_bytes() == fixture_before
    if args.baseline:
        target = p.FIXTURE / 'manifest.json'
        fresh = json.loads(target.read_text())
        evidence_path = p.ROOT / 'qa/generated/workflow-visibility/final/reopened.json'
        evidence = json.loads(evidence_path.read_text())
        assert evidence['state']['revision'] == evidence['manifest']['musicRevision'] == 30
        assert evidence['state']['projectID'] == '68B5D3D0-07E9-5631-A611-ED78245A4C89'
        project = copy.deepcopy(evidence['manifest'])
        assert project['assets'] == fresh['assets'] and project['sections'] == fresh['sections']
        project['id'] = fresh['id']
        project['circleLayout'] = 'orbit'
        assert len(project['arrangements'][0]['uses'][0]['addedLanes'][0]['notes']) == 3
        for asset in project['assets']:
            assert hashlib.sha256((p.FIXTURE / asset['path']).read_bytes()).hexdigest() == asset['checksum']
        target.write_text(json.dumps(project, ensure_ascii=False, indent=2) + '\n')
        with (p.OUT / 'fixture-initial.json').open('x') as file:
            json.dump(project, file, ensure_ascii=False, indent=2)
        with (p.OUT / 'fixture-origin.json').open('x') as file:
            json.dump({'sourceEvidence': str(evidence_path),
                       'sourceEvidenceSHA256': hashlib.sha256(evidence_path.read_bytes()).hexdigest(),
                       'sourceProjectID': evidence['state']['projectID'],
                       'newProjectID': project['id'], 'sourceRevision': 30}, file, indent=2)


if __name__ == '__main__':
    main()
