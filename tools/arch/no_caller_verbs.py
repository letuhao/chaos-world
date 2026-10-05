"""A published facade VERB that no production code calls is a FAILURE (ADR 0188).

## The defect this closes

BL-0907's re-measurement pass found six published verbs across two modules with
zero production callers and no gate that could notice: `QuestApi.complete`,
`QuestApi.catalog`, `EventApi.catalog`, `EventApi.active`, `EventApi.events`,
`EventApi.resolve`. Two of them have real consequences — `EventApi.resolve` is
the only caller of `NationApi.resolve_conflict`, so a declared sect-war verdict
can never be settled (DEF-0315), and `EventApi.events` is the module's event
BUS, so nothing subscribes to it. The other four are harmless surface. Nothing
distinguished the two cases, and nothing would have noticed.

ADR 0188 already decided the rule — "a published member is KEPT when a caller
exists that is not a test ... otherwise it is DELETED" — and this is the guard
that decision asked for. ADR 0226 supplies the shape it must obey: a DECLARATION
is never evidence of its own reachability.

## What counts as a caller, and why the definition is this wide

A source scan cannot see a call it is not shaped to read, and this repo wires
every seam through an indirection (INC-0012: a census that reported a live
trigger as dead). So the scan counts five caller shapes, and all five are real
invocations of the published verb:

1. **a qualified call** — `QuestApi.complete(...)`, or the module-directory
   spelling `quest.complete(...)`, from any production file;
2. **a bare call** — `complete(...)` from any production file outside the
   declaring module, because a verb on a `static func` facade is called by name
   inside its own module and through an instance alias outside it;
3. **a `Callable` seam** — `Callable(QuestApi, "complete")`, which is how
   `WorldStage.set_location_publisher(Callable(EventApi, "set_location"))`,
   `NpcBoot`'s `Callable(NpcApi, "tally")` and every `LootApi` bridge verb are
   wired;
4. **a dispatch seam** — `.call("complete")`, `.call_deferred("complete")`,
   `.connect("complete")`, `has_signal("complete")`, the reflective `.&"complete"`
   and `emit(...)` forms;
5. **a `ui/` caller**, which is already covered by (1)/(2) but is called out
   because `ui/` may reach a module ONLY through `api.gd`: a screen naming
   `QuestApi.complete` is a legitimate production caller, not a boundary
   violation, and a guard that refused it would be reporting the repo's own
   sanctioned pattern as dead.

`res://tests` NEVER counts. A verb exercised only by its own suite is the defect
restated, not an exemption (ADR 0188).

## What it reads: CODE LINES ONLY

ADR 0188's last clause, and it is the clause a first version of this guard
broke: prose must stay free to say what was deleted and why, and a scan that
reads comments credits every verb with the documentation about it. Comments are
stripped before matching. String literals are KEPT, because three of the five
caller shapes above are spelled as strings and `code_only` would delete them —
the exemption has to be measurable on the text an author actually wrote.

The declaration is stripped from the file that declares it. `static func
complete(` contains the name, so a scan of the raw file credits every verb with
itself and the guard can never report anything.

## The escape hatch is a DECLARED LIST, not a waiver

`no_caller_allowlist.json` maps `Class.verb` to a reason. It is exact-keyed, so a
verb that is NOT on it and has no caller still fails; there is no wildcard and no
module-level suppression. Two properties keep it from decaying into a blanket:

- **every entry carries a reason.** An entry with no reason is a parse failure,
  so "we did not want to look at this one" is not a value the file can hold;
- **a stale entry fails.** An allowlisted verb that has since found a caller is
  reported, so the list cannot accumulate entries that silently describe a
  different tree than the one it was written against.

This is ADR 0226's ladder read from the other end: the decidable question (does
production code call this verb?) is gated, and the question that needs a person
(the intended caller-less verb is deliberate — `EventApi.resolve`, deferred as
DEF-0315) is RECORDED against a named ticket rather than tolerated in silence.

## Anti-vacuity

Three ways this pass could measure nothing, each a FAILURE: no facades found, no
production source read, or no published verb enumerated. A guard that reports
nothing because it read nothing is indistinguishable from a clean tree at
exactly the moment the tree is broken (ADR 0226's own clause 3).
"""

from __future__ import annotations

import json
import re
import tempfile
from collections.abc import Iterable
from dataclasses import dataclass, field
from pathlib import Path

FACADE_NAME = "api.gd"
ALLOWLIST_NAME = "no_caller_allowlist.json"

COMMENT_RE = re.compile(r"#.*$", re.MULTILINE)
# `class_name Foo` — the spelling callers actually write.
CLASS_RE = re.compile(r"^\s*class_name\s+([A-Za-z_]\w*)", re.MULTILINE)
# A facade verb. Anchored to column zero: an indented `func` is a nested/local
# form GDScript does not publish, and reading it would enumerate helpers as
# surface.
FUNC_RE = re.compile(r"^(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(", re.MULTILINE)
# `QuestApi.complete(` — a qualified call through a class name or a module dir.
QUALIFIED_CALL_RE = r"\b(?:{cls}|{module})\s*\.\s*{verb}\s*\("
# `complete(` — a bare call, which a static facade verb is reached by when the
# caller holds the verb rather than the class.
BARE_CALL_RE = r"\b{verb}\s*\("


