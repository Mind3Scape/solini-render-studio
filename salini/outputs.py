import shutil
from PIL import Image
from . import config
from .imaging import composite_document, comparison_html
from .looks import finish_image


def write_outputs(path, settings):
    raw = path/'generated.png'
    if not raw.exists():
        shutil.copy2(path/'after.png', raw)  # Migrate results from version 1.0 only once.
    before = Image.open(path/'before.png').convert('RGB')
    generated = Image.open(raw).convert('RGB')
    result = finish_image(before, generated, settings.get('color_style','neutral'),
                          settings.get('color_strength',60), settings.get('amount',100),
                          settings.get('restored_regions',[]))
    result.save(path/'after.tmp.png'); (path/'after.tmp.png').replace(path/'after.png')
    original = Image.open(config.DATA/'uploads'/settings['upload_id']/'original.png').convert('RGB')
    composite_document(original, result, settings['crop']).save(path/'document.tmp.png')
    (path/'document.tmp.png').replace(path/'document.png')
    (path/'comparison.tmp.html').write_text(comparison_html(path/'before.png',path/'after.png'))
    (path/'comparison.tmp.html').replace(path/'comparison.html')
