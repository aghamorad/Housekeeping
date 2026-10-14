// Housekeeping — how the program starts
//
// Two lives are possible for this binary: a window, or an answer. Which one it
// is depends on whether anyone typed anything, and that decision has to be made
// before either of them begins — because a command that started AppKit would
// bounce an icon in the Dock and steal focus from whatever terminal asked the
// question, and a double-click that went looking for a verb would do nothing at
// all.
//
// So `HousekeepingApp` no longer carries `@main`. It is called from here,
// explicitly, only when nothing was typed. That one line is the whole of the
// arrangement: the window code is untouched, and the app still starts the same
// way it always did, from the same entry point, down to the same call.
//
// The command line needs the run loop to keep running, though — a scan is
// asynchronous and its first `await` would otherwise return to a program that had
// already fallen off the end of main and exited with nothing printed. So the
// command is started as a task and `dispatchMain()` takes over the thread, which
// is what keeps the main queue serviced while the work is in flight. Nothing in
// this branch is ever visible: no window, no Dock icon, no menu bar.

import AppKit

if HousekeepingCLI.wantsCommandLine(Array(CommandLine.arguments.dropFirst())) {
    Task {
        // `run` bounds its own failures and hands back a status rather than
        // throwing, so there is exactly one place an exit code is decided.
        let status = await HousekeepingCLI.run()
        exit(status)
    }
    // Never returns. The process ends from inside the task above.
    dispatchMain()
}

HousekeepingApp.main()
