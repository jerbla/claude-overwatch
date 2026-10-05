#!/bin/zsh
# ./overwatch: opens this folder in VS Code, where the live feed starts on its own.
# Double-click from Finder (the first time, right-click > Open if macOS asks).
cd "$(dirname "$0")"
if [ ! -d "/Applications/Visual Studio Code.app" ] && [ ! -d "$HOME/Applications/Visual Studio Code.app" ]; then
  echo "VS Code isn't installed yet. Get it from https://code.visualstudio.com"; exit 1
fi

# First time only: start this folder's window with the file sidebar closed, so the window is
# just the feed. VS Code has no setting for that; it keeps it in its own per-folder storage, so
# we set it there before the window opens. Later, Cmd+B still shows or hides the sidebar as usual.
if [ ! -f .vscode/.overwatch-layout ] && command -v sqlite3 >/dev/null 2>&1; then
  WSS="$HOME/Library/Application Support/Code/User/workspaceStorage"
  URI=$(osascript -l JavaScript -e 'ObjC.import("Foundation"); function run(a){ return $.NSURL.fileURLWithPath(a[0]).absoluteString.js.replace(/\/$/, ""); }' "$PWD" 2>/dev/null)
  DIR=""
  for j in "$WSS"/*/workspace.json(N); do                       # folder opened in VS Code before
    grep -q "\"folder\": \"$URI\"" "$j" 2>/dev/null && { DIR=${j:h}; break; }
  done
  if [ -z "$DIR" ] && [ -n "$URI" ]; then                       # never opened: VS Code's own folder id
    MS=$(osascript -l JavaScript -e 'ObjC.import("Foundation"); function run(a){ var d = $.NSFileManager.defaultManager.attributesOfItemAtPathError(a[0], null); return Math.round(d.objectForKey("NSFileCreationDate").timeIntervalSince1970 * 1000).toString(); }' "$PWD" 2>/dev/null)
    [ -n "$MS" ] && DIR="$WSS/$(md5 -q -s "$PWD$MS")"          # same id VS Code computes: md5(path + creation time in ms)
  fi
  if [ -n "$DIR" ]; then
    mkdir -p "$DIR"
    [ -f "$DIR/workspace.json" ] || printf '{\n  "folder": "%s"\n}' "$URI" > "$DIR/workspace.json"
    sqlite3 "$DIR/state.vscdb" "CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
      INSERT OR REPLACE INTO ItemTable (key, value) VALUES ('workbench.sideBar.hidden', 'true');" 2>/dev/null \
      && : > .vscode/.overwatch-layout
  fi
fi

open -a "Visual Studio Code" "$PWD"
