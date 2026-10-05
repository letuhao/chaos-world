"""A facade CONSTANT that no production code names is a FAILURE (ADR 0204).

## The defect this closes

Four features shipped in the technique program that were built, given a full test
suite, and called only from their own tests. `TechniqueCatalog.delivers`, so
every study was refused. `TechniqueLoadoutScreen.bind_target`, so every cast paid
qi, burned a cooldown and hit nothing. `TechniqueCastView`, 90 green assertions
and zero production calls. `TechniqueReadModel`'s `learn_price`, so a player
learned the cost by being refused. Each was found by an audit that grepped the
symbol's callers. **No gate failed, because no gate asked.** This module asks.

## Why a CONSTANT, and why only some constants

The width cap is what MADE this pattern common: `TechniquesApi` sat at 12 published
methods, so a module that could not add a method published what it had as a named
component id or a delivery seam, reached by NAME —
`TechniquesApi.CASTING_COMPONENT`, `TechniquesApi.CAST_VIEW`. That pattern was
correct under ADR 0056 and had no gate, which is how four features shipped
unreachable.

**The cap is deleted, and this gate stays anyway**, because its finding does not
depend on it: a constant published on a facade and named by nothing in `res://src`
is dead surface whatever shape the module took. Publishing is not reaching, and the
four features that proved it were never over any limit.

So the gate is scoped to exactly that population — the constants that exist
*because* an outside caller must name them, identified by the `_COMPONENT`
suffix and by the two seams ADR 0056 records. Every other facade constant is a
reason code, a save key, or a number the module applies to itself; those are a
different question, they are enumerated and counted but not gated, and pretending
otherwise is how a gate earns its INC-0017 deletion.

## What counts as a caller

A reference anywhere in `res://src` outside the constant's own declaration —
inside its own facade or in any other production file. **`res://tests` never
counts.** A constant exercised only by its own suite is the defect restated, not
an exemption, and that is the whole finding.

## Anti-vacuity

Three ways to pass without measuring anything, each a FAILURE rather than a pass:

- **no facades found** — the scan pointed at a tree with no `modules/*/api.gd`;
- **no production source read** — every constant would vacuously read as callerless;
- **no gated constant enumerated** — the parser stopped understanding the shape.

A guard that reports nothing because it read nothing is indistinguishable from a
clean tree at exactly the moment the tree is broken.
"""

from __future__ import annotations

import re
import tempfile
from collections.abc import Iterable
from dataclasses import dataclass, field
from pathlib import Path

FACADE_NAME = "api.gd"

COMMENT_RE = re.compile(r"#.*$", re.MULTILINE)
STRING_RE = re.compile(r'"[^"\n]*"')
# `const NAME :=`, `const NAME =`, `const NAME: Type =` at column zero. GDScript
# has no other declaration form, and an indented one is a function-local, not a
# published surface.
CONST_HEAD_RE = re.compile(r"^const\s+([A-Za-z_]\w*)\s*(?::=|:|=)")
# The value a `String`/`StringName` constant publishes, so the string-named
# exemption is measured against a value rather than assumed.
LITERAL_RE = re.compile(r'^&?"([^"\n]*)"$')
OPENERS, CLOSERS = "[({", ")]}"


@dataclass(frozen=True)
class Constant:
    """One constant declared by a module facade."""

    module: str
    name: str
    facade: str
    line: int
    value: str
    literal: str
    gated: bool

    @property
    def qualified(self) -> str:
        return f"{self.module}.{self.name}"

    @property
    def public(self) -> bool:
        return not self.name.startswith("_")


@dataclass
class Report:
    """Everything one pass measured, so callers print numbers, not adjectives."""

    src: Path = Path(".")
    facades: int = 0
    scanned_files: int = 0
    test_files: int = 0
    constants: list[Constant] = field(default_factory=list)
    references: dict[str, list[str]] = field(default_factory=dict)
    test_references: dict[str, list[str]] = field(default_factory=dict)
    internal: set[str] = field(default_factory=set)
    string_named: set[str] = field(default_factory=set)
    #: Constant names declared by more than one facade, so a wildcard `*Api.`
    #: reference cannot be attributed to the wrong module.
    ambiguous: list[str] = field(default_factory=list)

    @property
    def published(self) -> list[Constant]:
        return [c for c in self.constants if c.public]

    @property
    def gated(self) -> list[Constant]:
        return [c for c in self.published if c.gated]

    def callers(self, constant: Constant) -> list[str]:
        return self.references.get(constant.qualified, [])

    def unreferenced(self) -> list[Constant]:
        """Gated constants with no production caller and no exemption."""
        return [
            c
            for c in self.gated
            if not self.references.get(c.qualified) and c.qualified not in self.string_named
        ]


