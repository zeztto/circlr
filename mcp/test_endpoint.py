"""Real AF_UNIX coverage for the selected Circlr MCP endpoint boundary."""
import importlib.util
import json
import os
from pathlib import Path
import select
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
import uuid
from unittest.mock import patch

SERVER = Path(__file__).with_name("server.py")
spec = importlib.util.spec_from_file_location("circlr_endpoint_server", SERVER)
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


class Listener:
    def __init__(self, path, count=1, reply=b'{"ok":true,"result":{}}\n'):
        self.path = str(path)
        self.packets = []
        self.error = None
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.bind(self.path)
        self.sock.listen(2)
        self.sock.settimeout(3)
        self.count = count
        self.reply = reply
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self):
        try:
            for _ in range(self.count):
                client, _ = self.sock.accept()
                with client:
                    data = bytearray()
                    while not data.endswith(b"\n"):
                        part = client.recv(4096)
                        if not part:
                            break
                        data.extend(part)
                    self.packets.append(bytes(data))
                    client.sendall(self.reply)
        except OSError as error:
            self.error = error
        finally:
            self.sock.close()

    def finish(self):
        self.thread.join(4)
        if self.thread.is_alive():
            self.sock.close()
            self.thread.join(1)
            raise AssertionError("Listener did not receive its expected request")
        if self.error:
            raise self.error


class EndpointTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="mcpe-", dir="/tmp")
        self.addCleanup(self.tmp.cleanup)
        self.agent = Path(self.tmp.name) / "Agent"
        self.agent.mkdir()
        self.legacy = self.agent / "agent.sock"
        self.run_id = str(uuid.uuid4()).upper()

    def publish(self, endpoint=".r1a2b3c4d", run_id=None, **changes):
        data = {"schema": "circlr-agent-endpoint-v1", "endpoint": endpoint,
                "runID": run_id or self.run_id, "bundleID": "com.circlr.qa"}
        data.update(changes)
        path = self.agent / "selected.json"
        staged = self.agent / "selected.tmp"
        staged.write_text(json.dumps(data))
        staged.chmod(0o600)
        staged.replace(path)
        return path

    def isolated_home(self):
        home = Path(self.tmp.name) / "home"
        default_agent = home / "Library/Application Support/circlr/Agent"
        default_agent.parent.mkdir(parents=True)
        default_agent.symlink_to(self.agent, target_is_directory=True)
        env = {**os.environ, "HOME": str(home)}
        env.pop("CIRCLR_SOCKET", None)
        return env

    def test_default_resolves_each_rpc_and_sends_versioned_wire_and_run_id(self):
        listener = Listener(self.agent / ".r1a2b3c4d", 2)
        self.publish()
        resolver = adapter.EndpointResolver(self.legacy)
        self.assertTrue(adapter.rpc(resolver, {"id": "one", "method": "snapshot", "arguments": {}})["ok"])
        self.assertFalse(adapter.call_tool(resolver, "circlr_snapshot", {})["isError"])
        listener.finish()
        self.assertEqual(len(listener.packets), 2)
        for packet in listener.packets:
            self.assertTrue(packet.startswith(("CIRCLR/2 " + self.run_id + " ").encode()))
            body = json.loads(packet.split(b" ", 2)[2])
            self.assertEqual(body["expectedRunID"], self.run_id)
        self.assertEqual(resolver.pinned, (str(self.agent / ".r1a2b3c4d"), self.run_id))

    def test_manifest_replacement_or_deletion_fails_closed_after_success(self):
        listener = Listener(self.agent / ".r1a2b3c4d")
        self.publish()
        resolver = adapter.EndpointResolver(self.legacy)
        adapter.rpc(resolver, {"id": "one", "method": "snapshot", "arguments": {}})
        listener.finish()
        self.publish(endpoint=".rdeadbeef", run_id=str(uuid.uuid4()))
        with self.assertRaisesRegex(ValueError, "target_changed"):
            adapter.rpc(resolver, {"id": "two", "method": "snapshot", "arguments": {}})
        (self.agent / "selected.json").unlink()
        with self.assertRaisesRegex(ValueError, "target_changed"):
            adapter.rpc(resolver, {"id": "three", "method": "snapshot", "arguments": {}})
        self.publish(endpoint="../../wrong")
        result = adapter.call_tool(resolver, "circlr_snapshot", {})
        self.assertTrue(result["isError"])
        self.assertIn("target_changed", result["structuredContent"]["error"])

    def test_native_rejection_still_pins_reached_run_and_deleted_manifest_cannot_fallback(self):
        listener = Listener(self.agent / ".r1a2b3c4d", reply=b'{"ok":false,"error":"stale_revision"}\n')
        self.publish()
        resolver = adapter.EndpointResolver(self.legacy)
        self.assertFalse(adapter.rpc(resolver, {"id": "one", "method": "snapshot", "arguments": {}})["ok"])
        listener.finish()
        self.assertEqual(resolver.pinned, (str(self.agent / ".r1a2b3c4d"), self.run_id))
        (self.agent / "selected.json").unlink()
        with self.assertRaisesRegex(ValueError, "target_changed"):
            adapter.rpc(resolver, {"id": "two", "method": "snapshot", "arguments": {}})

    def test_legacy_without_manifest_and_explicit_path_retain_json_wire(self):
        listener = Listener(self.legacy, count=2)
        resolver = adapter.EndpointResolver(self.legacy)
        adapter.rpc(resolver, {"id": "legacy", "method": "snapshot", "arguments": {}})
        adapter.rpc(resolver, {"id": "legacy-again", "method": "snapshot", "arguments": {}})
        listener.finish()
        self.assertEqual(len(listener.packets), 2)
        for packet in listener.packets:
            self.assertTrue(packet.startswith(b"{"))
            self.assertNotIn("expectedRunID", json.loads(packet))
        self.legacy.unlink()
        listener = Listener(self.legacy)
        self.publish(endpoint=".r1a2b3c4d")
        adapter.rpc(str(self.legacy), {"id": "explicit", "method": "snapshot", "arguments": {}})
        listener.finish()
        self.assertTrue(listener.packets[0].startswith(b"{"))
        self.assertNotIn("expectedRunID", json.loads(listener.packets[0]))

    def test_successful_legacy_default_pins_before_new_manifest_appears(self):
        listener = Listener(self.legacy, reply=b'{"ok":false,"error":"busy"}\n')
        resolver = adapter.EndpointResolver(self.legacy)
        self.assertFalse(adapter.rpc(resolver, {"id": "legacy", "method": "snapshot", "arguments": {}})["ok"])
        listener.finish()
        self.assertEqual(resolver.pinned, (str(self.legacy), None))
        self.assertIsNotNone(resolver.pinned_identity)
        self.publish()
        failed = adapter.call_tool(resolver, "circlr_snapshot", {})
        self.assertTrue(failed["isError"])
        self.assertIn("target_changed", failed["structuredContent"]["error"])

    def test_same_legacy_path_reused_by_another_socket_is_rejected(self):
        listener = Listener(self.legacy)
        resolver = adapter.EndpointResolver(self.legacy)
        adapter.rpc(resolver, {"id": "legacy", "method": "snapshot", "arguments": {}})
        listener.finish()
        self.legacy.rename(self.agent / "old-agent.sock")
        replacement = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            replacement.bind(str(self.legacy))
            replacement.listen(1)
            with self.assertRaisesRegex(ValueError, "target_changed"):
                adapter.rpc(resolver, {"id": "next", "method": "snapshot", "arguments": {}})
        finally:
            replacement.close()

    def test_same_selected_path_reused_with_unchanged_manifest_is_rejected(self):
        selected = self.agent / ".r1a2b3c4d"
        listener = Listener(selected)
        self.publish()
        resolver = adapter.EndpointResolver(self.legacy)
        adapter.rpc(resolver, {"id": "first", "method": "snapshot", "arguments": {}})
        listener.finish()
        selected.rename(self.agent / "old-selected.sock")
        replacement = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            replacement.bind(str(selected))
            replacement.listen(1)
            with self.assertRaisesRegex(ValueError, "target_changed"):
                adapter.rpc(resolver, {"id": "second", "method": "snapshot", "arguments": {}})
        finally:
            replacement.close()

    def test_manifest_present_but_bad_never_falls_back_to_legacy(self):
        path = self.publish()
        resolver = adapter.EndpointResolver(self.legacy)
        invalid = [
            {"endpoint": "../agent.sock"}, {"endpoint": "agent.sock.r1a2b3c4d"},
            {"endpoint": ".rABCDEF12"}, {"endpoint": ".r1234567"},
            {"runID": "not-a-uuid"}, {"schema": "future-schema"},
            {"bundleID": ""},
        ]
        for fields in invalid:
            with self.subTest(fields=fields):
                self.publish(**fields)
                with self.assertRaisesRegex(ValueError, "Invalid endpoint manifest"):
                    resolver.resolve()
        path.write_text("{" + '"schema":"x",' * 500 + "}")
        with self.assertRaisesRegex(ValueError, "Invalid endpoint manifest"):
            resolver.resolve()
        path.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "Invalid endpoint manifest"):
            resolver.resolve()
        path.unlink()
        path.symlink_to(self.agent / "selected.tmp")
        with self.assertRaisesRegex(ValueError, "Invalid endpoint manifest"):
            resolver.resolve()

    def test_selected_endpoint_must_be_same_user_socket(self):
        self.publish()
        endpoint = self.agent / ".r1a2b3c4d"
        # A published but unavailable endpoint must not use a concurrent legacy app.
        with self.assertRaises(FileNotFoundError):
            adapter.EndpointResolver(self.legacy).resolve()
        endpoint.write_text("not a socket")
        with self.assertRaisesRegex(ValueError, "same-user socket"):
            adapter.EndpointResolver(self.legacy).resolve()
        endpoint.unlink()
        endpoint.symlink_to(self.agent / "missing.sock")
        with self.assertRaisesRegex(ValueError, "same-user socket"):
            adapter.EndpointResolver(self.legacy).resolve()

    def test_manifest_requires_owner_and_unique_fields(self):
        path = self.publish()
        with patch.object(adapter.os, "getuid", return_value=os.getuid() + 1):
            with self.assertRaisesRegex(ValueError, "owner"):
                adapter.EndpointResolver(self.legacy).resolve()
        path.write_text('{"schema":"circlr-agent-endpoint-v1","schema":"circlr-agent-endpoint-v1",'
                        '"endpoint":"agent.sock","runID":"' + self.run_id + '","bundleID":"com.circlr.qa"}')
        with self.assertRaisesRegex(ValueError, "duplicate field"):
            adapter.EndpointResolver(self.legacy).resolve()

    def test_request_cli_uses_selected_endpoint_without_socket_argument(self):
        listener = Listener(self.agent / ".r1a2b3c4d")
        self.publish()
        request = self.agent / "request.json"
        request.write_text(json.dumps({"id": "cli", "method": "snapshot", "arguments": {}}))
        # HOME is isolated so the default path resolves to this fixture.
        env = self.isolated_home()
        result = subprocess.run([sys.executable, str(SERVER), "--request", str(request)],
                                env=env, text=True, capture_output=True, timeout=5)
        listener.finish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)["ok"])
        self.assertTrue(listener.packets[0].startswith(b"CIRCLR/2 "))

    def test_cli_explicit_socket_and_environment_keep_legacy_wire(self):
        self.publish()
        request = self.agent / "request.json"
        request.write_text(json.dumps({"id": "cli", "method": "snapshot", "arguments": {}}))
        env = self.isolated_home()
        env["CIRCLR_SOCKET"] = str(self.legacy)
        listener = Listener(self.legacy)
        result = subprocess.run([sys.executable, str(SERVER), "--request", str(request)],
                                env=env, text=True, capture_output=True, timeout=5)
        listener.finish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(listener.packets[0].startswith(b"{"))
        self.legacy.unlink()
        listener = Listener(self.legacy)
        env["CIRCLR_SOCKET"] = str(self.agent / "wrong.sock")
        result = subprocess.run([sys.executable, str(SERVER), "--socket", str(self.legacy),
                                 "--request", str(request)], env=env, text=True, capture_output=True, timeout=5)
        listener.finish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(listener.packets[0].startswith(b"{"))

    def test_stdio_session_pins_first_successful_run(self):
        listener = Listener(self.agent / ".r1a2b3c4d")
        self.publish()
        proc = subprocess.Popen([sys.executable, str(SERVER)], env=self.isolated_home(),
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, bufsize=1)
        try:
            def exchange(packet):
                proc.stdin.write(json.dumps(packet) + "\n")
                proc.stdin.flush()
                ready, _, _ = select.select([proc.stdout], [], [], 3)
                self.assertTrue(ready, "MCP server did not answer")
                return json.loads(proc.stdout.readline())

            exchange({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-11-25"}})
            proc.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
            proc.stdin.flush()
            first = exchange({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                              "params": {"name": "circlr_snapshot", "arguments": {}}})
            listener.finish()
            self.assertFalse(first["result"]["isError"])
            self.publish(endpoint=".rdeadbeef", run_id=str(uuid.uuid4()))
            second = exchange({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                               "params": {"name": "circlr_snapshot", "arguments": {}}})
            self.assertTrue(second["result"]["isError"])
            self.assertIn("target_changed", second["result"]["structuredContent"]["error"])
        finally:
            proc.stdin.close()
            proc.wait(timeout=5)
            proc.stdout.close()
            proc.stderr.close()


if __name__ == "__main__":
    unittest.main()
