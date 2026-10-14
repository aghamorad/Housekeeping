#!/usr/bin/env bash
set -euo pipefail

# Housekeeping — putting `housekeeping` on the PATH
#
# The command line lives *inside* the app. There is no second binary to build and
# nothing to keep in step: `Housekeeping.app/Contents/MacOS/Housekeeping` is the
# same program as the window, and it answers a question instead of opening a window
# when it is given one. That is deliberate — a scripted answer has to come from the
# same rules, the same classifier and the same safety policy as the screen, and the
# only way to be sure of that is for it to be the same file.
#
# So what gets installed here is a shim, not a copy. A copy would be a second
# program to keep current, and it would go stale the first time the app was
# updated — silently answering from rules that had been replaced. The shim looks
# for the app each time it runs, and when several copies are around it takes the
# most recently built one, so a fresh install or a fresh debug build is used the
# moment it exists.
#
# Re-running this script is safe and does nothing new. Removing the command is
# `rm ~/.local/bin/housekeeping`, which is also the whole of the uninstall.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${HOUSEKEEPING_BIN_DIR:-$HOME/.local/bin}"
SHIM="$BIN_DIR/housekeeping"

# Every copy of the app that exists is considered and the newest wins, because
# there is no registry to ask on macOS and a stale app in /Applications is the one
# failure that looks like Housekeeping giving wrong answers rather than like a
# missing command.

mkdir -p "$BIN_DIR"

# Quoted, so nothing in this script is expanded as the shim is written. The shim
# carries its own search list rather than reading this one, because this script
# will not be here next year but the command still has to work.
cat > "$SHIM" <<'SHIM'
#!/usr/bin/env bash
# Housekeeping, from the command line.
#
# Written by script/install_cli.sh. It holds no behaviour of its own: it finds the
# app and hands over. All of the answering happens in there, beside the window.

set -euo pipefail

# Named on purpose first, for the times a particular copy has to be spoken for —
# testing a build that is not installed, or running one that has been unpacked
# somewhere unusual.
if [[ -n "${HOUSEKEEPING_APP:-}" ]]; then
  candidate="$HOUSEKEEPING_APP"
  [[ -x "$candidate/Contents/MacOS/Housekeeping" ]] || {
    echo "housekeeping: there is no app at $candidate" >&2
    exit 1
  }
  exec "$candidate/Contents/MacOS/Housekeeping" "$@"
fi

BEST=""
BEST_TIME=-1
for candidate in \
  "/Applications/Housekeeping.app" \
  "$HOME/Applications/Housekeeping.app" \
  "$HOME/Downloads/Housekeeping.app" \
  "@REPO_ROOT@/dist/Housekeeping.app" \
  "@REPO_ROOT@/.build/DerivedData/Build/Products/Debug/Housekeeping.app"
do
  binary="$candidate/Contents/MacOS/Housekeeping"
  [[ -x "$binary" ]] || continue
  stamp="$(stat -f %m "$binary" 2>/dev/null || echo 0)"
  if (( stamp > BEST_TIME )); then
    BEST_TIME=$stamp
    BEST=$binary
  fi
done

if [[ -z "$BEST" ]]; then
  cat >&2 <<'MISSING'
housekeeping: Housekeeping is not installed, and there is no build to use here.

  Install the app, or run this from a checkout that has been built:
    script/build_and_run.sh
MISSING
  exit 1
fi

exec "$BEST" "$@"
SHIM

# The checkout this came from, so the shim can reach a debug build without being
# run from the repository root. Substituted after the fact because the heredoc
# above is quoted — everything in it has to survive to the shim exactly as typed,
# and the one exception is this path, which is only known here.
if [[ "$ROOT_DIR" != *"|"* ]]; then
  sed -i '' "s|@REPO_ROOT@|$ROOT_DIR|g" "$SHIM"
fi

chmod +x "$SHIM"

echo "Installed $SHIM"
echo

# Said out loud, because the one way this silently does nothing is a PATH that does
# not include the folder — the command exists and the shell still says "not found".
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo "Note: $BIN_DIR is not on your PATH. Add it, then open a new terminal:"
    echo
    echo "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc"
    echo
    ;;
esac

# Then actually run it, because a command that is installed and a command that
# works are different claims, and the second is the one that matters.
if "$SHIM" version >/dev/null 2>&1; then
  echo "Check it with:"
  echo
  echo "  housekeeping version"
  echo "  housekeeping help"
  echo
else
  echo "The command is in place, but running it did not work — try it directly:"
  echo
  echo "  $SHIM version"
  echo
fi
