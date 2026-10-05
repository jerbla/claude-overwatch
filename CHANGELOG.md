# Changelog

## 1.0.0 (2026-10-05)
First public release of Claude Overwatch (`./overwatch`).

- Live feed in a VS Code window: commands typed like a person, every line of output, every line of
  code with line numbers, neon green on black. Replays the current task when the window opens.
- Pass/fail and time after every command (red `✗ exit N` on failure); pipelines fail if any part
  fails, `| head` cutting a pipe short does not.
- Browser steps and the full text of every page Claude reads.
- `live_remote` for work Claude does outside your Mac's shell (shown with `· cloud`).
- `live_write` headers say which lines changed when a file is rewritten, and note Windows line endings.
- Output streams line by line (Python unbuffered); progress bars show their final state; control
  codes and binary junk are shown as text (`^[[1A`, `^@`) instead of scrambling the window.
- A command killed mid-run gets a red "interrupted" line.
- Catch-up pacing: typing speeds up and pauses shrink only while the feed is behind; one line never
  takes more than ~2s; reopening replays everything but the last 100 lines instantly.
- End-of-task summary and a running `.overwatch-stats.log`.
- Heartbeat and lag files so Claude can tell the window is open without looking at your screen.
- "Plain shell" terminal profile for a normal zsh in the same folder.
- Opens as just the feed: the first time VS Code opens your folder, the feed starts by itself and
  there's no file sidebar, chat sidebar or git pop-up. The feed's working files are hidden.
- Installer and uninstaller that keep your own VS Code settings (merged, with a backup). Claude can
  do the whole setup for you the first time you say Yes.
- Self-test: `bash tests/run-tests.sh` (28 checks).
