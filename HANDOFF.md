## Current work — 2026-11-06 — 0.26.5 (45): Clean Up swept user data

Objective: stop Clean Up offering things that are not junk. Trigger: a sweep on
2026-11-06 14:08 UTC moved 393 items out of the home folder, including the whole
Hugging Face model cache (25.4 GB), the Draw Things container (7.3 GB, its image
models), Voice Memos recordings back to 2019 (1.8 GB), the Notes database,
Contacts, Office group containers, and /Applications/ChronoSync.app.

Root causes fixed (commit 671aa9d, pushed to main):
- OrphanScanner matched system prefixes against the raw container name, so
  `group.com.apple.*` and TeamID-prefixed containers (`UBF8T346G9.Office`)
  never matched and became "orphans". Containers are now unwrapped via
  `matchName` before matching, and any name containing `com.apple.` is skipped.
- New `Housekeeping/Sources/Cleaner/ModelStorageGuard.swift`: refuses known
  model roots and any tree holding weight files > 8 MB. Wired into
  OrphanScanner and into every shelf in `CleanerScanner.scanAll`, which counts
  what it withheld and says so in the Clean Up notes.
- `sizeToRecord` measured a directory's own entry, not its contents (96 B for a
  3 GB library). Now walks the tree and sums allocated bytes.
- `quarantineRepairs` takes a per-path `categories` map; CleanerModel fills it
  so the manifest records the shelf each item came from.

Verified: typecheck clean; `script/test_safety.sh` — 299 assertions pass
(3 new: model-library detection, group-container name unwrapping, recursive
recorded size). Release built and installed to /Applications/Housekeeping.app,
relaunched.

Recovery state: complete. 207 items restored by hand, the rest through the app:
`open -n -a /Applications/Housekeeping.app --args quarantine restore --yes`
works where a shell cannot, because macOS attributes the Full Disk Access
grant to the app when LaunchServices starts it, and to the terminal when a
shell does. Verified live — Voice Memos (140 recordings), Notes, Contacts,
Office, HF cache (24 GB), Draw Things (7.3 GB), ChronoSync.app.

Two containers macOS had already recreated could not be restored as whole
items, because the app refuses to overwrite an existing path. Notes was put
back file by file instead: a manifest was written pointing at the surviving
files inside the quarantine with their live destinations, and the app's own
restore moved them in (`NoteStore.sqlite`, 25 MB, original mtime intact).

16 items (7.48 GB) remain held and all are download caches — npm, gradle, uv,
npx, codex-runtimes, the DeepSeek updater, Apple Music artwork.

Next: verify a fresh Clean Up scan no longer lists any model folder, and that
the note 'Left alone: N AI model libraries' appears.

# Housekeeping — handoff

## Current work — 2026-11-06 — Release 0.26.4 (44)

Publication authorized by Morad. Preparing a new release from main with all changes since 0.26.0.

- Background Activity now provides Recommendations, Running Now, Startup Files and Background Permissions. Scans are manual, asynchronous and bounded; no new persistent service is installed.
- Housekeeper's “What can I do without?” review works without an AI model. It combines measured evidence with remembered use choices, explains consequences, and distinguishes Keep, Optional, Unneeded, Likely leftover and Unknown. High resource use alone never establishes dispensability.
- Verified optional widgets support confirmed pause/restore with saved elections and exact identity/path checks. Unknown widgets cannot become whole-app uninstall targets. App removal remains in the existing uninstaller; startup removal revalidates the exact candidate.
- RouteSweep remains within Housekeeping. ExpressVPN supports local MCP with Keychain storage, loopback-only transport, bounded JSON/SSE handling, explicit readiness checks and no CLI retry after a failed MCP mutation. Existing CLI support also recognizes the bundled executable.
- Registered all app Swift sources in the Xcode project, including previously omitted files. VPN process presence alone no longer proves a routing conflict.
- Validation: 291 safety/conversation assertions and 85 background/recommendation/MCP assertions passed. Both optimized architectures and GUI typecheck passed with warnings treated as errors. Fake-server tests did not change a live VPN. Native visual interaction remains unverified.
- Tested local universal bundle preserves embedded Bookbind, media tools and llama-server. Release packaging must preserve these resources, record the release commit, verify signatures and publish checksums for all three architecture downloads.

Release status: in progress. First 0.26.3 runner exposed older-compiler errors in existing code: private stored property restricted the synthesized DiskScanner.Context initializer; AppUpdateEngine shadowed its download method with a local binding. Added explicit initializer and renamed the local. Shipping as 0.26.4 (44), keeping the earlier unpublished tag immutable. Next: validation, runner build, verify assets and publish. Machine-specific audit evidence and rollback paths remain in the local workspace checkpoint rather than this repository.

