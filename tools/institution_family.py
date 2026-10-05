"""Every declared content family and every content root a mod registers — checked, not assumed.

## What this closes (ADR 0184 §9 and its acceptance criterion)

ADR 0184 requires that `tools check` gates "key off the module+family registry, or loudly
exempt — **never silently pass unknown content**", and its acceptance criterion says "an
unrecognized family fails loudly". Neither half shipped. Measured before this module:

1. **`unknown_family` passed silently.** `families.json` declared 48 families and nothing
   verified a mod's `content_roots[].family` against that list. `_wire_content_roots` in
   `app/item_workbench_body.gd` hardcodes eight families and its `_:` arm only records the
   offender in `_unwired_families` with a `push_warning` — so a mod shipping a ninth
   organization's content was announced, ignored, and green.
2. **`undeclared_root` passed silently.** `ModLoader._stamp_context` plays every
   `content_roots[]` row straight through `RegistrationContext.add_content_root`, and the
   seam takes any `family`/`dir` it is handed. Nothing compared a declared root against
   the mod's own directory, so a manifest could claim content anywhere.
3. **`module` was an unchecked comment.** It is read in exactly ONE place
   (`tools/cultivation/audit.py:389`, and only for a row carrying `path`, where it
   resolves `game/src/modules/<module>/provider.gd`). Nothing checked it — and the one
   stale value it already had, `"unique_characters"` on `portraits`, named **no directory
   at all**: `PortraitDef` lives in `core/portrait_def.gd` and there has never been a
   `modules/unique_characters/`. That is a row lying about its owner, which is why a
   `core`-owned family now simply OMITS the key and the key is verified when present.

## The refusals, each with a name

| reason | fires when |
|---|---|
| `unknown_family` | a mod declares a family `families.json` does not |
| `undeclared_root` | a mod declares a content root outside its own directory |
| `unknown_module` | a family row's `module` names no directory under `game/src/modules/` |
| `missing_data_dir` | a family row declares no `data_dir` |

`unknown_module` exists to make the ABSENCE of `module` load-bearing rather than merely
tidy: with the key verified, `"module": "core"` on `institutions` would be refused, so
the honest row and the lying row are distinguishable by the gate instead of by a reader.

## Loop safety

Every loop here is a `for` over a materialised, `sorted()` sequence — a directory walk
(`Path.rglob`) or a dict's keys — with no bound computed from a container the body grows.
There is no `while` in this module. `rglob` is bounded by the tree and skips `.godot/`,
which is the generated import cache (AGENTS.md) and the one directory under `game/` large
enough to matter.

    uv run python -m tools institution_family check     # non-zero on any finding
    uv run python -m tools institution_family report    # same findings, exit 0

## Why the red paths live in THIS module

A Python guard is unreachable from the GDScript suite, so nothing asserts it still goes
RED unless its cases are loaded (INC-0016) — and the repo's own answer for a busy shared
case file (`selftest_cases.py`) is a separate module that something must import.
`tools/check.py` imports this module to run the gate, so the cases below register on the
same import that makes the gate reachable. A gate and its proof that can drift apart in
the loader are the INC-0016 shape; keeping them in one file removes the possibility.

## Loops in the red-path cases

The cases write their fixtures with `tempfile` and never touch the repository. There is
no `while` in them either; `iterdir()` is drained by a `for`.
"""

from __future__ import annotations

import json
import tempfile
from pathlib import Path

from .common import REPO_ROOT, ToolError, fail, ok, warn
from .selftest import case, expect, write

## ## Reasons. Named constants, not inline strings.
##
## A finding is a refusal and a refusal is a name (ADR 0083's third state), so a caller
## can branch on the cause without matching prose. Kept as a tuple as well so
## [function run] can report which reasons it has seen without a second list.
R_UNKNOWN_FAMILY = "unknown_family"
R_UNDECLARED_ROOT = "undeclared_root"
R_UNKNOWN_MODULE = "unknown_module"
R_MISSING_DATA_DIR = "missing_data_dir"

REASONS: tuple[str, ...] = (
    R_UNKNOWN_FAMILY,
    R_UNDECLARED_ROOT,
    R_UNKNOWN_MODULE,
    R_MISSING_DATA_DIR,
)

## Where the module directories a family's `module` may name actually live. `core` is a
## LAYER and deliberately absent: `game/src/modules/core` does not exist and must not.
MODULES_DIR = REPO_ROOT / "game" / "src" / "modules"

