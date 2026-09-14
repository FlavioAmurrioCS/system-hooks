# system-hooks

[prek](https://github.com/j178/prek) / [pre-commit](https://pre-commit.com) hooks
that run the tools already on your `PATH` (managed by [mise](https://mise.jdx.dev)).

Each hook is a copy of the upstream hook (same `id`, `entry`, `args`, `types`,
`files`, `stages`, `require_serial`, …) with `language: system`. So:

- the hook uses the **same tool version as your editor and CLI** (from `mise.toml`)
- prek/pre-commit **never installs, compiles or downloads** the tool, so it works
  behind Artifactory

## Usage

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/<you>/system-hooks
    rev: 2026.9.14  # date-based, see Versioning
    hooks:
      - id: gitleaks
      - id: end-of-file-fixer
      - id: trailing-whitespace
      - id: ruff-check
        args: [--fix]
      - id: ruff-format
      - id: shellcheck
      - id: shfmt
```

```toml
# mise.toml  (this is where the tool versions live)
[tools]
"pipx:pre-commit-hooks" = "6.0.0"
gitleaks = "8.30.1"
ruff = "0.16.7"
shellcheck = "0.11.0"
shfmt = "3.14.1"
```

Migrating from upstream: only `repo:` and `rev:` change. Hook ids stay the same.

### Make sure git hooks can find the tools

Git hooks started from an IDE or GUI git client don't load your shell rc, so
`mise activate` isn't enough there. Add mise's shims to `PATH` in a login profile
(e.g. `~/.zprofile`):

```sh
export PATH="$HOME/.local/share/mise/shims:$PATH"
```

If a tool is missing, the hook fails (pre-commit: ``Executable `ruff` not found``;
prek: `Failed to run hook ... No such file or directory`). Fix it with
`mise install`.

## Available hooks

| id | source | tools needed on PATH |
| --- | --- | --- |
| `check-added-large-files`, `check-case-conflict`, `check-executables-have-shebangs`, `check-illegal-windows-names`, `check-json`, `check-merge-conflict`, `check-shebang-scripts-are-executable`, `check-symlinks`, `check-toml`, `check-yaml`, `debug-statements`, `detect-private-key`, `end-of-file-fixer`, `mixed-line-ending`, `name-tests-test`, `requirements-txt-fixer`, `trailing-whitespace` | [pre-commit/pre-commit-hooks](https://github.com/pre-commit/pre-commit-hooks) | `pipx:pre-commit-hooks` |
| `gitleaks` | [gitleaks/gitleaks](https://github.com/gitleaks/gitleaks) | `gitleaks` |
| `shellcheck` | [shellcheck-py/shellcheck-py](https://github.com/shellcheck-py/shellcheck-py) | `shellcheck` |
| `shfmt` | [scop/pre-commit-shfmt](https://github.com/scop/pre-commit-shfmt) | `shfmt` |
| `vale` | [errata-ai/vale](https://github.com/errata-ai/vale) | `vale` |
| `ruff-check`, `ruff-format`, `ruff` | [astral-sh/ruff-pre-commit](https://github.com/astral-sh/ruff-pre-commit) | `ruff` |
| `taplo-format`, `taplo-lint` | [ComPWA/mirrors-taplo](https://github.com/ComPWA/mirrors-taplo) | `taplo` |
| `uv-lock`, `uv-export` | [astral-sh/uv-pre-commit](https://github.com/astral-sh/uv-pre-commit) | `uv` |
| `uv-ty`, `uv-pyrefly`, `uv-zuban`, `uv-mypy`, `uv-basedpyright`, `uv-pyright`, `uv-test` | local | `uv` |

Notes:

- **pre-commit-hooks**: every hook is a console script of the
  `pre-commit-hooks` package, so `"pipx:pre-commit-hooks"` in mise provides them
  all. This works with both prek and pre-commit; prek's `repo: builtin` only
  works with prek, and its automatic fast path still builds a Python venv (pip
  through Artifactory). `check-illegal-windows-names` keeps upstream's
  `language: fail` (it only matches bad filenames and needs no tool).
- **shfmt**: put style options in `.editorconfig` instead of `args`; shfmt reads
  it when no style flags are passed (`indent_size = 2` + `switch_case_indent = true`
  is `shfmt -i 2 -ci`).
- **vale**: runs on all text files like upstream; narrow it per project with
  `files: \.md$`. Styles must already be synced (`vale sync`).
- **taplo-lint** runs with `args: []`. Upstream's `--default-schema-catalogs`
  downloads the schemastore catalog on every run, which is blocked behind
  Artifactory and currently fails to parse with taplo 0.10.0. Add it back per
  project with `args: [--default-schema-catalogs]` if you want it.
- **local `uv-*` hooks** run the checker from the project's own environment
  (`uv run --group=type-checkers ...`; `uv-mypy` and `uv-test` use the default
  `dev` group). The project must define those dependency groups, as projects
  generated from python-cookie do.

## How this repo works

| file | role |
| --- | --- |
| `upstream/.pre-commit-config.yaml` | which upstream hooks to mirror (and `repo: local` hooks owned here) |
| `.pre-commit-hooks.yaml` | **generated** hook definitions that consumers use |
| `self-lint.yaml` | which hooks lint this repo |
| `.pre-commit-config.yaml` | **generated** from `self-lint.yaml`: this repo's own hooks, as `repo: local` copies of the current definitions |
| `scripts/sync.py` | regenerates both generated files (`--check` for CI) |
| `scripts/test.sh` | runs every hook through prek and pre-commit against `tests/fixtures/` |

`upstream/.pre-commit-config.yaml` lives in `upstream/`, not the repo root, and
`.prekignore` lists `upstream/`. Without that, prek discovers the manifest as a
nested project and runs every mirrored hook against this repo. Never edit the
generated files by hand.

| task | what it does |
| --- | --- |
| `mise run sync` | regenerate `.pre-commit-hooks.yaml` and `.pre-commit-config.yaml` |
| `mise run update` | `pre-commit autoupdate` on the upstream config, sync, test |
| `mise run test` | check generated files are in sync, run all hook fixtures |
| `mise run lint` | lint this repo with its own hooks (`prek run --all-files`) |
| `mise run release` | check, test and create today's date tag (see [Versioning and releases](#versioning-and-releases)) |

## Adding / updating a hook

- **Add a hook:** add the repo/hook id to `upstream/.pre-commit-config.yaml`
  (or write it under `repo: local` for a hook this repo owns), add its tool to
  `mise.toml`, run `mise run sync`, add fixtures (below), then run
  `scripts/test.sh <hook-id>`.
- **Update revs:** `mise run update` (`--freeze` hashes work too). Renovate's
  pre-commit manager can also bump that file.
- **Customize a hook:** set hook-level keys in the upstream config (see
  [Overrides, ids and local hooks](#overrides-ids-and-local-hooks)).
- **Lint this repo with a hook:** add its id to `self-lint.yaml` and run
  `mise run sync`.

### Overrides, ids and local hooks

- **Overrides are published.** A hook-level key set on an upstream hook (`args`,
  `files`, `exclude`, `types`, `stages`, `name`, …) replaces upstream's value in
  `.pre-commit-hooks.yaml`. Exceptions: `language` always becomes `system`
  (except `fail`); `additional_dependencies`, `language_version` and
  `minimum_pre_commit_version` are dropped; and `id` can't change, because it's
  how the upstream hook is looked up.
- **Ids and aliases are unique.** Every published `id` and `alias` must be unique
  across all hooks, upstream and local, since `prek run <name>` selects by
  either. `mise run sync` fails on a collision; prek's own manifest check doesn't
  catch duplicates.
- **No renames.** Listing the same upstream id twice fails too. To ship a variant,
  copy the hook under `repo: local` with a new id. The copy doesn't follow
  upstream changes, so check it when `mise run update` bumps that upstream:

  ```yaml
  - repo: local
    hooks:
      - id: ruff-check-unsafe
        name: ruff check (unsafe fixes)
        entry: ruff check --force-exclude
        language: system
        types_or: [python, pyi, jupyter]
        args: [--fix, --unsafe-fixes]
        require_serial: true
  ```

- **Local hooks are published as written.** They need `id`, `name`, `entry` and
  `language`, and `language` must be `system`, `script` or `fail`. A `script`
  hook runs a script shipped in this repo: put it in `hooks/<id>.sh` (executable,
  with a shebang) and set `entry: hooks/<id>.sh`. The path is relative to this
  repo, which prek/pre-commit clone for consumers:

  ```yaml
  - repo: local
    hooks:
      - id: no-todo
        name: no TODO comments
        entry: hooks/no-todo.sh
        language: script
        types: [text]
  ```

- **Every published hook needs a test.** `scripts/test.sh` fails if a hook id in
  `.pre-commit-hooks.yaml` has no fixture case.
- **Repo-only hooks in `self-lint.yaml`** (entries with `entry`/`language`) must
  not reuse a published hook's id.

Release with `mise run release` once the change is on main (see
[Versioning and releases](#versioning-and-releases)).

### Fixtures

`tests/fixtures/<case>/good/` must pass and `bad/` must fail; map
`<hook-id>:<case>` in `scripts/test.sh`. Each folder becomes the root of a
throwaway git repo and the hook runs with `--all-files`.

- A good case that is "Skipped" fails the test, unless mapped as
  `<hook-id>:<case>:skip-ok` (for hooks that only match bad files).
- An optional `.setup.sh` runs inside the throwaway repo before staging, for
  things files can't express: exec bits, symlinks, CRLF, large files, merge
  state, index-only paths, and secret-shaped strings that must never be
  committed here.

On the work network, point git at your mirror so `sync` and `autoupdate` can
reach upstreams:

```sh
git config --global url."https://artifactory.example.com/api/vcs/github/".insteadOf "https://github.com/"
```

## Versioning and releases

Releases are git tags named after the UTC date they are cut, **`YYYY.M.D`**
with no zero padding: `2026.9.14`, not `2026.09.14`. A second release on the
same day gets a counter: `2026.9.14.1`, `2026.9.14.2`.

- **What a version means:** a snapshot of `.pre-commit-hooks.yaml`, the hook
  definitions. It says nothing about tool versions (those live in each
  project's `mise.toml`), and a date can't signal a breaking change.
- **When to release:** when `.pre-commit-hooks.yaml` changes on main (a new
  hook, an upstream rev bump that changed a definition, a changed override).
  Changes to tests, docs or `self-lint.yaml` alone don't need a release, and
  `mise run release` refuses to tag them unless you pass `--force`.
- **Breaking changes:** removing or renaming a hook id, or changing its
  `entry`/`args`/`files` so results change, breaks consumers when they update.
  Avoid removing ids (keep an alias, like upstream ruff's `ruff` hook). When it
  can't be avoided, say so in the GitHub release notes for that tag.
- **Tags are immutable:** never move or delete a pushed tag; cut a new one.
  prek and pre-commit cache hook repos by `rev`, so a moved tag never reaches
  anyone who already fetched it.

### Why this format

- `pre-commit autoupdate` takes the newest tag on the default branch, whatever
  its format.
- `prek update` sorts tags by creation time. Only for tags created in the same
  second does it compare versions, and then only tags that are valid semver.
  `2026.9.14` is valid semver; `2026.09.14` isn't (leading zeros aren't
  allowed). With tags created at different times, both tools picked the newest
  tag for every format tested, including same-day `.1` releases.
- No `-1` suffixes (`2026.9.14-1`): semver tools read that as a pre-release of
  `2026.9.14` and sort it *before* the base tag.
- Plain `git tag` sorts as text (`2026.10.1` before `2026.9.2`). Use
  `git tag --sort=-v:refname` to list newest first.

### Cutting a release

```sh
mise run release -- --dry-run --no-test   # preview the tag and its message
mise run release                          # check, test, create the annotated tag
git push origin <tag>
gh release create <tag> --generate-notes  # optional GitHub release with notes
```

`mise run release` refuses to tag unless:

- you're on `main` with a clean working tree, and HEAD isn't already tagged
- the generated files are in sync
- `.pre-commit-hooks.yaml` changed since the previous tag (`--force` overrides)
- `scripts/test.sh` passes (`--no-test` skips it)

It fetches tags from `origin` first, so a date already used from another
machine gets the next counter. The tag message lists the upstream revs the
hooks were copied from.

### For consumers

- Pin `rev: 2026.9.14`. `pre-commit autoupdate` and `prek update` both move to
  the newest date tag; add `--freeze` to pin the commit hash instead.
- `prek update --cooldown-days 7` only takes tags that are at least 7 days old.