## Objective

**0.26.0 Universal Housekeeper Intelligence & Expandable Usage (2026-11-04).** Morad: "should be scrollable and expandable too - the usage part for all our stuff - right now, it is neither - right click should always allow you throughout the app to ask your housekeeper too - whenever you're done and debugged and leaned our code (also a rule and a skill for all our apps), then push over to github and package as a NEW RELEASE"
Shipped:
1. Universal Right-Click "Ask the Housekeeper" (`.contextMenu`):
   - Added `HousekeeperTopic.ask(_ topic:)` backed by `WindowOpener.shared.withWindow` so right-clicking items anywhere in the app immediately brings up the main window and asks the AI Housekeeper with a tailored briefing.
   - Menu Bar popover: Right-click room cards, `consumerRow`, and `detailHand` to ask about rooms or specific processes.
   - App Uninstaller (`UninstallerModernView.swift`): Right-click any installed application or leftover component to ask about its purpose and deletion safety.
   - Local AI Models (`ModelsView.swift`): Right-click any model to ask about its callers, runtime intersections, and necessity status.
   - Space Lens & Disk Browser (`SpaceLensView.swift`, `DiskBrowserView.swift`): Right-click any file, folder, or heavy node to ask about its contents.
   - VPN Profiles & Interfaces (`VPNTunnelsView.swift`): Right-click any VPN profile or daemon to ask about its configuration and routing impact.
2. Smoothly Scrollable & Expandable Resource Consumers:
   - Replaced fixed/clipped list with an always-scrollable `ScrollView(.vertical, showsIndicators: true)` with bounded heights.
   - Added interactive `[Expand (X)]` / `[Compact]` toggle button: expands the view from 138pt to 280pt to view all active processes without clipping the bottom row.
   - Updated Processor, Memory, and Battery room detail pages with always-scrollable views and expansion toggles.
3. Enhanced Process Icon & Fallback Resolution:
   - Added `/System/Library/CoreServices` to search paths, resolving native icons for Finder, Dock, etc.
   - Added fast-path resolution for Safari / WebKit helper processes.
   - Fixed slice indexing in `ProcessIconProvider` (`..<appRange.upperBound`).
4. Quality & Verification:
   - Strict 0-compiler-warning type check passed (`typecheck.sh`).
   - All 282 safety assertions passed (`test_safety.sh`).
   - Packaged universal fat binaries (`arm64` + `x86_64`) into `dist/`.
   - Installed build into `/Applications/Housekeeping.app` and verified live operation.
   - Created GitHub Release `v0.26.0` with assets and release notes.

**0.25.0 Senior-Friendly Menu Bar Panel Ergonomics & Human Process Intelligence (2026-11-04).** Morad: "see - this doesnt quite work with our 72 year old rule right? it even intimidates me! even though I want it to be just as helpful. I want it still to be intuitive... everything - the spacing especially in the menu bar icon is really, really tight, like this... see, disk usage and stuff... further more, you see how little the fonts are, and how cramped everything is - i also should be able to expand and see all the stuff taking up my memory you know? to make it more pleasing to the eye, i dont mind for each process shown even in the menu bar drop-down - for ram and shit, all of them to have little icons next to them - not only would it make them pleasing on the eye, but also gives it more space. the fonts should also be bigger, not so cramped - it is hard on the eyes. we want something balanced... when you finish, just update the last release honestly; you don't need to go through the release page thing again."
Shipped:
1. Universal Senior Ergonomics (The 75-Year-Old Rule) & Calming Visual Hierarchy:
   - Eliminated sysadmin / airplane-cockpit cognitive overload by restructuring the popover into a warm, welcoming interface accessible to an Iranian grandparent.
   - Welcoming Health Verdict: Replaced cryptic numbers (`Busy · 76`, `Crowded · 54`) with human-first reassuring verdicts: "Mac is Healthy" ("Everything is running smoothly"), "Mac is Busy" ("A few apps are working hard"), and "Needs Attention" ("Memory or disk is getting crowded"), paired with the warm octopus housekeeper mascot and circular health ring.
   - Clean Device Summary: Replaced 6 truncated, overflowing pills (`M1 Pro`, `16.0...`, `macOS 2...`, `up 7d...`, `45°C`, `1518 R...`) with a single, un-truncated specs line: `💻 Apple M1 Pro · 16 GB RAM · macOS Sequoia` plus a neat live thermal badge `[🌡️ 45°C]`.
   - Calm 2×2 Core Essentials Grid: Focused primary attention on the 4 metrics normal users care about: Memory (with 1-tap `[Free]` button), Disk Storage, Processor, and Battery / Cooling. Replaced jittery sparklines on Memory with a calm, colored `MeterBar` consistent with Disk and Battery.
   - Progressive Disclosure for Advanced Sensors: Jittery network throughput (KB/s) and graphics load (GPU %) are tucked behind an intuitive toggle: `[ Show Network & Graphics ∨ ]`, keeping the popover calm for seniors while remaining 1 tap away for power users.
