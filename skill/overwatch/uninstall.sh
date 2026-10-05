#!/bin/bash
# Claude Overwatch uninstaller: removes ./overwatch from a folder, keeps everything else.
#   bash uninstall.sh [FOLDER]      (FOLDER defaults to ~/Claude-Workspace)
set -euo pipefail
TARGET="${1:-$HOME/Claude-Workspace}"
[ -f "$TARGET/.vscode/claude-live.zsh" ] || { echo "No ./overwatch found in $TARGET"; exit 1; }
cd "$TARGET"
SETTINGS=.vscode/settings.json; OURS=.vscode/overwatch-settings.json
if [ -f "$SETTINGS" ] && [ -f "$OURS" ] && command -v python3 >/dev/null 2>&1 \
   && { [ "$(uname)" != "Darwin" ] || xcode-select -p >/dev/null 2>&1; }; then
  python3 - "$SETTINGS" "$OURS" <<'PY'
import json, sys
path, ours = sys.argv[1], sys.argv[2]
try: cur = json.load(open(path, encoding='utf-8'))
except Exception: sys.exit("settings.json has comments; remove the ./overwatch keys by hand (listed in " + ours + ")")
for k, v in json.load(open(ours, encoding='utf-8')).items():
    if isinstance(v, dict) and isinstance(cur.get(k), dict):
        for kk in v: cur[k].pop(kk, None)
        if not cur[k]: cur.pop(k)
    else: cur.pop(k, None)
open(path, 'w', encoding='utf-8').write(json.dumps(cur, indent=2, ensure_ascii=False) + '\n')
PY
  echo "  ~ removed the ./overwatch keys from .vscode/settings.json"
elif [ -f "$SETTINGS.before-overwatch" ]; then
  cp "$SETTINGS.before-overwatch" "$SETTINGS"; echo "  ~ restored .vscode/settings.json from the backup"
fi
rm -f .vscode/live.sh .vscode/claude-live.zsh .vscode/zdot/.zshrc .vscode/overwatch-settings.json \
      .vscode/overwatch.conf .vscode/.overwatch-layout "Open Overwatch.command" .claude-live.log .claude-live.steps .claude-live.webt \
      .claude-live.maxlag .claude-live.run .overwatch.alive .overwatch.pos
rmdir .vscode/zdot 2>/dev/null || true
echo "Removed ./overwatch from $TARGET (kept .overwatch-stats.log, .gitignore lines and the settings backup)."
echo "Close and reopen VS Code on the folder to get normal terminals back."
