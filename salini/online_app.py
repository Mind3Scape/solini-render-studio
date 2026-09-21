"""An isolated, invitation-only web service; never serves desktop uploads or history."""
import asyncio
from collections import deque
from contextlib import asynccontextmanager
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import shutil
import threading
import time
import uuid
from urllib.parse import urlparse

from fastapi import FastAPI, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel, Field

from .app import ID_RE, JobManager, RenderRequest, LookRequest, RestoreRequest, read_json, write_json
from .config import DATA, ROOT, MODELS, LIGHTS, model_ready, model_blocker, memory_gb
from .imaging import open_image, validate_crop
from .looks import LOOKS
from .outputs import write_outputs

ONLINE_DATA = Path(os.environ.get('SALINI_ONLINE_DATA', DATA / 'online'))
PAGE_URL = 'https://mind3scape.github.io/solini-render-studio/'
COOKIE = 'salini_visitor'
MAX_BYTES = 20 * 1024**2
MAX_QUEUE = 6


def setup():
    ONLINE_DATA.mkdir(parents=True, exist_ok=True, mode=0o700)
    for name in ('uploads', 'jobs', 'logs'):
        (ONLINE_DATA / name).mkdir(exist_ok=True)
    path = ONLINE_DATA / 'secrets.json'
    if not path.exists():
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as out:
            json.dump({'invite': secrets.token_urlsafe(32), 'signing': secrets.token_hex(32)}, out)
    return read_json(path)


def sign_session(owner, expires):
    message = f'{owner}.{expires}'
    digest = hmac.new(setup()['signing'].encode(), message.encode(), hashlib.sha256).hexdigest()
    return f'{message}.{digest}'


def session_owner(request):
    try:
        owner, expires, signature = request.cookies.get(COOKIE, '').split('.')
        if not ID_RE.fullmatch(owner) or int(expires) < time.time():
            return None
        expected = sign_session(owner, int(expires)).rsplit('.', 1)[1]
        return owner if hmac.compare_digest(signature, expected) else None
    except (ValueError, TypeError):
        return None


def public_host():
    try:
        return urlparse(read_json(ONLINE_DATA / 'connection.json')['url']).hostname
    except (OSError, ValueError, KeyError):
        return None


def owned_dir(kind, key, owner):
    if not ID_RE.fullmatch(key):
        raise HTTPException(404, 'Файл не найден.')
    path = ONLINE_DATA / kind / key
    try:
        info = read_json(path / ('meta.json' if kind == 'uploads' else 'settings.json'))
        if info.get('owner_id') != owner:
            raise HTTPException(404, 'Файл не найден.')
    except (OSError, ValueError):
        raise HTTPException(404, 'Файл не найден.')
    return path


class QueueManager(JobManager):
    def __init__(self):
        super().__init__(ONLINE_DATA)
        self.pending = deque()
        self.condition = threading.Condition(self.lock)
        self.stopping = False
        self.pump_thread = None

    def begin(self):
        self.pump_thread = threading.Thread(target=self.pump, daemon=True)
        self.pump_thread.start()

    def admit(self, owner):
        active = list(self.pending) + ([self.active] if self.active else [])
        if len(active) >= MAX_QUEUE:
            raise HTTPException(429, 'Очередь заполнена. Попробуйте после завершения текущих задач.')
        if any(read_json(self.data_dir/'jobs'/key/'settings.json').get('owner_id') == owner for key in active):
            raise HTTPException(409, 'Ваша предыдущая обработка ещё выполняется или ожидает в очереди.')
        recent = [p for p in (self.data_dir/'jobs').glob('*/settings.json')
                  if p.stat().st_mtime > time.time()-3600 and read_json(p).get('owner_id') == owner]
        if len(recent) >= 12:
            raise HTTPException(429, 'Достигнут лимит: 12 обработок в час. Попробуйте позже.')

    def enqueue(self, key):
        with self.condition:
            self.pending.append(key)
            self.condition.notify_all()

    def pump(self):
        while True:
            with self.condition:
                self.condition.wait_for(lambda: self.stopping or self.pending)
                if self.stopping:
                    return
                key = self.pending.popleft()
                self.active = key
            super().run(key)

    def cancel(self, key):
        with self.condition:
            if key in self.pending:
                self.pending.remove(key)
                self.update(key, status='cancelled', message='Обработка отменена.')
            else:
                super().cancel(key)

    def stop(self):
        with self.condition:
            self.stopping = True
            for key in list(self.pending):
                self.cancel(key)
            if self.active:
                super().cancel(self.active)
            self.condition.notify_all()
        # Let cancellation terminate native children before the server exits.
        if self.pump_thread:
            self.pump_thread.join(timeout=7)


