#!/bin/bash
# Claude Overwatch self-test. Installs ./overwatch into a temporary folder and checks that the
# feed log gets every command, every output line and every line of code, exactly.
#   bash tests/run-tests.sh
# Runs anywhere with bash + GNU coreutils (the Claude Cowork shell). The viewer part also needs
# zsh and `script` (macOS has both); it is skipped when they are missing.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/overwatch-test.XXXXXX"); WS="$TMP/ws"
pass=0; fail=0
ok(){ if eval "$2"; then echo "  pass  $1"; pass=$((pass+1)); else echo "  FAIL  $1"; fail=$((fail+1)); fi; }
plain(){ sed 's/\x1b\[[0-9;]*m//g' "$WS/.claude-live.log"; }

echo "Installer"
bash "$ROOT/install.sh" "$WS" UTC >/dev/null 2>&1
ok "files installed" '[ -f "$WS/.vscode/live.sh" ] && [ -f "$WS/.vscode/claude-live.zsh" ] && [ -f "$WS/.vscode/zdot/.zshrc" ] && [ -x "$WS/Open Overwatch.command" ]'
ok "settings.json written" 'grep -q "Claude Live" "$WS/.vscode/settings.json"'
ok "feed opens by itself in a fresh folder (startupEditor = terminal)" 'grep -q "\"workbench.startupEditor\": \"terminal\"" "$WS/.vscode/settings.json"'
ok "no chat sidebar or git pop-up in the feed window" 'grep -q "secondarySideBar.defaultVisibility\": \"hidden" "$WS/.vscode/settings.json" && grep -q "openRepositoryInParentFolders\": \"never" "$WS/.vscode/settings.json"'
ok "opener hides the file sidebar on first open" 'grep -q "workbench.sideBar.hidden" "$WS/Open Overwatch.command"'
bash "$ROOT/install.sh" "$WS" UTC >/dev/null 2>&1
ok "re-install is clean (no duplicate .gitignore lines)" '[ -z "$(sort "$WS/.gitignore" | uniq -d)" ]'

