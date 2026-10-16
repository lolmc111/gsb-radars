# Known issues and limits — kit 1.0.0 (2026-10-12)

Add to this file as pilots surface things. Newest first.

## Not yet verified on a second Mac
- The whole kit was derived from one working installation. `setup.command` has not yet been run end-to-end on a fresh Mac; the first pilot install is the test. Expect small snags around Homebrew's first install (password prompt, PATH) and the Full Disk Access dialog.
- `wacrawl` CLI flags used by the export (`--db`, `--sync never`, `--json`, `messages --chat --after --asc --limit`, `chats --limit`) match the version the original install used. If a newer wacrawl renames one, `export.sh` logs it in `raw/<date>/_export.log` and `doctor.command` shows SYNC FAILED.

## Progress page (setup)
- `setup.command` serves a progress page on 127.0.0.1:47821 with python3's http.server. If that port is busy or python3 is missing the page simply does not open; setup continues in the Terminal unaffected.

## By design
- **Mac must be awake.** Nothing runs while it sleeps; the export reaches back to the last delivered run (up to 7 days) so nothing is lost, but the page is only as fresh as the last wake.
- **One Google account across Drive for desktop, the Claude Google Drive connector, and (if used) the Canvas calendar subscription and Gmail label.** Mixing accounts is the #1 way to get "bundle not found".
- **No DMs, no media.** Images and documents are resized/copied locally into `raw/<date>/media/` for your own use but never leave the Mac.
- **The cloud task's learned rules don't write back to the Mac.** They live in each edition's `meta.notes`; your Claude copies the ones you keep into `me/prefs.md` on request.
- **Suggestions typed on the page** are only read by the next cloud build; they don't edit `me/prefs.md` by themselves.
- **Checkmarks need the claude.ai page.** A downloaded copy of the HTML shows the content but can't save check-offs or votes.
- **Google Workspace forwarding quirk.** `deliveredto:you@stanford.edu` often does *not* match forwarded Stanford mail; a Gmail filter on the label is the reliable path, and the fallback search in the task prompt uses `to:` — which can miss mail sent via lists. If email items look thin, ask Claude to check the filter.

## Cloud-side
- First run creates the artifact; if the account's Claude lacks the `db`/`user` capabilities for artifacts, the page still publishes but check-offs won't persist (the page shows a yellow note).
- The scheduled task runs on the user's own Claude usage. Three builds a day plus pokes is noticeable on a light plan.

## Harmless noise
- `wacrawl sync` prints a warning about an existing default archive on some machines; the kit uses its own throwaway archive at `~/.wacrawl/gsb-radar.db` and never touches `~/.wacrawl/wacrawl.db`.
- `doctor.command`'s "online-only placeholder" check is a heuristic; if the bundle is small and fresh, ignore it.
