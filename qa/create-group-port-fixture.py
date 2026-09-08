#!/usr/bin/env python3
"""Copy authored, isolated QA tones into a separate group-port fixture; never overwrite."""
import json
from pathlib import Path
import shutil
import uuid

BASE = Path.home() / 'Library/Application Support/circlr-ports-qa/fixtures'
SOURCE = BASE / 'ports-playback.circlr'
TARGET = BASE / 'ports-group.circlr'


def identity(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-group-ports-d2/' + name)).upper()


def main():
    assert SOURCE.is_dir() and not TARGET.exists(), 'Preserve existing QA fixtures'
    project = json.loads((SOURCE / 'manifest.json').read_text())
    assert project['id'] == 'A727DC35-BB4D-5C79-AEB1-004A2F0CC2B0'
    use = project['arrangements'][0]['uses'][0]
    assert 'graphEdits' not in use and 'graphLayout' not in use
    graph = project['sections'][0]['graph']
    router = next(n for n in graph['nodes'] if 'router' in n['content'])
    source = next(n for n in graph['nodes'] if 'audio' in n['content'])
    group = {'id': identity('group'), 'name': '신스 그룹', 'members': [router['id'], source['id']], 'collapsed': True}
    graph['layout']['groups'] = [group]
    project.update(id=identity('project'), name='그룹 포트 검증', musicRevision=1)
    project.pop('portLayout', None); project.pop('hierarchyView', None)
    shutil.copytree(SOURCE, TARGET)
    (TARGET / 'manifest.json').write_text(json.dumps(project, ensure_ascii=False, indent=2) + '\n')
    address = {'group': {'parent': {'section': {'arrangementID': project['activeArrangementID'], 'useID': use['id']}}, 'id': group['id']}}
    print(json.dumps({'path': str(TARGET), 'projectID': project['id'], 'group': address, 'router': router['id']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
