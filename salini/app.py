import asyncio
import json
import os
import platform
import re
import signal
import subprocess
import sys
import threading
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Literal
from urllib.parse import urlparse

from fastapi import FastAPI, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel, Field

from .config import DATA, MODELS, ROOT, LIGHTS, ensure_dirs, model_ready, model_blocker, memory_gb
from .looks import LOOKS
from .outputs import write_outputs
from .imaging import open_image, validate_crop, restore_region, composite_document, comparison_html

ID_RE = re.compile(r"^[0-9a-f]{32}$")
MAX_BYTES = 40 * 1024 * 1024


def read_json(path):
    return json.loads(path.read_text())


def write_json(path, data):
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    tmp.replace(path)


def get_dir(kind, key):
    if not ID_RE.fullmatch(key):
        raise HTTPException(404, "Файл не найден.")
    path = DATA / kind / key
    if not path.is_dir():
        raise HTTPException(404, "Файл не найден.")
    return path


class JobManager:
    def __init__(self):
        self.lock = threading.RLock()
        self.active = None
        self.process = None
        self.cancelled = set()

    def start(self, job_id):
        with self.lock:
            if self.active:
                raise HTTPException(409, "Дождитесь завершения текущей обработки или отмените её.")
            self.active = job_id
            threading.Thread(target=self.run, args=(job_id,), daemon=True).start()

    def update(self, job_id, **fields):
        with self.lock:
            path = DATA / "jobs" / job_id / "status.json"
            status = read_json(path)
            status.update(fields, updated_at=time.time())
            write_json(path, status)

    def run(self, job_id):
        job_dir = DATA / "jobs" / job_id
        try:
            env = os.environ.copy()
            env.update(PYTHONUNBUFFERED="1", HF_HUB_DISABLE_TELEMETRY="1", TOKENIZERS_PARALLELISM="false")
            with self.lock:
                if job_id in self.cancelled:
                    return
                process = subprocess.Popen([sys.executable, "-m", "salini.worker", "--job", str(job_dir)],
                                           cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                           text=True, start_new_session=True)
                self.process = process
            tail = []
            with (job_dir / "worker.log").open("w") as log:
                for line in process.stdout:
                    log.write(line)
                    log.flush()
                    tail = (tail + [line.strip()])[-20:]
                    if "SALINI_EVENT " in line:
                        try:
                            update = json.loads(line.split("SALINI_EVENT ", 1)[1])
                            stage = update.pop("stage")
                            self.update(job_id, status="done" if stage == "done" else "running", stage=stage, **update)
                        except (ValueError, TypeError):
                            pass
            code = process.wait()
            if job_id in self.cancelled:
                self.update(job_id, status="cancelled", message="Обработка отменена.")
            elif code or not (job_dir / "after.png").exists():
                text = "\n".join(tail)
                if any(s in text.lower() for s in ["out of memory", "memory limit", "resource exhausted", "failed to allocate"]):
                    message = "Недостаточно памяти. Выберите размер 512 px или модель Klein 4B и закройте тяжёлые приложения."
                elif "ValueError: Для загрузки нужно" in text:
                    message = text.split("ValueError: ")[-1].splitlines()[0]
                elif any(s in text.lower() for s in ["connection", "timeout", "network", "resolve", "download"]):
                    message = "Не удалось загрузить модель. Проверьте интернет и повторите — загрузка продолжится из кэша."
                else:
                    message = "Обработка не завершилась. Повторите с моделью 4B и размером 768 px. Подробности — в журнале."
                self.update(job_id, status="failed", message=message, error=text[-3000:])
        except Exception as exc:
            self.update(job_id, status="failed", message="Не удалось запустить обработку.", error=str(exc))
        finally:
            with self.lock:
                self.active = None
                self.process = None
                self.cancelled.discard(job_id)

    def cancel(self, job_id):
        with self.lock:
            if self.active != job_id:
                raise HTTPException(409, "Эта обработка уже завершена.")
            self.cancelled.add(job_id)
            self.update(job_id, status="cancelled", message="Обработка отменена.")
            if self.process and self.process.poll() is None:
                os.killpg(self.process.pid, signal.SIGTERM)
                # Some native GPU operations don't react immediately to TERM.
                proc = self.process
                def stop():
                    try:
                        proc.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(proc.pid, signal.SIGKILL)
                threading.Thread(target=stop, daemon=True).start()


