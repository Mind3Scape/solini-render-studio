import numpy as np
import pytest
from PIL import Image, ImageChops
from salini.looks import LOOKS, apply_look, finish_image
from salini.config import LIGHTS, build_prompt, MODELS
from salini.cpp_engine import build_command


def sample():
    rng=np.random.default_rng(42)
    return Image.fromarray(rng.integers(30,225,size=(60,80,3),dtype=np.uint8))


def test_zero_and_neutral_preserve_exact_pixels():
    image=sample()
    for style in LOOKS:
        assert ImageChops.difference(apply_look(image,style,0),image).getbbox() is None
    assert ImageChops.difference(apply_look(image,'neutral',100),image).getbbox() is None


def test_styles_differ_and_strength_has_numeric_effect():
    image=sample();source=np.array(image,dtype=float)
    outputs=[]
    for style in LOOKS:
        out=apply_look(image,style,100);outputs.append(out.tobytes())
        half=np.array(apply_look(image,style,50),dtype=float)
        assert np.abs(half-(source+np.array(out))/2).max()<=1
    assert len(set(outputs))==len(LOOKS)
    warm=np.array(apply_look(image,'warm',100),dtype=float).mean((0,1))
    cool=np.array(apply_look(image,'cool',100),dtype=float).mean((0,1))
    assert warm[0]>cool[0] and warm[2]<cool[2]


def test_amount_and_restored_detail_are_preserved():
    before=sample();after=Image.new('RGB',before.size,'black')
    assert finish_image(before,after,'warm',100,0).tobytes()==before.tobytes()
    fixed=finish_image(before,after,'cool',100,100,[(20,20,30,30)])
    assert fixed.getpixel((35,35))==before.getpixel((35,35))
    assert fixed.getpixel((1,1))!=before.getpixel((1,1))
    with pytest.raises(ValueError):apply_look(after,'unknown')


def test_lighting_prompts_are_distinct():
    assert len({build_prompt(k) for k in LIGHTS})==6
    assert '3000K' in build_prompt('warm')
    assert 'deep but detailed shadows' in build_prompt('dramatic')


def test_cpp_edit_command_uses_reference_and_version_specific_option():
    spec=MODELS['qwen2511']
    cmd=build_command('/bin/sd',spec,{'--diffusion-model':'/model.gguf'},'/input image.png','/out.png','quote " and $word',512,384,42,30)
    assert cmd[cmd.index('-r')+1]=='/input image.png'
    assert cmd[cmd.index('-p')+1]=='quote " and $word'
    assert 'qwen_image_zero_cond_t=true' in cmd
    assert '--vae-tiling' in cmd
    for key in ('qwen21','qwen2511','firered','longcat','fibo15','flux2dev'):
        assert MODELS[key]['engine'] and MODELS[key]['revision']


def test_upscaler_uses_image_input_without_diffusion_prompt():
    cmd=build_command('/bin/sd',MODELS['realesrgan'],{'--upscale-model':'/weights.pth'},'/in.png','/out.png','unused',512,384,42,1)
    assert cmd[cmd.index('--mode')+1]=='upscale'
    assert cmd[cmd.index('-i')+1]=='/in.png'
    assert '-p' not in cmd and '-r' not in cmd
