#!/usr/bin/env python3
"""Build109 isolated QA package with explicit no-CoreAudio Mach-O catalog fixtures.

--candidate success|delay|failure|missing. Never starts the app or changes preferences.
"""
import argparse
import hashlib
import importlib.util
import json
import re
from pathlib import Path
import shutil
import subprocess
import sys

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p = importlib.util.module_from_spec(spec); spec.loader.exec_module(p)
NAME = 'output-preferences'
OUT = p.ROOT / 'qa/generated' / NAME


def run(args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=60).stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', required=True, help='Exclusive folder, e.g. success2')
    parser.add_argument('--scenario', choices=['success','delay','failure','missing'], help='Defaults to candidate prefix')
    parser.add_argument('--delay-seconds', type=int, default=4, choices=range(1,61), metavar='1..60',
                        help='Delay scenario only; default4s, values over5s also exercise timeout')
    args = parser.parse_args()
    assert re.fullmatch(r'(success|delay|failure|missing)[0-9]*', args.candidate), 'Use a scenario prefix and optional digits'
    scenario = args.scenario or re.match(r'[a-z]+', args.candidate).group()
    directory = OUT / args.candidate
    assert not directory.exists(), 'Preserve existing candidate evidence'
    p.NAME = NAME; p.BUILD = '109'; p.FIXTURE = p.SOURCE.with_name(NAME + '.circlr')
    first = not p.FIXTURE.exists()
    if not first:
        assert any(OUT.glob('*/package.json')), 'Existing fixture needs its owned package evidence'
    before = None if first else (p.FIXTURE / 'manifest.json').read_bytes()
    p.OUT = directory if first else OUT; p.APP = p.OUT / '써클러 통합 검증.app'
    argv = sys.argv
    try:
        sys.argv = [argv[0]] + ([] if first else ['--candidate', args.candidate])
        p.main()
    finally:
        sys.argv = argv
    if before is not None: assert (p.FIXTURE / 'manifest.json').read_bytes() == before
    package = json.loads((directory / 'package.json').read_text())
    app = Path(package['app']); macos = app / 'Contents/MacOS'
    originals = directory / 'production-helpers'; originals.mkdir()
    for name in ['circlr-output-device-catalog','circlr-output-worker']:
        shutil.copy2(macos / name, originals / name)
    devices = [{'uid':'qa-output-a','name':'QA 출력 A'}, {'uid':'qa-output-b','name':'QA 출력 B'}]
    if scenario == 'missing': devices = devices[:1]
    catalog = {'version':1,'devices':devices,'defaultUID':'qa-output-a'}
    payload = json.dumps(catalog, ensure_ascii=False, separators=(',',':'))
    # JSON escaping produces a valid C string for ASCII escapes and UTF-8 data.
    literal = json.dumps(payload, ensure_ascii=False)
    code = '#include <stdio.h>\n#include <string.h>\n#include <unistd.h>\nint main(int argc,char **argv){\n'
    code += 'if(argc!=2 || strcmp(argv[1],"--list"))return 64;\n'
    if scenario == 'delay': code += f'sleep({args.delay_seconds});\n'
    code += 'return 70;\n' if scenario == 'failure' else 'fputs(' + literal + ',stdout);return 0;\n'
    code += '}\n'
    source = directory / 'mock-catalog.c'; source.write_text(code)
    deny = directory / 'deny-output.c'; deny.write_text('int main(void){return 78;}\n')
    for src, name in [(source,'circlr-output-device-catalog'),(deny,'circlr-output-worker')]:
        run(['xcrun','clang','-Os',str(src),'-o',str(macos/name)])
        run(['codesign','--force','--sign','-',str(macos/name)])
        assert 'Mach-O' in run(['file',str(macos/name)])
    run(['codesign','--force','--deep','--sign','-',str(app)])
    run(['codesign','--verify','--deep','--strict',str(app)])
    manifest = {'qaOnlyMock':True,'candidate':args.candidate,'scenario':scenario,
                'preferenceContract':{'suite':'com.circlr.integrationqa','key':'circlr.playback.outputDeviceUID',
                                      'explicitValue':'UID string','systemDefault':'remove key'},
                'uiContract':{'open':'Command-comma or 곡 재생 출력 설정','refresh':'다시 조회','cancel':'조회 취소 or close/Escape','pickerAXID':'output-preferences-device'},'catalog':catalog,
                'delaySeconds':args.delay_seconds if scenario=='delay' else 0,'catalogExit':70 if scenario=='failure' else 0,
                'physicalOutputWorker':'deny stub exits78; production helper preserved outside app',
                'productionHelperSHA256':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in originals.iterdir()},
                'mockHelperSHA256':{n:hashlib.sha256((macos/n).read_bytes()).hexdigest() for n in ['circlr-output-device-catalog','circlr-output-worker']}}
    with (directory/'qa-injection.json').open('x') as file: json.dump(manifest,file,ensure_ascii=False,indent=2)
    with (directory/'fixture-initial.json').open('x') as file: file.write((p.FIXTURE/'manifest.json').read_text())
    print(json.dumps({'package':str(directory/'package.json'),'qaInjection':str(directory/'qa-injection.json')},ensure_ascii=False))


if __name__ == '__main__':
    main()
