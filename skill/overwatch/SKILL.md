---
name: overwatch
description: ./overwatch (Claude Overwatch), a live terminal view of everything Claude does in Cowork. At the start of every Cowork task ask "Run ./overwatch for this task?"; if yes, stream the real commands, their output and all code as it is written into a neon-green VS Code window on the user's Mac.
---

# ./overwatch

./overwatch is a live feed of Claude's work: a VS Code window on the user's Mac that types out every real command Claude runs, all of its output, and every line of code as Claude writes it, neon green on black. Always write the name exactly as `./overwatch` (like running a script). The project is published as "Claude Overwatch"; inside the product it is always `./overwatch`.

IMPORTANT: load this skill WITHOUT arguments. Passing args makes the loader substitute `$0`, `$1`, `$2`... inside the code this skill refers to, which garbles it.

## The one question
At the START of every Cowork task, before anything else (before folder or app access requests), ask one AskUserQuestion: "Run ./overwatch for this task?" with header "./overwatch", multiSelect false, and EXACTLY two options: label "Yes" with description "" (empty) and label "No" with description "" (empty). No explanation text under the choices, no "(Recommended)", no extra options. It should be the only prompt at startup. On "No", skip everything in this skill. On "Yes", startup must be almost instant: usually ONE device_bash call, then just work.

## Rules of the feed (these are the product)
- Show ONLY real work: the actual commands, their real output, and the code as it is written. No fake effects (no matrix rain, no random glyphs, no decorative output).
- Show ALL of it. Never truncate, summarize or collapse output, page text or code. Seeing everything is the whole point.
- No emoji or icons in anything Claude adds to the feed: green text and plain symbols only (▸ ↳ ✓ ✗ ✎ │).
- Errors show as they really happen (red ✗). Fix them through the feed too.

## How it works
- The workspace is the folder the user connected to Cowork (for example `~/Claude-Workspace`). In device_bash it is mounted at `$HOME/mnt/<folder-name>`.
- `.vscode/live.sh` (sourced by Claude) appends everything to `.claude-live.log` in that folder.
- `.vscode/claude-live.zsh` (the viewer) runs in VS Code on the Mac, tails the log and types it out: commands typed like a person, code streaming with line numbers, output landing line by line. It lives in the editor area (no panel), fills the window, and replays the current task from its start whenever it opens, then follows live.
- `.vscode/settings.json` makes the viewer the default terminal ("Claude Live"), and `ZDOTDIR` points at `.vscode/zdot`, whose `.zshrc` turns any terminal VS Code opens or revives in this folder into the feed. The "Plain shell" profile (terminal dropdown) is the one exception: it gets the user's normal zsh.
- Heartbeat: the viewer rewrites `.overwatch.alive` every 2s, so `overwatch_up` tells Claude whether the window is open without screen access. It also writes its position to `.overwatch.pos`, so `overwatch_lag` says how many lines it is behind (0 = caught up).
- Behaviour Claude can rely on: every live_run ends with `↳ ✓ 1.2s` or a red `↳ ✗ exit N · 1.2s` (pipelines fail if any part fails; `| head` cutting a pipe short is fine); output streams line by line (Python unbuffered, stdbuf); stdin is /dev/null; progress bars show their final state; control codes and binary junk in output are shown as visible text (`^[[1A`, `^@`) instead of acting on the terminal; a command killed mid-run (e.g. the 3-minute device_bash limit) gets a red "interrupted" line on the next live_* call; the viewer speeds up its typing and shortens pauses only while it is behind, and one line never takes more than ~2s.
- `live_end` prints a summary (time per step, ✓/✗ counts, browser steps, feed lag) and appends a row to `.overwatch-stats.log`.
- Optional time zone for the `[hh:mm:ss]` stamps: `.vscode/overwatch.conf` (`OVERWATCH_TZ=America/New_York`).

## Startup (on "Yes")
1. Find the workspace. If a folder is already connected, run ONE device_bash call:
   `OW=$(ls -d $HOME/mnt/*/.vscode/live.sh 2>/dev/null | head -1); [ -n "$OW" ] && source "$OW" && live_start "<task name>" && { overwatch_up && echo UP || echo DOWN; } || echo NOT-INSTALLED`
   - If no folder is connected yet, request the one the user works in (`device_request_folder_access`, e.g. `["~/Claude-Workspace"]`), then run the line above.
   - If several connected folders have ./overwatch, prefer the one this task is about; otherwise the first.
2. UP: the feed window is open. Start working; no screenshots, no more prompts.
3. DOWN: VS Code isn't open on the workspace. Use computer access only now: `computer_resolve_access ["Visual Studio Code"]` -> `computer_request_access` -> `computer_open_application com.microsoft.VSCode` (or ask the user to double-click `Open Overwatch.command` in the folder). The feed starts and replays. Re-check `overwatch_up` after ~5s.
   - Still DOWN with VS Code open on the folder: the user (or Claude with full control) picks Terminal > New Terminal; it opens as the feed in the editor area.
