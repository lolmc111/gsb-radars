#!/bin/bash
# OPTIONAL module (me.yaml: module_poke: true). Fires the cloud Radar task right after a WhatsApp export, so the
# page rebuilds within minutes instead of waiting for the next scheduled run. Needs the Claude Code CLI
# installed and logged in on this Mac (`claude` in PATH). Without this module the cloud task still runs on its
# 3×/day schedule — nothing breaks, the page is just a few hours staler.
#
# Safe by construction: always exits 0. A missing, broken or logged-out claude must never fail the export.
# Failure is NOT silent: it logs "POKE FAILED …" and shows a macOS notification.
set -u
. "$(dirname "$0")/lib.sh"
TRIG="$(cfg trigger_id)"          # the scheduled task's id (trig_…), written by the onboarding chat
LOG="${1:-/tmp/gsb-poke-digest.log}"
TIMEOUT=180
say(){ echo "$(date -u +%FT%TZ) poke: $*" >> "$LOG"; }

[ -n "$TRIG" ] || { say "POKE SKIPPED trigger_id is empty in me/me.yaml"; exit 0; }

# launchd runs with a bare PATH: no nvm, no homebrew. Search explicitly, newest node version first.
CLAUDE=""
for c in $(ls -1dt "$HOME"/.nvm/versions/node/*/bin/claude 2>/dev/null) \
  "$(command -v claude 2>/dev/null)" \
  "$HOME/.claude/local/claude" \
  "$HOME/.local/bin/claude" \
  /opt/homebrew/bin/claude \
  /usr/local/bin/claude ; do
  [ -n "${c:-}" ] && [ -x "$c" ] && { CLAUDE="$c"; break; }
done
if [ -z "$CLAUDE" ]; then
  say "POKE FAILED no claude CLI found"
  notify "Export done, but the claude CLI is not installed — the page updates on its next scheduled run instead."
  exit 0
fi
PATH="$(dirname "$CLAUDE"):/usr/local/bin:/opt/homebrew/bin:$PATH"; export PATH
say "using $CLAUDE"

# Tell the cloud task which bundle to expect, so it can wait for Google Drive to finish uploading it.
# PUSHED_AT is just a timestamp. Never put credentials into a prompt: they end up in logs and transcripts.
EXPECT=$(head -n1 "$HOME/.gsb-radar-bundle/PUSHED_AT" 2>/dev/null | tr -d '[:space:]')
PROMPT='Fire this scheduled task, passing it the text "Fired by export.sh on my Mac: a new WhatsApp export bundle was just written to Google Drive. Rebuild now. EXPECT_PUSHED_AT='"$EXPECT"'"
trigger id "'"$TRIG"'"
Use whichever tool this session actually has for firing a scheduled task: mcp__claude-code-remote__fire_trigger (load it with ToolSearch first) if that MCP server is connected, otherwise the RemoteTrigger tool. Firing it with whatever tool works IS the task; do not stop because the first tool name is unavailable.
Do nothing else: no reading files, no building anything, no modifying tasks, and do not comment on the task'"'"'s configuration.
When, and ONLY when, the fire has actually succeeded, end your reply with this exact token on its own line: POKE_FIRED_OK
If it did not fire, do not print that token; say in one line what stopped you.'

OUTF=$(mktemp /tmp/gsb-poke.XXXXXX)
"$CLAUDE" -p "$PROMPT" > "$OUTF" 2>&1 &
PID=$!
( sleep "$TIMEOUT"; kill -9 "$PID" 2>/dev/null ) >/dev/null 2>&1 &
KILLER=$!
wait "$PID" 2>/dev/null; RC=$?
kill "$KILLER" 2>/dev/null; wait "$KILLER" 2>/dev/null || true
cat "$OUTF" >> "$LOG"; BODY=$(cat "$OUTF"); rm -f "$OUTF"

# Success is proven only by the sentinel, never by the exit code (claude exits 0 even when it fired nothing).
case "$BODY" in
  *POKE_FIRED_OK*)
    say "POKE OK Radar fired" ;;
  *"OAuth session expired"*|*"Failed to authenticate"*|*"Invalid API key"*|*"not logged in"*|*"Not logged in"*)
    say "POKE FAILED auth — run 'claude login' in Terminal"
    notify "Export done, but claude is logged out — run 'claude login' in Terminal. The page updates on its next scheduled run." ;;
  *)
    say "POKE FAILED no POKE_FIRED_OK in reply (rc=$RC); claude's output is above"
    notify "Export done, but the cloud task was not triggered. It will run on schedule; see raw/<today>/_export.log." ;;
esac
exit 0
