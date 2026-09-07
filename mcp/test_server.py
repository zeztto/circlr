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
        self.assertEqual(len(tools), 14)
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

    def test_finite_edit_packet_is_accepted(self):
        server.validate({"projectID": "p", "expectedRevision": 2, "operations": [{"kind": "set_notes", "useID": "u", "laneID": "l", "notes": [{"beat": 0, "length": 1, "pitch": 66, "velocity": 90}]}]}, server.BY_NAME["circlr_apply"]["inputSchema"])

    def test_follow_requires_boolean(self):
        schema = server.BY_NAME["circlr_focus"]["inputSchema"]
        for value in (True, False):
            server.validate({"follow": value}, schema)
        for value in ("true", 1, None):
            with self.assertRaises(ValueError):
                server.validate({"follow": value}, schema)


if __name__ == "__main__":
    unittest.main()
