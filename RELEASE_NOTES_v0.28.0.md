# Housekeeping 0.28.0 — truthful controls, honest numbers, the mascot you already have

This release makes the cleaner show what it is really doing: selections stay inside
what you can see, related app data is opt-in, Quarantine reports what it is holding,
and the menu bar warns only when there is sustained evidence. The app icon is now
rendered from the canonical octopus mascot instead of the old static artwork.

## Clean Up

- **Bulk selection is scoped to what is visible.** "Select shown" and "Deselect shown"
  change only the rows in the current shelf and search; the footer says how many selected
  items sit outside the current view.
- **Checkboxes are disabled while a scan is running**, instead of appearing clickable and
  silently ignoring clicks. Items are selectable again the moment the scan finishes.
- **Stop Scan is real and bounded.** It no longer reports "nothing found" for categories
  it never reached; it says the scan was stopped and that unvisited categories are
  unchecked.
- **Real progress.** Scans and moves show measured completed/total counts through the
  shared progress component, and the move sheet says that selected items are *moved*
  into Quarantine — the disk space is held there, not freed, until permanent deletion.
- **Scan notes stay visible** on the status line (unreadable folders, skipped paths),
  rather than hiding behind "Scan Details".

## App Uninstaller

- **Related data starts excluded.** Matched preferences, caches and support folders are
  shown for inspection and must be ticked one by one (or with "Include All (review first)")
  before they move. The confirmation states this and shows exact paths.
- **Changing the search or a filter says what it did**: hidden selections are cleared and
  a notice reports how many, so a selection never disappears unexplained.
- Scans are cancellable, the refresh button reports a stopped scan, and the no-op controls
  during scanning are visibly disabled.

## Quarantine

- The screen reports **how many items are waiting and how much disk they hold**, and says
  plainly that restoring returns them while only permanent deletion frees space.
- **Select batch / Deselect batch** act only on the batch, scoped by search; changing the
  search deselects hidden rows so batch actions cannot touch what you cannot see.
- **Delete ALL waiting items…** is a separate, clearly irreversible action that includes
  hidden items and asks again.
- Manifests and history are read **off the main thread**, once per app activation, so
  returning from Finder no longer stalls the window.

## Models and the Housekeeper

- Loaded-versus-stored is kept honest: a model is shown as occupying memory only after its
  runtime reports it loaded. A configured default, symlink or file on disk is never
  presented as RAM use; each row says where to load/unload it.
- The inventory refreshes when the app regains focus and on demand, without continuous
  scanning.
- **First-party answers without the optional model**: where models live (only paths that
  actually exist), memory size, core count, and macOS thermal *pressure* (an OS category,
  never a pretend temperature). Open-ended questions still go to the model, and these
  answers are not fed back into the model's history.

## Menu bar

- A **sustained high CPU** warning (three consecutive readings above 90%) and **macOS
  thermal-pressure** warnings (serious/critical) appear as an accessible badge beside the
  octopus, with a tooltip and an accessibility label; the passive watch checks every 15
  seconds and does no process or GPU polling.
- **Refresh Health Status** in the right-click menu takes a fresh reading; it can clear a
  warning the current state no longer supports.
- The menu-bar animation honours Reduce Motion and stays still when nobody is looking
  (the existing idle-energy guarantees are unchanged; measured 0.0% CPU idle over ten
  minutes with the panel closed in this release pass).

## The mascot icon

The app icon is rendered at build time from `housekeeper_octopus_maid.png`, producing a
1024 px icon, the full 16–512 iconset and two unmasked Icon Composer layers. It is legible
at 32 px and the packaged `.icns` is generated, not hand-copied.

## Universal build

One download runs on Apple Silicon and Intel: the app, `llama-server` and Bookbind's frozen
runtime (Python extensions, ffmpeg, ffprobe) all contain arm64 and x86_64 code, link only
system/relative libraries and meet macOS 13. Packaging rejects thin native files and
externally resolved absolute dependencies. Source commit and build date are stamped inside
the bundle.

## Verified in this release pass

- 373 safety assertions and 85 background/fake-MCP assertions pass.
- Static UI no-op audit, warnings-as-errors type check and Xcode Debug build pass.
- Universal ZIP: 52 universal Mach-O files, ad-hoc signature verifies, stamped source
  commit matches the tag; CLI (`--version`, `help`, `where --json`) runs on arm64 and
  under Rosetta as x86_64; `llama-server` runs on both slices.
- Bookbind's packaged runtime exercises server, scan, transcode, AAC copy, chapters, tags
  and restore on arm64 and x86_64.
- Click-through pass on macOS 27.2 / M1 Pro: every sidebar tool opens, Clean Up scan and
  bulk selection, uninstall review with related data excluded, Quarantine refresh, Local
  Models status, first-party versus model answers in the chat, the menu-bar panel and its
  accessibility label, and quit/reopen all behave as described.

## Limits, stated plainly

- Intel execution was verified through Rosetta on this Apple Silicon Mac, not on a
  physical Intel machine.
- The build is ad-hoc signed, not notarized; a downloaded copy is not promised to open
  without a Gatekeeper step.
- Live Ollama/LM Studio model load/unload was not disturbed during this pass; the status
  rules were verified from their reports and unit assertions.
- The right-click menu items exist and are tested by code assertions, but macOS exposes no
  accessibility menu for a status item until a real right-click, so the menu was not
  enumerated by automation in this pass.

Made by Morad.
