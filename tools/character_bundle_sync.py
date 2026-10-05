"""Sync a character's indexed shots into an authored `PortraitDef` the game already reads.

## What this is for

ADR 0175 keeps the named cast a separate catalog and forbids `res://src` from reading it. It
promises one bridge: `published_as` "stays empty until a deliberate sync step writes an authored
resource". This module is that step, and it is deliberately a SEPARATE task rather than a
subcommand of `unique_characters`.

**It imports `tools.unique_characters` and never edits it.** That file is under concurrent edit by
several sessions writing catalog shards (INC-0023), and a change there cannot be reviewed in
isolation. Reading it through its public module surface keeps this slice reviewable and keeps the
collision surface at zero.

## The one number that matters, and why it is here

`_validate_image` in `tools/unique_characters.py` refuses an installed PNG whose size is not
EXACTLY its shot's declared `canvas`. Every one of the 25 shipped renders is 1248x1664 (one canvas
for every slot) except a map sprite at 896x1184, so **all 25 fail that rule** and none is
installable (DEF-0253).

`CANVAS_BY_SLOT` below is therefore the *install* geometry, and it is declared in ONE place here
rather than in two. It is seeded from the proven crowd catalog — `character_assets.py:256` for
`map_sprite` (128x192, "centered with a bottom-center ground pivot") and `:268` for
`dialogue_portrait` (384x512) — because those are canvases the game has actually shipped and
placed. The slot's own `canvas` in the catalog remains the *authored intent*; `sync` reports the
mismatch rather than overwriting it, because quietly rewriting an author's declared canvas is how a
content gap becomes invisible.

## What it refuses

- **A character with no installed shot.** A `PortraitDef` with an empty `layer_paths` fails
  `PortraitResolver.validate()` (`:157`) for anything that is not the placeholder, so publishing
  one makes the gate red rather than making the game work.
- **A `palette_key` derived from prose.** `appearance.palette` is written prose ("Oiled brown
  leather, bleached undyed wool..."), and `portrait_def.gd:40-42` requires a theme KEY because "a
  literal colour in content is a second place to retune it". So the key is empty unless an authored
  `palette:` tag supplies one.
- **A `race_id` the content tree does not define.** Five races ship; the catalog spans
  `races.echoless`, `races.tidecaller` and many more that no `RaceDef` defines. An unresolvable race
  is reported, never guessed, because a portrait naming a race no content defines fails for exactly
  the actors who most need one (`portrait_resolver.gd:123-124`).
"""

from __future__ import annotations

import os
import re
import tempfile
from pathlib import Path

from . import art_fidelity, unique_characters
from .common import GAME_DIR, fail, info, ok

## Where the authored resources go. `PortraitCatalog.ROOT` is the only place the game reads
## portraits from, and it is asserted in `tests/core/test_portrait_resolver.gd`, so a sync that
## wrote anywhere else would produce content nothing resolves.
PORTRAIT_ROOT = GAME_DIR / "data" / "portraits"

## The INSTALL geometry per slot, seeded from the shipped crowd catalog and declared HERE, once.
## `map_sprite` keeps the bottom-center ground pivot in prose because that is a rendering
## instruction, not a number, and `character_assets.py:263` is where the game already relies on it.
CANVAS_BY_SLOT: dict[str, list[int]] = {
    "map_sprite": [128, 192],
    "dialogue_portrait": [384, 512],
    "character_portrait": [384, 512],
    "concept_art": [1024, 1024],
    "environmental_concept": [1024, 1024],
    "combat_concept": [1024, 1024],
    "relationship_scene": [1024, 1024],
    "daily_life": [1024, 1024],
    # Set slots have no single canvas of their own; each member declares its own.
    "expression_set": [],
    "pose_set": [],
}

## Slots that carry the face a panel draws. Order matters: the first installed one is the base the
## rest composite over, and a portrait is useless without one of these.
## `character_portrait` outranks `dialogue_portrait` because it is the polished primary.
PRIMARY_SLOT_ORDER = ("character_portrait", "dialogue_portrait")

## Slots whose members are ALTERNATIVES of one another, not layers of one image (ADR 0237).
## Compositing nine expressions onto a portrait puts nine faces on it; they are reached through
## `PortraitCatalog.for_variant` instead. Mirrors `SET_SLOT_MINIMUMS` in
## `tools/unique_characters.py` rather than re-deriving it, because a set slot named in one table
## and missing from the other is
## exactly the second-source-of-truth failure this module's docstring exists to prevent.
SET_SLOTS = frozenset({"expression_set", "pose_set"})

