# Housekeeping — handoff

## Objective (2026-10-30)

Morad: "housekeeping apparently takes up a lot of battery — can we somehow fix that?"
His own panel showed Housekeeping as the top consumer (16.9). Shipped as **0.20.1**.

## Done and verified

- **Measured first.** `sample 27720` (installed 0.20.0, menu bar only, no window): main
  thread 100% busy, ~28% CPU, 8.8k idle wakeups/s, call graph under `OctopusMark.body`
  and `StatusItemController.advance`.
- **Two causes.** (1) `StatusItemController.install()` added a 12 fps `Timer` and never
  stopped it — a status-bar image swap and menu bar redraw twelve times a second forever.
  (2) `WorkingOctopus` was a `TimelineView` at 12/20 fps even with `working: false`, in a
  window SwiftUI had closed but not torn down, so a menu-bar copy kept laying out and
  drawing a hidden window.
- **Fix — `MotionBudget`** (`Housekeeping/Sources/UI/Motion.swift`): motion runs while the
  app is active (or a token is held — launch greeting only), and `OnScreenProbe`, a
  zero-sized `NSView` reported through `tracksOnScreen(_:)`, answers whether *this* drawing's
  window is on screen and unoccluded. Both are needed: opening the panel activates the app,
  and the closed window would have taken that as its cue.
- Wired: `WorkingOctopus`, the rail's octopus in `ModernChrome`, the menu bar timer
  (`setAnimating`, driven from `MotionBudget.$isTicking`), and the panel header.
- **Two more costs found while measuring, also fixed:** the panel's header octopus made
  AppKit re-solve the panel's whole Auto Layout per frame (~1.4% CPU per frame at 12 fps),
  so it is now a still frame; and `resize(to:)` fought the popover's own relayout (resize →
  layout → new height → resize), so it is debounced 80 ms.
- **Verified on this Mac, same states:** 28% → **0.0%** idle in the menu bar; **~2.6%** with
  the window open and frontmost; **~1.5%** with the panel open. Fresh launch → 0.0%;
  window open but app in the background → 0.0%.
- Visual check: desktop capture (cua-driver) of the open panel shows the header mark drawing,
  the vitals live, and the foot reading `Made by Morad · Housekeeping 0.20.1`.

## Shipped

- Commit `b6d6bf1`, tag `v0.20.1`, release with universal/arm64/x86_64 zips + SHA256SUMS:
  <https://github.com/aghamorad/Housekeeping/releases/tag/v0.20.1>
  (the tag was force-moved once: the first 0.20.1 push predated the panel fixes, so commit,
  tag and assets were replaced before anyone downloaded them).
- Packaged build installed in `/Applications` (0.20.1, build 34); the previous app moved to
  `~/.Trash/housekeeping-app-backup-20261030-*`.
- Guide rewritten: `~/Desktop/Housekeeping — a noob's guide.md` (the 0.20.0 one was no
  longer on the Desktop).

## Not done / open

- **The panel still costs ~1.5% while open**, from `SystemVitals` sampling once a second.
  That is by design (it only measures while the panel is up), but a slower tick would cut it.
- **The window's own marks still relayout the window per frame** (~2.6% with the window open
  and frontmost). The next lever is drawing the mark without `GeometryReader` (pass the size
  in) or with a `Canvas`, so a frame does not re-solve constraints. Not attempted.
- `appResignedActive` clears every motion token as a belt-and-braces guard; the only token
  left is the launch greeting, which a timer clears.
- Duplicate invisible windows still accumulate at launch (0.20.0 note, unchanged). They now
  cost nothing because the on-screen probe keeps their timelines still.
- Still unverified: the panel's Scan/Ask/MediaDock/Bookbind buttons individually; LM Studio
  `lms` load/unload (no models installed).
