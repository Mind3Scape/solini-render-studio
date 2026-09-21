import io
import pytest
from PIL import Image, ImageChops
from salini.imaging import open_image, validate_crop, prepare_input, composite_document, restore_region, comparison_html


def test_upload_orients_and_flattens():
    im = Image.new('RGBA', (100, 80), (0, 0, 0, 0))
    buf = io.BytesIO(); im.save(buf, format='PNG')
    assert open_image(buf.getvalue()).getpixel((0, 0)) == (255, 255, 255)
    im = Image.new('RGB', (100, 80))
    exif = Image.Exif(); exif[274] = 6
    buf = io.BytesIO(); im.save(buf, format='JPEG', exif=exif)
    assert open_image(buf.getvalue()).size == (80, 100)


@pytest.mark.parametrize('box', [(-1,0,100,100),(0,0,63,100),(99,101,100,100),(0,0,401,64)])
def test_invalid_crop(box):
    with pytest.raises(ValueError): validate_crop(box, (500, 200))


def test_preparation_and_document_protection():
    source = Image.new('RGB', (1200, 900), 'blue')
    box = (60, 100, 887, 633)
    crop = source.crop(validate_crop(box, source.size))
    prepared, unpadded = prepare_input(crop, 768)
    assert prepared.width % 16 == prepared.height % 16 == 0
    assert unpadded == (768, 548)
    changed = composite_document(source, Image.new('RGB', crop.size, 'red'), box)
    assert ImageChops.difference(source, changed).getbbox() == (60,100,947,733)
    assert source.getpixel((60,100)) == (0,0,255)


def test_restore_exact_interior_and_unchanged_outside():
    original = Image.new('RGB', (120,100), 'white')
    after = Image.new('RGB', original.size, 'black')
    restored = restore_region(original, after, (30,20,40,30))
    assert restored.getpixel((45,35)) == (255,255,255)
    assert restored.getpixel((0,0)) == (0,0,0)
    assert 0 < restored.getpixel((32,22))[0] < 255
    with pytest.raises(ValueError): restore_region(original, after, (119,0,5,5))


def test_share_is_standalone(tmp_path):
    before, after = tmp_path/'before.png', tmp_path/'after.png'
    Image.new('RGB', (64,64), 'white').save(before)
    Image.new('RGB', (64,64), 'black').save(after)
    html = comparison_html(before, after)
    assert html.count('data:image/png;base64,') == 2
    assert 'http://' not in html and 'https://' not in html
    assert 'onpointermove' in html and 'type="range"' in html