2. Authentic macOS Application Icons & Senior-Friendly App Names:
   - High-Resolution Multi-Tier Process Icons (`ProcessIconProvider` & `ProcessIconView`): Resolves authentic icons at 24×24 pt (main popover) and 22×22 pt (detail drilldowns) via `NSRunningApplication`, binary path traversal (`proc_pidpath`), `NSWorkspace` app matching, and fast-path system resolution for Safari, Finder, Telegram, Codex, ChatGPT, etc.
   - Senior-Friendly App Names & Subtitles: Replaced scary bundle identifiers like `com.apple.WebKit.WebContent` and `cua-driver` with human names ("Safari Web Pages", "Finder", "AI Desktop Assistant", "Codex", "Telegram", "ChatGPT") and category subtitles ("Open Browser Tabs", "Desktop & Files", "Desktop Automation", "Code Editor", "Messaging").
3. Interactive Memory & Process Expansion Controls:
   - Increased capture buffers in `SystemVitals.swift` to 20 busy processes and 35 memory holders.
   - Main popover Top Consumers features `[Show all apps using memory (X) ∨]` expanding into a smooth scrollable list (`maxHeight: 260`) so users can inspect *everything* taking up RAM without clipping or leaving the popover.
   - Memory Room detail page features `[Expand All (35)]` scrollview (`maxHeight: 320`) showing all memory holders with 1-click Quit buttons.
   - Defaulted process consumer tab to `Memory` (with `Processor` as secondary tab).
4. Senior-Ergonomic Tactile Door Buttons:
   - Reorganized cramped 5-button row into 4 generous, tactile buttons (`Free RAM`, `Clean Clutter`, `Cooling`, `Open App`) with minimum hit targets of 85×52 pt.
   - Moved `Updates` into the footer utility row alongside `Open at login` and `Quit`.
5. In-Place Release & Verification:
   - Verified 0 warnings with `typecheck.sh` (`-warnings-as-errors`).
   - Passed all 282 safety assertions with `test_safety.sh`.
   - Packaged universal fat binaries (`arm64` + `x86_64`) via `package_release.sh`.
   - Installed into `/Applications/Housekeeping.app` and restarted.
   - Updated GitHub Release `v0.25.0` assets in-place via `gh release upload v0.25.0 ... --clobber`.
   - Updated beginner guide at `~/Desktop/Housekeeping — a noob's guide.md`.

**0.25.0 Intersection & AI Runtime Engine Update (2026-11-03, session 2).** Morad: "Okay, delete the leftovers that we dont need at all please, i beg you - and add this to our housekeeping app to that it does this too - tell you which intersects with what and what is necessary - it should remain the same release just updated"
Shipped:
1. AI Tool Intersections & Necessity Intelligence:
   - Evaluates dependency mapping for every model & runtime on the Mac (`LocalModels.swift` `evaluateNecessity`):
     - Draw Things (7.3 GB FLUX.2 Klein 4B 6-bit): Tagged `NECESSARY` with active callers `Jeopardy (generate_image.sh)`, `Agent Skill (generate-image)`, and `draw-things-cli`.
     - Apple Silicon MLX Models: Tagged `NECESSARY` with callers `Hermes (hermes-local 4b/9b)`, resident LaunchAgent `:18434`, `DeepSeek Harness`, and `~/Models/llm`.
     - Whisper, SenseVoice, Silero VAD, Fish Speech, Apple Depth Pro: Tagged `NECESSARY` with exact caller applications (`VoiceStudio.app`, `DeepSeek Harness.app`, `Madavi`).
     - Standalone engines (Parakeet TDT, OmniVoice, Meta NLLB-200, Ollama): Tagged `OPTIONAL` with clear usage rationale.
     - Unused/Orphaned runtimes: Tagged `EXTRA / ORPHANED` (e.g. `ComfyUI` with 0 generation checkpoints, or uninstalled host apps like `LM Studio` leaving `~/.lmstudio`).
   - Integrated safe 1-click `[🗑 Trash]` action (`FileManager.default.trashItem(at:resultingItemURL:)`) moving leftovers safely to `~/.Trash`, plus `[↗ Reveal in Finder]`.
   - Accurate size calculation combining `.ckpt` weight files and `-tensordata` storage (`fileOrDirectorySize`).
