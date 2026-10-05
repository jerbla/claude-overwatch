#!/bin/bash
# Claude Overwatch: remove ./overwatch from a folder. See README.md.
#   bash uninstall.sh [FOLDER]     (FOLDER defaults to ~/Claude-Workspace)
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skill/overwatch/uninstall.sh" "$@"
