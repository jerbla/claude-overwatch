#!/bin/bash
# Claude Overwatch installer: sets up ./overwatch in one folder (the folder Claude Cowork works in).
#   bash install.sh [FOLDER] [TIME_ZONE]
#   FOLDER     defaults to ~/Claude-Workspace (created if missing)
#   TIME_ZONE  e.g. America/New_York; detected automatically when left out
# Safe to run again (updates the files). Your existing VS Code settings are kept and backed up.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TPL="$HERE/template"
TARGET="${1:-$HOME/Claude-Workspace}"
TZNAME="${2:-}"
VERSION=$(cat "$HERE/VERSION" 2>/dev/null || echo "?")

[ -d "$TPL" ] || { echo "error: template folder not found next to install.sh ($TPL)"; exit 1; }
mkdir -p "$TARGET/.vscode/zdot"
TARGET=$(cd "$TARGET" && pwd)
echo "Installing ./overwatch $VERSION into $TARGET"

# 1. The feed files (overwritten on update)
for f in .vscode/live.sh .vscode/claude-live.zsh .vscode/zdot/.zshrc .vscode/overwatch-settings.json; do
  cp "$TPL/$f" "$TARGET/$f"; echo "  + $f"
done
cp "$TPL/Open Overwatch.command" "$TARGET/Open Overwatch.command"
chmod +x "$TARGET/Open Overwatch.command"; echo "  + Open Overwatch.command"

# 2. Time zone for the [hh:mm:ss] stamps (kept if already set)
if [ ! -f "$TARGET/.vscode/overwatch.conf" ]; then
  if [ -z "$TZNAME" ]; then
    if [ "$(uname)" = "Darwin" ]; then TZNAME=$(readlink /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##')
    elif [ -f /etc/timezone ]; then TZNAME=$(cat /etc/timezone)
    fi
  fi
  printf '# ./overwatch settings\nOVERWATCH_TZ=%s\n' "${TZNAME:-UTC}" > "$TARGET/.vscode/overwatch.conf"
  echo "  + .vscode/overwatch.conf (time zone ${TZNAME:-UTC})"
fi

# 3. VS Code workspace settings: add the ./overwatch keys, keep everything else
SETTINGS="$TARGET/.vscode/settings.json"
python_ok(){ command -v python3 >/dev/null 2>&1 || return 1
  [ "$(uname)" = "Darwin" ] && ! xcode-select -p >/dev/null 2>&1 && return 1   # avoid the macOS install pop-up
  return 0; }
if [ ! -f "$SETTINGS" ]; then
  cp "$TARGET/.vscode/overwatch-settings.json" "$SETTINGS"; echo "  + .vscode/settings.json"
else
  [ -f "$SETTINGS.before-overwatch" ] || { cp "$SETTINGS" "$SETTINGS.before-overwatch"; echo "  backup: .vscode/settings.json.before-overwatch"; }
  if python_ok; then
    python3 - "$SETTINGS" "$TARGET/.vscode/overwatch-settings.json" <<'PY'
import json, re, sys
def load_jsonc(text):
    out, i, n, s = [], 0, len(text), None
    while i < n:                                  # drop // and /* */ comments outside strings
        c = text[i]
        if s:
            out.append(c)
            if c == '\\': out.append(text[i+1:i+2]); i += 2; continue
            if c == s: s = None
        elif c == '"': s = c; out.append(c)
        elif text.startswith('//', i): i = text.find('\n', i); i = n if i < 0 else i; continue
        elif text.startswith('/*', i): j = text.find('*/', i + 2); i = n if j < 0 else j + 2; continue
        else: out.append(c)
        i += 1
    clean = re.sub(r',(\s*[}\]])', r'\1', ''.join(out))   # trailing commas
    return json.loads(clean) if clean.strip() else {}
path, ours = sys.argv[1], sys.argv[2]
cur = load_jsonc(open(path, encoding='utf-8').read())
for k, v in json.load(open(ours, encoding='utf-8')).items():
    if isinstance(v, dict) and isinstance(cur.get(k), dict): cur[k].update(v)
    else: cur[k] = v
open(path, 'w', encoding='utf-8').write(json.dumps(cur, indent=2, ensure_ascii=False) + '\n')
PY
    echo "  ~ .vscode/settings.json (./overwatch keys merged in)"
  else
    cp "$TARGET/.vscode/overwatch-settings.json" "$SETTINGS"
    echo "  ! .vscode/settings.json replaced (no python3 to merge). Your old settings are in"
    echo "    .vscode/settings.json.before-overwatch; copy back any you want to keep."
  fi
fi

# 4. Keep the feed's working files out of git
GI="$TARGET/.gitignore"; touch "$GI"
for l in .claude-live.log .claude-live.steps .claude-live.webt .claude-live.maxlag .claude-live.run \
         .overwatch.alive .overwatch.pos .overwatch-stats.log; do
  grep -qxF "$l" "$GI" || echo "$l" >> "$GI"
done
echo "  ~ .gitignore"

# 5. Files downloaded from the internet are quarantined by macOS; let the opener run
[ "$(uname)" = "Darwin" ] && xattr -dr com.apple.quarantine "$TARGET/Open Overwatch.command" "$TARGET/.vscode" 2>/dev/null || true

echo "Done. Open the folder in VS Code (double-click 'Open Overwatch.command') and the feed starts."