2. Interactive Filter Bar & High-Contrast Visual Stencils (`ModelsView.swift`):
   - Added filter pills with dynamic item counters: `All`, `Necessary`, `Optional`, `Extra / Orphaned`.
   - Distinct system badges with icons: green `checkmark.shield.fill` (`NECESSARY`), neutral `info.circle` (`OPTIONAL`), amber `exclamationmark.triangle.fill` (`EXTRA / ORPHANED`).
   - Horizontal capsule tags displaying exact system intersections (`INTERSECTS:`).
   - Plain-language explanation text under each item detailing why it is needed or why it is safe to clean.
3. User Home Orphaned AI Cache Scanner (`OrphanScanner.swift`):
   - Expanded Clean Up's "Orphaned Leftovers" scanner to detect root dot-directories of uninstalled AI applications (`~/.lmstudio`, `~/.comfyui`, `~/.cache/comfyui`).
4. Machine Leftovers Purge:
   - Moved inactive `~/C3PO/Tools/ComfyUI` (3.1 GB, 0 checkpoints) to `~/.Trash`.
   - Moved orphaned `~/.lmstudio` (2.0 GB uninstalled app cache) to `~/.Trash`.
   - Removed dead `~/Models/llm/nomic-embed-text-v1.5` symlink to `~/.Trash` and updated `~/Models/MODELS.md`. Total freed: ~5.1 GB.
5. In-Place Release Packaging & Verification:
   - Verified zero compiler warnings (`./script/typecheck.sh`), passed 282 safety assertions (`./script/test_safety.sh`).
   - Built fat universal binary (`arm64` + `x86_64`) via `package_release.sh`.
   - Installed into `/Applications/Housekeeping.app` (verified running, PID 19554).
   - Retained release `v0.25.0` in place per instruction.

**0.25.0 Update (2026-11-03).** Morad: "two things - one can this be the Housekeeping menu bar template Icon? and the other be the release banner in the latest release to be updated? (not a new release but just updating the previous release) '/Users/Morad/Desktop/git release banner.png' '/Users/Morad/Desktop/menu bar template Icon.png'"
Shipped:
1. Custom Menu Bar Template Icon (`menu_bar_template.png`, `.tiff`, `@2x`, `@3x`):
   - Converted Morad's hand-crafted icon into a native macOS multi-representation cut-paper stencil template.
   - Handled negative space: body/head/dress remain solid alpha stencil; cap puffs, eyes, apron, collar are transparent cutouts so macOS dynamic appearance tinting (Light & Dark mode) highlights facial & clothing details crisply with zero clipping.
   - Updated `HousekeeperMascot.swift` and `StatusItemController.swift` to load the template; stopped idle loop timer when static template icon is active, lowering idle CPU overhead to an absolute 0.0%.
   - Updated installed `/Applications/Housekeeping.app` bundle resources and committed master & multi-resolution assets to `Housekeeping/Resources/BenignMonster/`.
2. GitHub Release v0.25.0 Banner Update:
   - Uploaded `git release banner.png` to GitHub Release `v0.25.0` assets via `gh release upload v0.25.0 docs/images/release_banner.png --clobber`.
   - Updated release notes header with full-width `<img src="https://raw.githubusercontent.com/aghamorad/Housekeeping/main/docs/images/release_banner.png" width="860" alt="Housekeeper 0.25.0 Release Banner" />` via `gh release edit v0.25.0 --notes-file RELEASE_NOTES_v0.25.0.md`.
   - Kept release at `v0.25.0` without creating a new release or tagging a redundant version.
   - Synchronized `README.md` and created `releases/v0.25.0.md`.
   - Created beginner guide at `~/Desktop/Housekeeping — a noob's guide.md`.

