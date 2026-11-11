# Housekeeping 0.28.3 — Mini-animated menu bar octopus, scanning banner & smart select

This release delivers the promised mini-animated menu bar octopus with moving arms, an in-app animated mascot scanning banner, 1-click Mole/Purge-style smart selection, and the updated high-resolution application icon.

## What changed

- **Mini-Animated Menu Bar Octopus**: 24-frame vector-rendered sequence in `StatusItemController` animating at 12 fps with wide 14–28° arm sweeps and curling side tentacles. Seamless 2.0-second period.
- **Zero Idle Drain**: When idle, the animation timer stops completely and parks at frame 0, consuming **0.0% CPU** to conserve battery and thermals.
- **In-App Octopus Scanning Banner**: `HousekeeperScanningBanner` features the animated Housekeeper mascot with moving arms, gentle breathing aura, live path inspection, category counters, and safety guarantees across Clean Up, App Uninstaller, and Updater.
- **Mole & Purge Style Smart Select**:
  - Clean Up: 1-click **`[✨ Smart Select Safe Junk]`** selects all safe, rebuildable everyday caches and uninstalled app orphans.
  - App Uninstaller: 1-click **`[✨ Smart Select Leftovers]`** isolates and selects all apps with orphaned containers/caches in `~/Library`.
  - App Updates: 1-click **`[Update All Ready]`** in the hero banner.
- **Codex High-Resolution Icon**: Updated `AppIcon.icns` and `AppIcon.png` in the repository and app bundle.
- **Author Attribution**: Canonical git author configured as `aghamorad <52329905+aghamorad@users.noreply.github.com>`.

## Verified in this pass

- All 375 safety assertions pass (`script/test_safety.sh`).
- Type check passes with warnings treated as errors (`script/typecheck.sh`).
- Zero idle CPU verified via `ps` (`0.0% CPU`).
- Universal binary (`arm64` + `x86_64`) packaged and verified.
