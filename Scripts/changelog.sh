#!/bin/bash
# Generates a consumer-oriented changelog from conventional commits:
# feat/fix subjects become plain bullet points, everything else is skipped.
# Usage: Scripts/changelog.sh [<from-ref>] [<to-ref>]
set -euo pipefail

FROM=${1:-}
TO=${2:-HEAD}
if [ -n "$FROM" ]; then
    RANGE="$FROM..$TO"
else
    RANGE="$TO"
fi

capitalize() { awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }'; }

section() {
    local prefix=$1 title=$2 lines
    lines=$(git log --no-merges --pretty='%s' "$RANGE" 2>/dev/null \
        | grep -E "^${prefix}(\([^)]*\))?: " \
        | sed -E "s/^${prefix}(\([^)]*\))?: //" \
        | capitalize \
        | sed 's/^/- /') || true
    if [ -n "$lines" ]; then
        printf '%s\n\n%s\n\n' "$title" "$lines"
    fi
}

section feat "### New"
section fix "### Fixed"
