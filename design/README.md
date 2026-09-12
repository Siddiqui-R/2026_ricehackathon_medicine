# Selected palette

`palette.json` is the exact sampled palette from the user's original 447 × 447 sRGB PNG. The six interior 40 × 40 pixel samples exclude swatch borders, shadows, text, and compression/edge artifacts. `scripts/extract_palette.py` reproduces the extraction and records the source SHA-256.

| Name | Exact source RGB | Hex | Reva role |
| --- | --- | --- | --- |
| Ivory | 250, 244, 244 | `#FAF4F4` | Warm app background |
| Gold | 200, 160, 125 | `#C8A07D` | Small decorative accent; not body text |
| Slate | 162, 183, 188 | `#A2B7BC` | Quiet supporting surfaces and dividers |
| Teal | 10, 91, 108 | `#0A5B6C` | Primary actions and selected navigation |
| Aqua | 111, 171, 182 | `#6FABB6` | Secondary accents and illustrations |
| Sky | 225, 236, 238 | `#E1ECEE` | Soft selected/source surfaces |

These are exact pixels in the supplied image, not a claim about a separate original designer file. Preserve these named source colors unchanged. The user reaffirmed these exact values during MVP verification. The shipped MVP uses Ivory canvas, Sky cards, Teal actions and Ivory action text. Gold/Slate/Aqua remain named supporting colors. Derived dark substitutions were removed; the MVP stays in light appearance. Native system text and controls retain readable neutral rendering.

Use Apple Health's readable hierarchy and grouped surfaces. The palette is not an instruction to copy the image's decorative serif typography. SF Pro remains the native app typeface. The earlier A–D color proposals are superseded.
