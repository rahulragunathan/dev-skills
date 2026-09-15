#!/usr/bin/env python3
"""Run one CLI under a deadline; terminate its whole process group on exit."""
import os
import signal
import subprocess
import sys

seconds = float(sys.argv[1])
if seconds <= 0:
    sys.exit("deadline must be positive")
process = subprocess.Popen(sys.argv[2:], start_new_session=True)
def terminate(signum, frame):
    raise SystemExit(128 + signum)
signal.signal(signal.SIGTERM, terminate)
signal.signal(signal.SIGINT, terminate)
try:
    try:
        code = process.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        print("probe timeout", file=sys.stderr)
        code = 124
finally:
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()
sys.exit(code)
