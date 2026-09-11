#!/usr/bin/env python3
"""Package build101 and copy the preserved compact MIDI document to a new identity."""
import argparse
import sys
import re
import importlib.util
import json
import hashlib
from pathlib import Path

spec=importlib.util.spec_from_file_location('packager',Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate")
    args=parser.parse_args()
    if args.candidate:
        assert re.fullmatch("[a-z0-9-]{1,32}",args.candidate) and args.candidate!="final"
    source=p.SOURCE.with_name('midi-compact.circlr')
    raw=(source/'manifest.json').read_bytes()
    document=json.loads(raw)
    assert document['id']=='E1B36942-8E7D-5ADB-91A7-5B0A6DC26B9B' and document['musicRevision']==36
    p.NAME='header-compact';p.BUILD='101'
    p.OUT=p.ROOT/'qa/generated/header-compact/final'
    p.APP=p.OUT/'써클러 통합 검증.app'
    p.FIXTURE=p.SOURCE.with_name('header-compact.circlr')
    if args.candidate:
        p.OUT=p.OUT.parent
        before=(p.FIXTURE/'manifest.json').read_bytes()
        p.main()
        assert (p.FIXTURE/'manifest.json').read_bytes()==before
        return
    assert not p.OUT.exists() and not p.FIXTURE.exists()
    p.main()
    fresh=json.loads((p.FIXTURE/'manifest.json').read_text())
    assert document['assets']==fresh['assets']
    for asset in document['assets']:
        assert hashlib.sha256((p.FIXTURE/asset['path']).read_bytes()).hexdigest()==asset['checksum']
    document['id']=fresh['id']
    (p.FIXTURE/'manifest.json').write_text(json.dumps(document,ensure_ascii=False,indent=2)+'\n')
    (p.OUT/'fixture-initial.json').write_text(json.dumps(document,ensure_ascii=False,indent=2)+'\n')
    (p.OUT/'fixture-origin.json').write_text(json.dumps({'path':str(source),'sha256':hashlib.sha256(raw).hexdigest()},indent=2)+'\n')
    assert (source/'manifest.json').read_bytes()==raw

if __name__=='__main__':main()
