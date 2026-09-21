"""Version-pinned model catalogue. Components are shared in the HF cache."""
def part(repo, revision, filename, size, flag):
    return dict(repo=repo, revision=revision, filename=filename, size=size, flag=flag)

QWEN25 = [
    part('mradermacher/Qwen2.5-VL-7B-Instruct-GGUF','cfa2baa09946b211c107e6e104948987a64dd2c1','Qwen2.5-VL-7B-Instruct.Q4_K_M.gguf',4683072512,'--llm'),
    part('mradermacher/Qwen2.5-VL-7B-Instruct-GGUF','cfa2baa09946b211c107e6e104948987a64dd2c1','Qwen2.5-VL-7B-Instruct.mmproj-Q8_0.gguf',853119712,'--llm_vision'),
]
QWEN_VAE = part('Comfy-Org/Qwen-Image_ComfyUI','7beb7b647f04469fbe64ba8adc2bb0d7e5e9f73f','split_files/vae/qwen_image_vae.safetensors',253806246,'--vae')

EXTRA_MODELS = {
 'qwen21': dict(name='Qwen Image 2.1', description='GGUF Q4 · около 12,5 мин при 512 px на M4 Pro', tested=True, engine='cpp', license='Qwen Research License', ram_gb=24, steps=40, cfg=6.0,
  source='https://huggingface.co/Qwen/Qwen-Image-2.1', components=[
   part('leejet/Qwen-Image-2.1-GGUF','cc11433936a06e9765f7c0c0b1f0436cfd2b9856','qwen_image_2.1-Q4_K.gguf',4197494816,'--diffusion-model'),
   part('Qwen/Qwen3-VL-8B-Instruct-GGUF','f982a07559d4a2f6c8744d840bf6fccab30eea96','Qwen3VL-8B-Instruct-Q4_K_M.gguf',5027784800,'--llm'),
   part('Qwen/Qwen3-VL-8B-Instruct-GGUF','f982a07559d4a2f6c8744d840bf6fccab30eea96','mmproj-Qwen3VL-8B-Instruct-F16.gguf',1159029824,'--llm_vision'),
   part('Comfy-Org/Qwen-Image-2.1','ace0edeb3791a594ddfa36ed5f41a178a394e921','vae/qwen_image_2.1_vae_bf16.safetensors',675509688,'--vae')]),
 'qwen2511': dict(name='Qwen Image Edit 2511', description='GGUF Q4 · 30 шагов · долгий прогон, начните с 512 px', engine='cpp', license='Apache 2.0', ram_gb=24, steps=30, cfg=2.5,
  source='https://huggingface.co/Qwen/Qwen-Image-Edit-2511', args=['--flow-shift','3','--model-args','qwen_image_zero_cond_t=true'], components=[
   part('unsloth/Qwen-Image-Edit-2511-GGUF','0d33d9692b4b26212297240d87b0d4719aa4fd06','qwen-image-edit-2511-Q4_K_S.gguf',12410747488,'--diffusion-model'), *QWEN25, QWEN_VAE]),
 'firered': dict(name='FireRed Image Edit 1.1', description='Альтернативный редактор · GGUF Q4 · экспериментальный запуск', engine='cpp', license='Apache 2.0', ram_gb=24, steps=30, cfg=2.5,
  source='https://huggingface.co/FireRedTeam/FireRed-Image-Edit-1.1', args=['--flow-shift','3','--model-args','qwen_image_zero_cond_t=true'], components=[
   part('vantagewithai/FireRed-Image-Edit-1.1-GGUF','6882be7fafd594a3655d9fbcf5474ef141c34a86','FireRed-Image-Edit-1.1-Q4_K_S.gguf',12249135680,'--diffusion-model'), *QWEN25, QWEN_VAE]),
 'longcat': dict(name='LongCat Image Edit', description='GGUF Q4 · 30 шагов · экспериментальный запуск', engine='cpp', license='Apache 2.0', ram_gb=16, steps=30, cfg=4.5,
  source='https://huggingface.co/meituan-longcat/LongCat-Image-Edit', args=['--flow-shift','3'], components=[
   part('vantagewithai/LongCat-Image-Edit-GGUF','8bfeb76dd77f783aecbe99bcc32f22ee1a45e222','LongCat-Image-Edit-Q4_K_M.gguf',3867152736,'--diffusion-model'), *QWEN25,
   part('meituan-longcat/LongCat-Image-Edit','7b54ef423aa7854be7861600024be5c56ab7875a','vae/diffusion_pytorch_model.safetensors',167666902,'--vae')]),
 'fibo15': dict(name='FIBO Edit 1.5', description='MLX Q4 · около 4 мин при 512 px · на примере заметно изменила конструкцию', tested=True, engine='mlx_fibo', license='BRIA FIBO Edit 1.5 Non-Commercial', ram_gb=24, steps=30, cfg=5.0,
  source='https://huggingface.co/briaai/Fibo-Edit-1.5-base', repo='mflux-community/fibo-edit-1-5-base-mflux-q4', revision='d278e41f28949bc3da9569b040fe0de3cf3b4e04', download_gb=7.79, config='fibo_edit'),
 'flux2dev': dict(name='FLUX.2 dev', description='Большая модель · нужен Mac с 48 ГБ памяти или больше', engine='cpp', license='FLUX Non-Commercial License', ram_gb=48, steps=28, cfg=1.0,
  source='https://huggingface.co/black-forest-labs/FLUX.2-dev', args=['--guidance','4'], components=[
   part('city96/FLUX.2-dev-gguf','ade5d688ddab0d9cf4a5b01bf4321e01c115020d','flux2-dev-Q4_K_S.gguf',19299128288,'--diffusion-model'),
   part('unsloth/Mistral-Small-3.2-24B-Instruct-2506-GGUF','b750ec2299225e492f1bd27cab88a0a595fa848f','Mistral-Small-3.2-24B-Instruct-2506-Q4_K_S.gguf',13549293088,'--llm'),
   part('Comfy-Org/flux2-dev','ab9055628ea245000e610f2aa2c96f4746093546','split_files/vae/flux2-vae.safetensors',336213556,'--vae')]),
}