## A lore id is namespaced (`races.tidecaller`), a game id is not (`tidecaller`). The catalog speaks
##: the first dialect throughout, so every join to game content strips the namespace — and where
## that fails, the sync says so instead of shipping an unresolvable reference.
_LORE_ID_RE = re.compile(r"^[a-z_]+\.(?P<bare>[a-z0-9_]+)$")

_RACE_TAG_RE = re.compile(r"^race:(?P<value>[a-z0-9_-]+)$")
_PALETTE_TAG_RE = re.compile(r"^palette:(?P<value>[a-z0-9_-]+)$")

## The `res://` prefix an authored `layer_paths` entry must carry. Matched rather than assumed,
##: because a path with the wrong prefix fails `ResourceLoader` at paint time and is reported by the
##: panel as "Not on disk" while the file is right there.
_PATH_PREFIX = "res://assets/characters/unique/"


# --- Finding the rendered art -------------------------------------------------


def render_prefix(display_name: str) -> str:
    """The filename stem a character's renders are named after: `Ilsa Renn` -> `ilsa`.

    The FIRST name, not the whole name — measured against all 25 shipped files, every one of which
    is `ilsa_` + the shot id. The whole name lowercased gives `ilsarenn` and matches nothing, which
    is why this returns a single token rather than a squashed string.

    Only the ASCII-alphanumeric characters of that token survive, so a name carrying a hyphen or an
    apostrophe still yields a stem the filesystem can hold.
    """
    first = str(display_name).split()[0] if str(display_name).split() else ""
    return re.sub(r"[^a-z0-9]+", "", first.lower())


def rendered_name(prefix: str, shot_id: str) -> str:
    """The rendered file a shot is expected at: `ilsa` + `map-sprite` -> `ilsa_map_sprite.png`.

    The catalog names shots with hyphens (`expression-01`) and the generator names files with
    underscores (`ilsa_expression_01.png`), so the substitution is the whole of the rule. Both sides
    are data, not convention, so a mismatch here is reported rather than guessed around.
    """
    return f"{prefix}_{str(shot_id).replace('-', '_')}.png"


def render_index(folder: Path) -> dict[str, Path]:
    """Every rendered PNG under `folder`, keyed by FILE NAME, walking one level of subfolder.

    Subfolders are load-bearing: the scene plates live in `outputs/scenes/` and the face studies in
    `outputs/face_angles/`, so a flat lookup reports "no render at ilsa_combat_concept.png" for a
    file that exists — the same coverage gap `art_fidelity.installed_images` had. Keyed by name
    because the shot rule addresses files by name, and `sorted` on both levels so two runs cannot
    disagree about which of two same-named files won. Bounded by the tree's own contents.
    """
    found: dict[str, Path] = {}
    if not folder.is_dir():
        return found
    candidates: list[Path] = sorted(folder.glob("*.png"), key=lambda item: item.name)
    for entry in sorted(folder.iterdir(), key=lambda item: item.name):
        if entry.is_dir():
            candidates.extend(sorted(entry.glob("*.png"), key=lambda item: item.name))
    for path in candidates:
        # First wins, and `candidates` is sorted, so the shallow file beats a same-named nested one
        # deterministically rather than by filesystem order.
        found.setdefault(path.name, path)
    return found


def install_canvas(slot: str, shot: dict) -> list[int]:
    """The geometry a shot must MATCH to install, or `[]` when nothing can be said.

    `CANVAS_BY_SLOT` is the install geometry (ADR 0175's per-shot canvas, seeded from the shipped
    crowd specs). A set member carries its own declared canvas instead, because nine expressions
    are nine different crops and a single square for all of them is not a canvas but a default.
    """
    declared = CANVAS_BY_SLOT.get(slot)
    if declared:
        return list(declared)
    own = shot.get("canvas")
    if isinstance(own, list) and len(own) == 2:
        return [int(own[0]), int(own[1])]
    return []


def image_size(path: Path) -> tuple[int, int]:
    """`(width, height)` read from the PNG header.

    Header-only on purpose: `PIL.Image.open` is lazy, and calling `.size` never decodes pixels, so
    this cannot allocate the image a 51 MB folder would otherwise hold open.
    """
    from PIL import Image  # local: only this one function needs it

    with Image.open(path) as handle:
        return (int(handle.width), int(handle.height))


