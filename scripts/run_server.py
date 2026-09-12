#!/usr/bin/env python3
"""Start RevaAPI using root .env without shell evaluation or extra dependencies."""
import argparse
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def read_environment(path: Path) -> dict[str, str]:
    values = {}
    if not path.exists():
        return values
    for number, line in enumerate(path.read_text().splitlines(), 1):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('export '):
            line = line[7:]
        key, sep, raw = line.partition('=')
        key = key.strip()
        if not sep or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', key):
            raise ValueError(f'{path.name}:{number}: expected NAME=value')
        parts = shlex.split(raw, comments=True, posix=True)
        if len(parts) > 1:
            raise ValueError(f'{path.name}:{number}: quote values containing spaces')
        value = parts[0] if parts else ''
        if value:  # Empty placeholders do not accidentally enable invalid configuration.
            values[key] = value
    return values


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--env', type=Path, default=ROOT / '.env')
    parser.add_argument('--build', action='store_true', help='Build the Swift server first')
    args = parser.parse_args()
    try:
        config = read_environment(args.env)
    except (OSError, ValueError) as error:
        sys.exit(str(error))
    # Explicit shell environment overrides the optional file; values are never printed.
    environment = {**config, **os.environ}
    server = ROOT / 'server'
    if args.build:
        subprocess.run(['swift', 'build', '-j', '6'], cwd=server, env=environment, check=True)
    binary = server / '.build' / 'debug' / 'RevaAPI'
    if not binary.exists():
        sys.exit('Build first: python3 scripts/run_server.py --build')
    os.chdir(server)
    os.execve(str(binary), [str(binary)], environment)


if __name__ == '__main__':
    main()
