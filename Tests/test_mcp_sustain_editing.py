import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('sustain_mcp', Path(__file__).resolve().parents[1] / 'mcp/server.py')
s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)


class SustainEditingMCPTests(unittest.TestCase):
    def operation(self, change=None, shared=False):
        address = dict(patternID='patt', trackID='track') if shared else dict(arrangementID='a', useID='u', laneID='l', original=False)
        return dict(kind='edit_sustain', sustainChange=change or dict(kind='clear'), **address)

    def arguments(self, *ops):
        return dict(projectID='p', expectedRevision=3, operations=list(ops))

    def snapshot(self, capability=1):
        return dict(ok=True, result=dict(projectID='p', revision=3, runtime=dict(capabilities=dict(midiSustainEditing=capability))))

    def test_actions_and_addresses_forward_exactly(self):
        changes = [dict(kind='insert', beat=0, rawValue=64), dict(kind='update', index=0, beat=1.5, rawValue=63),
                   dict(kind='remove', index=0), dict(kind='setInitial', channel=15, rawValue=127), dict(kind='clear')]
        for shared in (False, True):
            for change in changes:
                args = self.arguments(self.operation(change, shared))
                with self.subTest(shared=shared, change=change), patch.object(s, 'rpc', side_effect=[self.snapshot(), dict(ok=True)]) as rpc:
                    self.assertFalse(s.call_tool('/unused', 'circlr_apply', args)['isError'])
                    self.assertEqual([c.args[1]['method'] for c in rpc.call_args_list], ['snapshot', 'apply'])
                    self.assertEqual(rpc.call_args.args[1]['arguments']['operations'], args['operations'])

    def test_invalid_shapes_never_touch_socket(self):
        invalid = []
        for field, value in [('sustainChange', None), ('change', dict(kind='clear')), ('clipID', 'c'), ('original', None), ('gain', 1), ('patternID', 'patt'), ('previewOnly', True)]:
            invalid.append(dict(self.operation(), **{field: value}))
        for field in ['arrangementID', 'useID', 'laneID', 'original', 'sustainChange']:
            invalid.append({k: v for k, v in self.operation().items() if k != field})
        changes = [dict(kind='insert', beat=0, rawValue=v) for v in [-1, 128, True, None, 1.5]]
        changes += [dict(kind='insert', beat=v, rawValue=64) for v in [-1, float('nan'), float('inf'), 131073, None]]
        changes += [dict(kind='clear', rawValue=0), dict(kind='remove', index=-1), dict(kind='setInitial', channel=16, rawValue=0),
                    dict(kind='setInitial', rawValue=0), dict(kind='insert', beat=0), dict(kind='update', index=0, rawValue=1),
                    dict(kind='clear', extra=1)]
        invalid += [self.operation(c) for c in changes]
        invalid += [dict(self.operation(shared=True), **{field: value}) for field, value in [('original', False), ('laneID', 'l'), ('compositionID', 'c')]]
        invalid += [dict(kind='set_track', trackID='t', sustainChange=dict(kind='clear'))]
        for operation in invalid:
            with self.subTest(operation=operation), patch.object(s, 'rpc') as rpc:
                with self.assertRaises(ValueError):
                    s.call_tool('/unused', 'circlr_apply', self.arguments(operation))
                rpc.assert_not_called()

    def test_capability_and_fresh_revision_required(self):
        probes = [self.snapshot(v) for v in [None, False, True, 0, 2, '1']]
        missing = self.snapshot(); del missing['result']['runtime']['capabilities']['midiSustainEditing']; probes.append(missing)
        for key, value in [('projectID', 'other'), ('revision', 4), ('revision', True)]:
            probe = self.snapshot(); probe['result'][key] = value; probes.append(probe)
        probes += [dict(ok=False), dict(ok=True, result={})]
        for probe in probes:
            with self.subTest(probe=probe), patch.object(s, 'rpc', return_value=probe) as rpc:
                self.assertTrue(s.call_tool('/unused', 'circlr_apply', self.arguments(self.operation()))['isError'])
                rpc.assert_called_once(); self.assertEqual(rpc.call_args.args[1]['method'], 'snapshot')

    def test_entire_batch_validated_before_rpc_and_final_rejection_retained(self):
        invalid = self.operation(dict(kind='insert', beat=0, rawValue=128))
        with patch.object(s, 'rpc') as rpc:
            with self.assertRaises(ValueError):
                s.call_tool('/unused', 'circlr_apply', self.arguments(dict(kind='set_track', trackID='t', gain=1), invalid))
            rpc.assert_not_called()
        operations = [dict(kind='set_track', trackID='t', gain=1), self.operation()]
        with patch.object(s, 'rpc', side_effect=[self.snapshot(), dict(ok=False, error='stale_revision')]) as rpc:
            result = s.call_tool('/unused', 'circlr_apply', self.arguments(*operations))
            self.assertTrue(result['isError']); self.assertEqual(result['structuredContent']['error'], 'stale_revision')
            self.assertEqual(rpc.call_args.args[1]['arguments']['operations'], operations)

    def test_readonly_and_description_contract(self):
        with patch.object(s, 'rpc') as rpc:
            with self.assertRaises(ValueError):
                s.call_tool('/unused', 'circlr_apply', self.arguments(self.operation()), read_only=True)
            rpc.assert_not_called()
        self.assertIn('midiSustainEditing=1', s.OPERATION['description'])
        self.assertIn('sustainChange', s.OPERATION['properties'])
        self.assertIs(s.OPERATION['properties']['change'], s.BEND_CHANGE)


if __name__ == '__main__':
    unittest.main()
