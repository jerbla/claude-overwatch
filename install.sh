#!/bin/bash
# Claude Overwatch: install ./overwatch into a folder. See README.md.
#   bash install.sh [FOLDER] [TIME_ZONE]     (FOLDER defaults to ~/Claude-Workspace)
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skill/overwatch/install.sh" "$@"
