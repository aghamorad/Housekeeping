#!/usr/bin/env python3
"""Exercise the actual frozen engine on both architectures using generated audio.

Usage: python3 script/test_bookbind_runtime.py /path/to/bin /new/fixture/directory
Only the test's own child servers are stopped. Fixture files are retained.
Intel execution on Apple Silicon requires an existing Rosetta installation.
"""
import hashlib
import json
import math
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import wave

bin_dir = Path(sys.argv[1]).resolve()
fixtures = Path(sys.argv[2]).resolve()
fixtures.mkdir(parents=True, exist_ok=False)
results = []


def run(arch, tool, *args):
    return subprocess.check_output(['/usr/bin/arch', '-' + arch, str(bin_dir / tool), *map(str, args)],
                                   text=True, stderr=subprocess.STDOUT, timeout=45)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


for architecture in ['arm64', 'x86_64']:
    for tool in ['ffmpeg', 'ffprobe']:
        assert run(architecture, tool, '-version').startswith(tool + ' version')
    folder = fixtures / architecture
    folder.mkdir()
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('PYTHON', 'DYLD_'))}
    env.update(PATH=str(bin_dir) + ':/usr/bin:/bin', BOOKBIND_PORT=str(port),
               BOOKBIND_PARENT=str(os.getpid()), PYTHONUNBUFFERED='1')
    with (folder / 'server.log').open('w') as log:
        server = subprocess.Popen(['/usr/bin/arch', '-' + architecture, str(bin_dir / 'BookbindServer')],
                                  cwd=folder, env=env, stdout=log, stderr=log)

        def request(path, body=None):
            data = json.dumps(body).encode() if body is not None else None
            req = urllib.request.Request(f'http://127.0.0.1:{port}{path}', data=data,
                                         headers={'Content-Type': 'application/json'})
            with urllib.request.urlopen(req, timeout=3) as response:
                payload = response.read()
            return json.loads(payload) if path.startswith('/api/') else payload

        try:
            deadline = time.monotonic() + 30
            while True:
                try:
                    health = request('/api/health')
                    break
                except OSError:
                    assert server.poll() is None, (folder / 'server.log').read_text()
                    if time.monotonic() > deadline:
                        raise TimeoutError('Frozen Bookbind did not become ready')
                    time.sleep(0.1)
            assert health['version'] == '1.5.2', health
            assert health['pid'] == server.pid, health
            assert b'<html' in request('/').lower(), 'Bundled static page missing'
            jobs = []
            for mode in ['transcode', 'aac-copy']:
                book = folder / mode
                book.mkdir()
                sources = []
                for index, frequency in enumerate([440, 660], 1):
                    wav = book / f'{index:02}.wav'
                    with wave.open(str(wav), 'wb') as audio:
                        audio.setparams((1, 2, 44100, 0, 'NONE', 'not compressed'))
                        audio.writeframes(b''.join(struct.pack('<h', int(8000 * math.sin(2 * math.pi * frequency * n / 44100)))
                                                   for n in range(88200)))
                    if mode == 'aac-copy':
                        m4a = book / f'{index:02}.m4a'
                        run(architecture, 'ffmpeg', '-nostdin', '-v', 'error', '-i', wav, '-c:a', 'aac', m4a)
                        # Keep generated WAVs outside the selected folder.
                        wav.rename(folder / f'generated-{index}.wav')
                        sources.append(m4a)
                    else:
                        sources.append(wav)
                originals = {p.name: digest(p) for p in sources}
                scan = request('/api/scan?' + urllib.parse.urlencode({'path': book}))
                assert scan['count'] == 2 and scan['secs'] >= 3.9, scan
                started = request('/api/start', {'folder': str(book), 'author': 'Runtime Test',
                                                'title': mode, 'year': '2026', 'bitrate': 96})
                job_id = started['job']['id']
                deadline = time.monotonic() + 60
                while True:
                    job = next(j for j in request('/api/jobs')['jobs'] if j['id'] == job_id)
                    if job['state'] in ['done', 'failed', 'cancelled']:
                        break
                    if time.monotonic() > deadline:
                        raise TimeoutError(f'Bookbind job stalled: {job}')
                    time.sleep(0.1)
                assert job['state'] == 'done', job
                output = Path(job['out'])
                probe = json.loads(run(architecture, 'ffprobe', '-v', 'error', '-show_chapters',
                                      '-show_format', '-of', 'json', output))
                assert len(probe['chapters']) == 2, probe
                assert abs(float(probe['format']['duration']) - 4) < 0.4, probe
                assert probe['format']['tags']['artist'] == 'Runtime Test', probe
                assert all((book / '_originals' / name).exists() for name in originals), job
                restored = request('/api/restore', {'id': job_id})
                assert restored['ok'], restored
                assert all(digest(book / name) == sha for name, sha in originals.items())
                assert not output.exists(), 'Fixture restore left the generated output behind'
                jobs.append({'mode': mode, 'chapters': 2, 'duration': probe['format']['duration'],
                             'completed': True, 'restore_original_hashes': 'match'})
            results.append({'architecture': architecture, 'health': health, 'jobs': jobs})
            print(f'{architecture}: frozen server, static page, scan, transcode, AAC copy, chapters, tags and restore passed', flush=True)
        finally:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)

(fixtures / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
