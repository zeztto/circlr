"""Resonance IPC boundary tests; no real socket, application, or audio."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('resonance_mcp', Path(__file__).resolve().parents[1] / 'mcp/server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class ResonanceMCPTests(unittest.TestCase):
    def operation(self, value=0.12):
        return dict(kind='set_automation', arrangementID='a', useID='u', nodeID='n',
                    parameter='synthResonance', automationPoints=[dict(beat=0, value=value)])

    def packet(self, operations):
        return dict(projectID='p', expectedRevision=8, operations=operations)

    def snapshot(self, capability=1, project='p', revision=8, cutoff=1):
        return dict(ok=True, result=dict(projectID=project, revision=revision,
                    runtime=dict(capabilities=dict(synthResonanceAutomation=capability, synthCutoffAutomation=cutoff))))

    def test_advertised_range_and_exact_raw_values(self):
        self.assertIn('synthResonance', server.OPERATION['properties']['parameter']['enum'])
        self.assertEqual(server.AUTOMATION_RANGES['synthResonance'], (0, 0.9))
        for value in (0, 0.12, 0.9):
            op = self.operation(value)
            with patch.object(server, 'rpc', side_effect=[self.snapshot(), dict(ok=True)]) as rpc:
                self.assertFalse(server.call_tool('/unused', 'circlr_apply', self.packet([op]))['isError'])
                self.assertEqual(rpc.call_args.args[1]['arguments']['operations'], [op])
                self.assertEqual([c.args[1]['method'] for c in rpc.call_args_list], ['snapshot', 'apply'])

    def test_invalid_batch_rejected_before_any_rpc(self):
        for value in (-0.001, 0.90001, 1, None, True, '0.1', float('nan'), float('inf')):
            with self.subTest(value=value), patch.object(server, 'rpc') as rpc:
                with self.assertRaises(ValueError):
                    server.call_tool('/unused', 'circlr_apply', self.packet([self.operation(), self.operation(value)]))
                rpc.assert_not_called()
        invalid = self.operation(); invalid['kind'] = 'set_node'
        with patch.object(server, 'rpc') as rpc:
            with self.assertRaises(ValueError):
                server.call_tool('/unused', 'circlr_apply', self.packet([invalid]))
            with self.assertRaises(ValueError):
                server.call_tool('/unused', 'circlr_apply', self.packet([self.operation()]), read_only=True)
            rpc.assert_not_called()

    def test_fresh_capability_required_for_set_clear_and_bypass(self):
        clear = self.operation(); clear['automationPoints'] = []
        bypass = self.operation(); del bypass['automationPoints']; bypass['enabled'] = False
        for op in (self.operation(), clear, bypass):
            op['original'] = True
            for probe in (self.snapshot(capability=0), self.snapshot(capability=True), self.snapshot(capability='1'),
                          self.snapshot(capability=2), self.snapshot(capability=None), self.snapshot(project='other'),
                          self.snapshot(revision=9), dict(ok=True, result={}), dict(ok=False), None):
                with self.subTest(op=op, probe=probe), patch.object(server, 'rpc', return_value=probe) as rpc:
                    self.assertTrue(server.call_tool('/unused', 'circlr_apply', self.packet([op]))['isError'])
                    rpc.assert_called_once(); self.assertEqual(rpc.call_args.args[1]['method'], 'snapshot')
            with patch.object(server, 'rpc', side_effect=[self.snapshot(), dict(ok=True)]) as rpc:
                self.assertFalse(server.call_tool('/unused', 'circlr_apply', self.packet([op]))['isError'])
                self.assertEqual(rpc.call_args.args[1]['arguments']['operations'], [op])

    def test_mixed_cutoff_requires_both_capabilities_in_one_snapshot(self):
        cutoff = self.operation(400); cutoff['parameter'] = 'synthCutoff'
        batch = [cutoff, self.operation()]
        for probe in (self.snapshot(cutoff=0), self.snapshot(capability=0)):
            with patch.object(server, 'rpc', return_value=probe) as rpc:
                self.assertTrue(server.call_tool('/unused', 'circlr_apply', self.packet(batch))['isError'])
                rpc.assert_called_once()
        with patch.object(server, 'rpc', side_effect=[self.snapshot(), dict(ok=True)]) as rpc:
            self.assertFalse(server.call_tool('/unused', 'circlr_apply', self.packet(batch))['isError'])
            self.assertEqual(rpc.call_count, 2)
            self.assertEqual(rpc.call_args.args[1]['arguments']['operations'], batch)

    def test_final_app_target_engine_and_revision_rejections_propagate(self):
        for error in ('stale_revision', 'unsupported engine 1', 'wrong node', 'unsupported sampler'):
            with patch.object(server, 'rpc', side_effect=[self.snapshot(), dict(ok=False, error=error)]) as rpc:
                result = server.call_tool('/unused', 'circlr_apply', self.packet([self.operation()]))
                self.assertTrue(result['isError']); self.assertEqual(result['structuredContent']['error'], error)
                self.assertEqual(rpc.call_count, 2)


if __name__ == '__main__':
    unittest.main()
