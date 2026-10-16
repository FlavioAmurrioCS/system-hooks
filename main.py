#!/usr/bin/env uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#     "persistent-cache-decorator>=0.1.11",
#     "ruamel-yaml>=0.19.1",
# ]
# ///
from __future__ import annotations

import datetime as dt
import shlex
import subprocess
import tempfile
from copy import deepcopy
from functools import cached_property
from io import StringIO
from string import Template
from textwrap import dedent
from typing import TYPE_CHECKING
from typing import NotRequired
from typing import TypeVar

from persistent_cache.decorators import json_cache
from ruamel.yaml import YAML

T = TypeVar("T")

if TYPE_CHECKING:
    from typing import TypedDict

    from ruamel.yaml import YAML

    class PreCommitConfigRepoHook(TypedDict):
        id: str
        entry: str
        additional_dependencies: NotRequired[list[str]]
        language_version: NotRequired[str]
        language: str
        mise_tools: NotRequired[list[str]]

    class PreCommitConfigRepo(TypedDict):
        repo: str
        rev: NotRequired[str]
        hooks: list[PreCommitConfigRepoHook]
        mise_tools: NotRequired[list[str]]

    class PreCommitConfig(TypedDict):
        repos: list[PreCommitConfigRepo]


class Lazy:
    @cached_property
    def yaml(self) -> YAML:
        from ruamel.yaml import YAML

        yaml = YAML(typ="rt")
        yaml.indent(mapping=2, sequence=4, offset=2)
        # yaml.preserve_quotes = True
        yaml.preserve_quotes = False
        yaml.width = 4096

        return yaml


LAZY = Lazy()

region_start = Template("""\
################################################################################
# region: ${title}
################################################################################\n""")
region_end = Template("""
################################################################################
# endregion: ${title}
################################################################################\n\n""")
UPDATED_PREFIX = "# Updated: "
OUTPUT_FILE = ".pre-commit-hooks.yaml"


def strip_trailing_comments(node: object) -> None:
    """Drop comment lines that follow a node, keeping same-line (EOL) comments."""
    from ruamel.yaml.comments import CommentedMap
    from ruamel.yaml.comments import CommentedSeq

    if isinstance(node, (CommentedMap, CommentedSeq)):
        for tokens in node.ca.items.values():
            for i, tok in enumerate(tokens):
                if tok is None or isinstance(tok, list):
                    continue
                first = tok.value.split("\n", 1)[0]
                if first.strip():
                    tok.value = first + "\n"  # real EOL comment: keep just that line
                else:
                    tokens[i] = None  # only trailing lines: drop
        node.ca.end = None  # comments after the last item of the collection
        for child in node.values() if isinstance(node, CommentedMap) else node:
            strip_trailing_comments(child)


@json_cache(days=1)
def fetch_remote_file(*, url: str, rev: str, path: str = ".pre-commit-hooks.yaml") -> str:
    with tempfile.TemporaryDirectory() as d:

        def git(*args: str) -> str:
            return subprocess.run(  # noqa: S603
                ("git", "-C", d, *args),  # noqa: S607
                check=True,
                stdout=subprocess.PIPE,
                text=True,
            ).stdout

        git("init", "-q")
        # A named remote is needed so the blob can be lazily fetched (partial clone)
        git("remote", "add", "origin", url)
        git("fetch", "-q", "--depth", "1", "--filter=blob:none", "origin", rev)
        return git("show", f"FETCH_HEAD:{path}")


def without_updated_line(text: str) -> list[str]:
    """Lines to compare between runs: no date line, and no indentation formatters change."""
    return [line.strip() for line in text.splitlines() if not line.startswith(UPDATED_PREFIX)]


def updated_date(new_text: str) -> str:
    """Keep the previous date unless the hooks or sources changed."""
    try:
        with open(OUTPUT_FILE) as f:
            old_text = f.read()
    except FileNotFoundError:
        old_text = ""
    old_dates = [line for line in old_text.splitlines() if line.startswith(UPDATED_PREFIX)]
    if old_dates and without_updated_line(old_text) == without_updated_line(new_text):
        return old_dates[0].removeprefix(UPDATED_PREFIX)
    return dt.datetime.now(dt.UTC).date().isoformat()