# Research pipelines cannot honestly be presented as interchangeable JPG editors.
UNAVAILABLE = [
 ('controlnet','Qwen 2512 + Fun ControlNet','Нужен отдельный процесс с картой контуров/глубины. Текущий движок не поддерживает этот ControlNet для Qwen.','https://huggingface.co/alibaba-pai/Qwen-Image-2512-Fun-Controlnet-Union'),
 ('supir','SUPIR','Официальный процесс требует CUDA и отдельной среды. Прямого проверенного запуска на Apple GPU здесь нет.','https://github.com/Fanghua-Yu/SUPIR'),
 ('harmonizer','NVIDIA DiffusionHarmonizer','Исследовательский процесс для сцен; не готовый редактор произвольного JPG на Mac.','https://github.com/NVIDIA/harmonizer'),
 ('diffusionrenderer','NVIDIA DiffusionRenderer','Нужны восстановление свойств сцены и отдельный процесс нейрорендеринга.','https://github.com/nv-tlabs/diffusion-renderer'),
 ('regen','REGEN','Предобученные модели ориентированы на игры и автомобильные сцены; адаптер для этой программы не реализован.','https://github.com/stefanos50/REGEN'),
 ('hunyuan','HunyuanImage 3.0 Instruct','Очень большая модель; официальный запуск требует серверных NVIDIA GPU.','https://github.com/Tencent-Hunyuan/HunyuanImage-3.0'),
 ('dlss','DLSS 5 / Visual Enhancer','Для DLSS нужны Windows и совместимая NVIDIA RTX. На Mac он не запускается.','https://github.com/Merserk/dlss5-visual-enhancer'),
]
for key,name,reason,source in UNAVAILABLE:
    EXTRA_MODELS[key] = dict(name=name,description=reason,reason=reason,source=source,engine=None,license='См. страницу проекта',ram_gb=0,steps=0,download_gb=0)
EXTRA_MODELS['realesrgan'] = dict(name='Real-ESRGAN x4plus', description='Восстановление деталей · без генерации нового освещения · размер сохраняется', tested=True,
    engine='cpp', task='upscale', license='BSD-3-Clause', ram_gb=8, steps=1,
    source='https://github.com/xinntao/Real-ESRGAN', components=[dict(
        url='https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth',
        filename='RealESRGAN_x4plus.pth', size=67040989, flag='--upscale-model',
        sha256='4fa0d38905f75ac06eb49a7951b426670021be3018265fd191d2125df9d682f1')])
for spec in EXTRA_MODELS.values():
    if 'components' in spec:
        spec['download_gb'] = round(sum(p['size'] for p in spec['components'])/1e9,2)
        spec['revision'] = '|'.join(p.get('revision',p.get('sha256'))+':'+p['filename'] for p in spec['components'])
