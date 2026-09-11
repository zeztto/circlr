#!/usr/bin/env python3
"""Package isolated output-session QA with authored source assets."""
import importlib.util
from pathlib import Path
spec=importlib.util.spec_from_file_location('packager',Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
p.NAME='output-session';p.BUILD='82';p.OUT=p.ROOT/'qa/generated/output-session'
p.APP=p.OUT/'써클러 통합 검증.app';p.FIXTURE=p.SOURCE.with_name('output-session.circlr')
if __name__=='__main__': p.main()
