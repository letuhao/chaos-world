"""Drive a domain headlessly over a JSONL transcript (ADR 0231, ADR 0232).

The driver reads the domain through the same seam a screen drives
(`DomainBoot.bridge()` / `DomainApi` / `DomainRunApi`), so a transcript is a thing a
player could also play. Every event carries `event`, `seed` and `template_id`, so a defect
report is `--seed N --template <id> --cmd ...` and nothing else.

`templates` and every argument check are engine-free. `drive` and `audit` spawn the engine
through `godot.run_godot`, so `TIMEOUT_SECONDS`, `RAM_CEILING_BYTES`, `LOG_BYTE_CEILING`,
`SILENCE_GRACE_SECONDS` and `PROJECT_LOCK` all apply (INC-0004/0005). The Godot binary is
never resolved here.

**A transcript is a list, walked with a counted `for` on both sides** — the Python loop
below and the GDScript `_commands` — so every loop terminates on any input. The verb count
is additionally capped by `MAX_COMMANDS` and an extra verb is refused by name, because a
guard that silently truncates is a guard that lies (AGENTS.md).
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from . import godot
from .common import GAME_DIR, SRC_DIR, ToolError, fail, info, ok

DRIVER = "res://tools/domain_driver.gd"
PREFIX = "DOMAINJSON "

# Where authored domain content lives. `DomainApi.TEMPLATE_DIR` and `api.gd:28-31` say
# this is deliberately NOT `game/data`: the 160 legacy `DomainDef` records there are a
# different, older content set. `tools domain audit` and `tools data audit`'s second root
# both read THIS one, never the module constant, so the two cannot disagree about which
# tree they graded.
SRC_DOMAIN_ROOT = SRC_DIR / "data" / "domains"
TEMPLATE_DIR = SRC_DOMAIN_ROOT / "templates"
ROOM_DIR = SRC_DOMAIN_ROOT / "rooms"
INHABITANT_DIR = SRC_DOMAIN_ROOT / "inhabitants"

# The verbs, mirrored from the GDScript `VERB_ARGS` so `--help` and the refusal below are
# read from ONE list. A verb the engine refuses is reported by name, never skipped.
VERBS = (
    "enter",
    "visit:<room_id>",
    "arm:<room_id>|<fixture_id>|<delta>",
    "attempt:<room_id>|<fixture_id>|<node_id>",
    "claim:<room_id>|<fixture_id>",
    "leave",
    "map",
    "rooms",
    "minimap",
    "summary",
    "band",
    "kill:<boss_id>",
    "gate",
    "abandon",
    "templates",
)

# The seed `DomainBridge.DEFAULT_SEED` publishes (20260904). Named here so `--help` can
# print it; the driver reads the bridge's own constant for its own default, so this is a
# default for the CLI and not a second declaration the engine can drift from.
DEFAULT_SEED = 20260904

# A transcript may carry at most this many verbs. A guard, not a budget: the driver refuses
# the extra one by name and exits non-zero rather than truncating a caller's script.
MAX_COMMANDS = 512


def register(subparsers) -> None:
    parser = subparsers.add_parser("domain", help="drive a domain headlessly (ADR 0231)")
    sub = parser.add_subparsers(dest="domain_command", required=True)

    sub.add_parser("templates", help="print the authored domain catalogue (no engine)")

    drive = sub.add_parser("drive", help="enter a domain and play a JSONL transcript")
    drive.add_argument(
        "--template", default="", help="template_id to enter (default: first authored)"
    )
    drive.add_argument(
        "--seed", type=int, default=DEFAULT_SEED, help=f"generator seed (default {DEFAULT_SEED})"
    )
    drive.add_argument(
        "--cmd",
        action="append",
        default=[],
        metavar="VERB",
        help=(
            "a verb from: "
            + ", ".join(VERBS)
            + "; repeatable, runs in order. A verb may carry an argument after '='"
        ),
    )
    drive.add_argument(
        "--out",
        default="",
        metavar="PATH",
        help="also write the JSONL transcript to PATH (gitignored build/ recommended)",
    )

    audit = sub.add_parser("audit", help="grade the authored content under src/data/domains")
    audit.add_argument(
        "--fail-on",
        choices=["none", "warn", "error"],
        default="error",
        help="exit non-zero above this finding level (default error)",
    )


def run(args) -> int:
    if args.domain_command == "templates":
        return _templates()
    if args.domain_command == "drive":
        return _drive(args)
    if args.domain_command == "audit":
        return _audit_command(args.fail_on)
    raise ToolError(f"unknown domain command: {args.domain_command}")


# ── templates (engine-free) ───────────────────────────────────────────────────


def _template_records() -> list[dict[str, str]]:
    r"""Every authored `DomainTemplateDef`, read the way `DomainApi.templates()` reads.

    Text, not an engine run: the catalogue question ("which domains exist and what shape
    are they") does not need a generator, and `tools domain templates` must answer it
    without taking the project lock. Parsed from the `.tres` the engine itself loads, so a
    template the reader cannot parse is reported rather than silently dropped.

    Three parsers, each because the `.tres` shape demands it:

    - `_ext_paths` maps `ExtResource("<id>")` to the resource's own path, because a
      `room_pool` names a pool member BY ITS EXTERNAL ID and the path lives on a separate
      `[ext_resource]` line. Reading the id as if it were a room name is a reader that
      resolves nothing.
    - `_block` finds an array by counting brackets to the matching close, because the
      closing `])` shares a line with the last entry, so a line-anchored `^\]\)` reads the
      whole pool as empty.
    - `_main_resource` scopes a scalar to the main `[resource]` block, because a
      `TemplatePin` `sub_resource` carries its own `display_name` and a first-match scan
      reads the PIN's as the template's.

    Raw, because the bracket literals quoted above are not valid escapes in a non-raw
    docstring: a `SyntaxWarning` today and a `SyntaxError` on the next Python that tightens
    it. A docstring must not be able to fail a build over prose.
    """
    if not TEMPLATE_DIR.is_dir():
        return []
    out: list[dict[str, str]] = []
    for path in sorted(TEMPLATE_DIR.glob("*.tres")):
        text = path.read_text(encoding="utf-8", errors="replace")
        if 'script_class="DomainTemplateDef"' not in text:
            continue
        paths = _ext_paths(text)
        body = _main_resource(text)
        rooms = sorted(
            {Path(paths.get(ref, "")).stem for ref in _pool_refs(text) if paths.get(ref)}
        )
        out.append(
            {
                "template_id": _field(body, "template_id"),
                "display_name": _field(body, "display_name"),
                "path": path.relative_to(GAME_DIR.parent).as_posix(),
                "rooms_in_pool": str(len(rooms)),
                "rooms": ",".join(rooms),
                "weather": _field(body, "weather"),
                "min_rooms": _number(body, "min_rooms"),
                "max_rooms": _number(body, "max_rooms"),
            }
        )
    return out


def _ext_paths(text: str) -> dict[str, str]:
    """`ExtResource("<id>")` -> that resource's `path`, from the header block only."""
    header = text.split("[sub_resource", 1)[0]
    ids = re.findall(r'\[ext_resource[^\]]*?path="([^"]*)"[^\]]*?id="([^"]*)"\]', header)
    return {resource_id: res_path for res_path, resource_id in ids}


def _main_resource(text: str) -> str:
    """The file's own `[resource]` block, ignoring every `sub_resource` before it.

    The same idiom `tools/data.py:_main_resource` uses, for the same reason: a template
    authors `TemplatePin` sub-resources and a first-match scan over the whole file reads a
    pin's `display_name` as the template's.
    """
    marker = "\n[resource]"
    index = text.rfind(marker)
    return text[index + 1 :] if index >= 0 else text


def _block(text: str, name: str, typed: str) -> list[str]:
    r"""Every `ExtResource("<id>")` inside the `name = Array[typed]([ ... ])` block.

    Bracket COUNTING rather than a bounded wildcard, for the same reason
    `tools/data.py:_children_of` counts braces: a line-anchored `^\]\)` never matches,
    because the engine writes the close on the last entry's line. A counted scan is a
    `while` over a fixed string that either breaks at the close or runs out of file, so it
    terminates on any input — it does not test a length it is itself changing.
    """
    opener = re.search(rf"(?m)^\s*{name}\s*=\s*Array\[{re.escape(typed)}\]\(\s*\[", text)
    if opener is None:
        return []
    depth = 1
    index = opener.end()
    end = len(text)
    while index < len(text):
        char = text[index]
        if char in "[{":
            depth += 1
        elif char in "]}":
            depth -= 1
            if depth == 0:
                end = index
                break
        index += 1
    return re.findall(r'ExtResource\("([^"]*)"\)', text[opener.end() : end])


def _pool_refs(text: str) -> list[str]:
    """The `room_pool` members, plus the `TemplatePin.room_def` each pin names."""
    refs = _block(text, "room_pool", "RoomDef")
    for pin in text.split("[sub_resource")[1:]:
        refs += re.findall(r'(?m)^room_def\s*=\s*ExtResource\("([^"]*)"\)', pin)
    return refs


def _field(text: str, name: str) -> str:
    match = re.search(rf'(?m)^\s*{name}\s*=\s*&"([^"]*)"', text)
    if match:
        return match.group(1)
    match = re.search(rf'(?m)^\s*{name}\s*=\s*"([^"]*)"', text)
    return match.group(1) if match else ""


def _number(text: str, name: str) -> str:
    match = re.search(rf"(?m)^\s*{name}\s*=\s*(-?[\d.]+)", text)
    return match.group(1) if match else ""


def _templates() -> int:
    records = _template_records()
    for record in records:
        info(json.dumps(record))
    ok(f"{len(records)} domain template(s) under {TEMPLATE_DIR}")
    return 0


# ── drive ─────────────────────────────────────────────────────────────────────


def _drive(args) -> int:
    commands = list(args.cmd or [])
    if len(commands) > MAX_COMMANDS:
        raise ToolError(
            f"a transcript may carry at most {MAX_COMMANDS} verbs, got {len(commands)}; "
            "refusing rather than truncating a caller's script"
        )
    # Every argument is validated BEFORE the engine is spawned, so a typo costs a
    # `ToolError` rather than a 900 s ceiling and a lock.
    _validate(commands)

    cmd = [
        "--headless",
        "--path",
        str(GAME_DIR),
        "-s",
        DRIVER,
        "--",
        "--seed",
        str(args.seed),
    ]
    if args.template:
        cmd += ["--template", args.template]
    for verb in commands:
        cmd += ["--cmd", verb]

    result = godot.run_godot(cmd, capture=True, tag="domain")
    events = _events(result.stdout or "")
    if not events:
        for line in (result.stdout or "").splitlines():
            info(line)
        for line in (result.stderr or "").splitlines():
            info(line)
        raise ToolError("driver produced no output; see the engine log above")

    lines: list[str] = []
    for event in events:
        line = json.dumps(event)
        print(line)
        lines.append(line)
    if args.out:
        target = Path(args.out)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("\n".join(lines) + "\n", encoding="utf-8")

    violations = [event for event in events if event.get("event") == "violation"]
    final = next((event for event in events if event.get("event") == "final"), None)
    if violations:
        # **The offending transcript line is named**, which is the difference between a
        # driver and a viewer: a caller pasting a broken script learns which line to fix.
        for event in violations:
            fail(
                f"transcript line {event.get('step')} [{event.get('verb', event.get('kind'))}]: "
                f"{event.get('message')}"
            )
        fail(f"domain drive failed: {len(violations)} violated invariant(s)")
        return 1
    if final is None:
        fail("driver produced no final state; the transcript was truncated")
        return 1
    if result.returncode != 0:
        fail(f"driver exited {result.returncode} with no invariant violated; see the engine log")
        return result.returncode
    ok(
        f"{len(events)} event(s), seed {args.seed}, template {final.get('template_id', '')}; "
        "every invariant held"
    )
    return 0


def _validate(commands: list[str]) -> None:
    """Refuse a malformed verb here, where it is cheap, rather than inside the engine."""
    for verb in commands:
        name = verb.split("=", 1)[0]
        if name not in {v.split(":", 1)[0] for v in VERBS}:
            raise ToolError(f"unknown verb '{name}'; the bridge publishes: " + ", ".join(VERBS))


def _events(stdout: str) -> list[dict[str, Any]]:
    """The `DOMAINJSON ` documents, in order. A malformed line is SKIPPED, not fatal —
    the engine may print a partially-flushed line — and `drive` reports the empty case.
    """
    events: list[dict[str, Any]] = []
    for line in stdout.splitlines():
        if not line.startswith(PREFIX):
            continue
        try:
            events.append(json.loads(line[len(PREFIX) :]))
        except json.JSONDecodeError:
            continue
    return events


# ── audit (ADR 0233, ADR 0234, ADR 0226) ─────────────────────────────────────


def _room_records() -> dict[str, str]:
    """Every authored `RoomDef`, keyed by file stem. `room_id` is the content id, so a
    def whose `room_id` disagrees with its filename is the finding, not a silent alias.
    """
    if not ROOM_DIR.is_dir():
        return {}
    out: dict[str, str] = {}
    for path in sorted(ROOM_DIR.glob("*.tres")):
        out[path.stem] = path.relative_to(GAME_DIR.parent).as_posix()
    return out


def _audit_command(fail_on: str) -> int:
    """Grade the authored domain content the way `tools data audit` grades `game/data`.

    Engine-free on purpose: this is a CONTENT gate, and one that needed the engine would be
    unable to run in the same breath as the content change it grades.
    """
    errors: list[str] = []
    warnings: list[str] = []
    templates = _template_records()
    rooms = _room_records()
    if not templates:
        errors.append(f"{TEMPLATE_DIR} holds no DomainTemplateDef; the domain has no catalogue")
    if not rooms:
        errors.append(f"{ROOM_DIR} holds no RoomDef; no template can have a kit")

    # ADR 0226: a room def in no template's `room_pool` is content no map can contain, so
    # the catalog is the union of the pools. Read from the CATALOG, never from the def's
    # own declaration — a row that asserts its own reachability is the failure this gate
    # exists to catch.
    pooled: set[str] = set()
    for record in templates:
        text = (GAME_DIR.parent / record["path"]).read_text(encoding="utf-8", errors="replace")
        paths = _ext_paths(text)
        pooled |= {Path(paths.get(ref, "")).stem for ref in _pool_refs(text) if paths.get(ref)}
    for stem in sorted(set(rooms) - pooled):
        errors.append(
            f"room '{stem}' ({rooms[stem]}) is in no template's room_pool, so no map can "
            "ever contain it (ADR 0226); the pin is the fix"
        )

    for record in templates:
        template_id = record["template_id"]
        if not template_id:
            errors.append(f"{record['path']}: no template_id, so no caller can name it")
        elif template_id != Path(record["path"]).stem:
            warnings.append(
                f"{record['path']}: template_id '{template_id}' differs from its filename; "
                "DomainApi._template matches on the id, so the file name is cosmetic"
            )
        if int(record["min_rooms"] or 0) <= 0:
            errors.append(f"{record['path']}: min_rooms is not a positive count")
        if record["min_rooms"] and record["max_rooms"]:
            if float(record["max_rooms"]) < float(record["min_rooms"]):
                errors.append(
                    f"{record['path']}: max_rooms {record['max_rooms']} is below "
                    f"min_rooms {record['min_rooms']}, so no seed can satisfy both"
                )
        if int(record["rooms_in_pool"]) <= 0:
            errors.append(
                f"{record['path']}: has an empty room_pool, so generate_and_enter can "
                "never place a room (ADR 0221)"
            )

    for level, message in (
        *[("error", m) for m in errors],
        *[("warn", m) for m in warnings],
    ):
        if level == "error":
            fail(message)
        else:
            info(f"warn {message}")

    census = (
        f"domain content: {len(templates)} template(s), {len(rooms)} room def(s), "
        f"{len(pooled)} pooled, under {SRC_DOMAIN_ROOT}"
    )
    info(census)
    if fail_on != "none" and errors:
        fail(f"domain audit failed: {len(errors)} error(s)")
        return 1
    if fail_on == "warn" and warnings:
        fail(f"domain audit failed: {len(warnings)} warning(s)")
        return 1
    ok("domain audit clean" if not warnings else f"domain audit clean ({len(warnings)} warning(s))")
    return 0
