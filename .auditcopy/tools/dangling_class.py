"""`uv run python -m tools dangling_class` — name the `extends` only an untracked file satisfies.

A tracked script that extends a class declared in an UNTRACKED file is a self-inflicted
broken build that no diff shows, because the half that breaks it is not in version control.
Nothing fails, nothing warns, `tools arch` stays green — it resolves modules and layers, not
`class_name` — and the only symptom is that every composition-root test in the repo reports
the same MISSING SEAM. That happened on 2026-10-04 and went unnoticed for six hours, with
the untracked file's last write at 17:38 and the discovery after 23:30.

It is REPORT-ONLY BY DEFAULT, and that is a deliberate choice rather than a missing step.
The same state is what a session looks like in the middle of a legitimate refactor: it has
written the new file and has not `git add`-ed it yet, having done nothing wrong. A gate that
fired on that would be red for most of every working day, and a permanently-red gate is a
gate people learn to ignore — which is INC-0017, and how guards get deleted. `--fail` opts
into gating for whoever wants it.

## Why it reports only THIS and not "extends something unknown"

The obvious version of this check — every `extends X` that matches no repo `class_name` —
is useless without an allow-list of Godot's built-in classes, and would fire on every
`extends Control` in the tree. So the question is not "is X unknown" but "is X known ONLY
somewhere unversioned". That needs no engine list, and it is exactly the failure mode.

Both loops are `for` over a finite file list from `git ls-files` and `Path.rglob`, so both
terminate on any input.
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

from .common import GAME_DIR, ToolError, fail, info, ok

# `class_name Foo` and `extends Foo`, in that order of usefulness: the first builds the
# registry, the second is what a missing entry breaks.
CLASS_NAME_RE = re.compile(r"^\s*class_name\s+([A-Za-z_]\w*)", re.MULTILINE)
EXTENDS_RE = re.compile(r"^\s*extends\s+([A-Za-z_]\w*)", re.MULTILINE)


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "dangling_class",
        help="report extends/class_name references that only an UNTRACKED file satisfies",
    )
    parser.add_argument(
        "--fail",
        action="store_true",
        help="exit non-zero on any finding (off by default; see the module docstring)",
    )


def _git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args], capture_output=True, text=True, check=False, cwd=GAME_DIR.parent
    )
    return result.stdout if result.returncode == 0 else ""


def _declares(path: Path) -> set[str]:
    """Every `class_name` in one file. One read, one pass, no nesting."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return set()
    return set(CLASS_NAME_RE.findall(text))


def _extends(path: Path) -> set[str]:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return set()
    return set(EXTENDS_RE.findall(text))


def _script_paths(root: Path) -> list[Path]:
    return sorted(root.rglob("*.gd"))


def findings(root: Path) -> tuple[list[tuple[str, str, str]], list[tuple[str, list[str]]]]:
    """(dangling extends, duplicate class_name) as `(referrer, class_name, holder)` triples.

    Split out from `run` with the root injected, so a test can point it at a fixture tree
    and never touch the repository.
    """
    tracked_rel = {
        line for line in _git("ls-files", "--", "game").splitlines() if line.endswith(".gd")
    }
    tracked: list[Path] = []
    untracked: list[Path] = []
    for path in _script_paths(root):
        rel = path.relative_to(root.parent).as_posix()
        (tracked if rel in tracked_rel else untracked).append(path)

    tracked_classes: dict[str, str] = {}
    for path in tracked:
        for name in _declares(path):
            tracked_classes.setdefault(name, path.relative_to(root).as_posix())

    untracked_classes: dict[str, str] = {}
    for path in untracked:
        for name in _declares(path):
            untracked_classes.setdefault(name, path.relative_to(root).as_posix())

    dangling: list[tuple[str, str, str]] = []
    for path in tracked:
        for name in sorted(_extends(path)):
            if name in tracked_classes or name not in untracked_classes:
                continue
            dangling.append((path.relative_to(root).as_posix(), name, untracked_classes[name]))

    seen: dict[str, list[str]] = {}
    for name, where in tracked_classes.items():
        seen.setdefault(name, [where])
    for path in tracked:
        for name in _declares(path):
            where = path.relative_to(root).as_posix()
            if where not in seen.setdefault(name, []):
                seen[name].append(where)
    duplicates = sorted((name, sorted(where)) for name, where in seen.items() if len(where) > 1)
    return dangling, duplicates


def run(args) -> int:
    if not (GAME_DIR / "project.godot").is_file():
        raise ToolError("game/project.godot not found; nothing to inspect")
    dangling, duplicates = findings(GAME_DIR)

    for referrer, name, holder in dangling:
        fail(
            f"{referrer}: extends {name}, which is declared ONLY in UNTRACKED {holder} — the "
            "referrer is version-controlled and the class it needs is not, so this builds "
            "nowhere but your machine and no diff shows it"
        )
    for name, where in duplicates:
        fail(f"class_name {name} is declared by {len(where)} tracked files: {', '.join(where)}")

    if not dangling and not duplicates:
        ok("every tracked extends resolves to a tracked class_name")
        return 0

    info(
        f"{len(dangling)} dangling extends, {len(duplicates)} duplicated class_name. "
        "Advisory by default: if the untracked holder is your own in-flight refactor, add it. "
        "If it is not yours, the file has been abandoned — see BL-0850."
    )
    return 1 if args.fail else 0
