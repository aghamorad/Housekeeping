# Housekeeping 0.27.0 — Apps and leftovers, removed together

This release rebuilds the uninstall experience and adds batch controls to Quarantine. It includes the fixes developed locally as 0.26.9, along with the new animated removal workspace.

## Fixed: app removal could fail without a useful explanation

The dedicated uninstaller was sending applications through the policy used for ordinary junk cleanup and discarding the resulting errors. Both uninstall screens now use one explicit app-removal engine and report the actual outcome.

When macOS refuses an ordinary move of a third-party app bundle, Housekeeping can request administrator approval for that specific app. The same recovery supports restoring or permanently deleting its recorded Quarantine copy. It does not rewrite ownership or permissions, install a persistent privileged helper, or elevate operations on arbitrary related folders. Canceling one permission request prevents a succession of password prompts for the rest of the batch.

Open apps offer **Quit to Uninstall**, which asks them to close normally so you can save your work. Housekeeping does not force-quit them.

## Apps and their matched related files are reviewed together

Matched preferences, caches, support files and other related items start included in the review. You can inspect their paths and categories, uncheck individual items, choose **Keep All Related Files**, or use **Include All**. The app count, included related-item count and total size update with the selection.

The application moves first. If it is missing, running, protected, or cannot be moved, its related data stays in place. Ambiguous folders matched to multiple installed apps are excluded, and the Leave Alone list applies in both screens and at the engine.

Related files can contain personal app data. Review the selection before confirming removal.

## An animated workspace that follows real work

Both uninstall entry points now show app icons, file-transfer animation, the current path, an item counter and a progress ring. Permission requests have their own visible status. Successful item outcomes appear after the recovery record has been saved.

The completion report separates apps removed, related items removed and storage held in Quarantine. Failed app rows expand with an explanation and **Show in Finder**. Interrupted operations retain their known successes rather than claiming that nothing moved. Removed apps disappear immediately from the browser while the inventory refreshes.

Animation pauses when the view is hidden or covered, the window is minimized, the app is inactive, permission is needed, or removal has finished. It respects Reduce Motion and adds no idle animation timer. Small removals can finish immediately; no artificial delay is added.

## Quarantine works in batches

Quarantine now supports search, **Select Batch**, **Select All Shown**, **Clear Selection**, **Put Selected Back**, **Delete Selected**, and **Empty Quarantine**. Permanent deletion has one confirmation showing the reviewed count, size and paths.

Bulk restore and deletion run off the interface thread. A restore collision preserves the existing file and continues with other selected items; failures remain visible for review.

**Moving files to Quarantine does not free their disk space.** You can restore them there. Permanent deletion frees the space and removes the recovery copy.

## Validation and downloads

- 358 safety assertions pass, including permission cancellation, app-before-data ordering, durable recovery records, partial failures, protection rules and bulk restore collisions.
- GUI validation and optimized Apple Silicon and Intel builds pass with warnings treated as errors.
- Offscreen SwiftUI layouts were checked in both themes. Live click-through behavior, animation timing and the real administrator dialog remain unverified because the native UI inspection bridge could not read the app window.
- Packages include the embedded housekeeper and media tools, retaining the Bookbind fixes from 0.26.8.

Choose **universal** for either Mac architecture, **arm64** for Apple Silicon, or **x86_64** for Intel. SHA-256 checksums accompany the downloads. Quit and reopen Housekeeping after any current media jobs finish to load the update.
