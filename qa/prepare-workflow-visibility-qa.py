#!/usr/bin/env python3
"""Package only build97 candidates; the root-created baseline96 and fixture are immutable inputs."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import sys

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
NAME = 'workflow-visibility'
OUT = p.ROOT / 'qa/generated' / NAME


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', required=True)
    args = parser.parse_args()
    assert re.fullmatch('[a-z0-9-]{1,32}', args.candidate) and args.candidate != 'baseline'
    baseline = json.loads((OUT / 'baseline/package.json').read_text())
    assert baseline['build'] == '96' and baseline['projectID'] == '68B5D3D0-07E9-5631-A611-ED78245A4C89'
    p.NAME = NAME; p.BUILD = '97'; p.OUT = OUT
    p.FIXTURE = Path(baseline['fixture'])
    assert p.FIXTURE == p.SOURCE.with_name(NAME + '.circlr')
    before = (p.FIXTURE / 'manifest.json').read_bytes()
    assert json.loads(before)['id'] == baseline['projectID']
    argv = sys.argv
    try:
        sys.argv = [argv[0], '--candidate', args.candidate]
        p.main()
    finally:
        sys.argv = argv
    assert (p.FIXTURE / 'manifest.json').read_bytes() == before


if __name__ == '__main__':
    main()
