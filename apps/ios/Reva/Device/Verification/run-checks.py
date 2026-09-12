#!/usr/bin/env python3
"""Build and run isolated native adapter checks on an already booted iPhone simulator.

No shared Xcode project changes, credentials, camera, or microphone access. Harness.swift.in
is a template so the app project generator does not include a second executable entrypoint.
"""
import argparse
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import time


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="booted", help="An already booted iPhone simulator UUID")
    parser.add_argument("--output", default="/private/tmp/reva-device-qa")
    parser.add_argument("--restore-app", default="health.revamed.Reva")
    args = parser.parse_args()
    device_dir = pathlib.Path(__file__).resolve().parent.parent
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="reva-device-harness-"))
    app = scratch / "RevaDeviceHarness.app"
    app.mkdir()
    harness = scratch / "Harness.swift"
    shutil.copyfile(device_dir / "Verification" / "Harness.swift.in", harness)
    identifier = "health.revamed.DeviceHarness"
    info = {
        "CFBundleIdentifier": identifier, "CFBundleName": "Reva Device QA",
        "CFBundleExecutable": "DeviceHarness", "CFBundleVersion": "1",
        "CFBundleShortVersionString": "1.0", "CFBundlePackageType": "APPL",
        "MinimumOSVersion": "18.0", "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
        "UIDeviceFamily": [1], "LSRequiresIPhoneOS": True, "UILaunchScreen": {},
    }
    (app / "Info.plist").write_bytes(plistlib.dumps(info))
    sdk = output("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path")
    compiler = output("xcrun", "--find", "swiftc")
    run(compiler, "-swift-version", "6", "-strict-concurrency=complete", "-sdk", sdk,
        "-target", "arm64-apple-ios18.0-simulator", "-module-cache-path", str(scratch / "module-cache"),
        *(str(p) for p in sorted(device_dir.glob("*.swift"))), str(harness),
        "-o", str(app / "DeviceHarness"))
    run("/usr/bin/codesign", "--force", "--sign", "-", str(app))
    subprocess.run(["xcrun", "simctl", "terminate", args.device, identifier], capture_output=True)
    run("xcrun", "simctl", "install", args.device, str(app))
    run("xcrun", "simctl", "launch", args.device, identifier)
    try:
        container = pathlib.Path(output("xcrun", "simctl", "get_app_container", args.device, identifier, "data")) / "Documents"
        result_file = container / "results.txt"
        deadline = time.monotonic() + 150
        while time.monotonic() < deadline:
            text = result_file.read_text() if result_file.exists() else ""
            if "ALL CHECKS PASSED" in text or "FAIL " in text:
                break
            time.sleep(0.5)
        else:
            raise RuntimeError("Adapter checks timed out; inspect the simulator harness.")
        destination = pathlib.Path(args.output).resolve()
        destination.mkdir(parents=True, exist_ok=True)
        for path in [result_file, container / "adapter-report.pdf", *container.glob("report-page-*.png")]:
            if path.exists():
                shutil.copyfile(path, destination / path.name)
        print(text)
        print(f"QA artifacts: {destination}")
        if "ALL CHECKS PASSED" not in text:
            raise RuntimeError("A device adapter check failed.")
    finally:
        subprocess.run(["xcrun", "simctl", "terminate", args.device, identifier], capture_output=True)
        if args.restore_app:
            subprocess.run(["xcrun", "simctl", "launch", args.device, args.restore_app], capture_output=True)


if __name__ == "__main__":
    main()
