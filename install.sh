#!/bin/bash
# GSB Radar — one-line installer.
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/lolmc111/gsb-radars/main/install.sh)"
# Gets the kit into ~/gsb-radar (git clone when git is available, otherwise a zip download), then runs
# setup.command, which does the actual setup with you in the Terminal and a progress page in your browser.
# Safe to run again: an existing ~/gsb-radar is updated in place and your me/ settings are kept.
set -u
REPO="lolmc111/gsb-radars"
TARGET="$HOME/gsb-radar"
BOLD=$'\033[1m'; NC=$'\033[0m'
echo "${BOLD}GSB Radar installer${NC}"
if [ "$(uname -s)" != "Darwin" ]; then echo "This runs on a Mac only."; exit 1; fi

if [ -d "$TARGET/.git" ] && command -v git >/dev/null 2>&1; then
  echo "  updating existing ~/gsb-radar (git pull)…"
  ( cd "$TARGET" && git pull --ff-only ) || { echo "  git pull failed; fix it in Terminal or delete ~/gsb-radar and run again."; exit 1; }
elif command -v git >/dev/null 2>&1 && xcode-select -p >/dev/null 2>&1; then
  if [ -d "$TARGET" ]; then
    echo "  ~/gsb-radar exists without git history — keeping your me/ and replacing the rest…"
    T=$(mktemp -d /tmp/gsb-install.XXXXXX)
    git clone --depth 1 -q "https://github.com/$REPO.git" "$T/kit" || { echo "  clone failed"; exit 1; }
    mkdir -p "$T/keep"; [ -d "$TARGET/me" ] && cp -R "$TARGET/me" "$T/keep/me"; [ -d "$TARGET/raw" ] && mv "$TARGET/raw" "$T/keep/raw"
    rm -rf "$TARGET"; mv "$T/kit" "$TARGET"
    [ -d "$T/keep/me" ] && cp -Rn "$T/keep/me/." "$TARGET/me/"; [ -d "$T/keep/raw" ] && mv "$T/keep/raw" "$TARGET/raw"
    rm -rf "$T"
  else
    echo "  downloading (git clone)…"
    git clone --depth 1 -q "https://github.com/$REPO.git" "$TARGET" || { echo "  clone failed — check your internet connection."; exit 1; }
  fi
else
  # No git yet (Xcode command line tools not installed). Download the zip; setup.command installs the tools
  # later for Homebrew, and update.command can switch to git afterwards.
  echo "  downloading (zip)…"
  T=$(mktemp -d /tmp/gsb-install.XXXXXX)
  curl -fsSL -o "$T/kit.zip" "https://github.com/$REPO/archive/refs/heads/main.zip" || { echo "  download failed — check your internet connection."; exit 1; }
  ( cd "$T" && unzip -q kit.zip ) || { echo "  unzip failed"; exit 1; }
  SRC=$(find "$T" -maxdepth 1 -type d -name 'gsb-radars-*' | head -n1)
  if [ -d "$TARGET" ]; then
    rm -rf "$TARGET/engine"; cp -R "$SRC/engine" "$TARGET/engine"
    for f in setup.command doctor.command update.command install.sh CLAUDE.md README.md KNOWN-ISSUES.md; do [ -f "$SRC/$f" ] && cp "$SRC/$f" "$TARGET/$f"; done
    mkdir -p "$TARGET/me"; for f in me.yaml.template groups.md.template prefs.md.template; do cp "$SRC/me/$f" "$TARGET/me/$f"; done
  else
    mv "$SRC" "$TARGET"
  fi
  rm -rf "$T"
fi
chmod +x "$TARGET"/*.command "$TARGET"/engine/*.sh "$TARGET"/engine/*.py "$TARGET/install.sh" 2>/dev/null
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
echo "  kit is at $TARGET — starting setup"
echo
exec /bin/bash "$TARGET/setup.command"
