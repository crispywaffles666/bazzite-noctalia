#!/usr/bin/python3
"""Make the largest landscape Umbriel output primary in Xwayland.

Umbriel sets no RandR primary, so X11 and Proton games fall back to the first
output, which may be a rotated portrait monitor.
"""

import json
import subprocess
import time


def pick(outputs):
    enabled = [item for item in outputs if item.get("enabled")]
    landscape = [item for item in enabled if item["logical_size"]["width"] >= item["logical_size"]["height"]]
    candidates = landscape or enabled
    if not candidates:
        return None
    best = max(candidates, key=lambda item: item["logical_size"]["width"] * item["logical_size"]["height"])
    return best["name"]


def set_primary(name):
    # Xwayland may still be starting, or may not have the output yet.
    for _ in range(20):
        result = subprocess.run(("xrandr", "--output", name, "--primary"), capture_output=True, check=False)
        if result.returncode == 0:
            return
        time.sleep(0.5)


def follow():
    with subprocess.Popen(("umbriel", "subscribe", "outputs"), stdout=subprocess.PIPE, text=True) as process:
        for line in process.stdout:
            event = json.loads(line)
            if event.get("event") != "outputs":
                continue
            name = pick(event.get("data", []))
            if name is not None:
                set_primary(name)


def main():
    while True:
        try:
            follow()
        except (OSError, ValueError, KeyError, json.JSONDecodeError):
            pass
        time.sleep(1)


if __name__ == "__main__":
    main()
