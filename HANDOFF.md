## 2026-11-10 — Housekeeping 0.28.2 (54) SHIPPED: Codex's canonical octopus in the menu bar

Published latest stable: https://github.com/aghamorad/Housekeeping/releases/tag/v0.28.2
Not a prerelease. Tag `v0.28.2` on `16da92766f85aa75f1ba95cd7dfa23e1cc25ab59`; release workflow
run 42692848331 green; asset Housekeeping-macOS-universal.zip 162818026 bytes, SHA-256
`1e6c68eaa3cc8460dc6866a9b3c6ec5009e55abd7ace350f94b0c4e4641cb9a7` (matches SHA256SUMS.txt).

Why: Codex's icon work lived in open PR #1 ("Use the canonical maid-octopus template in the
menu bar") and was never merged, so releases carried the older menu-bar mark. This release
integrates the canonical icon from that PR directly:
- `HousekeeperMascot.canonicalMenuBarTemplate` embeds the 144 px alpha-mask PNG (116 base64
  chunks, 13,868 chars) so no Xcode resource registration or loose file can lose it; the
  original dark artwork is the tintable foreground and white cap/apron/details are cut-outs.
- `loadMenuBarTemplate()` returns it first at 18 pt with `isTemplate = true`, then keeps the
  previous bundle/dev-file fallbacks. Breathing animation, Reduce Motion and the
  accessibility label are unchanged.
- PR #1 was closed as superseded with a comment explaining the icon-only integration (its
  StatusItemController predates the 0.28.x health-alert and streaming changes).
Verified: embedded base64 decodes in a standalone AppKit probe to a 144×144 template image
and renders as an 18 pt template; 375 safety + 85 background/MCP assertions, static UI audit,
warnings-as-errors typecheck and Xcode build pass; universal package verifies (52 universal
Mach-Os, signature, stamped commit, Bookbind manifest); packaged CLI 0.28.2 (54) on arm64 and
under Rosetta. Downloaded the published asset fresh, checksum matched, verified and installed
at /Applications/Housekeeping.app (binary SHA-256
`e85533d8da43c6fff678c3d719dfe358ef814254435fd0511c004edc4800d625`), launched (PID 18808),
release published Latest. Previous local test build backed up to
`/Users/Morad/.Trash/Housekeeping-0.28.2-local-test-before-published-20261110-001143.app`;
0.28.1 published build remains at
`/Users/Morad/.Trash/Housekeeping-0.28.1-local-test-before-published-20260911-...` (see Trash).
Also refreshed LaunchServices registration (`lsregister -f`) and touched the app so Finder and
the Dock pick up the current bundle icon.

Limits: macOS places status items in the menu-bar overflow when the bar is full (this Mac runs
several menu-bar apps); the icon is correct and the system decides visibility without expanding
the overflow chevron. Intel verified through Rosetta only; the build is ad-hoc signed.

## 2026-11-09 — Housekeeping 0.28.1 (53) SHIPPED: living controls and a smarter, streaming Housekeeper

Published latest stable: https://github.com/aghamorad/Housekeeping/releases/tag/v0.28.1
Not a prerelease. Tag `v0.28.1` on `0cd347697ae59b512957ad773bd1b833953934c0`; release workflow
run 42686342083 green; asset Housekeeping-macOS-universal.zip 162789932 bytes, SHA-256
`2b214bbe0961aeb16e3cd8d81093f760fc8b8c66d6084419583a0ae1139e9eb4` (matches SHA256SUMS.txt).

What went into it (commits f0977b6, 6465500, f97828c, 0cd3476):
- Buttons/controls: `HousekeepingButtonStyle`, `RailButtonStyle`, `HousekeepingPressableStyle`
  add spring press travel, hover lift/glow, a travelling sheen and a trackpad tick; applied to
  themed buttons, rail buttons, sidebar rows, dashboard action cards and utility tiles.
  State-driven only, Reduce Motion respected, idle cost unchanged.
- Chat streaming: `AppleHousekeeper.stream` (FoundationModels `streamResponse`) and
  `LlamaServer.stream` (SSE `stream: true`) drive a new `Housekeeper.liveAnswer`; the panel
  shows "Thinking…" only until the first word, renders the answer live, keeps the partial
  answer if stopped, offers Copy on every answer and Simpler / What next? / Example chips.
- Prompt rewrite: warm, concrete, general-purpose; still forbids invented files/actions;
  names the real tool screens so a small model cannot invent features.
