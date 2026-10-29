## 0.21.1 — the Bookbind catalogue search reaches the catalogue

**Search online catalogue**, on the Bookbind screen, failed on this Mac with
`CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate`. Not a network
fault: a python.org Python on macOS has no root certificates until its
`Install Certificates.command` is run, and every https request fails verification
until then. The trust store is now named — `certifi`'s bundle when installed, macOS's
`/etc/ssl/cert.pem` otherwise — for the catalogue lookup and for cover downloads.
This is Bookbind 1.5.1 carried inside the app.

## 0.21.0 — bars instead of spinners, and a way forward

Two long operations answered "is it working" and never "how much longer". **Update Apps**
now shows a bar over the whole run — *3 of 5 updated*, with the name being worked on under
it — counted in rows, because a row is the only unit with a real length across Homebrew,
GitHub releases and the store. The reading pass behind it has a bar in two honest states:
travelling (*Counting what is installed*) while the bundles are being counted and there is
no denominator, then filling (*Reading 34 of 210*) once the inventory lands. Housekeeping's
own update shows *Step 3 of 6* over its six named steps.

The disk browser gained **Forward** (⌘]), beside Back, so the path bar can be walked in
both directions; opening anything new clears it. Measuring the disk now fills a bar over
the root's top-level folders — *5 of 134* — with the file count, bytes read and current
folder beneath it, instead of a spinner and two live counters.

Motion is back at twenty frames a second wherever the mark can be seen, which is smoother
than the twelve the menu bar ran before 0.20.1. The window costs about 2.5% of one core
while frontmost; idle in the menu bar it is still 0.0%.

## 0.20.1 — she stops breathing for an empty room

A copy of Housekeeping sitting in the menu bar with no window open was holding about 28%
of one core, all day — the top consumer on the machine by its own panel's reading — while
doing nothing at all. Two animations were responsible. The menu bar octopus was played
back on a twelve-frames-a-second timer installed at launch and never stopped, and the
window's marks were `TimelineView`s redrawing at twelve and twenty frames a second even
with `working: false`, from a window SwiftUI had closed but not torn down.

Motion is now spent from a budget: it runs while the app is active, while the mark's own
window is on screen, and for a moment at launch, and stops dead otherwise — a still frame,
no timer, no layout. A sleeping display stops it too. Two more costs fell out of the same
measurements: the panel's octopus is now still, because every animated frame in a popover
re-solves the panel's whole Auto Layout at about 1.4% of a core per frame; and the panel's
height reporting is debounced, because resizing the popover made it lay itself out again
and report a new height, round and round.

Measured after the change on the same Mac: 28% → 0.0% in the menu bar with the app in the
background; ~2.6% with the window open and frontmost; ~1.5% with the panel open.

## 0.20.0 — Local Models, and the octopus opens the window again

**Local Models** is a new screen, in Maintenance and in the Jobs menu (⇧⌘I):
everything installed for local inference in one list — Ollama, LM Studio, the
housekeeper's own weights, a running MLX server, and the Hugging Face cache — with
what each one weighs on disk, what each one is holding in memory now, and a Load or
Unload on every row that can take one. Nothing is downloaded from it and nothing is
deleted by it: the only thing this screen changes is memory.

Loading is measured before it is offered. A model that needs more memory than is
free is shown with the arithmetic — "this one needs about 6.4 GB and 3.9 GB is
free" — instead of a button, because on a 16 GB Mac a model that does not fit does
not fail politely. One model loads at a time, and **Unload Everything** is there for
when the machine needs the room back. LM Studio is read as a folder and never woken
by a command; Ollama is read through its own service; the Hugging Face cache is
listed as downloads, because a file that nothing can run is not a model you can load.

The five buttons at the foot of the menu bar panel — Open, Scan, Ask, MediaDock,
Bookbind — work again. They were bringing a window that SwiftUI had already finished
with to the front: it stays in the window list with its style mask intact, so it
still answers "can I become the main window", and ordering it forward put nothing on
screen. The live window was always there, one entry further down. A minimized window
is now restored rather than left in the Dock, and an app that is refused activation
still puts its window in front. The panel itself is also reachable without a mouse:
**Jobs ▸ Menu Bar Panel** (⇧⌘M).

## 0.19.0 — Bookbind takes a drop, and shows you the run

The Bookbind screen can now be handed a folder by dragging it in from the Finder,
and pressing Make the audiobook opens a panel that follows that one run to the end.

A folder dropped on the screen becomes the book's folder — the one the `.m4b` is
written into and the one the originals are moved aside inside — and loose audio
files are added to the chapter list already there. A veil comes up while files are
held over the page, and a drop that holds nothing playable says so rather than
doing nothing. The drop is caught by the app rather than by the page, because a web
page is never told where a dropped file lives and Bookbind needs the real path; the
same catcher is carried by Bookbind.app.

The run panel shows planning, then a real percentage with the audio done out of the
audio total, then checking, then moving the originals aside, and then Saved — the
exact path the book was written to, with Show in Finder. It can be stopped, sent to
the background and brought back with Progress on the job, and closed without
stopping anything. The bundled engine is Bookbind 1.5.0.

# Housekeeping changelog

## 0.18.6 — Optional Dock icon

Settings → Startup includes Show in Dock. Turning it off switches to accessory
mode immediately, leaving the menu-bar octopus and its window-opening and Quit
actions available. The preference survives relaunch; turning it back on restores
the Dock and Command-Tab entry. Existing windows stay available during the change.

## 0.18.5 — Platinum layout repair

Platinum uses the shared storage overview and a wrapping tool grid so every tool
stays reachable without horizontal scrolling. Repairs the compressed title strip,
uses compact system typography and responsive beveled buttons, and keeps shared
cards square and unlit. Backgrounds receive the resolved theme explicitly so
modern lighting does not leak into Platinum windows. Settings uses the native
SettingsLink, repairing the inactive toolbar action on current macOS.