manager = QueueManager()


@asynccontextmanager
async def lifespan(app):
    global manager
    setup()
    manager = QueueManager()
    for path in (ONLINE_DATA/'jobs').glob('*/status.json'):
        item = read_json(path)
        if item.get('status') in ('queued', 'running'):
            item.update(status='failed', message='Сервер был перезапущен. Повторите обработку.')
            write_json(path, item)
    manager.begin()
    yield
    manager.stop()


app = FastAPI(title='Salini Render Studio Online', lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)


@app.middleware('http')
async def access(request: Request, call_next):
    if request.url.hostname not in ('127.0.0.1', 'localhost', 'testserver', public_host()):
        return JSONResponse({'detail': 'Неверный адрес сайта.'}, status_code=403)
    if request.method not in ('GET', 'HEAD', 'OPTIONS'):
        origin = request.headers.get('origin')
        if origin and urlparse(origin).netloc != request.headers.get('host'):
            return JSONResponse({'detail': 'Откройте студию по ссылке-приглашению.'}, status_code=403)
    try:
        if int(request.headers.get('content-length', 0)) > MAX_BYTES + 1024**2:
            return JSONResponse({'detail': 'Файл должен быть меньше 20 МБ.'}, status_code=413)
    except ValueError:
        return JSONResponse({'detail': 'Неверный размер запроса.'}, status_code=400)
    request.state.owner = session_owner(request)
    if request.url.path.startswith('/api/') and request.url.path != '/api/session' and not request.state.owner:
        return JSONResponse({'detail': 'Нужна ссылка-приглашение от владельца студии.'}, status_code=401)
    response = await call_next(request)
    response.headers.update({'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
        'Referrer-Policy': 'no-referrer', 'X-Frame-Options': 'DENY',
        'Content-Security-Policy': "default-src 'self'; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"})
    if request.url.path == '/health' and request.headers.get('origin') == urlparse(PAGE_URL).scheme+'://'+urlparse(PAGE_URL).netloc:
        response.headers['Access-Control-Allow-Origin'] = request.headers['origin']
        response.headers['Vary'] = 'Origin'
    return response


@app.get('/health')
def health():
    return {'app': 'salini-online', 'online': True}


class Invitation(BaseModel):
    invite: str = Field(max_length=100)
    visitor: str = Field(default='',max_length=100,pattern=r'^[A-Za-z0-9_-]*$')


@app.post('/api/session')
def join(body: Invitation, request: Request):
    if not hmac.compare_digest(body.invite, setup()['invite']):
        raise HTTPException(403, 'Код приглашения неверен. Попросите владельца прислать полную ссылку.')
    if body.visitor and len(body.visitor) < 40:
        raise HTTPException(400,'Неверное приглашение.')
    owner = (hmac.new(setup()['signing'].encode(),body.visitor.encode(),hashlib.sha256).hexdigest()[:32]
             if body.visitor else session_owner(request) or uuid.uuid4().hex)
    response = JSONResponse({'ok': True})
    response.set_cookie(COOKIE, sign_session(owner, int(time.time())+7*86400),
                        secure=True, httponly=True, samesite='strict', max_age=7*86400)
    return response


@app.get('/api/session')
def session(request: Request):
    if not request.state.owner:
        raise HTTPException(401, 'Нужна ссылка-приглашение.')
    return {'ok': True, 'share_url': PAGE_URL+'#invite='+setup()['invite']}