## Generated import cache. The one directory under `game/` large enough that walking it
## would cost more than the check itself, and it holds no authored content.
SKIP_DIRS = frozenset({".godot", ".git", ".venv", "__pycache__", ".ruff_cache", "build"})

## ## The manifest key a mod declares its content roots under.
ROOTS_KEY = "content_roots"

## ## SEAM_ALIASES: the LOUD EXEMPTION, and the vocabulary split it records
##
## Measured on the shipped tree before this module existed: **five of the eight families
## `_wire_content_roots` actually wires are spelled differently here than there.**
##
## | seam name the runtime matches | family declared in `families.json` |
## |---|---|
## | `quest`  | `quests`   |
## | `event`  | `events`   |
## | `world`  | `world_locations` |
## | `npc`    | `npcs`     |
## | `race`   | `races`    |
##
## (`items`, `techniques` and `elements` agree, which is why the split went unnoticed for
## as long as it did.) The shipped fixture `w8_third_party_data` ships a `world` root and
## is a live instance of the mismatch, not a hypothetical one.
##
## **ADR 0184 §9 permits exactly one alternative to failing: "or loudly exempt".** So the
## exemption is declared here, mapped to the family each seam stands for rather than
## listed bare, and **every exemption consumed is reported on every run** — so this is a
## printed allowance a reviewer can see and shrink, never a silent pass. A bare
## `("world", "npc", "race", "quest", "event")` allowlist would hide the correspondence
## that is the whole finding.
##
## **What is NOT exempted is everything else.** An invented family still refuses with a
## non-zero exit, which is the acceptance criterion, and the red-path case proves it.
##
## The vocabulary is not reconciled here: doing so needs either an edit under `app/`
## (held by another session) or a rename in this file that `tools/data.py` and
## `tools/cultivation/audit.py` both key off. Recorded in `docs/deferred.jsonl`.
SEAM_ALIASES: dict[str, str] = {
    "quest": "quests",
    "event": "events",
    "world": "world_locations",
    "npc": "npcs",
    "race": "races",
}


# --- The family declaration ----------------------------------------------------


def load_families(families_path: Path) -> dict[str, dict]:
    """The declared families, or `{}` when the file is absent.

    An absent declaration is reported by [function findings] rather than treated as "no
    families, therefore nothing to check" — that reading is the silent pass this module
    exists to delete.
    """
    if not families_path.is_file():
        return {}
    return json.loads(families_path.read_text(encoding="utf-8")).get("families", {})


def find_mod_manifests(game_dir: Path) -> list[Path]:
    """Every `mod.json` under `game/`, sorted, skipping generated directories.

    The widest safe superset of what `ModLoader.discover` will be pointed at: a mod
    parked outside the roots the game currently mounts is still a mod whose manifest is
    wrong, and finding it costs one directory walk.
    """
    found: list[Path] = []
    for path in game_dir.rglob("mod.json"):
        if any(part in SKIP_DIRS for part in path.relative_to(game_dir).parts[:-1]):
            continue
        found.append(path)
    found.sort()
    return found


def _is_inside(child: Path, parent: Path) -> bool:
    """Whether `child` resolves to `parent` or something beneath it.

    Resolved before comparing, so a `dir` of `../../elsewhere` cannot pass as being
    inside the mod by spelling alone. `relative_to` raises rather than returning False,
    which is the containment test.
    """
    try:
        child.resolve().relative_to(parent.resolve())
    except ValueError:
        return False
    return True


def _family_findings(families: dict[str, dict]) -> list[str]:
    """Whether each declared family is well formed and, when it names a module, TRUE."""
    findings: list[str] = []
    for name in sorted(families):
        info_row = families[name]
        if not isinstance(info_row, dict):
            findings.append(f"{R_MISSING_DATA_DIR}: family '{name}' is not an object")
            continue
        if not str(info_row.get("data_dir", "")).strip():
            findings.append(f"{R_MISSING_DATA_DIR}: family '{name}' declares no 'data_dir'")
        # `module` is OPTIONAL, and its absence is meaningful rather than incomplete: a
        # `core`-owned family has no module to name (ADR 0278, `institutions`). So this
        # checks only that a name which IS given resolves, which is what makes omitting
        # the key the honest option rather than merely a defensible one.
        module = str(info_row.get("module", "")).strip()
        if module and not (MODULES_DIR / module).is_dir():
            findings.append(
                f"{R_UNKNOWN_MODULE}: family '{name}' names module '{module}', "
                f"which is no directory under game/src/modules"
            )
    return findings