## 0.18.4 — Burgundy surface refinement

Adds soft directional lighting to the burgundy workspace and sidebar, fine
highlighted edges and shaded panels, and a satin finish on primary controls.
The overview uses quieter typography, inset tool symbols, a graduated storage
meter, and subtle card hover feedback that respects Reduce Motion.

## 0.18.3 — Update-list caption

Adds “(probably pirated?)” beside the Unclear origin group heading.

## 0.18.2 — Visible model deletion in Settings

Settings shows downloaded models and their disk usage directly, with Delete model
and Delete all downloaded models actions. Confirmation lists the exact files and
size before removal. Empty storage is shown explicitly. Apple's system-managed
model is excluded.

## 0.18.1 — Specific folder explanations

Folder questions resolve against the complete held inventory and known app
locations, with the discussed path shown in chat. Exact paths and matching
selected folder names receive a read-only check of directory metadata and up to
16 immediate child names. File contents are not read. Missing and ambiguous
paths remain explicit; a short name cannot silently identify an unrelated folder.

Relevant folder facts and recorded app assessments precede general scan status,
so narrow provider contexts retain the subject. Explain this folder opens with
the path and known purpose where available. uv package-cache explanations cover
Python packages and versioned cache buckets; persistent uv Python installations
and tool data are identified separately, with official documentation references.
Chat remains optional, and no models are downloaded by folder lookup.

## 0.18.0 — Optional chatbot and model choices

Chat starts Off on fresh installations and upgrades without an explicit saved
choice. Choosing a model never downloads it. A separate Download button shows
the file size, and Not now leaves all Housekeeping tools available. Model choice
and download management are available in both the chat panel and Settings.

Choices include Gemma 3 1B (806 MB), Qwen 2.5 1.5B (986 MB), Qwen 3 1.7B
(1.11 GB), Gemma 2 2B (1.71 GB), and the optional Qwen 3 4B (2.50 GB).
Each download has its own resumable partial and pinned SHA-256. Users can pause,
switch, and remove individual downloads or all app-managed model files after
confirmation. Older weights are counted in the storage display.

Apple Intelligence uses the on-device system Foundation Model on eligible Macs
running macOS 26 or later, with availability checks and no separate Housekeeping
model download or cloud fallback. Other Macs retain the downloadable options.
Conversation framing supports general questions and Gemma's documented role
format. All chat providers share the app's recorded-assessment protections.

## 0.17.1 — Housekeeper conversation repair

Housekeeper uses Qwen3 4B Instruct in place of the previous 0.6B model. Downloads
are checked against the published SHA-256 before installation. Previous weights
are retained for rollback and are never silently used for new conversations.

Removal questions about a selected path quote the app's recorded assessment and
risk directly. Generated explanations cannot replace that recorded verdict.

Each question receives current app status and a bounded sample of recorded
findings. Context is carried as context, with complete recent conversation pairs
and the actual latest question. Repeated long answers are retried once and then
reported as an error. Responses can be stopped, conversations reset, and tools
opened directly from the panel. The model loads on the first question and releases
its memory 45 seconds after the panel closes. The burgundy appearance is retained.

## 0.17.0 — Modern desktop redesign

The modern appearance now uses a compact grouped sidebar with a visible current
selection, a retained burgundy palette with a warm light variant, larger shared typography, flat controls,
square selection boxes, and quiet panel borders. The animated circular launcher
is replaced by an overview showing live volume capacity and available storage,
with direct cleanup, disk, update, and utility actions. Active cleanup readings
can be reopened from the overview without starting over.

Cleanup actions sit below a separate selection summary. Rows and navigation
respond on hover, and tools remain accessible while work is running. The window
uses normal desktop resizing. Settings opens through the native SettingsLink on
macOS 14+, and includes System, Light, and Dark appearance choices. The classic
appearance remains available.

## 0.16.1 — Navigable tools and inspectable cleanup

Tools share the main window with persistent navigation. Disk, folder comparison,
route testing, and phone controllers retain state when switching tools. Contextual
help opens above the active tool. Update and environment readings survive navigation.

Clean Up gains search, largest/smallest/name/date sorting, per-category results as
scanning progresses, current-path measurement feedback, cancellation, visible-item
selection, and a count of selections outside the current view. Every candidate has
an inspector and Finder reveal. App-related files expand without truncation and
must be explicitly included in uninstall; confirmations list every exact path.
Matching no longer accepts an arbitrary embedded bundle-ID substring. Duplicate
and nested candidates are counted once. Protected apps and related data are filtered.

Disk browsing gains filtering and five sort orders. Main findings default to largest
first with smallest and name ordering available. Text distinguishes incomplete scans,
installed-app support data, unverified installers, and storage retained in Quarantine.

Assistant opening explanations now quote recorded facts directly. Answers from an
older subject are discarded after changing subjects.

Xcode now includes all six cleaner sources, all 23 rule files, and the assistant
runtime. The run script also stages Bookbind resources and verifies the app signature.

## 0.16.0 — Clean Up screen

A Clean Up screen, built the way a cleaner is expected to work: everything on one page, each
shelf named, and nothing moved without a tick and a typed word.

- **Clean Up is a screen now, not a suggestion.** A new door on the ring and a job in the bar
  open one page with six shelves: everyday junk (caches, logs, saved state, crash reports),
  developer caches (npm, pip, cargo, Gradle, Xcode, Homebrew and the rest), project build
  folders (`node_modules`, `build`, `dist` and friends), installers (`dmg`, `pkg`, `iso`, and
  archives over 200 MB), large files over 500 MB or over 200 MB and more than a year old, and
  apps you no longer need together with the files they left behind. Each shelf says how much
  it holds and how many items, and every row can be read before it is ticked.
