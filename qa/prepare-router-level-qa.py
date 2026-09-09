#!/usr/bin/env python3
"""Create build91 baseline once; package build92 candidates without resetting music.

  python3 qa/prepare-router-level-qa.py --baseline
  python3 qa/prepare-router-level-qa.py --candidate final

The common packager copies the two authored assets, then the baseline imports the
preserved signal-level reopened document under a new project identity.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import sys

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
NAME = 'router-level'
OUT = p.ROOT / 'qa/generated' / NAME


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--baseline', action='store_true', help='First creation only, from build91 release')
    mode.add_argument('--candidate', help='New build92 package folder; preserve the existing fixture')
    args = parser.parse_args()
    if args.candidate:
        assert re.fullmatch('[a-z0-9-]{1,32}', args.candidate)
        assert args.candidate != 'baseline', 'baseline is reserved for the original build91 package'
        assert (OUT / 'baseline/package.json').is_file(), 'Create --baseline first'
    p.NAME = NAME
    p.BUILD = '91' if args.baseline else '92'
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
        target = p.FIXTURE / 'manifest.json'
        fresh = json.loads(target.read_text())
        evidence_path = p.ROOT / 'qa/generated/signal-level/final-scroll/reopened.json'
        evidence = json.loads(evidence_path.read_text())
        assert evidence['state']['revision'] == evidence['manifest']['musicRevision'] == 28
        assert evidence['state']['projectID'] == 'FB8E3942-1B47-58A1-B81D-BDC9C88F7964'
        project = copy.deepcopy(evidence['manifest'])
        assert project['assets'] == fresh['assets'] and project['sections'] == fresh['sections']
        project['id'] = fresh['id']
        use = project['arrangements'][0]['uses'][0]
        section = next(s for s in project['sections'] if s['id'] == use['sectionID'])
        router_id = 'FC5544DC-54E1-5CBB-80C3-514C5087D9C1'
        assert router_id not in use['graphEdits']['nodeOverrides']
        router = copy.deepcopy(next(n for n in section['graph']['nodes'] if n['id'] == router_id))
        route = next(r for r in router['content']['router']['_0']['routes']
                     if r['input'] == 'in.audio.bus1' and r['output'] == 'out.audio.bus1')
        assert route['gain'] == 1
        route['gain'] = math.pow(10, -6 / 20)
        use['graphEdits']['nodeOverrides'][router_id] = router
        target.write_text(json.dumps(project, ensure_ascii=False, indent=2) + '\n')
        with (p.OUT / 'fixture-initial.json').open('x') as file:
            json.dump(project, file, ensure_ascii=False, indent=2)
        with (p.OUT / 'fixture-origin.json').open('x') as file:
            json.dump({'sourceEvidence': str(evidence_path),
                       'sourceEvidenceSHA256': hashlib.sha256(evidence_path.read_bytes()).hexdigest(),
                       'sourceProjectID': evidence['state']['projectID'],
                       'newProjectID': project['id'], 'sourceRevision': 28}, file, indent=2)


if __name__ == '__main__':
    main()
