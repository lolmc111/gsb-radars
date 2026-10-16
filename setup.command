#!/bin/bash
# GSB Radar — one-time setup. Double-click me in Finder. Safe to run again any time (it repairs what's missing).
#
# What it does, in order:
#   1. Moves this folder to ~/gsb-radar if it isn't there yet (background jobs can't read ~/Documents or ~/Downloads).
#   2. Checks macOS 13+, WhatsApp Desktop with a local message database, Google Drive for desktop.
#   3. Installs Homebrew (if missing) and wacrawl (the open-source WhatsApp → SQLite exporter), copies wacrawl
#      to ~/wacrawl-scheduled/ and walks you through giving THAT copy Full Disk Access.
#   4. Writes me/me.yaml (machine facts), me/groups.md, me/prefs.md from the templates.
#   5. Installs the background export job (launchd) and runs the first export now.
#   6. Lists every WhatsApp group it found under "U — Untiered" in me/groups.md.
# It never sends anything on WhatsApp, never reads direct messages, and stores no passwords.
set -u
BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; NC=$'\033[0m'
say(){ echo; echo "${BOLD}== $* ==${NC}"; }
ok(){ echo "  ${GRN}✓${NC} $*"; }
warn(){ echo "  ${YEL}!${NC} $*"; }
CUR=""
die(){ echo; echo "  ${RED}✗ $*${NC}"; echo; [ -n "$CUR" ] && st "$CUR" fail "$*"; read -n1 -r -p "Press any key to close." ; exit 1; }
pause(){ echo; read -r -p "  ${DIM}Press Return when done…${NC} "; }

HERE="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/gsb-radar"

# ---- 1. location ----------------------------------------------------------------------------------------------
if [ "$HERE" != "$TARGET" ]; then
  say "Moving the kit to ~/gsb-radar"
  echo "  Background jobs on macOS cannot read ~/Documents, ~/Desktop or ~/Downloads without extra permissions,"
  echo "  so the kit lives at ~/gsb-radar. Copying it there now."
  if [ -d "$TARGET" ]; then
    if [ -f "$TARGET/me/me.yaml" ]; then
      warn "~/gsb-radar already exists with your settings. Updating engine/ and the .command files only (me/ untouched)."
      rm -rf "$TARGET/engine"; cp -R "$HERE/engine" "$TARGET/engine"
      for f in setup.command doctor.command update.command CLAUDE.md README.md KNOWN-ISSUES.md; do [ -f "$HERE/$f" ] && cp "$HERE/$f" "$TARGET/$f"; done
      for f in me.yaml.template groups.md.template prefs.md.template; do [ -f "$HERE/me/$f" ] && cp "$HERE/me/$f" "$TARGET/me/$f"; done
    else
      rm -rf "$TARGET"; cp -R "$HERE" "$TARGET"
    fi
  else
    cp -R "$HERE" "$TARGET"
  fi
  xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
  ok "Kit is at $TARGET. Continuing from there (you can delete the original folder afterwards)."
  exec /bin/bash "$TARGET/setup.command"