- Fixed general questions being hijacked: folder evidence now requires an explicit path, a
  named folder plus a folder noun, a distinctive name, or a focused "this folder" reference
  ("What is 17 times 23?" used to answer with folders named 23). Regression assertion added.
- Fixed general questions being buried in app status: app context is only sent when the
  question is about this Mac/Housekeeping or the chat is open about a folder; Mac questions
  get a volume reading taken at question time (older Disk Browser snapshots are labelled
  dated).
- Build scripts resolve the physical checkout path (`pwd -P`), fixing intermittent module
  cache collisions when the tree is opened through the C3PO symlink.

Verified locally before tagging: 375 safety assertions (incl. folder-hijack regression),
85 background/MCP, static UI audit, warnings-as-errors typecheck, Xcode build, universal
package (52 universal Mach-Os, signature, source stamp), headless model probe (first token
1.7-3.3 s, full 3.7-6.7 s on the Apple system model), live GUI pass on macOS 27.2/M1 Pro:
general internet question answered on topic without app noise, "What can you do?" returns
the exact tool list, disk-space question answers with a fresh 247.7 GB reading, streaming
visible, follow-up chips and copy rendered, buttons/layout unchanged otherwise.
Post-download verification of the published asset: signature OK, version 0.28.1 (53),
stamped commit equals tag, 52 universal Mach-Os, Bookbind manifest OK, CLI 0.28.1 on arm64
and Rosetta. Installed that exact app at /Applications/Housekeeping.app (binary SHA-256
`e1c4ebf594b5f41dbbf78ff45c567a24f541a1e4e4de132a43075c1a4ca7e29d`), launched it (PID
11909 at verification). Previous local test build backed up to
`/Users/Morad/.Trash/Housekeeping-0.28.1-local-test-before-published-20261109-234033.app`;
the 0.28.0 app is at
`/Users/Morad/.Trash/Housekeeping-0.28.0-before-0.28.1-20261109-225426.app`.

Limits recorded in the notes: Intel via Rosetta only; ad-hoc signed, not notarized; Stop's
partial-answer path not clicked by the automation (code/cancellation reviewed); the Apple
system model is small — the downloadable Qwen/Gemma options remain the better choice for
harder reasoning.

Build evidence: `.build/dist-0.28.1-v2` (last local package), `.build/release-v0.28.1`
(downloaded asset), `.build/release-v0.28.1-check` (extracted verified bundle). No local
service was stopped.

## 2026-11-09 — Housekeeping 0.28.0 (52) SHIPPED: released, verified, installed

Published latest stable: https://github.com/aghamorad/Housekeeping/releases/tag/v0.28.0
(Draft created, release workflow built it, assets verified from a fresh download, then
published with the Latest badge. Not a prerelease.)

Source: PR #5 `release-candidate/universal-ux-20261109` was marked ready and merged as
`3bbe7dc8e676d368f6ec920e8f9241010087ceea`; tag `v0.28.0` on that commit. The branch
carried five local fix commits on top of Codex's candidate:
- `8dc1d54` separate panel/health CPU baselines, honest Refresh Health Status (can clear a
  stale warning), uninstall copy now says related data starts excluded, Quarantine manifest
  reads moved off the main thread and once per activation, hidden-selection clearing is
  announced, scan notes restored on the Clean Up status line, first-party answers match
  intent (and are not written into model history), accessible menu-bar health label.
- `09b632f` + `8b3e428` the clearing notice survives typing and reports the cumulative
  number cleared, not just the last keystroke.
- `a735dca` CHANGELOG 0.28.0 and RELEASE_NOTES_v0.28.0.md.

Release workflow run 42676285784 succeeded in 10m18s (checkout → target checks → base
input restore → universal Bookbind runtime build → 373 safety + 85 MCP assertions →
universal package → ZIP/provider verification → asset upload). GitHub Actions artifact:
Housekeeping-macOS-universal.zip 162729709 bytes; SHA-256
4f8cc7a76bd5488a338f86b6569a7375ab665172ae39c2b2a54705490a65fd0e (matches SHA256SUMS.txt
attached to the release).

Published asset independently downloaded, checksum-checked, extracted, and verified:
codesign --deep --strict OK; 52 universal Mach-O files with no external absolute
libraries; stamped `HousekeepingSourceCommit` equals tag commit; Bookbind runtime manifest
and source comparisons pass; `lipo` x86_64 + arm64; packaged CLI reports 0.28.0 (52) on
arm64 and under `arch -x86_64`; `where --json` parses; bundled llama-server runs on both
slices. Installed that exact app at /Applications/Housekeeping.app (binary SHA-256
`e88abfd7c632c74b2c0645fd15d2db6efb3fe026c01b59fb3a2676fdea50aea1`), launched it
(PID 87509 at verification), and its UI reads 0.28.0 with "Made by Morad". Previous app
backed up to
`/Users/Morad/.Trash/Housekeeping-0.27.1-before-0.28.0-20261109-222405.app`.