@dataclass(frozen=True)
class Verb:
    """One published verb on a module facade."""

    module: str
    cls: str
    name: str
    facade: str
    line: int

    @property
    def qualified(self) -> str:
        return f"{self.cls}.{self.name}"

    @property
    def public(self) -> bool:
        return not self.name.startswith("_")


@dataclass(frozen=True)
class AllowEntry:
    """One deliberate caller-less verb, and the reason it is one."""

    reason: str
    ticket: str = ""


@dataclass
class Report:
    """Everything one pass measured, so the verdict prints numbers, not adjectives."""

    src: Path = Path(".")
    facades: int = 0
    verbs: list[Verb] = field(default_factory=list)
    scanned_files: int = 0
    test_files: int = 0
    allowlist: dict[str, AllowEntry] = field(default_factory=dict)
    #: Direct callers — a real `Cls.verb(` or a bare `verb(` from outside the module.
    callers: dict[str, list[str]] = field(default_factory=dict)
    #: Every caller, direct AND seam-wired. The set the verdict is read from.
    reached: dict[str, list[str]] = field(default_factory=dict)
    seams: dict[str, list[str]] = field(default_factory=dict)
    tests: dict[str, list[str]] = field(default_factory=dict)
    #: ADR 0188's second keeper: a verb named by a committed guard in `tools/` that
    #: checks for its call. `game/tests` cannot see Python, so a Python guard
    #: naming a verb is a live dependency on it, not documentation about it.
    guards: dict[str, list[str]] = field(default_factory=dict)

    @property
    def published(self) -> list[Verb]:
        return [v for v in self.verbs if v.public]

    def caller_less(self) -> list[Verb]:
        """Published verbs with no production caller and no declaration."""
        return [
            v
            for v in self.published
            if not self.reached.get(v.qualified) and not self.guards.get(v.qualified)
        ]


def load_allowlist(path: Path) -> tuple[dict[str, AllowEntry], list[str]]:
    """Read the declared exceptions.

    Returns `(entries, parse_failures)`. An entry without a reason is a failure
    rather than a tolerated row: the whole value of a declared exception list is
    that someone had to say why, and an optional reason makes the list a waiver.
    """
    if not path.is_file():
        return {}, []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return {}, [f"{path.as_posix()}: not readable as JSON ({exc})"]
    entries: dict[str, AllowEntry] = {}
    problems: list[str] = []
    raw = data.get("entries", {}) if isinstance(data, dict) else {}
    if not isinstance(raw, dict):
        return {}, [f"{path.as_posix()}: `entries` is not an object"]
    for name, row in raw.items():
        if not isinstance(row, dict):
            problems.append(f"{path.as_posix()}: entry {name!r} is not an object")
            continue
        reason = str(row.get("reason", "")).strip()
        if not reason:
            problems.append(
                f"{path.as_posix()}: entry {name!r} carries no reason. A deliberate "
                "caller-less verb must say WHY; an unexplained entry is the blanket "
                "waiver this list exists to avoid"
            )
            continue
        entries[name] = AllowEntry(reason=reason, ticket=str(row.get("ticket", "")).strip())
    return entries, problems


def facade_paths(src: Path) -> list[Path]:
    if not src.is_dir():
        return []
    found = set(src.glob(f"modules/*/{FACADE_NAME}"))
    top = src / FACADE_NAME
    if top.is_file():
        found.add(top)
    return sorted(found)