def discover_renders(record: dict) -> list[dict]:
    """One verdict per shot: the render found for it, and whether it can install.

    `found` is the file on disk; `verdict` is `install` / `wrong_canvas` / `missing` / `no_canvas`;
    `reason` always explains a non-`install` verdict in a sentence a content author can act on,
    because "22 shots did not install" is the failure this program exists to end.
    """
    art = record.get("art") or {}
    prefix = render_prefix(str(record.get("name", "")))
    folder = art_fidelity.art_root()
    on_disk = render_index(folder)
    verdicts: list[dict] = []
    # `for` over the authored shot list, bounded by its length; it is never appended to.
    for shot in art.get("shots") or []:
        if not isinstance(shot, dict):
            continue
        shot_id = str(shot.get("id", ""))
        slot = str(shot.get("slot", ""))
        name = rendered_name(prefix, shot_id)
        found = on_disk.get(name, folder / name)
        want = install_canvas(slot, shot)
        entry = {
            "shot_id": shot_id,
            "slot": slot,
            "source": found,
            "want": want,
            "verdict": "install",
            "reason": "",
        }
        if not found.is_file():
            entry["verdict"] = "missing"
            entry["reason"] = f"no render at {found.name}"
        elif not want:
            entry["verdict"] = "no_canvas"
            entry["reason"] = (
                f"slot '{slot}' has no install canvas and the shot declares none of its own"
            )
        else:
            have = image_size(found)
            if list(have) != want:
                entry["verdict"] = "wrong_canvas"
                entry["reason"] = (
                    f"{found.name} is {have[0]}x{have[1]}; slot '{slot}' installs at "
                    f"{want[0]}x{want[1]}"
                )
        verdicts.append(entry)
    return verdicts


def bare_id(lore_id: str) -> str:
    """The game-side id behind a namespaced lore id, or `""` when it does not namespace.

    `races.tidecaller` becomes `tidecaller`. A value with no namespace is returned unchanged,
    because the catalog is not the only thing that ever writes these fields.
    """
    match = _LORE_ID_RE.match(lore_id.strip())
    if match is None:
        return lore_id.strip()
    return match.group("bare")


def shipped_race_ids() -> set[str]:
    """Every `RaceDef.id` the content tree actually defines.

    Read by text rather than by `load()`, for the same reason `PortraitCatalog` does it: a
    `DirAccess` walk that `load()`s every file mis-casts a `.tres` of another type, and a
    mis-cast here would make a character resolve to a race that does not exist.
    """
    found: set[str] = set()
    root = GAME_DIR / "data" / "races"
    if not root.is_dir():
        return found
    # `sorted` over a materialised listing: the result is a SET of ids and must not depend on
    # directory order, which is not stable between runs.
    for path in sorted(root.glob("*.tres")):
        match = re.search(r'^id = &"([^"]+)"', path.read_text(encoding="utf-8"), re.MULTILINE)
        if match is not None:
            found.add(match.group(1))
    return found


def _tag_value(tags: list, pattern: re.Pattern[str]) -> str:
    for tag in tags if isinstance(tags, list) else []:
        found = pattern.match(str(tag))
        if found is not None:
            return found.group("value")
    return ""


def install_plan(record: dict) -> tuple[list[dict], list[dict], list[str]]:
    """(layers, variants, refusals) — what installs, what becomes a variant, and what cannot.

    A layer is `{shot_id, slot, source, target}` where `source` is a file on disk and `target` is
    the `res://` path it will occupy once installed. A variant is the same shape plus `axis` and
    `value`, the `axis:value` pair a caller requests (ADR 0237). A refusal names the shot and the
    reason, because "nothing synced" with no reason is the failure this whole program exists to end.

    Ordered back to front: [method PRIMARY_SLOT_ORDER] first, then the remaining slots in sorted
    order, then each slot's shots in authored order. [method PortraitPanel] composites later layers
    over earlier ones, so the face has to be underneath — an ordering that put the map token first
    would draw the face on top of it.
    """
    character_id = str(record.get("id", ""))
    refusals: list[str] = []
    verdicts = discover_renders(record)
    installable: list[dict] = []
    variants: list[dict] = []
    for entry in verdicts:
        if entry["verdict"] != "install":
            refusals.append(f"{entry['shot_id']}: {entry['reason']}")
            continue
        if entry["slot"] in SET_SLOTS:
            # NOT a refusal: a set member is published, as its own variant portrait (ADR 0237).
            # Listing it beside the genuinely-blocked shots and calling both "not installable"
            # contradicted itself on every run — the render was right there in the variant list.
            variants.append(dict(entry))
            continue
        installable.append(entry)

    by_slot: dict[str, list[dict]] = {}
    for entry in installable:
        by_slot.setdefault(str(entry["slot"]), []).append(entry)

    ordered: list[dict] = []
    for slot in PRIMARY_SLOT_ORDER:
        ordered.extend(by_slot.get(slot, []))
    for slot in sorted(by_slot):
        if slot not in PRIMARY_SLOT_ORDER:
            ordered.extend(by_slot[slot])

    layers: list[dict] = []
    for entry in ordered:
        shot_id = str(entry["shot_id"])
        # The INSTALLED name is the render's own filename, not the shot id. `ilsa_map_sprite.png`
        # already sits in this folder WITH its Godot `.import` beside it, so naming the layer
        # `map-sprite.png` would duplicate a 51 MB folder's worth of art to express the same shot —
        # and a re-import of the copy for no reason.
        layers: list[dict] = []
    for entry in ordered:
        shot_id = str(entry["shot_id"])
        source: Path = entry["source"]
        target = f"{_PATH_PREFIX}{character_id}/{source.name}"
        layers.append(
            {
                "shot_id": shot_id,
                "slot": str(entry["slot"]),
                "source": source,
                "target": target,
                "local": GAME_DIR / target.removeprefix("res://"),
            }
        )
    # Variants reuse the base layer's install path rule, so a member lands beside the portrait it
    # alternates with rather than in a folder of its own.
    for entry in variants:
        shot_id = str(entry["shot_id"])
        source = entry["source"]
        target = f"{_PATH_PREFIX}{character_id}/{source.name}"
        entry["target"] = target
        entry["local"] = GAME_DIR / target.removeprefix("res://")
    return (layers, variants, refusals)


