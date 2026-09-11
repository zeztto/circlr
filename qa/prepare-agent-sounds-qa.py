#!/usr/bin/env python3
"""Create the build 62 QA app and authored-only fixture; preserve existing candidates."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

spec=importlib.util.spec_from_file_location('packager',Path(__file__).with_name('prepare-automation-workspace-qa.py'))
packager=importlib.util.module_from_spec(spec);spec.loader.exec_module(packager)
packager.NAME='agent-sounds';packager.BUILD='62'
packager.OUT=packager.ROOT/'qa/generated/agent-sounds';packager.APP=packager.OUT/'써클러 통합 검증.app'
packager.FIXTURE=packager.SOURCE.with_name('agent-sounds.circlr')

if __name__=='__main__':
    packager.main()
    if '--candidate' not in sys.argv:
        path=packager.FIXTURE/'manifest.json';project=json.loads(path.read_text())
        project['tracks'][2]['instrument']['synth']['cutoff']=731
        path.write_text(json.dumps(project,ensure_ascii=False,indent=2)+'\n')
        (packager.OUT/'fixture-initial.json').write_bytes(path.read_bytes())
    sources=['Resources/Info.plist','Sources/CirclrCore/AgentProtocol.swift','Sources/CirclrCore/AgentSoundCatalog.swift','Sources/CirclrApp/AgentWorkspace.swift','Sources/CirclrApp/AppStore.swift','mcp/server.py','Resources/Codex/skills/circlr-studio/SKILL.md','Resources/Codex/skills/circlr-studio/references/circlr-operations.md','Resources/Codex/skills/circlr-studio/scripts/mcp_server.py','Resources/Codex/manifest.json']
    (packager.OUT/'source-hashes.json').write_text(json.dumps({name:hashlib.sha256((packager.ROOT/name).read_bytes()).hexdigest() for name in sources},indent=2)+'\n')
