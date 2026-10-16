#!/bin/bash
# Shared helpers for every engine script. Source it: `. "$(dirname "$0")/lib.sh"`.
# Reads me/me.yaml (flat `key: value` lines; quotes optional; `#` comments allowed). No yq needed.

# KIT = the folder that holds engine/ and me/ (the kit root), regardless of where the caller lives.
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$(cd "$_here/.." && pwd)"
ME="$KIT/me/me.yaml"
ENGINE="$KIT/engine"
RAW_ROOT="$KIT/raw"

# cfg KEY [default] — print the value of KEY from me.yaml, or the default when unset/empty.
cfg(){
  local k="$1" d="${2:-}" v
  v=$(grep -E "^[[:space:]]*$k[[:space:]]*:" "$ME" 2>/dev/null | head -n1 | sed -E "s/^[^:]*:[[:space:]]*//; s/[[:space:]]+#.*$//; s/^\"(.*)\"$/\1/; s/^'(.*)'$/\1/; s/[[:space:]]+$//")
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$d"
}
# cfg_bool KEY — exit 0 when the value is true/yes/on/1.
cfg_bool(){ case "$(cfg "$1" false | tr 'A-Z' 'a-z')" in true|yes|on|1) return 0;; *) return 1;; esac; }
# cfg_set KEY VALUE — set or append a key in me.yaml (keeps comments on other lines).
cfg_set(){
  local k="$1" v="$2"
  [ -f "$ME" ] || { mkdir -p "$(dirname "$ME")"; : > "$ME"; }
  if grep -qE "^[[:space:]]*$k[[:space:]]*:" "$ME"; then
    /usr/bin/python3 - "$ME" "$k" "$v" <<'PY'
import re,sys
p,k,v=sys.argv[1:4]
L=open(p).read().split('\n')
for i,l in enumerate(L):
    if re.match(r'^\s*'+re.escape(k)+r'\s*:',l):
        m=re.search(r'(\s+#.*)$',l.split(':',1)[1])
        L[i]=f'{k}: "{v}"'+(m.group(1) if m else '')
        break
open(p,'w').write('\n'.join(L))
PY
  else
    printf '%s: "%s"\n' "$k" "$v" >> "$ME"
  fi
}

WACRAWL="$HOME/wacrawl-scheduled/wacrawl"
LABEL="com.gsb-radar.export"
notify(){ /usr/bin/osascript -e "display notification \"$1\" with title \"GSB Radar\"" >/dev/null 2>&1 || true; }
now_iso(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
