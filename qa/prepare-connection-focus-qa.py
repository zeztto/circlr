#!/usr/bin/env python3
"""Package build104 against the preserved connection-focus QA document."""
import importlib.util
from pathlib import Path
spec=importlib.util.spec_from_file_location('packager',Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
p.NAME='connection-focus';p.BUILD='104';p.OUT=p.ROOT/'qa/generated/connection-focus'
p.APP=p.OUT/'써클러 통합 검증.app';p.FIXTURE=p.SOURCE.with_name('connection-focus.circlr')
if __name__=='__main__':
    assert (p.OUT/'baseline/compact.json').is_file()
    before=(p.FIXTURE/'manifest.json').read_bytes()
    import argparse
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--candidate',required=True)
    args=parser.parse_args();assert args.candidate!='baseline', 'Preserve baseline evidence'
    p.main()
    assert (p.FIXTURE/'manifest.json').read_bytes()==before