4. NOT-INSTALLED: set it up once (see "First-time setup"), then continue from step 1.

## First-time setup (when NOT-INSTALLED)
The files ship inside this skill: `install.sh`, `uninstall.sh`, `VERSION` and `template/` in this skill's base directory.
1. Pack this skill's folder into ONE tarball and copy it into the workspace. Cowork's file-copy tool refuses paths that contain `.vscode` or dotfiles like `.zshrc`, so never copy the template files one by one. From a cloud workspace:
   `tar czf /mnt/user-data/outputs/overwatch-setup-<VERSION>.tgz -C "<this skill's base directory>/.." "<this skill's folder name>"`
   then `device_commit_files` it to `<folder>/.overwatch-setup/overwatch-setup-<VERSION>.tgz` (a new file name for each version).
2. Unpack and install with device_bash:
   `cd "$HOME/mnt/<folder-name>/.overwatch-setup" && tar xzf overwatch-setup-<VERSION>.tgz && bash */install.sh "$HOME/mnt/<folder-name>" "<the user's IANA time zone if known, e.g. America/New_York>"`
   It copies the feed files, writes the time zone, merges the ./overwatch keys into `.vscode/settings.json` (keeping the user's own settings, with a backup), and adds the feed's working files to `.gitignore`.
3. Tell the user in one line: double-click `Open Overwatch.command` in the folder. VS Code opens with just the feed running (if VS Code asks whether to trust the folder, they choose "Yes, I trust the authors"; if they had opened that folder in VS Code before, Cmd+B once hides the file sidebar). Then continue with Startup.
To update later, do the same with the newer skill and run the installer again; to remove, run `uninstall.sh` (on the Mac it deletes files; inside Cowork, deleting needs the user's permission).

## During the task: route EVERYTHING through the feed
Start each device_bash call with `source $HOME/mnt/<folder-name>/.vscode/live.sh`.
- `live_note "Step 2 - build the report"`: section header (each one is a step in the summary)
- `live_run 'command'`: shows `$ command` (extra lines as `> ...`), runs it in the workspace, streams ALL output, then ✓/✗ with exit code and time; returns the exit code
- `live_write path/in/workspace < file` (or a heredoc): streams every line of the file with line numbers, then saves it. When the file already existed the header says what changed: `(6 lines · changed: lines 1-2, 6)`, `(… · 2 removed)`, `(… · no changes)`; Windows files say `· Windows line endings`. Write files this way, not with cat or sed, so the code appears. For edits, build the new version in scratch (`$HOME/...`), then live_write it.
- `live_remote 'command' EXIT_CODE SECONDS <<'OVERWATCH_EOF'` … the command's FULL output … `OVERWATCH_EOF`: for anything Claude ran outside the Mac's shell (in its cloud workspace: downloads, installs, image checks, syntax checks). The Mac-side shell may have no internet, so mirror that work here; it shows exactly like live_run with `· cloud` after the time.
- Browser work (Claude in Chrome or the built-in browser): BEFORE each browser call, in the same message as a device_bash call, `live_web open "https://..."` (actions: open / read / click / type / close); after it `live_web_done "what happened"` or `live_web_fail "why"`. Batch the done-line of one step with the live_web of the next. Only log steps that really happen.
- After every page read (get_page_text / read_page), stream the FULL text: `live_page "Page title" <<'OVERWATCH_EOF'` … `OVERWATCH_EOF` (quoted delimiter so nothing expands). Never shorten it.
- At the very end of every task: `live_end`.
- `overwatch_lag` shows whether the user is seeing things in real time; after a big write it is normally tens to a few hundred lines and drops to 0 within ~10-20s.

## Habits while ./overwatch is on
- Run commands ONE AT A TIME (parallel live_runs interleave their output).
- Keep single commands under ~3 minutes (device_bash limit); split long jobs.
- Start background servers with their output redirected (`cmd > server.log 2>&1 &`), or live_run waits for them. Stop them by PID (`kill $!`), never `pkill -f <text>` (it also matches and kills Claude's own shell).
- Copy binary files (images, PDFs, zips) with `live_run 'cp …'`, not live_write.
- Programs that wait for keyboard input get end-of-file immediately; pass input with arguments or a pipe.
- Cowork folders may not allow deleting files: tools that replace files in place (zip updating an archive, SQLite journals) can fail there. The feed shows that as it happens.

## VS Code notes (for when Claude has to use computer access)
- Click by `element_index` from a fresh `computer_app_screenshot`/`computer_app_ax_find`; coordinates misfire. Menu-bar items need full control.
- Keep exactly ONE feed terminal open. Edits to `.vscode/claude-live.zsh` apply on their own (the viewer reloads itself and replays the task).
- Application-wide settings such as `window.titleBarStyle` (`native` gives a thin Mac title bar) only work in the user's own VS Code settings, not the workspace's; change them only if the user asks.