- **Nothing here deletes anything.** Every move goes through the same engine the rest of the
  app uses: the manifest is written first, the files go to Quarantine, and they can be put
  back. Emptying the Trash is the one exception, and it is in the screen as its own shelf with
  its own warning, because macOS really does delete that.
- **Three confirmations, each in a word.** Cleaning asks for "clean", uninstalling for
  "uninstall", emptying the Trash for "delete". A run that only part-succeeds says which files
  stayed where they were instead of reporting success.
- **Right-click anything on the shelf.** Every row answers a right-click with Show in Finder,
  Ask the Housekeeper About This, Copy Path, and Leave This Alone. Leaving something alone puts
  it on the Left Alone list and takes it off the screen immediately — a file that stayed
  visible after being protected would make the reader doubt the list, not the file. The next
  scan honours it without being told.
- **The housekeeper explains and still does not decide.** Its prompt now refuses to offer a
  verdict of its own: it may only repeat the one Housekeeping gives it, and when there is no
  verdict in the briefing it says what the item is and leaves the decision alone. The opener
  on the Clean Up screen no longer invites a recommendation.
- **Copy that reads like a person wrote it.** "Folders that belong to no known app" is now
  "folders that belong to no app", the deep-sweep switch says what it does before it says what
  it costs, and every scan note is a sentence rather than a status line. The Trash note now
  says the real reason it can be unreadable — Full Disk Access — instead of guessing at a
  locked file.

# Housekeeping 0.15.0

MediaDock 9 and Bookbind are screens in this app now, not two other apps it kept in a drawer.

- **The kitchen sink.** Both used to sit behind an Extras door that started them as separate
  programs. That was the wrong shape: they were inside the bundle, but they were not inside the
  app — each one opened its own window, kept its own Dock presence while it ran, and had to be
  quit on its own. The door is gone, and so is the embedding. MediaDock's sources compile into
  this binary and its screen opens on top of the window like every other screen here; Bookbind
  keeps its Python engine, which starts with the app and stops with it, but its page is shown in
  the app's own web view rather than a browser window of its own.
- **The ring has twelve doors, and two of them are new.** MediaDock 9 and Bookbind sit beside
  scan, browse, routes, spoof and the disk-reading screen, with the same faces and the same one
  line of description as everything else. The menu bar panel has a door for each, and both are in
  the Jobs menu — MediaDock on ⇧⌘D, Bookbind on ⇧⌘O.
- **Closing the screen does not lose the work.** Bookbind's page is kept by the app rather than by
  the sheet, so a folder half chosen, or a merge still running, is still there when the screen is
  opened again. MediaDock keeps its log and its settings the same way.
- **Bookbind travels as its program files.** The release no longer carries a second `.app`, and no
  longer ships the 121 MB frozen server: `app.py`, `bookbind_cli.py` and `static/` go into
  `Contents/Resources/Bookbind`, and the engine runs them with the Python already on the Mac. If
  Python or the tag reader is missing, the screen says which one and how to get it, rather than
  failing silently.
- **MediaDock's own updater is gone.** It compared its version against a bundle that is no longer
  MediaDock's, so it could only ever be wrong. Housekeeping's self-update covers both.
- **Both screens wear the house's appearance.** MediaDock arrived with its own cream-and-steel
  palette and Bookbind's page with a light blue one; inside this app both now use the maroon glass
  the rest of the window is made of — the same ink, the same red, the same rounded panels and
  system type. MediaDock reads the active theme and switches back to its retro face when the app is
  set to classic9; Bookbind's page gets a stylesheet that overrides only the colours it already
  reads, so its layout and behaviour are unchanged and the skin comes back after every reload.
- **The menu bar panel answers back.** Every room and every hand is a button now. Clicking
  PROCESSOR, MEMORY, DISK, NETWORK, GRAPHICS or BATTERY opens a page in the panel itself: the live
  reading, what the number actually counts, and what sits behind it — the busiest hands for the
  processor, the biggest holders for memory, because "11.6 of 16 GB" is a figure and not an
  explanation. Clicking a hand opens it by name, with its share of one core, the memory it is
  holding, and quit or force-quit behind a confirmation that says what each one does. Every page
  ends with a door to the housekeeper, opened already holding that reading, so the question can be
  asked in the panel's own numbers. The panel resizes to whichever page is showing, and closes
  back to the overview.
- **Every screen has a way back.** MediaDock 9 and Bookbind open over the window like every other
  screen, but neither carried a way out of its own: MediaDock had none at all, and Bookbind's only
  exit was a Done at the bottom of a 780-point page. Both now start with a Back at the top left,
  the same place the panel's room and process pages put theirs, and it says where it goes.
- **The findings list can be organised by size.** The filter bar now carries a small Kind / Size
  control beside the search field. Kind is how this list has always read — one heading per kind of
  residue, each group biggest first. Size drops the headings and puts every finding in one list,
  biggest first, so the total in the header can be walked down from the largest thing; its heading
  keeps the count and the total where the grouped headings put theirs. It changes the order only —
  never what was found, what it is, or what is ticked.
- **The update list is grouped, not one wall.** Seven channels used to be flattened into a single
  alphabetical list under one heading. They are now five families — Homebrew, Applications, App
  Store, macOS, Unclear origin — with a chip strip above them carrying the count in each, and one
  heading per family that says how many are in it and what Housekeeping does about them. The
  heading's tick box selects the whole family, and its own Update button runs only that family.
  Each row grew the icon it deserves: Homebrew's burnt-orange mug, the App Store bag, and, for a
  real application, its actual icon read off the bundle.
