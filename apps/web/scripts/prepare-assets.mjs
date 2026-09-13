// Purpose: Bundle the existing fictional sources and local OCR runtime for browser use.
// Inputs: Checked-in native demo resources and installed OCR packages.
// Outputs: Generated public/demo and public/ocr directories, ignored by Git.
// Side effects: Replaces only those two generated asset directories.

import { cp, mkdir, readdir, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// MARK: - Reuse the native fixtures without maintaining a second patient dataset
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const demo = path.join(root, 'public/demo');
const ocr = path.join(root, 'public/ocr');
await rm(demo, { recursive: true, force: true });
await rm(ocr, { recursive: true, force: true });
await mkdir(demo, { recursive: true });
await mkdir(path.join(ocr, 'core'), { recursive: true });
await cp(path.resolve(root, '../ios/Reva/Resources'), demo, { recursive: true });
await cp(path.join(root, 'assets/source-previews'), path.join(root, 'public/source-previews'), {
  recursive: true,
});

// MARK: - Serve one local English OCR model and worker; user documents never leave the browser
await cp(path.join(root, 'node_modules/tesseract.js/dist/worker.min.js'), path.join(ocr, 'worker.min.js'));
const core = path.join(root, 'node_modules/tesseract.js-core');
for (const name of await readdir(core)) {
  if (name.endsWith('.wasm') || name.endsWith('.wasm.js'))
    await cp(path.join(core, name), path.join(ocr, 'core', name));
}
await cp(
  path.join(root, 'node_modules/@tesseract.js-data/eng/4.0.0_best_int/eng.traineddata.gz'),
  path.join(ocr, 'eng.traineddata.gz'),
);
console.log('Prepared native demo originals and local English OCR assets.');
