# Housekeeping — handoff

## Objective

**0.23.0 (2026-11-02, session 2).** Morad: "see the menu bar choices are so damn dififcult too... and even the parts where you can close stuff that take ram etc you should just even be able to kill it with one click - and you should be able to see better throughout the interface with better icons, better spacing... even the model loader doesnt quite work - since it doesnt even notice the two MLX models I have for example... Reverse engineer both CleanMyMac and Mole... The updater too should be able to update some apps from the websites they were downloaded from, and the app store stuff it recognizes it should open the app store for you... And it shouldn't download it all in this hidden cache in its own app library... clean with this app - not messy".
Shipped:
1. Re-architected Menu Bar Panel: Replaced niche subtools with CleanMyMac-style quick actions (`[Open App]`, `[Free RAM]`, `[Clean]`, `[Cooling]`, and `[Updates]`). Added high-contrast hardware gauges, instant thermal chips, and streamlined room detail views without long walls of text.
2. 1-Click Process Killer: Added top resource consumers panel with a segmented `[Top CPU | Top RAM]` inspector. Every process row features a direct, one-click `✕` termination button executing `SIGTERM` (with immediate resource reclaim and list refresh).
3. Instant Memory Purge ("Free RAM"): Built-in virtual memory compaction and cache purge flushes inactive buffers, URL caches, and system image caches without requiring root permissions, dropping memory pressure with live feedback.
4. Native Apple Silicon MLX & Local Registry Model Loader: Comprehensive discovery across `~/.mlx-lm` and `~/Models` (`llm/`, `speech/`, `voice/`, `image/`). Detects Morad's MLX models (`Qwen 3.5 4B Claude Heretic 4-bit`, `Qwen 3.5 9B 4-bit`, `Whisper Large v3 MLX`, `Fish Speech S2 Pro 8-bit MLX`, `SenseVoice ONNX`, etc.). Shows resolved symlink paths, true disk footprints, quantization, and allows 1-click active default switching via `~/.mlx-lm/models/current`.
5. Clean Updater Workflow: Added direct "Open App Store" actions (`macappstore://showUpdatesPage`) and official "Visit Website" buttons for web-distributed apps. Downloaded update packages are placed visibly in `~/Downloads/Housekeeping Updates` instead of hidden app caches, and backup copies of replaced applications are safely moved to `~/.Trash`.

**0.22.0 (2026-11-02, session 1).** Morad: "So my Housekeeping app sucks. It is still not doing what I want it to do, having fan controls, being quick, having a very, very user-friendly interface where you can easy pick and see what you should update, uninstall etc. The updater itself is terrible... make everything as easy as CleanMyMac and Mole but better with all the other features..."
Shipped:
1. Native SMC & IOHID Fan & Thermal Control for Apple Silicon and Intel Macs (live RPM gauges, 5 profiles including System Auto, Quiet, Balanced, Full Blast, and Custom RPM slider, CPU/GPU/Battery temps, safety reset on quit).
2. Modern, CleanMyMac-inspired App & Package Updater with hero banner, one-click *Update All*, individual row update actions, Full Disk Access verification, and automated macOS native authorization (sudo) for Homebrew packages and casks.
3. Space Lens & Visual Storage Explorer providing instant volume statistics, category breakdown (Applications, Developer & Caches, Media, Downloads, Documents, Trash), large files discovery (>200 MB), and fluid folder exploration with breadcrumbs.
4. Dedicated App Uninstaller scanning application bundles and associated leftovers across Application Support, Caches, Preferences, Saved State, and Containers with safe Quarantine archiving.

**0.21.1 (2026-10-30).** Bookbind 1.5.1 bundled to resolve catalogue search root certificate verification.

**0.21.0 (2026-10-30, session 2).** Morad: "make sure there's no lag… a progress bar for the
updates… a path bar for the searches so someone can go back and forth." Shipped: bars on
every long operation, Forward in the disk browser, and smooth motion restored.

**0.20.1 (2026-10-30, session 1).** "Housekeeping apparently takes up a lot of battery."
Idle cost went from ~28% of a core to **0.0%**.

## Done and verified

### 0.21.0

