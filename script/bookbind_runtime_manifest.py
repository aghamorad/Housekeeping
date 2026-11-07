#!/usr/bin/env python3
"""Bind the frozen engine to the exact versioned Python/static source."""
import hashlib
import json
from pathlib import Path
import sys


def source_files(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob('*')) if p.is_file() and p.name != '.DS_Store'
            and '__pycache__' not in p.parts}


if __name__ == '__main__':
    action, source, manifest = sys.argv[1:]
    expected = source_files(Path(source))
    path = Path(manifest)
    if action == 'write':
        path.write_text(json.dumps({'python': '3.15.2', 'engine': '1.5.2',
                                    'architectures': ['arm64', 'x86_64'],
                                    'source_files': expected}, indent=2) + '\n')
    elif action == 'verify':
        if json.loads(path.read_text())['source_files'] != expected:
            raise SystemExit('Bookbind source changed: rebuild its universal runtime before packaging.')
    else:
        raise SystemExit('Expected write or verify')
