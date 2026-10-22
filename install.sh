#!/usr/bin/env bash
# Installs the latest Sound Control release without the Gatekeeper prompt.
#
#   curl -fsSL https://raw.githubusercontent.com/chairat25/sound-noi/main/install.sh | bash
#
# Files fetched with curl carry no quarantine flag, so macOS opens the app directly.
# The download is checked against the release's SHA-256 file before anything is installed.
#
# Optional environment:
#   SOUND_CONTROL_VERSION  install this version (e.g. 1.2.0) instead of the latest
#   SOUND_CONTROL_DIR      install into this folder instead of /Applications
#   SOUND_CONTROL_NO_OPEN  set to 1 to skip launching the app afterwards
set -euo pipefail

REPO="chairat25/sound-noi"
APP_NAME="Sound Control"
MIN_MACOS=15
WORK_DIR=""

say() { printf '\033[1;35m→\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31m✗\033[0m %s\n' "$1" >&2; exit 1; }

check_system() {
    [[ "$(uname -s)" == "Darwin" ]] || fail "Sound Control runs on macOS only."
    local major
    major="$(sw_vers -productVersion | cut -d. -f1)"
    (( major >= MIN_MACOS )) || fail "Sound Control needs macOS $MIN_MACOS or later (this Mac has $(sw_vers -productVersion))."
}

latest_version() {
    curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' \
        | head -n 1
}

install_dir() {
    if [[ -n "${SOUND_CONTROL_DIR:-}" ]]; then
        echo "$SOUND_CONTROL_DIR"
    elif [[ -w /Applications ]]; then
        echo /Applications
    else
        echo "$HOME/Applications"
    fi
}

download_and_verify() {
    local version="$1" work="$2"
    local base="https://github.com/$REPO/releases/download/v$version"
    local zip="SoundControl-$version.zip"
    say "Downloading Sound Control $version"
    curl -fL --progress-bar -o "$work/$zip" "$base/$zip" || fail "Download failed: $base/$zip"
    curl -fsSL -o "$work/checksums" "$base/SoundControl-$version.sha256" || fail "Could not fetch the checksum file."
    say "Verifying checksum"
    (cd "$work" && grep "  $zip\$" checksums | shasum -a 256 -c - >/dev/null) \
        || fail "Checksum mismatch. The download may be corrupt; nothing was installed."
    ditto -x -k "$work/$zip" "$work/unpacked"
    [[ -d "$work/unpacked/$APP_NAME.app" ]] || fail "The archive does not contain $APP_NAME.app."
    codesign --verify --deep --strict "$work/unpacked/$APP_NAME.app" 2>/dev/null \
        || fail "The app's code signature is invalid; nothing was installed."
}

quit_running_copy() {
    local binary="$1/Contents/MacOS/SoundControl"
    pgrep -f "^$binary" >/dev/null || return 0
    say "Quitting the running copy"
    # SIGTERM goes through the app's normal quit, which restores macOS sounds and saves settings.
    pkill -TERM -f "^$binary" || true
    for _ in {1..20}; do
        pgrep -f "^$binary" >/dev/null || return 0
        sleep 0.25
    done
    fail "Sound Control did not quit. Quit it from the menu bar and run the installer again."
}

main() {
    check_system
    local version="${SOUND_CONTROL_VERSION:-$(latest_version)}"
    [[ -n "$version" ]] || fail "Could not find the latest release of $REPO."

    WORK_DIR="$(mktemp -d)"
    trap 'rm -rf "$WORK_DIR"' EXIT
    download_and_verify "$version" "$WORK_DIR"

    local dir app
    dir="$(install_dir)"
    app="$dir/$APP_NAME.app"
    mkdir -p "$dir"
    quit_running_copy "$app"
    say "Installing to $app"
    rm -rf "$app"
    ditto "$WORK_DIR/unpacked/$APP_NAME.app" "$app"
    xattr -dr com.apple.quarantine "$app" 2>/dev/null || true

    if [[ "${SOUND_CONTROL_NO_OPEN:-0}" != "1" ]]; then
        open "$app"
    fi
    printf '\033[1;32m✓\033[0m Sound Control %s installed. Look for the waveform icon in the menu bar.\n' "$version"
}

# Wrapped in main so a partially downloaded script never runs.
main "$@"
