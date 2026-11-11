#!/usr/bin/env python3
"""Verify an extracted, signed release against its tagged source and run both slices.

Run on an Apple Silicon build Mac with Rosetta:
python3 script/verify_release.py archive.zip new-check-directory release-tag
Preserves extracted apps, generated audio and a JSON validation receipt.
"""
from pathlib import Path
import glob
import hashlib
import json
import plistlib
import re
import shlex
import subprocess
import sys

from verify_universal_bundle import verify
from bookbind_runtime_manifest import source_files

root = Path(__file__).resolve().parent.parent
archive = Path(sys.argv[1]).resolve()
checks = Path(sys.argv[2]).resolve()
tag = sys.argv[3]
checks.mkdir(parents=True, exist_ok=False)


def run(*args, timeout=45):
    return subprocess.check_output(list(map(str, args)), text=True, stderr=subprocess.STDOUT,
                                   timeout=timeout).strip()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


run('/usr/bin/ditto', '-x', '-k', archive, checks)
app = checks / 'Housekeeping.app'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
source_info = plistlib.loads((root / 'Housekeeping/Info.plist').read_bytes())
commit = run('git', '-C', root, 'rev-parse', tag + '^{commit}')
assert info.get('HousekeepingSourceCommit') == commit, 'Wrong release source commit'
assert info.get('HousekeepingSourceBaseCommit') == commit, 'Wrong release base commit'
for key in ['CFBundleVersion', 'CFBundleShortVersionString']:
    assert info[key] == source_info[key], f'Wrong {key}'
assert tag == 'v' + info['CFBundleShortVersionString'], 'Tag does not match the packaged version'

block = re.search(r'SOURCES=\((.*?)\n\)', (root / 'script/package_release.sh').read_text(), re.S).group(1)
inputs = []
for token in shlex.split(block):
    inputs.extend(Path(p) for p in sorted(glob.glob(token.replace('$ROOT_DIR', str(root)))))
inputs.append(root / 'Housekeeping/Info.plist')
inputs.append(root / 'script/render_app_icon.swift')
inputs.append(root / 'Housekeeping/Resources/BenignMonster/housekeeper_octopus_maid.png')
cmd = f"shasum -a 256 {' '.join(shlex.quote(str(p)) for p in inputs)} | shasum -a 256 | awk '{{print $1}}'"
digest = subprocess.check_output(cmd, shell=True, text=True).strip()
assert info['HousekeepingSourceDigest'] == digest, f"Packaged Swift/Info inputs differ from checkout ({info['HousekeepingSourceDigest']} vs {digest})"

native_files = verify(app)
run('codesign', '--verify', '--deep', '--strict', app)
engine_root = app / 'Contents/Resources/Bookbind'
manifest = json.loads((engine_root / 'bin/runtime-manifest.json').read_text())
assert manifest['source_files'] == source_files(root / 'Runtime/Bookbind'), 'Stale frozen engine'
for name, checksum in manifest['source_files'].items():
    assert sha(engine_root / name) == checksum, f'Wrong bundled source: {name}'
versions = {}
for architecture in ['arm64', 'x86_64']:
    version = run('/usr/bin/arch', '-' + architecture, app / 'Contents/MacOS/Housekeeping', '--version')
    assert info['CFBundleShortVersionString'] in version and info['CFBundleVersion'] in version, version
    versions[architecture] = version
run(sys.executable, root / 'script/test_bookbind_runtime.py', engine_root / 'bin', checks / 'audio-fixtures', timeout=240)
receipt = {'archive': archive.name, 'sha256': sha(archive),
           'source_commit': commit, 'source_digest': digest,
           'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
           'native_file_count': len(native_files), 'architectures': ['arm64', 'x86_64'],
           'signature': 'verified deep and strict', 'cli_versions': versions,
           'bookbind_smoke': json.loads((checks / 'audio-fixtures/results.json').read_text())}
(checks / 'validation.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({key: receipt[key] for key in ['archive', 'sha256', 'source_commit',
                                              'version', 'build', 'native_file_count', 'architectures']}, indent=2))
print('Signature, source provenance, every native architecture and both actual Bookbind workflows verified.')
