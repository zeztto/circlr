#!/usr/bin/env python3
"""Create build86 baseline once; package build87 candidates without resetting music.

  python3 qa/prepare-render-tail-qa.py --baseline
  python3 qa/prepare-render-tail-qa.py --candidate final

The common packager copies authored assets and creates its usual shared second use.
Delay and bounce tail cases are prepared separately through the app, never here.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import sys

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
NAME = 'render-tail'
OUT = p.ROOT / 'qa/generated' / NAME


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--baseline', action='store_true', help='First creation only, from build86 release')
    mode.add_argument('--candidate', help='New build87 package folder; preserve the existing fixture')
    args = parser.parse_args()
    if args.candidate:
        assert re.fullmatch('[a-z0-9-]{1,32}', args.candidate)
        assert args.candidate != 'baseline', 'baseline is reserved for the original build86 package'
        assert (OUT / 'baseline/package.json').is_file(), 'Create --baseline first'
    p.NAME = NAME
    p.BUILD = '86' if args.baseline else '87'
    p.FIXTURE = p.SOURCE.with_name(NAME + '.circlr')
    # Baseline must enter the common FIRST-CREATION path, not its candidate path.
    p.OUT = OUT / 'baseline' if args.baseline else OUT
    p.APP = p.OUT / '써클러 통합 검증.app'
    original_argv = sys.argv
    try:
        sys.argv = [original_argv[0]] + ([] if args.baseline else ['--candidate', args.candidate])
        p.main()
    finally:
        sys.argv = original_argv
    if args.baseline:
        with (p.OUT / 'fixture-initial.json').open('x') as file:
            json.dump(json.loads((p.FIXTURE / 'manifest.json').read_text()), file, ensure_ascii=False, indent=2)


if __name__ == '__main__':
    main()