**0.24.1 (2026-11-02, session 4).** Morad: "The app's logo shouldn't say Benign Monster Studios - it should be the Octopus that is our main brand mascot and have it dressed in a maids outfit holding all the tools and appliances of the housekeeper... use your own imagegen!!! You have the octopus already you just need to dress it up using your own imagegen!... Remember from now on when it comes to Antigravity/Gemini tasks - you are more than capable to make your own images so you can bypass the other ones (update the skill accordingly too)... And don't push anything yet until we check and see what needs working on still please... For example, the uninstaller (and all the other options in the app) doesn't have organize by size, by date, by modified , by name etc. which is central... the uninstaller button doesnt have an icon either - make sure everything has a nice icon you know?... and when is ee such a thing when checking my ram - maybe i can see what swift-run-end is according to the housekeeping knowledge (made better if I enable its local AI) while also it telling me what app it is connected to... The icon is terrible btw - it is not what it is supposed to be - let me make it myself and i'll share it with you... there you go - /Users/Morad/Desktop/30e46a86-0c5a-4a6f-ab23-6bb3f8d430ee.png... can you also add this as a feature too - that it does the damaaged file repair gatekepeer thing? like one of the app options? '/Applications/Damaged Repair Tool'... BTW Benign Monster Works shouldnt be littered - its just the studio that made this technically... Also battery health maangment is also a good feature to have in this... Before you commit it, debug and troubleshoot and make sure everything is in perfect working order... the storage is wrong btw - it says that i have only that many gbs of apps when there is much much more... Also, the housekeeper can have a transparent background - the icon i mean - it doesnt need to be boxed in - the housekeper should also have its logo updated in the menu bar... also, there should be an option here to see the leftovers... also - i want one that shows how many vpn tunnels are installe dand running because sometimes that can really confuse the computer so its good to have a list - with the option to delete them... also, menu bar item should be consistent with all the other buttons up there in form and style... Oh man - this is bad. Like MediaDock and BookBind should be part of this app - same with all the other features. They should not need a separate app. This is a kitchen-sink app after all. Full bundle."
Shipped:
1. Native Monochrome Menu Bar Consistency & Unboxed Mascot:
   - Preserved natural transparent background on Morad's hand-crafted housekeeper octopus mascot (`/Users/Morad/Desktop/30e46a86-0c5a-4a6f-ab23-6bb3f8d430ee.png`) across all resolutions.
   - Removed artificial rounded squircle clipping, borders, and solid backdrop boxes from `OverviewView.swift`, `ContentView.swift`, and `script/prepare_icon.swift`.
   - Status Item Menu Bar Consistency (`StatusItemController.swift`): Replaced colored raster image with native vector cut-paper monochrome template icon (`OctopusSilhouette` with `isTemplate = true`). macOS automatically applies dynamic appearance tinting (pure white in dark menu bar, dark graphite in light menu bar, inverted white highlight on click), matching the exact form, weight, and visual style of adjacent Wi-Fi, Bluetooth, Time Machine, and battery buttons.
   - Popover & In-App Identity: Retained full-colour unboxed maid mascot in `MenuBarPanel.swift` header (44×44 pt), `OverviewView.swift`, and `ContentView.swift`.
2. Accurate Space Lens Category Calculation (`SpaceAnalyzer.swift`, `SpaceLensView.swift`):
   - Replaced flawed directory-inode resource sizing with parallel, asynchronous kernel-level `duBytes` traversal measuring full bundle contents across `/Applications`, `/Applications/Utilities`, and `~/Applications` (accurate 92.2 GB).
   - Removed premature 20,000-file iteration limit on `Documents` (accurate 218 GB).
   - Removed `skipsPackageDescendants` in Trash scan so moved `.app` bundles reflect real trash size.
   - Removed artificial synthetic fallback floors (`12 GB`, `18 GB`, etc.).
   - Integrated fast Spotlight query (`mdfind "kMDItemFSSize > 209715200"`) for Big & Old Files (>200 MB), yielding 50 ms queries.
   - Added progressive loading states with mini `ProgressView` and clickable category cards jumping directly into the folder browser.
3. Battery Health & Power Management (`BatteryHealthEngine.swift`, `BatteryHealthModels.swift`, `BatteryHealthView.swift`):
   - Real-time hardware telemetry: Cycle count, design capacity vs full charge capacity, wear loss in mAh, health %, temperature, voltage, wattage, and condition (Normal, Service Recommended, etc.).
   - Sleep inhibitor detection: Identifies active assertions (`PreventUserIdleSystemSleep`, `NoDisplaySleepAssertion`) and flags non-system apps (Chrome, DaVinci Resolve, caffeinate) preventing Mac sleep.
   - Optimized battery charging status & power adapter watt rating.
