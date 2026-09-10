#!/usr/bin/env python3
"""Read-only build117 native state checks; PNG layout inspection is a separate gate."""
import copy
import importlib.util
from pathlib import Path

spec=importlib.util.spec_from_file_location('shared_evidence',Path(__file__).with_name('check-shared-audio-workspace-evidence.py'))
q=importlib.util.module_from_spec(spec);spec.loader.exec_module(q)
directory=q.OUT/'compact117-final2'
scenario=q.load(q.OUT/'baseline/scenario.json');seed=q.load(q.OUT/'baseline/fixture-initial.json')
package=q.verify_package(directory,scenario,'117')
assert package['packagedMainUUID']==package['sourceBinaryUUID']
assert q.digest(Path(package['app'])/'Contents/MacOS/circlr')==package['packagedMainSHA256']
revisions={'before':38,'scrolled':38,'compact':38,'gain':39,'undo':40,'ordinary':40,'wave-zoom':40,'restored':40,'reopened':40}
captures={name:q.verify_capture(directory/(name+'.json'),scenario,seed,'117',revision) for name,revision in revisions.items()}
for name,capture in captures.items():
    expected=copy.deepcopy(seed)
    if name=='gain':q.by_id(q.by_id(expected['patterns'],scenario['patternID'])['audio'],scenario['clipIDs'][1])['gain']=10**(-12/20)
    assert q.music(capture['manifest'])==q.music(expected),name
assert captures['before']['manifest']==captures['scrolled']['manifest'],'Content wheel must not move the canvas or change music'
assert captures['compact']['manifest']['hierarchyView']['camera']!=captures['before']['manifest']['hierarchyView']['camera'],'Canvas wheel remains available'
for name in revisions:
    if name not in ('ordinary','wave-zoom'):q.verify_selected_clip(captures[name],scenario,scenario['useA'],scenario['clipIDs'][1])
ordinary=captures['ordinary']['state']['selection']['music']
assert ordinary['useID']==scenario['useA'] and ordinary['nodeID']!=scenario['rhythmAudioNodeID']
assert captures['ordinary']['manifest']['hierarchyView']['camera']==captures['wave-zoom']['manifest']['hierarchyView']['camera']
zoom_ax=(directory/'wave-zoom.ax.txt').read_text()
assert '원본 표시 0.000부터 32.000초' not in zoom_ax and '선택 0.000부터 32.000초' in zoom_ax
q.verify_persistence(captures['restored'],captures['reopened'],scenario)
for name in ('scrolled','compact','gain','ordinary','reopened'):
    ax=(directory/(name+'.ax.txt')).read_text()
    assert len([line for line in ax.splitlines() if line.lstrip()[:1].isdigit() and 'text field (settable) Description: 오디오 ' in line])==8,name
    assert 'sheet Description: alert' not in ax
returned=(directory/'returned.ax.txt').read_text()
assert 'The focused UI element is' in returned and 'container Description: 오디오 파형 편집기' in returned.split('The focused UI element is')[-1]
assert 'Value: -12.00' in (directory/'gain.ax.txt').read_text()
print('PASS: 9 build117 states; content wheel preserves camera, canvas wheel works, gain/Undo and exact reopen; assets intact; no audio I/O')
