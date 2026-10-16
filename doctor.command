#!/bin/bash
# GSB Radar — diagnostics. Double-click when the page looks stale or something feels off.
# Read-only except for one optional test export at the end. Every FAIL comes with the fix.
set -u
BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; NC=$'\033[0m'
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/engine/lib.sh"
PASS=0; FAILN=0
pass(){ echo "  ${GRN}PASS${NC}  $*"; PASS=$((PASS+1)); }
fail(){ echo "  ${RED}FAIL${NC}  $1"; echo "        ${DIM}fix:${NC} $2"; FAILN=$((FAILN+1)); }
warn(){ echo "  ${YEL}WARN${NC}  $1"; [ -n "${2:-}" ] && echo "        ${DIM}note:${NC} $2"; }
hdr(){ echo; echo "${BOLD}$*${NC}"; }
age_h(){ local t="$1"; local s; s=$(date -u -j -f %Y-%m-%dT%H:%M:%SZ "$t" +%s 2>/dev/null) || { echo 9999; return; }; echo $(( ($(date +%s) - s) / 3600 )); }

echo "${BOLD}GSB Radar doctor${NC} · kit $(cat "$ENGINE/VERSION" 2>/dev/null || echo '?') · $(date)"

hdr "Location"
[ "$KIT" = "$HOME/gsb-radar" ] && pass "kit at ~/gsb-radar" || fail "kit is at $KIT, not ~/gsb-radar" "double-click setup.command; it moves the kit (background jobs cannot read ~/Documents)."
[ -f "$ME" ] && pass "me/me.yaml exists" || fail "me/me.yaml missing" "run setup.command"
[ -f "$KIT/me/groups.md" ] && pass "me/groups.md exists" || fail "me/groups.md missing" "run setup.command"
[ -f "$KIT/me/prefs.md" ] && pass "me/prefs.md exists" || fail "me/prefs.md missing" "run setup.command"

hdr "WhatsApp + wacrawl"
WADB="$HOME/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite"
[ -f "$WADB" ] && pass "WhatsApp Desktop database present" || fail "WhatsApp Desktop database not found" "install WhatsApp Desktop from the App Store and sign in; keep it installed (it can stay closed)."
if [ -x "$WACRAWL" ]; then pass "wacrawl copy at $WACRAWL ($("$WACRAWL" --version 2>/dev/null | head -n1))"; else fail "wacrawl copy missing at $WACRAWL" "run setup.command"; fi
if [ -x "$WACRAWL" ]; then
  rm -f /tmp/gsb-doc-test.db*; if "$WACRAWL" --db /tmp/gsb-doc-test.db sync >/tmp/gsb-doc-test.log 2>&1; then pass "wacrawl can read WhatsApp (Full Disk Access OK)"; else fail "wacrawl cannot read WhatsApp's database" "System Settings → Privacy & Security → Full Disk Access → add $WACRAWL and switch it ON. Log: /tmp/gsb-doc-test.log"; fi; rm -f /tmp/gsb-doc-test.db*
fi

hdr "Google Drive for desktop"
ACCT="$(cfg drive_account)"
if [ -z "$ACCT" ]; then fail "drive_account empty in me/me.yaml" "run setup.command"; else
  ROOT="$HOME/Library/CloudStorage/GoogleDrive-$ACCT"
  if [ -d "$ROOT" ]; then pass "Drive for desktop signed in as $ACCT"; else fail "Drive for desktop is not signed in as $ACCT" "sign in to Google Drive for desktop with $ACCT (it can coexist with other accounts), or change drive_account in me/me.yaml. Found: $(ls "$HOME/Library/CloudStorage" 2>/dev/null | tr '\n' ' ')"; fi
  DEST=""; for d in "$ROOT/My Drive" "$ROOT/我的云端硬盘"; do [ -d "$d/$(cfg drive_folder 'GSB Radar (auto)')" ] && DEST="$d/$(cfg drive_folder 'GSB Radar (auto)')"; done
  if [ -n "$DEST" ]; then
    B="$DEST/$(cfg bundle_name gsb-radar-bundle.tar)"
    if [ -f "$B" ]; then
      SZ=$(wc -c < "$B" | tr -d ' '); M=$(stat -f %m "$B"); H=$(( ($(date +%s) - M) / 3600 ))
      [ "$SZ" -gt 2000 ] && pass "bundle in Drive folder: $SZ bytes, written ${H}h ago" || fail "bundle in Drive is tiny ($SZ bytes)" "the export produced no groups; check the WhatsApp section above and me/groups.md (are all groups in D/X?)."
      [ "$H" -gt 26 ] && warn "bundle is older than 26 hours" "the export job is not running — see the launchd section."
      if ! xattr -p com.apple.FinderInfo "$B" >/dev/null 2>&1 && [ "$(stat -f %b "$B")" = 0 ]; then warn "bundle is an online-only placeholder" "In Finder, right-click the '$(cfg drive_folder)' folder → Make available offline. Otherwise Drive may evict it and the next write can fail."; fi
    else fail "no bundle in $DEST" "run: bash ~/gsb-radar/engine/export.sh --force  and read raw/<today>/_export.log"; fi
  else warn "Drive folder '$(cfg drive_folder 'GSB Radar (auto)')' not created yet" "the first successful export creates it."; fi
