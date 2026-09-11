import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('view_mcp', Path(__file__).resolve().parents[1] / 'mcp/server.py')
s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)

class WorkspaceViewTests(unittest.TestCase):
    def args(self, **settings):
        return dict(projectID='p', expectedRevision=7, **settings)

    def probe(self, capability=1, revision=7):
        return dict(ok=True, result=dict(projectID='p', revision=revision,
                    runtime=dict(capabilities=dict(workspaceView=capability))))

    def test_full_settings_forward_without_focus_side_effect(self):
        args = self.args(viewingMode=True, follow=True, followSettings=dict(
            target='pinned', framing='keepZoom', transition='subtle',
            pinned=dict(music=dict(arrangementID='a', useID='u', nodeID='n'))))
        with patch.object(s, 'rpc', side_effect=[self.probe(), dict(ok=True)]) as rpc:
            self.assertFalse(s.call_tool('/unused', 'circlr_workspace_view', args)['isError'])
            self.assertEqual([x.args[1]['method'] for x in rpc.call_args_list], ['snapshot', 'workspace_view'])
            self.assertEqual(rpc.call_args.args[1]['arguments'], {k:v for k,v in args.items() if k not in s.REVISION})

    def test_invalid_settings_fail_before_socket(self):
        cases = [self.args(), self.args(viewingMode=1), self.args(follow=None),
                 self.args(followSettings=dict(target='pinned', framing='fit', transition='off')),
                 self.args(followSettings=dict(target='other', framing='fit', transition='off')),
                 self.args(viewingMode=True, unexpected=True)]
        for args in cases:
            with self.subTest(args=args), patch.object(s, 'rpc') as rpc:
                with self.assertRaises(ValueError): s.call_tool('/unused', 'circlr_workspace_view', args)
                rpc.assert_not_called()

    def test_capability_revision_and_readonly_guards(self):
        for probe in [self.probe(capability=x) for x in [0, True, None, '1']] + [self.probe(revision=8)]:
            with patch.object(s, 'rpc', return_value=probe) as rpc:
                self.assertTrue(s.call_tool('/unused', 'circlr_workspace_view', self.args(follow=False))['isError'])
                self.assertEqual(rpc.call_count, 1)
        with patch.object(s, 'rpc') as rpc:
            with self.assertRaises(ValueError):
                s.call_tool('/unused', 'circlr_workspace_view', self.args(follow=False), read_only=True)
            rpc.assert_not_called()

    def test_loop_scope_requires_capability_and_forwards_exactly(self):
        probe=self.probe()
        probe['result']['runtime']['capabilities']['playbackLoop']=1
        probe['result']['runtime']['capabilities']['playbackLoopLive']=1
        for mode in ['off','song','section']:
            with patch.object(s,'rpc',side_effect=[probe,dict(ok=True)]) as rpc:
                self.assertFalse(s.call_tool('/unused','circlr_playback_loop',self.args(loopMode=mode))['isError'])
                self.assertEqual(rpc.call_args.args[1]['arguments'],dict(loopMode=mode))
        with patch.object(s,'rpc',return_value=self.probe()) as rpc:
            self.assertTrue(s.call_tool('/unused','circlr_playback_loop',self.args(loopMode='song'))['isError'])
            rpc.assert_called_once()
        with patch.object(s,'rpc') as rpc:
            with self.assertRaises(ValueError):s.call_tool('/unused','circlr_playback_loop',self.args(loopMode='album'))
            rpc.assert_not_called()

    def test_loop_live_capability_rejects_old_app_and_preserves_pending_ack(self):
        probe=self.probe()
        probe['result']['runtime']['capabilities']['playbackLoop']=1
        with patch.object(s,'rpc',return_value=probe) as rpc:
            self.assertTrue(s.call_tool('/unused','circlr_playback_loop',self.args(loopMode='section'))['isError'])
            rpc.assert_called_once()
        probe['result']['runtime']['capabilities']['playbackLoopLive']=1
        pending=dict(ok=True,result=dict(loopRequestState='accepted_pending',view=dict(loopMode='song',loopTransition=dict(busy=True,pendingMode='section',phase='rendering'))))
        with patch.object(s,'rpc',side_effect=[probe,pending]):
            response=s.call_tool('/unused','circlr_playback_loop',self.args(loopMode='section'))
            self.assertEqual(response['structuredContent'],pending)

    def test_legacy_follow_does_not_require_new_capability(self):
        with patch.object(s, 'rpc', return_value=dict(ok=True)) as rpc:
            self.assertFalse(s.call_tool('/unused', 'circlr_focus', dict(follow=True))['isError'])
            rpc.assert_called_once()
            self.assertEqual(rpc.call_args.args[1]['method'], 'focus')

if __name__ == '__main__': unittest.main()
