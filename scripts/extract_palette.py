"""Extract Reva's six exact sRGB swatches from the supplied 447x447 palette image.

Usage: python3 scripts/extract_palette.py /path/to/image-1.png
Requires Pillow. Samples exclude frames, labels, shadows, and swatch edges.
"""
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path
from PIL import Image

source = Path(sys.argv[1])
image = Image.open(source).convert("RGB")
if image.size != (447, 447):
    raise SystemExit("Expected original 447x447 image; do not sample a resized copy.")
boxes = {
    "ivory": (80, 150, 120, 190),
    "gold": (205, 150, 245, 190),
    "slate": (330, 150, 370, 190),
    "teal": (80, 280, 120, 320),
    "aqua": (205, 280, 245, 320),
    "sky": (330, 280, 370, 320),
}
colors = {}
for name, box in boxes.items():
    pixels = list(image.crop(box).getdata())
    rgb, count = Counter(pixels).most_common(1)[0]
    colors[name] = {
        "hex": "#%02X%02X%02X" % rgb,
        "rgb": list(rgb),
        "sample_box_xyxy": list(box),
        "matching_pixels": count,
        "sampled_pixels": len(pixels),
    }
result = {
    "name": "Reva — supplied Luxe & Modern palette",
    "color_space": "sRGB",
    "source_dimensions": list(image.size),
    "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
    "method": "Most frequent exact RGB pixel in each interior sample rectangle; no resampling.",
    "colors": colors,
}
output = Path(__file__).resolve().parents[1] / "design" / "palette.json"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
print(output)
for name, color in colors.items():
    print(name, color["hex"], f'{color["matching_pixels"]}/{color["sampled_pixels"]} identical pixels')
