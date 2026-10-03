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
# Every facade in this repo declares `static func`, so the optional `static`
# prefix is required — without it the ISP cap silently counted zero methods on
# all twelve facades and never fired.
FUNC_RE = re.compile(r"^(?:static\s+)?func\s+([A-Za-z_]\w*)", re.MULTILINE)
# A bare class reference: the name used as a word, not part of a longer identifier.
# `\b` after the name keeps `BodyTrainingX` from matching `BodyTraining`.
WORD_RE = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\b")
# `# comment` and quoted literals are stripped before scanning for bare class
# references, so prose and user-facing strings never count as dependencies.
COMMENT_RE = re.compile(r"#.*$", re.MULTILINE)
STRING_RE = re.compile(r'"[^"\n]*"')
# An authored content type: a direct `extends Resource`. Caught only where it
# belongs, so a `Resource` is read as a placement question and not an edge.
RESOURCE_RE = re.compile(r"^\s*extends\s+Resource\s*$", re.MULTILINE)
# A member whose declared type is a bare `Array` — a table this file owns, with
# no engine node type and no repo class behind it. `Array[Marker2D]` is a bound
# node list and does not match; `Array[SkillDef]` matches only when `SkillDef` is
# a class this repo actually defines.
APP_UNSHAPED_ARRAY_RE = re.compile(rules.APP_UNSHAPED_ARRAY_RE, re.MULTILINE)
APP_CONTENT_ARRAY_RE = re.compile(rules.APP_CONTENT_ARRAY_RE, re.MULTILINE)
# `static var` is process-wide memoisation, not per-instance state: `recipe_catalog.gd`
# caches a directory walk in one and is not a feature system.
APP_MARKER_RES: tuple[tuple[str, re.Pattern[str]], ...] = tuple(
    (label, re.compile(pattern, re.MULTILINE)) for label, pattern in rules.APP_STATE_MARKERS
)
# Two independent signals, not one: `world_entry.gd` and `nav_bar.gd` are controls
# with legitimate per-instance collections, and `player_adapter.gd` legitimately
# has a `_physics_process`. One signal never decides; two always describe a file
# that holds a feature's mutable state rather than wiring it.
APP_STATE_MIN_SIGNALS = 2


def _code_only(text: str) -> str:
    """Drop comments and string literals so only real code is scanned."""
    return STRING_RE.sub('""', COMMENT_RE.sub("", text))


def register(subparsers) -> None:
    subparsers.add_parser("arch", help="enforce module boundaries")


def unit_of(rel: str) -> str | None:
    """Map a game-relative path to its architectural unit, or None if irrelevant."""
    parts = Path(rel).parts
    if not parts:
        return None
    if parts[0] == "scenes":
        return "app"
    if parts[0] == "tools":
        return "harness"
    if parts[0] != "src" or len(parts) < 2:
        return None
    head = parts[1]
    if head == "modules":
        return f"modules/{parts[2]}" if len(parts) >= 3 else None
    if head == "ui":
        return "ui"
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
        rel = _relative_to_game(path)
        text = path.read_text(encoding="utf-8", errors="replace")
        for name in CLASS_RE.findall(text):
            index[name] = (rel, unit_of(rel), is_facade(rel))
    return index


def _references(text, scan_bare: bool = False):
    seen = set()
    for match in RES_RE.finditer(text):
        seen.add((text.count("\n", 0, match.start()) + 1, match.group(0)))
    for match in EXTENDS_RE.finditer(text):
        seen.add((text.count("\n", 0, match.start()) + 1, match.group(1)))
    if scan_bare:
        # `ui/` is held to the facade rule, so its edges must be visible even when
        # a class is referenced by bare name (`BodyTraining.cultivate(...)`) with
        # no `res://` and no `extends`. This is what makes the rule enforceable
        # without forcing every panel to preload its facade.
        code = _code_only(text)
        for match in WORD_RE.finditer(code):
            line = code.count("\n", 0, match.start()) + 1
            seen.add((line, match.group(1)))
    return sorted(seen)


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
    if source == "harness":
        # `game/tools/` is headless harness code: the test runner and the UI
        # driver. It builds an Actor directly, so it may reach module internals,
        # and it instantiates screens to drive them, so `ui/` is allowed too.
        # What it must not do is reach `app/` — that is the composition root, and
        # a harness that used it would be testing wiring no player drives.
        if target == "app":
            return "'harness/' must not depend on 'app/'"
        return None
    if source == "ui":
        # `ui/` reads gameplay through facades only, and only what it declares.
        # Reaching into module internals would couple the UI program to the
        # gameplay program and defeat the split.
        if target in ("core", "contracts"):
            return None
        if target.startswith("modules/"):
            dep = target.split("/", 1)[1]
            if not facade:
                return f"'ui/' may reference '{dep}' only through modules/{dep}/api.gd"
            if dep not in rules.UI_MODULES:
                return (
                    f"'ui/' references undeclared module '{dep}'; register it in rules.UI_MODULES"
                )
            return None
        return f"'ui/' must not depend on '{target}/'"
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
        rel = _relative_to_game(path)
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


