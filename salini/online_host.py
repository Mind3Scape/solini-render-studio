"""Owner-side supervisor: localhost service, outbound tunnel, stable GitHub Pages entry."""
import argparse
import base64
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import queue
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import threading
import time

import requests
from .config import ROOT
from .online_app import ONLINE_DATA, PAGE_URL, setup
from .app import read_json, write_json

REPOSITORY = 'Mind3Scape/solini-render-studio'
SITE_BRANCH = 'codex/site'
PORT = 18767
LABEL = 'local.salini.online'
PLIST = Path.home()/'Library/LaunchAgents'/f'{LABEL}.plist'
CF_URL = 'https://github.com/cloudflare/cloudflared/releases/download/2026.9.1/cloudflared-darwin-arm64.tgz'
CF_SHA = 'c27ab8fd0aa489449e3d201eb02f957ef460a13b613662928b1b23394bf1bcfe'
URL_RE = re.compile(r'https://[a-z0-9-]+\.trycloudflare\.com')


def tunnel_binary():
    path = ROOT/'.tools/cloudflared'
    if path.is_file():
        return path
    path.parent.mkdir(exist_ok=True)
    response = requests.get(CF_URL,timeout=(20,120))
    response.raise_for_status()
    if hashlib.sha256(response.content).hexdigest() != CF_SHA:
        raise ValueError('Проверка загруженного cloudflared не пройдена.')
    with tarfile.open(fileobj=io.BytesIO(response.content),mode='r:gz') as archive:
        item = next(m for m in archive.getmembers() if Path(m.name).name=='cloudflared' and m.isfile())
        temporary = path.with_suffix('.part')
        temporary.write_bytes(archive.extractfile(item).read())
        temporary.chmod(0o755)
        temporary.replace(path)
    return path


def github_api(endpoint, body=None):
    command = [shutil.which('gh') or '/opt/homebrew/bin/gh','api',endpoint]
    if body is not None:
        command += ['--method','PUT','--input','-']
    result = subprocess.run(command,input=json.dumps(body) if body is not None else None,
                            capture_output=True,text=True,timeout=40,env={**os.environ,'GH_PROMPT_DISABLED':'1'})
    if result.returncode:
        raise RuntimeError('GitHub не принял обновление входной ссылки. Проверьте gh auth status.')
    return json.loads(result.stdout)


def publish_connection(url):
    endpoint = f'repos/{REPOSITORY}/contents/connection.json'
    current = github_api(endpoint+'?ref='+SITE_BRANCH)
    content = json.loads(base64.b64decode(current['content']))
    if content.get('url') == url:
        return
    data = json.dumps({'url':url,'updated_at':int(time.time())},indent=2)+'\n'
    github_api(endpoint,{'branch':SITE_BRANCH,'sha':current['sha'],'message':'Update the Mac processing endpoint',
                         'content':base64.b64encode(data.encode()).decode()})
    print('Постоянная ссылка обновлена: '+PAGE_URL,flush=True)


def stop_process(process):
    if process and process.poll() is None:
        os.killpg(process.pid,signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid,signal.SIGKILL)
            process.wait(timeout=5)