fi
KIT="$TARGET"
xattr -dr com.apple.quarantine "$KIT" 2>/dev/null
chmod +x "$KIT"/*.command "$KIT"/engine/*.sh 2>/dev/null
. "$KIT/engine/lib.sh"

# ---- progress page (optional, cosmetic): a local page that mirrors these steps with pictures ----------------------
# The Terminal stays the place where you answer questions; the page just shows where you are and what each dialog
# looks like. It is served from ~/.gsb-radar-setup on 127.0.0.1 only and stops when setup ends.
UI="$HOME/.gsb-radar-setup"; mkdir -p "$UI"; STATUS="$UI/status.json"; UIPID=""
st(){ # st <step> <state: running|done|fail|wait> [message]
  /usr/bin/python3 - "$STATUS" "$1" "$2" "${3:-}" <<'PY' 2>/dev/null
import json,sys,time,os
p,step,state,msg=sys.argv[1:5]
d={'steps':{},'updated':0}
if os.path.exists(p):
    try: d=json.load(open(p))
    except Exception: pass
d['steps'][step]={'state':state,'msg':msg,'t':time.time()}; d['updated']=time.time(); d['current']=step
json.dump(d,open(p,'w'))
PY
}
ui_start(){
  [ -f "$KIT/engine/setup-ui.html" ] || return 0
  cp "$KIT/engine/setup-ui.html" "$UI/index.html"; printf '{"steps":{},"updated":0,"user":"%s"}' "$(id -un)" > "$STATUS"
  PORT=47821
  ( cd "$UI" && exec /usr/bin/python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 ) & UIPID=$!
  sleep 1; open "http://127.0.0.1:$PORT/" 2>/dev/null
  echo "  ${DIM}A progress page opened in your browser; keep answering questions here in the Terminal.${NC}"
}
ui_stop(){ [ -n "$UIPID" ] && kill "$UIPID" 2>/dev/null; }
trap ui_stop EXIT

# ---- 2. prerequisites -----------------------------------------------------------------------------------------
ui_start
CUR=mac; st mac running
say "Checking this Mac"
MAJ=$(sw_vers -productVersion | cut -d. -f1)
[ "$MAJ" -ge 13 ] 2>/dev/null && ok "macOS $(sw_vers -productVersion)" || die "macOS 13 or newer is required (you have $(sw_vers -productVersion))."
WADB="$HOME/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite"
if [ -f "$WADB" ]; then ok "WhatsApp Desktop database found"; else
  warn "WhatsApp Desktop's message database was not found."
  echo "  Install WhatsApp from the Mac App Store, sign in (scan the QR code with your phone), let it finish syncing,"
  echo "  then run this setup again. (The web version in a browser does not count — it keeps no local database.)"
  open "https://apps.apple.com/app/whatsapp-messenger/id310633997" 2>/dev/null
  die "WhatsApp Desktop is required."
fi
if ! xcode-select -p >/dev/null 2>&1; then
  warn "Apple's command line tools are missing; macOS will offer to install them (needed by Homebrew)."; xcode-select --install 2>/dev/null; echo "  Finish that install, then run setup again."; die "Command line tools required."
fi

# ---- 3. Homebrew + wacrawl ------------------------------------------------------------------------------------
st mac done "macOS $(sw_vers -productVersion) · WhatsApp Desktop found"
CUR=wacrawl; st wacrawl running
say "Installing wacrawl (WhatsApp → local SQLite exporter, open source: github.com/openclaw/wacrawl)"
BREW=""; for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && BREW="$b" && break; done
if [ -z "$BREW" ]; then
  warn "Homebrew (the Mac package manager) is not installed."
  st wacrawl wait "Homebrew is not installed — answer in the Terminal (it will ask for your Mac password)"
  read -r -p "  Install Homebrew now? It will ask for your Mac password. [Y/n] " yn
  st wacrawl running "Installing Homebrew…"
  case "${yn:-Y}" in [Yy]*) /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || die "Homebrew install failed. Install it from https://brew.sh and run setup again.";; *) die "Homebrew is required.";; esac
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && BREW="$b" && break; done
  [ -n "$BREW" ] || die "Homebrew installed but not found. Open a new Terminal and run setup again."
fi
eval "$("$BREW" shellenv)"
if ! "$BREW" list openclaw/tap/wacrawl >/dev/null 2>&1 && ! command -v wacrawl >/dev/null 2>&1; then
  "$BREW" install openclaw/tap/wacrawl || die "brew install openclaw/tap/wacrawl failed. Check your internet connection and run setup again."
fi
SRCBIN="$("$BREW" --prefix)/bin/wacrawl"; [ -x "$SRCBIN" ] || SRCBIN="$(command -v wacrawl)"
[ -x "$SRCBIN" ] || die "wacrawl binary not found after install."
ok "wacrawl $("$SRCBIN" --version 2>/dev/null | head -n1)"
# A copy at a fixed path: macOS ties Full Disk Access to the binary's path, and Homebrew's path changes on upgrade.
mkdir -p "$HOME/wacrawl-scheduled"
if [ ! -x "$WACRAWL" ] || ! cmp -s "$SRCBIN" "$WACRAWL"; then cp -p "$SRCBIN" "$WACRAWL"; ok "Copied to $WACRAWL"; fi
codesign -dv "$WACRAWL" 2>&1 | grep -q 'Identifier=org.openclaw.wacrawl' && ok "Signature verified (org.openclaw.wacrawl)" || warn "Could not verify wacrawl's code signature; continuing."

# Full Disk Access: needed so the BACKGROUND job can read WhatsApp's database. A test from this Terminal window
# would prove nothing (macOS would attribute it to Terminal), so the real check is the launchd-run export below.
st wacrawl done "wacrawl $("$SRCBIN" --version 2>/dev/null | head -n1 | cut -c1-40) · copy at ~/wacrawl-scheduled/wacrawl"
CUR=fda; st fda wait "Grant Full Disk Access in System Settings, then press Return in the Terminal"
say "Full Disk Access for the wacrawl copy"
echo "  macOS must allow ${BOLD}~/wacrawl-scheduled/wacrawl${NC} to read WhatsApp's data when it runs in the background."
echo "  System Settings opens now. In ${BOLD}Privacy & Security → Full Disk Access${NC}: click ${BOLD}+${NC}, press ${BOLD}⌘⇧G${NC}, paste this path,"
echo "  click Open, and make sure the switch next to ${BOLD}wacrawl${NC} is ON:"
echo
echo "      $WACRAWL"
echo
printf '%s' "$WACRAWL" | pbcopy && echo "  (The path is already on your clipboard — just paste it.)"
echo "  Already done on this Mac? Just press Return."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
pause
st fda done "Granted (verified by the first background export below)"

# ---- Google Drive for desktop ---------------------------------------------------------------------------------
CUR=drive; st drive running
say "Google Drive for desktop"
ACCTS=$(ls "$HOME/Library/CloudStorage" 2>/dev/null | grep -E '^GoogleDrive-' | sed 's/^GoogleDrive-//')
if [ -z "$ACCTS" ]; then
  warn "Google Drive for desktop is not signed in. The Radar moves data from this Mac to the cloud through your own Drive — no servers, no tokens."
  echo "  Install it from https://www.google.com/drive/download/ and sign in with the Google account you use with Claude"
  echo "  (the one whose Google Drive connector you will authorize in Claude). Then run setup again."
  open "https://www.google.com/drive/download/" 2>/dev/null
  die "Google Drive for desktop is required."
fi
N=$(echo "$ACCTS" | wc -l | tr -d ' ')
if [ "$N" = 1 ]; then ACCT="$ACCTS"; else
  echo "  Several Google accounts are signed in to Drive for desktop:"; i=1; while read -r a; do echo "    $i) $a"; i=$((i+1)); done <<< "$ACCTS"
  st drive wait "Several Drive accounts found — pick one in the Terminal"
  read -r -p "  Which one will you connect to Claude (Google Drive connector)? [1] " pick; pick="${pick:-1}"
  ACCT=$(echo "$ACCTS" | sed -n "${pick}p"); [ -n "$ACCT" ] || die "Invalid choice."
fi
ok "Drive account: $ACCT"
st drive done "$ACCT"
echo "  ${DIM}Reminder: in Claude, the Google Drive connector must be authorized for this same account.${NC}"

# ---- 4. me/ files ----------------------------------------------------------------------------------------------
CUR=settings; st settings running
say "Your settings (me/)"
mkdir -p "$KIT/me"
[ -f "$KIT/me/me.yaml" ] || { cp "$KIT/me/me.yaml.template" "$KIT/me/me.yaml"; ok "Created me/me.yaml"; }
[ -f "$KIT/me/groups.md" ] || { cp "$KIT/me/groups.md.template" "$KIT/me/groups.md"; ok "Created me/groups.md"; }
[ -f "$KIT/me/prefs.md" ] || { sed -e 's/{{NAME}}/you/g; s/{{SECTION}}/—/; s/{{DORM}}/—/; s/{{FOCUS}}/(not set yet)/; s/{{INTERESTS}}/(not set yet)/; s/{{NOT_FOR_ME}}/(not set yet)/' "$KIT/me/prefs.md.template" > "$KIT/me/prefs.md"; ok "Created me/prefs.md"; }
cfg_set drive_account "$ACCT"
[ -n "$(cfg drive_folder)" ] || cfg_set drive_folder "GSB Radar (auto)"
[ -n "$(cfg bundle_name)" ] || cfg_set bundle_name "gsb-radar-bundle.tar"
[ -n "$(cfg timezone)" ] || cfg_set timezone "$(readlink /etc/localtime | sed 's#.*/zoneinfo/##')"
ok "me/me.yaml: drive_account, timezone"