manager = JobManager()


@asynccontextmanager
async def lifespan(app):
    ensure_dirs()
    for path in (DATA / "jobs").glob("*/status.json"):
        status = read_json(path)
        if status.get("status") in ("queued", "running"):
            status.update(status="failed", message="Предыдущий запуск был прерван. Можно повторить обработку.")
            write_json(path, status)
    yield
    if manager.active:
        manager.cancel(manager.active)


app = FastAPI(title="Salini Render Studio", lifespan=lifespan, docs_url=None, redoc_url=None)


@app.middleware("http")
async def local_only(request: Request, call_next):
    host = request.url.hostname
    if host not in ("localhost", "127.0.0.1", "testserver"):
        return JSONResponse({"detail": "Доступ разрешён только с этого компьютера."}, status_code=403)
    origin = request.headers.get("origin")
    if request.method not in ("GET", "HEAD") and origin and urlparse(origin).netloc != request.headers.get("host"):
        return JSONResponse({"detail": "Откройте приложение в его локальном окне."}, status_code=403)
    try:
        length = int(request.headers.get("content-length", "0") or 0)
    except ValueError:
        return JSONResponse({"detail": "Неверный размер запроса."}, status_code=400)
    if length > MAX_BYTES + 1024 * 1024:
        return JSONResponse({"detail": "Файл должен быть меньше 40 МБ."}, status_code=413)
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Cache-Control"] = "no-store"
    return response


@app.get("/api/status")
def status():
    models = [{"key": k, **{x: v.get(x) for x in ("name", "description", "download_gb", "license", "engine", "task", "ram_gb", "source", "tested")},
               "ready": model_ready(k), "blocker": model_blocker(k)}
              for k, v in MODELS.items()]
    memory = memory_gb()
    return {"app": "salini-render-studio", "version": "1.1.0", "models": models, "looks": LOOKS,
            "lights": {k:v[0] for k,v in LIGHTS.items()},
            "recommended_model": "klein9" if memory >= 24 else "klein4", "memory_gb": round(memory),
            "active_job": manager.active, "supported": platform.system() == "Darwin" and platform.machine() == "arm64"}


@app.post("/api/uploads")
async def upload(file: UploadFile):
    data = bytearray()
    while chunk := await file.read(1024 * 1024):
        data.extend(chunk)
        if len(data) > MAX_BYTES:
            raise HTTPException(413, "Файл должен быть меньше 40 МБ.")
    try:
        im = await asyncio.to_thread(open_image, bytes(data))
    except (ValueError, OSError, UnidentifiedImageError, Image.DecompressionBombError) as exc:
        raise HTTPException(400, str(exc) if isinstance(exc, ValueError) else "Не удалось прочитать изображение.") from exc
    key = uuid.uuid4().hex
    path = DATA / "uploads" / key
    path.mkdir(parents=True)
    await asyncio.to_thread(im.save, path / "original.png")
    result = {"id": key, "name": Path(file.filename or "Изображение").name, "width": im.width, "height": im.height,
              "url": f"/api/uploads/{key}/image"}
    write_json(path / "meta.json", result)
    return result


@app.get("/api/uploads/{key}/image")
def upload_image(key: str):
    return FileResponse(get_dir("uploads", key) / "original.png", media_type="image/png")


@app.get("/api/uploads/{key}")
def upload_metadata(key: str):
    return read_json(get_dir("uploads", key) / "meta.json")


class LookRequest(BaseModel):
    color_style: Literal["neutral", "warm", "cool", "vivid", "soft", "contrast"] = "neutral"
    color_strength: int = Field(default=60, ge=0, le=100)
    amount: int = Field(default=100, ge=0, le=100)


