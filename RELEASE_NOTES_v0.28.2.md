# Housekeeping 0.28.2 — Codex's canonical octopus comes to the menu bar

This release applies the canonical maid-octopus menu-bar mark from Codex's icon work
(PR #1) — the piece that had never been merged.

## What changed

- The menu bar now uses the **canonical maid-octopus mask**, embedded in the app so no
  resource registration or loose file can lose it: the original dark artwork becomes one
  tintable alpha mask, with the white cap, apron and details as transparent cut-outs. At
  18 pt it reads as the same character as the app icon, in light and dark menu bars.
- The existing gentle breathing animation, Reduce Motion handling and accessibility label
  are unchanged; the fallback drawn mark is still there if the embedded image ever fails
  to decode.

## Why it was missing

Codex's PR #1 ("Use the canonical maid-octopus template in the menu bar") was never merged:
it lived on `feature/monochrome-menu-bar-template` while releases were cut from `main` and
the integrated candidate branch. This release integrates that icon directly.

## Verified in this pass

- 375 safety assertions, 85 background/MCP assertions, static UI audit, warnings-as-errors
  type check and Xcode build pass.
- The embedded mask decodes to the expected 144 px silhouette; the app builds and runs with
  the new template; the menu bar item still opens the panel and carries its accessibility
  label.
- Universal package, signature, source stamp, CLI on both slices and Bookbind runtime are
  re-verified as usual.

## Limits, stated plainly

- macOS hides status items in the menu-bar overflow when the bar is full (several other
  menu-bar apps are running on this Mac). The icon is correct; the system decides whether it
  is visible without expanding the overflow chevron.
- Intel is verified through Rosetta on this Apple Silicon Mac; the build is ad-hoc signed.
