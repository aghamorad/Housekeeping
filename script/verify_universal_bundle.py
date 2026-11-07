#!/usr/bin/env python3
"""Reject thin Mach-O files and dependencies on the build machine.

Scans nested Python extensions and libraries as well as executable entry points.
No software is executed and no files are modified.
"""
import argparse
from pathlib import Path
import struct
import subprocess
import re

MACHO_MAGICS = {0xFEEDFACE, 0xCEFAEDFE, 0xFEEDFACF, 0xCFFAEDFE,
                0xCAFEBABE, 0xBEBAFECA, 0xCAFEBABF, 0xBFBAFECA}


def verify(root):
    root = Path(root)
    paths = [root] if root.is_file() else sorted(root.rglob('*'))
    checked = []
    failures = []
    for path in paths:
        if not path.is_file() or path.is_symlink():
            continue
        with path.open('rb') as stream:
            header = stream.read(4)
        if len(header) != 4 or struct.unpack('>I', header)[0] not in MACHO_MAGICS:
            continue
        arches = subprocess.check_output(['lipo', '-archs', str(path)], text=True).split()
        if set(arches) != {'arm64', 'x86_64'}:
            failures.append(f'{path}: expected arm64 + x86_64, found {arches}')
        libraries = subprocess.check_output(['otool', '-L', str(path)], text=True)
        for line in libraries.splitlines():
            if not line.startswith('\t'):
                continue
            dependency = line.strip().split(' (compatibility version', 1)[0]
            if dependency.startswith('/') and not dependency.startswith(('/usr/lib/', '/System/Library/')):
                failures.append(f'{path}: external dependency {dependency}')
            if dependency.startswith('@loader_path/'):
                target = (path.parent / dependency[len('@loader_path/'):]).resolve()
                if not target.exists() or not target.is_relative_to(root.resolve()):
                    failures.append(f'{path}: missing or external relative dependency {dependency}')
        load_commands = subprocess.check_output(['otool', '-l', str(path)], text=True)
        for block in re.split(r'Load command \d+', load_commands):
            if not re.search(r'\bcmd LC_(?:BUILD_VERSION|VERSION_MIN_MACOSX)\b', block):
                continue
            minimum = re.search(r'^\s+(?:minos|version) (\d+\.\d+(?:\.\d+)?)$', block, re.M)
            if minimum and tuple(map(int, minimum[1].split('.'))) > (13, 0, 0):
                failures.append(f'{path}: requires macOS {minimum[1]}; app supports macOS 13')
        checked.append(str(path))
    if not checked:
        failures.append(f'{root}: no Mach-O programs or libraries found')
    if failures:
        raise ValueError('\n'.join(failures))
    return checked


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('paths', nargs='+')
    args = parser.parse_args()
    try:
        for path in args.paths:
            checked = verify(path)
            print(f'{path}: {len(checked)} universal Mach-O files; no external absolute dependencies')
    except (ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Universal bundle validation failed: {error}\n')