- **The Housekeeper answers the question in front of it.** Asked three questions in a row about one
  list, it used to answer the third with a paraphrase of the first. It is now told to answer only
  what was asked and to never reuse a sentence it has already said, and the runtime runs a little
  warmer with a repetition penalty. The briefing also now states, for a family with nothing in it,
  what Housekeeping would do about it — previously the App Store had no line of its own and the
  model, given a gap, filled it with an invented reason.

# Housekeeping 0.14.0

The window opens on a picture of everything it can do, and two other programs now travel inside it.

- **The welcome screen is a ring of doors.** Four jobs sit around the octopus in a circle — scan,
  browse, routes, spoof — with Extras beneath and the disk-reading screen on its own. Each door is a
  disc with a colour and a face, and each says in a line what it is for. The cue is Jeopardy's board:
  a shape is remembered before a label is read, and a reader who does not yet know what the app does
  can find out by looking rather than by opening every menu.
- **Extras.** MediaDock 9 and Bookbind — the two other apps built here — ship inside the bundle, so
  the Extras screen can start them without being told where they live. A build made from a checkout
  that has not built them says so instead of offering a dead button. Bookbind's program files are
  staged into its embedded copy the way its own release workflow stages them; without that the
  copied bundle cannot find its own code and opens to an error.
- **One sheet at a time.** Fourteen independent presentation flags became one optional screen.
  AppKit attaches a single sheet to a window, so the flags were never fourteen windows — they were
  one window and an invisible queue: ask for Extras while Update Apps was open and Extras waited
  behind it, then appeared when Update Apps closed as though the click had just happened. The flags
  survive as computed properties, so every existing call site reads unchanged, and the screen asked
  for last is the one that shows.
- **The command menu is called Jobs.** SwiftUI names the app menu after the app, so a command menu
  called Housekeeping put the name in the menu bar twice.
- **The update list can be chosen in groups.** Every channel heading now carries its own tick box and
  a link that updates only that group — Homebrew applications, Homebrew packages, GitHub releases —
  and Select all and Select none sit beside the ticked count at the bottom, acting on whatever the
  list is showing. Leaving Homebrew alone while replacing three bundles no longer means walking the
  list row by row. A group Housekeeping cannot finish itself shows a dash in that box rather than a
  tick, so the control never offers something the Update button would then ignore.

- **The octopus now opens a live panel.** Clicking the menu bar icon no longer drops a list of
  commands; it opens a small window on the machine as it is this second — a verdict and a score, the
  processor with the last half-minute drawn behind it, memory, disk, network, graphics and battery,
  and the three busiest programs by name. The numbers are readings, not stored ones: each is the
  difference between two samples a second apart, which is the only way a counter that climbs forever
  can say anything at all. The octopus in the panel works harder as the processor does. Nothing is
  measured while the panel is shut. The old menu is still there on a right-click.
- **Open at login.** A switch in the panel turns it on and off, and it reports what is true rather
  than what was asked: if macOS is waiting for approval it says so and offers the button, and if it
  was turned off somewhere else, the switch shows that the next time the panel opens.

# Housekeeping 0.13.0

Housekeeping gets a face, a way to update itself, and a command line other apps can call. The engine
underneath is the one that has been reading disks since the first release; what changed is how much of
it a reader can see, and how little of it now has to be reached through the window.

- **She is drawn, not pasted.** The housekeeper — the octopus — is the app's mark, and she is built
  from paths rather than shipped as a picture. That is what lets her stay sharp at eighteen points in
  the menu bar and at a hundred and four on the sweep screen from one set of coordinates, and it is
  what lets her move: she breathes, her hands swing while she is working, and her eyes follow the room.
  When she is not working she settles to a slow breath rather than stopping, because a mark that has
  gone still reads as a window that has stopped. The one place she is not drawn is the app icon, which
  has to survive being shrunk by the Dock and rendered on a plinth by a system that is not asked first.
- **The navigation is a rail, not a row of tabs.** The sections sit down the left as coloured discs set
  into sockets, each with its own colour and depth, each arriving as the window opens. A flat row of
  words asks a reader to read; a rail of shapes is scanned once and then known, and the shape is
  remembered before the word is. The section a reader is in is the one lit up, so the rail also answers
  where they are without a title repeating it.
- **The update check reads commits, not release pages.** Housekeeping updates itself from the folder it
  was built from: it asks GitHub how far behind the local copy is, fast-forwards the tree, builds a new
  copy beside the old one, verifies it, and only then hands over — so a failed build never replaces a
  working app. Releases are published by hand and lag behind `main`, which is why the check compares
  commits: a reader running the newest code would otherwise be told there was nothing new. It refuses
  to update over changes that are not committed rather than reconciling two histories, it never
  downloads a build, and it says which of those two it hit.
- **A command line.** `housekeeping` reads the same disk the window reads and prints in one line what
  the window shows in a panel — `scan`, `explain`, `where`, `quarantine list` and `quarantine restore`,
  plus `version` and `help`. It exists so other tools can ask what is taking space without a window
  having to open, and it is deliberately the same engine: nothing the command line can do is something
  the window cannot, and nothing it does moves a file without being told to.
- **The copy was rewritten for someone who does not already know the words.** "Also measure folders
  that belong to no known app" replaced a line about unclaimed paths; the door to the question box is
  called "Talk to the Housekeeper" instead of "Ask about this". The app knows what sixteen apps and
  tools keep their files, and it now says it in those words. Where a thing cannot be explained in
  plain words — what is inside a folder nobody claims — it says what it does not know instead of
  sounding as if it does.

# Housekeeping 0.12.0

Housekeeping can now test the routes a VPN client offers and say which of them actually carry traffic.
It is the first part of the app that is about the network rather than the disk, and the first that
changes the state of the machine while it is open.

- **One server, one setting, one at a time.** A VPN client holds a single tunnel, so a route can only be
  tried alone: connect, measure, disconnect, next. That is the whole design, and it is also the reason
  the screen warns before it starts rather than after — for the length of a run the connection drops and
  comes back over and over. That is the test working, not a fault.
