import io
import json
from pathlib import Path
import pytest
from fastapi.testclient import TestClient
from PIL import Image
import salini.online_app as online
from salini.app import write_json
from salini.outputs import write_outputs


@pytest.fixture
def service(tmp_path,monkeypatch):
    monkeypatch.setattr(online,'ONLINE_DATA',tmp_path)
    monkeypatch.setattr(online.QueueManager,'begin',lambda self:None)
    monkeypatch.setattr(online,'model_ready',lambda key:key=='klein4')
    monkeypatch.setattr(online,'model_blocker',lambda key:'' if key=='klein4' else 'Недоступна')
    with TestClient(online.app,base_url='https://testserver') as client:
        yield client


def join(client,visitor='a'*43):
    r=client.post('/api/session',json={'invite':online.setup()['invite'],'visitor':visitor})
    assert r.status_code==200
    cookie=r.headers['set-cookie']
    assert 'HttpOnly' in cookie and 'Secure' in cookie and 'SameSite=strict' in cookie


def upload(client):
    stream=io.BytesIO();Image.new('RGB',(128,128),'white').save(stream,format='PNG')
    r=client.post('/api/uploads',files={'file':('example.png',stream.getvalue(),'image/png')})
    assert r.status_code==200
    assert 'owner_id' not in r.json()
    return r.json()


def test_invitation_and_origin_are_required(service):
    assert service.get('/api/status').status_code==401
    assert service.post('/api/session',json={'invite':'wrong'}).status_code==403
    join(service)
    assert service.get('/api/status').status_code==200
    assert service.post('/api/uploads',headers={'Origin':'https://bad.example'},files={'file':('x',b'x')}).status_code==403
    assert service.get('/health',headers={'Host':'bad.example'}).status_code==403
    assert service.get('/health',headers={'Origin':'https://mind3scape.github.io'}).headers['access-control-allow-origin']=='https://mind3scape.github.io'
    assert 'access-control-allow-origin' not in service.get('/health',headers={'Origin':'https://bad.example'}).headers
    service.cookies.set(online.COOKIE,'0'*32+'.9999999999.fake')
    assert service.get('/api/status').status_code==401


def test_visitor_isolation_and_stable_identity(service):
    join(service);source=upload(service)
    data={'upload_id':source['id'],'crop':[0,0,128,128],'model':'klein4'}
    r=service.post('/api/jobs',json=data);assert r.status_code==200;key=r.json()['id']
    assert service.post('/api/jobs',json=data).status_code==409
    assert service.get('/api/status').json()['active_job']==key
    service.cookies.clear();join(service,'b'*43)
    assert service.get(source['url']).status_code==404
    assert service.get('/api/uploads/'+source['id']).status_code==404
    assert service.get('/api/jobs/'+key).status_code==404
    assert service.get(f'/api/jobs/{key}/files/before.png').status_code==404
    assert service.post(f'/api/jobs/{key}/cancel').status_code==404
    assert service.post('/api/jobs',json=data).status_code==404
    assert service.get('/api/status').json()['active_job'] is None
    assert service.get('/api/jobs').json()==[]
    service.cookies.clear();join(service)
    assert service.get(source['url']).status_code==200
    assert service.post(f'/api/jobs/{key}/cancel').status_code==200
    assert service.get('/api/jobs/'+key).json()['status']=='cancelled'


def test_online_exports_and_finishing_use_separate_storage(service):
    join(service);source=upload(service)
    r=service.post('/api/jobs',json={'upload_id':source['id'],'crop':[0,0,128,128],'model':'klein4'})
    key=r.json()['id'];path=online.ONLINE_DATA/'jobs'/key
    online.manager.pending.clear()
    Image.new('RGB',(128,128),(130,110,90)).save(path/'generated.png')
    settings=json.loads((path/'settings.json').read_text());write_outputs(path,settings,data_dir=online.ONLINE_DATA)
    write_json(path/'status.json',{'id':key,'status':'done','created_at':1,'error':'private local traceback'})
    assert service.post(f'/api/jobs/{key}/look',json={'color_style':'cool','color_strength':100}).status_code==200
    assert Image.open(path/'after.png').getpixel((50,50))!=(130,110,90)
    assert service.get(f'/api/jobs/{key}/files/comparison.html').status_code==200
    assert 'owner_id' not in service.get(f'/api/jobs/{key}/files/settings.json').json()
    assert 'error' not in service.get('/api/jobs/'+key).json()
    assert 'error' not in service.get('/api/jobs').json()[0]
    assert service.get(f'/api/jobs/{key}/files/worker.log').status_code==404
    assert service.post(f'/api/jobs/{key}/look',json={'amount':0}).status_code==200
    assert Image.open(path/'after.png').tobytes()==Image.open(path/'before.png').tobytes()


def test_missing_models_are_not_downloaded_by_visitors(service):
    join(service);source=upload(service)
    assert service.post('/api/jobs',json={'upload_id':source['id'],'crop':[0,0,128,128],'model':'fibo15'}).status_code==400
    assert service.post('/api/jobs',json={'upload_id':source['id'],'crop':[0,0,128,128],'model':'klein4','resolution':1024}).status_code==400
    response=service.get('/')
    assert 'data-mode="online"' in response.text and '/online.js' in response.text
    assert "frame-ancestors 'none'" in response.headers['content-security-policy']