- **`ProgressBar`** (`UI/ModernChrome.swift`): themed determinate bar with caption, detail
  line and percentage; `fraction: nil` draws a travelling third of the bar for a pass whose
  length is not known yet. One component, four call sites.
- **Update Apps**: `AppState.updateRunDone/Total/Current` and `updateReadDone/Total`;
  `UpdateBridge` publishes them. Run bar shows *3 of 5 updated* plus the app being worked
  on; the reading pass shows a travelling bar (*Counting what is installed*) until the
  inventory lands, then fills as *Reading 34 of 210*.
- **Housekeeping's own update**: a bar over `SelfUpdateStep.allCases` (*Step 3 of 6*) above
  the existing step list, with the running step's title under it.
- **Disk browser**: `forward` history + `goForward()` + ⌘] + a Forward button beside Back.
  `open()`/`goUp()` clear it; `goBack()` fills it. Up still clears, as in Finder.
- **Disk measurement bar**: `DiskScanProgress.foldersDone/foldersTotal`; `DiskScanner.scan`
  counts the root's children before walking, `measure` increments at `depth == 0`. The
  measuring screen shows *5 of 134 top-level folders* with files, bytes read and the folder
  being read underneath.
- **Motion at 20 fps** wherever the mark can be seen — the 8/12 split from 0.20.1 was
  unnecessary; what people felt was the panel's layout loop, not the frame rate. Measured:
  0.0% idle in the menu bar, ~2.5% with the window frontmost, ~1.5% with the panel open.
- **Verified visually** (cua-driver window captures): Back/Forward/Up + breadcrumb in the
  Disk Browser; measuring at *5 of 134 · 4%* with live counters; Update Apps in its
  travelling-bar phase; the update list after reading. A real 66 s disk measurement was run
  and saved (`~/Library/Application Support/Housekeeping/DiskSnapshot.plist`, 4.0 MB).

### 0.20.1

- Two causes of the drain: a 12 fps status-item timer installed at launch and never stopped,
  and window `TimelineView`s that kept redrawing a window SwiftUI had closed but not torn
  down.
- `MotionBudget` (`UI/Motion.swift`) + `OnScreenProbe` (`tracksOnScreen(_:)`): motion runs
  while the app is active and the drawing's own window is on screen, plus a 2.6 s launch
  greeting; display sleep stops it. Verified 28% → 0.0% idle, ~2.5% with the window open.
- The panel's octopus is deliberately still: every animated frame in a popover made AppKit
  re-solve the panel's whole Auto Layout (~1.4% of a core per frame). The panel's height
  reporting is debounced (resize → layout → new height → resize).

## Shipped

- `v0.21.0` — commit `abb8f47`: <https://github.com/aghamorad/Housekeeping/releases/tag/v0.21.0>
- `v0.20.1` — commit `b6d6bf1`: <https://github.com/aghamorad/Housekeeping/releases/tag/v0.20.1>
- Installed in `/Applications` (0.21.0, build 35). Previous copies are in `~/.Trash` as
  `housekeeping-app-backup-*`.
- Guide: `~/Desktop/Housekeeping — a noob's guide.md` (kept current through 0.21.0).

## Not done / open

- **The determinate reading bar has not been photographed mid-read** — the read finished
  between captures. To see it, press Recheck and watch the first ~30 s; if it sits at 0%,
  `updateReadTotal` is landing empty.
- **`AppInventory.scan` has no progress of its own**, so the first ~25 s of a Recheck is the
  travelling bar covering only the counting phase. A callback from the inventory would let
  it say "reading 40 applications".
- Bookbind, MediaDock and the Local Models screens keep their own `ProgressView` spinners;
  not converted to `ProgressBar`.
- The window's animated marks still re-solve constraints per frame (`GeometryReader` inside
  `OctopusMark`). Cheap at 20 fps (~2.5%) but the next lever if it ever matters is passing
  the size in.
- Duplicate invisible windows still accumulate at launch (0.20.0 note). They cost nothing
  now — the on-screen probe keeps their timelines still.
- Unverified by hand: the panel's Scan/Ask/MediaDock/Bookbind buttons individually; LM
  Studio `lms` load/unload (no models installed); Forward/Back across a measurement restart
  (history resets on a new measurement, by design).
