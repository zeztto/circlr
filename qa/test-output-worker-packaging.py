#!/usr/bin/env python3
"""Exercise production packaging in a temporary project, preserving the user's dist app."""
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections']

def main():
 with tempfile.TemporaryDirectory(prefix='circlr-package-qa-') as temp:
  root=Path(temp);(root/'scripts').mkdir();(root/'mcp').mkdir();(root/'Resources').mkdir()
  for name in ['package-app.py','build-agent-kit.py']:shutil.copy2(ROOT/'scripts'/name,root/'scripts'/name)
  shutil.copy2(ROOT/'mcp/server.py',root/'mcp/server.py')
  for name in ['Info.plist','AppIcon.icns','Assets.car']:shutil.copy2(ROOT/'Resources'/name,root/'Resources'/name)
  shutil.copytree(ROOT/'Resources/Codex',root/'Resources/Codex',ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
  binary=ROOT/'.build/integration-release/release/circlr'
  args=[sys.executable,str(root/'scripts/package-app.py'),str(binary)]
  subprocess.run(args,check=True,capture_output=True,text=True,timeout=30)
  app=root/'dist/써클러.app'
  for name in ['circlr','circlr-output-worker']:
   assert sections(binary.with_name(name))==sections(app/'Contents/MacOS'/name)
  subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True,capture_output=True)
  subprocess.run(args,check=True,capture_output=True,text=True,timeout=30)
  assert len(list((root/'dist/archive').glob('*.app')))==1
  before=hashlib.sha256((app/'Contents/MacOS/circlr').read_bytes()).hexdigest()
  missing=root/'missing/circlr';missing.parent.mkdir();missing.write_bytes(b'not executed')
  failed=subprocess.run([sys.executable,str(root/'scripts/package-app.py'),str(missing)],capture_output=True,text=True,timeout=10)
  assert failed.returncode!=0 and 'Build circlr-output-worker' in failed.stderr
  assert hashlib.sha256((app/'Contents/MacOS/circlr').read_bytes()).hexdigest()==before
  assert not list((root/'dist').glob('.circlr-stage-*'))
  print(json.dumps(dict(packaging='passed',executables=2,archivePreserved=True,missingHelperRejected=True)))
if __name__=='__main__':main()
