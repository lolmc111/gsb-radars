# GSB Radar

A private page that reads your Stanford GSB WhatsApp groups (and, if you switch them on, your forwarded school email and Canvas due dates) and sorts everything into **To do · Assignments · About you · Go, join or sign up · Good to know · FYI**, plus a month calendar. It rebuilds three times a day. You open one link in the morning instead of forty group chats.

Nothing runs on anyone else's server. Your Mac exports your own WhatsApp groups to your own Google Drive; your own Claude account reads that file and publishes the page. No passwords or tokens exist anywhere in the setup.

## What you need

| | Why |
|---|---|
| A Mac (macOS 13+) that is awake for a while each day | The export runs on it |
| WhatsApp Desktop (App Store), signed in | It keeps the local message database the export reads |
| Google Drive for desktop, signed in | Moves the export file to the cloud through your own Drive |
| A Claude plan with **scheduled tasks** and **connectors** (Google Drive; plus Google Calendar / Gmail for the optional modules) | The cloud side |
| The Claude desktop app, or Claude Code | For the 10-minute onboarding chat and for changing things later |

## Install (15 minutes, two parts)

Illustrated walkthrough with a help desk: **https://claude.ai/artifact/S4SixbQVob7rAyf1c6FMTd** (ask Michael for access if it won't open).