@app.get('/api/status')
def status(request: Request):
    models = []
    for key, spec in MODELS.items():
        ready = model_ready(key)
        blocker = model_blocker(key) or ('' if ready else 'Эта модель пока не установлена на Mac владельца сайта.')
        models.append({'key': key, **{k:spec.get(k) for k in ('name','description','engine','task','ram_gb','download_gb','source','tested')},
                       'ready': ready, 'blocker': blocker})
    own = None
    with manager.lock:
        for key in list(manager.pending) + ([manager.active] if manager.active else []):
            if read_json(ONLINE_DATA/'jobs'/key/'settings.json').get('owner_id') == request.state.owner:
                own = key
                break
    return {'app': 'salini-render-studio', 'version': '1.2.0', 'mode': 'online', 'models': models,
            'looks': LOOKS, 'lights': {k:v[0] for k,v in LIGHTS.items()}, 'supported': True,
            'memory_gb': memory_gb(), 'recommended_model': 'klein9' if memory_gb() >= 24 else 'klein4',
            'active_job': own}


def public_settings(settings):
    return {k:v for k,v in settings.items() if k != 'owner_id'}


@app.post('/api/uploads')
async def upload(request: Request, file: UploadFile):
    body = bytearray()
    while chunk := await file.read(1024**2):
        body.extend(chunk)
        if len(body) > MAX_BYTES:
            raise HTTPException(413, 'Файл должен быть меньше 20 МБ.')
    try:
        im = await asyncio.to_thread(open_image, bytes(body))
        if im.width*im.height > 20_000_000:
            raise ValueError('Для сайта уменьшите изображение до 20 мегапикселей.')
    except (ValueError, OSError, UnidentifiedImageError, Image.DecompressionBombError) as exc:
        raise HTTPException(400, str(exc) if isinstance(exc, ValueError) else 'Не удалось прочитать изображение.')
    with manager.lock:
        if shutil.disk_usage(ONLINE_DATA).free < 5*1024**3:
            raise HTTPException(503, 'На сервере мало свободного места. Сообщите владельцу.')
        total = sum(p.stat().st_size for p in ONLINE_DATA.rglob('*.png'))
        if total > 2*1024**3:
            raise HTTPException(503, 'Хранилище сайта заполнено. Сообщите владельцу.')
        own = [p for p in (ONLINE_DATA/'uploads').glob('*/meta.json') if read_json(p).get('owner_id') == request.state.owner]
        if len(own) >= 30:
            raise HTTPException(429, 'Достигнут лимит 30 исходных изображений. Сообщите владельцу.')
        key = uuid.uuid4().hex
        path = ONLINE_DATA/'uploads'/key
        path.mkdir()
        im.save(path/'original.png')
        meta = {'id': key, 'owner_id': request.state.owner, 'name': Path(file.filename or 'Изображение').name,
                'width': im.width, 'height': im.height, 'url': f'/api/uploads/{key}/image'}
        write_json(path/'meta.json', meta)
    return public_settings(meta)


@app.get('/api/uploads/{key}/image')
def upload_image(key: str, request: Request):
    return FileResponse(owned_dir('uploads',key,request.state.owner)/'original.png', media_type='image/png')


@app.get('/api/uploads/{key}')
def upload_meta(key: str, request: Request):
    return public_settings(read_json(owned_dir('uploads',key,request.state.owner)/'meta.json'))


@app.post('/api/jobs')
def create_job(body: RenderRequest, request: Request):
    if body.model not in MODELS or body.mode not in LIGHTS:
        raise HTTPException(400, 'Неизвестная модель или вариант света.')
    if reason := model_blocker(body.model):
        raise HTTPException(400, reason)
    if not model_ready(body.model):
        raise HTTPException(400, 'Эта модель пока не установлена владельцем сайта.')
    if body.resolution > 768:
        raise HTTPException(400, 'В веб-версии доступна обработка до 768 px.')
    source = owned_dir('uploads',body.upload_id,request.state.owner)
    im = Image.open(source/'original.png').convert('RGB')
    try:
        box = validate_crop(body.crop, im.size)
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    with manager.lock:
        manager.admit(request.state.owner)
        key = uuid.uuid4().hex
        path = ONLINE_DATA/'jobs'/key
        path.mkdir()
        im.crop(box).save(path/'before.png')
        settings = body.model_dump()
        settings.update(owner_id=request.state.owner, source_name=read_json(source/'meta.json')['name'])
        write_json(path/'settings.json',settings)
        write_json(path/'status.json',{'id':key,'status':'queued','stage':'queued','created_at':time.time(),
                                     'model':body.model,'message':'В очереди на Mac владельца…'})
        manager.enqueue(key)
    return {'id':key}


