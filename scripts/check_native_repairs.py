#!/usr/bin/env python3
"""Purpose: Run deterministic native state regression checks against production Swift sources.
Inputs: Checked-in synthetic fixture, production state/domain sources, and a Swift compiler.
Outputs: Named assertions for audited races, recovery, editing, and recording metadata persistence.
Side effects: Temporary files under /private/tmp only; all provider/server calls use test doubles.
Boundary: No real provider, microphone, simulator UI, or network requests.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    "Core/Models.swift", "Core/SymptomEntry.swift", "Core/LocalRepository.swift",
    "Core/ProviderContracts.swift", "Core/ReportEngine.swift",
    "State/AppStore.swift", "State/AppStore+Records.swift", "State/AppStore+Visits.swift",
    "State/AppStore+Providers.swift", "State/AppStore+AI.swift",
    "State/AppStore+Recordings.swift",
    "State/AppStore+Transcription.swift", "State/AppStore+Sync.swift",
]


# MARK: - Compile unchanged production sources with controlled transport boundaries

def main():
    xcode = Path("/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc")
    compiler = os.environ.get("SWIFTC") or (str(xcode) if xcode.exists() else shutil.which("swiftc"))
    if not compiler:
        raise SystemExit("Swift compiler unavailable; native repair checks did not run.")
    sdk = Path("/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")
    compiler_options = ["-sdk", str(sdk)] if xcode.exists() and sdk.exists() else []
    scratch_root = "/private/tmp" if Path("/private/tmp").is_dir() else None
    with tempfile.TemporaryDirectory(prefix="reva-native-repairs-", dir=scratch_root) as directory:
        scratch = Path(directory)
        binary = scratch / "NativeRepairChecks"
        shutil.copyfile(ROOT / "demo/seed.json", scratch / "seed.json")
        subprocess.run([
            compiler, *compiler_options, "-swift-version", "5", "-parse-as-library", "-module-cache-path", str(scratch / "modules"),
            *(str(ROOT / "apps/ios/Reva" / source) for source in SOURCES),
            str(ROOT / "Tests/NativeRepairChecks/NativeRepairChecks.swift"), "-o", str(binary),
        ], check=True)
        subprocess.run([str(binary), str(scratch / "seed.json"), str(scratch)], check=True)
        # Device implementations are unavailable on macOS. Swap imports only; preserve every production body.
        audio_source = (ROOT / "apps/ios/Reva/Device/AudioServices.swift").read_text()
        audio_source = audio_source.replace("import AVFoundation", "import Foundation").replace("import UIKit", "")
        audio_copy = scratch / "AudioServices.swift"
        audio_copy.write_text(audio_source)
        audio_binary = scratch / "AudioRepairChecks"
        subprocess.run([
            compiler, *compiler_options, "-swift-version", "5", "-parse-as-library",
            "-module-cache-path", str(scratch / "modules"), str(audio_copy),
            str(ROOT / "Tests/NativeRepairChecks/AudioBoundaryDoubles.swift"),
            str(ROOT / "Tests/NativeRepairChecks/AudioRepairChecks.swift"), "-o", str(audio_binary),
        ], check=True)
        subprocess.run([str(audio_binary), str(scratch)], check=True)


if __name__ == "__main__":
    main()
