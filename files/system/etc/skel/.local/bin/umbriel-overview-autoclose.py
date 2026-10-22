#!/usr/bin/python3
"""Close the Umbriel overview when a new window opens."""

import json
import subprocess
import time


def follow():
    known = None
    with subprocess.Popen(("umbriel", "subscribe", "windows"), stdout=subprocess.PIPE, text=True) as process:
        for line in process.stdout:
            event = json.loads(line)
            if event.get("event") != "windows":
                continue
            current = {item["id"] for item in event.get("data", [])}
            # The first event lists the windows that already exist.
            if known is not None and current - known:
                subprocess.run(("umbriel", "msg", "overview-close"), check=False)
            known = current


def main():
    while True:
        try:
            follow()
        except (OSError, ValueError, json.JSONDecodeError):
            pass
        time.sleep(1)


if __name__ == "__main__":
    main()
