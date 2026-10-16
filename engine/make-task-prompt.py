#!/usr/bin/env python3
"""Render engine/task-prompt.template.md with the values in me/me.yaml → me/task-prompt.md.

usage: python3 engine/make-task-prompt.py            (writes me/task-prompt.md and prints a summary)
       python3 engine/make-task-prompt.py --print    (prints the prompt itself)

Template syntax: {{KEY}} (upper-case me.yaml key), {{#if key}}…{{/if}}, {{#unless key}}…{{/unless}}.
A key is "true" for the conditionals when its value is true/yes/on/1 or any non-empty string that is not false/no/off/0/"".
Run it again whenever me/me.yaml changes (modules, calendars, names); then paste the new prompt into the scheduled task.
"""
import re, sys, os

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ME = os.path.join(KIT, 'me', 'me.yaml')
TPL = os.path.join(KIT, 'engine', 'task-prompt.template.md')
OUT = os.path.join(KIT, 'me', 'task-prompt.md')

def load_me(path):
    cfg = {}
    if not os.path.exists(path):
        sys.exit(f'missing {path} — run setup.command first')
    for line in open(path, encoding='utf-8'):
        line = line.rstrip('\n')
        if not line.strip() or line.lstrip().startswith('#') or ':' not in line:
            continue
        k, v = line.split(':', 1)
        v = re.sub(r'\s+#.*$', '', v).strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in '"\'':
            v = v[1:-1]
        cfg[k.strip()] = v
    return cfg

def truthy(v):
    return str(v).strip().lower() not in ('', 'false', 'no', 'off', '0')

def render(tpl, cfg):
    def block(m):
        kind, key, body = m.group(1), m.group(2), m.group(3)
        on = truthy(cfg.get(key, ''))
        return body if (on if kind == 'if' else not on) else ''
    # innermost blocks first, repeat until stable (handles one level of nesting)
    prev = None
    while prev != tpl:
        prev = tpl
        tpl = re.sub(r'\{\{#(if|unless) (\w+)\}\}((?:(?!\{\{#(?:if|unless) ).)*?)\{\{/\1\}\}', block, tpl, flags=re.S)
    def var(m):
        k = m.group(1).lower()
        return cfg.get(k, '')
    tpl = re.sub(r'\{\{([A-Z_]+)\}\}', var, tpl)
    # tidy: collapse 3+ blank lines left by removed blocks
    tpl = re.sub(r'\n{3,}', '\n\n', tpl)
    return tpl

def main():
    cfg = load_me(ME)
    missing = [k for k in ('name', 'wa_names', 'drive_account', 'page_title') if not cfg.get(k)]
    if truthy(cfg.get('module_email')) and not cfg.get('school_email'):
        missing.append('school_email (module_email is on)')
    if truthy(cfg.get('module_canvas')) and not cfg.get('canvas_calendar_id'):
        missing.append('canvas_calendar_id (module_canvas is on)')
    if not cfg.get('class_calendar_id'):
        cfg['class_calendar_id'] = cfg.get('school_email') or 'primary'
    cfg.setdefault('run_times', '7:05, 13:05, 19:05')
    cfg.setdefault('timezone', 'America/Los_Angeles')
    cfg.setdefault('drive_folder', 'GSB Radar (auto)')
    cfg.setdefault('bundle_name', 'gsb-radar-bundle.tar')
    # wa_names → quoted list for the prompt
    names = [n.strip() for n in cfg.get('wa_names', '').split(',') if n.strip()]
    cfg['wa_names'] = ' or '.join(f'"{n}"' for n in names) if names else '"(unknown — treat from_me=true as the user)"'
    out = render(open(TPL, encoding='utf-8').read(), cfg)
    if '--print' in sys.argv:
        print(out); return
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, 'w', encoding='utf-8').write(out)
    print(f'wrote {OUT} ({len(out)} chars)')
    mods = [m for m in ('email', 'canvas', 'poke') if truthy(cfg.get('module_' + m))]
    print('modules on:', ', '.join(mods) if mods else 'none (Lite)')
    if missing:
        print('WARNING — still empty in me/me.yaml:', ', '.join(missing))
        print('Fill them (the onboarding chat does this) and run this script again.')

if __name__ == '__main__':
    main()