def _is_resource_home(unit: str | None) -> bool:
    """Whether an authored `Resource` filed under this unit is the repo precedent."""
    if unit in rules.RESOURCE_HOME_UNITS:
        return True
    return unit is not None and unit.startswith("modules/")


def resource_home_warnings(files) -> list[str]:
    """Flag an authored `Resource` that was filed in `contracts/`.

    Exact heuristic: a `.gd` whose `unit_of()` is `contracts` and whose text
    contains a line matching `^\\s*extends\\s+Resource\\s*$`. Nothing else — a
    `Resource` in its owning module or in `core/` is the precedent, and a
    contracts value object that extends another contracts class is untouched.

    A warning and not a failure on purpose: the convention is real but unenforced,
    and hard-failing would turn the gate red on a prototype file that predates it
    for anyone working on something else. The precedent count in the message is
    measured on the same pass, so it cannot drift from the tree.
    """
    offenders: list[tuple[str, str]] = []
    precedent = 0
    for path in files:
        if path.suffix != ".gd":
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if not RESOURCE_RE.search(text):
            continue
        rel = _relative_to_game(path)
        if _is_resource_home(unit_of(rel)):
            precedent += 1
        elif unit_of(rel) == "contracts":
            offenders.append((rel, next(iter(CLASS_RE.findall(text)), "this class")))
    return [
        (
            f"{rel}: {class_name} extends Resource inside contracts/ — an authored content "
            f"type belongs to the module that owns it, or in core/ for shared foundation data; "
            f"all {precedent} other authored Resources in this repo sit in one of those two "
            "places, and no .tres binds a contracts/ script, so nothing is authored against "
            "this one. Move it to the owning module and let that module's facade expose it."
        )
        for rel, class_name in offenders
    ]


def app_state_signals(text: str, classes) -> list[str]:
    """Which independent state signals a script carries. `classes` disambiguates.

    Three signals, all of which mean "this file owns mutable feature state"
    rather than "this file wires things together":

    - `persistence` — calls `set_module_data` / `get_module_data`, i.e. it writes
      its state into an actor's save blob under its own key.
    - `tick-loop`   — declares `tick(` / `process(` / `physics_process(`, i.e. it
      is advanced by time rather than called by a caller.
    - `state-table` — declares a member `Array` with no element type, or with a
      repo-defined element type. An unshaped array is a table the file built; a
      typed one is a table of authored content. `Array[Marker2D]` and friends do
      not match: those are bound node lists, and a name in the class index is
      required for the typed branch so an engine class never counts.

    `classes` may be a mapping of class name to index entry OR a plain container
    of class names: the typed-array branch only asks whether a name is known, and
    accepting both shapes keeps a caller from having to fabricate an index entry
    for a name it merely wants to assert exists.

    `static var` is excluded from all three by construction — the member patterns
    anchor on `var` with no `static` before it.
    """
    signals = [label for label, pattern in APP_MARKER_RES if pattern.search(text)]
    if APP_UNSHAPED_ARRAY_RE.search(text) or any(
        _class_known(element, classes) for element in APP_CONTENT_ARRAY_RE.findall(text)
    ):
        signals.append("state-table")
    return signals


def _class_known(name: str, classes) -> bool:
    """Whether `classes` declares a class by this name, in either supported shape."""
    if classes is None:
        return False
    try:
        return name in classes
    except TypeError:
        return False


