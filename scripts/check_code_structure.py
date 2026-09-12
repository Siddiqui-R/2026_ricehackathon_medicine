#!/usr/bin/env python3
"""Purpose: Check the required contracts and section markers in first-party Swift source.
Inputs: The native app and server source trees relative to this script.
Outputs: File/line diagnostics and a nonzero exit status when a required marker is missing.
Side effects: None; this check only reads source files.
"""

from pathlib import Path
import re


# Source inventory: explicit roots exclude packages, build output and historical worktrees.
ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOTS = (ROOT / "apps/ios/Reva", ROOT / "server/Sources")
CONTRACT_FIELDS = ("Purpose", "Inputs", "Outputs", "Side effects")


# File contract: require substantive values before imports/declarations, plus named chunks.
def check_source(path: Path) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    header_lines = []
    for line in lines:
        if line.strip() and not line.lstrip().startswith("//"):
            break
        header_lines.append(line)
    header = "\n".join(header_lines)
    relative = path.relative_to(ROOT)
    errors = []
    for field in CONTRACT_FIELDS:
        pattern = rf"^// {re.escape(field)}: \S.+$"
        if not re.search(pattern, header, re.MULTILINE):
            errors.append(f"{relative}:1: missing leading '// {field}: <description>'")
    if not any(re.match(r"\s*// MARK: - \S.+", line) for line in lines):
        errors.append(f"{relative}:1: missing named '// MARK: - <responsibility>' section")
    return errors


# Command boundary: report every affected file so one run can guide the complete correction.
def main() -> int:
    sources = sorted(path for root in SOURCE_ROOTS for path in root.rglob("*.swift"))
    if not sources:
        print("No Swift sources found; check the repository layout.")
        return 1
    errors = [error for path in sources for error in check_source(path)]
    for error in errors:
        print(error)
    if errors:
        print(f"Structure check failed: {len(errors)} missing contracts/sections.")
        return 1
    print(f"Structure check passed: {len(sources)} Swift source files have contracts and named sections.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
