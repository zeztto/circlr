import copy
import importlib.util
import gzip
import json
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('refine',ROOT/'Tools/refine-demo-v6.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class RefinementTests(unittest.TestCase):
    def setUp(self):
        self.source=ROOT/'Resources/Demos/f0r-h3r.circlr'
        # Pinned v0.50.1 source; independent of whichever demo the app now ships.
        self.original=json.loads(gzip.decompress((ROOT/'qa/fixtures/f0r-h3r-v5-manifest.json.gz').read_bytes()))

    def test_deterministic_and_musical_invariants(self):
        old=copy.deepcopy(self.original)
        p,report=module.refine(old)
        self.assertEqual((p,report),module.refine(old))
        self.assertEqual(old,self.original)
        for key in ('id','circleColors','album','arrangements','signal','assets','global'):
            self.assertEqual(p[key],old[key])
        self.assertEqual(p['schemaVersion'],6)
        self.assertEqual(len(report['automation']),5)
        ids=[]
        for a,b in zip(old['sections'],p['sections']):
            self.assertEqual(a['graph']['layout'],b['graph']['layout'])
            self.assertEqual(a['graph']['edges'],b['graph']['edges'])
            self.assertEqual(a['lanes'][:4],b['lanes'][:4])
            for left,right in zip(a['lanes'],b['lanes']):
                for n,m in zip(left['notes'],right['notes']):
                    self.assertEqual({k:v for k,v in n.items() if k!='length'}, {k:v for k,v in m.items() if k!='length'})
                    self.assertGreater(m['length'],0)
                    self.assertLessEqual(m['beat']+m['length'],b['bars']*4+1e-6)
            for node in b['graph']['nodes']:
                for lane in node.get('automation',[]):
                    self.assertEqual([x['beat'] for x in lane['points']],[0,b['bars']*2,b['bars']*4])
                    ids.extend(x['id'] for x in lane['points'])
        self.assertEqual(len(ids),len(set(ids)))

    def test_copy_does_not_overwrite_and_preserves_media(self):
        with tempfile.TemporaryDirectory() as folder:
            source=Path(folder)/'v5.circlr'
            source.mkdir(); (source/'media').mkdir()
            (source/'manifest.json').write_text(json.dumps(self.original))
            for media in (self.source/'media').iterdir():
                (source/'media'/media.name).write_bytes(media.read_bytes())
            target=Path(folder)/'v6.circlr'
            module.run(source,target)
            for media in (self.source/'media').iterdir():
                self.assertEqual(media.read_bytes(),(target/'media'/media.name).read_bytes())
            with self.assertRaises(ValueError): module.run(source,target)
            with self.assertRaises(ValueError): module.run(source,source)

    def test_v6_cannot_be_applied_twice(self):
        result,_=module.refine(self.original)
        with self.assertRaises(ValueError): module.refine(result)

    def test_existing_automation_is_not_silently_replaced(self):
        p=copy.deepcopy(self.original)
        n=next(n for n in p['sections'][2]['graph']['nodes'] if n['content'].get('instrument',{}).get('trackID')==p['tracks'][6]['id'])
        n['automation']=[{'parameter':'gain'}]
        with self.assertRaises(ValueError):module.refine(p)

if __name__=='__main__':unittest.main()
