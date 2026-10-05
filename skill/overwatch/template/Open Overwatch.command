#!/bin/zsh
# ./overwatch: opens this folder in VS Code, where the live feed starts on its own.
# Double-click from Finder (the first time, right-click > Open if macOS asks).
cd "$(dirname "$0")"
if [ ! -d "/Applications/Visual Studio Code.app" ] && [ ! -d "$HOME/Applications/Visual Studio Code.app" ]; then
  echo "VS Code isn't installed yet. Get it from https://code.visualstudio.com"; exit 1
fi
open -a "Visual Studio Code" "$PWD"