**Part 1 — your Mac (5 min).** Open Terminal and paste:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/lolmc111/gsb-radars/main/install.sh)"
```

It downloads the kit to `~/gsb-radar` and runs `setup.command`: a progress page opens in your browser while the Terminal installs [wacrawl](https://github.com/openclaw/wacrawl) (open-source WhatsApp → SQLite exporter) through Homebrew, asks you to grant Full Disk Access to one copy of it, finds your Drive account, installs the background job, runs the first export and lists every group it found. You answer in the Terminal at four moments at most (Homebrew password, Full Disk Access, which Google account, Return).

Got the kit as a zip instead? Unzip it anywhere and double-click `setup.command`; it moves itself to `~/gsb-radar`. If macOS says the file "cannot be opened because it is from an unidentified developer": right-click → Open → Open.

**Part 2 — Claude (10 min).** Open the Claude desktop app, start a new chat, connect the folder `~/gsb-radar`, and say **set me up**. Claude reads `CLAUDE.md` in the folder and interviews you: who you are, what you care about, which groups matter, which modules to turn on. It writes your answers into `me/`, generates the cloud prompt, and creates (or helps you create) the scheduled task. The first run publishes your page and sends you its link.

## How it works

```
WhatsApp Desktop ──launchd (on new messages, ≤ every 30 min)──► engine/export.sh ──► raw/<date>/*.json
                                                                       │
                                                        engine/publish-bundle.sh
                                                                       ▼
                                   Google Drive / "GSB Radar (auto)" / gsb-radar-bundle.tar   (your Drive, auto-uploaded)
                                                                       │
                              Claude scheduled task "GSB Group Radar (cloud)" · 7:05 / 13:05 / 19:05
                              reads the bundle with the Google Drive connector, builds the page, keeps
                              check-offs and votes in the page's own database
                                                                       ▼
                                                         your page (claude.ai/artifact/…)
```

- `engine/` — identical for everyone; replaced wholesale by `update.command`. Never edit it.
- `me/` — yours: `me.yaml` (settings), `groups.md` (which groups, which tier), `prefs.md` (ranking rules in plain English), `task-prompt.md` (generated). Updates never touch it.
- `raw/` — the last 14 days of exports (groups only, never DMs). `chats.txt` — your chat list.

The page's **?** button has a one-minute tour, this diagram animated, how ranking works, and ready-made sentences to paste into Claude when you want something changed.

## Modules (all optional; default off)

| Module | What it adds | What you set up once |
|---|---|---|
| **Canvas** | Assignments section + due dates on the calendar | Subscribe to your Canvas calendar feed in Google Calendar (Canvas → Calendar → Calendar Feed → copy URL → Google Calendar → Other calendars → From URL), on the same Google account as Drive. The chat finds its id. |
| **Email** | School mail as items (official notices, things addressed to you) | Forward your @stanford.edu mail to that Gmail account; a filter applies label `GSB`, marks read, skips inbox. The chat walks you through it. |
| **Instant refresh** | Page rebuilds minutes after each export instead of on schedule | Claude Code CLI installed and logged in. Skip it unless you already use Claude Code. |

The already-scheduled filter (events on your own calendar are not repeated as items) and the calendar's exams/classes need `class_calendar_id` — usually your school Google calendar. If your school calendar is a different Google account than your Drive account, subscribe to it from the Drive account; the chat explains.

## Changing anything

Open the folder in Claude and say it in one sentence: "religious events are FYI for me", "move the Golf group to tier C", "FINANCE 305 assignments are due before the next class", "turn on Canvas". Claude edits `me/` and ships the change on the next export. The page's **Change it** tab has more starters, and a box to leave a note when you're away from your Mac.

Direct edits are fine too: `me/prefs.md` and `me/groups.md` are plain text. After editing, run `bash ~/gsb-radar/engine/export.sh --force` (or wait for the next export). Changes to `me/me.yaml` also need `python3 engine/make-task-prompt.py` and pasting the new `me/task-prompt.md` into the scheduled task — ask Claude: "update my radar task prompt".

## Troubleshooting

Double-click **`doctor.command`** first. It checks every stage and prints the fix.

| Symptom | Usually | Fix |
|---|---|---|
| "Updated" time on the page is old; amber dot or a stale banner | Mac asleep, WhatsApp Desktop not running recently, or the job isn't loaded | Wake the Mac, open WhatsApp once; `doctor.command` |
| macOS notification "WhatsApp export failed" | Full Disk Access missing for `~/wacrawl-scheduled/wacrawl`, or WhatsApp signed out | System Settings → Privacy & Security → Full Disk Access → switch wacrawl ON; sign in to WhatsApp |
| Notification "bundle did not reach Google Drive" | Drive for desktop signed out, or signed in to a different account than `me.yaml` says | Sign in; or fix `drive_account` |
| `cp: … Resource deadlock avoided` in `raw/<date>/_export.log` | Drive evicted the bundle to an online-only placeholder | In Finder: right-click the "GSB Radar (auto)" folder → *Make available offline* |
| Push: "Radar: bundle not found in Google Drive" | Drive connector in Claude is a different Google account than Drive for desktop | Reconnect the Google Drive connector with the `drive_account` account |
| Page never appears after the first run | Scheduled task didn't run, or ran without the Drive connector | Check the task's history in the Claude app; make sure Google Drive is enabled for the task |
| An item you handled keeps coming back as "Updated" | Its thread got new messages | That's by design; check it off again |
| Nothing from email after a day; item "no forwarded mail seen" | Forwarding or the Gmail filter isn't catching school mail | Re-check the filter; Google Workspace sometimes needs `deliveredto:` with the school's internal routing address — ask Claude |

Everything the export does is logged in `raw/<date>/_export.log`; launchd's own output is in `/tmp/gsb-radar-export.log`.

## Updating

Double-click `update.command`. A git clone pulls; otherwise it downloads the latest zip from github.com/lolmc111/gsb-radars. Running the install one-liner again does the same. `me/` is never touched by any of these.

## Uninstall

`launchctl bootout gui/$(id -u)/com.gsb-radar.export`, delete the scheduled task in Claude, remove `~/wacrawl-scheduled/wacrawl` from Full Disk Access, delete `~/gsb-radar`, `~/wacrawl-scheduled`, `~/.gsb-radar-bundle` and `~/.wacrawl/gsb-radar.db*`. The page stays until you delete the artifact in Claude.

## Privacy, in one paragraph

The export reads group messages only — never direct messages, never media — and only from groups you put in tiers A, B, C or U. Messages leave your Mac in one file that sits in your own Google Drive and is read by your own Claude account. The page is private to your account unless you share its link. Treat it like your inbox: don't forward it around. The tool reads WhatsApp's local database, which WhatsApp doesn't officially support; it is read-only and has not caused issues, but that is the honest status.
