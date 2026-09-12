#!/usr/bin/env python3
"""Purpose: Compile focused regression checks against production Swift state/storage code.
Inputs: A Swift compiler, production sources and the checked-in Swift harness.
Outputs: Compiler diagnostics and behavioral assertions; nonzero on any failure.
Side effects: Writes only build/optimization-checks and runs a local synthetic-data executable.
Boundary: Network clients and Windows Combine are test doubles; no iOS UI/provider tests.
"""

import os
from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build/optimization-checks"
SOURCES = [
    "Core/Models.swift", "Core/SymptomEntry.swift", "Core/LocalRepository.swift",
    "Core/ProviderContracts.swift", "State/AppStore.swift",
    "State/AppStore+Records.swift", "State/AppStore+Sync.swift",
    "State/AppStore+Providers.swift",
]


def main():
    compiler = shutil.which("swiftc")
    if not compiler and os.name == "nt":
        roots = [Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/Swift",
                 Path("C:/Program Files/Swift")]
        compiler = next((str(p) for root in roots for p in root.glob("Toolchains/*/usr/bin/swiftc.exe")), None)
    if not compiler:
        raise SystemExit("Swift compiler unavailable; these behavioral checks have NOT run.")
    if os.name == "nt":
        vswhere = Path(os.environ["ProgramFiles(x86)"]) / "Microsoft Visual Studio/Installer/vswhere.exe"
        installation = subprocess.check_output([
            str(vswhere), "-latest", "-products", "*", "-requires",
            "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"
        ], text=True).strip()
        if not installation:
            raise SystemExit("Visual Studio C++ build tools are required for Windows Swift.")
        devcmd = Path(installation) / "Common7/Tools/VsDevCmd.bat"
        environment = subprocess.check_output(
            f'cmd.exe /d /s /c ""{devcmd}" -arch=x64 -host_arch=x64 >nul && set"', text=True)
        for line in environment.splitlines():
            key, separator, value = line.partition("=")
            if separator and key.upper() in {"PATH", "INCLUDE", "LIB", "LIBPATH", "VCTOOLSINSTALLDIR", "WINDOWSSDKDIR", "WINDOWSSDKVERSION"}:
                os.environ[key] = value
        swift_root = Path(compiler).resolve().parents[4]
        sdk = next(swift_root.glob("Platforms/*/Windows.platform/Developer/SDKs/Windows.sdk"))
        runtime = next(swift_root.glob("Runtimes/*/usr/bin"))
        os.environ["SDKROOT"] = str(sdk)
        os.environ["PATH"] = os.pathsep.join([str(Path(compiler).parent), str(runtime), os.environ["PATH"]])
    BUILD.mkdir(parents=True, exist_ok=True)
    suites = [("StateChecks", SOURCES)]
    if (ROOT / "Tests/OptimizationChecks/ProviderChecks.swift").exists():
        suites.append(("ProviderChecks", ["Core/Models.swift", "Core/SymptomEntry.swift",
                                         "Core/ProviderContracts.swift", "Core/ProviderClient.swift"]))
    for suite, sources in suites:
        paths = []
        for relative in sources:
            source = ROOT / "apps/ios/Reva" / relative
            # Use production logic; Windows needs its FoundationNetworking import and a Combine double.
            content = source.read_text(encoding="utf-8")
            if os.name == "nt":
                content = content.replace("import Combine", "")
                if source.name == "ProviderClient.swift":
                    content = content.replace("import Foundation", "import Foundation\nimport FoundationNetworking")
            target = BUILD / source.name
            target.write_text(content, encoding="utf-8")
            paths.append(str(target))
        executable = BUILD / (suite + (".exe" if os.name == "nt" else ""))
        subprocess.run([compiler, "-swift-version", "5", "-parse-as-library", *paths,
                        str(ROOT / f"Tests/OptimizationChecks/{suite}.swift"), "-o", str(executable)], check=True)
        subprocess.run([str(executable), str(ROOT / "demo/seed.json")], check=True)


if __name__ == "__main__":
    main()
