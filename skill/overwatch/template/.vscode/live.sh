# ./overwatch - Claude's side of the live feed (part of Claude Overwatch).
# Sourced by Claude in the Cowork shell that can see this folder; not run on the Mac itself.
#   live_start "task name"     -> clears the feed, starts a new task header and the task clock
#   live_note "text"           -> section header (each one is a step in the end-of-task summary)
#   live_run 'command'         -> shows $ command (> for extra lines), runs it in the workspace, streams ALL output,
#                                 then a ✓/✗ line with exit code and time; returns the exit code. The output is
#                                 also printed back to Claude, so Claude sees its own results.
#   live_write path < content  -> streams the file's code line by line, then saves it
#   live_web action "detail"   -> a browser step (open / read / click / type / close) as a web> line
#   live_web_done "result"     -> ↳ ✓ line for that browser step, with the time since live_web
#   live_web_fail "reason"     -> ↳ ✗ line for that browser step
#   live_page "title" < text   -> streams ALL the text Claude read from a page, with word count
#   live_remote 'cmd' rc secs  -> shows a command Claude ran in its cloud workspace + ALL its output (stdin)
#   live_end                   -> end-of-task summary (time per step, ✓/✗ counts, browser steps,
#                                 feed lag) and one line appended to .overwatch-stats.log
#   overwatch_up               -> true if the feed window is open (heartbeat < 10s old)
#   overwatch_lag              -> prints how many log lines the feed has not shown yet (0 = caught up)
# The workspace is the folder this file sits in (<workspace>/.vscode/live.sh), unless LIVE_WS is set.
_OW_SELF="${BASH_SOURCE[0]:-$0}"
WS="${LIVE_WS:-$(cd "$(dirname "$_OW_SELF")/.." && pwd)}"; LOG="$WS/.claude-live.log"
# Optional settings written by the installer (e.g. OVERWATCH_TZ=America/New_York for the [hh:mm:ss] stamps)
[[ -f $WS/.vscode/overwatch.conf ]] && . "$WS/.vscode/overwatch.conf"
STEPS="$WS/.claude-live.steps"; WEBT="$WS/.claude-live.webt"; MAXLAG="$WS/.claude-live.maxlag"
STATS="$WS/.overwatch-stats.log"; RUNF="$WS/.claude-live.run"
SB=(); command -v stdbuf >/dev/null && SB=(stdbuf -oL -eL)
C=$'\033[36m'; G=$'\033[32m'; Y=$'\033[33m'; D=$'\033[2m'; B=$'\033[1m'; RED=$'\033[31m'; R=$'\033[0m'
ts(){ TZ="${OVERWATCH_TZ:-${TZ:-UTC}}" date +%H:%M:%S; }
now_ms(){ echo $(( $(date +%s%N) / 1000000 )); }
fmt_ms(){ local ms=$1
  if (( ms >= 60000 )); then printf '%dm %02ds' $(( ms / 60000 )) $(( ms % 60000 / 1000 ))
  else printf '%d.%ds' $(( ms / 1000 )) $(( ms % 1000 / 100 )); fi; }
live_start(){ echo 0 > "$RUNF"; : > "$LOG"; printf '\f\n' >> "$LOG"; echo 0 > "$MAXLAG"
  printf '%s\t%s\n' "$(now_ms)" "${1:-New task}" > "$STEPS"
  printf '\n%s%s▸ %s%s %s[%s]%s\n' "$B" "$C" "${1:-New task}" "$R" "$D" "$(ts)" "$R" >> "$LOG"; }
live_note(){ _close_open_run; _lag_sample; printf '%s\t%s\n' "$(now_ms)" "$1" >> "$STEPS"
  printf '\n%s%s▸ %s%s %s[%s]%s\n' "$B" "$C" "$1" "$R" "$D" "$(ts)" "$R" >> "$LOG"; }
live_run(){ local t0 rc ms el
  _close_open_run
  _cmd_lines "$1"
  t0=$(date +%s%N); echo 1 > "$RUNF"
  # PYTHONUNBUFFERED + stdbuf: output streams line by line instead of arriving at the end
  # progress bars (\r updates) keep the final state of the line; every line is written, nothing dropped
  (cd "$WS" && PYTHONUNBUFFERED=1 ${SB[@]} bash -o pipefail -c "$1" < /dev/null) 2>&1 | LC_ALL=C awk -v lf="$LOG" '{ sub(/\r$/, ""); n = split($0, a, "\r"); print "  " a[n] >> lf; fflush(lf); print a[n]; fflush() }'
  rc=${PIPESTATUS[0]}; echo 0 > "$RUNF"
  (( rc == 141 )) && rc=0                              # SIGPIPE from "| head" etc. is not a failure
  ms=$(( ($(date +%s%N) - t0) / 1000000 )); el=$(printf '%d.%ds' $((ms / 1000)) $((ms % 1000 / 100)))
  if (( rc == 0 )); then printf '%s ↳ ✓ %s%s\n' "$D" "$el" "$R" >> "$LOG"
  else printf '%s ↳ ✗ exit %d · %s%s\n' "$RED" "$rc" "$el" "$R" >> "$LOG"; fi
  _lag_sample; return $rc; }
