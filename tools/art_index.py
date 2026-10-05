"""Index rendered PNGs into catalog shot rows, with provenance recovered from the files.

## Why this is separate from `character_bundle_sync`

`character_bundle_sync` answers "what reaches the game" — which shots install, and which authored
`.tres` they become. This answers "what is this row's `path`, and where did it come from", which is
a different question with a different failure mode: a bundle can be complete while every row behind
it is still `planned`.

Two facts made the question worth a tool rather than a hand edit:

**A render's provenance is inside the render.** DEF-0308 held that it was unrecoverable, because the
generator's checkpoint is chosen by the agent and never passed to the script. That looked at the
writer and never at the artefact; ComfyUI writes the graph it executed into the PNG. See
`tools/png_provenance.py`. So `source`, `prompt`, `generated_on` and `license` are READ, never typed
in by a human who remembers what they ran last week.

**Every render is the wrong canvas for most slots, and the slot table is the arbiter.** All 25
shipped files came out of one generator at `3:4 / 2.0 MP`, i.e. 1248x1664. `CANVAS_BY_SLOT` demands
384x512 for `character_portrait`, 1024x1024 for the concept slots, 128x192 for `map_sprite`, and
declares empty for the two set slots so each member declares its own. So a 1248x1664 file is
installable for a set member that declares it and un-installable for a `character_portrait` one, and
both verdicts are correct — which is exactly why the rule cannot be "1248x1664 is fine".

## What is a hard failure here, and why

Three things refuse to write rather than write something plausible:

- **A canvas that does not match the slot's install geometry.** Recording `path` on a shot that
  cannot install produces a row which claims a resource the game will never load — the same class of
  defect as the 18 false `published_as` claims DEF-0293 removed.
- **A file carrying no ComfyUI workflow.** `source` would have to be invented, and a provenance row
  asserting a checkpoint no file supports is the one thing this whole program exists to end.
- **A `path` that already names a different file.** Overwriting it would silently repoint a shot at
  new art; both files are reported instead.

Refusals are reported per shot and the command exits 1, so a partial index is visible rather than
half-written and read as complete.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

from . import character_bundle_sync as sync
from . import png_provenance, unique_characters
from .common import GAME_DIR, ToolError, fail, ok

#: The license string the corpus's own indexed rows already declare. Copied rather than reworded
#: so `check` sees one consistent value, and a CONSTANT because it is a claim about someone else's
#: checkpoint: "the source checkpoint license applies" is not this repo's to paraphrase.
LICENSE_TEXT = "Generated locally for private use; source checkpoint license applies."

#: Statuses a row may hold. `generated` means a real file exists at `path` with recovered
#: provenance; `planned` means the slot is authored and nothing is rendered yet. A third value would
#: be a status no consumer reads, so it is refused rather than accepted.
STATUS_GENERATED = "generated"
STATUS_PLANNED = "planned"
ALLOWED_STATUSES = (STATUS_GENERATED, STATUS_PLANNED)


class IndexError_(ToolError):
    """Raised for a refusal that must not write. Named with a trailing underscore so it cannot be
    confused with the builtin `IndexError`, which this module never catches and never means."""


def _shot_rows(record: dict) -> list[dict]:
    """The character's authored shot rows, bounded by the authored list."""
    return [shot for shot in (record.get("art") or {}).get("shots") or [] if isinstance(shot, dict)]


def _on_disk(record: dict) -> dict[str, Path]:
    """Every candidate render for this character, keyed by the filename a shot is addressed at."""
    return sync.render_index(sync.art_fidelity.art_root())


