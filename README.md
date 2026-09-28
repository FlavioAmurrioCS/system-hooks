# system-hooks

Popular [pre-commit](https://pre-commit.com) hooks, republished as
`language: system` hooks. Instead of pre-commit building an isolated environment
for each tool, these hooks run the tools you already have.

## Why

pre-commit installs its own copy of each tool, pinned by the hook's `rev`. That
copy easily drifts from the version in your `pyproject.toml` development
dependencies, your `mise.toml`, `uv tool` or your IDE, so pre-commit and your
editor disagree. These hooks use the same tool the rest of your setup uses.

The usual workaround is a `repo: local` hook, but then you copy the upstream
settings (`types`, `files`, `pass_filenames`, `require_serial` and so on) into
every project and keep them updated by hand. This repository keeps the upstream
definitions and only swaps how the tool runs.

Some upstream hooks also build the tool from source when installed, for example
the Go-based `vale`, `actionlint` and `dockerfmt`. mise installs prebuilt
binaries, which is much faster.

## Hook variants

Every hook comes in two variants:

- `<id>` runs the tool from your `PATH`: your activated virtual environment,
  mise when it's activated in your shell, or a system install. For example, with
  `ruff` as a development dependency and the virtual environment active,
  `ruff-check` uses that `ruff`.
- `mise-<id>` runs the tool through [`mise exec`](https://mise.jdx.dev), for
  when mise isn't activated in your shell. It uses the version pinned in your
  project's `mise.toml`, falling back to your global mise configuration or the
  newest release, and installs it on demand.

Plain hooks need the tool on `PATH`, and `mise-` hooks need mise installed. A
few hooks call other programs too: `ty` runs `uv`, `vale-commit-msg` runs `sh`,
and the `oxfmt` hooks need `node`.

If a plain hook fails with `command not found`, the tool isn't on `PATH`. This
often happens when you commit from an IDE or git GUI without the virtual
environment active. Use the `mise-` variant instead.

## Usage

```yaml
repos:
  - repo: https://github.com/FlavioAmurrioCS/system-hooks
    rev: v2026.09.28
    hooks:
      - id: ruff-check
      - id: ruff-format
      - id: mise-shellcheck
```

Each release gets a date tag in the form `YYYY.MM.DD`, and
`pre-commit autoupdate` picks up new ones. A release pins the hook definitions,
not tool versions: those come from your environment or `mise.toml`.

## CI

These hooks don't work on [pre-commit.ci](https://pre-commit.ci): it runs hooks
without network access and installs nothing for `language: system` hooks. Skip
them there with `ci: skip: [...]`, or run pre-commit in GitHub Actions instead.
Install the tools first, for example with
[`jdx/mise-action`](https://github.com/jdx/mise-action), or use the `mise-`
variants, which only need mise.

## Available hooks

| Tool | Hook ids | Upstream |
| --- | --- | --- |
| `ruff` | `ruff-check`, `ruff-format` | [astral-sh/ruff-pre-commit](https://github.com/astral-sh/ruff-pre-commit) |
| `ty` | `ty` | [astral-sh/ty-pre-commit](https://github.com/astral-sh/ty-pre-commit) |
| `oxfmt` | `oxfmt`, `oxfmt-yaml`, `oxfmt-json` | [oxc-project/mirrors-oxfmt](https://github.com/oxc-project/mirrors-oxfmt) |
| `oxlint` | `oxlint` | [oxc-project/mirrors-oxlint](https://github.com/oxc-project/mirrors-oxlint) |
| `actionlint` | `actionlint` | [rhysd/actionlint](https://github.com/rhysd/actionlint) |
| `zizmor` | `zizmor` | [zizmorcore/zizmor-pre-commit](https://github.com/zizmorcore/zizmor-pre-commit) |
| `shfmt` | `shfmt` | [scop/pre-commit-shfmt](https://github.com/scop/pre-commit-shfmt) |
| `bash` | `bash-syntax-check` | local |
| `shellcheck` | `shellcheck` | [shellcheck-py/shellcheck-py](https://github.com/shellcheck-py/shellcheck-py) |
| `shuck` | `shuck` | [ewhauser/shuck](https://github.com/ewhauser/shuck) |
| `dockerfmt` | `dockerfmt` | [reteps/dockerfmt](https://github.com/reteps/dockerfmt) |
| `hadolint` | `hadolint` | [hadolint/hadolint](https://github.com/hadolint/hadolint) |
| `rumdl` | `rumdl-fmt`, `rumdl-check` | [rvben/rumdl-pre-commit](https://github.com/rvben/rumdl-pre-commit) |
| `mado` | `mado` | [akiomik/mado](https://github.com/akiomik/mado) |
| `vale` | `vale`, `vale-commit-msg` | [vale-cli/vale](https://github.com/vale-cli/vale) |
| `tombi` | `tombi-format`, `tombi-lint` | [tombi-toml/tombi-pre-commit](https://github.com/tombi-toml/tombi-pre-commit) |
| `ryl` | `ryl`, `ryl-markdown` | [owenlamont/ryl-pre-commit](https://github.com/owenlamont/ryl-pre-commit) |

Each id also has a `mise-` variant. See
[`.pre-commit-hooks.yaml`](.pre-commit-hooks.yaml) for the full definitions.

## Notes

- Override `args`, `files`, `types` and other options in your configuration as
  usual.
- A few hooks change upstream defaults: `ruff-check`, `ryl` and `ryl-markdown`
  run with `--fix`, and the `tombi` hooks run with `--offline`, so they only use
  schemas that `tombi` already cached.
- Some hooks overlap. For example, `ruff-format` and `rumdl-fmt` both format
  Markdown, and `ryl` fixes YAML files that `oxfmt-yaml` also formats. Pick one
  per file type.

## Maintaining

`.pre-commit-config.yaml` in this repository is the source list, not the hook
setup for this repository. Each entry names an upstream repository and version,
the hooks to include, any overrides, and a custom `mise_tools` key listing what
`mise exec` should install.

To regenerate `.pre-commit-hooks.yaml`, run:

```sh
./main.py
```

Don't edit `.pre-commit-hooks.yaml` by hand.
