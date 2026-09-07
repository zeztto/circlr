"""End-to-end QA against the separate Circlr QA app, never the production socket."""
import json
import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid
from server import rpc

ROOT = Path(__file__).resolve().parents[1]
SOCKET = str(Path.home() / "Library/Application Support/circlr-hierarchy-qa/Agent/agent.sock")
OUTPUT = ROOT / "qa/generated"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-dir', type=Path, default=OUTPUT / ('mcp-' + time.strftime('%Y%m%d-%H%M%S')))
    parser.add_argument('--require-minimized', action='store_true')
    parser.add_argument('--snapshot', action='store_true')
    parser.add_argument('--show-result', type=Path)
    parser.add_argument('--save-copy', type=Path)
    parser.add_argument('--orbit-view', choices=['album','song','section','midi','audio','inspect'])
    parser.add_argument('--capture', type=Path)
    parser.add_argument('--reopen-current', action='store_true')
    options = parser.parse_args()
    if options.reopen_current:
        state=rpc(SOCKET,{'id':str(uuid.uuid4()),'method':'snapshot'})['result']
        assert state['path'].startswith(str(ROOT / 'qa/generated/0.10-')) and not state['dirty']
        opened=rpc(SOCKET,{'id':str(uuid.uuid4()),'method':'open','projectID':state['projectID'],'expectedRevision':state['revision'],'arguments':{'path':state['path']}})
        assert opened['ok'],opened
        for _ in range(90):
            job=rpc(SOCKET,{'id':str(uuid.uuid4()),'method':'job','arguments':{'jobID':opened['result']['jobID']}})['result']['job']
            if job['state']!='running':
                assert job['state']=='completed',job
                print(json.dumps(job,ensure_ascii=False))
                return
            time.sleep(1)
        raise TimeoutError(opened)
    if options.orbit_view:
        def native(method, arguments=None):
            reply=rpc(SOCKET,{'id':str(uuid.uuid4()),'method':method,'arguments':arguments or {}})
            assert reply['ok'],reply
            return reply['result']
        state=native('snapshot')
        assert '/qa/generated/0.10-' in state['path'], 'Only a disposable orbit QA copy'
        ai=state['activeArrangementID'];use=state['arrangements'][0]['uses'][3]['id']
        section=native('inspect',{'arrangementID':ai,'useID':use})
        lane=next(l for l in section['lanes'] if l['trackID']==state['tracks'][1]['id'])
        if options.orbit_view != 'inspect':
            args={}
            if options.orbit_view=='song':args={'compositionID':state['album']['children'][0]}
            if options.orbit_view in ('section','midi','audio'):args={'arrangementID':ai,'useID':use}
            if options.orbit_view=='midi':args.update(nodeID='midi:'+lane['id'],detail=True)
            if options.orbit_view=='audio':args.update(nodeID=next(n['id'] for n in section['graph']['nodes'] if n.get('bounce')),detail=True)
            native('focus',args)
        payload={'state':state,'section':section,'lane':lane}
        if options.capture:options.capture.write_text(json.dumps(payload,ensure_ascii=False,indent=2))
        print(json.dumps({'revision':state['revision'],'laneID':lane['id'],'noteCount':len(lane['notes']),'selection':options.orbit_view},ensure_ascii=False))
        return
    if options.save_copy:
        path=options.save_copy.resolve()
        assert not path.exists(), 'Preservation copy must be a new path'
        current=rpc(SOCKET, {'id':str(uuid.uuid4()), 'method':'snapshot'})['result']
        reply=rpc(SOCKET, {'id':str(uuid.uuid4()), 'method':'save', 'projectID':current['projectID'], 'expectedRevision':current['revision'], 'arguments':{'path':str(path)}})
        assert reply['ok'],reply
        print(json.dumps(reply,ensure_ascii=False))
        return
    if options.snapshot:
        print(json.dumps(rpc(SOCKET, {'id': str(uuid.uuid4()), 'method': 'snapshot'}), ensure_ascii=False, indent=2))
        return
    if options.show_result:
        state = json.loads(options.show_result.read_text())['project']
        current = rpc(SOCKET, {'id': str(uuid.uuid4()), 'method': 'snapshot'})['result']
        if current['path'] != state['path']:
            opened = rpc(SOCKET, {'id': str(uuid.uuid4()), 'method': 'open', 'projectID': current['projectID'], 'expectedRevision': current['revision'], 'arguments': {'path': state['path']}})
            assert opened['ok'], opened
            for _ in range(90):
                job = rpc(SOCKET, {'id': str(uuid.uuid4()), 'method': 'job', 'arguments': {'jobID': opened['result']['jobID']}})['result']['job']
                if job['state'] != 'running':
                    assert job['state'] == 'completed', job
                    break
                time.sleep(1)
            else:
                raise TimeoutError(opened)
        rpc(SOCKET, {'id': str(uuid.uuid4()), 'method': 'focus', 'arguments': {'minimized': False}})
        print(json.dumps(rpc(SOCKET, {'id': str(uuid.uuid4()), 'method': 'focus', 'arguments': {'arrangementID': state['arrangementID'], 'useID': state['useID'], 'nodeID': state['bounceNodeID'], 'detail': True}}), ensure_ascii=False))
        return
    output = options.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=False)
    project = output / 'f0r-h3r-agent.circlr'
    shutil.copytree(ROOT / 'music/f0r-h3r/v1/f0r h3r.circlr', project)
    child = subprocess.Popen([sys.executable, str(ROOT / "mcp/server.py"), "--socket", SOCKET], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
    sequence = 0
    report = {"transport": "MCP stdio → user-only Unix socket → QA native app", "checks": []}

    def message(method, params=None, notification=False):
        nonlocal sequence
        sequence += 1
        packet = {"jsonrpc": "2.0", "method": method}
        if not notification:
            packet["id"] = sequence
        if params is not None:
            packet["params"] = params
        child.stdin.write(json.dumps(packet) + "\n")
        child.stdin.flush()
        if not notification:
            reply = json.loads(child.stdout.readline())
            assert "error" not in reply, reply
            return reply["result"]

    def call(name, args=None, error=False):
        result = message("tools/call", {"name": "circlr_" + name, "arguments": args or {}})
        assert bool(result.get("isError")) == error, result
        payload = result.get("structuredContent") or json.loads(result["content"][0]["text"])
        return payload if error else payload["result"]

    def scope(state):
        return {"projectID": state["projectID"], "expectedRevision": state["revision"]}

    def wait(job, terminal='completed'):
        for _ in range(90):
            result = call("job", {"jobID": job["jobID"]})["job"]
            if result["state"] != "running":
                assert result["state"] == terminal, result
                return result
            time.sleep(1)
        raise TimeoutError(job)

    try:
        initialize = message("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "circlr-native-qa", "version": "1"}})
        message("notifications/initialized", notification=True)
        tools = message("tools/list")["tools"]
        assert len(tools) == 14
        report["checks"].append("MCP initialize and 14-tool discovery")
        if options.require_minimized:
            call('focus', {'minimized': True})
            time.sleep(1)
        state = call("snapshot")
        report['runtimeBefore'] = state['runtime']
        if options.require_minimized:
            assert any(window['minimized'] for window in state['runtime']['windows']), state['runtime']
        wait(call("open", {**scope(state), "path": str(project)}))
        state = call('snapshot')
        assert state["name"] == "f0r h3r" and len(state["tracks"]) == 8
        assert len(state['assets']) == 6 and state['album']
        ai = state["activeArrangementID"]
        use = state["arrangements"][0]["uses"][3]["id"]
        track = state["tracks"][3]["id"]
        section = call("inspect", {"arrangementID": ai, "useID": use})
        lane = next(lane for lane in section["lanes"] if lane["trackID"] == track)
        before_notes = lane["notes"]
        op = {"kind": "generate_midi", "arrangementID": ai, "useID": use, "laneID": lane["id"], "pattern": "arpeggio"}
        edited = call("apply", {**scope(state), "operations": [op]})
        assert edited["revision"] == state["revision"] + 1
        changed = call("inspect", {"arrangementID": ai, "useID": use})
        assert len(next(x for x in changed["lanes"] if x["id"] == lane["id"])["notes"]) == 64
        rejected = call("apply", {**scope(state), "operations": [op]}, error=True)
        assert "stale_revision" in rejected["error"]
        state = call("undo", scope(edited))
        restored = call("inspect", {"arrangementID": ai, "useID": use})
        assert next(x for x in restored["lanes"] if x["id"] == lane["id"])["notes"] == before_notes
        report["checks"].append("MIDI generation, stale rejection, Undo restores exact notes")
        bad = [{"kind": "rename_project", "name": "must not apply"}, {"kind": "set_node", "useID": use, "nodeID": "missing", "muted": True}]
        call("apply", {**scope(state), "operations": bad}, error=True)
        unchanged = call("snapshot")
        assert unchanged["name"] == state["name"] and unchanged["revision"] == state["revision"]
        report["checks"].append("Invalid batch is atomic")

        packet = {'id': str(uuid.uuid4()), 'method': 'apply', **scope(state), 'arguments': {'operations': [{'kind': 'rename_project', 'name': 'QA retry'}]}}
        first = rpc(SOCKET, packet)
        retry = rpc(SOCKET, packet)
        assert first['ok'] and first == retry
        assert call('snapshot')['revision'] == state['revision'] + 1
        packet['arguments']['operations'][0]['name'] = 'different payload'
        assert not rpc(SOCKET, packet)['ok']
        state = call('undo', scope(first['result']))
        report['checks'].append('Identical native request retries apply once; conflicting payload under same ID is rejected')

        cancelled_path = output / 'must-not-exist-cancelled.wav'
        cancelled_job = call('export', {**scope(state), 'path': str(cancelled_path)})
        call('stop')
        cancelled = wait(cancelled_job, 'cancelled')
        stale_path = output / 'must-not-exist-stale.wav'
        stale_job = call('export', {**scope(state), 'path': str(stale_path)})
        edited = call('apply', {**scope(state), 'operations': [{'kind': 'rename_project', 'name': 'QA in-flight edit'}]})
        stale = wait(stale_job, 'failed')
        assert 'stale_revision' in stale['message'], stale
        state = call('undo', scope(edited))
        assert not cancelled_path.exists() and not stale_path.exists()
        report['checks'].append('Stop cancels render and in-flight revision changes reject stale outputs without files')
        report['rejectedJobs'] = [cancelled, stale]

        baseline = output / "0.9-mcp-before.wav"
        before_job = wait(call("export", {**scope(state), "path": str(baseline)}))
        print("Native MCP baseline export completed", flush=True)
        bounced = wait(call("bounce", {**scope(state), "arrangementID": ai, "useID": use, "trackID": track}))
        assert bounced.get("nodeID")
        state = call("snapshot")
        after_job = wait(call("export", {**scope(state), "path": str(output / "0.9-mcp-bounced.wav")}))
        state = call("save", scope(state))
        assert not state['dirty']
        assert not cancelled_path.exists() and not stale_path.exists()
        report["checks"].append("Asynchronous native bounce and WAV export complete; project saves with source references")
        report["jobs"] = [before_job, bounced, after_job]
        report["project"] = {"path": str(project), "projectID": state["projectID"], "revision": state["revision"], "arrangementID": ai, "useID": use, "trackID": track, "bounceNodeID": bounced["nodeID"]}
        report["events"] = call("events", {"afterSequence": 0})
        report['runtimeAfter'] = state['runtime']
        if options.require_minimized:
            assert any(window['minimized'] for window in state['runtime']['windows']), state['runtime']
            report['checks'].append('All native project edits, bounce, export and save ran with the window minimized')
        (output / "0.9-mcp-native.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
        print(json.dumps({"checks": report["checks"], "bounceNodeID": bounced["nodeID"]}, ensure_ascii=False), flush=True)
    finally:
        child.stdin.close()
        child.wait(timeout=5)


if __name__ == "__main__":
    main()
