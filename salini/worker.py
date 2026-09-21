"""One isolated process per job. Cancellation also terminates native engine children."""
import argparse
import json
import os
import shutil
import time
import hashlib
from pathlib import Path
from .config import DATA, MODELS, build_prompt, ensure_dirs, model_blocker


def event(stage, message, **extra):
    print('SALINI_EVENT '+json.dumps(dict(stage=stage,message=message,**extra),ensure_ascii=False),flush=True)


def download_model(key):
    from huggingface_hub import snapshot_download, hf_hub_download
    ensure_dirs()
    spec=MODELS[key]
    if reason:=model_blocker(key): raise ValueError(reason)
    marker=DATA/'models'/f'{key}.json'
    if marker.exists():
        try:
            cached=json.loads(marker.read_text())
            if cached.get('revision')==spec['revision']:
                if cached.get('files') and all(Path(p).is_file() for p in cached['files'].values()): return cached['files']
                if cached.get('path') and Path(cached['path']).is_dir(): return cached['path']
        except (OSError, ValueError): pass
    cache=DATA/'models/cache'
    needed=int(spec['download_gb']*1e9)
    if spec.get('components'):
        from huggingface_hub import try_to_load_from_cache
        needed=sum(p['size'] for p in spec['components'] if 'url' in p or not isinstance(try_to_load_from_cache(p['repo'],p['filename'],revision=p['revision'],cache_dir=cache),str))
    if shutil.disk_usage(DATA).free < needed+2*1024**3:
        raise ValueError(f'Для загрузки нужно ещё примерно {needed/1e9:.1f} ГБ и 2 ГБ свободного запаса на диске.')
    event('download',f"Загрузка {spec['name']} · до {spec['download_gb']} ГБ. Уже загруженные компоненты используются повторно.")
    if spec.get('components'):
        files={}
        for i,p in enumerate(spec['components']):
            event('download',f"Компонент {i+1}/{len(spec['components'])}: {Path(p['filename']).name} · {p['size']/1e9:.2f} ГБ")
            if 'url' in p:
                import requests
                target=DATA/'models'/p['filename']
                if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest()!=p['sha256']:
                    response=requests.get(p['url'],timeout=(20,120));response.raise_for_status()
                    if hashlib.sha256(response.content).hexdigest()!=p['sha256']:
                        raise ValueError('Контрольная сумма модели не совпала.')
                    target.write_bytes(response.content)
                files[p['flag']]=str(target)
            else:
                files[p['flag']]=hf_hub_download(p['repo'],p['filename'],revision=p['revision'],cache_dir=cache)
        info={'files':files,'revision':spec['revision']}
        result=files
    else:
        result=snapshot_download(spec['repo'],revision=spec['revision'],cache_dir=cache,max_workers=3)
        info={'path':result,'revision':spec['revision']}
    tmp=marker.with_suffix('.tmp');tmp.write_text(json.dumps(info));tmp.replace(marker)
    return result


def generate_mlx(spec, path, prepared_path, prepared, config, prompt):
    import mlx.core as mx
    from mflux.models.common.config import ModelConfig
    mx.set_cache_limit(512*1024*1024)
    if spec['engine']=='mlx_fibo':
        from mflux.models.fibo.variants.edit.fibo_edit import FIBOEdit
        model=FIBOEdit(model_path=path,model_config=ModelConfig.fibo_edit())
        kwargs={'image_path':str(prepared_path),'guidance':spec['cfg']}
        prompt=json.dumps({'edit_instruction':prompt})
    else:
        from mflux.models.flux2.variants import Flux2KleinEdit
        model=Flux2KleinEdit(model_path=path,model_config=getattr(ModelConfig,spec['config'])())
        kwargs={'image_paths':[str(prepared_path)]}
    class Progress:
        def call_before_loop(self,**kwargs): event('rendering','Создание изображения…',step=0,total=spec['steps'])
        def call_in_loop(self,t,latents,**kwargs):
            mx.eval(latents)
            event('rendering',f"Обработка · шаг {int(t)+1} из {spec['steps']}",step=int(t)+1,total=spec['steps'])
        def call_after_loop(self,**kwargs): event('decoding','Проявление изображения…')
    model.callbacks.register(Progress())
    event('encoding','Чтение изображения и материалов…')
    generated=model.generate_image(seed=config['seed'],prompt=prompt,num_inference_steps=spec['steps'],
                                   width=prepared.width,height=prepared.height,**kwargs)
    return generated.image,round(mx.get_peak_memory()/1024**3,2)


def run(job_dir):
    from PIL import Image
    from .imaging import prepare_input
    from .outputs import write_outputs
    config=json.loads((job_dir/'settings.json').read_text())
    started=time.monotonic();spec=MODELS[config['model']]
    path=download_model(config['model'])
    event('loading','Модель загружается в память Mac…')
    crop=Image.open(job_dir/'before.png').convert('RGB')
    prepared,unpadded=prepare_input(crop,config['resolution'],alignment=32 if spec['engine']=='cpp' else 16)
    prepared_path=job_dir/'model-input.png';prepared.save(prepared_path)
    prompt=build_prompt(config['mode'],config['note'])
    if spec['engine']=='cpp':
        from .cpp_engine import generate
        image,peak=generate(spec,path,prepared_path,job_dir,prompt,prepared.width,prepared.height,config['seed'],event)
    else:
        image,peak=generate_mlx(spec,path,prepared_path,prepared,config,prompt)
    event('export','Сохранение результата и сравнения…')
    if spec.get('task') == 'upscale':
        image=image.resize(prepared.size,Image.Resampling.LANCZOS)
    result=image.crop((0,0,*unpadded)).resize(crop.size,Image.Resampling.LANCZOS)
    result.save(job_dir/'generated.png')
    config.update(prompt=prompt,model_repo=spec.get('repo',spec.get('source')),model_revision=spec['revision'],
                  engine=spec['engine'],engine_version='c678dfe' if spec['engine']=='cpp' else '0.19.2',steps=spec['steps'],
                  processing_size=list(prepared.size),elapsed_seconds=round(time.monotonic()-started,1),peak_memory_gb=peak)
    write_outputs(job_dir,config)
    (job_dir/'settings.json').write_text(json.dumps(config,ensure_ascii=False,indent=2))
    event('done','Готово. Проверьте детали изделия в сравнении.',elapsed=config['elapsed_seconds'],peak_memory_gb=peak)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--job',type=Path);parser.add_argument('--download',choices=list(MODELS))
    args=parser.parse_args();os.environ['HF_HUB_DISABLE_TELEMETRY']='1'
    if args.download: download_model(args.download)
    elif args.job: run(args.job)