# A constant that exists to be NAMED by a caller outside its module. The suffix
# is the repo's own vocabulary (ADR 0056's component ids) and the exact set is
# the two seams that ADR records, so the scope is stated rather than guessed.
GATED_SUFFIXES = ("_COMPONENT",)
GATED_EXACT = frozenset({"DELIVERY", "CAST_VIEW"})


def is_gated(name: str) -> bool:
    return name.endswith(GATED_SUFFIXES) or name in GATED_EXACT


def code_only(text: str) -> str:
    """Drop comments and string literals, so a scan reads code rather than prose.

    Same cut as `enforce._code_only` and for the same reason: a component name
    in a comment is documentation, and a `#` inside a string is data.
    """
    return STRING_RE.sub('""', COMMENT_RE.sub("", text))


def split_declarations(code: str) -> tuple[dict[str, tuple[int, str]], str]:
    """Split a facade into its constant declarations and its remaining body.

    A `const` whose value opens a bracket continues across lines, and only then:
    a reader that cuts at the line end treats `NODE_YIELDS := {` as declaring
    nothing and reports the body of every multi-line constant as its own name.

    Returns `({name: (line, value)}, body_with_declarations_removed)`. The body
    is what "used by its own facade" asks about — a declaration is not a use.
    """
    lines = code.split("\n")
    declarations: dict[str, tuple[int, str]] = {}
    consumed: set[int] = set()
    index = 0
    while index < len(lines):
        head = CONST_HEAD_RE.match(lines[index])
        if head is None:
            index += 1
            continue
        value = lines[index].split("=", 1)[1].strip() if "=" in lines[index] else ""
        start = index
        depth = _depth(lines[index])
        consumed.add(index)
        index += 1
        while depth > 0 and index < len(lines):
            consumed.add(index)
            value = f"{value} {lines[index].strip()}"
            depth += _depth(lines[index])
            index += 1
        declarations[head.group(1)] = (start + 1, value.strip())
    body = "\n".join("" if i in consumed else line for i, line in enumerate(lines))
    return declarations, body


def _depth(line: str) -> int:
    return sum(line.count(c) for c in OPENERS) - sum(line.count(c) for c in CLOSERS)


def facade_paths(src: Path) -> list[Path]:
    modules = src / "modules"
    if not modules.is_dir():
        return []
    return sorted(modules.glob(f"*/{FACADE_NAME}"))


