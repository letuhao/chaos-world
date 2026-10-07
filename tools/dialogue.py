"""Compile a Yarn-shaped script into a `DialogueDef` (ADR 0862).

`DialogueYarn` is the compiler and it lives in GDScript, because it needs the real
`DialogueDef` / `DialogueNodeDef` / `DialogueCondition` resources and their validation — a
Python re-implementation would be a SECOND compiler that could disagree with the runtime.
So this module ferries arguments and spawns the engine through `godot.run_godot`, which
means `TIMEOUT_SECONDS`, `RAM_CEILING_BYTES`, `LOG_BYTE_CEILING` and `PROJECT_LOCK` all
apply (INC-0004/0005). The Godot binary is never resolved here.

Every argument is checked BEFORE the engine is spawned, so a typo costs a `ToolError`
rather than a 900 s ceiling and a lock.
"""

from __future__ import annotations

import json
from pathlib import Path

from . import godot
from .common import GAME_DIR, REPO_ROOT, ToolError, info, ok

DRIVER = "res://tools/dialogue_driver.gd"
PREFIX = "DIALOGUEJSON "


def register(subparsers) -> None:
    parser = subparsers.add_parser("dialogue", help="compile a Yarn script into a DialogueDef")
    sub = parser.add_subparsers(dest="dialogue_command", required=True)

    compile_ = sub.add_parser("compile", help="compile a .yarn file into a .tres DialogueDef")
    compile_.add_argument("--src", required=True, help="path to the .yarn source")
    compile_.add_argument("--npc", required=True, help="the npc_id this conversation belongs to")
    compile_.add_argument("--id", required=True, dest="dialog_id", help="the dialog_id")
    compile_.add_argument(
        "--out", required=True, help="the res:// path to write (e.g. res://data/dialogue/x.tres)"
    )


def run(args) -> int:
    if args.dialogue_command == "compile":
        return _compile(args)
    raise ToolError(f"unknown dialogue action: {args.dialogue_command}")


def _compile(args) -> int:
    src = Path(args.src)
    if not src.is_absolute():
        src = (REPO_ROOT / src).resolve()
    if not src.is_file():
        raise ToolError(f"source not found: {src}")
    if not str(args.out).startswith("res://"):
        # `ResourceSaver` writes into the project, so an OS path would be written to a
        # directory the game cannot load from. Refused before the engine starts.
        raise ToolError("--out must be a res:// path, e.g. res://data/dialogue/name.tres")
    if not args.npc or not args.dialog_id:
        raise ToolError("--npc and --id must both be non-empty")

    cmd = [
        "--headless",
        "--path",
        str(GAME_DIR),
        "-s",
        DRIVER,
        "--",
        "--src",
        str(src),
        "--npc",
        args.npc,
        "--id",
        args.dialog_id,
        "--out",
        str(args.out),
    ]
    result = godot.run_godot(cmd, capture=True, tag="dialogue")
    payload = _payload(result.stdout or "")
    if payload is None:
        for line in (result.stdout or "").splitlines():
            info(line)
        for line in (result.stderr or "").splitlines():
            info(line)
        raise ToolError("dialogue driver produced no output; see the engine log above")

    problems = payload.get("problems") or []
    if not payload.get("ok"):
        for problem in problems:
            info(str(problem))
        raise ToolError(f"compilation failed ({len(problems)} problem(s))")
    ok(f"wrote {payload.get('out')} ({payload.get('nodes')} node(s))")
    return 0


def _payload(stdout: str) -> dict | None:
    """The one `DIALOGUEJSON ` line the driver prints, or None."""
    for line in stdout.splitlines():
        if line.startswith(PREFIX):
            try:
                return json.loads(line[len(PREFIX) :])
            except json.JSONDecodeError:
                return None
    return None
