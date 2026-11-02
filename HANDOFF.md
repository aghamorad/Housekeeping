# Housekeeping — handoff

## Objective

**0.24.1 (2026-11-02, session 4).** Morad: "The app's logo shouldn't say Benign Monster Studios - it should be the Octopus that is our main brand mascot and have it dressed in a maids outfit holding all the tools and appliances of the housekeeper... use your own imagegen!!! You have the octopus already you just need to dress it up using your own imagegen!... Remember from now on when it comes to Antigravity/Gemini tasks - you are more than capable to make your own images so you can bypass the other ones (update the skill accordingly too)"
Shipped:
1. Native Mascot Art Generation: Generated official crimson octopus brand mascot in housekeeper maid uniform using native Antigravity `image-generator` subagent (lace cap, white ruffled apron, holding feather duster, spray bottle, vacuum hose, squeegee, sponge, wrench, and fan turbine).
2. macOS Full-Bleed App Icon: Created `AppIcon.icns` and `AppIcon.png` via `script/make_icon.sh` using the maid mascot. Bundled in `/Applications/Housekeeping.app` and `Housekeeping/Resources/`.
3. Native Skill Update: Updated `/Users/Morad/Skills/generate-image/SKILL.md` to establish that under Antigravity/Gemini, agents must directly use the native `image-generator` subagent rather than external browser scripts.
4. Universal Binary Build & Release: Verified Universal multi-architecture fat binary (`arm64` + `x86_64`) packaged in `dist/` and installed cleanly into `/Applications/Housekeeping.app`.

**0.24.0 (2026-11-02, session 3).** Morad: "Can housekeeper also take advantage of our Benign Monster brand? Like Benign Monster Works, we can call it? /Users/Morad/Desktop/BMP/afaedd61-c32a-4a0b-a308-26727bf2fc0a.png '/Users/Morad/Desktop/BMP/Brand Identity'... definitely give Housekeeper all these capabilities and superpowers... welcoming, friendly... animated and shiny and professional looking... easy to navigate menus... updater should have one for apps, for homebrew, for unknown origins, with select all, ignore list, right click check in finder... intuitive, something that a 72 year old dad could even use... available for both kinds of Macs; intel and silicon obviously; as universal as can be."
Shipped:
1. Benign Monster Works Brand Integration: Mascot artwork (`mascot.png`, `badge.png`), welcoming hero banner, and clear studio provenance ("Made by Morad · Benign Monster Works").
2. 5-Room Dad-Simple Navigation: Simplified sidebar to 5 primary rooms (Dashboard, Clean Up, Update Apps, Uninstall Apps, Cooling & Fans). Organized specialized power tools under an expandable "Advanced Tools" drawer.
3. Zombie & Runaway Process Watchdog: Real-time detection of high-CPU runaway loops (>60% CPU for >3m or script interpreters >75%) and sleep inhibitors (`caffeinate`) with a 1-click `[Stop Task Now]` button.
4. Modern Developer & AI Cache Cleaner: Scans and purges `~/.cache/uv`, `~/.cache/huggingface/hub`, `~/.cache/mlx-vlm`, `~/.cache/codex-runtimes`, Apple Music `AMPArtworkAgent` album art cache, and app updater caches.
5. 3-Tab Intuitive Updater: Dedicated tabs for `Mac Apps`, `Homebrew Tools`, and `Unknown Origins`, plus quick `[Select All]` / `[Deselect All]` controls, an `Ignore List`, and right-click `Reveal in Finder` on all rows.
6. Universal Binary (`arm64` + `x86_64`): Native compilation and lipo packaging for Apple Silicon and Intel Macs.

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

---

## Cross-Agent Handoff: Orphan Scanner, Zombie TCC Purger & Least-Privilege Engine (2026-11-02, session 4)

**Morad Directive:**
> "also check for oprhans for me and delete those orphans too - remember to talk to our other agent so that all these things can be implemented in our housekeeping app"

