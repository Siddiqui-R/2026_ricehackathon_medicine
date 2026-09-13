#!/usr/bin/env python3
"""Render web-only fixture copies with the same display policy as the app.

Canonical sources, native resources, record IDs, and saved attachments stay intact.
Run manually when the fixtures or presentation wording change; build only copies these assets.
Requires the same local dependencies as generate_fixtures.py and Node 24.
"""
import hashlib
import json
import re
import subprocess
import tempfile
from pathlib import Path
import generate_fixtures as fixtures
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'apps/web/assets/source-previews'


def render(directory):
    fixtures.SOURCES = directory
    for doc in fixtures.DOCUMENTS:
        fixtures.create_pdf(doc)
    fixtures.create_diary()
    for name, text in [('asthma-context', fixtures.ASTHMA_BODY), ('import-preparation-note', fixtures.IMPORT_TEXT)]:
        (directory / fixtures.source(name, 'txt')).write_text(fixtures.display_text(text))


def main():
    fixtures.pdfmetrics.registerFont(fixtures.TTFont('DemoSans', fixtures.find_font()))
    fixtures.pdfmetrics.registerFont(fixtures.TTFont('DemoSansBold', fixtures.find_font(True)))
    inputs = set()
    def collect(text):
        inputs.add(text)
        return text
    fixtures.display_text = collect
    with tempfile.TemporaryDirectory(prefix='reva-source-layout-') as scratch:
        render(Path(scratch))
    # Reuse the exact TypeScript presentation policy, including its uncertainty-preservation tests.
    program = r"""
import {demoSourceText} from './apps/web/src/core/presentation.ts';
import {readFileSync} from 'node:fs';
const input = JSON.parse(readFileSync(0, 'utf8'));
const clean = text => text === 'SYNTHETIC DEMO - FICTIONAL MEDICAL RECORD' ? 'MEDICAL RECORD' : demoSourceText(text, true)
  .replace('SYNTHETIC DEMO - FICTIONAL MEDICAL RECORD | ', '')
  .replace('Reva Synthetic Fixture Generator', 'Reva')
  .replace('Synthetic raster-only PDF; text requires actual OCR.', 'Image-only document; text requires OCR.')
  .replace('Invented for Reva software demonstration.', '')
  .replace('Not a real patient record or medical advice.', '')
  .replace(/This unseeded sample is intended for a manual import demonstration\. It is\s+not a clinical recommendation or a real patient document\./, '')
  .trim();
process.stdout.write(JSON.stringify(Object.fromEntries(input.map(text => [text, clean(text)]))));
"""
    values = json.loads(subprocess.run(['node', '--input-type=module', '-e', program], cwd=ROOT,
        input=json.dumps(sorted(inputs)), text=True, capture_output=True, check=True).stdout)
    markers = re.compile(r'\b(demo|demonstration|synthetic|fictional|invented|fake)\b', re.I)
    assert all(not markers.search(value) for value in values.values()), 'Unformatted fixture label'
    fixtures.display_text = lambda text: values[text]
    OUTPUT.mkdir(parents=True, exist_ok=True)
    render(OUTPUT)
    seed = json.loads((ROOT / 'demo/seed.json').read_text())
    manifest = {}
    for record in seed['records']:
        path = OUTPUT / record['sourceFilename']
        data = path.read_bytes()
        if record['mimeType'] == 'application/pdf':
            pages = PdfReader(path).pages
            assert len(pages) == record['pageCount']
            assert all(not markers.search(page.extract_text()) for page in pages)
        manifest[path.name] = dict(recordID=record['id'], mimeType=record['mimeType'],
            bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
    (OUTPUT / 'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(f'Generated and verified {len(manifest)} source previews; canonical sources unchanged.')


if __name__ == '__main__':
    main()