def _mod_findings(manifest_path: Path, families: dict[str, dict]) -> tuple[list[str], list[str]]:
    """Whether one manifest declares only known families and only its OWN content.

    Returns `(findings, exemptions)`. The exemptions are the seams this manifest consumed
    out of `SEAM_ALIASES`, so [function run] can print every allowance it spent — an
    exemption nobody is told about is a silent pass wearing a comment.
    """
    findings: list[str] = []
    exemptions: list[str] = []
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        # A malformed manifest is `ModManifest.parse`'s `not_json` refusal at runtime.
        # Reported here as its own line rather than guessed at, so this gate never
        # becomes the place a JSON error is swallowed.
        return ([f"not_json: {manifest_path.name}: {exc}"], exemptions)
    if not isinstance(manifest, dict):
        return (findings, exemptions)
    mod_root = manifest_path.parent
    mod_id = str(manifest.get("id", mod_root.name))
    roots = manifest.get(ROOTS_KEY, [])
    if not isinstance(roots, list):
        return (
            [f"bad_{ROOTS_KEY}: mod '{mod_id}' declares {ROOTS_KEY} that is not an array"],
            exemptions,
        )
    for row in roots:
        if not isinstance(row, dict):
            findings.append(f"bad_{ROOTS_KEY}: mod '{mod_id}' has a non-object root entry")
            continue
        family = str(row.get("family", ""))
        if family not in families:
            seam = SEAM_ALIASES.get(family)
            # The exemption only speaks when the family it stands for is ITSELF declared,
            # so the allowance cannot outlive the family it was written for.
            if seam is not None and seam in families:
                exemptions.append(
                    f"exempt: mod '{mod_id}' declares seam '{family}', exempted as "
                    f"'{seam}' (the declared family the runtime seam name stands for)"
                )
            else:
                # The headline refusal: content shipped into a family no gate grades.
                findings.append(
                    f"{R_UNKNOWN_FAMILY}: mod '{mod_id}' declares family '{family}', "
                    f"which tools/arch/families.json does not"
                )
        declared_dir = str(row.get("dir", ""))
        if declared_dir:
            # A relative `dir` is authored AGAINST THE MOD'S OWN DIRECTORY, which is how
            # `ModLoader._stamp_context` plays it into `add_content_root`. Resolving it
            # against the process CWD instead would refuse every well-formed manifest.
            declared = Path(declared_dir)
            target = declared if declared.is_absolute() else (mod_root / declared)
            if not _is_inside(target, mod_root):
                # ADR 0184: "A mod registering content outside its declared family roots is
                # refused." The declared root must live inside the mod's own directory, so a
                # manifest cannot claim a sibling's tree or the base game's.
                findings.append(
                    f"{R_UNDECLARED_ROOT}: mod '{mod_id}' declares family '{family}' at "
                    f"'{declared_dir}', which resolves outside its own root {mod_root.name}"
                )
    return (findings, exemptions)


def findings(
    families: dict[str, dict],
    manifests: list[Path],
) -> list[str]:
    """Every refusal across the family declaration and every mod manifest.

    Two `for`s over lists built before the call and never appended to inside a loop, so
    there is no bound here a body could grow in lockstep with.
    """
    out: list[str] = _family_findings(families)
    for manifest in manifests:
        out.extend(_mod_findings(manifest, families)[0])
    return out


def exemptions(
    families: dict[str, dict],
    manifests: list[Path],
) -> list[str]:
    """Every seam exemption consumed, which [function report] prints every run."""
    out: list[str] = []
    for manifest in manifests:
        out.extend(_mod_findings(manifest, families)[1])
    return out


def report(causes: list[str], waived: list[str], strict: bool) -> int:
    """Print the causes and any exemption spent, and return the exit code.

    Every exemption is printed whether or not anything failed. That is the difference
    between ADR 0184's "loudly exempt" and a quiet allowlist: an allowance that only
    appears when something else breaks is not loud.
    """
    for entry in waived:
        warn(entry)
    if not causes:
        ok(
            "every declared family is well formed and every mod root is inside its mod"
            + (f" ({len(waived)} seam exemption(s) spent)" if waived else "")
        )
        return 0
    for cause in causes:
        fail(cause)
    message = (
        f"{len(causes)} content-family finding(s); a family no gate grades is content nobody reads"
    )
    if strict:
        fail(message)
        return 1
    warn(message + " (pass --strict to fail, or use the `check` action)")
    return 0


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "institution-family", help="declared content families and mod content roots"
    )
    parser.add_argument(
        "--strict", action="store_true", help="exit non-zero on any finding (default: report)"
    )
    actions = parser.add_subparsers(dest="action", required=True)
    actions.add_parser("check", help="report every finding and exit non-zero on any")
    actions.add_parser("report", help="report every finding and exit 0")


