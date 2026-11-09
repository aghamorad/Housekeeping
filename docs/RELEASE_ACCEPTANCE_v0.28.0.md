# Housekeeping 0.28.0: universal release acceptance

This is a **candidate** until every blocker below is tested. Passing a macOS
compile or a code review cannot guarantee every SwiftUI button works or prove
that every person will find the app intuitive. Publish only after evidence.

## Automated gates (CI)

- [ ] Safety test suite: protected folders, symlinks, cleanup, scoped selection,
      reinstall data opt-in, quarantine records, manifest restore collisions.
- [ ] Background / fake-MCP regression tests (no live credentials required).
- [ ] Actual native Swift compile for the UI and menu bar, with all dependencies.
- [ ] 1024px mascot icon renderer and both unmasked layers are generated.
- [ ] Build arm64 and x86_64 executable from the same commit.
- [ ] Bundle the checksum-verified llama-server and all universal media runtimes,
      not compile-time placeholders. Check every nested Mach-O's architectures
      and platform minimums.
- [ ] Verify app codesign, SHA-256 and source-commit stamp after ZIP extraction.
- [ ] Execute the **packaged** app's read-only CLI: --version, help, where --json.
- [ ] Store the entire universal ZIP and checksum as a review artifact.
- [ ] Confirm clean install and rollback to v0.27.1 on a separate test machine.

## User experience and interaction matrix (must be executed on real Macs)

Test on M1/M1 Pro 16 GB and one Intel Mac, AC power and battery; macOS
13 where supported and a current macOS 27 machine. Cover light, dark,
high contrast, Reduce Motion, VoiceOver and keyboard-only navigation.

Each item should record: **click/action, actual effect, expected effect,
error state, recovery, screenshot/video and tested OS/hardware.**

- [ ] Every main navigation and menu-bar entry opens the correct panel exactly
      once and is dismissible. Check ⌘Q, Escape, app reopen and hidden Dock.
- [ ] Every checkbox has an accessible label; disabled work-in-progress controls
      are visibly disabled, not inert while appearing enabled.
- [ ] Clean Up: scan/stop/rescan, sort/search, expand/inspect, select only visible
      items, switch categories, clear-all, review exact paths, cancel, confirm,
      and observe a truthful completed/total count.
- [ ] Uninstaller: filter/search, select only shown apps, open-app refusal,
      inspect leftovers, keep all by default, selectively include one related
      file, cancel then re-enter confirmation and confirm exact planned paths.
- [ ] Quarantine: select shown; change search (hidden targets lose selection);
      batch select/deselect; restore; simulated original-path collision refusal;
      deletion with confirmation; delete-all explicitly includes hidden items.
      Verify no overwrite and that manifest/history states agree.
- [ ] Disk Browser, large-file scan, background activity and app-repair actions:
      no hidden deletions, accurate preview, refusal reason, and recovery.
- [ ] Models: disk-only vs runtime-resident status, Ollama and LM Studio
      targeted load/unload, Housekeeper exact GGUF selected, failure/timeout,
      network offline, repeated refresh and interrupted start/stop. Test RAM
      pressure and ensure other apps' models are not stopped inadvertently.
- [ ] Assistant: first-party status facts, actual visible paths, model-off
      diagnostics, chat with a functioning installed model, timeout, stop/cancel,
      very long reply, and zero fabricated filesystem claims.
- [ ] Menu: thermal pressure warnings, sustained CPU hysteresis, tooltip,
      right-click commands, refresh and accessible states. Test the passive
      monitor's idle energy draw and avoid calling OS pressure a temperature.
- [ ] Other tools: Setup Health, Updates, Routes, Phone, MediaDock, Bookbind,
      DNS, VPN, Battery, Fan, Settings and Self Update. Every enabled button
      must have a reproducible effect; external dependencies should show clear
      unavailable states rather than silent no-ops.
- [ ] Progress animations for real work should reflect measured progress, show
      a graceful indeterminate state where totals are unavailable, and stop
      when the window closes or macOS Reduce Motion is enabled.
- [ ] Icon legibility at 16, 32, 128 and 1024px, including dark/light modes;
      confirm the canonical octopus shape, not a generated substitute.

## Performance gates

Measure rather than assume parity with Mole/CleanMyMac:

- [ ] 10-minute idle (window closed, menu item installed): CPU, physical
      footprint, wakeups and energy impact; compare to v0.27.1.
- [ ] 10-minute idle (main window open): same metrics and no runaway animation.
- [ ] Typical 100 GB home-folder scan on HDD/APFS SSD, with interrupted scan,
      permission-denied folders and external volume detach.
- [ ] Simultaneous chat, app scan and model load on a 16 GB Mac without OOM,
      runaway swap or a stranded model server after quit.
- [ ] Clean uninstall and self-update smoke tests plus rollback.

## Release rule

Publish `v0.28.0` with `Housekeeping-macOS-universal.zip` only after all
critical tests are marked with concrete evidence. The CI candidate uses
ad-hoc code signing; notarization and the downloaded-app Gatekeeper
experience must be checked separately before advertising frictionless install.
If any critical item remains unchecked, leave the candidate as an Actions
artifact/draft PR, not a public stable release.
