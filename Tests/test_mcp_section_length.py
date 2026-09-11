import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('section_length_mcp',Path(__file__).resolve().parents[1]/'mcp/server.py')
s=importlib.util.module_from_spec(spec);spec.loader.exec_module(s)

class SectionLengthMCPTests(unittest.TestCase):
    def args(self,op):return dict(projectID='p',expectedRevision=3,operations=[op])
    def operation(self,clear=False):
        return dict(kind='clear_use_length_override' if clear else 'set_use_length_override',arrangementID='a',useID='u',**({} if clear else {'bars':8}))
    def probe(self,cap=1):return dict(ok=True,result=dict(projectID='p',revision=3,runtime=dict(capabilities=dict(sectionLengthEditing=cap))))
    def test_set_clear_gate_and_forward_exactly(self):
        for op in [self.operation(),self.operation(True)]:
            with self.subTest(op=op),patch.object(s,'rpc',side_effect=[self.probe(),dict(ok=True)]) as rpc:
                self.assertFalse(s.call_tool('/unused','circlr_apply',self.args(op))['isError'])
                self.assertEqual([c.args[1]['method'] for c in rpc.call_args_list],['snapshot','apply'])
                self.assertEqual(rpc.call_args.args[1]['arguments']['operations'],[op])
    def test_new_operation_strict_shape_rejects_before_socket(self):
        invalid=[]
        for clear in [False,True]:
            op=self.operation(clear)
            invalid.extend({k:v for k,v in op.items() if k!=key} for key in ['arrangementID','useID'])
            invalid.extend(dict(op,**{key:None}) for key in ['arrangementID','useID'])
            invalid.extend(dict(op,**{key:value}) for key,value in [('name','wrong'),('nodeID','n'),('settings',{}),('original',False),('unknown',1)])
        invalid.extend(dict(self.operation(),bars=value) for value in [None,True,0,4097,1.5,'8'])
        invalid.append({k:v for k,v in self.operation().items() if k!='bars'})
        invalid.append(dict(self.operation(True),bars=8))
        for op in invalid:
            with self.subTest(op=op),patch.object(s,'rpc') as rpc:
                with self.assertRaises(ValueError):s.call_tool('/unused','circlr_apply',self.args(op))
                rpc.assert_not_called()
    def test_bad_capability_stale_or_readonly_never_mutates(self):
        probes=[self.probe(value) for value in [None,False,True,0,2,'1']]
        for key,value in [('projectID','other'),('revision',4)]:
            probe=self.probe();probe['result'][key]=value;probes.append(probe)
        for probe in probes:
            with patch.object(s,'rpc',return_value=probe) as rpc:
                self.assertTrue(s.call_tool('/unused','circlr_apply',self.args(self.operation()))['isError'])
                rpc.assert_called_once();self.assertEqual(rpc.call_args.args[1]['method'],'snapshot')
        with patch.object(s,'rpc') as rpc:
            with self.assertRaises(ValueError):s.call_tool('/unused','circlr_apply',self.args(self.operation()),read_only=True)
            rpc.assert_not_called()
    def test_other_legacy_section_fields_do_not_require_new_capability(self):
        op=dict(kind='set_section',useID='u',name='별명',repeatCount=2,bars=8)
        with patch.object(s,'rpc',return_value=dict(ok=True)) as rpc:
            self.assertFalse(s.call_tool('/unused','circlr_apply',self.args(op))['isError'])
            rpc.assert_called_once();self.assertEqual(rpc.call_args.args[1]['method'],'apply')

if __name__=='__main__':unittest.main()
