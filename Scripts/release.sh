#!/bin/bash
# Cuts a release: derives the next version from conventional commits since
# the last tag (feat → minor, fix/other → patch, breaking → major), updates
# the Makefile default, tags, and pushes — CI builds and publishes from there.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -z "$(git status --porcelain)" ] || { echo "Working tree not clean — commit or stash first."; exit 1; }
branch=$(git branch --show-current)
[ "$branch" = "main" ] || { echo "Releases are cut from main (currently on $branch)."; exit 1; }
git fetch -q origin main
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] \
    || { echo "main is not in sync with origin/main — pull/push first."; exit 1; }

last=$(git tag --list 'v*' --sort=-v:refname | head -1)
last=${last:-v0.0.0}
IFS=. read -r major minor patch <<< "${last#v}"

log=$(git log --no-merges --pretty='%s' "$last"..HEAD 2>/dev/null || git log --no-merges --pretty='%s')
[ -n "$log" ] || { echo "No commits since $last — nothing to release."; exit 1; }

bump=patch
if echo "$log" | grep -qE '^[a-z]+(\([^)]*\))?!:' || echo "$log" | grep -q 'BREAKING CHANGE'; then
    bump=major
elif echo "$log" | grep -qE '^feat(\([^)]*\))?: '; then
    bump=minor
fi

case $bump in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
esac
version="$major.$minor.$patch"
tag="v$version"

echo "Releasing $tag ($bump bump from $last)"
echo "— running tests…"
swift test > /dev/null

sed -i '' -E "s/^VERSION  \?= .*/VERSION  ?= $version/" Makefile
if ! git diff --quiet Makefile; then
    git add Makefile
    git commit -q -m "chore: release $tag"
fi
git tag "$tag"
git push -q origin main "$tag"
echo "Pushed $tag — CI is building the release:"
echo "  https://github.com/fwin-git/OutcutShare/releases/tag/$tag"
