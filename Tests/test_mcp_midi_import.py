import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('midi_import_mcp',Path(__file__).resolve().parents[1]/'mcp/server.py')
s=importlib.util.module_from_spec(spec);spec.loader.exec_module(s)

class MIDIImportMCPTests(unittest.TestCase):
    def args(self,**extra):
        return dict(projectID='p',expectedRevision=3,path='/tmp/score.mid',arrangementID='a',useID='u',**extra)
    def probe(self,**extra):
        return dict(ok=True,result=dict(projectID='p',revision=3,runtime=dict(capabilities=dict(midiTempoImport=1,midiPitchBendImport=1)),**extra))
    def test_default_and_preview_arguments_are_not_injected(self):
        for extra in ({},{'previewOnly':True},{'expressionPolicy':'preserve'},{'expressionPolicy':'omit','previewOnly':True},{'expressionPolicy':'omit'},{'trackIDs':['0:0'],'atBeat':2,'extendSection':True,'tempoPolicy':'applyFile'}):
            args=self.args(**extra)
            with patch.object(s,'rpc',side_effect=[self.probe(),dict(ok=True,result=dict(jobID='job',state='running'))]) as rpc:
                self.assertFalse(s.call_tool('/unused','circlr_import_midi',args)['isError'])
                self.assertEqual([c.args[1]['method'] for c in rpc.call_args_list],['snapshot','import_midi'])
                self.assertEqual(rpc.call_args.args[1]['arguments'],{k:v for k,v in args.items() if k not in s.REVISION})
    def test_invalid_input_does_not_read_socket(self):
        invalid=[dict(self.args(),**{key:value}) for key,value in [('path','relative.mid'),('path','/tmp/a\0.mid'),('atBeat',True),('atBeat',-1),('atBeat',float('nan')),('extendSection',None),('previewOnly','true'),('tempoPolicy','current'),('tempoPolicy',None),('expressionPolicy','ignore'),('expressionPolicy',None),('expressionPolicy',True),('trackIDs',[]),('trackIDs',['0:0','0:0']),('trackIDs',None)]]
        invalid += [{k:v for k,v in self.args().items() if k!=key} for key in ['projectID','expectedRevision','path','arrangementID','useID']]
        for args in invalid:
            with self.subTest(args=args),patch.object(s,'rpc') as rpc:
                with self.assertRaises(ValueError):s.call_tool('/unused','circlr_import_midi',args)
                rpc.assert_not_called()
    def test_capability_or_stale_preflight_never_imports(self):
        probes=[dict(ok=True,result={}),dict(ok=False)]
        for cap in [None,False,0,2,'1']:
            p=self.probe();p['result']['runtime']['capabilities']['midiTempoImport']=cap;probes.append(p)
        for cap in [None,False,0,2,'1']:
            p=self.probe();p['result']['runtime']['capabilities']['midiPitchBendImport']=cap;probes.append(p)
        for key,value in [('projectID','other'),('revision',4)]:
            p=self.probe();p['result'][key]=value;probes.append(p)
        for p in probes:
            with patch.object(s,'rpc',return_value=p) as rpc:
                self.assertTrue(s.call_tool('/unused','circlr_import_midi',self.args())['isError'])
                rpc.assert_called_once();self.assertEqual(rpc.call_args.args[1]['method'],'snapshot')
    def test_preview_is_not_a_readonly_session_bypass(self):
        with patch.object(s,'rpc') as rpc:
            with self.assertRaises(ValueError):s.call_tool('/unused','circlr_import_midi',self.args(previewOnly=True),read_only=True)
            rpc.assert_not_called()
    def test_clear_override_batch_is_gated_and_forwarded_exactly(self):
        op=dict(kind='clear_use_tempo_override',arrangementID='a',useID='u')
        args=dict(projectID='p',expectedRevision=3,operations=[op,dict(kind='set_section',arrangementID='a',useID='u',bars=8)])
        with patch.object(s,'rpc',side_effect=[self.probe(),dict(ok=True)]) as rpc:
            self.assertFalse(s.call_tool('/unused','circlr_apply',args)['isError'])
            self.assertEqual(rpc.call_args.args[1]['arguments']['operations'],args['operations'])
        for key in ['arrangementID','useID']:
            bad={k:v for k,v in op.items() if k!=key}
            with patch.object(s,'rpc') as rpc:
                with self.assertRaises(ValueError):s.call_tool('/unused','circlr_apply',dict(args,operations=[bad]))
                rpc.assert_not_called()
    def test_final_app_rejection_preserved(self):
        with patch.object(s,'rpc',side_effect=[self.probe(),dict(ok=False,error='stale_revision')]):
            result=s.call_tool('/unused','circlr_import_midi',self.args())
            self.assertTrue(result['isError']);self.assertEqual(result['structuredContent']['error'],'stale_revision')

if __name__=='__main__':unittest.main()