def plan_index(record: dict, allow_wrong_canvas: bool = False) -> tuple[list[dict], list[str]]:
    """(`row_updates`, `refusals`) for one character. Writes nothing.

    A row update is `{shot_id, path, source, prompt, generated_on, license, canvas, status, from}`.

    Matching is by the same filename rule `discover_renders` already uses (`ilsa_map-sprite` ->
    `ilsa_map_sprite.png`), so a shot can never be bound to a file the install path would not find.
    Reading that rule from the install side rather than restating it is the point: a second copy of
    the naming convention is a second chance to disagree about which file a shot means.
    """
    prefix = sync.render_prefix(str(record.get("name", "")))
    found_by_name = _on_disk(record)
    updates: list[dict] = []
    refusals: list[str] = []

    for shot in _shot_rows(record):
        shot_id = str(shot.get("id", ""))
        slot = str(shot.get("slot", ""))
        name = sync.rendered_name(prefix, shot_id)
        source_path = found_by_name.get(name)
        if source_path is None:
            continue

        # A WITHDRAWN shot refuses before its file is even measured. 22 of unique-0001's renders are
        # marked withdrawn on a visual audit - apparent age 18-35 against an authored 41, a styled
        # bob rather than the authored blade crop, brass jewellery a faction grants none of - and
        # indexing one would put a `path` and a recovered `source` on a row whose own note says the
        # art is wrong. The file exists, the file is provenance-bearing, and the file is still bad:
        # those three facts are independent, and only the first two are what this tool measures.
        if shot.get("withdrawn"):
            refusals.append(
                f"{shot_id}: the shot is marked withdrawn ({str(shot['withdrawn'])[:90]}...) and "
                f"its render fails visual audit, so it is not indexed; re-render before indexing"
            )
            continue

        want = sync.install_canvas(slot, shot)
        have = sync.image_size(source_path)
        declared = [int(c) for c in shot.get("canvas") or []] if shot.get("canvas") else []
        if not want:
            refusals.append(
                f"{shot_id}: slot '{slot}' has no install geometry and the shot declares no canvas "
                f"of its own, so nothing can be said about whether {name} fits"
            )
            continue
        if have != tuple(want) and not allow_wrong_canvas:
            refusals.append(
                f"{shot_id}: {name} is {have[0]}x{have[1]} and slot '{slot}' installs at "
                f"{want[0]}x{want[1]}; re-render at the slot's geometry rather than index a file "
                f"the install path will refuse"
            )
            continue
        if declared and declared != list(have):
            refusals.append(
                f"{shot_id}: the shot declares canvas {declared[0]}x{declared[1]} but {name} is "
                f"{have[0]}x{have[1]}; the declaration and the file disagree about one crop"
            )
            continue

        prov = png_provenance.read_provenance(source_path)
        if not prov.present:
            refusals.append(
                f"{shot_id}: {name} carries no ComfyUI workflow, so `source` would have to be "
                f"invented; {'; '.join(prov.notes)}"
            )
            continue
        if not prov.source:
            refusals.append(
                f"{shot_id}: {name} has a workflow but names no checkpoint, so there is nothing to "
                f"record as its source"
            )
            continue
        if not prov.generated_on:
            refusals.append(
                f"{shot_id}: {name} carries no date in its output path ({prov.filename_prefix!r}), "
                f"so `generated_on` would have to come from a filesystem time that a copy rewrites"
            )
            continue

        # An already-indexed shot is compared by CONTENT, not by `res://` string: the generator's
        # originals live in `unique/outputs/` while the rows point at the INSTALLED copies in
        # `unique/unique-<id>/`, so one render has two paths and a string comparison calls every one
        # of them "already names a different file". See `_same_file`.
        res_path = _res_path_of(source_path)
        if res_path == "":
            refusals.append(
                f"{shot_id}: {source_path} is outside the game tree, so it has no `res://` "
                f"path and cannot be indexed"
            )
            continue

        existing = str(shot.get("path") or "")
        if existing and not _same_file(existing, source_path):
            refusals.append(
                f"{shot_id}: already names {existing}, which is a different file from {name}; "
                f"refusing to repoint a shot that is already indexed"
            )
            continue

        # When the shot is already indexed, keep the INSTALLED path it already names. The render is
        # byte-identical, but the installed copy is the one with a `.import` sibling and the one the
        # game loads, so rewriting the row to point at `outputs/` would repoint a working layer at
        # an unimported original - a change that looks like a no-op and is not one.
        target = existing if existing else res_path
        updates.append(
            {
                "shot_id": shot_id,
                "from": existing,
                "path": target,
                "status": STATUS_GENERATED,
                "source": prov.source,
                "prompt": prov.positive_prompt,
                "generated_on": prov.generated_on,
                "license": LICENSE_TEXT,
                "canvas": [int(have[0]), int(have[1])],
                "checkpoint": prov.checkpoint,
                "seed": prov.seed,
                "aspect_ratio": prov.aspect_ratio,
            }
        )
    return updates, refusals


def _res_path_of(candidate: Path) -> str:
    """The `res://` path for an on-disk file, or "" when the file is outside the game tree.

    `relative_to` RAISES for a path outside `GAME_DIR`, and this is called from a plan loop over
    every shot of every character: an art root pointed anywhere else would abandon the remaining
    shots with a traceback instead of reporting them. The refusal belongs in `refusals`, which is
    where a file that is not part of the game belongs.

    Returns "" rather than guessing a path, because a `res://` string resolving to nothing is
    the false-claim shape DEF-0293 was filed for.
    """
    resolved = Path(str(candidate)).resolve()
    root = GAME_DIR.resolve()
    try:
        return "res://" + str(resolved.relative_to(root)).replace("\\", "/")
    except ValueError:
        return ""


def _same_file(res_path: str, candidate: Path) -> bool:
    """Is the `res://` path the same RENDER as this on-disk candidate?

    Samefile is the wrong question, and answering it wrong is how 22 already-indexed renders got
    reported as "already names a different file". The generator's originals live in
    `unique/outputs/` while the catalog rows point at the INSTALLED copies in
    `unique/unique-<id>/`, so one render legitimately has two paths on disk and `samefile` says
    False for every one of them - verified on ilsa_map_sprite.png, ilsa_expression_01.png and three
    more, each pair byte-identical by SHA-256 and still "different files" to the OS.

    So the question is CONTENT, and it is asked of the bytes: a streamed SHA-256 of both sides,
    chunked, because these are 2.6 MB files and reading them whole to compare would be fine here and
    wrong on a 40 MB render. A missing side is False rather than an error, since "not installed yet"
    is the ordinary state of a first index pass.
    """
    installed = GAME_DIR / res_path.removeprefix("res://")
    if not installed.is_file() or not candidate.is_file():
        return False
    return _digest(installed) == _digest(candidate)