def script_paths(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    return sorted(p for p in root.rglob("*.gd") if ".godot" not in p.parts)


def code_only(text: str) -> str:
    """Drop `#` comments and keep string literals (ADR 0188: a guard reads code lines only).

    String literals are kept deliberately. Three of the five caller shapes are
    spelled as strings — `Callable(Api, "verb")`, `.call("verb")`, `has_signal(
    "verb")` — and a scan that stripped them would report every seam in this repo
    as caller-less, which is INC-0012 in a new coat.
    """
    return COMMENT_RE.sub("", text)


def enumerate_verbs(facades: Iterable[Path]) -> list[Verb]:
    """Every published verb on every module facade, in file and declaration order."""
    verbs: list[Verb] = []
    for facade in facades:
        raw = facade.read_text(encoding="utf-8", errors="replace")
        found = CLASS_RE.search(raw)
        cls = found.group(1) if found else facade.parent.name
        module = facade.parent.name
        body = code_only(raw)
        for match in FUNC_RE.finditer(body):
            line = body.count("\n", 0, match.start()) + 1
            verbs.append(
                Verb(
                    module=module, cls=cls, name=match.group(1), facade=facade.as_posix(), line=line
                )
            )
    return verbs


def _declaration_free(body: str) -> str:
    """`body` with every `func NAME(` HEADER removed, so a verb is not its own caller."""
    return FUNC_RE.sub("", body)


def _seam_patterns(cls: str, module: str, verb: str) -> list[re.Pattern[str]]:
    """Regexes for the three indirection shapes a direct-call scan cannot see.

    Compiled ONCE per verb, and the text they run against is pre-indexed by
    script, so a pass over 400 verbs and 1300 files is one indexed lookup per
    verb rather than 1300 regex sweeps. The first version compiled inline and
    scanned every body for every verb; it read the real tree correctly and took
    over two minutes, which is a guard nobody runs (ADR 0226 clause 3: a gate
    that cannot be executed is not a gate).
    """
    name = re.escape(verb)
    qualifiers = "|".join({re.escape(cls), re.escape(module)})
    raw = [
        # `Callable(QuestApi, "complete")` and `QuestApi.&"complete"`.
        rf'\bCallable\s*\([^)]*\b(?:{qualifiers})[^)]*,\s*&?"{name}"',
        rf'\b(?:{qualifiers})\s*\.\s*&"{name}"',
        # `.call("complete")`, `.call_deferred(...)`, `.connect(...)`,
        # `has_signal(...)` — the reflective dispatch forms.
        rf"\.\s*(?:call|call_deferred|callv|connect|has_signal|is_connected|emit_signal|emit)"
        rf'\s*\(\s*&?"{name}"',
    ]
    return [re.compile(pattern) for pattern in raw]


#: Every string literal in a production body, used to answer "does any file name
#: this verb as a string?" once instead of once per verb.
_STR_CALL_RE = re.compile(r"&?\"([A-Za-z_]\w*)\"")
#: Every bare `name(` in a body, pre-indexed so a bare call costs one lookup.
_BARE_CALL_SCAN_RE = re.compile(r"\b([A-Za-z_]\w*)\s*\(")
#: Every `Class.verb(` edge in a production body, already indexed.
_CLASS_CALL_RE = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\s*\.\s*([A-Za-z_]\w*)\s*\(")


def _index(bodies: dict[Path, str]) -> dict[str, set[Path]]:
    """`verb name -> files that contain it`, over one read of every production body.

    The index is what makes a whole-tree verb census affordable: each verb then
    costs one set lookup, and the expensive per-file regex work happens once. A
    verb whose name appears in only three files is then read three times, not 1300.
    """
    index: dict[str, set[Path]] = {}
    for path, body in bodies.items():
        for _, verb in _CLASS_CALL_RE.findall(body):
            index.setdefault(verb, set()).add(path)
        for name in _STR_CALL_RE.findall(body):
            index.setdefault(name, set()).add(path)
        for name in _BARE_CALL_SCAN_RE.findall(body):
            index.setdefault(name, set()).add(path)
    return index


def _qualified_index(bodies: dict[Path, str]) -> dict[str, set[Path]]:
    """`Class.verb -> files`, for the qualified-call shape."""
    index: dict[str, set[Path]] = {}
    for path, body in bodies.items():
        for cls, verb in _CLASS_CALL_RE.findall(body):
            index.setdefault(f"{cls}.{verb}", set()).add(path)
    return index


def _ambiguous_verbs(verbs: list[Verb]) -> set[str]:
    """Verb names declared by MORE THAN ONE facade, where a bare call cannot be attributed.

    `events` is declared by five facades and `resolve` by three, so `events(` in
    `mods/mod_loader.gd` is `ModsApi.events` and `resolve(` in `owner_resolver.gd`
    is its own resolver. For those names a bare call proves nothing and is
    discarded unless the file also names the facade class.
    """
    counts: dict[str, int] = {}
    for verb in verbs:
        counts[verb.name] = counts.get(verb.name, 0) + 1
    return {name for name, count in counts.items() if count > 1}


def _bare_call_is_this_verb(
    text: str, verb: Verb, ambiguous: set[str]
) -> bool:
    """Is the bare `verb(` in this body a call of THIS verb, or of a namesake?

    A bare call is ambiguous, and an unguarded one is how a reader reports a dead
    verb as ALIVE. Two namesexes on this tree proved it while the rule was being
    written, and both are the subject of BL-0907:

    - `EventApi.events` — the event BUS, which has no production subscriber. Its
      bare name matches `ModsApi.events` in `mods`, so an unguarded reader credits
      seven unrelated files and the one true positive with "real consequences"
      passes clean.
    - `EventApi.resolve` — DEF-0315's whole subject, the verb that settles a
      sect-war verdict. `resolve(` matches `owner_resolver.gd`'s own `resolve`,
      so 23 namesexes credit it and a deferred decision reads as shipped.

    Two namesexes are discarded and two shapes kept:

    - a file that DECLARES `verb` owns the name, so its call is its own;
    - an AMBIGUOUS name (declared by several facades) counts only where the file
      also names the facade CLASS, because that is the one spelling that picks a
      facade out of the ambiguity;
    - a UNIQUE name counts wherever it is called, since nothing else can own it.

    This cuts both ways and both cuts were measured. Dropping the bare shape
    outright was tried and reports 117 caller-less verbs, including live ones like
    `NpcApi.spawn` and `QuickUseApi.attach`, which are reached through an instance
    alias rather than a class name. A false red on a boot verb sends an agent to
    author a caller that already exists (INC-0012), so the shape stays and the
    attribution is what narrows.
    """
    if re.search(rf"^\s*(?:static\s+)?func\s+{re.escape(verb.name)}\s*\(", text, re.MULTILINE):
        return False
    if verb.cls in text:
        return True
    return verb.name not in ambiguous


def _guard_callers(guards_dir: Path, verbs: list[Verb]) -> dict[str, list[str]]:
    """ADR 0188's second keeper: verbs a COMMITTED GUARD in `tools/` depends on.

    `QuestApi.complete` is called by `tools/` and by nothing in `game/src`, and it
    is kept rather than deleted for exactly that reason: a Python gate that fails
    when the call disappears is the unique seam a committed guard needs, which is
    the second of ADR 0188's three keepers. GDScript cannot see Python, so a
    `game/tests` mention is never enough — only a `tools/` one is.
    """
    if not guards_dir.is_dir():
        return {}
    # THIS FILE IS NOT A GUARD CALLER. It names every published verb in its own
    # messages, its allowlist prose and its selftest cases, so counting itself
    # would make every verb in the tree look reached and the rule would pass
    # vacuously — the exact shape INC-0012 records. A guard that reads itself as
    # evidence is not a guard.
    #
    # The selftest is excluded for a different and honest reason: it names a verb
    # to PROVE the rule fires on it, which is not a dependency. A committed guard
    # that calls the verb in production code is a real keeper.
    self_path = Path(__file__).resolve()
    excluded = {self_path}
    excluded.update(self_path.parent.glob("*_selftest.py"))
    text_by_file = {
        path: code_only(path.read_text(encoding="utf-8", errors="replace"))
        for path in sorted(guards_dir.rglob("*.py"))
        if path.resolve() not in excluded
    }
    found: dict[str, list[str]] = {}
    for verb in verbs:
        pattern = re.compile(rf"\b{re.escape(verb.cls)}\s*\.\s*{re.escape(verb.name)}\b")
        hits = [path.as_posix() for path, text in text_by_file.items() if pattern.search(text)]
        if hits:
            found[verb.qualified] = hits
    return found


def scan(
    src: Path,
    tests: Path | None = None,
    allowlist_path: Path | None = None,
    guards_dir: Path | None = None,
) -> Report:
    """Enumerate facade verbs and measure production callers for each.

    `src`/`tests` are parameters so a fixture can be scanned without the
    repository, which is what makes this guard testable at all.
    """
    report = Report(src=src)
    facades = facade_paths(src)
    report.facades = len(facades)
    report.verbs = enumerate_verbs(facades)

    sources = script_paths(src)
    report.scanned_files = len(sources)
    bodies = {
        path: code_only(path.read_text(encoding="utf-8", errors="replace")) for path in sources
    }
    test_bodies = {
        path: code_only(path.read_text(encoding="utf-8", errors="replace"))
        for path in script_paths(tests if tests is not None else Path(""))
    }
    report.test_files = len(test_bodies)
    if allowlist_path is not None:
        report.allowlist, allow_problems = load_allowlist(allowlist_path)
        if allow_problems:
            report.allowlist = {
                **report.allowlist,
                "__problems__": AllowEntry("\n".join(allow_problems)),
            }

    # The whole tree is indexed ONCE: `name -> files naming it`, and
    # `Class.verb -> files calling it`, for production and for tests.
    name_index = _index(bodies)
    qualified_index = _qualified_index(bodies)
    test_names = _index(test_bodies)
    test_qualified = _qualified_index(test_bodies)

    ambiguous = _ambiguous_verbs(report.published)
    report.ambiguous = sorted(ambiguous)
    for verb in report.published:
        facade = Path(verb.facade)
        module_dir = facade.parent
        # The candidate set is the verb's own index entry: every file that names
        # `verb` at all, by any spelling. Only those files are re-read to decide
        # WHICH shape named it.
        candidates = sorted(name_index.get(verb.name, set()))
        direct: list[str] = []
        seam: list[str] = []
        bare = re.compile(BARE_CALL_RE.format(verb=re.escape(verb.name)))
        for path in candidates:
            body = bodies[path]
            # The declaring facade is scanned with its own headers removed, so a
            # verb cannot be credited with the line that declares it (ADR 0226: a
            # declaration is never evidence of its own reachability).
            text = _declaration_free(body) if path == facade else body
            if any(p.search(text) for p in _seam_patterns(verb.cls, verb.module, verb.name)):
                # A seam IS a caller. It is recorded separately so a human can
                # see HOW the verb is reached, but it counts: recording a live
                # wiring as a non-caller is INC-0012 exactly — it reported four
                # shipped triggers as permanently dead because its reader was not
                # shaped to see them.
                seam.append(path.as_posix())
                continue
            qualified = path in qualified_index.get(
                f"{verb.cls}.{verb.name}", set()
            ) or path in qualified_index.get(f"{verb.module}.{verb.name}", set())
            if qualified or (
                path.parent != module_dir
                and bare.search(text)
                and _bare_call_is_this_verb(text, verb, ambiguous)
            ):
                direct.append(path.as_posix())
        report.callers[verb.qualified] = sorted(set(direct))
        # The caller set is direct PLUS seam. Splitting the two is for the
        # message, not for the verdict.
        report.reached[verb.qualified] = sorted(set(direct) | set(seam))
        report.seams[verb.qualified] = sorted(set(seam))
        report.tests[verb.qualified] = sorted(
            path.as_posix()
            for path in test_bodies
            if path in test_names.get(verb.name, set())
            or path in test_qualified.get(f"{verb.cls}.{verb.name}", set())
            or path in test_qualified.get(f"{verb.module}.{verb.name}", set())
        )
    report.guards = _guard_callers(
        guards_dir if guards_dir is not None else Path("tools"), report.published
    )
    return report


def findings(report: Report) -> list[str]:
    """Each caller-less published verb that is not declared, as one actionable line."""
    out: list[str] = []
    for verb in report.caller_less():
        if verb.qualified in report.allowlist:
            continue
        tests = report.tests.get(verb.qualified) or []
        if tests:
            tail = (
                f" It is called by {len(tests)} test file(s) (e.g. {tests[0]}) and by no "
                "production file, which IS the defect: a suite that only calls itself is not "
                "reachability (ADR 0188). Add the production call site, or record the verb in "
                "tools/arch/no_caller_allowlist.json with the reason it is deliberate."
            )
        else:
            tail = (
                " No production file and no test names it, so it is inert: add the production "
                "call site, delete the verb (ADR 0188), or record it in "
                "tools/arch/no_caller_allowlist.json with a reason."
            )
        out.append(
            f"{verb.facade}:{verb.line}: {verb.qualified} is a published facade VERB with no "
            f"caller in res://src. {verb.module}/api.gd publishes it for an outside caller to "
            f"name, and nothing does — not through {verb.cls}.{verb.name}(, not through "
            f'Callable({verb.cls}, "{verb.name}"), and not through a dispatch seam.{tail}'
        )
    return out


def stale_allowlist_findings(report: Report) -> list[str]:
    """Allowlisted verbs that now HAVE a caller: the list must not describe another tree."""
    out: list[str] = []
    live = {v.qualified for v in report.published}
    for name, entry in sorted(report.allowlist.items()):
        if name == "__problems__":
            out.append(entry.reason)
            continue
        if name not in live:
            out.append(
                f"{ALLOWLIST_NAME}: {name} is declared as a deliberate caller-less verb but no "
                f"such verb exists on any facade. Remove the entry: a list that describes a "
                "different tree than the one it gates is not an escape hatch, it is a habit"
            )
        elif report.reached.get(name) or report.guards.get(name):
            where = (report.reached.get(name) or report.guards.get(name))[0]
            out.append(
                f"{ALLOWLIST_NAME}: {name} is declared caller-less but {where} calls it. The "
                "verb found its caller, so the entry is stale and hides a repaired seam"
            )
    return out


def vacuity_failures(report: Report) -> list[str]:
    """Ways this pass could have measured nothing. Each FAILS; none is a pass."""
    where = report.src.as_posix()
    if report.facades == 0:
        return [
            f"no module facade found under {where} — the scan read no `modules/*/api.gd`, so it "
            "enumerated zero verbs. A guard that scanned nothing must fail, not pass"
        ]
    problems: list[str] = []
    if report.scanned_files == 0:
        problems.append(
            f"no production source read under {where} — every verb would read as having no "
            "caller, so this pass can only be wrong"
        )
    if not report.verbs:
        problems.append(
            f"{report.facades} facade(s) read and no verb found in any of them: either the "
            "reader no longer parses GDScript or the facades publish nothing. Either way the "
            "pass is vacuous and fails rather than reporting ok"
        )
    elif not report.published:
        problems.append(
            f"{len(report.verbs)} verb(s) enumerated across {report.facades} facade(s) and none "
            "is public: the population this guard grades has vanished, which is a change to the "
            "shape, not a clean tree"
        )
    return problems


def evaluate(
    src: Path,
    tests: Path | None = None,
    allowlist_path: Path | None = None,
    guards_dir: Path | None = None,
) -> tuple[list[str], Report]:
    """Return `(problems, report)`. Empty `problems` is the only clean verdict."""
    report = scan(src, tests, allowlist_path, guards_dir)
    problems = [*vacuity_failures(report), *findings(report), *stale_allowlist_findings(report)]
    return problems, report


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "no_caller_verbs", help="fail a published facade VERB that no production code calls"
    )
    parser.add_argument(
        "--src", default=None, help="the directory res://src maps to (default: game/src)"
    )
    parser.add_argument(
        "--allowlist",
        default=None,
        help=f"the declared exception list (default: tools/arch/{ALLOWLIST_NAME})",
    )


def run(args) -> int:
    """`uv run python -m tools no_caller_verbs` — the standalone entry point.

    `tools arch` runs the same `evaluate()` in-process; this exists so the guard
    can be pointed at a fixture tree from the command line.
    """
    from ..common import SRC_DIR, TESTS_DIR, fail, ok

    src = Path(args.src) if args.src else SRC_DIR
    allow = (
        Path(args.allowlist) if args.allowlist else Path(__file__).resolve().parent / ALLOWLIST_NAME
    )
    problems, report = evaluate(src, TESTS_DIR, allow, Path(__file__).resolve().parents[1])
    for problem in problems:
        fail(problem)
    if problems:
        return 1
    ok(
        f"no-caller verbs ok ({report.facades} facades, {len(report.published)} published verbs, "
        f"{len(report.caller_less())} caller-less with {len(report.allowlist)} declared, "
        f"{report.scanned_files} production files read, {report.test_files} test files read)"
    )
    return 0


# --- Red paths ---------------------------------------------------------------
#
# A green guard is an untested guard (INC-0016). Every case asserts a RED verdict,
# because "the guard passes on today's tree" is what `tools check` already does
# and proves nothing. Registered through `selftest.case`, so adding the guard
# without its red paths shows up as a missing case rather than as silence.

_REGISTERED = False


def _fixture(root, write, module="quest", cls="QuestApi", body="", extra=()):
    """One module facade publishing `body`, plus optional sibling production files."""
    facade = write(
        root / "src" / "modules" / module / "api.gd",
        f"class_name {cls}\nextends RefCounted\n\n{body}",
    )
    for rel, text in extra:
        write(root / rel, text)
    return facade


def register_selftest_cases(case, expect, write) -> None:
    """Attach the guard's red paths to the `selftest` harness.

    Imported lazily by `selftest_cases.py`, which owns the harness; importing
    `case`/`expect` at module scope would be a cycle (`selftest` -> `arch` ->
    this module), so the harness passes its own decorators in.
    """
    global _REGISTERED  # noqa: PLW0603 - registration happens exactly once
    if _REGISTERED:
        return
    _REGISTERED = True

    PUBLISHED = (
        "static func complete(actor, quest_id) -> Dictionary:\n\treturn {}\n\n\n"
        "static func offered(actor) -> Array[Dictionary]:\n\treturn []\n"
    )

    @case("no_caller_verbs: a published VERB with NO production caller FAILS")
    def _caller_less_fails() -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            _fixture(root, write, body=PUBLISHED)
            write(
                root / "tests" / "test_quest.gd",
                "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n",
            )
            problems, report = evaluate(root / "src", root / "tests")
            expect(
                any("QuestApi.complete" in p for p in problems),
                f"a published facade VERB that no production file calls was accepted: "
                f"{problems!r}. That is the shape BL-0907 found six times",
            )
            expect(
                len(report.published) == 2,
                f"the fixture enumerated {len(report.published)} published verbs, expected 2, so "
                "the case is not testing what it claims",
            )
            expect(
                not any("QuestApi.offered" in p for p in problems),
                f"the second fixture verb was reported too, which means the case cannot tell "
                "the two verbs apart: {problems!r}",
            )

    @case("no_caller_verbs: a TEST-only caller does not clear a verb")
    def _test_only_caller_fails() -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            _fixture(root, write, body=PUBLISHED)
            write(
                root / "tests" / "test_quest.gd",
                'extends TestCase\n\n\nfunc it() -> void:\n\tQuestApi.complete(null, &"q")\n',
            )
            problems, _ = evaluate(root / "src", root / "tests")
            expect(
                any("QuestApi.complete" in p for p in problems),
                f"a verb reached only from res://tests was accepted: {problems!r}. A suite that "
                "calls itself is the defect restated, not an exemption (ADR 0188)",
            )

    @case("no_caller_verbs: a Callable seam IS a caller")
    def _callable_seam_counts() -> None:
        """The false-positive direction (INC-0012). How this repo wires EVERY seam."""
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            _fixture(root, write, body=PUBLISHED)
            write(
                root / "src" / "app" / "quest_boot.gd",
                "extends Node\n\n\nfunc _install() -> void:\n"
                '\tWorldStage.set_commit(Callable(QuestApi, "complete"))\n',
            )
            write(root / "tests" / "t.gd", "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n")
            problems, report = evaluate(root / "src", root / "tests")
            expect(
                not any("QuestApi.complete" in p for p in problems),
                f'a verb wired through Callable(Api, "name") was reported dead: {problems!r}. '
                "That is INC-0012 in a new coat — it sends an agent to author a caller that "
                "already exists",
            )
            expect(
                report.seams.get("QuestApi.complete"),
                "the fixture did not register the seam, so the pass above would be vacuous",
            )
            expect(
                report.reached.get("QuestApi.complete"),
                "the seam was not counted as a CALLER, which is INC-0012 in a new coat: a live "
                "wiring recorded as a non-caller sends an agent to author a caller that exists",
            )

    @case("no_caller_verbs: a ui/ screen IS a production caller")
    def _ui_caller_counts() -> None:
        """`ui/` may reach a module ONLY through `api.gd`, so naming the facade IS the sanctioned path."""
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            _fixture(root, write, body=PUBLISHED)
            write(
                root / "src" / "ui" / "screens" / "quest_screen.gd",
                "extends Control\n\n\nfunc _commit() -> void:\n"
                '\tprint(QuestApi.complete(_actor, &"first_light"))\n',
            )
            write(root / "tests" / "t.gd", "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n")
            problems, _ = evaluate(root / "src", root / "tests")
            expect(
                not problems,
                f"a verb a screen calls through the facade was reported dead: {problems!r}. "
                "ui/ reaching a module only through api.gd is the RULE, not a violation",
            )

    @case("no_caller_verbs: a declaration is not a caller of ITSELF")
    def _declaration_is_not_a_caller() -> None:
        """ADR 0226: a declaration is never evidence of its own reachability.

        `static func complete(` contains the name, so a scan of the raw file credits
        every verb with itself and the guard can never report anything.
        """
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            _fixture(root, write, body=PUBLISHED)
            write(root / "tests" / "t.gd", "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n")
            problems, report = evaluate(root / "src", root / "tests")
            expect(
                not report.callers.get("QuestApi.complete"),
                "a verb's own `static func` header was counted as its caller, so this guard is "
                "structurally incapable of reporting anything",
            )
            expect(
                any("QuestApi.complete" in p for p in problems),
                f"the self-credit made a caller-less verb read as clean: {problems!r}",
            )

    @case("no_caller_verbs: a COMMENT naming a verb is not a caller")
    def _comment_is_not_a_caller() -> None:
        """ADR 0188's last clause. The bug this guard shipped with the first time."""
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            _fixture(
                root,
                write,
                module="anchor",
                cls="AnchorApi",
                body="static func complete(actor) -> Dictionary:\n\treturn {}\n",
                extra=[
                    (
                        "src/modules/anchor/other.gd",
                        "extends RefCounted\n\n\n## see AnchorApi.complete for the reason\n"
                        "static func _leave(actor) -> void:\n\tpass\n",
                    )
                ],
            )
            write(root / "tests" / "t.gd", "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n")
            problems, report = evaluate(root / "src", root / "tests")
            expect(
                not report.callers.get("AnchorApi.complete"),
                "a comment naming the verb was counted as a caller, so this guard could never "
                "report anything",
            )
            expect(
                any("AnchorApi.complete" in p for p in problems),
                f"a verb named only in another file's COMMENT was accepted: {problems!r}. Prose "
                "about a verb is not a call to it",
            )

    @case("no_caller_verbs: an ALLOWLIST entry with a reason is honoured")
    def _allowlist_honours_a_reason() -> None:
        """The escape hatch has to be reachable, or a deliberate verb is unreportable forever."""
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            _fixture(root, write, body=PUBLISHED)
            write(root / "tests" / "t.gd", "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n")
            allow = write(
                root / "allow.json",
                '{"entries": {"QuestApi.complete": {"reason": "DEF-0315: the moment that '
                'settles a verdict does not ship yet", "ticket": "DEF-0315"}}}\n',
            )
            problems, report = evaluate(root / "src", root / "tests", allow)
            expect(
                "QuestApi.complete" in report.allowlist,
                "the declared entry was not loaded, so the pass below proves nothing",
            )
            expect(
                not any("QuestApi.complete" in p for p in problems),
                f"a declared caller-less verb with a reason was still reported: {problems!r}. A "
                "guard with no way to record a deliberate exception gets deleted",
            )
            expect(
                any("QuestApi.offered" in p for p in problems),
                f"the allowlist suppressed a verb it never named: {problems!r}. The list must be "
                "exact-keyed; a wildcard is the blanket waiver it exists to avoid",
            )

    @case("no_caller_verbs: an allowlist entry with NO reason is refused")
    def _allowlist_requires_a_reason() -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            _fixture(root, write, body=PUBLISHED)
            write(root / "tests" / "t.gd", "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n")
            allow = write(root / "allow.json", '{"entries": {"QuestApi.complete": {}}}\n')
            problems, _ = evaluate(root / "src", root / "tests", allow)
            expect(
                any("carries no reason" in p for p in problems),
                f"an entry with no reason was accepted: {problems!r}. An unexplained exception "
                "is the waiver this list exists to prevent",
            )

    @case("no_caller_verbs: a STALE allowlist entry FAILS")
    def _stale_allowlist_fails() -> None:
        """Otherwise the list grows forever and describes a different tree than it gates."""
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            _fixture(root, write, body=PUBLISHED)
            write(
                root / "src" / "app" / "quest_boot.gd",
                'extends Node\n\n\nfunc _install() -> void:\n\tQuestApi.complete(null, &"q")\n',
            )
            write(root / "tests" / "t.gd", "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n")
            allow = write(
                root / "allow.json",
                '{"entries": {"QuestApi.complete": {"reason": "was deliberate"}}}\n',
            )
            problems, _ = evaluate(root / "src", root / "tests", allow)
            expect(
                any("stale" in p for p in problems),
                f"an entry whose verb has since found a caller was silently accepted: {problems!r}. "
                "A list that cannot notice its own staleness stops being an exception",
            )

    @case("no_caller_verbs: a tree with NO FACADES FAILS LOUDLY, never passes vacuously")
    def _no_facades_fails_loudly() -> None:
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
                f"a tree with zero facades was reported clean: {problems!r}. A guard that scanned "
                "nothing must FAIL, not pass",
            )

    @case("no_caller_verbs: a NAMESECKE bare call does NOT clear the verb")
    def _namesake_does_not_clear() -> None:
        """The false-GREEN direction, and the one that would have made this decorative.

        `mods/mod_manifest.gd` declares its own `func events(` and `mods/mod_loader.gd`
        calls it, while `EventApi.events` is the event BUS with no subscriber. A bare
        `events(` accepted anywhere credits the two, and the one true positive BL-0907
        calls "real consequences" passes clean. The same holds for `EventApi.resolve`
        against `owner_resolver.gd`'s own `resolve`.
        """
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            _fixture(
                root,
                write,
                module="event",
                cls="EventApi",
                body="static func events() -> WorldEvents:\n\treturn WorldEvents.new()\n",
            )
            # A DIFFERENT module that declares its own `events(` and calls it.
            _fixture(
                root,
                write,
                module="mods",
                cls="ModsApi",
                body="static func events(source_path: String) -> Array:\n\treturn []\n",
                extra=[
                    (
                        "src/modules/mods/mod_loader.gd",
                        "extends RefCounted\n\n\nstatic func _read(manifest) -> void:\n"
                        '\tprint(ModsApi.events("mods/x.json"))\n',
                    )
                ],
            )
            write(root / "tests" / "t.gd", "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n")
            problems, report = evaluate(root / "src", root / "tests")
            expect(
                any("EventApi.events" in p for p in problems),
                f"a namesake bare call cleared the verb: {problems!r}. `mods` declaring its "
                "own `events(` says nothing about the event BUS, which is exactly the false "
                "green that leaves this guard decorative",
            )
            expect(
                not any("ModsApi.events" in p for p in problems),
                f"the namesake's own verb was reported too, so the case cannot tell the two "
                f"apart: {problems!r}",
            )
            expect(
                not report.reached.get("EventApi.events"),
                "the namesake was still credited as a caller, so the guard cannot report it",
            )

    @case("no_caller_verbs: a verb a COMMITTED GUARD names is KEPT (ADR 0188 clause 2)")
    def _committed_guard_keeps_a_verb() -> None:
        """`QuestApi.complete` is called by `tools/` and by no production file.

        It is kept for the second of ADR 0188's three reasons — "it is the unique
        seam a committed guard needs" — and `game/tests` can never evidence that,
        because GDScript cannot see Python.
        """
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            _fixture(root, write, body=PUBLISHED)
            write(root / "tests" / "t.gd", "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n")
            guards = write(
                root / "tools" / "data.py",
                'ROUTES = [("quest", "res://src/modules/quest/api.gd", ["complete"], '
                '["src/app/quest_program.gd"]), ("quest", "other", ["offered"], ["src/app/x.gd"])]\n',
            )
            problems, report = evaluate(root / "src", root / "tests", None, guards)
            expect(
                report.guards.get("QuestApi.complete"),
                "the fixture's committed guard naming the verb was not registered, so the pass "
                "below would be vacuous",
            )
            expect(
                not any("QuestApi.complete" in p for p in problems),
                f"a verb a committed guard depends on was reported dead: {problems!r}. ADR 0188 "
                "keeps a member that is the unique seam a committed guard needs, and deleting it "
                "would break the gate that names it",
            )
            expect(
                any("QuestApi.offered" in p for p in problems),
                f"the guard keeper swallowed a verb it never named: {problems!r}. The keeper is "
                "exact-keyed like the allowlist",
            )

    @case("no_caller_verbs: a dispatch seam (.call / has_signal) IS a caller")
    def _dispatch_seam_counts() -> None:
        """The StringName indirection, which INC-0012 also names."""
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            _fixture(root, write, body=PUBLISHED)
            write(
                root / "src" / "app" / "bus.gd",
                "extends Node\n\n\nvar _sink := QuestApi\n\n\nfunc _go() -> void:\n"
                '\t_sink.call("complete")\n\tprint(_sink.has_signal("offered"))\n',
            )
            write(root / "tests" / "t.gd", "extends TestCase\n\n\nfunc it() -> void:\n\tpass\n")
            problems, report = evaluate(root / "src", root / "tests")
            expect(
                not any("QuestApi.complete" in p for p in problems),
                f"a verb reached through a dispatch seam was reported dead: {problems!r}. A "
                "StringName lookup is a real call",
            )
            expect(
                report.seams.get("QuestApi.complete"),
                "the fixture did not register the seam, so the pass above would be vacuous",
            )


__all__ = [
    "ALLOWLIST_NAME",
    "AllowEntry",
    "Report",
    "Verb",
    "code_only",
    "enumerate_verbs",
    "evaluate",
    "facade_paths",
    "findings",
    "load_allowlist",
    "register",
    "register_selftest_cases",
    "run",
    "scan",
    "stale_allowlist_findings",
    "vacuity_failures",
]
