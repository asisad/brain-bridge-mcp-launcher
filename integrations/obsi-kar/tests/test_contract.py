import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from urllib.error import HTTPError
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from obsi_bundle import build, file_info, safe_relative, stable_json
from obsi_client import Client, TransferError, CONTRACT

class Response(io.BytesIO):
    pass

class FakeGateway:
    """In-memory contract fixture. NOT a shipped server or a production writer."""
    def __init__(self, producer='manus'):
        self.producer = producer
        self.manifest = None
        self.files = {}
        self.calls = []
        self.commits = 0
        self.transient = False
        self.resume = False
        self.deny = None
    def open(self, req, timeout=30):
        self.calls.append((req.method, req.full_url))
        if self.deny:
            raise HTTPError(req.full_url, self.deny, 'Denied', {}, None)
        route = req.full_url.split('/v1/')[1]
        if route == 'capabilities':
            data = {'contract': CONTRACT, 'producer_id': self.producer,
                    'allowed_projects': ['demo'], 'max_files': 100,
                    'max_total_bytes': 2**31, 'max_chunk_bytes': 4096}
        elif route == 'packages':
            value = json.loads(req.data)
            if self.manifest and value != self.manifest:
                raise HTTPError(req.full_url, 409, 'Conflict', {}, None)
            self.manifest = value
            if self.resume and 0 not in self.files:
                self.files[0] = b'abc'
            data = {'package_id': value['package_id'], 'state': 'uploading'}
        elif '/files/' in route:
            index = int(route.split('/files/')[1])
            before = self.files.get(index, b'')
            if req.method == 'PUT':
                offset = int(req.get_header('X-offset'))
                block = req.data
                assert hashlib.sha256(block).hexdigest() == req.get_header('X-chunk-sha256')
                if len(before) == offset:
                    self.files[index] = before + block
                else:
                    assert before[offset:offset+len(block)] == block
                if self.transient:
                    self.transient = False
                    raise HTTPError(req.full_url, 503, 'Retry', {}, None)
            data = {'received_bytes': len(self.files.get(index, b''))}
        elif route.endswith('/commit'):
            for i, entry in enumerate(self.manifest['files']):
                content = self.files.get(i, b'')
                assert len(content) == entry['bytes']
                assert hashlib.sha256(content).hexdigest() == entry['sha256']
            self.commits += 1
            data = {'package_id': self.manifest['package_id'], 'state': 'received'}
        elif route.endswith('/receipt'):
            data = {'state': 'received', 'processed': False,
                    'package_id': self.manifest['package_id'], 'members': self.manifest['files']}
        elif route == 'notes/search': data = {'matches': [], 'complete': True}
        else: raise AssertionError(route)
        return Response(json.dumps(data).encode())

