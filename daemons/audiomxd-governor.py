#!/usr/bin/env python3
"""
audiomxd-governor: macOS Tahoe / Sequoia audiomxd Spin-Loop Governor Daemon
Open Source Community Fix for Apple Silicon macOS 15.x / 26.x

PURPOSE:
Prevents /usr/libexec/audiomxd from entering an unthrottled recursive XPC error
loop while the system is at loginwindow or operating headless.

DESIGN:
- Stateless, level-triggered supervisor monitoring /dev/console session ownership.
- When no interactive Aqua user is logged in (UID < 500), suspends audiomxd via SIGSTOP.
- When an interactive console user logs in (UID >= 500), sends SIGCONT if audiomxd is suspended.
- Robust across daemon restarts, crash cycles, and governor process restarts without relying
  on volatile in-memory PID tracking.
"""

import os
import sys
import time
import signal
import subprocess

def get_console_uid() -> int:
    """Return the UID of the current console session owner (/dev/console)."""
    try:
        st = os.stat("/dev/console")
        return st.st_uid
    except Exception:
        return 0

def get_audiomxd_pid_and_stat():
    """Query the active PID and process state string for audiomxd."""
    try:
        out = subprocess.check_output(
            "ps -p $(pgrep audiomxd) -o pid,stat",
            shell=True,
            text=True
        ).strip().splitlines()
        if len(out) > 1:
            parts = out[1].split()
            return int(parts[0]), parts[1]
    except Exception:
        pass
    return None, None

def main():
    while True:
        try:
            uid = get_console_uid()
            pid, stat = get_audiomxd_pid_and_stat()

            if pid is not None and stat is not None:
                is_headless = (uid < 500)
                is_stopped = ("T" in stat)

                if is_headless and not is_stopped:
                    # At loginwindow / headless: pause audiomxd
                    try:
                        os.kill(pid, signal.SIGSTOP)
                    except ProcessLookupError:
                        pass
                elif not is_headless and is_stopped:
                    # Interactive user logged in: resume audiomxd
                    try:
                        os.kill(pid, signal.SIGCONT)
                    except ProcessLookupError:
                        pass

            time.sleep(2)
        except Exception:
            time.sleep(2)

if __name__ == "__main__":
    main()