def _relative_to_game(path: Path) -> str:
    """A path as a `game/`-relative posix string, whatever tree it actually sits in.

    `unit_of` reads the unit off the path SHAPE — it requires the path to begin
    with `src` (or `scenes`/`tools`). A test fixture lives in a temp directory, so
    `relative_to(GAME_DIR)` raises on it, and falling back to the raw absolute
    text does not help either: `unit_of` still reads `None` off a leading
    `C:/Users/...` and the heuristic silently skips the file. So the path is
    re-anchored on the last `src`/`scenes`/`tools` segment, which is the part the
    unit actually depends on.

    Without this every heuristic built on `unit_of` was untestable: a fixture was
    accepted and then ignored, which reads as a passing negative case.
    """
    try:
        return path.relative_to(GAME_DIR).as_posix()
    except ValueError:
        pass
    parts = path.as_posix().split("/")
    for marker in ("src", "scenes", "tools"):
        if marker in parts:
            return "/".join(parts[parts.index(marker) :])
    return path.as_posix()


def app_state_warnings(files, classes) -> list[str]:
    """Flag a feature system living in the composition root.

    Exact heuristic: a `.gd` in `app/` carrying at least
    `APP_STATE_MIN_SIGNALS` (2) of `app_state_signals`. Two is the load-bearing
    number — a lone `tick` is a controller (`player_adapter.gd` has
    `_physics_process` and is legitimate wiring), and a lone member array is a
    node list (`nav_bar.gd`, `world_entry.gd` are legitimate wiring). Both
    together describe a file that holds a slot table, decays it over time and
    persists it, which is a module's job: the rules that own that data would then
    live in `app/`, outside the module that would change to fix them.
    """
    warnings: list[str] = []
    for path in files:
        if path.suffix != ".gd":
            continue
        rel = _relative_to_game(path)
        if unit_of(rel) != "app":
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        signals = app_state_signals(text, classes)
        if len(signals) < APP_STATE_MIN_SIGNALS:
            continue
        warnings.append(
            f"{rel}: app/ holds a stateful system ({', '.join(signals)}) — app/ is the "
            "composition root and wires; a feature that keeps its own state, decays it over "
            "time and persists it belongs in a module behind a facade, so the rules that own "
            "it sit next to the feature instead of in it."
        )
    return warnings


def module_inventory_warnings(registry) -> list[str]:
    """Report a registered module that has no directory, or no facade, on disk.

    `registry.json` and `UI_MODULES` are permission lists: naming a module there
    grants edges to it and costs nothing if the module does not exist, so a
    green run used to say nothing about whether any of the twelve names had a
    body. This walks both lists against `game/src/modules/` and says so.

    A module on disk that neither list names is *not* reported: an unregistered
    module is inert, not a broken permission, and `tools new_module` registers one
    as its first step anyway.
    """
    root = SRC_DIR / "modules"
    warnings: list[str] = []
    for name in sorted(set(registry) | set(rules.UI_MODULES)):
        directory = root / name
        if not directory.is_dir():
            declared = ", ".join(
                part
                for part, present in (
                    ("registry.json", name in registry),
                    ("UI_MODULES", name in rules.UI_MODULES),
                )
                if present
            )
            warnings.append(
                f"modules/{name}: registered in {declared} but no directory on disk — the "
                "permission is granted to nothing; build the module or drop the entry"
            )
            continue
        if not (directory / rules.FACADE_FILENAME).is_file():
            warnings.append(
                f"modules/{name}: no facade at modules/{name}/{rules.FACADE_FILENAME} — a "
                "module with no facade cannot be reached by ui/ or by a sibling module, so "
                "every edge that names it is a violation and nothing can use it"
            )
    return warnings


def run(args) -> int:
    if not SRC_DIR.is_dir():
        warn("game/src not found; nothing to check")
        return 0
    files = list(_iter_sources())
    classes = _class_index(files)
    registry = rules.load_registry()
    violations: list[str] = []
    for path in files:
        rel = _relative_to_game(path)
        source = unit_of(rel)
        if source is None:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        bare = source in rules.BARE_REF_UNITS
        for line, ref in _references(text, scan_bare=bare):
            target, facade = _resolve(ref, classes)
            reason = _violation(source, target, facade, registry)
            if reason:
                violations.append(f"{rel}:{line}: {reason}")
    cycle = _find_cycle(registry)
    if cycle:
        violations.append("module dependency cycle: " + " -> ".join(cycle))
    structural, structural_warnings = _structural_checks(files)
    violations.extend(structural)
    warnings = structural_warnings
    warnings.extend(resource_home_warnings(files))
    warnings.extend(app_state_warnings(files, classes))
    warnings.extend(module_inventory_warnings(registry))
    for warning in warnings:
        warn(warning)
    if violations:
        for violation in violations:
            fail(violation)
        return 1
    ok(f"boundaries ok ({len(files)} files, {len(registry)} modules)")
    return 0
