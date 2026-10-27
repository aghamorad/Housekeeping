# Housekeeping — handoff

## Objective (2026-10-27, session 2)

Two fixes for Morad: (1) the menu bar panel's five door buttons did nothing; (2) add a
screen that lists installed local AI models and loads/unloads them. Both shipped as
**0.20.0**.

## Done and verified

- **Menu bar panel, all five buttons.** Root cause: `WindowOpener.withWindow` used
  `NSApp.windows.first(where: { $0.canBecomeMain })`, and a window SwiftUI has closed
  keeps its style mask, so it still answers `canBecomeMain` while drawing nothing. The
  app activated, ordered the dead window front, and the reader saw the desktop. On this
  Mac there are always two such windows at launch (restored frame + default size), one
  of them invisible.
  Fix in `Housekeeping/Sources/MenuBar/StatusItemController.swift`: `liveWindow()` picks
  key → minimized → visible (titled, level .normal only); `bringForward()` also calls
  `NSRunningApplication.current.activate`; `orderFrontRegardless()` when activation was
  refused; `waiting` is kept even when no SwiftUI opener exists yet.
  Verified: minimize the window → open panel → click **Open** → the same window id
  returns on screen (`CGWindowListCopyWindowInfo`), not a duplicate.
- **Panel reachable without the mouse.** `StatusItemController.presentPanel()` +
  **Jobs ▸ Menu Bar Panel** (⇧⌘M). Added because the octopus can be hidden by a crowded
  menu bar.
- **Local Models screen** (`Sources/Models/LocalModels.swift`, `ModelsView.swift`):
  Ollama (REST `/api/tags`, `/api/ps`; load = `generate` keep_alive 10m, unload = 0),
  LM Studio (store read as a folder; REST `/api/v0/models` only when already running;
  `lms` used only for load/unload), the housekeeper's weights + `LlamaServer`, Hermes
  MLX `/v1/models` + `/unload`, and the HF cache as read-only downloads.
  RAM guard: `bytes * 1.15 + 700 MB` vs free; refuses with the arithmetic instead of a
  button. One load at a time; **Unload Everything**.
  Verified end-to-end with a stand-in Ollama service on :11434 (fake, 1.5 GB): row
  flipped to IN MEMORY on Load (`keep_alive='10m'` in the server log), back on Unload
  (`keep_alive=0`). Nothing real was loaded; no model was tested for real (16 GB Mac).
- Wired: `AppState.Screen.localModels`, `showLocalModels`, `localModels` inventory,
  ContentView sheet + sidebar (Maintenance) + job, Jobs menu (⇧⌘I), typecheck and
  package source lists, Xcode project (E1/E2 ids).

## Shipped

- Commit `92706fb`, tag `v0.20.0`, release with universal/arm64/x86_64 zips +
  SHA256SUMS: <https://github.com/aghamorad/Housekeeping/releases/tag/v0.20.0>
- Packaged build installed in `/Applications` (0.20.0); previous 0.18.6 app moved to
  `~/.Trash/housekeeping-app-backup-20261027-203743`; old dist in `/tmp/dist-0.19.0-backup`.
- Guide: `~/Desktop/Housekeeping — a noob's guide.md`.

## Not done / open

- The five panel buttons were verified through **Open** only; Scan/Ask/MediaDock/Bookbind
  share that same `withWindow` path and post notifications ContentView already handles,
  but were not clicked individually after the fix.
- Duplicate invisible windows still accumulate at launch (SwiftUI restores more than one
  and they are not closed). Harmless now that `liveWindow()` ignores them; a tidy-up was
  attempted in `AppDelegate` and removed because `window.close()` did not take effect.
- Menu-bar-only mode (`housekeeping.showInDock = 0`) is what Morad runs; the Dock policy
  change at launch may be part of why two windows appear.
- `lms` load/unload path is untested (LM Studio has no models installed here).
