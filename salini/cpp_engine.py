"""Pinned upstream Apple Silicon runtime; no shell interpolation of image prompts."""
import hashlib
import io
import os
from pathlib import Path
import re
import subprocess
import zipfile
import requests
from .config import DATA

RUNTIME_URL = 'https://github.com/leejet/stable-diffusion.cpp/releases/download/master-889-c678dfe/sd-master-c678dfe-bin-Darwin-macOS-26.6.2-arm64.zip'
RUNTIME_SHA = '935f47067941d3fe095d80751f04c59cd8105e297177b98d559d9be1d9e7cfd8'
RUNTIME_VERSION = 'c678dfe'


def ensure_runtime(event):
    folder = DATA/'engines'/RUNTIME_VERSION
    exe = folder/'sd-cli'
    if exe.is_file() and (folder/'libstable-diffusion.dylib').is_file() and (folder/'verified').is_file():
        return exe
    event('download','Загрузка движка для Apple Silicon · 34 МБ…')
    response = requests.get(RUNTIME_URL,timeout=(20,120)); response.raise_for_status()
    if hashlib.sha256(response.content).hexdigest() != RUNTIME_SHA:
        raise ValueError('Контрольная сумма движка не совпала. Повторите загрузку.')
    folder.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
        for name in ['sd-cli','libstable-diffusion.dylib','stable-diffusion.cpp.txt','ggml.txt']:
            with (folder/name).open('wb') as out:
                out.write(archive.read(name))
    exe.chmod(0o755)
    (folder/'verified').write_text(RUNTIME_SHA)
    return exe


def build_command(exe, spec, files, image_path, output, prompt, width, height, seed, steps):
    command = [str(exe)]
    for flag,path in files.items(): command.extend([flag,str(path)])
    if spec.get('task') == 'upscale':
        return command + ['--mode','upscale','-i',str(image_path),'-o',str(output),'--upscale-tile-size','128']
    command += ['-r',str(image_path),'-p',prompt,'-W',str(width),'-H',str(height),
                '--seed',str(seed),'--steps',str(steps),'--cfg-scale',str(spec.get('cfg',1)),
                '--sampling-method','euler','--offload-to-cpu','--mmap','--diffusion-fa',
                '--vae-tiling','-o',str(output)]
    return command + spec.get('args',[])


def generate(spec, files, image_path, job_dir, prompt, width, height, seed, event):
    from PIL import Image
    exe = ensure_runtime(event)
    output = job_dir/'engine-output.png'
    command = build_command(exe,spec,files,image_path,output,prompt,width,height,seed,spec['steps'])
    event('loading','Загрузка модели и кодирование исходного изображения…')
    process = subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1,
                               env={**os.environ,'NO_COLOR':'1'})
    for line in process.stdout:
        print(line, end='',flush=True)
        match = re.search(r'\b(\d+)\s*/\s*(\d+)\b',line)
        if match and int(match[2]) == spec['steps']:
            event('rendering',f'Обработка · шаг {match[1]} из {match[2]}',step=int(match[1]),total=int(match[2]))
        elif match and spec.get('task') == 'upscale' and 's/it' in line:
            event('rendering',f'Детализация · участок {match[1]} из {match[2]}',step=int(match[1]),total=int(match[2]))
    if process.wait() != 0 or not output.exists():
        raise RuntimeError('Движок не создал изображение. Подробности выше в журнале.')
    return Image.open(output).convert('RGB'), None