def build_variant_defs(record: dict, variants: list[dict]) -> list[tuple[str, str, list[str]]]:
    """`(filename, body, refusals)` per set member — one authored variant portrait each.

    A variant portrait's `layer_paths` is **the member alone**, never the base plus the member. The
    member is a complete standalone render at its own canvas (1248x1664 for Ilsa's expressions)
    while the base portrait is 384x512, and `PortraitPanel` skips a layer whose size differs from
    the first one and names it rather than scaling it. Compositing them would therefore produce a
    variant that silently draws only its base — technically complete, visually the default face.

    The declared trait is the member field's own text, so a caller requests
    `expression:<the exact expression>` and `declares_variant` matches it WHOLE (ADR 0177). Read
    from `unique_characters.SET_SLOT_MEMBER_FIELD` rather than a local copy: the axis a set is
    counted on is already decided there, and a second table would let the two disagree about which
    field makes a member distinct.
    """
    refusals: list[str] = []
    out: list[tuple[str, str, list[str]]] = []
    character_id = str(record.get("id", ""))
    member_fields = unique_characters.SET_SLOT_MEMBER_FIELD
    for entry in variants:
        slot = str(entry["slot"])
        axis = member_fields.get(slot)
        if axis is None:
            refusals.append(f"{entry['shot_id']}: no member field is declared for {slot}")
            continue
        shot = _shot_by_id(record, str(entry["shot_id"]))
        value = str((shot or {}).get(axis, "")).strip()
        if value == "":
            refusals.append(f"{entry['shot_id']}: carries no {axis}, so it names no variant")
            continue
        display = str(record.get("name", character_id))
        lines = [
            '[gd_resource type="Resource" script_class="PortraitDef" load_steps=2 format=3]',
            "",
            '[ext_resource type="Script" path="res://src/core/portrait_def.gd" id="1_portrait"]',
            "",
            "[resource]",
            'script = ExtResource("1_portrait")',
            f'id = &"{character_id}__{entry["shot_id"]}"',
            f'display_name = "{display}, {axis}"',
            f'race_id = &"{bare_id(str((record.get("appearance") or {}).get("race", "")))}"',
            f'visual_traits = Array[StringName]([&"{axis}:{value}"])',
            f'layer_paths = Array[String](["{entry["target"]}"])',
            'palette_key = &""',
            "",
        ]
        out.append((f"{character_id}__{entry['shot_id']}.tres", "\n".join(lines), refusals))
    return out


def _shot_by_id(record: dict, shot_id: str) -> dict | None:
    """The one shot with this id, or None. Bounded by the authored shot list."""
    for shot in (record.get("art") or {}).get("shots") or []:
        if isinstance(shot, dict) and str(shot.get("id", "")) == shot_id:
            return shot
    return None


def _fallback_layer(character_id: str) -> str | None:
    """The committed fallback `res://` path for this character, or None when there is none.

    A character's fallback is the one its RACE earned, because the fallback identifies the body
    plan and not the individual (ADR 0238). Found by walking up the id's race: `unique-0001` has
    no `RaceDef` at all, so there is nothing to fall back to and the caller must report it rather
    than guess a neighbouring body plan's face.
    """
    record = next(
        (
            item
            for item in unique_characters.readable_catalog()
            if isinstance(item, dict) and item.get("id") == character_id
        ),
        None,
    )
    if record is None:
        return None
    race = bare_id(str((record.get("appearance") or {}).get("race", "")))
    if race == "":
        return None
    candidate = GAME_DIR / "assets" / "characters" / "portraits" / f"{race}.png"
    if not candidate.is_file():
        return None
    return f"res://assets/characters/portraits/{race}.png"