def run(args) -> int:
    action = getattr(args, "action", "check")
    if action not in ("check", "report"):
        raise ToolError(f"unknown action {action}")
    families = load_families(REPO_ROOT / "tools" / "arch" / "families.json")
    manifests = find_mod_manifests(REPO_ROOT / "game")
    strict = action == "check" or getattr(args, "strict", False)
    return report(findings(families, manifests), exemptions(families, manifests), strict)


# --- Red paths (INC-0016) ------------------------------------------------------
#
# Each case breaks ONE thing and asserts that this module still says so. A happy-path
# case would prove nothing: `tools check` already runs the guard on today's tree every
# time. What matters is that a loosened rule is caught, so every case below builds a
# fixture in a temporary directory, points the guard at it, and asserts the named cause
# appears. The final case asserts a COMPLIANT manifest produces nothing, so the rules
# discriminate rather than reject everything.


def _families_json(dir_path: Path, families: dict[str, dict]) -> Path:
    path = dir_path / "families.json"
    write(path, json.dumps({"version": 1, "roots": {"data": "game/data"}, "families": families}))
    return path


def _manifest(dir_path: Path, mod_id: str, roots: list[dict], **extra) -> Path:
    payload = {
        "id": mod_id,
        "version": "1.0.0",
        "priority": 0,
        "requires_api": 1,
        "content_roots": roots,
        **extra,
    }
    return write(dir_path / "mod.json", json.dumps(payload))


@case("institution_family: a mod declaring a family families.json does not know is REFUSED by name")
def _unknown_family_is_refused() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        _families_json(root, {"items": {"data_dir": "items", "def_class": "ItemDef"}})
        mod = root / "mods" / "guild_pack"
        _manifest(mod, "guild_pack", [{"family": "guilds", "dir": "./content"}])
        causes = findings(load_families(root / "families.json"), find_mod_manifests(root))
        expect(
            any(R_UNKNOWN_FAMILY in cause and "guilds" in cause for cause in causes),
            f"a mod shipping content into an undeclared family passed silently; got {causes!r}. "
            "This is the ADR 0184 acceptance criterion: an unrecognized family fails loudly.",
        )


@case("institution_family: a mod declaring content OUTSIDE its own roots is REFUSED by name")
def _undeclared_root_is_refused() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        _families_json(
            root, {"institutions": {"data_dir": "institutions", "def_class": "InstitutionDef"}}
        )
        mod = root / "mods" / "guild_pack"
        # A KNOWN family, so this case cannot pass by reusing the unknown-family refusal.
        _manifest(mod, "guild_pack", [{"family": "institutions", "dir": "../other_mod/content"}])
        causes = findings(load_families(root / "families.json"), find_mod_manifests(root))
        expect(
            any(R_UNDECLARED_ROOT in cause and "guild_pack" in cause for cause in causes),
            f"a mod claiming a sibling's content tree passed silently; got {causes!r}. "
            "ADR 0184: content outside a mod's declared roots is refused.",
        )


@case("institution_family: a root that merely LOOKS inside the mod is still REFUSED")
def _traversing_root_is_refused() -> None:
    """The negative case the first one cannot express.

    `../other_mod/content` does not spell an absolute path outside the mod, so a checker
    comparing strings rather than resolved paths would pass it. This asserts the resolved
    containment test, which is the one that holds.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        _families_json(
            root, {"institutions": {"data_dir": "institutions", "def_class": "InstitutionDef"}}
        )
        mod = root / "mods" / "guild_pack"
        (root / "mods" / "other_mod").mkdir(parents=True, exist_ok=True)
        _manifest(
            mod,
            "guild_pack",
            [{"family": "institutions", "dir": "../other_mod/content"}],
        )
        causes = findings(load_families(root / "families.json"), find_mod_manifests(root))
        expect(
            any(R_UNDECLARED_ROOT in cause for cause in causes),
            f"a traversing root resolved inside its mod; got {causes!r}.",
        )


@case("institution_family: a family naming a module that does not exist is REFUSED")
def _stale_module_is_refused() -> None:
    """The refusal that already fired once on the shipped tree.

    `portraits` declared `"module": "unique_characters"` while `PortraitDef` lives in
    `core/` and no `modules/unique_characters/` has ever existed. Nothing checked it, so
    a row could lie about its owner indefinitely. With this refusal the honest answer
    (omit the key) and the lying one (name a layer) are distinguishable by the gate.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        (root / "modules").mkdir(parents=True, exist_ok=True)
        families = {
            "portraits": {"data_dir": "portraits", "def_class": "PortraitDef", "module": "core"}
        }
        causes = _family_findings(families)
        expect(
            any(R_UNKNOWN_MODULE in cause and "'core'" in cause for cause in causes),
            f"a family naming the core LAYER as its module passed; got {causes!r}. "
            "`core` is a layer, not a module, and game/src/modules/core does not exist.",
        )


