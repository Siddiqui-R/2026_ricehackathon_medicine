#!/usr/bin/env python3
"""SYNTHETIC DEMO ONLY. Render fixture PDFs for manual visual QA with Poppler.

Purpose: Produce page previews and a contact sheet for visual inspection of generated fictional sources.
Inputs: demo/sources PDFs, a Poppler pdftoppm executable, Pillow, and optional output path.
Outputs: Rendered PNG pages and contact-sheet.png in the selected output directory.
Side effects: Runs Poppler and writes preview/font-cache files without modifying source PDFs.
Boundary: Rendering supports manual layout review; it does not assert extraction accuracy or clinical correctness.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

from PIL import Image, ImageDraw, ImageFont

# --- Resolve the synthetic PDF source library ---
ROOT = Path(__file__).resolve().parent


# --- Resolve renderer/output paths and use a task-local font configuration ---
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="/private/tmp/reva-demo-qa")
    parser.add_argument("--pdftoppm", default=shutil.which("pdftoppm") or str(
        Path.home() / ".cache/codex-runtimes/codex-primary-runtime/dependencies/bin/override/pdftoppm"))
    args = parser.parse_args()
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    # The bundled macOS Poppler may ship a nonportable default fontconfig path.
    # Use a task-local configuration/cache rather than writing the user's cache.
    fonts = Path("/System/Library/Fonts/Supplemental")
    if fonts.exists():
        cache = output / "font-cache"
        cache.mkdir(exist_ok=True)
        config = output / "fonts.conf"
        config.write_text(f'<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd">'
                          f'<fontconfig><dir>{fonts}</dir><cachedir>{cache}</cachedir></fontconfig>')
        env["FONTCONFIG_FILE"] = str(config)
    # --- Render each source with a finite Poppler timeout ---
    for pdf in sorted((ROOT / "sources").glob("*.pdf")):
        result = subprocess.run([args.pdftoppm, "-scale-to", "1500", "-png", str(pdf), str(output / pdf.stem)],
                                env=env, capture_output=True, text=True, timeout=45)
        if result.returncode:
            raise RuntimeError(f"Rendering failed for {pdf.name}: {result.stderr[-2000:]}")
    # --- Assemble a labelled contact sheet for manual visual review ---
    pages = sorted(output.glob("reva-synthetic-*.png"))
    thumb_w, thumb_h, label_h = 380, 492, 55
    sheet = Image.new("RGB", (3 * thumb_w, ((len(pages) + 2) // 3) * (thumb_h + label_h)), "#e1ecee")
    d = ImageDraw.Draw(sheet)
    font_path = "/System/Library/Fonts/Supplemental/Arial.ttf"
    font = ImageFont.truetype(font_path, 13) if Path(font_path).exists() else ImageFont.load_default()
    for i, page in enumerate(pages):
        im = Image.open(page).convert("RGB")
        im.thumbnail((thumb_w - 16, thumb_h - 12))
        x, y = (i % 3) * thumb_w, (i // 3) * (thumb_h + label_h)
        sheet.paste(im, (x + (thumb_w - im.width) // 2, y + 5))
        label = page.stem.replace("reva-synthetic-", "")
        d.text((x + 8, y + thumb_h), "SYNTHETIC | " + label, fill="#1c3036", font=font)
    sheet.save(output / "contact-sheet.png")
    print(f"Rendered {len(pages)} synthetic PDF pages. Contact sheet: {output / 'contact-sheet.png'}")


if __name__ == "__main__":
    main()
