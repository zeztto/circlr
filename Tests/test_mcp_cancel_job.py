import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location('cancel_job_mcp', Path(__file__).resolve().parents[1] / 'mcp/server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class CancelJobMCPTests(unittest.TestCase):
    def probe(self, project='song', capability=1):
        return {'ok': True, 'result': {'projectID': project, 'revision': 9,
                'runtime': {'capabilities': {'jobCancellation': capability}}}}

    def test_catalog_requires_job_id_and_project_but_not_music_revision(self):
        tool = server.BY_NAME['circlr_cancel_job']
        self.assertEqual(set(tool['inputSchema']['required']), {'projectID', 'jobID'})
        self.assertFalse(tool['annotations']['readOnlyHint'])
        self.assertTrue(tool['annotations']['destructiveHint'])

    def test_cancel_checks_current_project_and_capability_then_forwards_exact_id(self):
        result = {'ok': True, 'result': {'job': {'id': 'render-1', 'state': 'cancelled'}}}
        with patch.object(server, 'rpc', side_effect=[self.probe(), result]) as rpc:
            response = server.call_tool('/qa/socket', 'circlr_cancel_job', {'projectID': 'song', 'jobID': 'render-1'})
        self.assertFalse(response['isError'])
        self.assertEqual([call.args[1]['method'] for call in rpc.call_args_list], ['snapshot', 'cancel_job'])
        self.assertEqual(rpc.call_args.args[1]['projectID'], 'song')
        self.assertEqual(rpc.call_args.args[1]['arguments'], {'jobID': 'render-1'})
        self.assertNotIn('expectedRevision', rpc.call_args.args[1])

    def test_invalid_or_read_only_request_never_reaches_native_app(self):
        cases = [{'jobID': 'j'}, {'projectID': 'p'}, {'projectID': 'p', 'jobID': 'j', 'expectedRevision': 3},
                 {'projectID': 1, 'jobID': 'j'}, {'projectID': 'p', 'jobID': None}]
        for arguments in cases:
            with self.subTest(arguments=arguments), patch.object(server, 'rpc') as rpc:
                with self.assertRaises(ValueError):
                    server.call_tool('/qa/socket', 'circlr_cancel_job', arguments)
                rpc.assert_not_called()
        with patch.object(server, 'rpc') as rpc:
            with self.assertRaises(ValueError):
                server.call_tool('/qa/socket', 'circlr_cancel_job', {'projectID': 'p', 'jobID': 'j'}, read_only=True)
            rpc.assert_not_called()

    def test_old_or_changed_project_cannot_cancel_job(self):
        for probe in [self.probe(project='other'), self.probe(capability=0),
                      self.probe(capability=True), self.probe(capability='1'),
                      {'ok': True, 'result': {'projectID': 'song', 'runtime': None}},
                      {'ok': False}]:
            with self.subTest(probe=probe), patch.object(server, 'rpc', return_value=probe) as rpc:
                response = server.call_tool('/qa/socket', 'circlr_cancel_job', {'projectID': 'song', 'jobID': 'j'})
                self.assertTrue(response['isError'])
                rpc.assert_called_once()
                self.assertEqual(rpc.call_args.args[1]['method'], 'snapshot')


if __name__ == '__main__':
    unittest.main()
