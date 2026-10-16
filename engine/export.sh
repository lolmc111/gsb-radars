#!/bin/bash
# Read-only export of recent WhatsApp GROUP messages for the GSB Radar. Never sends anything, never reads DMs.
# Runs on this Mac via launchd (com.gsb-radar.export): when WhatsApp's database changes (WatchPaths) and hourly
# (StartInterval) as a safety net. Throttled to once per 30 minutes; `--force` overrides.
# After exporting it (1) writes ONE bundle file into Google Drive (publish-bundle.sh), which the cloud Radar task
# reads through the Google Drive connector, and (2) if the poke module is on, pokes that task so the page
# rebuilds within minutes (poke-digest.sh).
set -u
. "$(dirname "$0")/lib.sh"
OUT="$KIT"
DAY=$(date +%Y-%m-%d)
NOW_ISO=$(now_iso)
OKF="$RAW_ROOT/_last_ok"                        # start time of the last export that synced AND reached Google Drive
# Window: the last 26 hours, or back to 2 hours before the last delivered export if that is earlier (so an
# outage on either side leaves no gap), never more than 7 days. Overlap is deduped by event_id in the cloud.
AFTER=$(date -u -v-26H +%Y-%m-%dT%H:%M:%SZ)
if [ -f "$OKF" ]; then
  LAST=$(head -n1 "$OKF" | tr -d '[:space:]')
  BACK=$(date -u -j -v-2H -f %Y-%m-%dT%H:%M:%SZ "$LAST" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)
  FLOOR=$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ)
  if [ -n "$BACK" ] && [[ "$BACK" < "$AFTER" ]]; then AFTER="$BACK"; fi
  if [[ "$AFTER" < "$FLOOR" ]]; then AFTER="$FLOOR"; fi
fi
RAW="$RAW_ROOT/$DAY"
LOG="$RAW/_export.log"
STAMP="$RAW_ROOT/_last_export"                   # throttle marker (mtime = last export start)
DB="$HOME/.wacrawl/gsb-radar.db"                 # throwaway archive, rebuilt from WhatsApp on every run

if [ ! -x "$WACRAWL" ]; then
  mkdir -p "$RAW"; echo "start $NOW_ISO after=$AFTER" > "$LOG"; echo "SYNC FAILED wacrawl not installed at $WACRAWL (run setup.command)" >> "$LOG"
  notify "wacrawl is missing. Double-click setup.command to repair."; exit 1
fi

# Throttle: at most one export per 30 min unless --force.
if [ "${1:-}" != "--force" ] && [ -f "$STAMP" ] && [ -n "$(find "$STAMP" -mmin -30 2>/dev/null)" ]; then exit 0; fi
mkdir -p "$RAW"
echo "start $NOW_ISO after=$AFTER" > "$LOG"
touch "$STAMP"

# Fresh archive on every run. wacrawl refuses to merge into an existing archive once WhatsApp reuses a database
# row ("message source_pk N belongs to a different event") and then fails on every later sync. A throwaway
# archive has nothing to conflict with, and the Radar only needs the last ~26 hours. ~/.wacrawl/wacrawl.db
# (wacrawl's own default archive, if the user has one) is never touched.
mkdir -p "$(dirname "$DB")"
rm -f "$DB" "$DB-wal" "$DB-shm" "$DB-journal"
SYNC_OK=1
"$WACRAWL" --db "$DB" sync >> "$LOG" 2>&1 || SYNC_OK=0
if [ "$SYNC_OK" = 0 ]; then
  echo "SYNC FAILED" >> "$LOG"
  notify "WhatsApp export failed (wacrawl sync). The Radar will have no new WhatsApp messages. Run doctor.command."
fi
"$WACRAWL" --db "$DB" --sync never chats --limit 500 > "$OUT/chats.txt" 2>> "$LOG"

# Groups only (JIDs ending in @g.us). DMs are never exported.
grep -oE '[0-9]+@g\.us' "$OUT/chats.txt" | sort -u | while read -r jid; do
  f="$RAW/$jid.json"
  "$WACRAWL" --db "$DB" --sync never --json messages --chat "$jid" --after "$AFTER" --asc --limit 3000 > "$f" 2>> "$LOG"
  [ "$(wc -c < "$f")" -le 5 ] && rm -f "$f"
done
NG=$(ls "$RAW" | grep -c '@g.us.json')
echo "exported $NG group files" >> "$LOG"

# Resized copies of images/documents for local use (NOT put in the bundle).
mkdir -p "$RAW/media"
/usr/bin/python3 - "$RAW" <<'PY2' >> "$LOG" 2>&1
import json,glob,os,subprocess,sys,shutil
raw=sys.argv[1]
for f in glob.glob(raw+'/*@g.us.json'):
    try: msgs=json.load(open(f)) or []
    except Exception: continue
    for m in msgs:
        p=m.get('media_path'); t=m.get('message_type')
        if not p or not os.path.exists(p) or t not in ('image','document','sticker'): continue
        eid=m['event_id'].replace(':','_'); ext=os.path.splitext(p)[1].lower()
        if t=='image':
            out=f"{raw}/media/{eid}.jpg"
            if not os.path.exists(out):
                subprocess.run(['/usr/bin/sips','-Z','900','-s','format','jpeg','-s','formatOptions','70',p,'--out',out],capture_output=True)
        elif os.path.getsize(p) < 8_000_000:
            out=f"{raw}/media/{eid}{ext}"
            if not os.path.exists(out): shutil.copy2(p,out)
PY2

# Keep the raw/ folder from growing forever: drop date folders older than 14 days.
find "$RAW_ROOT" -maxdepth 1 -type d -name '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' -mtime +14 -exec rm -rf {} + 2>/dev/null

date -u +%FT%TZ > "$RAW/_done"
echo "done $(cat "$RAW/_done")" >> "$LOG"

# Bundle (tiers A/B/C/U only, last 2 days, text only) → Google Drive, then (optionally) poke the cloud task.
# No poke if the bundle did not reach Drive: the cloud task would only re-read the old one.
if /bin/bash "$ENGINE/publish-bundle.sh" "$LOG"; then
  [ "$SYNC_OK" = 1 ] && [ "$NG" -gt 0 ] && echo "$NOW_ISO" > "$OKF"
  if cfg_bool module_poke; then /bin/bash "$ENGINE/poke-digest.sh" "$LOG" || true; fi
fi
