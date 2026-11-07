#!/usr/bin/env python3
"""Relocate an extracted python.org framework inside the project, without installing it."""
from pathlib import Path
import os
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
prefix = '/Library/Frameworks/Python.framework/Versions/3.15/'
for path in root.rglob('*'):
    if path.is_symlink() or not path.is_file():
        continue
    with path.open('rb') as stream:
        magic = stream.read(4)
    if magic not in (b'\xca\xfe\xba\xbe', b'\xcf\xfa\xed\xfe'):
        continue
    libraries = subprocess.check_output(['otool', '-L', str(path)], text=True)
    dependencies = {line.strip().split(' (compatibility version')[0]
                    for line in libraries.splitlines() if line.startswith('\t')}
    changes = []
    for dependency in sorted(dependencies):
        if dependency.startswith(prefix):
            target = root / dependency[len(prefix):]
            if target != path:
                changes += ['-change', dependency,
                            '@loader_path/' + os.path.relpath(target, path.parent)]
    if changes:
        subprocess.run(['install_name_tool', *changes, str(path)], check=True)
        subprocess.run(['codesign', '--force', '--sign', '-', str(path)], check=True)
