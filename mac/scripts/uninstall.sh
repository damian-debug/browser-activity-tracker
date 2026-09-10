#!/bin/bash
# Removes Activity Tracker from this Mac.
#
#   curl -fsSL https://raw.githubusercontent.com/damian-debug/browser-activity-tracker/master/mac/scripts/uninstall.sh | bash
#
# Removes the app, its login item, its permission grants and its preferences.
# Your tracked history is kept unless you say otherwise — it asks first, and
# even then it goes to the Trash rather than being erased. Flags, to skip the
# question:
#
#   ... | bash -s -- --keep-data     keep tracked history (the default)
#   ... | bash -s -- --delete-data   move tracked history to the Trash too
#
# The order below matters, and each step was checked against real macOS
# behaviour rather than assumed:
#   1. The login item must be removed BY THE APP, before it is deleted.
#      Deleting the bundle leaves the item registered and still enabled.
#   2. Permission grants must be reset BEFORE the bundle is deleted.
#      tccutil finds the app through LaunchServices and fails once it is gone.
set -euo pipefail

BUNDLE_ID="studio.goodspeed.timetracker"
APP_NAME="Activity Tracker.app"
DATA_DIR="$HOME/Library/Application Support/TimeTracker"
PREFS_PLIST="$HOME/Library/Preferences/${BUNDLE_ID}.plist"

say()  { printf '\033[1m==>\033[0m %s\n' "$1"; }
note() { printf '    %s\n' "$1"; }
warn() { printf '\033[33mNOTE:\033[0m %s\n' "$1"; }

# Everything runs inside main(), called on the last line. Under `curl | bash`
# bash executes as it reads, so a connection dropped mid-download would
# otherwise run a truncated script. Wrapped, nothing runs until all of it
# has arrived and parsed.
main() {
DATA_CHOICE="ask"
for arg in "$@"; do
    case "$arg" in
        --delete-data) DATA_CHOICE="delete" ;;
        --keep-data)   DATA_CHOICE="keep" ;;
        *) printf 'Unknown option: %s\n' "$arg" >&2; exit 64 ;;
    esac
done

[ "$(uname -s)" = "Darwin" ] || { echo "macOS only." >&2; exit 1; }