fi

hdr "Background job (launchd)"
U=$(id -u)
if launchctl print "gui/$U/$LABEL" >/dev/null 2>&1; then pass "$LABEL is loaded"; else fail "$LABEL is not loaded" "run setup.command (it reinstalls the job), or: launchctl bootstrap gui/$U ~/Library/LaunchAgents/$LABEL.plist"; fi
LASTDIR=$(ls -1d "$RAW_ROOT"/20*/ 2>/dev/null | sort | tail -n1)
if [ -n "$LASTDIR" ]; then
  LOG="$LASTDIR/_export.log"; ST=$(grep -m1 '^start ' "$LOG" 2>/dev/null | awk '{print $2}')
  if [ -n "$ST" ]; then H=$(age_h "$ST"); [ "$H" -le 26 ] && pass "last export started ${H}h ago ($(basename "$LASTDIR"))" || fail "last export was ${H}h ago" "WhatsApp Desktop may not have new messages, the Mac may have been asleep, or the job is broken. Run the test export at the end."; fi
  grep -q 'SYNC FAILED' "$LOG" 2>/dev/null && fail "last export: WhatsApp sync failed" "see $LOG; usually Full Disk Access (above) or WhatsApp Desktop not signed in."
  grep -q 'BUNDLE OK' "$LOG" 2>/dev/null && pass "last export: bundle reached Google Drive" || { grep -q 'BUNDLE FAILED' "$LOG" 2>/dev/null && fail "last export: bundle did not reach Google Drive" "$(grep 'BUNDLE FAILED' "$LOG" | tail -n1)"; }
  if cfg_bool module_poke; then grep -q 'POKE OK' "$LOG" 2>/dev/null && pass "last export: cloud task poked" || { grep 'POKE FAILED' "$LOG" >/dev/null 2>&1 && fail "poke failed: $(grep 'POKE FAILED' "$LOG" | tail -n1 | cut -c1-120)" "run 'claude' in Terminal and sign in; or set module_poke: false in me/me.yaml (the cloud task still runs on schedule)."; }; fi
  N=$(ls "$LASTDIR"/*.json 2>/dev/null | wc -l | tr -d ' '); [ "$N" -gt 0 ] && pass "$N group files in the last export" || fail "0 group files in the last export" "WhatsApp Desktop has no groups synced, or the sync failed (see above)."
else fail "no export has ever run (raw/ is empty)" "run setup.command, or: bash ~/gsb-radar/engine/export.sh --force"; fi

hdr "Cloud side (what this Mac can tell)"
[ -n "$(cfg name)" ] && pass "me.yaml: name set ($(cfg name))" || warn "me.yaml: name not set" "open this folder in Claude and say 'set me up'."
[ -f "$KIT/me/task-prompt.md" ] && pass "me/task-prompt.md exists (paste it into the scheduled task after changes)" || warn "me/task-prompt.md not generated yet" "the onboarding chat runs: python3 engine/make-task-prompt.py"
for m in email canvas poke; do cfg_bool module_$m && echo "        module $m: on" || echo "        module $m: off"; done
cfg_bool module_email && [ -z "$(cfg school_email)" ] && fail "module_email is on but school_email is empty" "set school_email in me/me.yaml and regenerate the task prompt."
cfg_bool module_canvas && [ -z "$(cfg canvas_calendar_id)" ] && fail "module_canvas is on but canvas_calendar_id is empty" "ask Claude to look it up (Google Calendar list_calendars) and regenerate the task prompt."
if cfg_bool module_poke; then
  C=""; for c in $(ls -1dt "$HOME"/.nvm/versions/node/*/bin/claude 2>/dev/null) "$(command -v claude 2>/dev/null)" "$HOME/.claude/local/claude" "$HOME/.local/bin/claude" /opt/homebrew/bin/claude /usr/local/bin/claude; do [ -n "${c:-}" ] && [ -x "$c" ] && C="$c" && break; done
  [ -n "$C" ] && pass "claude CLI found ($C)" || fail "module_poke is on but the claude CLI is not installed" "install Claude Code, or set module_poke: false."
  [ -n "$(cfg trigger_id)" ] && pass "trigger_id set" || fail "module_poke is on but trigger_id is empty" "paste the scheduled task's id (trig_…) into me/me.yaml."
fi
echo "        ${DIM}Whether the cloud task itself ran: check the task's history in the Claude app, or the 'Updated' time on your page.${NC}"

echo
echo "${BOLD}$PASS passed · $FAILN failed${NC}"
echo
read -r -p "Run a test export now (takes ~1 minute, writes to Google Drive)? [y/N] " yn
case "$yn" in [Yy]*) /bin/bash "$ENGINE/export.sh" --force; D=$(date +%Y-%m-%d); echo; tail -8 "$RAW_ROOT/$D/_export.log" 2>/dev/null;; esac
echo; read -n1 -r -p "Press any key to close."