GUI acceptance pass run live on macOS 27.2 / M1 Pro before tagging: every sidebar tool and
the Advanced Tools entries opened their own screen; Clean Up showed a completed scan and
scoped bulk selection; the review sheet listed exact paths; the uninstaller showed related
data excluded by default with "0 of 2 related files included" and exact-path review; a
search that hid selections showed "127 selected apps are hidden by the current search or
filter and were cleared"; Quarantine refreshed off the main thread; Local Models showed
model-on-disk versus runtime-resident wording; the assistant returned the tool list for
"What can you do?" and routed "What can you do about a full disk?" to the model; the
menu-bar panel opened with the octopus, rooms, processes and the accessibility label
"Housekeeping menu bar item: no sustained CPU or thermal warning"; quit + reopen produced
exactly one window.

Known limits recorded in the release notes: Intel verified through Rosetta on Apple
Silicon only; ad-hoc signature, not notarized; no live Ollama/LM Studio model load/unload
exercise; a status item's right-click menu is not enumerable by automation before a real
right-click, so those menu items were not clicked in this pass.

Local build evidence stays under `.build/`: worktree `rc-0.28` (branch + fix commits),
`dist-0.28-final2` (last local package), `release-v0.28.0` (downloaded assets) and
`release-v0.28.0-check` (extracted verified bundle). No local service was stopped.

## 2026-11-09 — Release candidate 0.28.0 (52) tested locally; test pass that led to the release above

Codex made the update through GitHub only (PR #5, draft, branch
`release-candidate/universal-ux-20261109` at `c676e52353e325c5a0bc3c0050241ebb2a160e0a`,
base `main` 2f5927d). It integrates PR #2 (model/menu-bar reliability) and PR #4
(cleanup/quarantine UX, mascot icon) and says it needs local testing. DeepSeek Harness
ran every gate that does not need a visible desktop.

Verified locally on 2026-11-09 (macOS 27.2, Xcode 27.2, M1 Pro; worktree
`Housekeeping/.build/rc-0.28`, which lives on the SanDisk volume via the C3PO symlink):
- Safety suite: 372 assertions pass (`script/test_safety.sh`).
- Background/fake-MCP: 85 assertions pass (`script/test_background_mcp.py`).
- UI no-op audit: clean, 161 buttons / 186 ThemeButtons over 131 sources
  (`script/audit_ui_controls.py`; new on this branch).
- `script/typecheck.sh` passes warnings-as-errors; `xcodebuild` Debug build succeeds.
- Mascot icon renderer passes: 1024 PNG, 16–512 iconset, two Icon Composer layers;
  legible at 32 px; packaged AppIcon.icns differs from the legacy source icon.
- Universal package built with `script/package_release.sh`: 52 universal Mach-O files,
  no external absolute libraries, ad-hoc signature verifies, stamped source commit
  matches `c676e52`, version 0.28.0 (52).
- Packaged CLI on both slices: `--version`, `help`, `where --json` under arm64 and
  under `arch -x86_64` (Rosetta). Bundled `llama-server --version` runs on both slices.
- Bookbind runtime inside the package passes on arm64 and x86_64: frozen server, static
  page, scan, transcode, AAC copy, chapters, tags, restore (script/test_bookbind_runtime.py).
- Read-only CLI on the packaged app: `scan --quick --json` (687 items) and
  `clean --json` both exit 0.
- Idle sample, 10 min, window open with the screen locked: CPU 0.0% throughout,
  RSS averaging 64.9 MB (range 18–143 MB), no crash reports.
- Artifact: `.build/rc-0.28/.build/dist-0.28/Housekeeping-macOS-universal.zip`
  (154 MB, SHA-256 `3d962ba963c4a5b34d6dcff61c96322f130bba60f69f010d342c949300931296`)
  plus `SHA256SUMS.txt`; extracted check bundle in `.build/check-0.28`.

Code review of the diff found real defects that the automated suites cannot see:
1. HIGH `Sources/MenuBar/SystemVitals.swift:391` (+`:176`) — `healthTick()` and the 1 s
   panel sampler share one `previousCPU` baseline. With the panel open the CPU headline
   becomes a 15 s average, and three unrelated ~1 s spikes 15 s apart can latch a false
   "Sustained high CPU load" alert. Separate baselines needed.
