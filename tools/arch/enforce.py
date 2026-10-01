"""Enforce the module boundaries defined in `rules.py`."""

from __future__ import annotations

import re
from pathlib import Path

from ..common import GAME_DIR, SRC_DIR, fail, ok, warn
from . import rules

SOURCE_SUFFIXES = (".gd", ".tscn", ".tres")
RES_RE = re.compile(r'res://[^"\'\s)]+')
CLASS_RE = re.compile(r"^\s*class_name\s+([A-Za-z_]\w*)", re.MULTILINE)
EXTENDS_RE = re.compile(r"^\s*extends\s+([A-Za-z_]\w*)", re.MULTILINE)
FUNC_RE = re.compile(r"^func\s+([A-Za-z_]\w*)", re.MULTILINE)


def register(subparsers) -> None:
    subparsers.add_parser("arch", help="enforce module boundaries")


def unit_of(rel: str) -> str | None:
    """Map a game-relative path to its architectural unit, or None if irrelevant."""
    parts = Path(rel).parts
    if not parts:
        return None
    if parts[0] == "scenes":
        return "app"
    if parts[0] != "src" or len(parts) < 2:
        return None
    head = parts[1]
    if head == "modules":
        return f"modules/{parts[2]}" if len(parts) >= 3 else None
    if head in rules.LAYER_DEPS:
        return head
    return None


def is_facade(rel: str) -> bool:
    parts = Path(rel).parts
    return (
        len(parts) == 4
        and parts[0] == "src"
        and parts[1] == "modules"
        and parts[3] == rules.FACADE_FILENAME
    )


def _iter_sources():
    for suffix in SOURCE_SUFFIXES:
        for path in GAME_DIR.rglob(f"*{suffix}"):
            if ".godot" in path.parts:
                continue
            yield path


def _class_index(files) -> dict[str, tuple[str, str | None, bool]]:
    index: dict[str, tuple[str, str | None, bool]] = {}
    for path in files:
        if path.suffix != ".gd":
            continue
        rel = path.relative_to(GAME_DIR).as_posix()
        text = path.read_text(encoding="utf-8", errors="replace")
        for name in CLASS_RE.findall(text):
            index[name] = (rel, unit_of(rel), is_facade(rel))
    return index


def _references(text):
    for match in RES_RE.finditer(text):
        yield text.count("\n", 0, match.start()) + 1, match.group(0)
    for match in EXTENDS_RE.finditer(text):
        yield text.count("\n", 0, match.start()) + 1, match.group(1)


def _resolve(ref: str, classes) -> tuple[str | None, bool]:
    if ref.startswith("res://"):
        rel = ref[len("res://") :]
        return unit_of(rel), is_facade(rel)
    entry = classes.get(ref)
    if entry is None:
        return None, False
    _, unit, facade = entry
    return unit, facade


def _violation(source: str | None, target: str | None, facade: bool, registry) -> str | None:
    if source is None or target is None or source == target:
        return None
    if source == "app":
        return None
    if target in rules.PRIVATE_UNITS:
        return f"'{target}/' is private and may only be referenced by app/"
    if source in rules.LAYER_DEPS:
        allowed = rules.LAYER_DEPS[source]
        if "*" in allowed or target in allowed:
            return None
        return f"'{source}/' must not depend on '{target}/'"
    if source.startswith("modules/"):
        name = source.split("/", 1)[1]
        if target in ("core", "contracts"):
            return None
        if target.startswith("modules/"):
            dep = target.split("/", 1)[1]
            if dep not in registry.get(name, []):
                return (
                    f"undeclared dependency '{name}' -> '{dep}'; "
                    "register it via `tools new_module` or registry.json"
                )
            if not facade:
                return f"'{name}' may reference '{dep}' only through modules/{dep}/api.gd"
            return None
        return f"module '{name}' must not depend on '{target}/'"
    return None


def _find_cycle(registry) -> list[str] | None:
    color: dict[str, int] = {}
    stack: list[str] = []

    def visit(node: str) -> list[str] | None:
        color[node] = 1
        stack.append(node)
        for dep in registry.get(node, []):
            if dep not in registry:
                continue
            state = color.get(dep, 0)
            if state == 1:
                return stack[stack.index(dep) :] + [dep]
            if state == 0:
                found = visit(dep)
                if found:
                    return found
        stack.pop()
        color[node] = 2
        return None

    for node in registry:
        if color.get(node, 0) == 0:
            found = visit(node)
            if found:
                return found
    return None


def _structural_checks(files) -> tuple[list[str], list[str]]:
    """SOLID structural proxies: facade surface (ISP) and line budget (SRP)."""
    violations: list[str] = []
    warnings: list[str] = []
    for path in files:
        if path.suffix != ".gd":
            continue
        rel = path.relative_to(GAME_DIR).as_posix()
        text = path.read_text(encoding="utf-8", errors="replace")
        if is_facade(rel):
            public = [name for name in FUNC_RE.findall(text) if not name.startswith("_")]
            if len(public) > rules.MAX_FACADE_PUBLIC_METHODS:
                violations.append(
                    f"{rel}: facade exposes {len(public)} public methods "
                    f"(max {rules.MAX_FACADE_PUBLIC_METHODS}); split the interface (ISP)"
                )
        lines = text.count("\n") + 1
        if lines > rules.LINE_BUDGET:
            warnings.append(f"{rel}: {lines} lines exceeds budget {rules.LINE_BUDGET} (SRP signal)")
    return violations, warnings


def run(args) -> int:
    if not SRC_DIR.is_dir():
        warn("game/src not found; nothing to check")
        return 0
    files = list(_iter_sources())
    classes = _class_index(files)
    registry = rules.load_registry()
    violations: list[str] = []
    for path in files:
        rel = path.relative_to(GAME_DIR).as_posix()
        source = unit_of(rel)
        if source is None:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for line, ref in _references(text):
            target, facade = _resolve(ref, classes)
            reason = _violation(source, target, facade, registry)
            if reason:
                violations.append(f"{rel}:{line}: {reason}")
    cycle = _find_cycle(registry)
    if cycle:
        violations.append("module dependency cycle: " + " -> ".join(cycle))
    structural, warnings = _structural_checks(files)
    violations.extend(structural)
    for warning in warnings:
        warn(warning)
    if violations:
        for violation in violations:
            fail(violation)
        return 1
    ok(f"boundaries ok ({len(files)} files, {len(registry)} modules)")
    return 0