def main() -> None:  # noqa: PLR0915
    yaml = LAZY.yaml
    with open(".pre-commit-config.yaml") as f:
        pre_commit_config: PreCommitConfig = yaml.load(f)

    buf = StringIO()
    buf.write(
        dedent("""\
    # yaml-language-server: $schema=https://www.schemastore.org/pre-commit-hooks.json
    ---
    """)
    )
    sources: list[str] = []
    for pre_commit_config_repo in sorted(
        pre_commit_config["repos"], key=lambda x: x["repo"].lower()
    ):
        global_mise_tools = pre_commit_config_repo.pop("mise_tools", None) or []
        pre_commit_hooks: list[PreCommitConfigRepoHook] = []
        if "rev" not in pre_commit_config_repo:
            for local_hook in sorted(
                pre_commit_config_repo["hooks"], key=lambda x: x["id"].lower()
            ):
                mise_tools = local_hook.pop("mise_tools", None) or global_mise_tools
                local_hook["language"] = "system"
                local_hook.pop("additional_dependencies", None)
                local_hook.pop("language_version", None)
                pre_commit_hooks.append(local_hook)

                hook = deepcopy(local_hook)
                hook["id"] = f"mise-{hook['id']}"
                if not mise_tools:
                    hook["entry"] = f"mise exec --no-deps -- {hook['entry']}"
                else:
                    line = " ".join(shlex.quote(x) for x in mise_tools)
                    hook["entry"] = f"mise exec {line} -- {hook['entry']}"
                pre_commit_hooks.append(hook)
            title = "local"
        else:
            upstream_pre_commit_hooks_text = fetch_remote_file(
                url=pre_commit_config_repo["repo"], rev=pre_commit_config_repo["rev"]
            )
            upstream_pre_commit_hooks: list[PreCommitConfigRepoHook] = yaml.load(
                upstream_pre_commit_hooks_text
            )
            title = pre_commit_config_repo["repo"].removesuffix(".git").rstrip("/")
            sources.append(f"{title} {pre_commit_config_repo['rev']}")
            upstream_pre_commit_hooks_map = {hook["id"]: hook for hook in upstream_pre_commit_hooks}
            for pre_commit_config_repo_hook in sorted(
                pre_commit_config_repo["hooks"], key=lambda x: x["id"].lower()
            ):
                if pre_commit_config_repo_hook["id"] not in upstream_pre_commit_hooks_map:
                    # Hook doesnt exist upstream
                    continue
                upstream_pre_commit_hooks_hook = upstream_pre_commit_hooks_map[
                    pre_commit_config_repo_hook["id"]
                ]
                # Here is where we combining
                upstream_pre_commit_hooks_hook.update(pre_commit_config_repo_hook)
                upstream_pre_commit_hooks_hook["language"] = "system"
                upstream_pre_commit_hooks_hook.pop("additional_dependencies", None)
                upstream_pre_commit_hooks_hook.pop("language_version", None)
                strip_trailing_comments(upstream_pre_commit_hooks_hook)
                mise_tools = (
                    upstream_pre_commit_hooks_hook.pop("mise_tools", None) or global_mise_tools
                )
                pre_commit_hooks.append(upstream_pre_commit_hooks_hook)

                hook = deepcopy(upstream_pre_commit_hooks_hook)
                hook["id"] = f"mise-{hook['id']}"
                if not mise_tools:
                    hook["entry"] = f"mise exec --no-deps -- {hook['entry']}"
                else:
                    line = " ".join(shlex.quote(x) for x in mise_tools)
                    hook["entry"] = f"mise exec {line} -- {hook['entry']}"
                pre_commit_hooks.append(hook)

        buf.write(region_start.safe_substitute(title=title))
        b = StringIO()
        yaml.dump(pre_commit_hooks, b)
        buf.write(dedent(b.getvalue().rstrip()))
        pre_commit_hooks.clear()
        buf.write(region_end.safe_substitute(title=title))

    buf.write("#" * 80 + "\n# Sources\n")
    buf.writelines(f"#   {source}\n" for source in sources)
    buf.write("#" * 80 + "\n")

    text = buf.getvalue().rstrip() + "\n"
    header, sep, body = text.partition("---\n")
    text = f"{header}{sep}{UPDATED_PREFIX}{updated_date(text)}\n{body}"
    with open(OUTPUT_FILE, "w") as f:
        f.write(text)


if __name__ == "__main__":
    main()
