#!/bin/bash
# GSB Radar — update the engine without touching your settings.
# Replaces engine/, the .command files, CLAUDE.md, README.md, KNOWN-ISSUES.md and the me/*.template files.
# Never touches me/me.yaml, me/groups.md, me/prefs.md, raw/ or chats.txt.
#
# Where updates come from, in order of preference:
#   1. This folder is a git clone  → git pull
#   2. Otherwise                   → download the latest zip from github.com/lolmc111/gsb-radars (or me.yaml update_url)
set -u
BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; NC=$'\033[0m'
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/engine/lib.sh"
CUR=$(cat "$ENGINE/VERSION" 2>/dev/null || echo 0)
die(){ echo; echo "  ${RED}✗ $*${NC}"; echo; read -n1 -r -p "Press any key to close."; exit 1; }
echo "${BOLD}GSB Radar update${NC} · installed engine $CUR"

apply_from(){ # $1 = unpacked kit dir
  local SRC="$1"
  [ -f "$SRC/engine/VERSION" ] || die "that download does not look like a GSB Radar kit (no engine/VERSION)."
  local NEW; NEW=$(cat "$SRC/engine/VERSION")
  echo "  new engine: $NEW"
  cp -R "$KIT/engine" "$KIT/.engine-backup-$CUR" 2>/dev/null
  rm -rf "$KIT/engine"; cp -R "$SRC/engine" "$KIT/engine"
  for f in setup.command doctor.command update.command install.sh CLAUDE.md README.md KNOWN-ISSUES.md; do [ -f "$SRC/$f" ] && cp "$SRC/$f" "$KIT/$f"; done
  mkdir -p "$KIT/me"; for f in me.yaml.template groups.md.template prefs.md.template; do [ -f "$SRC/me/$f" ] && cp "$SRC/me/$f" "$KIT/me/$f"; done
  chmod +x "$KIT"/*.command "$KIT"/engine/*.sh 2>/dev/null; xattr -dr com.apple.quarantine "$KIT" 2>/dev/null
  # me.yaml: add keys the new template knows and the user's file lacks (never changes existing values)
  /usr/bin/python3 - "$KIT/me/me.yaml.template" "$ME" <<'PY'
import re,sys
t,me=sys.argv[1:3]
have=set(re.findall(r'^\s*([A-Za-z_]+)\s*:',open(me).read(),re.M))
add=[l for l in open(t).read().split('\n') if re.match(r'^\s*([A-Za-z_]+)\s*:',l) and re.match(r'^\s*([A-Za-z_]+)\s*:',l).group(1) not in have]
if add:
    open(me,'a').write('\n# added by update '+'\n'.join(['']+add)+'\n'); print('  me.yaml: added new keys:',', '.join(re.match(r'^\s*([A-Za-z_]+)',l).group(1) for l in add))
PY
  echo "  ${GRN}✓${NC} engine $CUR → $NEW. Your me/ files were not changed."
  rm -rf "$KIT/.engine-backup-$CUR"
  # ship the new template to the cloud on the next run
  echo "  Running an export so the cloud task gets the new page template…"; /bin/bash "$ENGINE/export.sh" --force >/dev/null 2>&1 && echo "  ${GRN}✓${NC} exported" || echo "  ${YEL}!${NC} export did not finish — run doctor.command"
  if [ -f "$KIT/me/task-prompt.md" ]; then
    /usr/bin/python3 "$ENGINE/make-task-prompt.py" >/dev/null 2>&1 && echo "  ${YEL}!${NC} me/task-prompt.md regenerated. If the release notes say the cloud prompt changed, paste it into your scheduled task (ask Claude: 'update my radar task prompt')."
  fi
}

if [ -d "$KIT/.git" ] && command -v git >/dev/null; then
  echo "  git clone detected → git pull"
  ( cd "$KIT" && git pull --ff-only ) || die "git pull failed; resolve it in Terminal."
  NEW=$(cat "$ENGINE/VERSION"); chmod +x "$KIT"/*.command "$KIT"/engine/*.sh 2>/dev/null
  echo "  ${GRN}✓${NC} engine $CUR → $NEW"; /bin/bash "$ENGINE/export.sh" --force >/dev/null 2>&1
else
  URL="$(cfg update_url "https://github.com/lolmc111/gsb-radars/archive/refs/heads/main.zip")"; echo "  downloading $URL"
  T=$(mktemp -d /tmp/gsb-update.XXXXXX)
  curl -fsSL -o "$T/kit.zip" "$URL" || die "download failed."
  ( cd "$T" && unzip -q kit.zip ) || die "unzip failed."
  SRC=$(find "$T" -maxdepth 3 -name VERSION -path '*/engine/*' | head -n1); [ -n "$SRC" ] || die "no engine/VERSION in the download."
  apply_from "$(dirname "$(dirname "$SRC")")"; rm -rf "$T"
fi
echo; read -n1 -r -p "Press any key to close."