- **What it measures.** Time to connect, round-trip time, jitter, packet loss, and — on the deeper
  passes — a real page fetched through the tunnel. A route that connects but returns nothing is failed,
  not merely slow, which is the failure a ping alone cannot see. Before any of it, it measures the same
  things with the VPN off, so every result has something to be compared against, and each route is
  sorted into Excellent, Good, Usable, Poor or Failed.
- **Servers, protocols and ports are all tried.** A client's own window lists its servers but says
  nothing about which of their settings this line will carry, and the answer is rarely the same for all
  of them. Windscribe and ExpressVPN are read directly from their command-line tools, each with the
  protocols and ports that provider actually offers — ExpressVPN has no port axis, so it is not asked
  for one.
- **Two ways in, one engine underneath.** Simple asks which countries to cover, offers three depths —
  Quick for a first look, Thorough for every datacenter over both TCP and UDP, Careful for the real page
  load that catches a route which connects but carries nothing — and explains the result in plain words.
  Advanced exposes every control, including the timeouts and the probes. Both drive the same run, so
  there is one behaviour with two doors.
- **It leaves the machine disconnected.** Always, including when stopped early. It never connects to a
  server that was not on the list it was given, and it never leaves the tunnel up on the last one it
  tried as a convenience. A run in progress also holds the sheet open, because a test that vanished
  behind a stray Escape would take its result — and its Stop button — with it.
- **A client it cannot drive is said so, not worked around.** If the command-line tool is missing or not
  signed in, the screen says that and offers nothing else. Anything the provider needs fixed first — a
  daemon that is not running, for instance — is shown as an advisory to act on, never repaired on your
  behalf.
- **A log, if you want one.** At the end of a run it asks whether to keep a record, and if you say yes it
  appends a section to `~/Documents/Housekeeping/route-log.md`: the date and time, the provider, and
  which country, city, protocol and port carried traffic and which did not. One file rather than one per
  run, so a month of results can be read in a single place. The question is asked, never assumed.

# Housekeeping 0.11.0

Housekeeping can now hold two folders that are supposed to be the same thing up against each other — a
library and its backup — say what is on one side and not the other, and put the missing piece where it
belongs. It is the first part of the app that copies anything.

- **Two folders.** A new screen compares a pair — a library against its backup, a working drive against
  the archive — and reports the difference in both directions: what B has that A has not, what A has
  that B has not, what the two sides call the same name but hold different bytes, and what moved or was
  renamed rather than lost. Matching is by **content**, never by path. This matters more than it sounds:
  compare by path and every past reorganisation reads as a library deleted and rewritten, which is the
  one answer that would make this screen useless and dangerous at the same time.
- **Reading a file only when it has to.** Size and a modified date are enough to call two files the same
  almost every time, so that is what is read first, and the file itself is opened and hashed only when
  those two disagree. The one place a hash is unavoidable — working out that a file is missing from A
  because it is sitting under a different name in B — is capped, so a pair with hundreds of thousands of
  files reports what it could establish rather than running all night.
- **An unmounted drive is not an empty drive.** If a side is not there, Housekeeping says so and reports
  no findings at all. It never announces that the whole library is missing because a drive is in a
  drawer, which is the failure that would tempt somebody into 'restoring' a perfectly good archive over
  a good one.
- **A side can be closed.** A pair can name one side as frozen — the archived drive that is not being
  added to any more — and the direction switch is then unavailable rather than merely discouraged. The
  comparison still runs, because knowing what a closed archive is missing is worth knowing; what stops
  is the writing. When the plan is empty for that reason the screen says so in a sentence, so an empty
  plan never reads as 'nothing is missing'.
- **Some things are absent on purpose.** A path can be marked as existing on one side by design, and
  then its absence is not counted as a gap — but it is still compared if it *is* present on both sides.
  Photos that only ever lived on the working drive are the case this was built for.
- **Copy is the one new thing it does.** Until now Housekeeping only ever moved a file into Quarantine.
  Reconciling has to be able to write the missing copy into place, so that capability was added, and it
  is deliberately the narrowest version of it: a copy goes only into a pair's own writable side, a
  destination that resolves outside that side is refused rather than executed, and nothing is ever
  deleted to make room. Anything that has to come *off* a disk still goes through the same Quarantine,
  listed on the same screen and put back by the same Restore.
- **Every run leaves a record.** What was copied, what was moved aside, where each one went and what
  came of it, written as one line per change to a file you can open. An undo needs to know where a file
  went, so the record names the destination rather than only the source — and the screen can take you
  straight to it.
- **Nothing is ever ticked for you.** The plan arrives with no row selected; copies are one button, and
  everything a run would move aside is a separate, deliberate one. Every row states what it will do
  before it can be pressed.
- **What exists in only one place is named, not measured.** The record already holds libraries that have
  no second copy anywhere — the music library, the Iranian TV archive — and the screen says so in as
  many words rather than offering to compare them against nothing.
- **The Xcode project names every source file again.** The project file had stopped listing the app's
  setup-check, housekeeper and menu-bar sources, so building it in Xcode or through `build_and_run.sh`
  had been failing on files that were sitting right there. It lists them now, and the app builds and
  runs from Xcode as it did before.

# Housekeeping 0.10.0

Housekeeping can now look at the tools that are already installed and say what is wrong with them —
and, when you agree one at a time, put it right. It is the first part of the app that runs anything.

- **The setup check.** A new screen reads the machine the way a person debugging a broken command
  would: which program actually runs when you type a name, whether the link that reaches it leads
  anywhere, whether what a package installed is linked and complete, whether a package manager has
  been superseded, and whether something was put in place by hand rather than by the tool that
  claims to own it. Each thing it finds is one row, said in a sentence.
