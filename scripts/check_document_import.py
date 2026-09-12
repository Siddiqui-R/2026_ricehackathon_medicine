#!/usr/bin/env python3
"""Compile and run the native local PDFKit/Vision synthetic mixed-PDF regression checks."""
from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
if platform.system() != 'Darwin':
    raise SystemExit('These checks require macOS with Xcode PDFKit and Vision frameworks.')
sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
compiler = subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip()
with tempfile.TemporaryDirectory(prefix='reva-document-check-', dir='/private/tmp') as temporary:
    output = Path(temporary)
    subprocess.run([
        compiler, '-parse-as-library', '-sdk', sdk,
        '-target', platform.machine() + '-apple-macosx13.0',
        '-module-cache-path', str(output / 'module-cache'),
        str(root / 'apps/ios/Reva/Device/DocumentImportService.swift'),
        str(root / 'Tests/DocumentImportChecks/Check.swift'), '-o', str(output / 'check'),
    ], check=True)
    subprocess.run([str(output / 'check')], check=True)
