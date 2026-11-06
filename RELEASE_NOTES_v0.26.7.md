# Housekeeping 0.26.7

## The line between junk and something you cannot get back

Clean Up can no longer sweep an application's containers, its Application
Support, iCloud Drive, Mail, Messages, Calendars, Photos, Safari, Keychains,
Documents, Desktop, Music, Pictures, Movies, the system's own folders, any
`.app`, or any AI model library. Nor any folder holding recordings, documents
or a database. The rule is enforced twice: the shelves cannot offer these, and
the engine refuses to move them even when asked directly — so a scanner written
later cannot reach them either.

Replayed against the paths from this morning's sweep, the new rule refuses
1,002 of 1,103. The 101 that pass are caches, logs, cookie jars and saved window
positions.

## It now tells you what removal costs

"Safe to delete" and "free to delete" are different promises. A cache the app
rebuilds locally is both. A package store is only the first: it comes back over
the network. Items that must be downloaded again are marked in the list, and the
confirmation sheet says so plainly before anything moves:

> 4 of these are download caches (5.2 GB). Removing them frees the space now and
> takes it back over the network later. On a throttled or metered connection it
> can be quicker and cheaper to leave these where they are.

## Select all, and bulk uninstall

Every application row has a checkbox, each shelf has tick-all, the footer offers
Tick everything across every shelf, and selected apps uninstall in a single
confirmed transaction. Open applications are left out of a batch and named,
rather than blocking it.

## The command line

`housekeeping` is on the PATH and now covers Clean Up, read only:

    housekeeping clean            # what Clean Up offers, shelf by shelf
    housekeeping clean --json     # the same, for a script
    housekeeping quarantine list  # what is being held
    housekeeping scan --quick     # what is on this Mac

The verbs that move things stay in the app, where the exact paths are read back
before they go.

## Also fixed

A moved folder was recorded at the size of its directory entry — 96 bytes for a
3 GB model library. Sizes are now measured from contents.