def script_paths(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    return sorted(path for path in root.rglob("*.gd") if ".godot" not in path.parts)


def read_bodies(paths: Iterable[Path]) -> dict[Path, str]:
    return {path: code_only(path.read_text(encoding="utf-8", errors="replace")) for path in paths}


CLASS_NAME_RE = re.compile(r"^\s*class_name\s+([A-Za-z_]\w*)", re.MULTILINE)


def _class_name_of(facade: str) -> str:
    """The `class_name` a facade declares, which is what callers actually spell.

    Callers never write `techniques.CASTING_COMPONENT`; they write
    `TechniquesApi.CASTING_COMPONENT`. The directory name and the class name are
    the same relationship written two ways, and matching only one of them
    reports every live seam as dead — a finding nobody can act on, which is
    worse than no finding.
    """
    try:
        text = Path(facade).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    found = CLASS_NAME_RE.search(text)
    return found.group(1) if found else ""


def _ambiguous_names(constants: Iterable[Constant]) -> set[str]:
    """Constant names declared by more than one facade.

    `STATE_COMPONENT` is declared by `npc`, `nation`, `set_bonus` and `social`.
    A caller spelling `NpcApi.STATE_COMPONENT` names one of them precisely, so
    the qualified pattern resolves it; but a caller that writes the name bare
    cannot be attributed, and neither can a pattern that accepts ANY `*Api`. So
    a name in this set is credited only through its own module or its own
    `class_name`, never through the wildcard.
    """
    counts: dict[str, int] = {}
    for constant in constants:
        counts[constant.name] = counts.get(constant.name, 0) + 1
    return {name for name, count in counts.items() if count > 1}


def enumerate_constants(facades: Iterable[Path]) -> list[Constant]:
    """Every constant declared by a module facade, in file and declaration order.

    Reads RAW text, not the comment-stripped text, so the published value keeps
    the quotes `code_only` removes and `LITERAL_RE` needs.
    """
    constants: list[Constant] = []
    for facade in facades:
        raw = facade.read_text(encoding="utf-8", errors="replace")
        declarations, _ = split_declarations(raw)
        module = facade.parent.name
        for name, (line, value) in declarations.items():
            literal = LITERAL_RE.match(value)
            constants.append(
                Constant(
                    module=module,
                    name=name,
                    facade=facade.as_posix(),
                    line=line,
                    value=value,
                    literal=literal.group(1) if literal else "",
                    gated=is_gated(name),
                )
            )
    return constants


def scan(src: Path, tests: Path | None = None) -> Report:
    """Enumerate facade constants and count production references for each.

    `src`/`tests` are parameters so a fixture can be scanned without the
    repository — which is what makes this guard testable at all.
    """
    report = Report(src=src)
    facades = facade_paths(src)
    report.facades = len(facades)
    report.constants = enumerate_constants(facades)
    ambiguous = _ambiguous_names(report.constants)
    report.ambiguous = sorted(ambiguous)

    sources = script_paths(src)
    report.scanned_files = len(sources)
    # Raw text kept alongside the stripped bodies: the string-named exemption has
    # to match a string LITERAL, and `code_only` deletes every one of them.
    raw_bodies = {path: path.read_text(encoding="utf-8", errors="replace") for path in sources}
    bodies = {path: code_only(text) for path, text in raw_bodies.items()}
    # Facades are re-read with their DECLARATIONS REMOVED, so a constant cannot
    # be credited with its own `const` line. This is the difference between a
    # guard that reports and one that always says ok.
    for facade in facades:
        bodies[facade] = split_declarations(bodies[facade])[1]
    test_bodies = read_bodies(script_paths(tests)) if tests is not None else {}
    report.test_files = len(test_bodies)

    # A facade is matched on its BODY, never on its full text. The declaration
    # line `const NAME := &"x"` contains the name, so a scan of the raw file
    # credits every constant with itself and the guard can never report
    # anything — a guard that cannot fail is worse than none, because it
    # reports ok. `split_declarations` returns exactly the body, which is why
    # every other reference on this tree agrees and this one did not.
    #
    # The qualifier is the facade's `class_name` or its module directory — the
    # same relationship written two ways, since callers spell
    # `TechniquesApi.CASTING_COMPONENT` and never `techniques.CASTING_COMPONENT`.
    facade_set = {path for path in facades}
    for constant in report.constants:
        bare = re.compile(rf"\b{re.escape(constant.name)}\b")
        spellings = [constant.module, _class_name_of(constant.facade)]
        qualified = re.compile(
            r"\b(?:"
            + "|".join(re.escape(s) for s in spellings if s)
            + r")\s*\.\s*"
            + re.escape(constant.name)
            + r"\b"
        )
        # Any `*Api` is a module facade by this repo's own convention, so a
        # caller may reach a sibling's seam through its class name. Used only
        # for a name unique across facades: `STATE_COMPONENT` is declared by
        # four of them and a wildcard cannot say which one is meant.
        aliased = re.compile(rf"\b[A-Za-z_]\w*Api\s*\.\s*{re.escape(constant.name)}\b")
        hits = [
            path.as_posix()
            for path, body in bodies.items()
            # A facade reads its OWN constants unqualified. Only the DECLARING
            # facade may do so: `mind/api.gd` printing `NpcApi.STATE_COMPONENT`
            # contains the bare name `STATE_COMPONENT`, and crediting that to
            # `social.STATE_COMPONENT` would hide a dead seam behind a live one —
            # the exact direction in which this guard must not be blind.
            if (path == Path(constant.facade) and bare.search(body))
            or qualified.search(body)
            or (aliased.search(body) and constant.name not in ambiguous)
        ]
        report.references[constant.qualified] = sorted(hits)
        report.test_references[constant.qualified] = sorted(
            path.as_posix() for path, body in test_bodies.items() if bare.search(body)
        )

    # The ONE legitimate exemption, and it is measured rather than assumed: a
    # constant that exists to be named BY ITS STRING. `DELIVERY_SETTING :=
    # "technique/delivery_seam"` in `items/item_use.gd` is a caller naming the
    # published value; it cannot name the constant, because that would be a
    # cross-module edge to a facade it is not permitted to reach.
    #
    # Measured on RAW text, not on `bodies`. `code_only` replaces every string
    # literal with `""`, so a body-scoped search for `"technique_delivery"` can
    # never match — the exemption would be unreachable code that silently never
    # fires, which is worse than not having one. Comments are stripped here for
    # the same reason as everywhere else: prose naming a value is not code
    # naming it.
    for constant in report.constants:
        if not constant.literal:
            continue
        quoted = f'"{constant.literal}"'
        if any(quoted in raw_bodies.get(path, "") for path in sources if path not in facade_set):
            report.string_named.add(constant.qualified)
    return report


def findings(report: Report) -> list[str]:
    """Each gated constant with no production caller, as one actionable line."""
    out: list[str] = []
    for constant in report.unreferenced():
        tests = report.test_references.get(constant.qualified) or []
        if tests:
            tail = (
                f" It is called by {len(tests)} test file(s) (e.g. {tests[0]}) and nothing "
                "else, which IS the defect: a suite that only calls itself is not "
                "reachability. Add the production call site or delete the constant."
            )
        else:
            tail = (
                " No production file and no test names it, so it is inert: add the "
                "production call site or delete the constant."
            )
        out.append(
            f"{constant.facade}:{constant.line}: {constant.qualified} is a published facade "
            f"CONSTANT with no caller in res://src. {constant.module} publishes a component or "
            "seam type as a CONSTANT rather than a method (ADR 0056) — but publishing is not "
            f"reaching, and this one is reached by nothing.{tail}"
        )
    return out


def vacuity_failures(report: Report) -> list[str]:
    """Ways this pass could have measured nothing. Each FAILS; none is a pass."""
    where = report.src.as_posix()
    if report.facades == 0:
        return [
            f"no module facade found under {where} — the scan read no `modules/*/api.gd`, "
            "so it enumerated zero constants. A guard that scanned nothing must fail, not "
            "pass: this is the defect restated (a feature green because nothing examined it)"
        ]
    problems: list[str] = []
    if report.scanned_files == 0:
        problems.append(
            f"no production source read under {where} — every constant would read as having "
            "no caller, so this pass can only be wrong"
        )
    if not report.constants:
        problems.append(
            f"{report.facades} facade(s) read and no constant found in any of them: either "
            "every facade is a plain method surface or the reader no longer parses GDScript. "
            "Either way the pass is vacuous and fails rather than reporting ok"
        )
    elif not report.gated:
        problems.append(
            f"{len(report.constants)} constant(s) enumerated across {report.facades} facade(s) "
            "and none is a gated seam (`"
            + "`, `".join(GATED_SUFFIXES + tuple(sorted(GATED_EXACT)))
            + "`). The scope this guard exists for has vanished, which is a change to the "
            "shape, not a clean tree"
        )
    return problems


def evaluate(src: Path, tests: Path | None = None) -> tuple[list[str], Report]:
    """Return `(problems, report)`. Empty `problems` is the only clean verdict."""
    report = scan(src, tests)
    return [*vacuity_failures(report), *findings(report)], report


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "facade_constants", help="fail a facade CONSTANT that no production code names"
    )
    parser.add_argument(
        "--src",
        default=None,
        help="the directory res://src maps to (default: game/src)",
    )


