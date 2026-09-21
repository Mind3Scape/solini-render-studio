"""One model process across the desktop app and the online service."""
from contextlib import contextmanager
import fcntl
import time
from .config import DATA


@contextmanager
def gpu_slot(event):
    DATA.mkdir(parents=True, exist_ok=True)
    with (DATA / 'gpu.lock').open('a') as lock:
        announced = False
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if not announced:
                    event('waiting', 'Ожидание: Mac завершает предыдущую обработку…')
                    announced = True
                time.sleep(1)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)