2. HIGH `Sources/MenuBar/StatusItemController.swift:517` — "Refresh Health Status" makes
   one sample, but CPU alerts need 3 high samples and warnings clear only after 2 clean
   samples, so the menu item usually cannot change what it shows.
3. MEDIUM `Sources/Cleaner/CleanerModel.swift:296,322,375` and
   `Sources/Cleaner/CleanerModels.swift:79` — copy still says related files are
   "included by default" and tells the user to "uncheck anything you want to keep",
   while the branch now excludes related data by default. The uninstall confirmation can
   read "The application and 0 included related items".
4. MEDIUM `Sources/UI/QuarantineView.swift:141` — every `didBecomeActive` reloads
   Quarantine manifests and transaction history synchronously on the main thread;
   duplicate of `onAppear`, scales with Quarantine size.
5. MEDIUM `Sources/UI/UninstallerModernView.swift:23,27,157` — changing search or filter
   silently drops selections that scrolled out of view, with no "outside this view"
   count (Clean Up does show one).
6. LOW `Sources/UI/CleanerView.swift:766` — the scan-notes branch was dropped from the
   status line; unreadable-folder notes now exist only inside Scan Details.
7. LOW `Sources/Housekeeper/Housekeeper.swift:277` — canned `readOnlyAnswer` matches run
   before the model check, so substring hits ("What can you do about a full disk?") get
   the generic tool answer even with a model loaded.
8. LOW `Sources/MenuBar/StatusItemController.swift:305` — the alert "!" has a tooltip
   only; no accessibility label/value.

Not verified, blocked or out of reach on this run: the GUI acceptance matrix (the Mac's
screen was locked — `CGSSessionScreenIsLocked=Yes` — so no window could be focused or
clicked), physical Intel hardware, live Ollama/LM Studio model load/unload, window-closed
idle energy, VoiceOver/keyboard navigation, Gatekeeper download experience, clean
install/rollback on a second Mac.

State: the candidate was not merged, tagged, released or installed; only this handoff
record was committed to `main` (414478e). The candidate build remains in `.build` only;
`/Applications/Housekeeping.app` is still 0.27.1 (51) and was relaunched after the test
(the test candidate itself was quit). Next: unlock the screen and run the GUI matrix;
decide fixes for defects 1–3 before any v0.28.0 release.

## Completed — 2026-11-08 — Housekeeping 0.27.1 (51), fully universal release

Codex; user requested a GitHub release explaining the uninstall fixes and then
required every bundled executable/library to support Intel and Apple Silicon.
Published latest stable: https://github.com/aghamorad/Housekeeping/releases/tag/v0.27.1
Release source/tag: d18c742343db5e16769da758a0c289d29277969b, v0.27.1.
Uninstaller implementation commit: 3becf47537b40048ecf093c9443c5c10d71f37ea.
main and both tags were pushed. The superseded empty v0.27.0 draft was deleted;
its historical source tag remains. No published v0.27.0 binary release exists.

Delivered: scoped macOS administrator recovery for app bundles, useful failure
reports, apps plus matched related files reviewed/default-included together,
app-before-data safety, shared animated removal workspace and durable results,
Quarantine search/batch restore/delete/empty. Full details in
RELEASE_NOTES_v0.27.1.md and CHANGELOG.md; earlier implementation evidence below.

Universal fix: Bookbind's launcher no longer excludes Intel. Versioned Bookbind
1.5.2 source/static is in Runtime/Bookbind. Project-local extracted, notarized
python.org 3.15.2 plus PyInstaller 6.22.3 builds a real universal2 onedir runtime;
all Python extensions/libraries and the bootloader contain both architectures.
FFmpeg/FFprobe 9.0 combine checksum-pinned original arm64 codecs with Evermeet
Intel static builds. CI bootstrap uses checksum-verified 0.26.8 media inputs;
the old frozen engine/Python is never reused. All 52 native files in the final
app contain arm64 + x86_64, use system/relative libraries and meet macOS 13.
Packaging rejects thin native files, external absolute dependencies and stale
engine source manifests. One universal download replaces architecture choices.
Runtime build/reuse instructions and third-party notices: Runtime/README.md.

Published assets (uploaded, downloaded fresh, checksum checked and extracted):
- Housekeeping-macOS-universal.zip — 160986148 bytes; SHA-256
  babd71593a166d1aa30a190673d726ad53988dd5c2abeb280d7f2dec27dc82f4
