"""Start a persistent localhost server and open the user's default browser."""
import argparse
import fcntl
import json
import os
import socket
import subprocess
import sys
import time
import urllib.request
import webbrowser

from .config import DATA, ROOT, ensure_dirs


def health(port):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/status", timeout=1) as response:
            return json.load(response).get("app") == "salini-render-studio"
    except (OSError, ValueError):
        return False


def launch(open_browser=True):
    ensure_dirs()
    with (DATA / "launcher.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        port = None
        instance = DATA / "instance.json"
        if instance.exists():
            old = json.loads(instance.read_text())
            if health(old["port"]):
                port = old["port"]
        if port is None:
            for candidate in range(8765, 8785):
                if health(candidate):
                    port = candidate
                    break
                try:
                    with socket.socket() as sock:
                        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                        sock.bind(("127.0.0.1", candidate))
                    port = candidate
                    break
                except OSError:
                    continue
            if port is None:
                raise RuntimeError("Не удалось найти свободный локальный порт.")
            if not health(port):
                log = (DATA / "logs" / "server.log").open("a")
                proc = subprocess.Popen([sys.executable, "-m", "uvicorn", "salini.app:app", "--host", "127.0.0.1",
                                         "--port", str(port), "--no-access-log"],
                                        cwd=ROOT, stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
                for _ in range(100):
                    if health(port):
                        break
                    if proc.poll() is not None:
                        raise RuntimeError(f"Не удалось запустить Salini. Журнал: {DATA / 'logs/server.log'}")
                    time.sleep(.2)
                else:
                    proc.terminate()
                    raise RuntimeError("Сервер не ответил. Повторите запуск приложения.")
                instance.write_text(json.dumps({"port": port, "pid": proc.pid, "root": str(ROOT)}))
        url = f"http://127.0.0.1:{port}"
    if open_browser:
        webbrowser.open(url)
    print(url)
    return url


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-browser", action="store_true")
    launch(not parser.parse_args().no_browser)