def run(args) -> int:
    """`uv run python -m tools facade_constants` — the standalone entry point.

    `tools arch` runs the same `evaluate()` in-process; this exists so the
    guard can be pointed at a fixture tree from the command line and so a human
    can ask the question on its own.
    """
    from ..common import SRC_DIR, TESTS_DIR, fail, ok

    src = Path(args.src) if args.src else SRC_DIR
    problems, report = evaluate(src, TESTS_DIR)
    for problem in problems:
        fail(problem)
    if problems:
        return 1
    ok(
        f"facade constants ok ({report.facades} facades, {len(report.constants)} constants, "
        f"{len(report.gated)} gated seams, {report.scanned_files} production files read, "
        f"{len(report.test_files)} test files read)"
    )
    return 0


# --- Red paths ---------------------------------------------------------------
#
# A green guard is not a tested guard (INC-0016). Every validator in `tools/` is
# unreachable from the GDScript suite, so these cases exist to prove this one
# still goes RED. A happy path here would be worth almost nothing: "the guard
# passes on today's tree" is what `tools check` already does and proves nothing.
#
# Registered through `selftest.case`, so adding the guard without its red paths
# would show up as a missing case rather than as silence.

_REGISTERED = False


def register_selftest_cases(case, expect, write) -> None:
    """Attach the guard's red-path cases to the `selftest` harness.

    Imported lazily by `selftest_cases.py`, which owns the harness; importing
    `case`/`expect` at module scope would be a cycle (`selftest` -> `arch` ->
    this module), so the harness passes its own decorators in.
    """
    global _REGISTERED  # noqa: PLW0603 - registration happens exactly once
    if _REGISTERED:
        return
    _REGISTERED = True

    def fixture(root, module="techniques", class_name="TechniquesApi", body=None, extra=()):
        """One module facade declaring a gated seam, plus optional sibling files."""
        facade = write(
            root / "src" / "modules" / module / "api.gd",
            f"class_name {class_name}\nextends RefCounted\n\n"
            + (body or 'const CASTING_COMPONENT := &"technique_casting"\n')
            + "\n\nstatic func attach(actor) -> void:\n\tpass\n",
        )
        for rel, text in extra:
            write(root / rel, text)
        return facade

    @case("facade_constants: a seam with NO production caller FAILS")
    def _unreferenced_seam_fails() -> None:
        from ..selftest import write as _write

        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fixture(root)
            # A test that calls it is the DEFECT, not an exemption.
            _write(
                root / "tests" / "test_seam.gd",
                "extends TestCase\n\n\nfunc it() -> void:\n\tassert(true)\n",
            )
            problems, report = evaluate(root / "src", root / "tests")
            expect(
                any("CASTING_COMPONENT" in p for p in problems),
                "a facade CONSTANT that no production file names was accepted, which is "
                "exactly the shape that shipped four unreachable technique features",
            )
            expect(
                len(report.gated) == 1,
                f"the fixture enumerated {len(report.gated)} gated seams, expected 1, so the "
                "case is not testing what it claims",
            )

    @case("facade_constants: ONE production caller clears it")
    def _one_caller_is_enough() -> None:
        """The counterweight. A guard that fails everything passes every red path."""
        from ..selftest import write as _write

        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fixture(
                root,
                extra=[
                    (
                        "src/ui/screens/loadout.gd",
                        "extends Control\n\n\nfunc _read(actor) -> void:\n"
                        "\tvar c := actor.component(TechniquesApi.CASTING_COMPONENT)\n"
                        "\tprint(c)\n",
                    )
                ],
            )
            _write(root / "tests" / "t.gd", "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n")
            problems, report = evaluate(root / "src", root / "tests")
            expect(
                not problems,
                f"a seam with a production caller in ui/ was still reported: {problems!r}. "
                "ADR 0056's pattern is CORRECT, and a guard that refuses it is deleted on "
                "its first trip (INC-0017)",
            )
            expect(
                report.callers(report.gated[0]),
                "the fixture did not register the caller, so a pass below would be vacuous",
            )

    @case("facade_constants: a seam only its OWN TESTS call still FAILS")
    def _test_only_seam_fails() -> None:
        from ..selftest import write as _write

        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fixture(root)
            _write(
                root / "tests" / "test_seam.gd",
                "extends TestCase\n\n\nfunc it() -> void:\n\tTechniquesApi.CASTING_COMPONENT\n",
            )
            problems, _ = evaluate(root / "src", root / "tests")
            expect(
                any("CASTING_COMPONENT" in p for p in problems),
                "a seam reached only from res://tests was accepted. A suite that calls itself "
                "is the DEFECT restated, not an exemption",
            )

    @case("facade_constants: a facet with NO FACADES FAILS LOUDLY, never passes vacuously")
    def _no_facades_fails_loudly() -> None:
        """The anti-vacuity term, and the one that matters most.

        Point the guard at a directory holding no `modules/*/api.gd` and a
        scanner that reports nothing reads as a clean tree. That is the defect
        restated: a feature green because nothing examined it.
        """
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            write(root / "src" / "ui" / "screen.gd", "extends Control\n")
            problems, report = evaluate(root / "src")
            expect(
                report.facades == 0,
                "fixture did start with no facades, so the pass below would be vacuous",
            )
            expect(
                any("no module facade" in p for p in problems),
                f"a tree with zero facades was reported clean: {problems!r}. A guard that "
                "scanned nothing must FAIL, not pass",
            )

    @case("facade_constants: facades with NO gated constants FAILS, never passes vacuously")
    def _no_gated_constants_fails() -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            # A facade that publishes only a save key: perfectly legal GDScript,
            # and the state where a reader that stopped understanding seams would
            # still have SOMETHING to enumerate and report nothing.
            fixture(root, body='const MODULE_KEY := &"techniques"\n')
            problems, report = evaluate(root / "src")
            expect(
                len(report.constants) == 1 and not report.gated,
                f"fixture should hold one non-gated constant and no seam, but read "
                f"{len(report.constants)} constant(s) / {len(report.gated)} seam(s), so the "
                "gated-emptiness check below is untested",
            )
            expect(
                any("none is a gated seam" in p for p in problems),
                f"a facade set with no gated seam was reported clean: {problems!r}. A parser "
                "that stopped understanding the shape must fail rather than say ok",
            )

    @case("facade_constants: a COMMENT naming a seam is not a caller")
    def _comment_is_not_a_caller() -> None:
        """The bug this guard actually shipped with.

        `nation/api.gd` explains, in prose, why it does NOT need
        `TechniquesApi.CASTING_COMPONENT`. A scan that reads comments credits
        every seam with the documentation about it, so the guard reports ok
        forever and never fires — the exact failure the task exists to stop.
        """
        from ..selftest import write as _write

        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fixture(
                root,
                module="nation",
                class_name="NationApi",
                extra=[
                    (
                        "src/modules/nation/other.gd",
                        "extends RefCounted\n\n\n## the reason to spend one is the\n"
                        "## TechniquesApi.CASTING_COMPONENT precedent\n"
                        "static func _leave(actor) -> void:\n\tpass\n",
                    )
                ],
            )
            _write(root / "tests" / "t.gd", "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n")
            problems, report = evaluate(root / "src", root / "tests")
            expect(
                any("CASTING_COMPONENT" in p for p in problems),
                f"a seam named only in another module's COMMENT was accepted: {problems!r}. "
                "Prose about a seam is not a call to it",
            )
            expect(
                not report.callers(report.gated[0]),
                "the comment was counted as a caller, so this guard could never report anything",
            )

    @case("facade_constants: a declaration is not a caller of ITSELF")
    def _declaration_is_not_a_caller() -> None:
        """The second self-credit bug: matching a facade's raw text.

        `const NAME := &"x"` contains the name, so a scan of the raw file credits
        every constant with itself and the guard can never fail on anything.
        """
        from ..selftest import write as _write

        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fixture(root)
            _write(root / "tests" / "t.gd", "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n")
            problems, report = evaluate(root / "src", root / "tests")
            expect(
                not report.callers(report.gated[0]),
                "a constant's own `const` line was counted as its caller, so the guard is "
                "structurally incapable of reporting anything",
            )
            expect(
                any("CASTING_COMPONENT" in p for p in problems),
                f"the self-credit made a callerless seam read as clean: {problems!r}",
            )

    @case("facade_constants: a caller spelled through ANY `*Api` still counts")
    def _api_alias_counts() -> None:
        """The resolver must not demand the module's directory spelling.

        Callers write `TechniquesApi.CASTING_COMPONENT`, never
        `techniques.CASTING_COMPONENT`. A guard that only accepted the second
        reports every LIVE seam as dead, which is worse than no guard: it
        manufactures a finding nobody can act on.
        """
        from ..selftest import write as _write

        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fixture(
                root,
                module="techniques",
                class_name="TechniquesApi",
                body='const CAST_VIEW := "technique_cast_view"\n',
                extra=[
                    (
                        "src/ui/screens/loadout.gd",
                        "extends Control\n\n\nfunc _path() -> String:\n"
                        '\treturn "res://" + String(TechniquesApi.CAST_VIEW) + ".gd"\n',
                    )
                ],
            )
            _write(root / "tests" / "t.gd", "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n")
            problems, report = evaluate(root / "src", root / "tests")
            expect(
                not problems,
                f"a live seam reached through its `class_name` was reported dead: {problems!r}. "
                "ADR 0056 publishes CAST_VIEW and the screen consumes it; refusing that is "
                "refusing the sanctioned pattern",
            )
            expect(
                report.callers(report.gated[0]),
                "the fixture did not register the caller, so a pass below would be vacuous",
            )

    @case("facade_constants: a same-named constant in a SIBLING facade is not this caller")
    def _sibling_same_name_does_not_borrow() -> None:
        """`STATE_COMPONENT` is declared by four facades on this tree.

        The dangerous direction is the one that HIDES the defect: if a sibling's
        real caller were allowed to credit a seam nothing calls, this guard
        would be blind exactly where it is needed. So the fixture names ONE
        sibling and leaves the other untouched — if the wildcard leaks, the
        untouched sibling reads as alive.
        """
        from ..selftest import write as _write

        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fixture(
                root,
                module="npc",
                class_name="NpcApi",
                body='const STATE_COMPONENT := &"npc_state"\n',
            )
            fixture(
                root,
                module="social",
                class_name="SocialApi",
                body='const STATE_COMPONENT := &"social_state"\n',
            )
            # Only NpcApi is called. social.STATE_COMPONENT has NO caller, and
            # must be reported.
            _write(
                root / "src" / "modules" / "mind" / "api.gd",
                "class_name MindApi\nextends RefCounted\n\n\n"
                "static func _read(actor) -> void:\n\tprint(NpcApi.STATE_COMPONENT)\n",
            )
            _write(root / "tests" / "t.gd", "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n")
            problems, report = evaluate(root / "src", root / "tests")
            expect(
                report.ambiguous == ["STATE_COMPONENT"],
                f"the fixture's shared name was not detected as ambiguous ({report.ambiguous}), "
                "so this case cannot tell the wildcard from the guarded reading",
            )
            social = next(c for c in report.gated if c.qualified == "social.STATE_COMPONENT")
            expect(
                not report.callers(social),
                f"social.STATE_COMPONENT was credited with npc's caller "
                f"({report.callers(social)}), so a seam nothing reaches reads as alive — the "
                "guard would be blind in the one direction that hides the defect",
            )
            expect(
                any("social.STATE_COMPONENT" in p for p in problems),
                f"the untouched sibling seam was not reported: {problems!r}",
            )

    @case("facade_constants: a constant named BY ITS STRING is exempt")
    def _string_named_is_exempt() -> None:
        """The one legitimate exemption, and it must be reachable.

        A caller that may not reach the facade at all can still name the
        published value. Exempting it is why the guard is not a rule that
        outlives its exceptions.
        """
        from ..selftest import write as _write

        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fixture(root, body='const DELIVERY := &"technique_delivery"\n')
            _write(
                root / "src" / "modules" / "items" / "item_use.gd",
                'extends RefCounted\n\n\nconst SETTING := "technique/delivery_seam"\n\n\n'
                'static func seam() -> String:\n\treturn "technique_delivery"\n',
            )
            _write(root / "tests" / "t.gd", "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n")
            problems, report = evaluate(root / "src", root / "tests")
            expect(
                "techniques.DELIVERY" in report.string_named,
                "a constant named by its literal string elsewhere was not recognised as exempt",
            )
            expect(
                not problems,
                f"a published identifier a caller names by STRING was still reported: {problems!r}",
            )

    @case("facade_constants: the exemption needs a STRING caller, not a comment")
    def _comment_does_not_exempt() -> None:
        """Otherwise the exemption is a hole: prose about the value grants it."""
        from ..selftest import write as _write

        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fixture(root, body='const DELIVERY := &"technique_delivery"\n')
            _write(
                root / "src" / "modules" / "items" / "item_use.gd",
                "extends RefCounted\n\n\n## the seam is technique_delivery\n"
                "static func seam() -> void:\n\tpass\n",
            )
            _write(root / "tests" / "t.gd", "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n")
            problems, _ = evaluate(root / "src", root / "tests")
            expect(
                any("DELIVERY" in p for p in problems),
                f"a value mentioned only in a comment was accepted as a caller: {problems!r}. "
                "The exemption exists for code that names the string, not for prose",
            )
