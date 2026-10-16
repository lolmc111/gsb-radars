#!/bin/bash
# Put a text-only copy of the latest WhatsApp export into Google Drive as ONE file. Google Drive for desktop
# uploads it; the cloud Radar task reads it through the Google Drive connector. No tokens or passwords anywhere:
# this Mac writes to its own Drive folder, the cloud reads with the user's own Google sign-in.
# Logs to $1. Exit 0 = bundle is in the Drive folder, 1 = it is not (export.sh then skips the poke).
#
# What goes into the bundle (and nothing else):
#   raw/<date>/<jid>.json   message JSON for tier A/B/C/U groups (per me/groups.md), last 2 days. No media files.
#   raw/<date>/_export.log  start / done / SYNC FAILED lines only
#   groups.md, radar/prefs.md, radar/build.py, radar/render.py, radar/template.html
#   me.yaml                 the user's settings (no secrets live there)
#   VERSION, PUSHED_AT      kit version · UTC time this bundle was made
# The file is overwritten in place, so Drive keeps one file (older versions live in its version history).
set -u
. "$(dirname "$0")/lib.sh"
LOG="${1:-/tmp/gsb-bundle.log}"
WORK="$HOME/.gsb-radar-bundle"            # scratch, outside Documents
ACCT="$(cfg drive_account)"               # must be the Google account the Claude Drive connector is signed in to
FOLDER="$(cfg drive_folder 'GSB Radar (auto)')"
NAME="$(cfg bundle_name 'gsb-radar-bundle.tar')"
say(){ echo "$(date -u +%FT%TZ) bundle: $*" >> "$LOG"; }
fail(){ say "BUNDLE FAILED $*"; notify "WhatsApp export done, but the bundle did not reach Google Drive. The Radar page will not update. Run doctor.command."; exit 1; }

[ -n "$ACCT" ] || fail "drive_account is empty in me/me.yaml (run setup.command)"
ROOT="$HOME/Library/CloudStorage/GoogleDrive-$ACCT"
DRIVE=""
# Drive for desktop can briefly refuse access right after wake/login; retry a few times.
for try in 1 2 3 4; do
  for d in "$ROOT/My Drive" "$ROOT/我的云端硬盘" "$ROOT"/*; do [ -d "$d" ] && [ "$(basename "$d")" != ".shortcut-targets-by-id" ] && [ "$(basename "$d")" != ".Encrypted" ] && { DRIVE="$d"; break; }; done
  [ -n "$DRIVE" ] && break
  sleep 20
done
if [ -z "$DRIVE" ]; then
  say "CloudStorage has: $(ls "$HOME/Library/CloudStorage" 2>&1 | tr '\n' '|')"
  fail "Google Drive folder for $ACCT not found (is Google Drive for desktop signed in to that account?)"
fi
DEST="$DRIVE/$FOLDER"
mkdir -p "$DEST" 2>> "$LOG" || fail "cannot create $DEST"

SRC="$WORK/src"
rm -rf "$WORK"; mkdir -p "$SRC/raw" "$SRC/radar"
cp "$KIT/me/groups.md" "$SRC/" 2>/dev/null
cp "$KIT/me/prefs.md" "$SRC/radar/" 2>/dev/null
cp "$KIT/me/me.yaml" "$SRC/" 2>/dev/null
cp "$ENGINE/VERSION" "$SRC/" 2>/dev/null
for f in build.py render.py template.html; do cp "$ENGINE/$f" "$SRC/radar/" 2>/dev/null; done

# Tier D / X jids are excluded (ignored groups, non-GSB groups). Everything else, including untiered U, goes in.
EXCL=$(awk '/^## D /,/^## [^D]/' "$KIT/me/groups.md" 2>/dev/null | grep -oE '[0-9]+@g\.us' | sort -u)
EXCL="$EXCL
$(awk '/^## X /,/^## [^X]/' "$KIT/me/groups.md" 2>/dev/null | grep -oE '[0-9]+@g\.us' | sort -u)"
N=0
for d in $(ls -1 "$RAW_ROOT" | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort | tail -n 2); do
  mkdir -p "$SRC/raw/$d"
  for f in "$RAW_ROOT/$d"/*@g.us.json; do
    [ -f "$f" ] || continue
    jid=$(basename "$f" .json)
    echo "$EXCL" | grep -qx "$jid" && continue
    cp "$f" "$SRC/raw/$d/"; N=$((N+1))
  done
  grep -E '^(start|done) |^SYNC FAILED' "$RAW_ROOT/$d/_export.log" > "$SRC/raw/$d/_export.log" 2>/dev/null
done
PUSHED=$(date -u +%FT%TZ)
echo "$PUSHED" > "$SRC/PUSHED_AT"

( cd "$SRC" && COPYFILE_DISABLE=1 /usr/bin/tar -cf "$WORK/$NAME" . ) 2>> "$LOG" || fail "tar failed"
# Never open the existing Drive file for writing: once Drive for desktop has evicted it to an online-only
# placeholder, cp over it fails with "Resource deadlock avoided" (EDEADLK). Write a NEW file next to it, then
# rename it over the old one. The cloud task finds the bundle by title (newest modifiedTime), so a new id is fine.
TMPN="$NAME.partial"
OKW=0
for try in 1 2 3; do
  rm -f "$DEST/$TMPN" 2>/dev/null
  if cp "$WORK/$NAME" "$DEST/$TMPN" 2>> "$LOG" && cmp -s "$WORK/$NAME" "$DEST/$TMPN"; then
    if mv -f "$DEST/$TMPN" "$DEST/$NAME" 2>> "$LOG"; then OKW=1; break; fi
    say "rename over old bundle failed (try $try); deleting old bundle and retrying"
    rm -f "$DEST/$NAME" 2>> "$LOG"
    mv -f "$DEST/$TMPN" "$DEST/$NAME" 2>> "$LOG" && { OKW=1; break; }
  fi
  say "write attempt $try failed; retrying in 20s"
  sleep 20
done
rm -f "$DEST/$TMPN" 2>/dev/null
[ "$OKW" = 1 ] || fail "cannot write $DEST/$NAME"
[ "$(wc -c < "$DEST/$NAME" 2>/dev/null | tr -d ' ')" = "$(wc -c < "$WORK/$NAME" | tr -d ' ')" ] || fail "bundle in Drive folder has the wrong size"
cp "$SRC/PUSHED_AT" "$WORK/PUSHED_AT"
say "BUNDLE OK $PUSHED · $N group files · $(wc -c < "$WORK/$NAME" | tr -d ' ') bytes → Google Drive/$FOLDER/$NAME"
exit 0
