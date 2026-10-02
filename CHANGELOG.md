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