class RenderRequest(LookRequest):
    upload_id: str
    crop: tuple[int, int, int, int]
    model: str = "klein4"
    mode: str = "gentle"
    resolution: Literal[512, 768, 1024] = 768
    seed: int = Field(default=42, ge=0, le=2**32-1)
    note: str = Field(default="", max_length=600)


@app.post("/api/jobs")
def start_job(body: RenderRequest):
    if body.model not in MODELS or body.mode not in LIGHTS:
        raise HTTPException(400, "Неизвестная модель или вариант света.")
    if reason := model_blocker(body.model):
        raise HTTPException(400, reason)
    path = get_dir("uploads", body.upload_id)
    im = Image.open(path / "original.png").convert("RGB")
    try:
        box = validate_crop(body.crop, im.size)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    with manager.lock:
        if manager.active:
            raise HTTPException(409, "Уже выполняется обработка. Дождитесь её завершения.")
        key = uuid.uuid4().hex
        job = DATA / "jobs" / key
        job.mkdir(parents=True)
        im.crop(box).save(job / "before.png")
        settings = body.model_dump()
        settings["source_name"] = read_json(path / "meta.json")["name"]
        write_json(job / "settings.json", settings)
        write_json(job / "status.json", {"id": key, "status": "queued", "stage": "queued", "created_at": time.time(),
                                         "message": "Подготовка к обработке…", "model": body.model})
        manager.start(key)
    return {"id": key}


@app.get("/api/jobs")
def jobs():
    items = []
    for path in (DATA / "jobs").glob("*/status.json"):
        item = read_json(path)
        if item.get("status") == "done":
            item["name"] = read_json(path.parent / "settings.json").get("source_name", "Изображение")
            items.append(item)
    return sorted(items, key=lambda x: x["created_at"], reverse=True)[:20]


@app.get("/api/jobs/{key}")
def job_status(key: str):
    path = get_dir("jobs", key)
    return {**read_json(path / "status.json"), "settings": read_json(path / "settings.json")}


@app.post("/api/jobs/{key}/cancel")
def cancel_job(key: str):
    manager.cancel(key)
    return {"ok": True}


class RestoreRequest(BaseModel):
    box: tuple[int, int, int, int] | None = None
    reset: bool = False


@app.post("/api/jobs/{key}/look")
def update_look(key: str, body: LookRequest):
    path = get_dir("jobs", key)
    with manager.lock:
        if read_json(path / "status.json").get("status") != "done":
            raise HTTPException(409, "Дождитесь завершения обработки.")
        settings = read_json(path / "settings.json")
        settings.update(body.model_dump())
        write_outputs(path, settings)
        write_json(path / "settings.json", settings)
    return {"ok": True, "settings": settings}


@app.post("/api/jobs/{key}/restore")
def restore_detail(key: str, body: RestoreRequest):
    path = get_dir("jobs", key)
    with manager.lock:
        if read_json(path / "status.json").get("status") != "done":
            raise HTTPException(409, "Дождитесь завершения обработки.")
        settings = read_json(path / "settings.json")
        if body.reset:
            settings["restored_regions"] = []
        elif body.box:
            x,y,w,h = body.box
            iw,ih = Image.open(path / "before.png").size
            if min(x,y)<0 or min(w,h)<4 or x+w>iw or y+h>ih:
                raise HTTPException(400, "Выделите область минимум 4 × 4 пикселя внутри изображения.")
            settings.setdefault("restored_regions", []).append(list(body.box))
        else:
            raise HTTPException(400, "Выделите деталь для восстановления.")
        write_outputs(path, settings)
        write_json(path / "settings.json", settings)
    return {"ok": True, "restored_regions": settings["restored_regions"]}


@app.get("/api/jobs/{key}/files/{name}")
def job_file(key: str, name: str, download: bool = False):
    if name not in ("before.png", "after.png", "document.png", "comparison.html", "settings.json", "worker.log"):
        raise HTTPException(404)
    path = get_dir("jobs", key) / name
    if not path.exists():
        raise HTTPException(404, "Результат ещё не готов.")
    return FileResponse(path, filename=f"salini-{key[:8]}-{name}" if download else None)


app.mount("/", StaticFiles(directory=ROOT / "web", html=True), name="web")