- SHA256SUMS.txt — 99 bytes.
GitHub /releases/latest confirms v0.27.1, draft=false and prerelease=false.
Public page independently read back with explanatory notes and Latest badge.

Validation: 358 safety assertions + 85 background/MCP assertions; no warnings.
Both optimized GUI architecture compilations pass with warnings-as-errors.
Native + Intel/Rosetta runtime execution passed actual frozen-engine health,
static UI, scan, transcode, AAC copy, chapter/tag checks and restoration of the
generated originals with matching hashes. Repeated on the packaged ZIP and on
the freshly downloaded GitHub ZIP. Both Housekeeping CLI slices report 0.27.1
(51). llama-server --version runs for both architecture requests. Deep strict
signatures, exact tagged source SHA, input fingerprint and all native slices
verified by script/verify_release.py. Intel execution is through Rosetta on this
Apple Silicon Mac, not a physical Intel Mac test.

Evidence: .build/release-v0.27.1-{package.log,check.log,check/validation.json,
download-check.log,download-check/validation.json,installation.json}; runtime
build/smoke/safety/MCP evidence under .build/universal-runtimes/. Canonical release
artifact .build/release-v0.27.1; published/downloaded copy
.build/release-v0.27.1-download. Earlier 0.27.0 packages are superseded.

Installed the exact verified downloaded app at /Applications/Housekeeping.app;
strict signature, whole-bundle content comparison and CLI version pass. Binary
SHA-256: 53dcd7171651dc27badb24dabd4c7f7f3033337f331b95d1bb073bdf71923389.
Old app backup: /Users/Morad/.Trash/Housekeeping-0.27.0-before-0.27.1-20261108-004224.app
Running Housekeeping PID 8150 stayed alive; no local service was stopped or
restarted. Visible Quarantine manifest count/digest match before/after (0 at the
checked root). Desktop guide updated with release/download, controls, verified
limits and the actual backup: /Users/Morad/Desktop/Housekeeping — a noob's guide.md.

User action: finish any existing media jobs, then Quit/reopen Housekeeping to
load the installed build. Live uninstall clicks, animation timing and the real
administrator prompt remain unverified because the native UI bridge could not
read the window; the prior static fixtures are not live interaction checks.
No real app or existing Quarantine item was removed as a test. No task work remains.

## Current work — 2026-11-07 — 0.27.0 (50): Animated uninstaller installed locally

Status: implementation, fixture validation, packaging and installation complete.
Updated 2026-11-07 23:57 +0330, Codex.
Project `/Volumes/SanDisk-AI/Apps & Games/Housekeeping`, main at `3b5f636`.
All session changes remain local/uncommitted and unpublished. No branch, commit,
push, tag or release was created. No real user app was removed for testing.

User's latest request: a proper uninstaller with animations while removing apps,
comparable in polish to CleanMyMac or Mole. Builds on the 0.26.9 work below.

Delivered:
- Both uninstall entry points show the shared `UI/UninstallActivityView.swift`:
  retained app icons, file-transfer animation, real item counts/progress ring,
  permission status, per-app/per-file outcomes and a persistent summary.
- The engine awaits UI progress before starting authorization, and emits successful
  item outcomes only after the recovery manifest is saved. Preflight refusals,
  app-before-data dependencies, canceled permission requests and partial failures
  remain visible. Interrupted reports retain recorded successes.
- Failed app rows expand with reasons and Finder actions. Results distinguish
  removed apps, removed related items and storage held in Quarantine. Restore/
  review access and Back to Apps remain available after completion.
- Review includes live counts/size, category labels, Include All and Keep All
  Related Files. Open apps offer a normal quit request. Removed apps disappear
  from the browser immediately; rescanning remains visible before another choice.
- Animation follows actual work without fake delays or copied-byte estimates.
  Existing window visibility tracking stops it when covered, minimized, hidden,
  inactive, waiting for permission, finished or Reduce Motion is on. No persistent
  animation timer was added. Actual idle performance has not been measured in the
  newly installed executable because the old process was deliberately left running.
- Legacy cleanup totals deduplicate candidate/app-leftover paths; interrupted
  operations no longer claim that nothing was moved.

Verified:
- 358 safety assertions pass without warnings. Fixtures check durable recovery
  visibility during success callbacks, ordered app-before-data progress,
  permission-before-helper, partial/interrupted summaries, and the prior 0.26.9
  protection/authorization/bulk-Quarantine cases.
  Log `.build/uninstall-experience-safety.log`.
- GUI typecheck and both optimized architecture compilations pass with warnings
  treated as errors. Final build log `.build/uninstall-experience-package-final.log`.
