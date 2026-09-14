#!/usr/bin/env bash
# Run each hook through both prek and pre-commit against its fixtures.
#
# tests/fixtures/<case>/good/ must pass, tests/fixtures/<case>/bad/ must fail.
# The contents of good/ or bad/ become the root of a throwaway git repo and the
# hook runs with --all-files, so hooks that only match root files (uv.lock,
# pyproject.toml) see them. A good case that is "Skipped" counts as a failure,
# unless the case is marked skip-ok.
#
# An optional .setup.sh in good/ or bad/ runs inside the throwaway repo (after
# `git init`, before staging) and is deleted afterwards. Use it for what files
# can't express: exec bits, symlinks, CRLF, big files, merge state, and
# secret-shaped strings that must not be committed to this repo.
#
# Usage: scripts/test.sh [hook-id ...]   (default: all hooks)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

uv run "$root/scripts/sync.py" --check

git_quiet() { git -c user.name=test -c user.email=test@example.com "$@" >/dev/null; }

# hook-id:fixture-case[:skip-ok]
# (plain list, macOS ships bash 3.2 without associative arrays)
cases="
check-added-large-files:check-added-large-files
check-case-conflict:check-case-conflict
check-executables-have-shebangs:check-executables-have-shebangs
check-illegal-windows-names:check-illegal-windows-names:skip-ok
check-json:check-json
check-merge-conflict:check-merge-conflict
check-shebang-scripts-are-executable:check-shebang-scripts-are-executable
check-symlinks:check-symlinks
check-toml:check-toml
check-yaml:check-yaml
debug-statements:debug-statements
detect-private-key:detect-private-key
end-of-file-fixer:end-of-file-fixer
mixed-line-ending:mixed-line-ending
name-tests-test:name-tests-test
requirements-txt-fixer:requirements-txt-fixer
trailing-whitespace:trailing-whitespace
gitleaks:gitleaks
shellcheck:shellcheck
shfmt:shfmt
vale:vale
ruff-check:ruff-check
ruff:ruff-check
ruff-format:ruff-format
taplo-format:taplo-format
taplo-lint:taplo-lint
uv-lock:uv-lock
uv-export:uv-export
uv-ty:python-project
uv-pyrefly:python-project
uv-zuban:python-project
uv-mypy:python-project
uv-basedpyright:python-project
uv-pyright:python-project
uv-test:python-project
"

# Every published hook needs a case, so no hook ships untested.
missing=""
while IFS= read -r id; do
  printf '%s\n' "$cases" | grep -q "^$id:" || missing="$missing $id"
done < <(awk '/^- id: /{print $3}' "$root/.pre-commit-hooks.yaml")
if [ -n "$missing" ]; then
  echo "no fixture case in scripts/test.sh for:$missing" >&2
  exit 1
fi

selected() {
  [ $# -eq 0 ] && return 0
  local want
  for want in "$@"; do [ "$want" = "$hook" ] && return 0; done
  return 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

hooks_repo="$work/hooks"
mkdir "$hooks_repo"
cp "$root/.pre-commit-hooks.yaml" "$hooks_repo/"
# Scripts used by `language: script` hooks resolve relative to the hooks repo.
[ -d "$root/hooks" ] && cp -R "$root/hooks" "$hooks_repo/"
git_quiet -C "$hooks_repo" init -q
git_quiet -C "$hooks_repo" add .
git_quiet -C "$hooks_repo" commit -q -m test

status=0
for runner in prek pre-commit; do
  for entry in $cases; do
    IFS=: read -r hook case_dir flag <<<"$entry"
    selected "$@" || continue
    for kind in good bad; do
      # Fresh copy per run so formatters can't leak changes between runs.
      project="$work/project"
      rm -rf "$project"
      mkdir "$project"
      cp -R "$root/tests/fixtures/$case_dir/$kind/." "$project"
      git_quiet -C "$project" init -q
      if [ -f "$project/.setup.sh" ]; then
        (cd "$project" && bash .setup.sh)
        rm "$project/.setup.sh"
      fi
      # Stage fixtures: --all-files and formatter change detection only see tracked files.
      git_quiet -C "$project" add .

      if (cd "$project" && "$runner" try-repo "$hooks_repo" "$hook" --all-files) >"$work/out" 2>&1; then
        result=passed
        if grep -q Skipped "$work/out"; then
          result=skipped
          [ "$kind" = good ] && [ "${flag:-}" = skip-ok ] && result="passed (skipped, ok)"
        fi
      else
        result=failed
      fi

      expected=passed
      [ "$kind" = bad ] && expected=failed
      case "$result" in
        "$expected"*)
          echo "ok   $runner $hook $case_dir/$kind $result"
          ;;
        *)
          echo "FAIL $runner $hook $case_dir/$kind expected $expected, got $result:"
          sed 's/^/     | /' "$work/out"
          status=1
          ;;
      esac
    done
  done
done
exit "$status"
