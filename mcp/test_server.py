import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch
import tempfile

SPEC = importlib.util.spec_from_file_location("circlr_mcp", Path(__file__).with_name("server.py"))
server = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(server)


class MCPTests(unittest.TestCase):
    def test_render_tail_is_optional_bounded_and_forwarded_without_ui_defaults(self):
        for method, scope in [('bounce', {'useID': 'use', 'trackID': 'track'}),
                              ('export', {'path': '/tmp/new-tail.wav'})]:
            base = {'projectID': 'p', 'expectedRevision': 1, **scope}
            for extra in ({}, {'tailSeconds': 0}, {'tailSeconds': 12.5}, {'tailSeconds': 120}):
                with self.subTest(method=method, extra=extra), patch.object(server, 'rpc', return_value={'ok': True}) as ipc:
                    server.call_tool('/qa.sock', 'circlr_' + method, {**base, **extra})
                    forwarded = ipc.call_args.args[1]['arguments']
                    if extra:
                        self.assertEqual(forwarded['tailSeconds'], extra['tailSeconds'])
                    else:
                        self.assertNotIn('tailSeconds', forwarded)
            for invalid in (-0.001, 120.001, float('nan'), float('inf'), float('-inf'), True, '2', None):
                with self.subTest(method=method, invalid=invalid), patch.object(server, 'rpc') as ipc:
                    with self.assertRaises(ValueError):
                        server.call_tool('/unused.sock', 'circlr_' + method, {**base, 'tailSeconds': invalid})
                    ipc.assert_not_called()

    def test_arrangement_apply_requires_explicit_target_and_forwards_atomic_batch(self):
        operations = [
            {'kind': 'duplicate_arrangement', 'compositionID': 'owner', 'arrangementID': 'source', 'name': '  대안  '},
            {'kind': 'rename_arrangement', 'compositionID': 'other-owner', 'arrangementID': 'other-source', 'name': '새 이름'},
            {'kind': 'select_arrangement', 'compositionID': 'owner', 'arrangementID': 'source'},
        ]
        args = {'projectID': 'p', 'expectedRevision': 7, 'operations': operations}
        with patch.object(server, 'rpc', return_value={'ok': True}) as ipc:
            self.assertFalse(server.call_tool('/qa.sock', 'circlr_apply', args)['isError'])
            ipc.assert_called_once()
            request = ipc.call_args.args[1]
            self.assertEqual(request['method'], 'apply')
            self.assertEqual(request['expectedRevision'], 7)
            self.assertEqual(request['arguments']['operations'], operations)
        for operation in operations:
            required = ('compositionID', 'arrangementID') if operation['kind'] == 'select_arrangement' else ('compositionID', 'arrangementID', 'name')
            for key in required:
                for invalid in ({k: v for k, v in operation.items() if k != key}, {**operation, key: 123}):
                    with self.subTest(kind=operation['kind'], key=key, invalid=invalid), patch.object(server, 'rpc') as ipc:
                        with self.assertRaises(ValueError):
                            server.call_tool('/unused.sock', 'circlr_apply', {**args, 'operations': [operations[0], invalid]})
                        ipc.assert_not_called()
        with patch.object(server, 'rpc') as ipc, self.assertRaisesRegex(ValueError, 'read-only'):
            server.call_tool('/unused.sock', 'circlr_apply', args, read_only=True)
        ipc.assert_not_called()

    def test_sounds_read_only_contract_reaches_native(self):
        args={'soundTarget':'instrument','query':'#５','category':'soundBank','bankDrums':False,'offset':2,'limit':1,'catalogID':'a'*64}
        with patch.object(server, 'rpc', return_value={'ok':True,'result':{'items':[]}}) as ipc:
            result=server.call_tool('/qa.sock','circlr_sounds',args,read_only=True)
            self.assertFalse(result['isError'])
            self.assertEqual(ipc.call_args.args[1]['method'],'sounds')
            self.assertEqual(ipc.call_args.args[1]['arguments'],args)
        self.assertTrue(server.BY_NAME['circlr_sounds']['annotations']['readOnlyHint'])
        self.assertFalse(server.BY_NAME['circlr_sounds']['annotations']['destructiveHint'])

    def test_sounds_invalid_arguments_never_reach_ipc(self):
        invalid=[{'soundTarget':'shell'},{'query':'x'*257},{'category':'sampler'},{'bankDrums':0},
                 {'limit':0},{'limit':129},{'limit':True},{'offset':-1},{'offset':1000001},
                 {'catalogID':'short'},{'path':'/tmp/private'},{'query':None}]
        for args in invalid:
            with self.subTest(args=args),patch.object(server,'rpc') as ipc,self.assertRaises(ValueError):
                server.call_tool('/unused.sock','circlr_sounds',args,read_only=True)
            ipc.assert_not_called()

    def test_read_only_rejects_every_mutation_before_ipc(self):
        with patch.object(server, 'rpc') as ipc:
            for entry in server.TOOLS:
                if entry['method'] not in server.READ_METHODS:
                    with self.assertRaisesRegex(ValueError, 'read-only'):
                        server.call_tool('/unused.sock', entry['name'], {}, read_only=True)
            ipc.assert_not_called()

    def test_read_only_catalog_and_direct_call_rejection(self):
        packets = [
            {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {}},
            {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
            {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
            {'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call', 'params': {'name': 'circlr_stop', 'arguments': {}}},
        ]
        result = subprocess.run([sys.executable, str(Path(__file__).with_name('server.py')), '--read-only'],
                                input='\n'.join(map(json.dumps, packets)) + '\n', text=True, capture_output=True, check=True)
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual({t['name'] for t in replies[1]['result']['tools']}, {'circlr_' + m for m in server.READ_METHODS})
        self.assertTrue(replies[2]['result']['isError'])
        self.assertIn('read-only', replies[2]['result']['content'][0]['text'])

    def test_read_only_request_mode_cannot_bypass_filter(self):
        with tempfile.TemporaryDirectory() as temp:
            packet = Path(temp) / 'write.json'
            packet.write_text(json.dumps({'id': 'qa', 'method': 'stop'}))
            result = subprocess.run([sys.executable, str(Path(__file__).with_name('server.py')), '--read-only', '--request', str(packet)], text=True, capture_output=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn('read-only', result.stderr)

    def test_read_only_inspect_still_reaches_native(self):
        with patch.object(server, 'rpc', return_value={'ok': True, 'revision': 7}) as ipc:
            result = server.call_tool('/qa.sock', 'circlr_inspect', {'useID': 'u'}, read_only=True)
            self.assertFalse(result['isError'])
            self.assertEqual(ipc.call_args.args[1]['method'], 'inspect')

    def test_handshake_and_real_tool_catalog(self):
        packets = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-11-25"}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "circlr_apply", "arguments": {"operations": []}}},
        ]
        result = subprocess.run([sys.executable, str(Path(__file__).with_name("server.py")), "--socket", "/nonexistent/circlr.sock"], input="\n".join(json.dumps(p) for p in packets) + "\n", text=True, capture_output=True, check=True)
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(len(replies), 3)
        self.assertEqual(replies[0]["result"]["protocolVersion"], "2025-11-25")
        tools = replies[1]["result"]["tools"]
        self.assertEqual(len(tools), 23)
        self.assertTrue(all("method" not in item for item in tools))
        self.assertTrue(replies[2]["result"]["isError"])

    def test_invalid_inputs_fail_before_ipc(self):
        apply = server.BY_NAME["circlr_apply"]["inputSchema"]
        for arguments in [
            {"projectID": "p", "expectedRevision": True, "operations": [{"kind": "add_section"}]},
            {"projectID": "p", "expectedRevision": 10**400, "operations": [{"kind": "add_section"}]},
            {"projectID": "p", "expectedRevision": 0, "operations": [{"kind": "shell", "command": "noop"}]},
            {"projectID": "p", "expectedRevision": 0, "operations": [{"kind": "set_track", "gain": float("nan")}]},
            {"projectID": "p", "expectedRevision": 0, "operations": [{"kind": "set_notes", "notes": [{"beat": 0, "length": -1, "pitch": 60, "velocity": 90}]}]},
        ]:
            with self.assertRaises(ValueError):
                server.validate(arguments, apply)

    def test_port_contracts_and_revision_forwarding(self):
        node = {"music": {"arrangementID": "a", "useID": "u", "nodeID": "n"}}
        other = {"music": {"arrangementID": "a", "useID": "u", "nodeID": "r"}}
        pair = {"projectID": "p", "expectedRevision": 3, "expectedLayoutRevision": 7,
                "first": {"node": node, "portID": "out.audio.main"},
                "second": {"node": other, "portID": "in.audio.bus2"}, "firstOctant": 2, "secondOctant": 7}
        connection = {"edgeID": "e", "from": node, "to": other}
        packets = {
            "ports": {"node": node}, "connect_ports": pair,
            "reconnect_ports": {**pair, "connectionID": connection},
            "disconnect_ports": {**{k: pair[k] for k in ("projectID", "expectedRevision", "expectedLayoutRevision")}, "connectionID": connection},
            "move_ports": {**{k: pair[k] for k in ("projectID", "expectedRevision", "expectedLayoutRevision")}, "moves": [{"id": connection, "placement": {"from": 0, "to": 7}}]},
        }
        with patch.object(server, "rpc", return_value={"ok": True}) as ipc:
            for name, args in packets.items():
                result = server.call_tool("/qa.sock", "circlr_" + name, args, read_only=name == "ports")
                self.assertFalse(result["isError"])
                request = ipc.call_args.args[1]
                self.assertEqual(request["method"], name)
                if name != "ports":
                    self.assertEqual(request["expectedRevision"], 3)
                    self.assertEqual(request["arguments"]["expectedLayoutRevision"], 7)
                    self.assertNotIn("projectID", request["arguments"])
        for key in pair:
            with self.subTest(missing=key), patch.object(server, "rpc") as ipc, self.assertRaises(ValueError):
                server.call_tool("/unused.sock", "circlr_connect_ports", {k: v for k, v in pair.items() if k != key})
            ipc.assert_not_called()
        for key, value in [("firstOctant", 8), ("secondOctant", True), ("expectedLayoutRevision", -1), ("expectedLayoutRevision", True), ("expectedLayoutRevision", 10**400), ("first", {"node": node, "portID": ""})]:
            with self.subTest(key=key, value=value), patch.object(server, "rpc") as ipc, self.assertRaises(ValueError):
                server.call_tool("/unused.sock", "circlr_connect_ports", {**pair, key: value})
            ipc.assert_not_called()

    def test_port_addresses_are_exact_and_bounded(self):
        for node in [{"signal": {"_0": "s"}}, {"composition": {"_0": "c"}},
                     {"section": {"arrangementID": "a", "useID": "u"}},
                     {"music": {"arrangementID": "a", "useID": "u", "nodeID": "n"}}]:
            server.validate(node, server.PORT_ADDRESS)
        for node in [{}, {"group": {}}, {"album": {}}, {"signal": {"_0": ""}},
                     {"signal": {"_0": "s"}, "composition": {"_0": "c"}},
                     {"signal": {"_0": "s", "extra": 1}}, {"signal": {"_0": "s" * 1025}},
                     {"music": {"useID": "u", "nodeID": "n"}}]:
            with self.subTest(node=node), self.assertRaises(ValueError):
                server.validate(node, server.PORT_ADDRESS)
        move = {"id": {"edgeID": "e", "from": {"signal": {"_0": "s"}}, "to": {"signal": {"_0": "t"}}}, "placement": {"from": 0, "to": 7}}
        for moves in [[], [move] * 129, [{**move, "placement": {"from": 0, "to": -1}}]]:
            with self.subTest(count=len(moves)), self.assertRaises(ValueError):
                server.validate({"projectID": "p", "expectedRevision": 0, "expectedLayoutRevision": 0, "moves": moves}, server.BY_NAME["circlr_move_ports"]["inputSchema"])

    def test_explicit_group_binding_schema_and_write_isolation(self):
        group = {'group': {'parent': {'section': {'arrangementID': 'a', 'useID': 'u'}}, 'id': 'g'}}
        target = {'node': {'music': {'arrangementID': 'a', 'useID': 'u', 'nodeID': 'n'}}, 'portID': 'out.audio.bus2'}
        packet = {'projectID': 'p', 'expectedRevision': 1, 'expectedLayoutRevision': 2, 'node': group, 'target': target, 'name': '신스 출력'}
        for parent in [{'album': {}}, {'sound': {}}, {'composition': {'_0': 'c'}}, {'section': {'arrangementID': 'a', 'useID': 'u'}}]:
            server.validate({'group': {'parent': parent, 'id': 'g'}}, server.PORT_ADDRESS)
        with patch.object(server, 'rpc', return_value={'ok': True}) as ipc:
            self.assertFalse(server.call_tool('/qa.sock', 'circlr_set_group_port', packet)['isError'])
            self.assertEqual(ipc.call_args.args[1]['arguments']['node'], group)
            self.assertEqual(ipc.call_args.args[1]['arguments']['expectedLayoutRevision'], 2)
        for bad in [{**packet, 'name': ''}, {**packet, 'name': 'a'*129}, {**packet, 'node': target['node']},
                    {**packet, 'node': {'group': {'parent': group, 'id': 'nested'}}},
                    {k: v for k, v in packet.items() if k != 'expectedLayoutRevision'}]:
            with patch.object(server, 'rpc') as ipc, self.assertRaises(ValueError):
                server.call_tool('/unused.sock', 'circlr_set_group_port', bad)
            ipc.assert_not_called()
        for name, args in [('set_group_port', packet), ('remove_group_port', {k: v for k, v in packet.items() if k not in {'target', 'name'}} | {'portID': 'b'})]:
            with patch.object(server, 'rpc') as ipc, self.assertRaisesRegex(ValueError, 'read-only'):
                server.call_tool('/unused.sock', 'circlr_'+name, args, read_only=True)
            ipc.assert_not_called()

    def test_record_requires_revision_and_rejects_arbitrary_destination(self):
        with patch.object(server,'rpc',return_value={'ok':True,'result':{'recording':{'permissionPending':True}}}) as ipc:
            for args in [{},{'projectID':'p','expectedRevision':True},{'projectID':'p','expectedRevision':0,'path':'/tmp/record.wav'}]:
                with self.assertRaises(ValueError):server.call_tool('/qa.sock','circlr_record',args)
            ipc.assert_not_called()
            server.call_tool('/qa.sock','circlr_record',{'projectID':'p','expectedRevision':0})
            self.assertEqual(ipc.call_args.args[1]['method'],'record')

    def test_finite_edit_packet_is_accepted(self):
        server.validate({"projectID": "p", "expectedRevision": 2, "operations": [{"kind": "set_notes", "useID": "u", "laneID": "l", "notes": [{"beat": 0, "length": 1, "pitch": 66, "velocity": 90}]}]}, server.BY_NAME["circlr_apply"]["inputSchema"])

    def test_follow_requires_boolean(self):
        schema = server.BY_NAME["circlr_focus"]["inputSchema"]
        for value in (True, False):
            server.validate({"follow": value}, schema)
        for value in ("true", 1, None):
            with self.assertRaises(ValueError):
                server.validate({"follow": value}, schema)

    def test_ten_synth_voices_are_available_and_out_of_range_is_rejected(self):
        schema=server.BY_NAME['circlr_apply']['inputSchema']
        for voice in range(10):
            server.validate({'projectID':'p','expectedRevision':0,'operations':[{'kind':'set_instrument','trackID':'t','synthVoice':voice}]},schema)
        for voice in [-1,10,True]:
            with self.assertRaises(ValueError):
                server.validate({'projectID':'p','expectedRevision':0,'operations':[{'kind':'set_instrument','trackID':'t','synthVoice':voice}]},schema)

    def test_step_grid_types_are_checked_before_ipc(self):
        spec=server.BY_NAME['circlr_apply']['inputSchema']
        op={'kind':'set_step','useID':'u','laneID':'l','stepIndex':4,'subdivisions':4,'pitch':36,'velocity':110,'gate':.9,'enabled':True}
        packet={'projectID':'p','expectedRevision':0,'operations':[op]}
        server.validate(packet,spec)
        for key,value in [('stepIndex',-1),('stepIndex',True),('subdivisions',5),('pitch',128),('velocity',0),('gate',float('nan')),('enabled',1)]:
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):
                server.validate({**packet,'operations':[{**op,key:value}]},spec)

    def test_batch_note_fields_reject_invalid_types_before_ipc(self):
        spec=server.BY_NAME['circlr_apply']['inputSchema']
        op={'kind':'edit_notes','useID':'u','laneID':'l','noteIDs':['n'],'edit':'quantize','subdivisions':4,'strength':.5}
        packet={'projectID':'p','expectedRevision':0,'operations':[op]}
        server.validate(packet,spec)
        for key,value in [('noteIDs',[]),('noteIDs',[3]),('strength',1.1),('strength',True),('edit','unknown'),('semitones',128),('beatOffset',float('inf'))]:
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):
                server.validate({**packet,'operations':[{**op,key:value}]},spec)

    def test_relative_note_edit_schema_rejects_invalid_delta_before_ipc(self):
        spec=server.BY_NAME['circlr_apply']['inputSchema']
        base={'kind':'edit_notes','useID':'u','laneID':'l','noteIDs':['n']}
        def packet(op):return {'projectID':'p','expectedRevision':0,'operations':[dict(base,**op)]}
        server.validate(packet({'edit':'length_delta','beatOffset':-.125}),spec)
        server.validate(packet({'edit':'velocity_delta','velocityOffset':-10}),spec)
        for value in [-127,127,True,1.5,float('nan')]:
            with self.subTest(value=value),self.assertRaises(ValueError):
                server.validate(packet({'edit':'velocity_delta','velocityOffset':value}),spec)
        with self.assertRaises(ValueError):
            server.validate(packet({'edit':'velocity','velocity':-1}),spec)

    def test_audio_edit_numbers_are_validated(self):
        spec=server.BY_NAME['circlr_apply']['inputSchema']
        op={'kind':'edit_audio','useID':'u','nodeID':'n','edit':'split','sourceOffset':0.5}
        packet={'projectID':'p','expectedRevision':0,'operations':[op]}
        server.validate(packet,spec)
        for key,value in [('sourceOffset',0),('sourceOffset',True),('sourceOffset',float('nan')),('fadeIn',-1),('fadeOut',False)]:
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):
                server.validate({**packet,'operations':[{**op,key:value}]},spec)

    def test_automation_point_contract_before_ipc(self):
        spec=server.BY_NAME['circlr_apply']['inputSchema']
        point={'beat':0,'value':0.5,'shape':'linear'}
        op={'kind':'set_automation','useID':'u','nodeID':'n','parameter':'gain','automationPoints':[point]}
        packet={'projectID':'p','expectedRevision':0,'operations':[op]}
        server.validate(packet,spec)
        server.validate({**packet,'operations':[{**op,'automationPoints':[]}]},spec)
        for key,value in [('beat',-1),('beat',float('inf')),('value',True),('value',float('nan')),('value',5),('shape','bezier')]:
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):
                server.validate({**packet,'operations':[{**op,'automationPoints':[{**point,key:value}]}]},spec)


if __name__ == "__main__":
    unittest.main()
