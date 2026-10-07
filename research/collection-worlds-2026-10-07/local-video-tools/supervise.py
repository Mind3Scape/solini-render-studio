#!/usr/bin/env python3
"""Run ONE command in its own process group and supervise the whole group.

- The child is started with start_new_session=True: it leads a new session and process group,
  so every renderer process it spawns (ffmpeg, workers) is in that group.
- Every interval: memory pressure level, free %, swap, and the summed RSS of the group's
  processes go to the memory log.
- Stop conditions: sustained critical pressure (level >= 4 for `critical_seconds`) or the hard
  wall-time cap. Stopping sends SIGTERM to the group, waits `grace`, then SIGKILL to the group,
  and verifies that no process of the group is left (`os.killpg(pgid, 0)` → ProcessLookupError).
- Only this group is ever signalled; nothing else on the machine is touched.
- Max RSS of the child tree comes from getrusage(RUSAGE_CHILDREN) after it is reaped.

Usage: supervise.py --log DIR --wall SECONDS [--critical-seconds N] [--interval N] -- CMD...
Test hook: SUPERVISE_FAKE_LEVEL=4 pretends the system is under critical pressure.
"""
import argparse
import json
import os
import resource
import signal
import subprocess
import sys
import time


def sh(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception:
        return ""


def pressure_level():
    fake = os.environ.get("SUPERVISE_FAKE_LEVEL")
    if fake:
        return int(fake)
    v = sh(["sysctl", "-n", "kern.memorystatus_vm_pressure_level"])
    return int(v) if v.isdigit() else -1


def group_pids(pgid):
    out = sh(["ps", "-axo", "pid=,pgid=,rss="])
    pids, rss = [], 0
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[1] == str(pgid):
            pids.append(int(parts[0]))
            rss += int(parts[2])
    return pids, rss


def group_alive(pgid):
    try:
        os.killpg(pgid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def stop_group(pgid, child, grace, log):
    log(f"stop: SIGTERM to process group {pgid}")
    try:
        os.killpg(pgid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    deadline = time.time() + grace
    while time.time() < deadline and group_alive(pgid):
        child.poll()
        time.sleep(0.2)
    if group_alive(pgid):
        log(f"stop: SIGKILL to process group {pgid}")
        try:
            os.killpg(pgid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    child.wait()
    for _ in range(50):
        if not group_alive(pgid):
            break
        time.sleep(0.1)
    left, _ = group_pids(pgid)
    log(f"stop: group {pgid} alive={group_alive(pgid)} remaining={left}")
    return not group_alive(pgid) and not left


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", required=True)
    ap.add_argument("--wall", type=float, required=True)
    ap.add_argument("--critical-seconds", type=float, default=30)
    ap.add_argument("--interval", type=float, default=5)
    ap.add_argument("--grace", type=float, default=10)
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cmd = a.cmd[1:] if a.cmd and a.cmd[0] == "--" else a.cmd
    os.makedirs(a.log, exist_ok=True)
    mem = open(os.path.join(a.log, "memory.log"), "a", buffering=1)
    out = open(os.path.join(a.log, "generate.log"), "ab", buffering=0)

    def log(msg):
        mem.write(f"{time.strftime('%H:%M:%S')} {msg}\n")

    start = time.time()
    child = subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT, start_new_session=True)
    pgid = os.getpgid(child.pid)
    log(f"start pid={child.pid} pgid={pgid} wall_cap_s={a.wall}")
    reason, critical_since = "exit", None
    while child.poll() is None:
        level = pressure_level()
        free = sh(["memory_pressure", "-Q"]).rsplit(":", 1)[-1].strip()
        swap = sh(["sysctl", "-n", "vm.swapusage"])
        pids, rss = group_pids(pgid)
        log(f"level={level} free={free} swap=[{swap}] group_pids={len(pids)} group_rss_mb={rss // 1024}")
        now = time.time()
        if level >= 4:
            critical_since = critical_since or now
        else:
            critical_since = None
        if critical_since and now - critical_since >= a.critical_seconds:
            reason = "critical_memory_pressure"
        elif now - start >= a.wall:
            reason = "wall_time_cap"
        if reason != "exit":
            clean = stop_group(pgid, child, a.grace, log)
            break
        time.sleep(a.interval)
    else:
        clean = not group_alive(pgid)
        if not clean:
            # The leader exited but something it spawned is still in the group.
            clean = stop_group(pgid, child, a.grace, log)
            reason = "leader_exited_children_left"
    usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    result = {
        "reason": reason,
        "returncode": child.returncode,
        "wall_seconds": round(time.time() - start, 1),
        "children_max_rss_mb": round(usage.ru_maxrss / 1048576, 1),  # bytes on macOS
        "group_cleaned_up": clean,
        "pid": child.pid,
        "pgid": pgid,
    }
    log("result " + json.dumps(result))
    with open(os.path.join(a.log, "result.json"), "w") as f:
        json.dump(result, f, indent=2)
    print(json.dumps(result))
    sys.exit(0 if reason == "exit" and child.returncode == 0 else 1)


if __name__ == "__main__":
    main()