## Read granularity for the digest. Bounded and fixed: the loop below reads exactly
## ceil(size / CHUNK) times per file and no counter in it can change the file's size.
_DIGEST_CHUNK = 1 << 20


def _digest(path: Path) -> str:
    """SHA-256 of a file's bytes, streamed in fixed-size chunks."""
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(_DIGEST_CHUNK)
            if not chunk:
                break
            hasher.update(chunk)
    return hasher.hexdigest()


def _apply(record: dict, updates: list[dict]) -> int:
    """Write the updates into the record's shot rows. Returns how many rows changed."""
    by_id = {str(u["shot_id"]): u for u in updates}
    changed = 0
    for shot in _shot_rows(record):
        update = by_id.get(str(shot.get("id", "")))
        if update is None:
            continue
        # `prompt` records the RECOVERED positive prompt. The shot's own `pose`/`framing`/
        # `expression` prose is a different thing - it is the authored brief - and is left alone.
        shot["path"] = update["path"]
        shot["status"] = update["status"]
        shot["canvas"] = list(update["canvas"])
        shot["source"] = update["source"]
        shot["prompt"] = update["prompt"]
        shot["generated_on"] = update["generated_on"]
        shot["license"] = update["license"]
        changed += 1
    return changed


def _atomic_write(records: list[dict], character_id: str) -> Path:
    """Write into the shard that ALREADY owns this record; returns that shard.

    The owning shard is a LOOKUP, never a recomputation. Writing to a shard that does not hold the
    record duplicates it into two files, which is the bug `_backfill_command` documents at length.
    """
    shard = unique_characters._owning_shard(character_id)
    unique_characters._atomic_write(records, shard)
    return shard


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "art_index",
        help="index rendered PNGs into catalog shot rows with provenance read from the files",
    )
    actions = parser.add_subparsers(dest="art_index_action", required=True)
    plan = actions.add_parser("plan", help="print what would be indexed; never writes")
    plan.add_argument("--character-id", default="")
    plan.add_argument(
        "--allow-wrong-canvas",
        action="store_true",
        help="index a render whose size does not match the slot's install geometry",
    )
    write = actions.add_parser("write", help="write the recovered provenance into the owning shard")
    write.add_argument("--character-id", default="")
    write.add_argument(
        "--allow-wrong-canvas",
        action="store_true",
        help="index a render whose size does not match the slot's install geometry",
    )


def run(args) -> int:
    action = args.art_index_action

    catalog = unique_characters.readable_catalog()
    if args.character_id:
        catalog = [
            r for r in catalog if isinstance(r, dict) and str(r.get("id", "")) == args.character_id
        ]
        if not catalog:
            fail(f"no catalog record with id {args.character_id!r}")
            return 1

    total_updates = 0
    total_refusals = 0
    wrote_any = False
    for record in catalog:
        if not isinstance(record, dict):
            continue
        if not (record.get("art") or {}).get("shots"):
            continue
        updates, refusals = plan_index(record, allow_wrong_canvas=args.allow_wrong_canvas)
        total_updates += len(updates)
        total_refusals += len(refusals)
        character_id = str(record.get("id", ""))
        if action == "plan":
            print("=" * 78)
            print(f"{character_id}: {len(updates)} indexable, {len(refusals)} refused")
            for update in updates:
                print(f"  [index] {update['shot_id']:<24} {update['path']}")
                print(f"          source      {update['source']}")
                print(f"          generated_on {update['generated_on']}  seed {update['seed']}")
                print(
                    f"          canvas      {update['canvas'][0]}x{update['canvas'][1]}"
                    f"  aspect {update['aspect_ratio']}"
                )
                print(f"          prompt      {len(update['prompt'])} chars")
            for refusal in refusals:
                print(f"  [refuse] {refusal}")
            continue

        if not updates:
            continue
        changed = _apply(record, updates)
        owned = [r for r in catalog if str(r.get("id", "")) == character_id]
        if len(owned) != 1:
            fail(
                f"{character_id}: found {len(owned)} record(s) for this id; refusing to write a "
                f"shard when the id is ambiguous"
            )
            return 1
        shard = _atomic_write(owned, character_id)
        wrote_any = True
        print(f"ok   {character_id}: indexed {changed} shot(s) into {shard.name}")
        for update in updates:
            print(f"       {update['shot_id']:<24} {update['path']}")

    print()
    print(f"{total_updates} row(s) indexable, {total_refusals} refusal(s)")
    if action == "plan":
        print("nothing written (plan)")
    elif wrote_any:
        ok("recovered provenance written into the owning shard")
    if total_refusals:
        fail(
            f"{total_refusals} shot(s) could not be indexed. Each is a content or a re-render gap, "
            f"not a tool gap: re-render at the slot's install geometry, or record a workflow."
        )
        return 1
    return 0