echo "Helpers (live.sh)"
unset LIVE_WS; source "$WS/.vscode/live.sh"
ok "live.sh finds its own workspace" '[ "$WS" = "'"$WS"'" ]'
live_start "self-test" >/dev/null
live_run 'echo hello; echo to-stderr >&2' >/dev/null;               r1=$?
live_run 'exit 3' >/dev/null;                                        r2=$?
live_run 'cat /no/such/file | wc -l' >/dev/null;                     r3=$?
live_run 'seq 1 100000 | head -2' >/dev/null;                        r4=$?
ok "exit codes: 0, 3, pipeline failure, | head" '[ $r1 = 0 ] && [ $r2 = 3 ] && [ $r3 = 1 ] && [ $r4 = 0 ]'
ok "stdout and stderr both shown" 'plain | grep -qx "  hello" && plain | grep -qx "  to-stderr"'
back=$(live_run 'echo back-to-claude')
ok "live_run also hands its output back to Claude" '[ "$back" = "back-to-claude" ]'
ok "red line for failures" 'plain | grep -q "^ ↳ ✗ exit 3"'
live_run $'printf "a\\n"\necho second-line' >/dev/null
ok "multi-line command: \$ then >" 'plain | grep -qx "\$ printf \"a\\\\n\"" && plain | grep -qx "> echo second-line"'
live_run 'printf "dl 10%%\rdl 100%%\nwin\r\nno-newline-at-end"' >/dev/null
ok "progress bar keeps final state; CRLF and last line kept" 'plain | grep -qx "  dl 100%" && plain | grep -qx "  win" && plain | grep -qx "  no-newline-at-end"'
live_run 'printf "x\033[1Ay\0z\n"' >/dev/null
ok "control codes and NUL bytes reach the log untouched" 'grep -aq $'"'"'x\x1b\[1Ay'"'"' "$WS/.claude-live.log" && grep -caP "y\x00z" "$WS/.claude-live.log" >/dev/null'
live_run 'seq 1 20000' >/dev/null
ok "20,000 output lines, none dropped" '[ "$(plain | grep -cE "^  [0-9]+$")" -ge 20000 ]'
python_src=$(printf 'def f(x):\n    return "a\\tb\\n" + x  # backslashes stay\n\nprint(f("ok"))\n')
printf '%s\n' "$python_src" | live_write src/f.py
ok "live_write saves the file" '[ "$(cat "$WS/src/f.py")" = "$python_src" ]'
ok "every line of code in the feed, exactly" '[ "$(plain | sed -n "/writing src\/f.py/,/saved src\/f.py/p" | sed -n "s/^ *[0-9]* │ //p")" = "$python_src" ]'
printf 'def f(x):\n    return x\n' | live_write src/f.py
ok "change summary on rewrite" 'plain | grep -q "writing src/f.py.*(2 lines · changed: line 2 · 2 removed)"'
printf 'one\r\ntwo\r\n' | live_write src/w.txt
ok "Windows line endings noted, file saved byte-for-byte" 'plain | grep -q "w.txt.*Windows line endings" && [ "$(od -c "$WS/src/w.txt" | head -1)" = "$(printf "one\r\ntwo\r\n" | od -c | head -1)" ]'
printf 'only' | live_write src/one.txt
ok "line count: 1 line (no final newline)" 'plain | grep -q "one.txt.*(1 line)"'
printf 'out1\nout2\n' | live_remote 'curl -s example.com' 0 0.4
ok "live_remote shows cloud work" 'plain | grep -qx "  out2" && plain | grep -q "· cloud"'
( echo 1 > "$WS/.claude-live.run" ); live_note "after a killed command"
ok "killed command marked interrupted" 'plain | grep -q "interrupted (killed before it finished)"'
live_web open "https://example.com"; live_web_done "loaded"
printf 'Example Domain\nsecond line\n' | live_page "Example"
ok "browser step + full page text" 'plain | grep -q "^web> open" && plain | grep -qx "  second line"'
summary=$(live_end)
ok "end-of-task summary + stats row" '[[ $summary == summary:* ]] && grep -q "self-test" "$WS/.overwatch-stats.log"'

echo "Viewer (claude-live.zsh)"
if command -v zsh >/dev/null 2>&1 && command -v script >/dev/null 2>&1; then
  ok "viewer syntax" 'zsh -n "$WS/.vscode/claude-live.zsh"'
  : > "$WS/.overwatch.pos"; SCREEN="$TMP/screen.txt"
  if script --version >/dev/null 2>&1; then (cd "$WS" && exec script -qfc "zsh .vscode/claude-live.zsh" "$SCREEN" </dev/null >/dev/null 2>&1) & vp=$!
  else (cd "$WS" && exec script -q "$SCREEN" zsh .vscode/claude-live.zsh </dev/null >/dev/null 2>&1) & vp=$!; fi
  size=$(wc -c < "$WS/.claude-live.log" | tr -d ' ')
  for i in $(seq 1 120); do p=$(cat "$WS/.overwatch.pos" 2>/dev/null); [[ $p =~ ^[0-9]+$ ]] && (( p >= size )) && break; sleep 0.5; done
  ok "viewer replays the whole task (to the last byte)" '[[ $p =~ ^[0-9]+$ ]] && (( p >= size ))'
  ok "viewer heartbeat" '[ -f "$WS/.overwatch.alive" ]'
  ok "control codes shown as text, not executed" 'grep -aq "x^\[\[1Ay^@z" "$SCREEN" && ! grep -aq $'"'"'x\x1b\[1Ay'"'"' "$SCREEN"'
  ok "code shown exactly (backslashes kept)" 'grep -aqF "a\\tb\\n" "$SCREEN"'
  pkill -P $vp 2>/dev/null; kill $vp 2>/dev/null; wait $vp 2>/dev/null
else
  echo "  skip  zsh or script not found"
fi

rm -rf "$TMP" 2>/dev/null
echo; echo "$pass passed, $fail failed"; [ $fail = 0 ]