- **It runs, and that is new.** Until now Housekeeping measured and moved files and ran nothing.
  This screen runs Homebrew's own commands and rewrites a line of shell configuration. The safety
  model changes to match: nothing is ticked for you, nothing runs until you tick a row and press the
  button, and every row states in advance what it will change and what would undo it before it is
  offered.
- **One finding, one action, one row.** A fix that is really a sequence is a script, and a script is
  not a thing anyone can consent to. So a finding that would need two steps is reported as it is,
  with the commands shown, and no button. Anything that does have a button changes exactly one
  thing.
- **Moves go through the same Quarantine.** A repair that takes something off the disk — a dead
  symlink, a stray copy of a program shadowing the real one — moves it into the folder an ordinary
  cleanup uses, recorded in the same manifest, listed on the same Manage Quarantine screen, put back
  by the same Restore. There is one recovery screen, not two that can drift.
- **A failure is that row's own news.** Repairing proceeds in the order given rather than stopping
  at the first refusal, and each failure is reported against the row it belongs to, so one thing
  needing an administrator does not hide the twelve that worked.
- **Nothing that needs a password is run.** A few of the things the check can find — a Python
  installed by hand, a superseded package manager — can only be removed as an administrator.
  Housekeeping shows the command and does not run it, because it does not ask for your password.
  A finding it cannot fix says so in as many words rather than offering a button that would fail.
- **The whole Mac in one press.** "Look Everywhere" runs every reading the app has — the disk, the
  setup, the update list — one after another, with the octopus visibly working while it goes, and
  hands back a single account of what each one found. It is automated exactly as far as reading:
  nothing is ticked, moved, installed or fixed, and each count on the screen it leaves behind is a
  door to the screen that already asks before it changes anything. Stopping it stops the reading in
  flight and nothing else, because nothing had been changed for the stop to undo.
- **Every door is on the bar, in the order a reader wants them.** The row across the top no longer
  carries some of the jobs and leaves the rest in the app menu: the setup check — which had a menu
  item and no button anywhere in the window — and Settings are on it beside the others, and the row
  is grouped rather than one flat run. What reads the Mac and changes nothing comes first; then the
  two drawers holding what Housekeeping has already moved aside or been told to leave alone; and,
  apart from both, the two things that are about the app itself: its settings, and the housekeeper.
  The app menu still carries every one of them as a shortcut, so nothing here is the only way to
  reach a job — only the way that is visible.
- **The housekeeper is reachable from everywhere.** Every screen and every sheet now carries a way
  to open it: the bar across the top of the main screen, the Quarantine screen and each item in it,
  every update row, the disk browser on the folder you are standing in, the setup check, each
  cleanup candidate, the Settings window, and the last confirmation before a move. What it is handed
  is that screen's own subject, drawn from the same sentences the screen already prints, so the
  reader and the model are looking at the identical account.
- **A dead link is no longer mistaken for an empty space.** Restore and Undo asked whether anything
  was at the original path by following the link, which answers *no* for a link whose target is
  gone — exactly the items this app promises to hand back. They now check for the item itself, so a
  broken symlink waiting at a path is seen and refused rather than quietly written over.

# Housekeeping 0.9.0

There is now someone in the house. An octopus sits in the menu bar, and when you want to know what
something is, you ask it instead of reading a table.

- **The Housekeeper (⌘K).** A small local model that explains what Housekeeping found. It talks in
  plain English about one finding at a time — what the thing is, why it is on your disk, and what
  Housekeeping's own verdict was. It arrives as a download on first use, around 380 MB, and runs
  entirely on your Mac; nothing about your files leaves the machine.
- **It explains. It does not decide.** The verdict you act on — *Ready to go*, *Worth a look*,
  *Leave it alone* — is drawn by Housekeeping, above the octopus's answer, in the same words as
  everywhere else in the app. The model is handed that verdict as a fact and is never asked whether
  something should go, never sees what is ticked, and cannot clean anything. That division is why a
  model this small is enough: the judgement was already made and written down by hand, and the
  model's only job is to say it in sentences.
- **An octopus in the menu bar.** The mark from the app icon, animated — breathing, tentacles
  drifting — and still, one colour, cut into a template image so it matches whatever the menu bar is
  doing. The menu opens the app, opens the Housekeeper on its own, or starts a scan.
- **Ask about this one.** The button sits directly under the verdict on any finding, which is where
  the question "but why?" actually arrives.
- **The app wears the octopus's colour.** The icon is the octopus itself — the tile, not a picture
  sitting inside one — and the app now wears the same red: the lit red of its face for anything that
  wants attention, the shaded red it rolls off into for the hairlines, and the deep maroon underneath
  both for the window and every panel in it. The three verdicts moved off the system's own orange and
  red so that a warning can never be mistaken for the brand. *Mac OS 9 / Platinum* is unchanged, being
  an authentic alternate appearance rather than a theme to be tinted.

The housekeeper needs macOS 13 or later, as the app does. Its runtime is a single static binary
inside the bundle, and on first use it downloads its model once and keeps it in Application Support.

The distributed build is ad-hoc signed for local use on macOS 13 or later. It is not notarized, so
macOS may warn you the first time you open it.

# Housekeeping 0.8.0

Every row now says what the thing is. A window that lists `dav1d`, `cjson` and `Google Chrome` and
stops there is a name and a version number, which is no help to anyone deciding whether to update
it. Alongside that, the four jobs are visible the moment the window opens instead of buried in a
menu, and the Update Apps screen was cut back to what it is for.

- **Every line explains what it is.** An application now carries one sentence under its name saying
  what it is and who made it — `A video app from Acme Ltd., installed with Homebrew.` For a Homebrew
  package, whose name is the only thing on screen that means anything, the sentence is Homebrew's
  own description of it: written by someone who knows what the program does, rather than assembled
  from the parts. A package Homebrew has no description for is simply left as its name.
