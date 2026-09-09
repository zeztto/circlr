#!/usr/bin/env python3
"""Package isolated circle-color QA with authored source assets."""
import importlib.util
from pathlib import Path
spec=importlib.util.spec_from_file_location('packager',Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
p.NAME='circle-color';p.BUILD='81';p.OUT=p.ROOT/'qa/generated/circle-color/native'
p.APP=p.OUT/'써클러 통합 검증.app';p.FIXTURE=p.SOURCE.with_name('circle-color.circlr')
if __name__=='__main__': p.main()