def online():
    setup()
    lock = (ONLINE_DATA/'host.lock').open('a')
    try:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:
        raise RuntimeError('Веб-студия уже запущена.')
    signal.signal(signal.SIGTERM,lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT,lambda *_: sys.exit(0))
    binary = tunnel_binary()
    config = ONLINE_DATA/'cloudflared.yml'
    config.write_text('{}\n')
    server = tunnel = None
    events = queue.Queue()
    with (ONLINE_DATA/'logs/server.log').open('a') as log:
        try:
            server = subprocess.Popen([sys.executable,'-m','uvicorn','salini.online_app:app','--host','127.0.0.1',
                '--port',str(PORT),'--no-access-log','--proxy-headers','--forwarded-allow-ips','127.0.0.1'],
                cwd=ROOT,stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
            for _ in range(100):
                if server.poll() is not None:
                    raise RuntimeError('Веб-сервер не запустился. Подробности в online/logs/server.log.')
                try:
                    if requests.get(f'http://127.0.0.1:{PORT}/health',timeout=1).json().get('app')=='salini-online':
                        break
                except (requests.RequestException,ValueError):
                    pass
                time.sleep(.2)
            else:
                raise RuntimeError('Веб-сервер не отвечает.')
            tunnel = subprocess.Popen([str(binary),'tunnel','--config',str(config),'--no-autoupdate',
                '--protocol','http2','--url',f'http://127.0.0.1:{PORT}'],cwd=ROOT,stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,start_new_session=True)
            def reader():
                with (ONLINE_DATA/'logs/tunnel.log').open('a') as stream:
                    for line in tunnel.stdout:
                        stream.write(line);stream.flush()
                        if match := URL_RE.search(line):
                            events.put(match.group(0)+'/')
            threading.Thread(target=reader,daemon=True).start()
            desired = None
            retry_at = 0
            while True:
                if server.poll() is not None or tunnel.poll() is not None:
                    raise RuntimeError('Соединение остановилось. Служба запустит его заново.')
                try:
                    desired = events.get(timeout=1)
                    write_json(ONLINE_DATA/'connection.json',{'url':desired})
                    write_json(ONLINE_DATA/'running.json',{'host_pid':os.getpid(),'server_pid':server.pid,
                        'tunnel_pid':tunnel.pid,'port':PORT,'started_at':time.time()})
                    print('Защищённое соединение с веб-студией установлено.',flush=True)
                    retry_at = 0
                except queue.Empty:
                    pass
                if desired and time.time() >= retry_at:
                    try:
                        publish_connection(desired)
                        retry_at = time.time()+300
                    except (RuntimeError,subprocess.TimeoutExpired,OSError,ValueError) as exc:
                        print(str(exc),flush=True)
                        retry_at = time.time()+30
        finally:
            stop_process(tunnel)
            stop_process(server)
            (ONLINE_DATA/'running.json').unlink(missing_ok=True)
            lock.close()


def install():
    setup()
    if not shutil.which('gh'):
        raise RuntimeError('Для публикации постоянной ссылки владельцу нужен GitHub CLI: gh auth login.')
    tunnel_binary()
    PLIST.parent.mkdir(parents=True,exist_ok=True)
    environment = {'PATH':os.pathsep.join([str(Path.home()/'.local/bin'),'/opt/homebrew/bin','/usr/local/bin','/usr/bin','/bin','/usr/sbin','/sbin']),
                   'PYTHONUNBUFFERED':'1'}
    payload = {'Label':LABEL,'ProgramArguments':[str(ROOT/'.venv/bin/python'),'-m','salini.online_host','run'],
        'WorkingDirectory':str(ROOT),'RunAtLoad':True,'KeepAlive':True,'ThrottleInterval':15,
        'EnvironmentVariables':environment,'StandardOutPath':str(ONLINE_DATA/'logs/host.log'),
        'StandardErrorPath':str(ONLINE_DATA/'logs/host.log')}
    PLIST.write_bytes(plistlib.dumps(payload))
    domain = f'gui/{os.getuid()}'
    subprocess.run(['launchctl','bootout',domain+'/'+LABEL],capture_output=True)
    subprocess.run(['launchctl','enable',domain+'/'+LABEL],check=True)
    subprocess.run(['launchctl','bootstrap',domain,str(PLIST)],check=True)
    print('Веб-студия запущена и будет запускаться при входе в macOS.')
    print('Ссылка для друзей: '+PAGE_URL+'#invite='+setup()['invite'])


def stop():
    target = f'gui/{os.getuid()}/{LABEL}'
    subprocess.run(['launchctl','disable',target],check=True)
    subprocess.run(['launchctl','bootout',target],capture_output=True)
    print('Веб-студия остановлена. Локальное приложение продолжает работать.')


if __name__=='__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action',choices=['run','install','stop','link'])
    action = parser.parse_args().action
    if action=='run': online()
    elif action=='install': install()
    elif action=='stop': stop()
    else: print(PAGE_URL+'#invite='+setup()['invite'])