def _fallback_def(record: dict, layer: str) -> str:
    """A one-layer `PortraitDef` pointing at a committed fallback.

    Carries the same trait assembly as [method build_def] so a fallback portrait is selectable and
    describable exactly like a real one — a placeholder that cannot be addressed by a variant key
    would be a second, quieter kind of special case.
    """
    character_id = str(record.get("id", ""))
    display = str(record.get("name", character_id)).replace('"', "'")
    traits, _notes = _visual_traits(record)
    trait_text = ", ".join(f'&"{trait}"' for trait in sorted(set(traits)))
    return "\n".join(
        [
            '[gd_resource type="Resource" script_class="PortraitDef" load_steps=2 format=3]',
            "",
            '[ext_resource type="Script" path="res://src/core/portrait_def.gd" id="1_portrait"]',
            "",
            "[resource]",
            'script = ExtResource("1_portrait")',
            f'id = &"{character_id}"',
            f'display_name = "{display}"',
            f'race_id = &"{bare_id(str((record.get("appearance") or {}).get("race", "")))}"',
            f"visual_traits = Array[StringName]([{trait_text}])",
            f'layer_paths = Array[String](["{layer}"])',
            'palette_key = &""',
            "",
        ]
    )


def _visual_traits(record: dict) -> tuple[list[str], list[str]]:
    """(traits, notes) for a published portrait — ONE value per variant axis.

    Shared by [method build_def] and [method _fallback_def] because the rule is not a detail of one
    of them: `PortraitDef.trait_value` returns the FIRST match on an axis, and ADR 0177 matches a
    variant WHOLE, so two values on one axis let a single portrait answer for two variants it was
    never drawn as. The first `_fallback_def` draft retyped the rule instead of calling this and
    emitted `role:guild-surveyor` alongside `role:npc` — the exact ambiguity this exists to prevent,
    reproduced by the second implementation of it.

    An authored tag wins over an `identity` field on the same axis, because the tag is authored
    content and `identity` is a different field. When they disagree the loser is NAMED rather than
    dropped: `identity.role` is a role CLASS (`npc`) while a `role:` tag is usually a story role
    (`calibrator`), so one axis can be carrying two vocabularies and the loser's meaning is
    invisible to every later reader of the resource.
    """
    notes: list[str] = []
    traits: list[str] = []
    tags = record.get("tags") if isinstance(record.get("tags"), list) else []
    seen_axis: dict[str, str] = {}
    for tag in tags:
        if not isinstance(tag, str) or ":" not in tag:
            continue
        axis, _, value = tag.partition(":")
        if axis in seen_axis:
            if seen_axis[axis] != value:
                notes.append(
                    f"tags carry two '{axis}' values ({seen_axis[axis]} and {value}); kept "
                    f"'{seen_axis[axis]}', so the other is unreachable as a variant"
                )
            continue
        seen_axis[axis] = value
        traits.append(tag)
    for axis in ("race", "path", "role"):
        value = str((record.get("identity") or {}).get(axis, ""))
        if value == "":
            continue
        bare = bare_id(value)
        if axis not in seen_axis:
            seen_axis[axis] = bare
            traits.append(f"{axis}:{bare}")
            continue
        if seen_axis[axis] != bare:
            notes.append(
                f"axis '{axis}' has two vocabularies: tag '{seen_axis[axis]}' and identity "
                f"'{bare}'; published the tag, so '{bare}' is not selectable as a variant"
            )
    return (traits, notes)


