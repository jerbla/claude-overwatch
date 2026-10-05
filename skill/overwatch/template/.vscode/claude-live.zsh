#!/bin/zsh
# ./overwatch viewer (Claude Overwatch). Shows ONLY Claude's real actions — commands, output, code as
# it's written, and browser steps with the page text Claude read. Commands type at
# human speed, code streams, output lands line by line. When the feed opens it
# replays the current task from its start (fast), then follows live. If Claude gets
# ahead, it speeds up so it never falls far behind.
# Writes a heartbeat (.overwatch.alive), its position in the log (.overwatch.pos,
# so Claude can measure lag), and reloads itself when this file changes.
setopt extendedglob
zmodload zsh/zselect zsh/stat
cd "${0:A:h}/.."
LOG=.claude-live.log; touch $LOG
CMD=$'\e[1;38;5;46m'; CODE=$'\e[38;5;46m'; OUT=$'\e[38;5;34m'; HEAD=$'\e[1;38;5;118m'; OK=$'\e[1;38;5;82m'
DIM=$'\e[38;5;28m'; ERR=$'\e[1;38;5;196m'
CUR=$'\e[38;5;46m█\e[D'; RST=$'\e[0m'
TITLE="● ./overwatch — real commands and code from this session"
SELF=${0:A}; zstat -A self_m +mtime $SELF
# Heartbeat: lets Claude confirm the feed is open without touching the screen
( while :; do : >| .overwatch.alive; sleep 2; done ) &
hb=$!
trap 'kill $hb 2>/dev/null' EXIT HUP INT TERM
tick(){ zselect -t ${1:-1} 2>/dev/null; }          # 1 tick = 10 ms
# Control codes (cursor moves, line erases, title changes, binary junk) would act on the
# terminal and erase or scramble earlier lines. Show them as visible text instead (^[, ^G ...).
CTRL=$'[\x00-\x08\x0b-\x1f\x7f]'
vis(){ local s=$1 o= c i n
  for (( i = 1; i <= ${#s}; i++ )); do c=$s[i]
    if [[ $c == ${~CTRL} ]]; then n=$(( #c )); (( n == 127 )) && o+='^?' || o+="^${(#)$(( n + 64 ))}"
    else o+=$c; fi
  done; clean=$o; }
pause(){ (( replaying )) && return                  # no pauses while catching up
  backlog; (( BL > 20000 )) && return                 # far behind: no pause
  (( BL > 1000 )) && { tick $(( $1 * 1000 / BL )); return; }   # behind: shorter pauses the further behind
  tick $1; }                                          # caught up: normal pause
backlog(){ local -a s; zstat -A s +size $LOG 2>/dev/null || s=(0); (( s[1] < consumed )) && consumed=$s[1]; BL=$(( s[1] - consumed )); }
flow(){ # flow COLOR TEXT CHARS_PER_TICK
  local color=$1 text=$2 step=$3 i=1 n=${#2} b
  if (( replaying )); then (( consumed < fast_end )) && step=$n || step=$(( step * 8 ))
  else backlog; b=$BL; (( b > 20000 )) && step=$n || { (( b > 1000 )) && step=$(( step * (b > 2000 ? 6 : 3) )); }; fi
  (( n / step > 200 )) && step=$(( (n + 199) / 200 ))   # cap: ~2s per line, still typed
  while (( i <= n )); do
    print -rn -- "${color}${text[i,i+step-1]}${CUR}"; (( i += step )); tick
  done
  print -- " ${RST}"
}
# Catch up: start from the current task's first line (the \f that live_start writes)
start=$(grep -n $'^\f$' $LOG | tail -n 1 | cut -d: -f1); : ${start:=1}
consumed=$(head -n $(( start - 1 )) $LOG | wc -c | tr -d ' ')
replay_end=$(zstat +size $LOG 2>/dev/null || print 0)
(( replaying = consumed < replay_end ))
fast_end=$(( replay_end - $(tail -n 100 $LOG | wc -c) ))     # everything before the last 100 lines
clear
flow "$HEAD" "$TITLE" 2
tail -n +$start -F $LOG 2>/dev/null | while IFS= read -r line; do
  () { setopt localoptions nomultibyte; (( consumed += ${#line} + 1 )) }   # count bytes, not chars
  clean=${line//$'\e'\[[0-9;]#m/}
  [[ $clean != $'\f' && $clean == *${~CTRL}* ]] && vis "$clean"
  case $clean in
    $'\f')      clear; consumed=2; flow "$HEAD" "$TITLE" 2 ;;   # new task = fresh screen
    '')         print ;;
    '$ '*)      flow "$CMD" "$clean" 1; pause 20 ;;           # typed like a person
    '> '*)      flow "$CMD" "$clean" 1; pause 5 ;;            # next line of a multi-line command
    *' │ '*)    flow "$CODE" "$clean" 4 ;;                    # code streams
    ' ↳ ✗'*)    flow "$ERR" "$clean" 3; pause 20 ;;           # command failed
    ' ↳ '*)     flow "$DIM" "$clean" 3; pause 10 ;;           # command finished OK
    '  '*)      print -r -- "${OUT}${clean}${RST}"; backlog; (( BL < 4000 )) && pause 2 ;; # output lands; no pause when far behind
    'web> '*)   flow "$CMD" "$clean" 1; pause 20 ;;           # browser step, typed like a command
    *▸*)        print; flow "$HEAD" "$clean" 2; pause 15 ;;
    *✎*|*✓*|'--- page text'*) flow "$OK" "$clean" 3; pause 10 ;;
    *)          print -r -- "${OUT}${clean}${RST}"; pause 2 ;;
  esac
  print -r -- $consumed >| .overwatch.pos                     # lets Claude measure lag
  (( replaying && consumed >= replay_end )) && replaying=0
  # Self-update: if Claude changes this script, restart it in place (replays the task)
  zstat -A now_m +mtime $SELF 2>/dev/null; [[ $now_m != $self_m ]] && { kill $hb 2>/dev/null; exec /bin/zsh $SELF; }
done