- **The explanation comes off the disk, or it does not come at all.** Nothing is inferred from a
  name. A `.app` is described from what it says about itself — the category it files under, the
  maker in its own copyright line, whether it carries an App Store receipt, a Homebrew cask, a
  GitHub source or an update feed. Where a bundle states none of that, Housekeeping reads the maker
  out of the signing certificate instead, which is the one thing still standing for software
  distributed outside the App Store. A bundle that names nobody stays silent rather than being given
  a maker it never claimed.
- **The four jobs are on screen.** Quarantine, Left Alone, Browse the Disk and Update Apps used to
  be reachable only through the menu, which made the app look like it did one thing. They are now a
  permanent row across the top of every screen, with the keyboard shortcuts unchanged.
- **Update Apps says less and does more.** The header reports what came of the check rather than
  restating the whole inventory; when a filter or a search leaves the list empty, the empty state
  says which one it was and offers a **Show all** button that clears it, instead of leaving a blank
  panel to be puzzled over.

The distributed build is ad-hoc signed for local use on macOS 13 or later. It is not notarized, so
macOS may warn you the first time you open it.

# Housekeeping 0.7.0

A second job beside cleanup: what is installed, where each thing came from, and whether any of it is
out of date. Plus two fixes — the whole-home scan now runs to the end, and findings stop saying "no
rule".

- Adds **Update Apps** (⌘⇧U), a list of everything on the Mac that could be updated, grouped by
  where its updates actually come from rather than by name. Software does not arrive by one route:
  a Homebrew cask is a command and an answer, an App Store app belongs to the store and can only be
  asked, and an app that came as a file has to be fetched and swapped. One "Update All" over all of
  them would be wrong for at least three of the four, so the groups are the screen.
- **Nothing is guessed from an app's name.** Each row's group comes from evidence on disk — a
  Homebrew receipt, a Homebrew list, an App Store receipt, the bundle's own update feed, and the
  signature's developer team. A copy whose signature no longer matches its origin is reported as
  altered and is never touched. Every row can unfold the observations it was decided from, because
  a reader who disagrees with a verdict should be able to see exactly which fact they disagree with.
- **Update All only covers what it can finish.** Rows in the App Store, macOS, and unidentified
  groups carry no tick box at all rather than one the button would then skip, and each says why. An
  app with no `mas` installed offers to open the store's Updates page instead. A Homebrew package
  held by `brew pin` is reported as pinned and left alone, since the pin is the point.
- **Apps that update themselves are read, not replaced blindly.** For a bundle carrying its own
  feed, Housekeeping reads the version from the feed and, when it does install, fetches the same
  enclosure the app's own updater would, under the same checks.
- **Ignore from now on**, per row, for anything you never want offered again — and the way back,
  naming every entry, in Settings. Ignoring installs nothing and deletes nothing.
- Fixes the whole-home scan stopping at a wall-clock budget partway through the disk. It now runs
  until it has finished, so a folder reached by going down is reached again on the way back up
  instead of the walk being abandoned where the timer ran out.
- Fixes the wording on findings Housekeeping has no entry for. Rows said `No Rule`, which tells a
  reader nothing; they now say `Unrecognised`, and the sentences around them say that Housekeeping
  has nothing on file for that folder rather than talking about rules. Saved scans keep the old
  value, so nothing already on disk is rewritten.

The distributed build is ad-hoc signed for local use on macOS 13 or later. It is not notarized, so
macOS may warn you the first time you open it.

# Housekeeping 0.6.0

The name catches up with the app, and the app starts telling an old copy that a newer one exists.

- Renames the application to `Housekeeping.app`. It has called itself Housekeeping on screen since
  0.4.1, while the bundle, the download and the folder it kept its own state in still carried the
  former name.
- Brings the old quarantine forward instead of starting an empty one. Anything quarantined by an
  earlier build sits in a folder named after the former app, in one of two places — hidden inside
  Application Support, or beside the home folder. First launch walks both, transaction by
  transaction, into `~/Housekeeping Quarantine`. Each transaction's manifest is re-pointed at its
  new location before the move counts as done, and the move is undone if that rewrite fails, because
  a manifest still naming the old path leaves its items unrestorable.
- Moves the support folder in one go rather than teaching every path in the application two names: a
  folder renamed is one move, a folder read from two places is two chances to disagree. If a folder
  already exists under the new name the old one is left exactly where it is — doing nothing costs
  someone one folder moved by hand, and guessing costs them a file they cannot find.
- Adds the update notice. Once the window is drawn, and never before, Housekeeping asks GitHub for
  the newest release tag with a nine-second limit. A copy that is behind shows a line in the footer
  reading `Version 0.7.0 is out`, and Settings → About carries the same answer as one row: the
  newer release as a link, `None — this is the newest`, or `Could not check`. The third is
  deliberately not the second. Offline, throttled or rate-limited is not news that you are current,
  and a row that said so would tell someone on an old copy to sit still. Nothing is downloaded and
  nothing is installed; the link opens the releases page.

The distributed build is ad-hoc signed for local use on macOS 13 or later. It is not notarized.

# Housekeeping 0.5.0

Two things this release is about. One is that Housekeeping was blind to a whole shelf of leftovers, and
the other is that it was wrong about a class of folder it did report.

- Scans sandbox containers for the first time. A sandbox container is the private storage area
  macOS gives an application — its documents, its settings, and anything it downloaded — and
  deleting the application does not delete the container. That is where a removed application most
  often leaves the most behind, and Housekeeping had never looked inside it. A Mac carries well over a
  thousand of them, though, and almost every one is a few kilobytes of widget or extension state
  belonging to an application that is still installed. Those are measured and then left off the
  list, and the note above the results says how many there were, what they came to together, and
  that they were left out rather than missed.