@app.get('/api/jobs')
def jobs(request: Request):
    items = []
    for path in (ONLINE_DATA/'jobs').glob('*/settings.json'):
        settings = read_json(path)
        if settings.get('owner_id') == request.state.owner:
            status = read_json(path.parent/'status.json')
            if status['status'] == 'done':
                items.append({k:v for k,v in {**status,'name':settings['source_name']}.items() if k!='error'})
    return sorted(items,key=lambda s:s['created_at'],reverse=True)[:20]


@app.get('/api/jobs/{key}')
def job(key: str, request: Request):
    path = owned_dir('jobs',key,request.state.owner)
    status = read_json(path/'status.json')
    status.pop('error',None)
    with manager.lock:
        if key in manager.pending:
            position = list(manager.pending).index(key)+1
            status['message'] = f'В очереди · позиция {position}. Mac обрабатывает предыдущие запросы.'
    return {**status,'settings':public_settings(read_json(path/'settings.json'))}


@app.post('/api/jobs/{key}/cancel')
def cancel(key: str, request: Request):
    owned_dir('jobs',key,request.state.owner)
    manager.cancel(key)
    return {'ok':True}


def completed(key,owner):
    path = owned_dir('jobs',key,owner)
    if read_json(path/'status.json')['status'] != 'done':
        raise HTTPException(409,'Дождитесь завершения обработки.')
    return path, read_json(path/'settings.json')


@app.post('/api/jobs/{key}/look')
def look(key: str, body: LookRequest, request: Request):
    with manager.lock:
        path,settings = completed(key,request.state.owner)
        settings.update(body.model_dump())
        write_outputs(path,settings,data_dir=ONLINE_DATA)
        write_json(path/'settings.json',settings)
    return {'ok':True,'settings':public_settings(settings)}


@app.post('/api/jobs/{key}/restore')
def restore(key: str, body: RestoreRequest, request: Request):
    with manager.lock:
        path,settings = completed(key,request.state.owner)
        if body.reset:
            settings['restored_regions'] = []
        elif body.box:
            x,y,w,h = body.box
            iw,ih = Image.open(path/'before.png').size
            if min(x,y)<0 or min(w,h)<4 or x+w>iw or y+h>ih:
                raise HTTPException(400,'Выделите участок внутри изображения, минимум 4 × 4 пикселя.')
            settings.setdefault('restored_regions',[]).append(list(body.box))
        else:
            raise HTTPException(400,'Выделите деталь для восстановления.')
        write_outputs(path,settings,data_dir=ONLINE_DATA)
        write_json(path/'settings.json',settings)
    return {'ok':True,'restored_regions':settings['restored_regions']}


@app.get('/api/jobs/{key}/files/{name}')
def result_file(key: str, name: str, request: Request, download: bool=False):
    if name not in ('before.png','after.png','document.png','comparison.html','settings.json'):
        raise HTTPException(404)
    path = owned_dir('jobs',key,request.state.owner)
    if name == 'settings.json':
        return JSONResponse(public_settings(read_json(path/name)),headers={'Content-Disposition':f'attachment; filename="salini-{key[:8]}-settings.json"'})
    if not (path/name).is_file():
        raise HTTPException(404,'Результат ещё не готов.')
    return FileResponse(path/name, filename=f'salini-{key[:8]}-{name}' if download else None)


@app.get('/')
def index():
    html = (ROOT/'web/index.html').read_text()
    html = html.replace('<html lang="ru">','<html lang="ru" data-mode="online">')
    html = html.replace('На вашем Mac','На Mac владельца').replace('Изображения остаются на этом Mac','Изображения отправляются на Mac владельца сайта')
    html = html.replace('Сохранены на этом Mac','Ваша история на сервере').replace('до 40 МБ','до 20 МБ')
    html = html.replace('<script src="/app.js">','<script src="/online.js"></script><script src="/app.js">')
    html = html.replace('AI-визуализация · 1.2','Веб-студия · 1.2')
    return HTMLResponse(html)


app.mount('/',StaticFiles(directory=ROOT/'web'),name='assets')