**Background & Live Findings from System Security Audit:**
During a deep macOS privacy and permissions audit, we found that when apps are moved to Trash, macOS leaves behind:
1. **Orphaned App Leftovers:** 40 leftover directories/caches across `~/Library/Application Support`, `~/Library/HTTPStorages`, `~/Library/WebKit`, `~/Library/Caches`, `~/Library/Containers`, and `~/Library/Group Containers` from apps deleted long ago (CleanMyMac, Zoom, Raycast, Bartender, Ice, Immersed, BetterDisplay, DiskDrill, Malwarebytes, Smooze, etc.).
2. **Zombie TCC Permissions in `TCC.db`:** 51 security grants in `/Library/Application Support/com.apple.TCC/TCC.db` granting Full Disk Access, Screen Recording, Accessibility, and Endpoint Security to bundle identifiers of deleted applications (e.g. Hubstaff screen recording, Zoom FDA, uninstalled VPNs).
3. **Orphaned Root LaunchDaemons & Helper Tools:** Root background services registered in `/Library/LaunchDaemons/` and `/Library/PrivilegedHelperTools/` running continuously or scheduled at boot even though the parent `.app` is gone (e.g., `com.macpaw.CleanMyMac5.Agent` running as root PID 83275, AlDente Pro helper, Western Digital helper, Tuxera NTFS agent).
4. **Active App Over-Permissioning:** Active apps holding unnecessary high privileges (e.g., Microsoft Word with Full Disk Access, AnyDesk with Full Disk Access, Logitech holding Full Disk Access + Screen Recording).
5. **Sudoers Bypass:** `/etc/sudoers.d/mole` granting passwordless root execution to `/Library/Mole/mole-admin *`.

**Specifications to Implement in Housekeeping (Swift Engine & UI):**

1. **`OrphanScanner` (Enhance Clean Up / App Uninstaller Room):**
   - File: `Housekeeping/Sources/Cleaner/OrphanScanner.swift` (new or extension to `Uninstaller.swift`).
   - Walk candidate directories: `~/Library/Application Support`, `~/Library/Caches`, `~/Library/Containers`, `~/Library/Group Containers`, `~/Library/HTTPStorages`, `~/Library/WebKit`, `/Library/Application Support`.
   - Resolve bundle ID or app name; verify whether any installed application bundle exists via `NSWorkspace.shared.urlsForApplications(toOpen:)` or Spotlight `mdfind 'kMDItemCFBundleIdentifier == ...'`.
   - If missing, aggregate size and present in UI under a dedicated **"Orphan Leftovers"** filter/section in Clean Up with 1-click safe move to `~/.Trash`.

2. **`DaemonWatchdog` (Background Services & Helpers):**
   - Scan `/Library/LaunchDaemons`, `/Library/PrivilegedHelperTools`, `/Library/LaunchAgents`, and `~/Library/LaunchAgents`.
   - Parse plists for `Program` / `ProgramArguments`.
   - Check if executable exists or if parent application exists in `/Applications`.
   - Flag orphaned root daemons with an alert chip (e.g., "Leftover Root Daemon — Parent App Missing") and provide 1-click disable/unload and trash.

3. **`TCCPrivacyManager` (Permissions & Least-Privilege Advisor):**
   - Read `/Library/Application Support/com.apple.TCC/TCC.db` (read-only SQLite query, world-readable on macOS).
   - Cross-reference client identifiers with installed apps.
   - Flag **Zombie Grants** (uninstalled apps still holding Screen Recording, Full Disk Access, Accessibility).
   - Flag **Least-Privilege Warnings** (e.g. Microsoft Word with Full Disk Access, Logitech with Screen Capture).
   - Provide a 1-click `Fix / Revoke` button executing `/usr/bin/tccutil reset <Service> <bundle_id>` for installed apps, and an administrative helper/script to purge dead database rows.

4. **`SudoersAudit`:**
   - Check `/etc/sudoers.d/` for non-standard `NOPASSWD` rules (e.g. Mole) and flag them in the Security/Protection drawer.

