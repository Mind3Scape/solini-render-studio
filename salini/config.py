import os
import platform
import subprocess
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = Path(os.environ.get("SALINI_DATA_DIR", Path.home() / "Library/Application Support/Salini Render Studio"))
MODELS = {
    "klein4": {
        "name": "FLUX.2 Klein 4B",
        "description": "Быстрый · от 16 ГБ памяти",
        "repo": "mflux-community/flux2-klein-4b-mflux-q4",
        "revision": "77090341902cb5f9217f05c664ff604236ca18cc",
        "config": "flux2_klein_4b",
        "download_gb": 4.62,
        "license": "Apache 2.0",
    },
    "klein9": {
        "name": "FLUX.2 Klein 9B KV",
        "description": "Детальный · рекомендуется от 24 ГБ",
        "repo": "mflux-community/flux2-klein-9b-kv-mflux-q4",
        "revision": "aab0f62fa58db4e55f993c2d1bf2586686b97a1e",
        "config": "flux2_klein_9b_kv",
        "download_gb": 9.54,
        "license": "FLUX Non-Commercial License",
    },
}
for _key, _spec in MODELS.items():
    _spec.update(engine="mlx_klein", ram_gb=16 if _key == "klein4" else 24, steps=4,
                 source="https://huggingface.co/" + _spec["repo"], tested=True)
from .catalog import EXTRA_MODELS
MODELS.update(EXTRA_MODELS)

LIGHTS = {
    "gentle": ("Бережный", "Keep the existing light direction, brightness and soft shadows. Refine the surface response subtly."),
    "studio": ("Студийный", "Use a large studio key light from the upper right and a weak fill on the left. Create shaped specular highlights, defined edges and soft contact shadows."),
    "daylight": ("Дневной", "Relight with a broad cool daylight window from the left. Create a natural brightness gradient across the product and soft shadows toward the right."),
    "warm": ("Тёплый свет", "Relight with warm 3000K side lighting and gentle amber highlights, with warm soft shadows. Keep the underlying product materials unchanged."),
    "dramatic": ("Контрастный свет", "Use a single directional side light from the left, dark fill on the right, deep but detailed shadows and strongly shaped highlights. Clearly reveal material depth."),
    "highkey": ("Светлый каталог", "Use bright high-key diffuse lighting from a very large overhead softbox, open shadows, clean whites and low contrast, as in a premium bright catalogue photograph."),
}


@lru_cache
def memory_gb():
    try:
        return round(int(subprocess.check_output(["sysctl", "-n", "hw.memsize"], timeout=2))/1024**3)
    except (OSError, ValueError, subprocess.SubprocessError):
        return 0


def model_blocker(key):
    spec = MODELS[key]
    if not spec.get("engine"):
        return spec["reason"]
    if spec["engine"] == "cpp" and platform.system() == "Darwin" and int(platform.mac_ver()[0].split('.')[0]) < 26:
        return "Для готовой сборки этого движка нужен macOS 26 или новее. Модели MLX доступны начиная с macOS 14."
    if memory_gb() and memory_gb() < spec["ram_gb"]:
        return f"Для этой конфигурации нужно от {spec['ram_gb']} ГБ памяти; на этом Mac — {memory_gb()} ГБ."
    return ""


def ensure_dirs():
    for name in ("uploads", "jobs", "models", "logs"):
        (DATA / name).mkdir(parents=True, exist_ok=True)


def model_ready(key):
    import json
    try:
        info = json.loads((DATA / "models" / f"{key}.json").read_text())
        if info["revision"] != MODELS[key].get("revision"):
            return False
        if "files" in info:
            return bool(info["files"]) and all(Path(p).is_file() for p in info["files"].values())
        return Path(info["path"]).is_dir()
    except (OSError, ValueError, KeyError):
        return False


def build_prompt(mode, note=""):
    prompt = (
        "Retouch this exact bathroom product render into a realistic studio product photograph. "
        "The same product, in the same position, photographed from exactly the same camera angle. "
        "Preserve its exact silhouette, perspective, framing, proportions, basin geometry, "
        "all holes, countertop thickness and overhang, drawer fronts, seams, gaps, and edges. "
        "Preserve the existing material colors, wood grain pattern and direction. "
        "Keep the original neutral background. Only improve how the existing materials respond "
        "to light: natural surface reflections, soft light gradients and plausible contact shadows. "
        "The product is new and clean. Do not add or remove anything. Do not add a faucet, handles, "
        "legs, accessories, decorations, extra seams, text, scratches, water or an interior. "
    )
    prompt += LIGHTS[mode][1] + " "
    if note.strip():
        prompt += "Additional material description: " + note.strip() + ". "
    return prompt + "Preserving the identity and construction of the original product takes priority."