# ── Find installed copies ────────────────────────────────────────────────
# Only the two places install.sh puts it, and only if the bundle really is
# ours: never rm -rf something merely because it has the same name.
APPS=()
for dir in /Applications "$HOME/Applications"; do
    candidate="$dir/$APP_NAME"
    [ -d "$candidate" ] || continue
    id=$(defaults read "$candidate/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || true)
    if [ "$id" = "$BUNDLE_ID" ]; then
        APPS+=("$candidate")
    else
        warn "Skipping $candidate — it is not Activity Tracker (bundle ID '${id:-unknown}')."
    fi
done

if [ ${#APPS[@]} -eq 0 ] && [ ! -d "$DATA_DIR" ] && [ ! -f "$PREFS_PLIST" ]; then
    echo "Activity Tracker is not installed on this Mac. Nothing to do."
    exit 0
fi

# ── 1. Quit ──────────────────────────────────────────────────────────────
if pgrep -x TimeTrackerApp >/dev/null 2>&1; then
    say "Quitting Activity Tracker"
    # SIGTERM runs the normal quit path, which saves the session in progress.
    pkill -x TimeTrackerApp || true
    for _ in $(seq 1 20); do
        pgrep -x TimeTrackerApp >/dev/null 2>&1 || break
        sleep 0.25
    done
    pgrep -x TimeTrackerApp >/dev/null 2>&1 && pkill -9 -x TimeTrackerApp || true
fi

# ── 2. Login item ────────────────────────────────────────────────────────
LOGIN_ITEM_UNKNOWN=false
for app in ${APPS[@]+"${APPS[@]}"}; do
    hook=$(defaults read "$app/Contents/Info.plist" ActivityTrackerUninstallHook 2>/dev/null || echo 0)
    if [ "$hook" = "1" ]; then
        say "Removing the login item"
        "$app/Contents/MacOS/TimeTrackerApp" --unregister-login-item \
            || warn "Could not remove the login item automatically."
    else
        # 1.0.0 predates the hook. Passing it the flag would just launch the
        # app, so the only safe option is to tell the person.
        LOGIN_ITEM_UNKNOWN=true
    fi
done

# ── 3. Permissions ───────────────────────────────────────────────────────
if [ ${#APPS[@]} -gt 0 ]; then
    say "Revoking Accessibility and Automation permissions"
    tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 \
        || warn "Could not reset permissions — remove Activity Tracker under System Settings > Privacy & Security > Accessibility."
fi

# ── 4. The app ───────────────────────────────────────────────────────────
for app in ${APPS[@]+"${APPS[@]}"}; do
    say "Removing $app"
    rm -rf "$app"
done

# ── 5. Preferences ───────────────────────────────────────────────────────
# `defaults delete` rather than just removing the file: cfprefsd caches
# preferences, and a bare rm lets the cached copy be written straight back.
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
rm -f "$PREFS_PLIST"

# ── 6. Tracked history ───────────────────────────────────────────────────
DATA_RESULT="none"
if [ -d "$DATA_DIR" ]; then
    DB="$DATA_DIR/tracker.sqlite"
    SUMMARY=""
    if [ -f "$DB" ] && command -v sqlite3 >/dev/null 2>&1; then
        SUMMARY=$(sqlite3 -readonly "$DB" \
            "select count(*) || ' tracked sessions since ' || date(min(startTime),'unixepoch','localtime') from session" \
            2>/dev/null || true)
    fi

    if [ "$DATA_CHOICE" = "ask" ]; then
        echo
        echo "Your tracked history is still on this Mac${SUMMARY:+ ($SUMMARY)}."
        echo "Keep it and a reinstall picks up exactly where you left off."
        # Read from the terminal, not stdin: under `curl | bash`, stdin is
        # this script. With no terminal at all, fall through to keeping it.
        printf 'Delete your tracked history too? [y/N] '
        answer=""
        { read -r answer < /dev/tty; } 2>/dev/null || echo
        case "$answer" in
            y|Y|yes|YES|Yes) DATA_CHOICE="delete" ;;
            *)               DATA_CHOICE="keep" ;;
        esac
    fi

    if [ "$DATA_CHOICE" = "delete" ]; then
        # To the Trash, not rm: this is the one irreversible thing here, and
        # a mis-typed "y" should still be recoverable.
        stamp=$(date '+%Y-%m-%d at %H.%M.%S')
        dest="$HOME/.Trash/Activity Tracker data ($stamp)"
        if mv "$DATA_DIR" "$dest" 2>/dev/null; then
            DATA_RESULT="trashed"
        else
            warn "Could not move your data to the Trash; it has been left in place:"
            note "$DATA_DIR"
            DATA_RESULT="kept"
        fi
    else
        DATA_RESULT="kept"
    fi
fi

# ── Done ─────────────────────────────────────────────────────────────────
echo
printf '\033[32mActivity Tracker has been removed.\033[0m\n'
case "$DATA_RESULT" in
    trashed)
        echo "Your tracked history is in the Trash — empty it to erase it for good,"
        echo "or drag it back to ~/Library/Application Support/TimeTracker to restore it."
        ;;
    kept)
        echo "Your tracked history was kept, in:"
        note "$DATA_DIR"
        echo "Reinstalling picks it up again. To erase it later, delete that folder."
        ;;
esac

if [ "$LOGIN_ITEM_UNKNOWN" = true ]; then
    echo
    warn "If you had turned on \"Open at login\", also switch Activity Tracker off"
    note "in System Settings > General > Login Items. This version could not do it for you."
fi
}

main "$@"