4. App Doctor & 'Damaged' App Gatekeeper Fixer (`AppRepairEngine.swift`, `AppRepairModels.swift`, `AppRepairView.swift`):
   - 1-click repair of "‘AppName’ is damaged and can't be opened. You should move it to the Trash" and "Unidentified Developer" Gatekeeper rejections.
   - Strips `com.apple.quarantine` and extended provenance/download tags (`xattr -cr`).
   - Ensures binary user execution permissions (`chmod -R u+w,u+x Contents/MacOS`).
   - Ad-hoc code re-signs application and nested frameworks/dylibs (`codesign --force --deep --sign -`).
   - Drag-and-drop zone + native `[Choose App from Disk…]` file picker.
   - Quarantined apps shelf automatically detects apps in `/Applications` holding quarantine flags (e.g. LibreOffice) with individual and batch `[Repair All]` actions.
   - Context-menu integration in `UpdateView.swift` on all application rows.
   - 1-click "Allow Anywhere" system helper (`spctl --master-disable`).
5. Comprehensive Sorting Controls Across App:
   - Uninstaller: Added dropdown sorting by Size (Largest/Smallest), Name (A-Z/Z-A), Modified Date (Newest/Oldest), and Installed Date (Newest/Oldest). Added `[Select All in View]`, `[Deselect All]`, and row-level `[🗑 Uninstall]` button.
   - Updater: Added dropdown sorting by Updates Waiting First, Name, and Origin/Channel.
   - Clean Up: Added 5 sort modes across all categories.
   - Space Lens: Added sorting for large files by Size, Date, and Name.
6. SF Symbol Icons on All Action Buttons: Fixed the App Uninstaller icon across all views (Dashboard tile, sidebar row, and Uninstaller header) by replacing the invalid `app.badge.minus` with the standard macOS `xmark.app` / `xmark.app.fill` symbol. Added polished icons to every button across Clean Up, Uninstaller, Space Lens, and Overview.
7. Interactive App Leftovers Inspection & Filter Controls (`UninstallerModernView.swift`):
   - Added filter pills: `All Apps`, `With Leftovers`, and `Clean Bundles`.
   - Added global `[▾ Expand All Leftovers]` / `[▴ Collapse All Leftovers]` toggle to inspect all app remnants across the Mac at once.
   - Added interactive clickable capsule pill (`[👁 See X leftovers ▾]`) under the file size and a dedicated `[See Leftovers]` action button on every application row.
   - Enhanced the component drawer with categorized badges (`App Support`, `Caches`, `Sandbox`, `Preferences`, `Saved State`, `WebKit`, `Logs`), selectable abbreviated file paths (`~...`), formatted sizes, and direct 1-click `[↗ Reveal]` in Finder buttons for the main `.app` bundle and every individual leftover item.
8. Orphaned App Leftovers Scanner (`OrphanScanner.swift`): Dedicated scanner cross-referencing `~/Library` application support, containers, and caches against installed applications to isolate remnants of already-uninstalled software.
9. Background Daemons & Security Audit (`DaemonAndSecurityAudit.swift`): Inspects LaunchDaemons/LaunchAgents for deleted executables, audits TCC.db for zombie permissions and over-permissioned active apps, and inspects `/etc/sudoers.d/`.
10. Process Knowledge Engine & Local AI RAM Advisor (`ProcessKnowledge.swift`):
   - Cryptic process resolution via native Darwin APIs (`proc_pidinfo`, `proc_pidpath`, `sysctl KERN_PROCARGS2`).
   - Encyclopedia of Mac processes, developer tools, compilers, and runtimes.
   - Parent application hierarchy resolution (e.g. traces `swift-frontend` to `Xcode.app`, `Terminal`, or `Gemini`).
   - Active workload detection (e.g. identifies module being compiled: `Compiling module 'Housekeeping'`).
   - Dynamic safety badge (Safe to Quit, Caution, System Protected).
   - Full grounding integration with "Ask the Housekeeper" / Local AI so users can chat with the local model about held RAM with complete context.
11. VPN Tunnels & Interface Watchdog (`VPNTunnelEngine.swift`, `VPNTunnelsView.swift`):
   - Enumerates how many VPN services are installed vs actively routing (`scutil --nc list`, `networksetup`, `preferences.plist`).
   - Discovers BSD virtual tunnel interfaces (`utun`, `tun`, `tap`), inspects IP addresses and MTU, and correlates kernel routing (`netstat -rn -f inet` for `0/1` and `128.0/1` default routes).
   - Identifies Apple system infrastructure (`utun0`–`utun3` for AirDrop and iCloud) vs third-party VPN tunnels.
   - Scans running VPN background daemons (ExpressVPN, Amnezia, WireGuard, Tailscale, Sing-box, WARP, etc.) with CPU % and memory.
   - 1-click **[🗑 Delete VPN]** to permanently remove stale, conflicting VPN profiles from macOS Network Settings (`networksetup -removenetworkservice`).
   - 1-click **[Disconnect]** / **[Connect]** and **[🛑 Stop Engine]** process controls.
   - 1-click **[⚡️ Flush DNS & Reset Routes]** emergency rescue button.
   - Accessible via Overview Dashboard, sidebar, and keyboard shortcut `⇧⌘V`.
