# Housekeeping 0.26.8

## Bookbind binds again

Bookbind's job worker held the lock around the whole job table while ffmpeg ran.
The page polls that table once a second to draw its progress, so the poll waited
behind the encode and the dialog sat on "Waiting for the engine" until the run
finished. The lock now covers the queue, not the work: the bar moves, the stage
names change, and Stop answers while the job is running.

The engine that shipped inside Housekeeping was a frozen copy of an older
`app.py`, so fixing the source alone would not have changed what the app ran.
The bundled server has been rebuilt from the current source, and the packaging
script now prefers the checkout's own engine over whatever happens to be in
`/Applications`.

## It no longer adopts a stale engine

Housekeeping used to treat any server answering on ports 8765–8774 as its own.
An old copy left behind by a previous run was adopted silently, and the new app
talked to the old code. The handshake now includes the engine's version: a
server from a different build is left alone, an orphan whose parent has died is
cleared out, and the app starts its own. A watchdog checks every four seconds
and turns a dead engine into a clear message with Try Again, instead of a page
that queues work into nothing.

## The menu bar answers the first click

The panel used to read every process on the machine and measure its own layout
before showing itself, which made a click on the octopus look like it had done
nothing. It now appears first and samples on the next turn of the run loop.
"Open App" also reorders a closed SwiftUI window directly, so the door works
even when the `openWindow` action is no longer valid.

Quitting gives the housekeeper's runtime and the phone helper 1.2 seconds each
before taking them away, so Quit no longer sits on a child process.

## Verified

The GUI type-checks with warnings treated as errors, all 318 safety assertions
pass, and a new Bookbind test holds a job open and proves the job table stays
readable while it runs. That test fails against the old engine and passes
against this one.