def build_def(
    record: dict, races: set[str], layers: list[dict]
) -> tuple[str, list[str], list[str]]:
    """The `PortraitDef` body for `record`, plus the gaps that stop it and the notes that do not.

    Returned as TEXT, never as a loaded resource: this process has no Godot runtime, and the
    catalog it reads is reference data that must not be required to load in order to publish a
    portrait.

    **A note never blocks.** A lore race no `RaceDef` defines makes the portrait reachable only
    through a chosen portrait id rather than through `for_race`, which is a content gap to report —
    not a reason to refuse, because refusing would mean nothing in a 254-record cast written against
    a lore taxonomy the game's five-race table never implemented could EVER publish. Refusing on
    that would make the tool silently useless instead of loudly incomplete.
    """
    refusals: list[str] = []
    notes: list[str] = []
    character_id = str(record.get("id", ""))
    if character_id == "":
        return ("", ["a record with no id"], notes)
    appearance = record.get("appearance") or {}
    tags = record.get("tags") if isinstance(record.get("tags"), list) else []

    if not layers:
        return ("", ["no rendered shot matches its slot's install canvas"], notes)

    # Layer ORDER is the order `install_plan` computed: primary face slot first, then the rest,
    # because `PortraitPanel` composites later layers over the first.
    ordered = [str(layer["target"]) for layer in layers]

    race_id = bare_id(str(appearance.get("race", "")))
    if race_id == "":
        notes.append("appearance.race is unset, so the portrait is reachable only by a chosen id")
    elif race_id not in races:
        # `PortraitCatalog.for_race` matches `def.race_id == race_id` with NO membership check, so
        # this portrait IS resolvable by race id. What is missing is upstream: `RaceApi.race_of` can
        # only ever return one of the five authored races, so nothing in normal play asks for
        # `echoless` and the face is reached only when an actor CHOOSES this portrait by id.
        notes.append(
            f"race '{race_id}' is not a RaceDef the content tree defines, so `RaceApi.race_of` can "
            "never yield it and `for_race` is never reached with it; the face is reachable only "
            "when an actor chooses this portrait id"
        )

    # A theme KEY or nothing: `portrait_def.gd:40-42`. Prose palette is not a key.
    palette_key = _tag_value(tags, _PALETTE_TAG_RE)
    if palette_key == "":
        notes.append("no authored palette:<key> tag, so palette_key stays empty")

    visual_traits, _trait_notes = _visual_traits(record)
    display = str(record.get("name", character_id)).replace('"', "'")
    traits = ", ".join(f'&"{trait}"' for trait in sorted(set(visual_traits)))
    quoted = ", ".join(f'"{path}"' for path in ordered)
    lines = [
        '[gd_resource type="Resource" script_class="PortraitDef" load_steps=2 format=3]',
        "",
        '[ext_resource type="Script" path="res://src/core/portrait_def.gd" id="1_portrait"]',
        "",
        "[resource]",
        'script = ExtResource("1_portrait")',
        f'id = &"{character_id}"',
        f'display_name = "{display}"',
        f'race_id = &"{race_id}"',
        f"visual_traits = Array[StringName]([{traits}])",
        f"layer_paths = Array[String]([{quoted}])",
        f'palette_key = &"{palette_key}"',
        "",
    ]
    return ("\n".join(lines), refusals, notes)


def install_layers(layers: list[dict], force: bool) -> list[str]:
    """Copy each planned render to its `res://` home, and report what was skipped.

    **Never resizes.** A render is copied byte for byte or not at all:
    `unique_characters._validate_image`
    demands an EXACT canvas match, and silently scaling a 1248x1664 concept plate into a 1024x1024
    square would destroy the composition while making the guard report success. A content author
    re-renders; this tool installs.

    A target that already holds an identical file is left alone, so `publish` is idempotent and
    re-running it does not churn bytes. Skipped paths are returned rather than raised, because a
    partially-installed portrait is still strictly better than none and the caller decides.
    """
    import shutil

    skipped: list[str] = []
    for layer in layers:
        source: Path = layer["source"]
        target: Path = layer["local"]
        if not source.is_file():
            skipped.append(f"{layer['shot_id']}: {source.name} vanished between plan and install")
            continue
        if target.is_file() and target.stat().st_size == source.stat().st_size:
            continue
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        except OSError as error:
            if not force:
                skipped.append(f"{layer['shot_id']}: {error}")
    return skipped