13. Kitchen-Sink Full Bundle Integration (MediaDock 9 & Bookbind Built Right In):
   - Full Self-Contained Bookbind Engine: Cloned canonical checkout into `/Users/Morad/C3PO/Bookbind`. Packaged `app.py`, `bookbind_cli.py`, `static/`, AND `bin/` (`BookbindServer`, `ffmpeg`, `ffprobe`, `_internal`) directly into `Housekeeping.app/Contents/Resources/Bookbind`.
   - Zero Dependency Failures: `BookbindEngine.swift` resolves the bundled binary engine, local checkout, and system python (including `/Library/Frameworks/Python.framework/Versions/3.10` with `mutagen`). Verified live with port 8765 responding with full volume and user home data.
   - First-Class UI Integration: Added dedicated "Studios & Media" section in the primary sidebar (`MediaDock 9` and `Bookbind`) and prominent utility cards under "Studios & Utilities" on the Dashboard.
14. Universal Multi-Architecture Build: Fat universal binary (`arm64` + `x86_64`) packaged via `script/package_release.sh` and installed into `/Applications/Housekeeping.app` (PID 52911; git push held per Morad's review instruction).

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

---

## DNS Easy Switcher & Media Bundle Handoff (2026-11-02, session 6)

### Objective:
Morad requested: "Also add a DNS configurator to the app like this one.. '/Applications/DNS Easy Switcher.app'" alongside embedding Bookbind and MediaDock into a self-contained kitchen-sink bundle.

### Features Implemented:
1. **DNS Easy Switcher (`Sources/Network/DNSModels.swift`, `Sources/Network/DNSEngine.swift`, `Sources/UI/DNSConfigView.swift`):**
   - Built-in tool replicating and exceeding `/Applications/DNS Easy Switcher.app` without third-party daemons or system modifications.
   - **Preset Catalog**:
     - *Automatic (DHCP)*: 1-click restore to router default (`networksetup -setdnsservers <iface> empty`).
     - *Fast & Privacy*: Cloudflare (`1.1.1.1`, `1.0.0.1`), Google Public DNS (`8.8.8.8`, `8.8.4.4`), Quad9 (`9.9.9.9`, `149.112.112.112`), OpenDNS (`208.67.222.222`, `208.67.220.220`).
     - *Ad & Threat Blocking*: AdGuard DNS (`94.140.14.14`, `94.140.15.15`), Cloudflare Security (`1.1.1.2`, `1.0.0.2`).
     - *Sanction & 403 Bypass (Iran)*: Shecan (`178.22.122.100`, `185.51.200.2`), 403.online (`10.202.10.202`, `10.202.10.102`), Begzar (`185.55.226.26`, `185.55.225.25`) allowing seamless access to blocked developer platforms (Docker, Homebrew, Gradle, Android SDK, NPM, etc.).
     - *Gaming & Low Latency*: Electro (`78.157.42.100`, `78.157.42.101`), Radar Game (`10.202.10.10`, `10.202.10.11`).
     - *Custom Profiles*: Add, edit, test, and delete personal DNS servers with IP syntax validation.
   - **Real-Time Latency Testing**: ICMP ping benchmark tool (`ping -c 1 -W 1000 <ip>`) per card and global **[🔄 Test All Latencies]** with color-coded millisecond badges (`🟢 <35ms`, `🟡 35-100ms`, `🔴 Timeout`).
   - **Interface Targeting**: Automatically selects primary gateway via `route get default` and `networksetup -listallhardwareports` (e.g. `Wi-Fi · en0`), with support for specific interfaces or **All Physical Interfaces**.
   - **1-Click Cache Flushing**: Directly purges macOS DNS resolver cache via `dscacheutil -flushcache` and `killall -HUP mDNSResponder`.
2. **App Integration & Navigation:**
   - Sidebar: Under "Studios & Network" as "DNS Easy Switcher".
   - Dashboard Overview: Symmetrical 3×3 studios grid alongside MediaDock 9 and Bookbind.
   - Menu Bar & App Commands: `Jobs ▸ DNS Easy Switcher…` with keyboard shortcut `⇧⌘D`, and status item right-click menu.
3. **Full Kitchen-Sink Bundle (Bookbind & MediaDock):**
   - Bookbind's engine (`app.py`, `bookbind_cli.py`, `static/`, and `bin/` containing `BookbindServer`, `ffmpeg`, `ffprobe`) staged directly into `Housekeeping.app/Contents/Resources/Bookbind/`.
   - Runs headless on local loopback port 8765 when opened, cleanly shutting down on app exit.
4. **Verification & Packaging:**
   - `typecheck.sh`: Passed with 0 warnings.
   - `test_safety.sh`: Passed all 282 safety assertions.
   - `package_release.sh`: Built Universal Fat Binary (`arm64` + `x86_64`) and packaged zip archives.
   - Installed to `/Applications/Housekeeping.app` and verified live.
   - `~/Desktop/Housekeeping — a noob's guide.md`: Updated with Section 12 for DNS Easy Switcher and full command vocabulary.
   - **STRICT MANDATE HELD**: Zero git commits or pushes executed.

---

## Battery Health, App Doctor, and Mascot Handoff (2026-11-02, session 5)

### Features Implemented:
1. **Battery Health & Power Management (`Sources/Hardware/BatteryHealthEngine.swift`, `BatteryHealthModels.swift`, `Sources/UI/BatteryHealthView.swift`):**
   - Native Darwin IOKit interface querying `AppleSmartBattery` hardware registers in real time: cycle count (625 / 1,000 cycles, 62.5% consumed), maximum full-charge capacity (`6,521 mAh`) vs factory design capacity (`8,694 mAh`), capacity loss (`-2,173 mAh`), cell condition (`Normal`), voltage (`12.00 V`), amperage, and battery controller IC (`bq40z651`, serial `F8Y148502FA0J9TA6`).
   - Power flow detection: 40W USB-PD adapter (`20V @ 2.0A`), Optimized Charging 80% hold state detection (`NotChargingReason = 16777216`), and AC Pass-Through state.
   - Sleep Inhibitor Watchdog: Live `pmset -g assertions` parser displaying active apps preventing deep standby sleep with PID, name, duration, and 1-click `[Quit]` action.
   - Wired to Navigation: Sidebar under Hardware & Vitals, Overview dashboard card, menu bar popover battery room button, and local AI Housekeeper context topic (`HousekeeperTopic.batteryHealth`).
2. **App Doctor & Damaged App Repair (`Sources/AppRepair/AppRepairEngine.swift`, `Sources/UI/AppRepairView.swift`):**
   - Built-in tool replacing `/Applications/Damaged Repair Tool`.
   - Strips `com.apple.quarantine` recursively, clears Gatekeeper provenance attributes (`xattr -cr`), restores executable permissions (`chmod +x`), and ad-hoc re-signs binaries (`codesign --force --deep --sign -`).
   - Quarantined apps shelf + drag & drop repair zone.
3. **Mascot & App Icon:**
   - Generated multi-resolution `AppIcon.icns` and `AppIcon.png` from Morad's hand-crafted maid octopus mascot.
   - Replaced assets in `Resources/BenignMonster/`.
4. **Packaging & Verification:**
   - `script/typecheck.sh` passed with warnings as errors.
   - `script/test_safety.sh` passed all 282 safety assertions.
   - Universal fat binary (`arm64` + `x86_64`) built via `script/package_release.sh`.
   - Installed to `/Applications/Housekeeping.app` (running live).
   - Beginner guide updated at `~/Desktop/Housekeeping — a noob's guide.md`.
   - **NO GIT PUSH**: Strictly retained locally per Morad's instruction pending review.

5. **Storage Lens Category Measurement Fix (`Sources/Disk/SpaceAnalyzer.swift`, `Sources/UI/SpaceLensView.swift`):**
   - Root cause identified: `SpaceAnalyzer` was calling `resourceValues(forKeys: [.fileSizeKey])` directly on top-level `.app` directory nodes (which returns 4 KB per bundle) rather than summing file contents, triggering an artificial floor `max(appsSize, 12GB)` that made Morad's 92+ GB of apps display as 12 GB.
   - Replaced with parallel asynchronous APFS traversal measuring full bundle contents across `/Applications`, `/Applications/Utilities`, and `~/Applications` (accurate: ~92.2 GB).
   - Removed 20,000-file premature break in `quickFolderSize` that caused Documents (198+ GB) to report 18.92 GB.
   - Removed `skipsPackageDescendants` in Trash scan so moved `.app` bundles reflect real trash size.
   - Added fast Spotlight `mdfind` index for Big & Old Files (> 200MB) with 50ms response time.
   - Made category cards clickable with live progressive measuring states.

