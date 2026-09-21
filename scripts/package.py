"""Share source and launchers, never images, model weights, caches or user data."""
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parent.parent
FILES = ["pyproject.toml", "uv.lock", "bootstrap.sh", "Запустить Salini.command", "Установить Salini.command", "README.md", "ONLINE.md", "Запустить веб-студию.command", "Остановить веб-студию.command", "LICENSE", "THIRD_PARTY.md"]
FOLDERS = ["salini", "web", "pages", "Salini Render Studio.app", "scripts", "tests"]

if __name__ == "__main__":
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    out = dist / "Salini-Render-Studio-Mac.zip"
    paths = [ROOT / f for f in FILES]
    paths += [p for f in FOLDERS for p in (ROOT / f).rglob("*") if p.is_file() and "__pycache__" not in p.parts and p.name != ".DS_Store"]
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(paths):
            z.write(p, Path("Salini Render Studio") / p.relative_to(ROOT))
    print(out)