class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.source = self.root / 'selected'
        self.source.mkdir()
    def tearDown(self): self.tmp.cleanup()
    def put(self, name, content=b'abc'):
        p = self.source / name; p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(content); return p
    def manifest(self, **kw): return build(self.source, 'manus', 'demo', **kw)
    def client(self, fake):
        return Client('https://gateway.example.invalid', 'test-fixture-token-not-a-real-secret', opener=fake)
    def test_binary_preserved(self):
        data = bytes(range(256)); p=self.put('image.png', data)
        m=self.manifest(); self.assertEqual(m['files'][0]['sha256'], hashlib.sha256(data).hexdigest())
        self.assertEqual(p.read_bytes(), data)
    def test_zip_is_opaque(self):
        self.put('original.zip', b'PK\x03\x04opaque'); m=self.manifest()
        self.assertEqual(m['file_count'], 1)
        self.assertFalse((self.source/'extracted').exists())
    def test_nested_same_filename(self):
        self.put('a/file.txt'); self.put('b/file.txt', b'other')
        self.assertEqual(self.manifest()['file_count'], 2)
    def test_persian_paths(self):
        self.put('مقاله/متن.txt', 'سلام'.encode())
        self.assertEqual(self.manifest()['files'][0]['path'], 'مقاله/متن.txt')
    def test_deterministic(self):
        self.put('x'); self.assertEqual(self.manifest(), self.manifest())
    def test_revision_changes_id(self):
        self.put('x'); self.assertNotEqual(self.manifest()['package_id'], self.manifest(revision='2')['package_id'])
    def test_content_changes_id(self):
        p=self.put('x'); a=self.manifest(); p.write_bytes(b'def')
        self.assertNotEqual(a['package_id'], self.manifest()['package_id'])
    def test_empty_file(self):
        self.put('empty.txt',b''); self.assertEqual(self.manifest()['total_bytes'],0)
    def test_empty_folder(self):
        with self.assertRaises(ValueError): self.manifest()
    def test_count_limit(self):
        self.put('a'); self.put('b')
        with self.assertRaises(ValueError): self.manifest(max_files=1)
    def test_byte_limit(self):
        self.put('a', b'12345')
        with self.assertRaises(ValueError): self.manifest(max_bytes=4)
    def test_windows_path_safety(self):
        for name in ('../x','/x','x\\y','C:/x','x:stream','NUL.txt','dir/CON', 'x.', 'a//b'):
            with self.subTest(name=name), self.assertRaises(ValueError): safe_relative(name)
    def test_case_collision(self):
        self.put('Name'); self.put('name')
        with self.assertRaises(ValueError): self.manifest()
    def test_symlink(self):
        target=self.put('a'); (self.source/'link').symlink_to(target)
        with self.assertRaises(ValueError): self.manifest()
    def test_hardlink(self):
        target=self.put('a'); os.link(target, self.source/'b')
        with self.assertRaises(ValueError): self.manifest()
    def test_single_file(self):
        p=self.put('one.txt'); m=build(p,'manus','demo')
        self.assertEqual(m['source_kind'],'file')
    def test_invalid_producer(self):
        self.put('x')
        with self.assertRaises(ValueError): build(self.source, '../chatgpt','demo')
    def test_no_absolute_paths_in_manifest(self):
        self.put('a'); self.assertNotIn(str(self.root),json.dumps(self.manifest()))
    def test_http_refused(self):
        with self.assertRaises(TransferError): Client('http://example.invalid','x'*32)
    def test_url_secrets_refused(self):
        for url in ('https://user:pass@example.invalid','https://example.invalid/?token=x'):
            with self.assertRaises(TransferError): Client(url,'x'*32)
    def test_empty_token_refused(self):
        with self.assertRaises(TransferError): Client('https://example.invalid','')
    def test_multiformat_send_fixture(self):
        for name,data in [('a.txt',b'abc'),('sub/image.png',bytes(range(256))),('file.pdf',b'%PDF-synthetic'),
                          ('source.docx',b'PK-synthetic'),('archive.zip',b'PK-synthetic'),('memory.json',b'{"synthetic":true}'),('zero',b'')]:
            self.put(name,data)
        fake=FakeGateway(); result=self.client(fake).send(self.source,'manus','demo')
        self.assertEqual(result['file_count'],7); self.assertFalse(result['processed'])
    def test_multiple_chunks(self):
        self.put('large.bin', b'x'*(3*4096+77)); f=FakeGateway()
        self.client(f).send(self.source,'manus','demo'); self.assertEqual(len(f.files[0]),12365)
    def test_resume(self):
        self.put('a',b'abcdef'); f=FakeGateway(); f.resume=True
        self.client(f).send(self.source,'manus','demo'); self.assertEqual(f.files[0],b'abcdef')
    def test_retry_idempotent_chunk(self):
        self.put('a',b'abcdef'); f=FakeGateway(); f.transient=True
        self.client(f).send(self.source,'manus','demo'); self.assertEqual(f.files[0],b'abcdef')
    def test_repeat_no_resend(self):
        self.put('a',b'abcdef'); f=FakeGateway(); c=self.client(f)
        first=c.send(self.source,'manus','demo'); puts=sum(method=='PUT' for method,_ in f.calls)
        second=c.send(self.source,'manus','demo')
        self.assertEqual(first,second); self.assertEqual(puts,sum(method=='PUT' for method,_ in f.calls))
    def test_no_cross_producer(self):
        self.put('a'); f=FakeGateway('claude')
        with self.assertRaises(TransferError): self.client(f).send(self.source,'manus','demo')
        self.assertIsNone(f.manifest)
    def test_no_unknown_project(self):
        self.put('a'); f=FakeGateway()
        with self.assertRaises(TransferError): self.client(f).send(self.source,'manus','unregistered')
    def test_unauthorized_not_success(self):
        f=FakeGateway(); f.deny=403
        with self.assertRaises(TransferError): self.client(f).capabilities()
    def test_redirect_not_followed(self):
        f=FakeGateway(); f.deny=302
        with self.assertRaises(TransferError): self.client(f).capabilities()
    def test_receipt_is_not_processed(self):
        self.put('a'); f=FakeGateway(); c=self.client(f); sent=c.send(self.source,'manus','demo')
        self.assertFalse(c.receipt(sent['package_id'])['processed'])
    def test_no_injected_receipt_path(self):
        with self.assertRaises(TransferError): self.client(FakeGateway()).receipt('../secret')

if __name__=='__main__': unittest.main(verbosity=2)