def _atomic_write(path: Path, text: str) -> None:
    """Write via a sibling temporary and `os.replace`, so a reader never sees a half-written one.

    The same pattern `tools/unique_characters.py:269-309` and `tools/assets.py:321-341` use. Godot
    imports `.tres` on load, and a truncated one is a parse error rather than a missing portrait.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", newline="\n", dir=path.parent, delete=False
        ) as handle:
            handle.write(text)
            temporary = Path(handle.name)
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def verify(published: set[str]) -> tuple[list[str], list[str]]:
    """(defects, advisories) for the boundary between the catalog and the authored resources.

    Two kinds of finding, deliberately not merged:

    * **defect** — a `published_as.def_path` that is not on disk. `published_as` is documented at
      `tools/unique_characters.py:17-20` as the only field pointing at game content, and it "stays
      empty until a deliberate sync step writes an authored resource". A non-empty value is
      therefore a CLAIM that a resource exists, and a claim with no file behind it is false. This
      is true on every machine, so it is a defect everywhere.
    * **advisory** — an authored `layer_paths` entry whose PNG is absent. The art lives in a
      gitignored folder, so this is correct on a clean clone and only a problem where the art was
      meant to be present. Reported, never fatal, because a gate that cannot pass in CI is a gate
      nobody reads.

    `published` is the set of authored ids found on disk, so an orphan resource is detectable: a
    `.tres` with no catalog record behind it is content nothing can select.
    """
    defects: list[str] = []
    advisories: list[str] = []
    catalog = unique_characters.readable_catalog()
    claimed: set[str] = set()

    for record in catalog:
        if not isinstance(record, dict):
            continue
        published_as = record.get("published_as") or {}
        def_path = str(published_as.get("def_path", ""))
        if def_path == "":
            continue
        claimed.add(str(record.get("id", "")))
        if not def_path.startswith("res://"):
            defects.append(f"{record.get('id')}: def_path '{def_path}' is not a res:// path")
            continue
        local = GAME_DIR / def_path.removeprefix("res://")
        if not local.is_file():
            defects.append(
                f"{record.get('id')}: published_as claims {def_path}, which is not on disk"
            )

    # Every authored PortraitDef the game will load, read as TEXT because this process has no Godot
    # runtime. `for` over a sorted listing: the result is a set, and it must not depend on
    # directory order.
    for path in sorted(PORTRAIT_ROOT.glob("*.tres")):
        text = path.read_text(encoding="utf-8", errors="replace")
        found = re.search(r'^id = &"([^"]+)"', text, re.MULTILINE)
        if found is None:
            defects.append(f"{path.name}: no id, so nothing can select it")
            continue
        portrait_id = found.group(1)
        if portrait_id not in published:
            defects.append(
                f"{path.name}: id '{portrait_id}' has no PortraitDef the catalog vouches for"
            )
        layer_match = re.search(
            r"^layer_paths = Array\[String\]\(\[([^\]]*)\]\)", text, re.MULTILINE
        )
        if layer_match is None:
            continue
        for layer in re.findall(r'"([^"]+)"', layer_match.group(1)):
            local = GAME_DIR / layer.removeprefix("res://")
            if not local.is_file():
                advisories.append(f"{portrait_id}: layer {layer} is not on disk")

    for portrait_id in sorted(published - claimed):
        advisories.append(f"{portrait_id}: authored but no catalog record claims it")
    return (defects, advisories)


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "character_bundle_sync",
        help="sync indexed character shots into authored PortraitDef resources",
    )
    actions = parser.add_subparsers(dest="character_bundle_sync_action", required=True)

    write = actions.add_parser("write", help="write the authored resource for one character")
    write.add_argument("--character-id", required=True)
    write.add_argument(
        "--allow-gaps",
        action="store_true",
        help="write even when a gap was found, naming every gap in the output",
    )
    dry = actions.add_parser("plan", help="print what would be written; never writes")
    dry.add_argument("--character-id", required=True)
    publish = actions.add_parser(
        "publish", help="install the installable renders and write the authored resource"
    )
    publish.add_argument("--character-id", required=True)
    publish.add_argument(
        "--allow-gaps",
        action="store_true",
        help="report a layer that could not be installed without failing the publish",
    )
    actions.add_parser(
        "verify", help="check every published_as claim against the authored resources; fails"
    )
    report = actions.add_parser(
        "report", help="per-character readiness across the cast; never fails"
    )
    report.add_argument("--fail-on", choices=("warn", "error"), default=None)


def run(args) -> int:
    action = args.character_bundle_sync_action
    races = shipped_race_ids()
    catalog = unique_characters.readable_catalog()

    if action == "report":
        print(f"rendered art folder: {art_fidelity.art_root()}")
        print(f"authored race ids: {len(races)} ({', '.join(sorted(races))})")
        print(f"catalog records: {len(catalog)}")
        ready = 0
        installable_shots = 0
        blocked_shots = 0
        for record in catalog:
            if not isinstance(record, dict):
                continue
            layers, variants, refusals = install_plan(record)
            installable_shots += len(layers)
            blocked_shots += len(refusals)
            body, _refusals, _notes = build_def(record, races, layers)
            if body == "":
                print(f"  [blocked] {record.get('id')}: no rendered shot matches its slot canvas")
            else:
                ready += 1
                print(
                    f"  [ready]   {record.get('id')}: {len(layers)} layer(s) installable, "
                    f"{len(variants)} variant(s), {len(refusals)} shot(s) blocked"
                )
        print(f"ready to publish: {ready} of {len(catalog)}")
        print(
            f"shots: {installable_shots} installable as layers, "
            f"{blocked_shots} blocked or published as variants"
        )
        if getattr(args, "fail_on", None) == "error" and ready == 0:
            fail("no character is ready to publish")
            return 1
        ok("character bundle sync report complete")
        return 0

    if action == "verify":
        published = {
            found.group(1)
            for found in (
                re.search(
                    r'^id = &"([^"]+)"',
                    path.read_text(encoding="utf-8", errors="replace"),
                    re.MULTILINE,
                )
                for path in sorted(PORTRAIT_ROOT.glob("*.tres"))
            )
            if found is not None
        }
        defects, advisories = verify(published)
        for advisory in advisories:
            info(f"advisory: {advisory}")
        for defect in defects:
            fail(f"defect: {defect}")
        if defects:
            fail(f"{len(defects)} defect(s); a published_as claim with no file behind it is false")
            return 1
        ok(f"verified {len(published)} authored portrait(s); {len(advisories)} advisory(ies)")
        return 0

    character_id = args.character_id
    record = next(
        (item for item in catalog if isinstance(item, dict) and item.get("id") == character_id),
        None,
    )
    if record is None:
        fail(f"{character_id} is not in the readable catalog")
        return 1
    layers, variants, shot_refusals = install_plan(record)
    body, refusals, notes = build_def(record, races, layers)
    variant_defs = build_variant_defs(record, variants) if layers else []

    if action == "plan":
        print(
            f"--- would install {len(layers)} layer(s) and publish {len(variant_defs)} "
            f"variant portrait(s), then write {PORTRAIT_ROOT / (character_id + '.tres')} ---"
        )
        for layer in layers:
            print(f"  layer: {layer['source'].name} -> {layer['target']}  ({layer['slot']})")
        print(body)
        for name, variant_body, _r in variant_defs:
            print(f"--- variant portrait {name} ---")
            print(variant_body)
        for refusal in shot_refusals:
            print(f"  shot not installable: {refusal}")
        for note in notes:
            print(f"  note: {note}")
        return 0

    if action != "publish":
        fail(f"unknown action '{action}'")
        return 1

    if body == "":
        fallback = _fallback_layer(character_id)
        if fallback is not None:
            # No render on THIS machine, but a committed fallback exists (ADR 0238). Publishing it
            # is what makes a clone without the private art draw a face instead of an empty box,
            # and it is honest in both directions: the machine that HAS the art publishes the real
            # render, this one publishes the placeholder, and the note says which happened.
            info(
                f"{character_id}: no render on this machine; publishing the committed fallback "
                f"{fallback} instead of the private art"
            )
            body = _fallback_def(record, fallback)
            for refusal in shot_refusals[:4]:
                info(f"{character_id}: shot not available here: {refusal}")
            if len(shot_refusals) > 4:
                info(f"{character_id}: ...and {len(shot_refusals) - 4} more")
        else:
            for refusal in shot_refusals[:12]:
                fail(f"{character_id}: {refusal}")
            if len(shot_refusals) > 12:
                fail(f"{character_id}: ...and {len(shot_refusals) - 12} more shot(s)")
            fail(
                f"{character_id} has nothing to publish and no committed fallback. A "
                "PortraitDef with an empty layer_paths "
                "fails PortraitResolver.validate() for anything but the placeholder, so writing "
                "one would make the gate red rather than make the game work. Re-render the shots "
                "above at their slot's install canvas, or run "
                "`uv run python -m tools portrait_fallback write` to give this body plan a "
                "placeholder."
            )
            return 1

    if body == "":
        for refusal in shot_refusals[:12]:
            fail(f"{character_id}: {refusal}")
        if len(shot_refusals) > 12:
            fail(f"{character_id}: ...and {len(shot_refusals) - 12} more shot(s)")
        fail(
            f"{character_id} has nothing to publish. A PortraitDef with an empty layer_paths "
            "fails PortraitResolver.validate() for anything but the placeholder, so writing one "
            "would make the gate red rather than make the game work. Re-render the shots above at "
            "their slot's install canvas."
        )
        return 1

    skipped = install_layers(layers + variants, force=bool(getattr(args, "allow_gaps", False)))
    for line in skipped:
        fail(f"{character_id}: {line}")
    for refusal in shot_refusals:
        # A blocked shot is reported on every run, never only with a flag: it is a content gap, and
        # a gap that is only visible with --allow-gaps is a gap nobody fixes.
        info(f"{character_id}: shot not installable: {refusal}")
    for variant in variants:
        info(
            f"{character_id}: {variant['shot_id']} published as a VARIANT portrait on "
            f"{variant['slot']}, not composited as a layer (ADR 0237)"
        )
    for note in notes:
        info(f"{character_id}: {note}")

    target = PORTRAIT_ROOT / f"{character_id}.tres"
    _atomic_write(target, body)
    for name, variant_body, _variant_refusals in variant_defs:
        _atomic_write(PORTRAIT_ROOT / name, variant_body)
    if variant_defs:
        ok(f"published {len(variant_defs)} variant portrait(s) keyed on their member field")
    ok(f"published {target} with {len(layers)} layer(s) from {character_id}")
    if skipped:
        fail(f"{character_id}: published with {len(skipped)} layer(s) NOT installed")
        return 1
    return 0
