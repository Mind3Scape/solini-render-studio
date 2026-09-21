import base64
import io
import math
from pathlib import Path

from PIL import Image, ImageCms, ImageOps, ImageDraw

Image.MAX_IMAGE_PIXELS = 40_000_000


def open_image(data: bytes) -> Image.Image:
    with Image.open(io.BytesIO(data)) as source:
        if source.format not in ("JPEG", "PNG", "WEBP", "TIFF"):
            raise ValueError("Поддерживаются PNG, JPEG, WebP и TIFF.")
        if source.width * source.height > 40_000_000:
            raise ValueError("Максимальный размер — 40 мегапикселей.")
        source.load()
        im = ImageOps.exif_transpose(source)
        if "A" in im.getbands():
            rgba = im.convert("RGBA")
            white = Image.new("RGBA", rgba.size, "white")
            white.alpha_composite(rgba)
            im = white.convert("RGB")
        else:
            im = im.convert("RGB")
        if source.info.get("icc_profile"):
            try:
                im = ImageCms.profileToProfile(im, ImageCms.ImageCmsProfile(io.BytesIO(source.info["icc_profile"])),
                                              ImageCms.createProfile("sRGB"), outputMode="RGB")
            except (OSError, ValueError, ImageCms.PyCMSError):
                pass
        return im.copy()


def validate_crop(box, size):
    x, y, w, h = box
    iw, ih = size
    if x < 0 or y < 0 or w < 64 or h < 64 or x + w > iw or y + h > ih:
        raise ValueError("Выделите область минимум 64 × 64 пикселя внутри изображения.")
    if max(w / h, h / w) > 4:
        raise ValueError("Область слишком узкая. Соотношение сторон должно быть не больше 4:1.")
    return (x, y, x + w, y + h)


def prepare_input(crop, max_side, alignment=16):
    # Letterbox rather than stretch: the model and original share the same camera projection.
    scale = min(max_side / max(crop.size), 1.0)
    w, h = max(64, round(crop.width * scale)), max(64, round(crop.height * scale))
    canvas_w, canvas_h = math.ceil(w / alignment) * alignment, math.ceil(h / alignment) * alignment
    resized = crop.resize((w, h), Image.Resampling.LANCZOS)
    padded = ImageOps.expand(resized, (0, 0, canvas_w - w, canvas_h - h), fill=resized.getpixel((w-1, h-1)))
    return padded, (w, h)


def composite_document(original, result, box):
    x, y, w, h = box
    if result.size != (w, h):
        raise ValueError("Размер результата не совпадает с выделенной областью.")
    document = original.copy()
    document.paste(result, (x, y))
    return document


def restore_region(original, result, box):
    """Copy exact source pixels inside the rectangle, with a narrow inward feather."""
    x, y, w, h = box
    if original.size != result.size or min(w, h) < 4 or min(x, y) < 0 or x+w > result.width or y+h > result.height:
        raise ValueError("Выделите область минимум 4 × 4 пикселя внутри изображения.")
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    feather = min(6, (min(w, h)-1)//2)
    for inset in range(feather + 1):
        draw.rectangle((inset, inset, w-1-inset, h-1-inset), fill=round(255*inset/max(feather, 1)))
    output = result.copy()
    output.paste(original.crop((x, y, x+w, y+h)), (x, y), mask)
    return output


def comparison_html(before: Path, after: Path) -> str:
    a, b = [base64.b64encode(p.read_bytes()).decode("ascii") for p in (before, after)]
    return '''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Salini · До и после</title><style>*{box-sizing:border-box}body{margin:0;background:#f5f3ee;color:#173c37;font:16px system-ui;padding:24px}
main{max-width:1100px;margin:auto}h1{font-size:24px;font-weight:500}.compare{position:relative;overflow:hidden;background:#ddd;touch-action:none;user-select:none}
img{display:block;width:100%;pointer-events:none}.after{position:absolute;inset:0;clip-path:inset(0 0 0 50%)}.line{position:absolute;top:0;bottom:0;left:50%;width:2px;background:#fff;box-shadow:0 0 4px #222}
.line:after{content:'↔';position:absolute;top:50%;left:-20px;width:42px;height:42px;background:#173c37;color:#fff;border-radius:50%;display:grid;place-items:center}
.labels{display:flex;justify-content:space-between;margin:12px 0}input{width:100%;accent-color:#173c37}p{color:#66746f;font-size:13px}</style>
<main><h1>salini <span style="font-weight:300">/ До и после</span></h1><div class="labels"><span>Исходный рендер</span><span>AI-визуализация</span></div>
<div class="compare" id="c"><img alt="Исходный рендер" src="data:image/png;base64,''' + a + '''"><div class="after" id="a"><img alt="AI-визуализация" src="data:image/png;base64,''' + b + '''"></div><div class="line" id="l"></div></div>
<label>Сравнение <input id="s" type="range" min="0" max="100" value="50" aria-label="Положение разделителя"></label>
<p>AI-визуализация. Перед использованием проверьте форму, детали и материалы изделия.</p></main>
<script>const c=document.getElementById('c'),a=document.getElementById('a'),l=document.getElementById('l'),s=document.getElementById('s');
function set(v){v=Math.max(0,Math.min(100,v));a.style.clipPath=`inset(0 0 0 ${v}%)`;l.style.left=v+'%';s.value=v}
s.oninput=()=>set(+s.value);let drag=false;function move(e){let r=c.getBoundingClientRect();set((e.clientX-r.left)/r.width*100)}
c.onpointerdown=e=>{drag=true;c.setPointerCapture(e.pointerId);move(e)};c.onpointermove=e=>{if(drag)move(e)};c.onpointerup=c.onpointercancel=()=>drag=false;</script></html>'''