# ---- 5. launchd job ---------------------------------------------------------------------------------------------
st settings done "me/me.yaml · me/groups.md · me/prefs.md"
CUR=launchd; st launchd running
say "Background export job (launchd)"
PL="$HOME/Library/LaunchAgents/$LABEL.plist"
mkdir -p "$HOME/Library/LaunchAgents"
sed -e "s#__KIT__#$KIT#g" -e "s#__HOME__#$HOME#g" "$KIT/engine/launchd.plist.template" > "$PL"
plutil -lint "$PL" >/dev/null || die "Generated plist is invalid."
U=$(id -u)
launchctl bootout "gui/$U/$LABEL" 2>/dev/null
launchctl bootstrap "gui/$U" "$PL" && ok "Loaded $LABEL (runs when WhatsApp gets new messages, and hourly)" || die "launchctl bootstrap failed. Try: launchctl bootout gui/$U/$LABEL; then run setup again."

# ---- first export (through launchd, so Full Disk Access is tested the way it will be used) ---------------------
st launchd done "com.gsb-radar.export loaded"
CUR=export; st export running "Exporting your WhatsApp groups through the background job (up to 3 minutes)…"
say "First export (up to 3 minutes)"
DAY=$(date +%Y-%m-%d)
rm -f "$KIT/raw/$DAY/_done" "$KIT/raw/_last_export" 2>/dev/null
: > /tmp/gsb-radar-export.log
launchctl kickstart -k "gui/$U/$LABEL"
for i in $(seq 1 90); do [ -f "$KIT/raw/$DAY/_done" ] && break; sleep 2; printf '.'; done; echo
if [ -f "$KIT/raw/$DAY/_done" ]; then
  LOGF="$KIT/raw/$DAY/_export.log"
  NG=$(ls "$KIT/raw/$DAY"/*.json 2>/dev/null | wc -l | tr -d ' ')
  if grep -q 'SYNC FAILED' "$LOGF"; then
    warn "The background job ran but could NOT read WhatsApp. That is the Full Disk Access switch."
    echo "  Open System Settings → Privacy & Security → Full Disk Access, make sure 'wacrawl' is listed and ON,"
    echo "  then run setup.command again. Log: $LOGF"
    die "Full Disk Access is not granted yet."
  fi
  ok "Exported $NG groups to raw/$DAY"
  if grep -q 'BUNDLE OK' "$LOGF"; then ok "Bundle written to Google Drive/$(cfg drive_folder)/$(cfg bundle_name)"; st export done "$NG groups exported · bundle in Google Drive"; else warn "Bundle did not reach Google Drive yet — see $LOGF (doctor.command explains it)."; st export done "$NG groups exported · bundle NOT in Drive yet (doctor.command)"; fi
else
  warn "The background job did not finish in 3 minutes. launchd log:"; tail -15 /tmp/gsb-radar-export.log 2>/dev/null; tail -5 "$KIT/raw/$DAY/_export.log" 2>/dev/null
  die "First export failed. Run doctor.command, or run setup.command again after fixing the message above."
fi

# ---- 6. group discovery → me/groups.md U section --------------------------------------------------------------
CUR=groups; st groups running
say "Your WhatsApp groups"
/usr/bin/python3 - "$KIT" <<'PY'
import re,sys,os,glob,json
kit=sys.argv[1]; g=os.path.join(kit,'me','groups.md'); chats=os.path.join(kit,'chats.txt')
txt=open(g,encoding='utf-8').read() if os.path.exists(g) else ''
known=set(re.findall(r'\d+@g\.us',txt))
rows=[]
if os.path.exists(chats):
    for line in open(chats,encoding='utf-8',errors='replace'):
        m=re.search(r'(\d+@g\.us)\s+(.*)$',line.rstrip('\n'))
        if m and m.group(1) not in known: rows.append((m.group(1),m.group(2).strip() or '(unnamed group)'))
# message counts from today's export, to help the tiering chat
cnt={}
for f in glob.glob(os.path.join(kit,'raw','*','*@g.us.json')):
    try: cnt[os.path.basename(f)[:-5]]=cnt.get(os.path.basename(f)[:-5],0)+len(json.load(open(f)) or [])
    except Exception: pass
if rows:
    add='\n'.join(f"- {jid} | {name}  (found {__import__('datetime').date.today()}; {cnt.get(jid,0)} msgs in the export)" for jid,name in rows)
    if '## U — Untiered' in txt:
        txt=re.sub(r'(## U — Untiered[^\n]*\n)',lambda m:m.group(1)+add+'\n',txt,count=1)
    else:
        txt+='\n## U — Untiered (new, not yet classified; read like B until you move them)\n'+add+'\n'
    open(g,'w',encoding='utf-8').write(txt)
print(f"  {len(rows)} new group(s) listed under 'U — Untiered' in me/groups.md ({len(known)} already tiered).")
PY

# ---- done ----------------------------------------------------------------------------------------------------------
echo
st groups done "Listed in me/groups.md → U — Untiered"
CUR=""; st next wait "Open Claude, connect ~/gsb-radar, say: set me up"
echo "${GRN}${BOLD}Setup finished.${NC}"
echo
echo "${BOLD}Next step (10 minutes): let Claude finish your setup in a conversation.${NC}"
echo "  1. Open the Claude desktop app, start a new chat, and connect this folder:  $KIT"
echo "     (or run 'claude' in Terminal inside this folder, if you use Claude Code)."
echo "  2. Say:  ${BOLD}set me up${NC}"
echo "  Claude reads CLAUDE.md in this folder and interviews you: who you are, which groups matter, what you care about."
echo "  It writes your answers into me/, then helps you create the cloud task that builds your page three times a day."
echo
echo "  Later: ${BOLD}doctor.command${NC} diagnoses problems · ${BOLD}update.command${NC} installs new engine versions (never touches me/)."
echo
read -n1 -r -p "Press any key to close."
