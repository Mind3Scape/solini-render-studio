"""Two independent app processes must not load models simultaneously."""
import os
import subprocess
import sys

from salini import gpu_lock


def test_worker_waits_for_other_app_and_releases_on_exit(tmp_path, monkeypatch):
    monkeypatch.setattr(gpu_lock, 'DATA', tmp_path)
    child = subprocess.Popen(
        [sys.executable, '-u', '-c',
         "from salini.gpu_lock import gpu_slot; import sys\n"
         "with gpu_slot(lambda *a: None):\n"
         " print('locked', flush=True)\n"
         " sys.stdin.read()\n"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
        env={**os.environ, 'SALINI_DATA_DIR': str(tmp_path)},
    )
    try:
        assert child.stdout.readline().strip() == 'locked'
        events = []
        def waiting(stage, message):
            events.append(stage)
            child.terminate()
            child.wait(timeout=5)
        with gpu_lock.gpu_slot(waiting):
            assert events == ['waiting']
        with gpu_lock.gpu_slot(lambda *_: (_ for _ in ()).throw(AssertionError())):
            pass
    finally:
        if child.poll() is None:
            child.kill()
        child.wait(timeout=5)
