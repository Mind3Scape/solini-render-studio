import io
import json
import pytest
from fastapi.testclient import TestClient
from PIL import Image
import salini.app as backend
import salini.config as config


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(backend, 'DATA', tmp_path)
    monkeypatch.setattr(config, 'DATA', tmp_path)
    monkeypatch.setattr(backend, 'manager', backend.JobManager())
    with TestClient(backend.app) as client:
        yield client


def upload(client):
    buf = io.BytesIO(); Image.new('RGB', (128,128), 'white').save(buf, format='PNG')
    response = client.post('/api/uploads', files={'file': ('example.png', buf.getvalue(), 'image/png')})
    assert response.status_code == 200
    return response.json()


def test_upload_metadata_and_validation(client):
    data = upload(client)
    assert client.get('/api/uploads/'+data['id']).json()['width'] == 128
    assert client.get(data['url']).headers['content-type'] == 'image/png'
    assert client.post('/api/uploads', files={'file': ('bad.png', b'not an image')}).status_code == 400
    assert client.post('/api/jobs', json={'upload_id':data['id'],'crop':[0,0,64,200]}).status_code == 400
    assert client.get('/api/jobs/not-a-job/files/after.png').status_code == 404
    assert client.post('/api/uploads', headers={'Origin':'https://example.com'}, files={'file': ('x', b'x')}).status_code == 403
    assert client.get('/api/status', headers={'Host':'attacker.example'}).status_code == 403


def test_restore_and_reset_exports(client, monkeypatch):
    data = upload(client)
    monkeypatch.setattr(backend.manager, 'start', lambda key: None)
    response = client.post('/api/jobs', json={'upload_id':data['id'],'crop':[10,10,80,80]})
    assert response.status_code == 200
    key = response.json()['id']; path = backend.DATA/'jobs'/key
    Image.new('RGB', (80,80), 'black').save(path/'after.png')
    backend.write_json(path/'status.json', {'id':key,'status':'done','created_at':1})
    url = f'/api/jobs/{key}/restore'
    assert client.post(url, json={'box':[0,0,100,100]}).status_code == 400
    assert not (path/'generated.png').exists()
    response = client.post(url, json={'box':[20,20,30,30]})
    assert response.json()['restored_regions'] == [[20,20,30,30]]
    assert Image.open(path/'after.png').getpixel((30,30)) == (255,255,255)
    doc = Image.open(path/'document.png')
    assert doc.getpixel((0,0)) == (255,255,255)
    assert doc.getpixel((11,11)) == (0,0,0)
    assert client.get(f'/api/jobs/{key}/files/comparison.html').status_code == 200
    assert client.post(url, json={'reset':True}).json()['restored_regions'] == []
    assert Image.open(path/'after.png').getpixel((30,30)) == (0,0,0)
    backend.manager.active = 'busy'
    assert client.post('/api/jobs', json={'upload_id':data['id'],'crop':[0,0,80,80]}).status_code == 409
    backend.manager.active = None


def test_cache_download_does_not_contact_network(tmp_path, monkeypatch):
    import salini.worker as worker
    import huggingface_hub
    monkeypatch.setattr(worker, 'DATA', tmp_path)
    monkeypatch.setattr(config, 'DATA', tmp_path)
    config.ensure_dirs()
    cache = tmp_path/'cached'; cache.mkdir()
    (tmp_path/'models/klein4.json').write_text(json.dumps({'path':str(cache),'revision':config.MODELS['klein4']['revision']}))
    def unexpected(*args, **kwargs): raise AssertionError('Network called for cached model')
    monkeypatch.setattr(huggingface_hub, 'snapshot_download', unexpected)
    assert worker.download_model('klein4') == str(cache)


def test_catalog_and_live_color_preserve_generation(client,monkeypatch):
    models=client.get('/api/status').json()['models']
    assert {'qwen21','longcat','firered','fibo15','hunyuan'}.issubset({x['key'] for x in models})
    data=upload(client)
    monkeypatch.setattr(backend.manager,'start',lambda key:None)
    response=client.post('/api/jobs',json={'upload_id':data['id'],'crop':[10,10,80,80],'mode':'daylight','color_style':'warm','amount':50})
    key=response.json()['id'];path=backend.DATA/'jobs'/key
    Image.new('RGB',(80,80),(130,110,90)).save(path/'after.png')
    backend.write_json(path/'status.json',{'id':key,'status':'done','created_at':1})
    endpoint=f'/api/jobs/{key}/look'
    assert client.post(endpoint,json={'color_style':'cool','color_strength':100,'amount':100}).status_code==200
    cool=(path/'after.png').read_bytes();raw=(path/'generated.png').read_bytes()
    assert client.post(endpoint,json={'color_style':'warm','color_strength':100,'amount':100}).status_code==200
    assert (path/'after.png').read_bytes()!=cool
    assert (path/'generated.png').read_bytes()==raw
    assert client.post(endpoint,json={'color_style':'warm','color_strength':100,'amount':0}).status_code==200
    assert Image.open(path/'after.png').getpixel((20,20))==(255,255,255)
    assert client.post(endpoint,json={'amount':101}).status_code==422
    assert client.post('/api/jobs',json={'upload_id':data['id'],'crop':[0,0,80,80],'model':'dlss'}).status_code==400
