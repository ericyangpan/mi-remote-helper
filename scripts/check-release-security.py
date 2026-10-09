#!/usr/bin/env python3
"""Read-only checks for the app's minimal Release signing policy."""
import argparse
import pathlib
import plistlib
import subprocess
import sys


def run(*args):
    return subprocess.run(args, check=True, capture_output=True)


def check(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=pathlib.Path)
    parser.add_argument("--distribution", action="store_true",
                        help="also require Developer ID and a secure timestamp; does not prove notarization")
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    run("codesign", "--verify", "--deep", "--strict", str(app))
    signature = run("codesign", "-d", "--verbose=4", str(app)).stderr.decode()
    check(any(line.startswith("CodeDirectory ") and "runtime" in line
              for line in signature.splitlines()), "Hardened Runtime is missing")
    raw = run("codesign", "-d", "--entitlements", "-", "--xml", str(app)).stdout
    entitlements = plistlib.loads(raw) if raw.strip() else {}
    check(not entitlements, "Unexpected Release entitlements: " + ", ".join(entitlements))
    with (app / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    check(info.get("CFBundleIdentifier") == "com.yangpan.MiRemoteHelper", "Unexpected bundle identifier")
    usage_keys = {key for key in info if key.startswith("NS") and "UsageDescription" in key}
    check(usage_keys == {"NSBluetoothAlwaysUsageDescription"},
          "Unexpected permission descriptions: " + ", ".join(sorted(usage_keys)))
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    check(run("lipo", "-archs", str(executable)).stdout.decode().strip() == "arm64",
          "Release must contain only arm64")
    if args.distribution:
        check("Authority=Developer ID Application:" in signature, "Developer ID signature is missing")
        check(any(line.startswith("Timestamp=") for line in signature.splitlines()),
              "Secure timestamp is missing")
    print("PASS: arm64, valid signature, Hardened Runtime, no entitlements, Bluetooth-only usage description")
    if args.distribution:
        print("PASS: Developer ID and secure timestamp; notarization must be checked separately")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