@case("institution_family: a core-owned family that OMITS module is NOT refused")
def _absent_module_is_quiet() -> None:
    """The negative case for the row above, and the shape `institutions` ships in.

    Without this, a guard that fails on every family would pass the positive case while
    being useless — it would send an agent to invent a module for the generic def.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        (root / "modules").mkdir(parents=True, exist_ok=True)
        families = {"institutions": {"data_dir": "institutions", "def_class": "InstitutionDef"}}
        causes = _family_findings(families)
        expect(
            not causes,
            f"a core-owned family that admits it has no module was refused anyway; got {causes!r}. "
            "`institutions` has no module because its machinery is in core/, and saying so "
            "is the honest row.",
        )


@case("institution_family: a compliant manifest is NOT refused")
def _compliant_manifest_is_quiet() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        _families_json(
            root,
            {"institutions": {"data_dir": "institutions", "def_class": "InstitutionDef"}},
        )
        mod = root / "mods" / "guild_pack"
        _manifest(mod, "guild_pack", [{"family": "institutions", "dir": "./content"}])
        causes = findings(load_families(root / "families.json"), find_mod_manifests(root))
        expect(not causes, f"a well-formed mod was refused anyway; got {causes!r}.")


@case("institution_family: a family declaring no data_dir is REFUSED")
def _missing_data_dir_is_refused() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        _families_json(root, {"ghost": {"def_class": "GhostDef"}})
        causes = _family_findings(load_families(root / "families.json"))
        expect(
            any(R_MISSING_DATA_DIR in cause and "ghost" in cause for cause in causes),
            f"a family with no data_dir — and therefore no content for any gate to grade — "
            f"passed; got {causes!r}.",
        )


@case("institution_family: the seam exemption is LOUD and never swallows an invented family")
def _exemption_is_narrow_and_reported() -> None:
    """The case that keeps the exemption from becoming an allowlist.

    `world` is exempt because `world_locations` is declared; `guilds` is exempt because
    nothing. This asserts both halves at once — the real seam is allowed AND reported,
    and a name beside it in the same manifest still refuses.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        _families_json(
            root,
            {"world_locations": {"data_dir": "world/locations", "def_class": "WorldLocationDef"}},
        )
        mod = root / "mods" / "guild_pack"
        _manifest(
            mod,
            "guild_pack",
            [
                {"family": "world", "dir": "./world"},
                {"family": "guilds", "dir": "./guilds"},
            ],
        )
        families = load_families(root / "families.json")
        manifests = find_mod_manifests(root)
        causes, waived = _mod_findings(manifests[0], families)
        expect(
            len(waived) == 1 and "'world'" in waived[0] and "world_locations" in waived[0],
            f"the declared seam was not exempted-and-reported; waived={waived!r}.",
        )
        expect(
            any(R_UNKNOWN_FAMILY in cause and "guilds" in cause for cause in causes),
            f"an invented family rode in on the same manifest as an exempt one; "
            f"got {causes!r}. An exemption is per-name and reported, never a blanket.",
        )


@case("institution_family: an exemption whose family is NOT declared does NOT apply")
def _orphan_exemption_does_not_apply() -> None:
    """The exemption must not outlive the family it was written for.

    `world` stays in `SEAM_ALIASES` because `world_locations` is declared. If that family
    were ever renamed, the allowance has to die with it rather than keep exempting a name
    no gate grades — which is the failure mode a bare allowlist has.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        _families_json(root, {"items": {"data_dir": "items", "def_class": "ItemDef"}})
        mod = root / "mods" / "guild_pack"
        _manifest(mod, "guild_pack", [{"family": "world", "dir": "./world"}])
        families = load_families(root / "families.json")
        causes, waived = _mod_findings(find_mod_manifests(root)[0], families)
        expect(not waived, f"an orphan exemption still applied; waived={waived!r}.")
        expect(
            any(R_UNKNOWN_FAMILY in cause and "'world'" in cause for cause in causes),
            f"a seam with no declared family was exempt anyway; got {causes!r}.",
        )
