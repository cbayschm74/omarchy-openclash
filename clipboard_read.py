#!/usr/bin/python
"""Explicit paste only: cap aggregate bytes and the whole provider read time."""
import json
import os
import selectors
import signal
import subprocess
import time

MAX_BYTES = 8192
DEADLINE_SECONDS = 1.0


def read_clipboard(command=("/usr/bin/wl-paste", "--no-newline", "--type", "text"),
                   limit=MAX_BYTES, timeout=DEADLINE_SECONDS):
    deadline = time.monotonic() + timeout
    proc = subprocess.Popen(command, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        data = bytearray()
        with selectors.DefaultSelector() as selector:
            selector.register(proc.stdout, selectors.EVENT_READ)
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    raise ValueError("Paste timed out")
                chunk = os.read(proc.stdout.fileno(), min(4096, limit + 1 - len(data)))
                if not chunk:
                    break
                data.extend(chunk)
                if len(data) > limit:
                    raise ValueError("Clipboard text exceeds 8 KiB")
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ValueError("Paste timed out")
        try:
            code = proc.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            raise ValueError("Paste timed out") from None
        if code:
            raise ValueError("Clipboard text unavailable")
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            raise ValueError("Clipboard text is not UTF-8") from None
        if any(ord(c) < 32 or ord(c) == 127 for c in text):
            raise ValueError("Paste a single line without control characters")
        return text
    finally:
        # Kill the process group even when the provider closed stdout but left
        # a child alive. Do not buffer its output in communicate().
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.stdout.close()
        try:
            proc.wait(timeout=0.1)
        except subprocess.TimeoutExpired:
            pass


def main():
    try:
        result = {"ok": True, "text": read_clipboard()}
    except (OSError, ValueError):
        # No provider output, clipboard content or secret enters diagnostics.
        result = {"ok": False, "error": "Paste failed: clipboard text must be one line, at most 8 KiB, and available within one second"}
    print(json.dumps(result))


if __name__ == "__main__":
    main()
