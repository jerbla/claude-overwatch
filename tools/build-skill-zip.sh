#!/bin/bash
# Rebuild dist/overwatch-skill.zip (the file people upload in Claude > Customize > Skills).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../skill"
mkdir -p ../dist
out=../dist/overwatch-skill.zip; tmp=$(mktemp -u "${TMPDIR:-/tmp}/overwatch-skill.XXXXXX").zip
zip -qrX "$tmp" overwatch -x '*.DS_Store'
mv -f "$tmp" "$out"
unzip -l "$out"