- Fixes a mislabelling that mattered. The sweep that looks for folders no rule describes was
  calling Apple's own folders, and folders belonging to applications that are installed, residue
  from something you had removed — Telegram Desktop's data folder among them, because its name
  does not look like a bundle identifier. Vendor and system namespaces are now declared in one
  place and used by both audits, and a folder whose name marks it as belonging to macOS or to a
  large vendor is described as that, instead of as something you deleted.
- Adds the applications that never install as an application bundle, so had nothing for Housekeeping to
  find them by: MLX, Whisper.cpp, MacWhisper, GPT4All, Jan, Draw Things, and ComfyUI. Between them
  these hold the multi-gigabyte model files that prompted this whole application. Claude also picks
  up the second data folder it keeps on this Mac.
- Finds the residue Microsoft Office leaves behind when an add-in is taken off the disk without
  Office being told — the state that left Word, Excel, and PowerPoint complaining on every launch
  after Acrobat was uninstalled. Two things are looked for: a `~$` companion file sitting in a
  startup folder while its application is closed, and an add-in path an application still holds in
  its own settings while the file it names is gone.
- Says what each application will do on its next launch, because the two halves of that problem
  are not the same. An entry switched on makes the application go looking for a file that is not
  there and report it missing; an entry switched off is dormant and needs nothing done to it; and
  when the switch cannot be found in the settings file, Housekeeping says so rather than guessing,
  because a switched-off entry and an entry with no visible switch look identical from outside.
- Says plainly when removing the settings file is not the whole fix. It does clear the entry, and
  it takes every other setting for that application with it. Clearing one entry is a step inside
  the application's own add-in list, which Housekeeping cannot take for you.
- Reports its own blind spots. If a startup folder or a settings file cannot be read, the results
  say which one and what is therefore missing. An empty list and a folder nobody could open look
  the same on screen, and only one of them means the Mac is clean.
- Never matches an add-in to its companion file by name. Word's naming is not consistent enough to
  build a rule on, and one built on it would report files that are perfectly fine.

The distributed build is ad-hoc signed for local use on macOS 13 or later. It is not notarized.

# Housekeeping 0.4.1

Found by opening the shipped 0.4.0 build and reading it, rather than by running the tests — every
item below is a thing the tests could not have caught, because each one is about how the app
reads rather than what it computes.

- Fixes two panels that drew a large blank box around a short list. A `ScrollView` claims all the
  height it is offered, so a one-item quarantine review and a one-line hidden-detail note each left
  an empty block under their content. Both now grow to their content and stop at a cap.
- Fixes the count in the quarantine review, which read “1 path(s)”.
- Writes the app's name as **Housekeeping** everywhere in its own prose, matching the title bar and the
  Info.plist display name. Earlier builds called themselves Housekeeping in about two dozen sentences
  while the window above them said Housekeeping. The `~/Housekeeping Quarantine` folder and the
  `Library/Application Support/Housekeeping` directory deliberately keep their existing names — renaming
  either would orphan everything already quarantined and the records that sit beside it.
- Fixes the printed version number, which was written out by hand in the results footer, in
  Settings, and in `Info.plist` as three separate strings. The two the app draws now read
  `CFBundleShortVersionString`, so they cannot disagree with the bundle again.

The distributed build is ad-hoc signed for local use on macOS 13 or later. It is not notarized.

# Housekeeping 0.4.0

This release is about being able to tell Housekeeping what to leave alone, and about it refusing the things it should refuse without being told.

- Adds the left-alone list. Press **Leave It Alone** on any finding and that path stops being offered, on this scan and every later one, until it is taken off again. The list is a plain JSON file at `~/Library/Application Support/Housekeeping/Protection.json`, readable in any text editor. Protecting a folder protects everything inside it. The list can only ever make Housekeeping more careful: nothing on it can make an unproven path eligible.
- Adds a working-copy guard, taken from [Mole](https://github.com/tw93/mole)'s purge step. Before any folder is offered, Housekeeping looks three levels inside it for a Git repository — including the `.git` file a worktree uses — a deployment key named or extended like one, or a credential file. A match refuses the folder whatever its name suggests, and the refusal names the file and where inside the folder it was found. The answer is memoised per path and re-read when a scan begins.
- Adds help text to every control that needed it, and gives the primary **Scan My Mac** button an explanation for the first time. Because `ThemeButton` routes help to the accessibility hint as well, these were VoiceOver gaps too.
- Ships a universal binary for Apple silicon and Intel, with separate downloads for each architecture alongside it.
- Documents four rule files that had been shipping undocumented (`chrome.json`, `codex.json`, `gapcode.json`, `gemini.json`), and corrects the architecture listing, which named a source file that never existed.
- Fixes `script/package_release.sh`, which had gone stale: it did not list `ProtectionList.swift` and so could no longer build the app at all, and it was arm64-only.

The distributed build is ad-hoc signed for local use on macOS 13 or later. It is not notarized.

# Housekeeping 0.3.0

This release adds a phantom application audit for residue left behind after an application is removed.

- Checks user Application Support, Preferences, HTTP storage, Saved Application State, Group Containers, Caches, Logs, and LaunchAgents.
- Compares candidate namespaces with installed application bundles and bundle identifiers.
- Excludes Apple-owned, Housekeeping, and known shared/system namespaces.
- Labels likely remnants with their exact path, measured size, reason, and review warning.
- Keeps persistent data, preferences, web storage, and launch agents review-only.
- Keeps low-risk orphan caches and logs compatible with the existing reversible quarantine workflow.
- Repairs the Xcode project’s invalid configuration-list references.

The distributed build is ad-hoc signed for local Apple-silicon use on macOS 13 or later. It is not notarized.
