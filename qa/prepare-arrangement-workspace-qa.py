#!/usr/bin/env python3
"""Package authored-only arrangement management QA with a separate owner."""
import copy, importlib.util, json, sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('packager',Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
p.NAME='arrangement-workspace';p.BUILD='83';p.OUT=p.ROOT/'qa/generated/arrangement-workspace'
p.APP=p.OUT/'써클러 통합 검증.app';p.FIXTURE=p.SOURCE.with_name('arrangement-workspace.circlr')
spec2=importlib.util.spec_from_file_location('alternatives',Path(__file__).with_name('prepare-arrangement-search-qa.py'))
a=importlib.util.module_from_spec(spec2);spec2.loader.exec_module(a)
if __name__=='__main__':
 p.main()
 if '--candidate' not in sys.argv:
  path=p.FIXTURE/'manifest.json';project=json.loads(path.read_text());base=project['arrangements'][0]
  base['name']='메인 편곡';owner=project['album']['compositions'][0]
  project['circleColors']=[{'section':{'arrangementID':base['id'],'useID':base['uses'][0]['id']}},{'red':235,'green':156,'blue':134}]
  otherArrangement=a.alternative(base,901,'다른 곡의 메인 편곡')
  other=copy.deepcopy(owner);other.update(id=a.identifier('workspace-other-owner'),name='다른 곡',arrangementIDs=[otherArrangement['id']],selectedArrangementID=otherArrangement['id'],children=[])
  project['arrangements'].append(otherArrangement);project['album']['compositions'].append(other);project['album']['children'].append(other['id']);project['album']['layout']['positions'][other['id']]={'x':700,'y':0}
  path.write_text(json.dumps(project,ensure_ascii=False,indent=2)+'\n');(p.OUT/'fixture-initial.json').write_bytes(path.read_bytes())