- Eight offscreen SwiftUI PNG fixtures rendered (removal, permission, completion,
  interruption in both themes) in `.build/uninstall-previews/`. Inspected modern
  removal/completion and Classic interruption layouts. The fixture process uses
  fake plans only and never invokes the cleanup engine or controls the live app.
- All three final archives were extracted and checked for version/build,
  strict deep signatures, expected app/runtime architectures, working bundled
  ffmpeg/ffprobe, Bookbind engine matching 1.5.2, and a source fingerprint matching
  the final source tree. `.build/uninstall-experience-validation.json` and
  `.build/uninstall-experience-artifact-check.log` record the checks.
- Installed `/Applications/Housekeeping.app` answers `Housekeeping 0.27.0 (build 50)`;
  its signature verifies and binary hash matches the final packaged app:
  `2984d496dc75650be54b0bddad134fa24f665b50975c86a996d57ad68c6b021e`.
- Installation preserved the running process/jobs. Recorded Quarantine manifest
  count/hash matched before/after (0 manifests at that visible root).
  `.build/uninstall-experience-installation.json` has the receipt.

Final artifacts: `.build/uninstaller-0.27.0-final/` (.app, three ZIPs, SHA256SUMS).
The first `.build/uninstaller-0.27.0` package is superseded by a final browser-refresh
fix; do not install/deliver it. Verifier/installer helpers:
`.build/verify_uninstall_experience.py`, `.build/install_uninstall_experience.py`.
Backup: `/Users/Morad/.Trash/Housekeeping-0.26.9-before-0.27.0-20261107-235633.app`.
Guide `/Users/Morad/Desktop/Housekeeping — a noob's guide.md` now describes 0.27.0,
review/quit/progress/results, bulk Quarantine, recovery and the verified limits.

Limits / user action: the native bridge still returns "The observed macOS window
disappeared" (normal/explicit-window reads), so live clicks, animation timing and
the actual administrator dialog remain unverified. Static rendering and fixture
tests are not an end-to-end live uninstall. Quit and reopen Housekeeping after
current Bookbind/MediaDock jobs finish to load the installed update.

Reusable constraints: report progress only after the durable state transition;
await UI authorization status before a blocking helper; retain icons before moving
bundles; use shared presentation/reducers for multiple removal entry points;
keep animation gated by per-window visibility and actual operation state.

## Current work — 2026-11-07 — 0.26.9 (49): Uninstaller and bulk Quarantine installed locally

Status: implementation, fixture validation and local installation complete.
Updated 2026-11-07 23:23 +0330, Codex.
Project `/Volumes/SanDisk-AI/Apps & Games/Housekeeping`; main remains at
`3b5f636`, with these changes uncommitted and unpublished. Current developer
instructions prohibit commits/pushes without an explicit request. No branch,
tag, release, remote change, or user-app cleanup was performed.

Objective: fix the wonky uninstall permission flow, include leftovers with an
app, and end one-at-a-time Quarantine management. Vinegar was already deleted
by hand before this task; it was not used as a test target.

Delivered:
- Both uninstall interfaces use CleanupEngine.uninstall with explicitRemoval;
  the dedicated screen previously used sweep intent and silently discarded errors.
- Matched related files start included and can be unchecked in exact-path review.
  Leave Alone is honored in both interfaces and the engine. Shared exact matches
  and parent folders containing another installed app's data are excluded.
- The app moves before its related files. Running, missing, protected, Apple or
  failed apps leave their related data untouched. Actual results and failures show.
- Permission recovery is restricted to validated third-party app bundles and
  their recorded Quarantine copies. A bounded macOS administrator request runs
  Foundation through an argument-encoded JXA command; restore and permanent delete
  use the same recovery. No ownership/access permissions are rewritten. One
  canceled/failed request suppresses further prompts in that batch.
- Quarantine has search, batch selection, Select All Shown, Clear Selection,
  bulk restore, Delete Selected and Empty Quarantine. Confirmation captures the
  reviewed entries and shows count/size. Bulk filesystem work runs off the UI
  actor. Failed items remain waiting. History restore now reports partial failures
  and prevents overlapping actions in that view.

Verified:
- 347 assertions pass (29 new), log `.build/uninstaller-safety.log`.
- GUI typecheck with warnings-as-errors passes, `.build/uninstaller-typecheck.log`.
- Both optimized architecture builds and universal packaging pass. All three ZIPs
  were extracted and checked for version/build, strict deep signatures, app/runtime
  architectures, working ffmpeg/ffprobe, and BookbindServer matching engine 1.5.2.
  The universal extracted binary also answers --version and matches the installed
  binary. Evidence `.build/uninstaller-validation.json` and artifact-check log.