_cmd_lines(){ local first=1 c; { while IFS= read -r c || [[ -n $c ]]; do
      if (( first )); then printf '%s$ %s%s\n' "$Y" "$c" "$R"; first=0; else printf '%s> %s%s\n' "$Y" "$c" "$R"; fi
    done <<< "$1"; } >> "$LOG"; }
# live_remote: work Claude ran in its cloud workspace (downloads, installs, image checks) that
# the Mac shell can't do. Shows it exactly like live_run: $ command, ALL its real output, ✓/✗ + time.
#   live_remote 'command' EXIT_CODE SECONDS < output_file   (or a heredoc with the full output)
live_remote(){ local rc=${2:-0} el=${3:-0}; _close_open_run; _lag_sample; _cmd_lines "$1"
  LC_ALL=C awk '{ sub(/\r$/, ""); n = split($0, a, "\r"); print "  " a[n]; fflush() }' >> "$LOG"
  if (( rc == 0 )); then printf '%s ↳ ✓ %ss · cloud%s\n' "$D" "$el" "$R" >> "$LOG"
  else printf '%s ↳ ✗ exit %d · %ss · cloud%s\n' "$RED" "$rc" "$el" "$R" >> "$LOG"; fi; }
# .claude-live.run holds 1 while a command runs, 0 otherwise (overwritten, never deleted).
# If a live_run was killed (e.g. the 3-minute tool timeout), its result line never got written.
# The next live_* call writes it, so the feed never shows a command with no outcome.
_close_open_run(){ [[ $(cat "$RUNF" 2>/dev/null) == 1 ]] || return 0; echo 0 > "$RUNF"
  printf '%s ↳ ✗ interrupted (killed before it finished)%s\n' "$RED" "$R" >> "$LOG"; }
live_write(){ local f="$1" tmp info n; _close_open_run; tmp=$(mktemp); cat > "$tmp"
  n=$(awk 'END { print NR }' "$tmp"); (( n == 1 )) && info="1 line" || info="$n lines"
  grep -q $'\r$' "$tmp" && info+=" · Windows line endings"     # shown without the invisible \r; file saved as-is
  [[ -f $WS/$f ]] && info+=" · $(_changes "$WS/$f" "$tmp")"
  printf '%s✎ writing %s%s %s(%s)%s\n' "$G" "$f" "$R" "$D" "$info" "$R" >> "$LOG"
  awk '{ sub(/\r$/, ""); printf "\033[2m%4d │\033[0m %s\n", NR, $0 }' "$tmp" >> "$LOG"
  mkdir -p "$(dirname "$WS/$f")"; cp "$tmp" "$WS/$f"; rm -f "$tmp"
  printf '%s✓ saved %s%s\n' "$G" "$f" "$R" >> "$LOG"; }
# Which lines of the new version differ from the saved file, e.g. "changed: lines 3-5, 12 · 2 removed"
_changes(){ diff "$1" "$2" | awk '/^[0-9]/ { split($0, p, /[acd]/); op = substr($0, length(p[1]) + 1, 1)
      n = split(p[1], L, ","); l1 = L[1]; l2 = (n > 1 ? L[2] : L[1])
      n = split(p[2], N, ","); r1 = N[1]; r2 = (n > 1 ? N[2] : N[1])
      if (op == "d") rm += l2 - l1 + 1
      else { rng = rng (rng != "" ? ", " : "") (r1 == r2 ? r1 : r1 "-" r2)
             if (op == "c" && l2 - l1 > r2 - r1) rm += (l2 - l1) - (r2 - r1) } }
    END { out = ""; if (rng != "") out = ((index(rng, ",") || index(rng, "-")) ? "changed: lines " : "changed: line ") rng
          if (rm > 0) out = out (out != "" ? " · " : "") rm " removed"
          print (out == "" ? "no changes" : out) }'; }
