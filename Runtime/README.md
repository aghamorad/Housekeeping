# Bundled Bookbind runtime

`Bookbind/` is the exact Bookbind 1.5.2 source/static snapshot from
`aghamorad/bookbind`, commit `1619b70`. Housekeeping versions these small inputs
so its frozen engine cannot silently come from a different local checkout.
Bookbind's job-lock fix is included.

Build with `bash script/build_bookbind_runtime.sh` from the Housekeeping root.
It uses only project-local build directories, downloads the signed python.org
3.15.2 universal installer, extracts and relocates its framework without installing
it, installs pinned build requirements there, and freezes a universal2 onedir
engine. The complete `_internal` folder must travel beside `BookbindServer`.
Python, its OpenSSL libraries, every extension and the bootloader contain both
architectures. Do not merge two frozen PyInstaller executables with lipo: their
embedded Python archives would not be merged correctly.

The media inputs are FFmpeg/FFprobe 9.0 static builds, combined into universal
executables and signed. Intel inputs come from `https://evermeet.cx/ffmpeg/`.
The existing Apple Silicon builds originate at `https://www.osxexperts.net/` and
are retained from Housekeeping 0.26.8. Exact download/input checksums are enforced
in the script. The default arm64 input directory is the sibling Bookbind checkout's
`bin`; to build a fresh clone, extract the checksum-pinned 0.26.8 universal release
and set `HOUSEKEEPING_MEDIA_ARM64_BIN` to its
`Housekeeping.app/Contents/Resources/Bookbind/bin` directory, as the release workflow
does. The old frozen BookbindServer/Python from that release is never reused.

FFmpeg build options and linked codecs are available from the bundled executable's
`-version` output. FFmpeg source is at `https://ffmpeg.org/releases/`; vendor build
instructions and external-library sources are linked on the vendor pages above.
Python's license is retained in the bundle's `bin/licenses` folder; Mutagen is GPL-2.0-or-later;
the GPL-enabled FFmpeg builds retain their upstream licensing. Source and build
details remain available alongside this distribution.

`python3 script/verify_universal_bundle.py <bundle-or-runtime-folder>` scans every
native file and rejects missing slices or absolute references to non-system
libraries. `python3 script/test_bookbind_runtime.py <bin-folder> <new-fixture-folder>`
starts isolated child servers, runs actual audio jobs, checks chapters/tags and
restores generated originals on each architecture. On an Apple Silicon build Mac,
the Intel execution check requires Rosetta already installed. It never stops an
existing Bookbind or Housekeeping process. Keep fixtures for inspection.

After runtime/source changes, preserve the old `.build/bookbind-universal` folder
under another name before rebuilding. Packaging verifies the runtime's source
manifest and refuses a stale engine. The release has one universal app/ZIP.