- Fixtures exercise app+settings in one transaction, authorization success/cancel
  and canceled batches, permission recovery on restore/purge, no broad elevation
  for related data, missing/protected/Apple refusals, shared parent folders,
  multi-app deletion, bulk restoration collisions, and both single/bulk review
  defaults. The actual filesystem command was run without elevation against
  quotes/newlines/shell metacharacters. No real administrator prompt was exercised.
- Installed `/Applications/Housekeeping.app` is 0.26.9 (49), signature verifies,
  and its binary hash equals the packaged build. Installation did not stop the
  running 0.26.8 process or its services. Quit and reopen after current jobs finish.
- Old app backup: `/Users/Morad/.Trash/Housekeeping-0.26.8-before-0.26.9-20261107-232200.app`.
  Installation details: `.build/uninstaller-installation.json`.

Artifacts: `.build/uninstaller-0.26.9/` contains the .app, three ZIPs and
SHA256SUMS.txt. Package script now uses a fresh compiler cache per run (the old
cache caused a duplicate-module crash), preserves generated work in Trash, and
records base commit/input digest while omitting a false published-commit stamp
for a modified source tree. The updater will therefore show unknown source status
for this local build rather than claiming it equals the public commit.

Guide: `/Users/Morad/Desktop/Housekeeping — a noob's guide.md` updated, with
new actions, recovery, backup, and instructions not to rerun the old hkfix installer.

Limits / next action: the native computer-use bridge lists the running app but
both normal and explicit-window reads return "The observed macOS window
disappeared". No alternate UI mechanism was used. Visual layout/click verification
and an actual administrator prompt remain unverified. The new executable loads
on the user's next quit/reopen. No real user app or Quarantine item was removed
to test the update. Publication requires an explicit user request.

Reusable engineering constraints: route every uninstall surface through the same
intent-aware engine; make related-data moves depend on successful app moves;
exclude overlapping ownership as well as identical paths; preserve failed items
and cancellation as partial results; test the actual privilege-command encoding
without elevating fixture tests; bind confirmation to a reviewed batch snapshot.

## Current work — 2026-11-07 — 0.26.8 (48): Bookbind binds, menu bar answers

Objective: Bookbind sat on "Waiting for the engine", and the menu bar door and
quit were unreliable.

Root cause, engine: `Bookbind/app.py`'s `worker()` held the global `JOBS_LOCK`
around the whole `run_job`, so `/api/jobs` blocked behind ffmpeg and the page
never left its `queued` stage. Fixed by taking the lock only to claim the job.
`tests/test_job_queue.py` holds a job open and asserts the table stays readable;
it fails on the old code and passes on the new.

Root cause, shipped binary: Housekeeping ran the frozen
`Contents/Resources/Bookbind/bin/BookbindServer`, which was cut 29 October and
carried the same lock bug. `Bookbind/build/repack_server.py` replaces the `app`
entry in the PyInstaller archive, rewrites the table of contents, drops the old
signature command and pads the file back to its `__LINKEDIT` length; then
`codesign --force --sign -`. The rebuilt engine is in `Bookbind/bin/` and in the
0.26.8 bundle. `package_release.sh` now prefers the checkout's `bin` over
`/Applications/Bookbind.app`, which is how the stale engine got shipped.

Stale adoption: `BookbindEngine.boot()` used to adopt any server answering
`/api/home` on 8765–8774. It now checks `/api/health` (new endpoint: version,
pid, parent), adopts only the same version, clears an orphan whose parent died,
and otherwise starts its own. A four-second watchdog turns a dead engine into a
clear failure with Try Again.

Menu bar: `showPanel()` now shows the popover before `SystemVitals.start()` and
the layout measurement, both of which walk every process. `WindowOpener` orders
a closed-but-retained main window front before falling back to `openWindow`.
Quit waits 1.2 s for the housekeeper runtime and the phone helper, then kills.

Verified: GUI typecheck with `-warnings-as-errors` passes; 318 safety assertions
pass; the Bookbind queue test passes; the rebuilt server loads the patched
`app.py` (reaches `server_bind`); universal 0.26.8 package built and
`codesign --verify --deep --strict` passes.

Completed 2026-11-07 with full disk access. The installer copied the source into
both SanDisk-AI projects, installed the app, and pushed both repositories.
Fresh packages were then built from the pushed commit:

- Housekeeping 0.26.8 (48), source `c0bb49c`, released at
  https://github.com/aghamorad/Housekeeping/releases/tag/v0.26.8 with arm64,
  x86_64, universal and SHA256SUMS assets.
- Bookbind 1.5.2, source `1619b70`, released at
  https://github.com/aghamorad/bookbind/releases/tag/v1.5.2; CI passed.

The exact package from the Housekeeping release is now installed in
`/Applications`, with `HousekeepingSourceCommit` set to `c0bb49c`. Its strict
code signature verifies and its bundled engine hash matches Bookbind's.

Live GUI check on the installed release: the first menu bar click opens the
panel in 142 ms; "Open App" brings back a window closed moments before; Quit
exits in under two seconds with the panel open. The engine A/B was conclusive:
1.5.1 spent 4.2 s answering the first progress poll and never showed `encoding`;
1.5.2 answered in 1–2 ms and reported `encoding` during ffmpeg. Both the
Bookbind release zip and Housekeeping's downloaded copy completed a real
three-track merge with duration, chapter, decode and tag checks all passing.

The desktop guide still explains the installer under `.work/hkfix`; future
installs can be done from that folder. No unresolved app defect is known.

The queue test needs no audio stack: it supplies a `mutagen` stub when the
module is absent. Passing on `app.py` 1.5.2 and failing on the 1.5.1 copy from
`git show HEAD:app.py` was re-confirmed on 2026-11-07.

## Current work — 2026-11-06 — 0.26.7 (47) released

Shipped: v0.26.7 with three builds (arm64, universal, x86_64) at
https://github.com/aghamorad/Housekeeping/releases/tag/v0.26.7

- `RebuildCost` on every candidate: `.instant` or `.reDownload(why)`. A table in
  `CleanerScanner.rebuildCost` names the package stores (npm, gradle, uv, pip,
  npx, cargo, maven, brew, codex-runtimes, the updater cache). Rows carry a
  Re-download tag, the confirmation sheet totals the GB and warns about throttled
  connections, and the status line counts them.
- New CLI verb `housekeeping clean [--json]` — Clean Up, read only, with the same
  shelf grouping and the same warnings. The shim at `~/.local/bin/housekeeping`
  is installed and points at the app.
- `script/package_release.sh` did not list `ProtectedDataPolicy.swift`; it does
  now. Its module cache also had to be cleared — a cache built through the
  symlinked path (/Users/Morad/C3PO/Housekeeping) poisons a build run from the
  physical path. Clear `.build/*/ModuleCache` when the compiler reports a module
  "defined in both".

Verified: 318 assertions pass; `housekeeping clean --json` on the real disk gives
79 everyday-junk items, 6 orphans, 3 developer leftovers, and the note
"Left alone: 204 items, 65.0 GB".

Next: none outstanding. Housekeeping's scan is slow (minutes) because it measures
every cache folder; a future pass could bound it.

## Current work — 2026-11-06 — 0.26.6 (46): a line a sweep cannot cross

Objective: make Clean Up trustworthy enough that Select All is safe.

`Housekeeping/Sources/Cleanup/ProtectedDataPolicy.swift` is the rule. On a sweep
it refuses app group containers, sandboxed containers, Application Support,
iCloud Drive, Mail, Messages, Calendars, Photos, Safari, Keychains, Accounts,
Documents, Desktop, Music, Pictures, Movies, Spotlight's index, any AI model
library, /Applications, /System, /Library and any `.app` — plus any folder that
holds recordings, documents or a database, tested by extension outside cache
locations. `CleanupIntent` separates a sweep from an explicit removal, which is
the only path where a container may move.

Enforced in two places: `CleanerScanner.scanAll` filters every shelf through the
policy and reports what it withheld in the Clean Up notes, and
`CleanupEngine.refusalToMove` refuses at the chokepoint, so a shelf written
later cannot move these either. `OrphanScanner` no longer scans Containers or
Group Containers at all.

Bulk: app rows have checkboxes, each shelf has tick-all, the footer has Tick
everything and Uninstall N selected. Open applications are excluded from a batch
rather than blocking it.

Verified: typecheck clean; 312 assertions pass, 16 of them new and specific to
these rules. Replayed all 1103 paths from the 6 November sweep through the
policy — 1002 refused, the remaining 101 are caches, logs, cookie jars and
saved window state. Release built, installed, relaunched as 0.26.6.

Next: watch a full Clean Up scan finish on the real disk and confirm the
Orphaned Leftovers shelf is small and the "Left alone" note reads correctly.

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

