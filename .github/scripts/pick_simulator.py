#!/usr/bin/env python3
"""Print the UDID of an available iPhone simulator the selected Xcode can
target: the newest iOS runtime not newer than its simulator SDK, preferring a
"Pro". Used by CI and by the local command in docs/ci.md."""
import json
import re
import subprocess
import sys

sdk_version = subprocess.run(
    ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"],
    capture_output=True, text=True, check=True).stdout.strip()
sdk = tuple(int(x) for x in (sdk_version.split(".") + ["0"])[:2])
devices = json.loads(subprocess.run(
    ["xcrun", "simctl", "list", "devices", "available", "-j"],
    capture_output=True, text=True, check=True).stdout)["devices"]


def runtime_version(runtime):
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(m.group(1)), int(m.group(2))) if m else None


best = None
for runtime, devs in devices.items():
    v = runtime_version(runtime)
    if not v or v > sdk:
        continue
    phones = [d for d in devs if d.get("isAvailable") and d["name"].startswith("iPhone")]
    if not phones:
        continue
    phones.sort(key=lambda d: ("Pro" not in d["name"], d["name"]))
    if best is None or v > best[0]:
        best = (v, phones[0])

if best is None:
    sys.exit("no available iPhone simulator for SDK %s" % sdk_version)
(major, minor), device = best
print("Simulator SDK %s: using iOS %d.%d %s" % (sdk_version, major, minor, device["name"]), file=sys.stderr)
print(device["udid"])
