#!/usr/bin/env bash
# Create a date-based release tag: YYYY.M.D (UTC date, no zero padding), or
# YYYY.M.D.N for the Nth extra release on the same day. See README "Versioning".
#
# Refuses to tag unless: on main, the tree is clean, HEAD isn't already tagged,
# the generated files are in sync, the hook definitions changed since the last
# tag (override with --force), and the tests pass (skip with --no-test).
# Pushing the tag is left to you.
#
# Usage: scripts/release.sh [--dry-run] [--force] [--no-test]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

dry_run=false
force=false
run_tests=true
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    --force) force=true ;;
    --no-test) run_tests=false ;;
    -h | --help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

die() {
  echo "release: $*" >&2
  exit 1
}

git rev-parse --verify -q HEAD >/dev/null || die "no commits yet"

branch=$(git symbolic-ref --short -q HEAD || true)
[ "$branch" = main ] || die "releases are tagged from main (on '${branch:-detached HEAD}')"

[ -z "$(git status --porcelain)" ] || die "working tree is not clean; commit or stash first"

# Pick up tags created elsewhere so a date isn't reused.
if git remote get-url origin >/dev/null 2>&1; then
  git fetch --quiet --tags origin
fi

if existing=$(git describe --tags --exact-match HEAD 2>/dev/null); then
  die "HEAD is already released as $existing"
fi

previous=$(git describe --tags --abbrev=0 HEAD 2>/dev/null || true)
if [ -n "$previous" ] && git diff --quiet "$previous" HEAD -- .pre-commit-hooks.yaml; then
  if [ "$force" = true ]; then
    echo "note: .pre-commit-hooks.yaml is unchanged since $previous (--force)"
  else
    die ".pre-commit-hooks.yaml is unchanged since $previous, so consumers get nothing new (--force to tag anyway)"
  fi
fi

uv run scripts/sync.py --check >/dev/null || die "generated files are out of date; run: mise run sync"

if [ "$run_tests" = true ]; then
  scripts/test.sh || die "tests failed"
fi

# One `date` call so the parts can't straddle midnight. 10# drops the zero
# padding (and stops bash reading 08/09 as invalid octal).
read -r year month day <<<"$(date -u '+%Y %m %d')"
base="$year.$((10#$month)).$((10#$day))"

tag=$base
n=0
while git rev-parse -q --verify "refs/tags/$tag" >/dev/null; do
  n=$((n + 1))
  tag="$base.$n"
done

message="system-hooks $tag

Upstream hook sources:
$(awk '/^ *- repo: /{repo=$3} /^ *rev: /{print "- " repo " " $2}' upstream/.pre-commit-config.yaml)"

if [ "$dry_run" = true ]; then
  echo "would tag $tag${previous:+ (previous: $previous)}"
  printf '%s\n' "$message"
  exit 0
fi

git tag -a "$tag" -m "$message"
echo "tagged $tag${previous:+ (previous: $previous)}"
echo "publish with: git push origin $tag"
