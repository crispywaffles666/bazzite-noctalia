#!/usr/bin/python3
"""Restore per-monitor column widths after an Umbriel output move."""

import json
import os
from pathlib import Path
import re
import subprocess
import time


CONFIG = Path(
    os.environ.get(
        "UMBRIEL_OUTPUT_WIDTHS",
        str(Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "umbriel/output-widths.json"),
    )
)


def run_json(*args):
    return json.loads(subprocess.check_output(("umbriel", *args), text=True))


def desired_extents():
    values = json.loads(CONFIG.read_text())
    result = {}
    for serial, width in values.items():
        match = re.fullmatch(r"(\d{1,3})%", width)
        if match and 10 <= int(match.group(1)) <= 100:
            result[serial] = int(match.group(1)) / 100
    return result


def apply_width(window_id, output_name, extents):
    outputs = {item["name"]: item["serial"] for item in run_json("outputs", "--json")}
    fraction = extents.get(outputs.get(output_name))
    if fraction is None:
        return
    # The action targets the focused column. Recheck focus after the event so
    # a fast focus change cannot resize a different window.
    windows = run_json("windows", "--json")
    if not any(item["id"] == window_id and item["focused"] and not item["floating"] for item in windows):
        return
    subprocess.run(("umbriel", "msg", f"window-set-primary-extent:{fraction:g}"), check=True)


def follow(extents):
    previous = {}
    pending = {}
    with subprocess.Popen(("umbriel", "subscribe", "windows"), stdout=subprocess.PIPE, text=True) as process:
        for line in process.stdout:
            event = json.loads(line)
            if event.get("event") != "windows":
                continue
            windows = event.get("data", [])
            current = {item["id"]: item["output"] for item in windows if not item["floating"]}
            pending = {key: output for key, output in pending.items() if key in current}
            for window_id, output in current.items():
                if window_id in previous and previous[window_id] != output:
                    pending[window_id] = output
            previous = current
            for item in windows:
                if item["focused"] and not item["floating"] and pending.get(item["id"]) == item["output"]:
                    pending.pop(item["id"])
                    try:
                        apply_width(item["id"], item["output"], extents)
                    except (subprocess.CalledProcessError, KeyError, ValueError):
                        pass


def main():
    extents = desired_extents()
    while True:
        try:
            follow(extents)
        except (OSError, ValueError, json.JSONDecodeError):
            pass
        time.sleep(1)


if __name__ == "__main__":
    main()