# Browser steps (Claude in Chrome / built-in browser). Time = wall clock from live_web to done.
live_web(){ _close_open_run; _lag_sample; now_ms > "$WEBT"
  printf '%sweb> %-6s %s%s\n' "$G" "$1" "$2" "$R" >> "$LOG"; }
_web_el(){ local t0; t0=$(cat "$WEBT" 2>/dev/null) || t0=$(now_ms); fmt_ms $(( $(now_ms) - t0 )); }
live_web_done(){ printf '%s ↳ ✓ %s · %s%s\n' "$D" "${1:-done}" "$(_web_el)" "$R" >> "$LOG"; }
live_web_fail(){ printf '%s ↳ ✗ %s · %s%s\n' "$RED" "${1:-failed}" "$(_web_el)" "$R" >> "$LOG"; }
live_page(){ local tmp; tmp=$(mktemp); cat > "$tmp"
  printf '%s--- page text: %s%s %s(%s lines, %s words, all of it)%s\n' "$G" "$1" "$R" "$D" \
    "$(wc -l < "$tmp" | tr -d ' ')" "$(wc -w < "$tmp" | tr -d ' ')" "$R" >> "$LOG"
  while IFS= read -r l || [[ -n $l ]]; do printf '  %s\n' "$l" >> "$LOG"; done < "$tmp"
  rm -f "$tmp"; }
overwatch_up(){ local f="$WS/.overwatch.alive"; [[ -f $f ]] && (( $(date +%s) - $(stat -c %Y "$f") < 10 )); }
# The viewer writes how many bytes of the log it has shown to .overwatch.pos after every line.
overwatch_lag(){ local p s; p=$(cat "$WS/.overwatch.pos" 2>/dev/null); s=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
  [[ $p =~ ^[0-9]+$ ]] || { echo "?"; return 1; }
  (( p >= s )) && { echo 0; return 0; }
  tail -c +$(( p + 1 )) "$LOG" | wc -l | tr -d ' '; }
_lag_sample(){ local l m; l=$(overwatch_lag) || return 0; m=$(cat "$MAXLAG" 2>/dev/null); m=${m:-0}
  (( l > m )) && echo "$l" > "$MAXLAG"; return 0; }
live_end(){ local end task total ok bad web lag maxlag i l
  _close_open_run; end=$(now_ms); _lag_sample
  for i in 1 2 3 4 5 6 7 8 9 10; do l=$(overwatch_lag); [[ $l == 0 || $l == "?" ]] && break; sleep 0.5; done   # "?" = no feed window
  lag=$(overwatch_lag); maxlag=$(cat "$MAXLAG" 2>/dev/null)
  task=$(head -n 1 "$STEPS" | cut -f2-); total=$(( end - $(head -n 1 "$STEPS" | cut -f1) ))
  local plain; plain=$(sed 's/\x1b\[[0-9;]*m//g' "$LOG" | tr -d '\0')   # count result lines only, not code that mentions them
  ok=$(grep -c '^ ↳ ✓' <<< "$plain"); bad=$(grep -c '^ ↳ ✗' <<< "$plain"); web=$(grep -c '^web> ' <<< "$plain")
  printf '\n%s%s▸ Summary: %s%s %s[%s]%s\n' "$B" "$C" "$task" "$R" "$D" "$(ts)" "$R" >> "$LOG"
  awk -F'\t' -v end="$end" '{ t[NR]=$1; n[NR]=$2 }
    END { for (i = 1; i <= NR; i++) { d = ((i < NR) ? t[i+1] : end) - t[i]
            name = (i == 1) ? "(start)" : n[i]
            printf "  %8.1fs  %s\n", d / 1000, name } }' "$STEPS" >> "$LOG"
  printf '  total %s · %s ✓ · %s ✗ · %s browser steps · feed lag max %s lines, now %s\n' \
    "$(fmt_ms $total)" "$ok" "$bad" "$web" "${maxlag:-?}" "$lag" >> "$LOG"
  [[ -f $STATS ]] || printf 'date\ttask\ttotal_s\tok\tfailed\tbrowser_steps\tmax_lag_lines\tend_lag_lines\n' > "$STATS"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(TZ="${OVERWATCH_TZ:-${TZ:-UTC}}" date '+%Y-%m-%d %H:%M')" "$task" \
    "$(( total / 1000 ))" "$ok" "$bad" "$web" "${maxlag:-?}" "$lag" >> "$STATS"
  echo "summary: total $(fmt_ms $total), $ok ok, $bad failed, $web browser steps, lag max ${maxlag:-?} / now $lag"; }
