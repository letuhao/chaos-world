"""Author, validate, brief, and install reference art for the named cast.

`tools/character_assets.py` generates the anonymous cast: 2,000 balanced
`character-NNNN` profiles, one PNG per fixed slot, one shared style string, and
tags as the whole of a person's identity. That is the right shape for a crowd
and the wrong shape for a named character, who needs lore, a history, a
personality, a voice, and several images at different poses.

So the named cast is a SEPARATE catalog with its own id namespace, its own
folder, and its own index. Nothing links the two: deleting this index cannot
delete a face, and authoring a named character cannot perturb the 2,000-row
balance the other catalog guarantees.

This is REFERENCE data. It is not read by the game and must not become a runtime
dependency. `PortraitResolver` resolves from authored `res://data/portraits`
resources, and `tests/core/test_portrait_resolver.gd` asserts the resolver's
source names neither `character-index` nor `unique-index`. `published_as` is the
only field that points at game content and it stays empty until a deliberate
sync step writes an authored resource (ADR 0131).

`reference_stats` is PROSE by decision, and `_no_stat_numbers` is the guard that
keeps it prose.

Generation is deliberately absent. `plan` renders the art brief, which is the
deterministic half; the ComfyUI half lands separately against whatever workflow
the art direction settles on. A tool whose generate path cannot run yet would be
a tool whose generate path rots unobserved.
"""

from __future__ import annotations

import json
import os
import re
import tempfile
from collections import Counter
from datetime import UTC, datetime
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from .character_assets import CHARACTER_NEGATIVE
from .common import GAME_DIR, REPO_ROOT, ToolError, fail, info, ok

INDEX_PATH = GAME_DIR / "assets" / "characters" / "unique-index.jsonl"
# Art only. The index sits one level up on purpose: `.gitignore` excludes
# `game/assets/characters/*/` (directories only), so the catalog and its prose
# stay tracked while every generated PNG stays local.
UNIQUE_ROOT = GAME_DIR / "assets" / "characters" / "unique"
PATH_PREFIX = "res://assets/characters/unique/"

ID_RE = re.compile(r"^unique-[0-9]{4,}$")
SLUG_RE = re.compile(r"^[a-z0-9]+(?:[_-][a-z0-9]+)*$")
NUMBER_ONLY_RE = re.compile(r"^[\s+-]*\d+(?:\.\d+)?%?\s*$")

VALID_STATUS = {"draft", "canon", "retired"}
VALID_ROLES = {"pc", "npc", "boss"}
VALID_PATHS = {"qi", "body", "mind", "unaffiliated"}

# The routing vocabulary for the future backend: kind picks the ComfyUI
# workflow, and the kinds need different ones (a turnaround sheet and a scene
# illustration are not the same graph). Shots stay free-form WITHIN a kind,
# which is what lets one character carry nine portraits and still fit the
# schema. Adding a kind is a one-line change here and nothing else.
#
# `kind` answers HOW to render. `slot` answers WHY the shot exists, and it is
# the only one of the two with a required minimum: a catalog whose kinds are all
# correct but whose slots are absent still renders nine pictures of the same
# person, which passes every kind check here and is useless to a downstream
# generator told to produce a map token. Five kinds cover the nine required
# prompts because an expression sheet and a dialogue portrait are the same graph
# at different framings — the split is by render graph, not by prompt count.
SHOT_KINDS = ("map_sprite", "concept", "portrait", "dialogue", "scene")

PROMPT_SLOTS = (
    "map_sprite",
    "dialogue_portrait",
    "character_portrait",
    "concept_art",
    "environmental_concept",
    "combat_concept",
    "relationship_scene",
    "expression_set",
    "pose_set",
)

# The kind each single-shot slot is rendered as. A slot drawn by the wrong graph
# is a mislabelled prompt, so this is a FAIL rather than a note: otherwise a
# `map_sprite` slot quietly holds a 1024px waist-up portrait and the small-scale
# exploration representation the brief asks for is simply absent from the catalog.
SLOT_KIND = {
    "map_sprite": "map_sprite",
    "dialogue_portrait": "dialogue",
    "character_portrait": "portrait",
    "concept_art": "concept",
    "environmental_concept": "concept",
    "combat_concept": "concept",
    "relationship_scene": "scene",
}

# Slots holding a SET rather than one picture. The minimum is the count the art
# brief enumerates, not a round number, so raising it is a spec change rather
# than a taste change: the expression brief names nine emotions and the pose
# brief names six. These are PROMPT counts, not rendered images — generation is
# `unique_characters next`, which stays optional per shot.
SET_SLOT_MINIMUMS = {"expression_set": 9, "pose_set": 6}

# Which field distinguishes one member of a set from the next. It is not
# `expression` for both, and assuming it was is the bug this table exists to
# prevent: a pose set is nine shots differing in `pose`, and counting it on
# `expression` would demand nine distinct emotions from a character being asked
# for nine stances — a requirement no author can satisfy without writing the
# emotion field as a restatement of the pose.
SET_SLOT_MEMBER_FIELD = {"expression_set": "expression", "pose_set": "pose"}
SHOT_STATUS = {"planned", "generated", "approved"}
DEFAULT_CANVAS = [1024, 1024]
CANVAS_MAX = 4096

# `art.style` is a free-form slug, NOT a closed enum. The art direction has not
# settled the style list yet, and guessing one here would only have to be
# corrected when the ComfyUI workflow arrives. `report` prints the inventory so
# a typo is visible; the closed vocabulary gets added when the backend that
# routes on it exists.

# Required so an art brief cannot silently omit half a face. Extra keys are
# allowed: a named character has more to describe than an anonymous one.
APPEARANCE_KEYS = (
    "race",
    "presentation",
    "age",
    "build",
    "complexion",
    "hair",
    "eyes",
    "palette",
    "attire",
    "marks",
    "bearing",
)
PERSONALITY_KEYS = ("summary", "traits", "mannerisms", "motivations", "flaws", "voice", "taboos")
STATS_KEYS = ("summary", "strengths", "weaknesses", "combat_read", "notes")
CANON_KEYS = (
    "role_in_story",
    "first_appearance",
    "lore",
    "history",
    "personality",
    "relationships",
)

# Fields an installed shot must carry. A shot without these is a PNG with no
# stated origin, which is exactly what the minor-character catalog refuses too.
PROVENANCE_FIELDS = ("source", "prompt", "generated_on", "license")

STAT_DEFS = GAME_DIR / "src" / "contracts" / "stat.gd"

# The standing content rules, restated where they are used rather than only
# where they are defined, so a brief cannot be pasted into ComfyUI without them.
BRIEF_CONSTRAINTS = (
    "One subject only: the single character described above, and nobody else.",
    "Transparent background, no ground plane, no cast shadow beyond a soft contact edge.",
    "All characters are adults, fully clothed, and nonsexual.",
    "Fully covered costume: high collar, long sleeves, covered shoulders, no open neckline.",
    "No text, labels, letters, UI, frame, border, signature, or watermark.",
    "No childlike features and no exaggerated body proportions.",
)


# --- catalog ---------------------------------------------------------------


def _catalog_paths() -> list[Path]:
    """Every catalog shard, in a stable order.

    Sharding exists because a single catalog cannot be written by two agents. Each
    writer loads the whole catalog into memory and then rewrites the file from that
    snapshot, so two agents on disjoint id ranges lose whichever write lands second -
    silently, with no error and no warning. Simulated and confirmed before this
    existed: agent A wrote 2 rows, agent B then wrote its own 2 rows from a
    pre-A snapshot, and A's rows were gone.

    A shard per writer removes the collision entirely: two agents working at once
    touch different files, and neither read-modify-writes the other's.
    """
    if not INDEX_PATH.parent.is_dir():
        return []
    primary = INDEX_PATH if INDEX_PATH.is_file() else None
    shards = sorted(
        path for path in INDEX_PATH.parent.glob(f"{INDEX_PATH.stem}-*.jsonl") if path.is_file()
    )
    return [primary, *shards] if primary else shards


def _load_index() -> list[dict]:
    """Every character across every shard, primary file first.

    A record id may not appear twice: duplicate ids are a validation failure, and a
    shard scheme that allowed them would make that failure ambiguous between "an
    author copied a row" and "two shards claimed the same character".
    """
    paths = _catalog_paths()
    if not paths:
        raise ToolError(f"no unique-character catalog at {INDEX_PATH}; run `unique_characters add`")
    records: list[dict] = []
    for path in paths:
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ToolError(f"{path.name}:{number}: invalid JSON ({exc.msg})") from exc
            if not isinstance(record, dict):
                raise ToolError(f"{path.name}:{number}: each line must be an object")
            records.append(record)
    return records


def _shard_is_complete(path: Path) -> bool:
    """True when every line in a shard parses.

    A shard being written by an agent that bypassed `unique_characters add` is
    observable half-finished: an observed case grew 72KB -> 117KB over four minutes
    with a torn line at the end, and every other agent on the program was blocked by
    it. `_atomic_write` alone does not prevent that - it only guarantees files IT
    writes are never partial - so a reader needs a way to tell "this shard is
    mid-write" from "this shard is broken".

    It does not prove a shard is finished either. That is what the canon gate and the
    duplicate check are for; this only distinguishes a torn tail from a good catalog.
    """
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                json.loads(line)
    except json.JSONDecodeError:
        return False
    return True


def readable_catalog() -> list[dict]:
    """Every character from every shard that currently parses.

    For concurrent readers ONLY: an agent adding characters must not be able to block
    every other agent by writing a shard directly instead of through the tool. A
    shard with a torn line is skipped rather than raised, and `check` still reports it
    so a permanently broken shard is visible instead of quietly invisible.

    Never use this to write. `_load_index` is the strict reader, and a write built on
    a partial view would drop the rows it could not see - which is the exact clobber
    the shard flag exists to prevent.
    """
    records: list[dict] = []
    for path in _catalog_paths():
        if not _shard_is_complete(path):
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(record, dict):
                records.append(record)
    return records


def _atomic_write(records: list[dict], path: Path | None = None) -> None:
    """Write `records` to one shard, MERGING with whatever is already in it.

    Merging rather than overwriting is what makes a shard safe to write
    concurrently: a writer that only knows its own characters still preserves every
    other row in the file it touches. An earlier version wrote the whole file from
    the caller's in-memory list, which silently deleted other agents' characters.
    """
    target = path or INDEX_PATH
    target.parent.mkdir(parents=True, exist_ok=True)
    by_id: dict[str, dict] = {}
    order: list[str] = []
    if target.is_file():
        for line in target.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            existing = json.loads(line)
            key = existing.get("id")
            if key not in by_id:
                order.append(key)
            by_id[key] = existing
    for record in records:
        key = record.get("id")
        if key not in by_id:
            order.append(key)
        by_id[key] = record
    content = "".join(
        json.dumps(by_id[key], ensure_ascii=False, separators=(",", ":")) + "\n"
        for key in sorted(order, key=lambda item: str(item))
    )
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", newline="\n", dir=target.parent, delete=False
        ) as handle:
            handle.write(content)
            temporary = Path(handle.name)
        os.replace(temporary, target)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()


def _character(records: list[dict], character_id: str) -> dict:
    if not ID_RE.fullmatch(character_id):
        raise ToolError(f"invalid unique-character id {character_id!r}; expected unique-NNNN")
    record = next((item for item in records if item.get("id") == character_id), None)
    if record is None:
        raise ToolError(f"unknown unique character {character_id!r}")
    return record


def _shot(record: dict, shot_id: str) -> dict:
    shot = next(
        (item for item in record.get("art", {}).get("shots", []) if item.get("id") == shot_id),
        None,
    )
    if shot is None:
        names = ", ".join(str(item.get("id")) for item in record.get("art", {}).get("shots", []))
        raise ToolError(f"unknown shot {shot_id!r} on {record['id']}; it has: {names or 'none'}")
    return shot


def _blank_character(character_id: str, name: str, role: str, path: str, style: str) -> dict:
    """A `draft` shell: structurally valid, narratively empty.

    Drafts are allowed to be unfinished because reference data is written
    incrementally. Promoting one to `canon` is what demands the lore, the
    personality, and the prose stat read — see `_validate`.
    """
    return {
        "id": character_id,
        "name": name,
        "aliases": [],
        "status": "draft",
        "identity": {
            "role": role,
            "path": path,
            "faction": "",
            "home": "",
            "realm": "",
        },
        "appearance": {key: "" for key in APPEARANCE_KEYS},
        "tags": [],
        "canon": {
            "role_in_story": "",
            "first_appearance": "",
            "lore": "",
            "history": [],
            "personality": {
                "summary": "",
                "traits": [],
                "mannerisms": [],
                "motivations": [],
                "flaws": [],
                "voice": "",
                "taboos": [],
            },
            "relationships": [],
        },
        "reference_stats": {key: [] if key.endswith("s") else "" for key in STATS_KEYS},
        "art": {"style": style, "palette_notes": "", "shots": []},
        "published_as": {"portrait_id": "", "def_path": ""},
    }


# --- validation ------------------------------------------------------------


def _authored_stat_ids() -> set[str]:
    """Every stat id declared in `contracts/stat.gd`.

    Read from source rather than hardcoded so a stat added to the game is covered
    by `_no_stat_numbers` without editing this file.
    """
    if not STAT_DEFS.is_file():
        return set()
    text = STAT_DEFS.read_text(encoding="utf-8", errors="replace")
    return set(re.findall(r'^const [A-Z_0-9]+ := &"([a-z_0-9]+)"', text, re.M))


def _no_stat_numbers(block: object, label: str, stat_ids: set[str]) -> list[str]:
    """`reference_stats` describes how a character fights; it does not compute one.

    A number that lands in this block is the exact shape a balance surface
    takes, and a balance surface reached by editing a reference document is
    invisible to every guard that already exists: `realm_power check` reads the
    authored power table, `tools arch` reads the module graph, and neither can
    see a JSONL row. So the two ways a number gets in are refused here — a bare
    JSON number anywhere in the block, and a number assigned to one of the
    authored stat ids, in a key or in prose (`physique: 40`).

    A digit that is merely part of a name ("the 9th Brother") is not a stat and
    still passes, which is why this matches stat ids rather than any digit.
    """
    findings: list[str] = []
    if isinstance(block, bool):
        return findings
    if isinstance(block, (int, float)):
        return [f"{label}: {block!r} is a number; this block is prose, so describe it instead"]
    if isinstance(block, dict):
        for key, value in block.items():
            if key in stat_ids and isinstance(value, (int, float)):
                findings.append(f"{label}.{key}: assigns a number to an authored stat")
            findings.extend(_no_stat_numbers(value, f"{label}.{key}", stat_ids))
        return findings
    if isinstance(block, list):
        for index, value in enumerate(block):
            findings.extend(_no_stat_numbers(value, f"{label}[{index}]", stat_ids))
        return findings
    if isinstance(block, str):
        if NUMBER_ONLY_RE.match(block):
            findings.append(f"{label}: {block!r} is a bare number; this block is prose")
        for stat_id in stat_ids:
            pattern = rf"\b{re.escape(stat_id)}\s*[:=]\s*-?\d"
            if re.search(pattern, block, re.IGNORECASE):
                findings.append(f"{label}: '{stat_id}' is given a number; describe it instead")
    return findings


# Two characters are the same character when their prose is the same prose. Names
# are free-form and agents rename constantly, so the signal is the TEXT and not
# the label - but the comparison is exact token Jaccard rather than a model,
# because a validator that can be argued with is not a validator.
#
# 0.80 is the duplicate line and 0.55 the shallow-variant line, and the variant
# check ALSO requires an identical structural slot. That second condition is what
# makes the threshold safe: two unrelated characters may well write similar
# sentences about the same world, but two characters in the same role, on the same
# path, of the same race, in the same faction, saying the same thing, is the
# monoculture this catalog exists to avoid - whatever they are called.
DUPLICATE_JACCARD = 0.80
VARIANT_JACCARD = 0.55

# Reported, never failed: a cast that is mostly unaffiliated has not been given a
# cultivation system, it has been left one out. The number only means something at
# scale, and a gate that fires on a ten-character catalog is a gate nobody reads.
DIVERSITY_MAX_SHARE = 0.25

# Fields carrying WHO a character is, as opposed to how they are drawn. Appearance
# is deliberately excluded: two characters with the same build are not duplicates.
IDENTITY_FIELDS = ("role_in_story", "lore", "first_appearance")

_WORD_RE = re.compile(r"[a-z0-9]+")


def _tokens(text: object) -> frozenset[str]:
    if not isinstance(text, str):
        return frozenset()
    return frozenset(_WORD_RE.findall(text.lower()))


def _jaccard(left: frozenset[str], right: frozenset[str]) -> float:
    if not left or not right:
        return 0.0
    intersection = len(left & right)
    if intersection == 0:
        return 0.0
    return intersection / len(left | right)


def _identity_text(record: dict) -> str:
    canon = record.get("canon") if isinstance(record.get("canon"), dict) else {}
    parts = [canon.get(field) for field in IDENTITY_FIELDS]
    return " ".join(part for part in parts if isinstance(part, str) and part.strip())


def _slot(record: dict) -> tuple[str, str, str, str]:
    """The structural position a character occupies - what a variant would keep."""
    identity = record.get("identity") if isinstance(record.get("identity"), dict) else {}
    appearance = record.get("appearance") if isinstance(record.get("appearance"), dict) else {}
    return (
        str(identity.get("role", "")),
        str(identity.get("path", "")),
        str(appearance.get("race", "")),
        str(identity.get("faction", "")),
    )


def _duplicate_findings(records: list[dict]) -> list[str]:
    """Duplicates and shallow variants, found by prose rather than by name.

    O(n^2) over precomputed token sets, and that is deliberate at the 1000-record
    target: pairwise is EXACT, and a candidate prefilter would trade a known
    false-negative rate for speed this does not need. The failure a prefilter
    introduces is invisible and specific - two agents who independently write the
    same character, which is precisely the case worth catching.

    A draft with an empty identity text is skipped rather than compared. Two empty
    texts score 0.0 by the guard in `_jaccard`, so skipping them is an
    optimisation and not a hole.
    """
    findings: list[str] = []
    prepared: list[tuple[str, tuple[str, str, str, str], frozenset[str]]] = []
    seen_names: dict[str, str] = {}

    for record in records:
        if not isinstance(record, dict):
            continue
        character_id = str(record.get("id", "?"))
        name = record.get("name")
        if isinstance(name, str) and name.strip():
            key = name.strip().lower()
            if key in seen_names and seen_names[key] != character_id:
                findings.append(
                    f"{character_id}: name {name.strip()!r} is already used by {seen_names[key]}"
                )
            else:
                seen_names[key] = character_id
        text = _tokens(_identity_text(record))
        if text:
            prepared.append((character_id, _slot(record), text))

    for index, (left_id, left_slot, left_tokens) in enumerate(prepared):
        for right_id, right_slot, right_tokens in prepared[index + 1 :]:
            score = _jaccard(left_tokens, right_tokens)
            if score >= DUPLICATE_JACCARD:
                findings.append(
                    f"{right_id}: duplicate of {left_id} ({score:.0%} identical background text)"
                )
            elif score >= VARIANT_JACCARD and left_slot == right_slot:
                findings.append(
                    f"{right_id}: shallow variant of {left_id} "
                    f"({score:.0%} identical background in the same "
                    f"role/path/race/faction slot)"
                )
    return findings


def _diversity_axes(records: list[dict]) -> list[tuple[str, Counter]]:
    """Distributions worth watching, as (axis, counts) pairs.

    `role`, `path` and `race` are structural axes every character occupies. Tag
    axes are open-ended by design, so a tag axis with one value across the cast is
    a monoculture signal rather than an error.

    A tag may NOT claim a structural axis name. `setdefault` used to let a tag
    called `path:body-path` REPLACE the real `identity.path` counter, and the
    distribution then reported `path=none` and `path=body-path` - values that are
    not in `VALID_PATHS` at all - while the actual paths went uncounted. The axis
    read as six distinct values, which is the opposite of what happened.

    Structural axes are counted from their own fields and a colliding tag axis is
    counted under `tag:<name>` instead, so a collision is visible rather than
    silently substituting one measurement for another.
    """
    axes: dict[str, Counter] = {"role": Counter(), "path": Counter(), "race": Counter()}
    structural = {"role", "path", "race"}
    for record in records:
        if not isinstance(record, dict):
            continue
        identity = record.get("identity") if isinstance(record.get("identity"), dict) else {}
        appearance = record.get("appearance") if isinstance(record.get("appearance"), dict) else {}
        axes["role"][str(identity.get("role", "unset"))] += 1
        axes["path"][str(identity.get("path", "unset"))] += 1
        axes["race"][str(appearance.get("race") or "unset").strip() or "unset"] += 1
        tags = record.get("tags")
        for tag in tags if isinstance(tags, list) else []:
            if isinstance(tag, str) and ":" in tag:
                axis, value = tag.split(":", 1)
                key = f"tag:{axis}" if axis in structural else axis
                axes.setdefault(key, Counter())[value] += 1
    return sorted(axes.items())


# Scoped to the OPEN-ENDED axes. `role` has three values (pc, npc, boss), so in
# any small cast one value must repeat and exceed a 25% share by arithmetic alone:
# four records give 2/4 = 50%. Guarding `role` would fire on every catalog under
# roughly eight characters and teach authors to invent meaningless roles to
# silence a linter. `path` and `race` grow with the setting, so concentration on
# either is a real signal about the world rather than about the sample size.
DIVERSITY_GUARDED_AXES = ("path", "race")


def _concentration_warnings(records: list[dict]) -> list[str]:
    """Axes where one value has swallowed the cast. Reported, never failed."""
    total = sum(1 for record in records if isinstance(record, dict))
    if total < 2:
        return []
    warnings = []
    for axis, counts in _diversity_axes(records):
        if axis not in DIVERSITY_GUARDED_AXES:
            continue
        for value, count in counts.most_common():
            if count / total > DIVERSITY_MAX_SHARE:
                warnings.append(
                    f"{axis}={value} is {count}/{total} "
                    f"({count / total:.0%}) of the cast, over the "
                    f"{DIVERSITY_MAX_SHARE:.0%} share; a monoculture on a structural axis"
                )
    return warnings


def _validate(records: list[dict], *, check_files: bool) -> list[str]:
    issues: list[str] = []
    stat_ids = _authored_stat_ids()
    lore_entries = _lore_entries()
    if not stat_ids:
        issues.append(f"cannot read the authored stat vocabulary from {STAT_DEFS}")
    seen: set[str] = set()
    for index, record in enumerate(records, 1):
        label = f"line {index}"
        character_id = record.get("id")
        if not isinstance(character_id, str) or not ID_RE.fullmatch(character_id):
            issues.append(f"{label}: invalid id {character_id!r}; expected unique-NNNN")
            continue
        label = character_id
        if character_id in seen:
            issues.append(f"{label}: duplicate id")
            continue
        seen.add(character_id)
        if not _text(record.get("name")):
            issues.append(f"{label}: needs a name")

        status = record.get("status")
        if status not in VALID_STATUS:
            issues.append(f"{label}: status {status!r} must be one of {sorted(VALID_STATUS)}")
        if not isinstance(record.get("aliases"), list):
            issues.append(f"{label}: aliases must be a list")

        issues.extend(_validate_identity(record.get("identity"), label))
        issues.extend(_validate_appearance(record.get("appearance"), label))
        issues.extend(_validate_tags(record.get("tags"), label))
        issues.extend(_validate_canon(record.get("canon"), label, status))
        issues.extend(_validate_stats(record.get("reference_stats"), label, stat_ids))
        issues.extend(_validate_art(record.get("art"), label, check_files))

        published = record.get("published_as")
        if not isinstance(published, dict) or set(published) != {"portrait_id", "def_path"}:
            issues.append(f"{label}: published_as must hold exactly portrait_id and def_path")
        elif any(not isinstance(value, str) for value in published.values()):
            issues.append(f"{label}: published_as values must be strings")

        # The promotion gate. `draft` is allowed to be unfinished; `canon` is a
        # claim that the narrative is written, and an empty lore is a claim the
        # catalog cannot back. Appearance is required even on a draft, because an
        # empty face is not a narrative gap — it is a broken art brief.
        if status == "canon":
            canon = record.get("canon") if isinstance(record.get("canon"), dict) else {}
            personality = canon.get("personality")
            personality = personality if isinstance(personality, dict) else {}
            stats = record.get("reference_stats")
            stats = stats if isinstance(stats, dict) else {}
            art = record.get("art") if isinstance(record.get("art"), dict) else {}
            appearance = record.get("appearance")
            appearance = appearance if isinstance(appearance, dict) else {}
            identity = record.get("identity")
            identity = identity if isinstance(identity, dict) else {}
            for field, value in (
                ("canon.lore", canon.get("lore")),
                ("canon.personality.summary", personality.get("summary")),
                ("reference_stats.summary", stats.get("summary")),
                ("art.style", art.get("style")),
            ):
                if not _text(value):
                    issues.append(f"{label}: cannot be canon while {field} is empty")
            for key in APPEARANCE_KEYS:
                if not _text(appearance.get(key)):
                    issues.append(f"{label}: cannot be canon while appearance.{key} is empty")
            # The prompt set is part of the promotion gate rather than a separate
            # command, because `canon` is the claim that this character is fully
            # specified. A canon character missing its map token is a character
            # the exploration map cannot place, and finding that out at render
            # time is later than the only moment it is cheap to fix.
            for gap in _prompt_set_gaps(art):
                issues.append(f"{label}: cannot be canon while {gap}")
            # A bloodline is a concentration carried by a body, not a body. Ten
            # characters named one in `appearance.race` and named no species anywhere,
            # so they had no lifespan, no senses and no anatomy - and `check` passed,
            # because a non-empty string is a valid race. Ten characters is not a
            # labelling slip; it is a shape the schema could not see.
            if lore_entries is not None:
                bloodlines = bloodline_races(lore_entries)
                race_id = str(appearance.get("race", "")).strip()
                if race_id in bloodlines and not _names_a_species(record, lore_entries, bloodlines):
                    issues.append(
                        f"{label}: cannot be canon while appearance.race is {race_id!r}, "
                        f"which is a bloodline rather than a species, and no species is "
                        f"named anywhere in the record. Say which body carries the line."
                    )
            # A species can CLOSE a cultivation path, and a character cannot carry one
            # their own body makes impossible. Fifteen species do: commonborn closes
            # mind, rootmarch closes body, unwritten and wake close all three, and
            # `no-cultivation` closes everything without saying so in an attribute.
            #
            # Two characters were carrying a path their own lore forbids, and both
            # said so in their own prose - unique-0023 wrote "a rootmarch has no
            # heart-kidney channel and never gets past the fourth realm" while
            # carrying `path: body`. The record was self-refuting and `check` was
            # silent, because nothing compared the two fields.
            if lore_entries is not None:
                closed = species_closed_paths(lore_entries).get(race_id)
                if closed and str(identity.get("path", "")).strip() in closed:
                    issues.append(
                        f"{label}: cannot be canon while identity.path is "
                        f"{identity.get('path')!r}, which {race_id} closes "
                        f"({', '.join(sorted(closed))}). The species record is the "
                        f"authority on what its body can do."
                    )

    # Duplicates are checked across the whole catalog rather than per record,
    # because the defect is a RELATIONSHIP between two rows and neither row can
    # see it. A character unique in isolation and the third copy of one idea is
    # only discoverable pairwise.
    issues.extend(_duplicate_findings(records))
    return issues


def _validate_identity(identity: object, label: str) -> list[str]:
    if not isinstance(identity, dict):
        return [f"{label}: identity must be an object"]
    issues = []
    if identity.get("role") not in VALID_ROLES:
        issues.append(f"{label}: identity.role must be one of {sorted(VALID_ROLES)}")
    if identity.get("path") not in VALID_PATHS:
        issues.append(f"{label}: identity.path must be one of {sorted(VALID_PATHS)}")
    for field in ("faction", "home", "realm"):
        if not isinstance(identity.get(field, ""), str):
            issues.append(f"{label}: identity.{field} must be a string")
    return issues


def _validate_appearance(appearance: object, label: str) -> list[str]:
    """Shape only: every required key present, every value a string.

    Whether the face is actually DESCRIBED is a canon-gate question, not a
    structural one, so a draft can be created in one command and filled in.
    """
    if not isinstance(appearance, dict):
        return [f"{label}: appearance must be an object"]
    issues = [
        f"{label}: appearance is missing {key}" for key in APPEARANCE_KEYS if key not in appearance
    ]
    for key, value in appearance.items():
        if not isinstance(value, str):
            issues.append(f"{label}: appearance.{key} must be a string")
    return issues


def _validate_tags(tags: object, label: str) -> list[str]:
    """Shape only. The axis vocabulary is deliberately open.

    A named character carries axes an anonymous profile has no slot for
    (` scars:oath-burned `), and failing a record for inventing one would push
    authors back into the twelve closed axes. A typo'd axis is caught by reading
    `report`, which prints the inventory with counts.
    """
    if not isinstance(tags, list):
        return [f"{label}: tags must be a list"]
    issues = []
    for tag in tags:
        if not isinstance(tag, str) or ":" not in tag:
            issues.append(f"{label}: invalid tag {tag!r}; expected axis:value")
            continue
        axis, value = tag.split(":", 1)
        if not SLUG_RE.fullmatch(axis) or not SLUG_RE.fullmatch(value):
            issues.append(f"{label}: tag {tag!r} must be lowercase slug on both sides")
    return issues


def _validate_canon(canon: object, label: str, status: object) -> list[str]:
    if not isinstance(canon, dict):
        return [f"{label}: canon must be an object"]
    issues = []
    missing = set(CANON_KEYS) - set(canon)
    if missing:
        issues.append(f"{label}: canon is missing {', '.join(sorted(missing))}")
    for field in ("role_in_story", "first_appearance", "lore"):
        if not isinstance(canon.get(field, ""), str):
            issues.append(f"{label}: canon.{field} must be a string")
    if not isinstance(canon.get("history"), list):
        issues.append(f"{label}: canon.history must be a list")
    personality = canon.get("personality")
    if not isinstance(personality, dict):
        issues.append(f"{label}: canon.personality must be an object")
    else:
        for key in PERSONALITY_KEYS:
            if key not in personality:
                issues.append(f"{label}: canon.personality is missing {key}")
    relationships = canon.get("relationships")
    if not isinstance(relationships, list):
        issues.append(f"{label}: canon.relationships must be a list")
    else:
        for index, entry in enumerate(relationships):
            if not isinstance(entry, dict) or not {"to", "kind", "note"} <= set(entry):
                issues.append(f"{label}: canon.relationships[{index}] needs to, kind, note")
    return issues


def _validate_stats(stats: object, label: str, stat_ids: set[str]) -> list[str]:
    if not isinstance(stats, dict):
        return [f"{label}: reference_stats must be an object"]
    issues = []
    for key in STATS_KEYS:
        if key not in stats:
            issues.append(f"{label}: reference_stats is missing {key}")
    issues.extend(_no_stat_numbers(stats, f"{label}.reference_stats", stat_ids))
    return issues


def _validate_art(art: object, label: str, check_files: bool) -> list[str]:
    if not isinstance(art, dict):
        return [f"{label}: art must be an object"]
    issues = []
    style = art.get("style")
    # Not required while the record is a draft: the art direction has not settled
    # the style vocabulary, and forcing a guess at creation time only produces a
    # wrong value with a commit attached. The canon gate asks for it instead.
    if style and not SLUG_RE.fullmatch(str(style)):
        issues.append(f"{label}: art.style {style!r} must be a lowercase slug")
    if not isinstance(art.get("palette_notes", ""), str):
        issues.append(f"{label}: art.palette_notes must be a string")
    shots = art.get("shots")
    if not isinstance(shots, list):
        return issues + [f"{label}: art.shots must be a list"]
    seen: set[str] = set()
    for index, shot in enumerate(shots):
        issues.extend(_validate_shot(shot, f"{label}.shot[{index}]", check_files, seen))
    return issues


def _validate_shot(shot: object, label: str, check_files: bool, seen: set[str]) -> list[str]:
    if not isinstance(shot, dict):
        return [f"{label}: a shot must be an object"]
    issues = []
    shot_id = shot.get("id")
    if not isinstance(shot_id, str) or not SLUG_RE.fullmatch(shot_id):
        issues.append(f"{label}: shot id {shot_id!r} must be a lowercase slug")
    elif shot_id in seen:
        issues.append(f"{label}: duplicate shot id {shot_id!r}")
    else:
        seen.add(shot_id)
    if shot.get("kind") not in SHOT_KINDS:
        issues.append(f"{label}: kind {shot.get('kind')!r} must be one of {', '.join(SHOT_KINDS)}")
    # Required on every shot, draft included: a shot that does not say which
    # required prompt it fills cannot be counted toward the prompt set, so
    # allowing it here would make the canon gate below count shots it cannot
    # attribute.
    slot = shot.get("slot")
    if slot not in PROMPT_SLOTS:
        issues.append(f"{label}: slot {slot!r} must be one of {', '.join(PROMPT_SLOTS)}")
    elif slot in SLOT_KIND and shot.get("kind") != SLOT_KIND[slot]:
        issues.append(
            f"{label}: slot {slot!r} renders as kind {SLOT_KIND[slot]!r}, not {shot.get('kind')!r}"
        )
    for field in ("pose", "framing"):
        if not _text(shot.get(field)):
            issues.append(f"{label}: {field} is empty; the art brief is built from it")
    for field in ("expression", "scene"):
        if not isinstance(shot.get(field, ""), str):
            issues.append(f"{label}: {field} must be a string")
    status = shot.get("status")
    if status not in SHOT_STATUS:
        issues.append(f"{label}: status {status!r} must be one of {sorted(SHOT_STATUS)}")
    canvas = shot.get("canvas")
    if (
        not isinstance(canvas, list)
        or len(canvas) != 2
        or any(not isinstance(value, int) or isinstance(value, bool) for value in canvas)
        or any(value < 64 or value > CANVAS_MAX for value in canvas)
    ):
        issues.append(f"{label}: canvas must be two integers from 64 to {CANVAS_MAX}")
        return issues
    if status == "planned":
        if shot.get("path") is not None:
            issues.append(f"{label}: a planned shot must not name an installed path")
        return issues
    path = shot.get("path")
    if not isinstance(path, str) or not path.startswith(PATH_PREFIX):
        issues.append(f"{label}: an installed shot needs a {PATH_PREFIX} path")
        return issues
    for field in PROVENANCE_FIELDS:
        if not _text(shot.get(field)):
            issues.append(f"{label}: installed shot is missing {field} provenance")
    if check_files:
        issues.extend(_validate_image(path, canvas, f"{label} ({shot_id})"))
    return issues


def _prompt_set_gaps(art: object) -> list[str]:
    """Which required prompts this character's shot list does not supply.

    A shot list satisfying every required prompt is counted on the DISTINCT
    text that makes two members of a set different: `expression` for
    `expression_set`, `pose` for `pose_set` (`SET_SLOT_MEMBER_FIELD`). Nine pose
    shots differing in stance are nine prompts; nine pose shots sharing one
    stance are one prompt written nine times, which is the shape an agent
    produces when it satisfies a count instead of writing nine stances.
    """
    shots = art.get("shots") if isinstance(art, dict) else None
    if not isinstance(shots, list):
        return ["art.shots is not a list, so no prompt set can be read"]
    by_slot: dict[str, set[str]] = {}
    for shot in shots:
        if not isinstance(shot, dict):
            continue
        slot = shot.get("slot")
        if not isinstance(slot, str):
            continue
        field = SET_SLOT_MEMBER_FIELD.get(slot, "expression")
        value = shot.get(field)
        by_slot.setdefault(slot, set()).add(value.strip().lower() if isinstance(value, str) else "")
    gaps = []
    for slot in PROMPT_SLOTS:
        members = by_slot.get(slot)
        if not members:
            gaps.append(f"no shot fills the {slot!r} prompt")
            continue
        needed = SET_SLOT_MINIMUMS.get(slot)
        if needed is None:
            continue
        field = SET_SLOT_MEMBER_FIELD.get(slot, "expression")
        if len(members) < needed:
            gaps.append(f"{slot!r} holds {len(members)} distinct {field}(s), needs {needed}")
    return gaps


def _validate_image(path: str, canvas: list, label: str) -> list[str]:
    local = (GAME_DIR / path.removeprefix("res://")).resolve()
    if not local.is_relative_to(UNIQUE_ROOT.resolve()):
        return [f"{label}: asset path escapes the unique-character art folder"]
    if not local.is_file():
        return [f"{label}: image is missing ({path})"]
    try:
        with Image.open(local) as opened:
            if [opened.width, opened.height] != canvas:
                return [f"{label}: canvas declares {canvas}, image is {opened.size}"]
            if opened.convert("RGBA").getchannel("A").getextrema()[0] != 0:
                return [f"{label}: image needs transparent pixels"]
    except OSError:
        return [f"{label}: PNG cannot be opened"]
    return []


def _lore_entries() -> dict | None:
    """The Lore Bible's entities, or None when it cannot be read.

    The bloodline rule needs the bible, and `check` runs in `tools check` where a
    missing or broken bible must not become a character-catalog failure - that would
    couple two independent gates. A None here disables the rule rather than guessing.
    """
    try:
        from .lore.model import load_bible
    except ImportError:
        return None
    try:
        return load_bible().entities
    except Exception:  # noqa: BLE001 - any read failure means "cannot check"
        return None


def _text(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())


# The Lore Bible's `races` domain carries `type` values that are NOT all species:
# `bloodline` is a concentration carried by a body, and the authored records say so
# explicitly - hearthborn is "averaged with whatever else the household took in...
# most actors hold some", tideculled "crosses races freely - the cull was a political
# act, never an anatomical one". So a bloodline in `appearance.race` names a
# DESCENT, not a body, and a character whose only racial statement is a bloodline has
# no lifespan, no senses and no anatomy anywhere in the catalog.
#
# Ten characters were written that way and every one of them passed `check`, because a
# non-empty string is a valid `appearance.race`. The rule that catches it is not
# "the race must exist" - it is "the record must say what BODY this is".
BLOODLINE_RACE_TYPES = frozenset({"bloodline"})


def species_closed_paths(entries: dict) -> dict[str, set[str]]:
    """Which cultivation paths each species makes impossible, read from the bible.

    Derived, not hardcoded, for the same reason `bloodline_races` is. Two sources,
    because the bible uses both and a rule that read only one would miss half the
    species:

    - `attributes.closed_paths` on the race record.
    - the `no-cultivation` TAG, on species that close everything without saying so in
      an attribute. `races.echoless` is "qi-bearing in none of them"; nothing in its
      attributes says so.

    `_cultivation` is stripped because the bible writes `mind_cultivation` while a
    character's `identity.path` is `mind`. The comparison is otherwise between two
    different vocabularies and would never match.
    """
    closed: dict[str, set[str]] = {}
    for race_id, entity in entries.items():
        if not isinstance(entity, dict) or entity.get("domain") != "races":
            continue
        paths = entity.get("attributes", {}).get("closed_paths") or []
        names = {str(path).replace("_cultivation", "") for path in paths}
        tags = entity.get("tags") or []
        if "no-cultivation" in tags:
            names |= {"qi", "body", "mind"}
        if names:
            closed[race_id] = names
    return closed


def bloodline_races(entries: dict) -> set[str]:
    """Race ids that are a DESCENT rather than a body, read from the bible.

    Derived rather than hardcoded: the set of concentrations grows, and a hardcoded
    list goes stale the way every other hardcoded id list in this program has.
    """
    return {
        race_id
        for race_id, entity in entries.items()
        if isinstance(entity, dict)
        and entity.get("domain") == "races"
        and entity.get("type") in BLOODLINE_RACE_TYPES
    }


def _names_a_species(record: dict, entries: dict, bloodlines: set[str]) -> bool:
    """True when the record ASSERTS a species, rather than merely mentioning one.

    Searches `appearance` and the narrative fields for a race that is a body rather
    than a descent. Two things this deliberately does NOT accept, both found by
    reading records that had been passing:

    - a relationship pointing at a species. `unique-0026` names `races.stonebound` as
      a relationship and passed, but a relationship says the character is CONNECTED to
      that species, not that it IS one. `unique-0074` linked `races.echoless` as
      "the_mirror_failure" - deliberately the opposite body - and passed.
    - a bare word in a tag or a ledger's prose. `unique-0080` carried the tag
      `gift:unwritten-ledger` and passed, on a character whose own race field named a
      bloodline.

    A substring search over the whole record, which is what this was first, accepts
    all three. Four characters were passing incidentally when this was tightened.
    """
    fields: list[str] = []
    appearance = record.get("appearance")
    if isinstance(appearance, dict):
        fields.extend(str(value) for value in appearance.values())
    canon = record.get("canon")
    if isinstance(canon, dict):
        for key in ("role_in_story", "first_appearance", "lore"):
            value = canon.get(key)
            if isinstance(value, str):
                fields.append(value)
        history = canon.get("history")
        if isinstance(history, list):
            fields.extend(item for item in history if isinstance(item, str))
        personality = canon.get("personality")
        if isinstance(personality, dict):
            summary = personality.get("summary")
            if isinstance(summary, str):
                fields.append(summary)
            for key in ("traits", "mannerisms", "motivations", "flaws"):
                values = personality.get(key)
                if isinstance(values, list):
                    fields.extend(item for item in values if isinstance(item, str))
    blob = " ".join(fields).lower()
    if not blob:
        return False
    for race_id, entity in entries.items():
        if race_id in bloodlines or not isinstance(entity, dict):
            continue
        if entity.get("domain") != "races":
            continue
        name = race_id.split(".")[-1].lower()
        # A whole-token match, so `unwritten-ledger` does not assert `races.unwritten`
        # and `stone` does not assert `races.stonebound`.
        if re.search(rf"\b{re.escape(name)}\b", blob):
            return True
    return False


# --- the art brief ---------------------------------------------------------


def _brief(record: dict, shot: dict) -> str:
    """The deterministic half of generation: the text a renderer receives.

    Assembled from authored canon rather than typed per shot, so a portrait and
    a concept sheet of the same character cannot disagree about who they are —
    the failure the minor-character catalog avoids by deriving both slots from
    one seed and one trait string.
    """
    appearance = record.get("appearance", {})
    canon = record.get("canon", {})
    personality = canon.get("personality", {})
    lines = [
        f"{record.get('id')} {record.get('name')}"
        + (f" ({', '.join(record['aliases'])})" if record.get("aliases") else ""),
        f"style: {record.get('art', {}).get('style') or 'UNSET'}",
        f"shot: {shot.get('id')} | slot {shot.get('slot')} | kind {shot.get('kind')}"
        f" | canvas {shot.get('canvas')}",
        "",
        "SUBJECT (identity anchors: these MUST read identically in every prompt "
        "for this character; only pose, expression, framing and scene vary)",
        "; ".join(f"{key}: {appearance[key]}" for key in APPEARANCE_KEYS if appearance.get(key)),
        "",
        f"POSE: {shot.get('pose', '')}",
        f"EXPRESSION: {shot.get('expression') or 'a composed, readable expression'}",
        f"FRAMING: {shot.get('framing', '')}",
    ]
    if shot.get("scene"):
        lines.append(f"SCENE: {shot['scene']}")
    lines += [
        "",
        "WHO THIS IS",
        f"role: {record.get('identity', {}).get('role')}"
        f" | path: {record.get('identity', {}).get('path')}"
        f" | faction: {record.get('identity', {}).get('faction') or 'unaffiliated'}",
        f"role in the story: {canon.get('role_in_story', '')}",
        f"lore: {canon.get('lore', '')}",
    ]
    if canon.get("history"):
        lines.append("history (earliest first):")
        lines += [f"  - {beat}" for beat in canon["history"]]
    lines.append(f"personality: {personality.get('summary', '')}")
    if personality.get("voice"):
        lines.append(f"voice and manner: {personality['voice']}")
    if personality.get("mannerisms"):
        lines.append(f"mannerisms: {', '.join(personality['mannerisms'])}")
    stats = record.get("reference_stats", {})
    if stats.get("summary"):
        lines.append(f"how they fight: {stats['summary']}")
    if stats.get("strengths"):
        lines.append(f"strengths: {', '.join(stats['strengths'])}")
    if stats.get("weaknesses"):
        lines.append(f"weaknesses: {', '.join(stats['weaknesses'])}")
    if record.get("art", {}).get("palette_notes"):
        lines.append(f"palette notes: {record['art']['palette_notes']}")
    lines += [
        "",
        "CONSTRAINTS",
        *(f"  - {rule}" for rule in BRIEF_CONSTRAINTS),
        "",
        "NEGATIVE",
        f"  {CHARACTER_NEGATIVE}",
    ]
    return "\n".join(lines)


# --- actions ---------------------------------------------------------------


def _display_path(path: Path) -> str:
    """Repo-relative when possible, absolute otherwise.

    `relative_to(REPO_ROOT)` raises for a catalog outside the repo, which turned a
    confirmation message into a crash. A self-test pointing the catalog at a temp
    directory hit it, and a real user with the project on a second drive would too.
    """
    try:
        return path.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def _shard_path(name: str) -> Path:
    """The file one writer owns, validated as a shard name.

    A shard name must not be able to escape the catalog directory or collide with
    the primary index, because `--shard` is supplied on a command line by an agent
    and `INDEX_PATH.parent / f"{name}.jsonl"` is otherwise a path traversal.
    """
    if not SLUG_RE.fullmatch(name):
        raise ToolError(f"invalid shard name {name!r}; expected a lowercase slug")
    return INDEX_PATH.parent / f"{INDEX_PATH.stem}-{name}.jsonl"


def _owning_shard(character_id: str) -> Path:
    """Which catalog file holds this character, so a write goes back where it came from.

    Falls back to the primary index for a character that is not on disk yet, which
    is the only case where writing there can lose another agent's work.
    """
    for path in _catalog_paths():
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            if json.loads(line).get("id") == character_id:
                return path
    return INDEX_PATH


def _add(args) -> int:
    # Validate against the READABLE catalog, not the strict one. An agent that wrote
    # its shard by hand left a torn line, and because `_add` validated the whole
    # catalog first, that one bad row made `add` unusable for every OTHER agent - one
    # reported being unable to use the tool for three of its four batches and writing
    # rows by hand instead, which is how the next torn shard happened.
    #
    # The clobber risk lives in WRITING a partial view, not in validating one. This
    # function writes only its own record to its own shard via a merging
    # `_atomic_write`, so a foreign unreadable shard cannot lose anybody's rows. The
    # cost is that this agent's own duplicate check is slightly weaker while another
    # shard is torn, which is the right way round: `check` still fails loudly.
    records = readable_catalog()
    if any(record.get("id") == args.character_id for record in records):
        raise ToolError(f"{args.character_id} already exists")
    record = _blank_character(args.character_id, args.name, args.role, args.path, args.style)
    issues = _validate([*records, record], check_files=False)
    if issues:
        raise ToolError(f"refusing to write an invalid record: {issues[0]}")
    shard = getattr(args, "shard", None)
    target = _shard_path(shard) if shard else None
    _atomic_write([record], target)
    # Name the file that actually received the record. It used to print the primary
    # index unconditionally, so a sharded write reported a path it did not write -
    # and an agent verifying its own work would look in the wrong file, or conclude
    # its record was lost. A tool that misreports its own output path is the same
    # hazard class as the one sharding fixed: a confident message about the wrong
    # thing.
    written = target or INDEX_PATH
    ok(
        f"added {args.character_id} as a draft at "
        f"{_display_path(written)}; fill appearance, then canon, "
        "then set status to canon"
    )
    return 0


def _report(records: list[dict]) -> int:
    issues = _validate(records, check_files=True)
    print(f"unique characters: {len(records)}")
    if not records:
        info("  catalog is empty; every command below has nothing to act on yet")
        return 0
    status = Counter(record.get("status", "invalid") for record in records)
    print("status: " + " | ".join(f"{key} {status[key]}" for key in sorted(status)))
    for axis, key in (("identity", "role"), ("identity", "path")):
        counts = Counter(
            record.get(axis, {}).get(key, "unset")
            if isinstance(record.get(axis), dict)
            else "unset"
            for record in records
        )
        print(f"{key}: " + ", ".join(f"{name}={counts[name]}" for name in sorted(counts)))
    print(f"index: {INDEX_PATH.relative_to(REPO_ROOT).as_posix()}")

    styles = Counter(
        record.get("art", {}).get("style", "unset")
        if isinstance(record.get("art"), dict)
        else "unset"
        for record in records
    )
    print("art style (free-form; one use may be a typo):")
    for name, count in sorted(styles.items(), key=lambda item: (-item[1], item[0])):
        print(f"  {name}: {count}")

    by_kind: dict[str, Counter] = {kind: Counter() for kind in SHOT_KINDS}
    for record in records:
        shots = (
            record.get("art", {}).get("shots", []) if isinstance(record.get("art"), dict) else []
        )
        for shot in shots if isinstance(shots, list) else []:
            if not isinstance(shot, dict):
                continue
            # `Counter.get` returns the fallback rather than inserting it, so an
            # unknown kind has to be created explicitly or `report` dies on the
            # one row it was built to describe.
            kind = shot.get("kind")
            by_kind.setdefault(kind, Counter())
            state = shot.get("status")
            by_kind[kind][state if isinstance(state, str) else "invalid"] += 1
    print("shots:")
    for kind in (*SHOT_KINDS, "invalid"):
        counts = by_kind.get(kind, Counter())
        if not counts and kind == "invalid":
            continue
        if not counts:
            print(f"  {kind}: none planned")
            continue
        ordered = {
            state: counts[state] for state in ("approved", "generated", "planned") if counts[state]
        }
        print(f"  {kind}: " + " | ".join(f"{state} {n}" for state, n in ordered.items()))

    axes: dict[str, Counter] = {}
    for record in records:
        for tag in record.get("tags", []) if isinstance(record.get("tags"), list) else []:
            if isinstance(tag, str) and ":" in tag:
                axis, value = tag.split(":", 1)
                axes.setdefault(axis, Counter())[value] += 1
    if axes:
        print("tag axes in use (free-form; a count of 1 may be a typo):")
        for axis, counts in sorted(axes.items()):
            print(f"  {axis}: " + ", ".join(f"{v}={n}" for v, n in sorted(counts.items())))
    planned_none = sum(
        1
        for record in records
        if not (record.get("art") or {}).get("shots")
        if isinstance(record.get("art", {}), dict)
    )
    print(f"characters with no shot planned: {planned_none}")

    # Per-character prompt-set coverage. `report` is the read-only view, so this
    # is where an author sees which of the nine required prompts a draft is
    # missing BEFORE `check` refuses to promote it — a gate that only reports at
    # promotion time tells you the answer after you have already done the work.
    incomplete = 0
    for record in records:
        gaps = _prompt_set_gaps(record.get("art"))
        if gaps:
            incomplete += 1
            print(f"  {record.get('id')}: {len(gaps)} prompt gap(s)")
            for gap in gaps:
                print(f"    - {gap}")
    print(f"characters missing part of the required prompt set: {incomplete}")

    if issues:
        print(f"audit findings: {len(issues)} (run `unique_characters check` for details)")
        return 1
    ok("unique-character catalog audit complete")
    return 0


def _check(records: list[dict]) -> int:
    """The gate. Runs in `tools check`, so it must be cheap and must not be vacuous."""
    if not INDEX_PATH.is_file():
        ok("no unique-character catalog yet; nothing to validate")
        return 0
    issues = _validate(records, check_files=True)
    if issues:
        for issue in issues:
            fail(issue)
        fail(f"unique-character audit failed: {len(issues)} issue(s)")
        return 1
    canon = sum(1 for record in records if record.get("status") == "canon")
    shots = sum(
        len(record.get("art", {}).get("shots", []))
        for record in records
        if isinstance(record.get("art"), dict)
    )
    ok(f"unique-character catalog valid ({len(records)} characters, {canon} canon, {shots} shots)")
    return 0


def _canon_rows(records: list[dict]) -> list[dict]:
    """The canon cast, which is the only part of the file carrying authored choices.

    A `draft` row is a shell: `unique_characters add` fills `role` and `path` from the
    command line and leaves race, appearance and every shot empty. It is a work
    ticket, not a character, and it must not move a distribution.
    """
    return [
        record for record in records if isinstance(record, dict) and record.get("status") == "canon"
    ]


def _diversity_command(records: list[dict], args) -> int:
    """The read-only view of cast composition, and the number that steers a wave.

    Deliberately separate from `check`. A duplicate is a defect and fails; a
    monoculture is a fact about the cast that is only wrong at a given size, and a
    small catalog legitimately looks concentrated. So the warning always prints and
    only `--fail-on-warn` turns it into an exit code - which is what a release gate
    should ask for and what an authoring agent should not have to satisfy while
    filling its first ten characters.

    MEASURES CANON ONLY, by default. A draft shell carries no authored choice yet -
    `add` fills `role` and `path` from the command line and leaves race, appearance and
    all 22 shots empty - so counting it makes a wave in flight flap the gate. Measured
    on a live tree with 25 shells in progress, the two readings named DIFFERENT paths
    as the monoculture: drafts blamed `unaffiliated` at 41/150 while the canon cast
    actually had qi, mind and body each over. A gate that names the wrong axis sends
    the next wave to fix a path that was never the problem.

    `--include-drafts` shows the whole file, for the case where the drafts ARE the
    subject - checking that a wave has spread its shells before it fills them.
    """
    include_drafts = getattr(args, "include_drafts", False)
    canon = _canon_rows(records)
    rows = records if include_drafts else canon
    total = sum(1 for record in rows if isinstance(record, dict))
    drafts = len(records) - len(canon)
    if total == 0:
        info("no canon characters yet; nothing to distribute")
        return 0
    if include_drafts:
        label = f"cast size: {total} ({len(canon)} canon, {drafts} draft)"
    else:
        label = f"cast size: {total} canon" + (f" ({drafts} draft excluded)" if drafts else "")
    print(label)
    for axis, counts in _diversity_axes(rows):
        top = ", ".join(f"{value}={count}" for value, count in counts.most_common(6))
        print(f"  {axis}: {len(counts)} distinct | {top}")
    warnings = _concentration_warnings(rows)
    if not warnings:
        ok(f"no structural axis is a monoculture (share limit {DIVERSITY_MAX_SHARE:.0%})")
        return 0
    for warning in warnings:
        fail(f"monoculture: {warning}")
    return 1 if getattr(args, "fail_on_warn", False) else 0


def _next(records: list[dict], count: int, kind_filter: str | None) -> int:
    if count < 1:
        raise ToolError("--count must be at least 1")
    art_done: Counter = Counter()
    for record in records:
        shots = (
            record.get("art", {}).get("shots", []) if isinstance(record.get("art"), dict) else []
        )
        for shot in shots if isinstance(shots, list) else []:
            if isinstance(shot, dict) and shot.get("status") in {"generated", "approved"}:
                art_done[shot.get("kind")] += 1

    candidates = []
    for record in records:
        shots = (
            record.get("art", {}).get("shots", []) if isinstance(record.get("art"), dict) else []
        )
        for position, shot in enumerate(shots if isinstance(shots, list) else []):
            if not isinstance(shot, dict) or shot.get("status") != "planned":
                continue
            if kind_filter is not None and shot.get("kind") != kind_filter:
                continue
            candidates.append((record, shot, position))
    if not candidates:
        raise ToolError("no planned shots match the filter; add a shot to a character first")

    chosen: list[tuple[dict, dict]] = []
    while candidates and len(chosen) < count:
        # Canon first, then spread art across characters, then balance kinds,
        # then id order so two runs on the same catalog pick the same shots.
        def priority(candidate: tuple[dict, dict, int]) -> tuple[int, int, int, str, str]:
            record, shot, _position = candidate
            is_draft = record.get("status") != "canon"
            shots = record.get("art", {}).get("shots", [])
            made = sum(
                1
                for other in shots
                if isinstance(other, dict) and other.get("status") in {"generated", "approved"}
            )
            return (
                int(is_draft),
                made,
                art_done[shot.get("kind")],
                str(record.get("id")),
                str(shot.get("id")),
            )

        record, shot, position = min(candidates, key=priority)
        candidates.remove((record, shot, position))
        chosen.append((record, shot))
        art_done[shot.get("kind")] += 1
    print(f"next {len(chosen)} planned shots (canon first, then spread, then kind balance):")
    for record, shot in chosen:
        print(
            f"  {record.get('id')} | {shot.get('kind')} | {shot.get('id')} | {shot.get('pose', '')}"
        )
    return 0


def _plan(records: list[dict], args) -> int:
    record = _character(records, args.character_id)
    shot = _shot(record, args.shot_id)
    print(_brief(record, shot))
    return 0


def _normalize(source: Path, canvas: list) -> Image.Image:
    try:
        with Image.open(source) as opened:
            if opened.width * opened.height > 32_000_000:
                raise ToolError(f"source image is too large: {opened.size}")
            image = opened.convert("RGBA")
    except OSError as exc:
        raise ToolError(f"source PNG cannot be opened: {source}") from exc
    alpha = image.getchannel("A")
    if alpha.getextrema()[0] != 0:
        raise ToolError(f"source image has no transparent pixels: {source}")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ToolError(f"source image is fully transparent: {source}")
    image = image.crop(bounds)
    image.thumbnail(tuple(canvas), Image.Resampling.LANCZOS)
    frame = Image.new("RGBA", tuple(canvas), (0, 0, 0, 0))
    frame.alpha_composite(image, ((canvas[0] - image.width) // 2, (canvas[1] - image.height) // 2))
    return frame


def _install(records: list[dict], args) -> int:
    record = _character(records, args.character_id)
    shot = _shot(record, args.shot_id)
    replacing = args.replace_generated and shot.get("status") == "generated"
    if shot.get("status") != "planned" and not replacing:
        raise ToolError(
            f"refusing to replace {args.character_id}/{args.shot_id} ({shot.get('status')})"
        )
    source = Path(args.source)
    if not source.is_file() or source.suffix.lower() != ".png":
        raise ToolError(f"source must be an existing PNG: {source}")
    for field, value in (
        ("prompt", args.prompt),
        ("source-name", args.source_name),
        ("license", args.license),
    ):
        if not value.strip():
            raise ToolError(f"--{field} must be non-empty")
    if args.seed is not None and not 0 <= args.seed < 2**31:
        raise ToolError("--seed must be between 0 and 2147483647")
    settings: dict = {}
    if args.generation_settings.strip():
        try:
            settings = json.loads(args.generation_settings)
        except json.JSONDecodeError as exc:
            raise ToolError(f"--generation-settings is not valid JSON ({exc.msg})") from exc
        if not isinstance(settings, dict):
            raise ToolError("--generation-settings must be a JSON object")

    canvas = shot.get("canvas")
    if not isinstance(canvas, list) or len(canvas) != 2:
        raise ToolError(f"{args.character_id}/{args.shot_id} declares no usable canvas")

    stamp = f"-{args.seed}" if args.seed is not None else ""
    filename = f"{args.shot_id}{stamp}.png"
    output = (UNIQUE_ROOT / args.character_id / shot["kind"] / filename).resolve()
    if not output.is_relative_to(UNIQUE_ROOT.resolve()):
        raise ToolError("output must stay under the unique-character art folder")
    if output.exists():
        raise ToolError(f"refusing to overwrite existing art: {output}")

    frame = _normalize(source, canvas)
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor = None
    created = False
    try:
        descriptor = os.open(output, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        created = True
        with os.fdopen(descriptor, "wb") as handle:
            descriptor = None
            frame.save(handle, format="PNG", optimize=True)
        # Re-read after a long render: a concurrent author may have edited this
        # character, and installing onto a changed shot is how a portrait ends up
        # contradicting the lore it was briefed from.
        current_records = _load_index()
        current = _character(current_records, args.character_id)
        current_shot = _shot(current, args.shot_id)
        if current_shot.get("status") != "planned" and not (
            replacing and current_shot.get("status") == "generated"
        ):
            raise ToolError(f"{args.character_id}/{args.shot_id} changed while rendering")
        if current.get("art", {}).get("style") != record.get("art", {}).get("style"):
            raise ToolError(f"{args.character_id} art style changed while rendering")
        current_shot.update(
            status="generated",
            path=f"{PATH_PREFIX}{args.character_id}/{shot['kind']}/{filename}",
            source=args.source_name,
            prompt=args.prompt,
            generated_on=datetime.now(UTC).date().isoformat(),
            license=args.license,
            seed=args.seed,
            generation_settings=settings,
        )
        # Write back to the shard that OWNS this character, never the primary file.
        # Installing one shot must not rewrite a catalog another agent is filling.
        _atomic_write([current], _owning_shard(args.character_id))
    except Exception:
        if created:
            output.unlink(missing_ok=True)
        raise
    finally:
        if descriptor is not None:
            os.close(descriptor)
    installed = output.relative_to(REPO_ROOT).as_posix()
    ok(f"installed {args.character_id}/{args.shot_id} at {installed}")
    return 0


def _preview(records: list[dict], args) -> int:
    if not 1 <= args.limit <= 256:
        raise ToolError("--limit must be between 1 and 256")
    ready = []
    for record in records:
        shots = (
            record.get("art", {}).get("shots", []) if isinstance(record.get("art"), dict) else []
        )
        for shot in shots if isinstance(shots, list) else []:
            if not isinstance(shot, dict):
                continue
            if args.kind and shot.get("kind") != args.kind:
                continue
            if shot.get("status") in {"generated", "approved"}:
                ready.append((record, shot))
    ready = ready[: args.limit]
    if not ready:
        raise ToolError("no generated shots to preview; install one first")

    columns, cell, thumb, label_height = 4, 200, 168, 30
    rows = (len(ready) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * cell, rows * (thumb + label_height)), (38, 42, 48))
    font = ImageFont.load_default()
    for index, (record, shot) in enumerate(ready):
        findings = _validate_image(shot["path"], shot["canvas"], f"{record['id']}/{shot['id']}")
        if findings:
            raise ToolError("cannot preview invalid image: " + "; ".join(findings))
        with Image.open(GAME_DIR / shot["path"].removeprefix("res://")) as opened:
            foreground = opened.convert("RGBA")
        foreground.thumbnail((thumb, thumb), Image.Resampling.LANCZOS)
        checker = Image.new("RGBA", (thumb, thumb), (230, 230, 230, 255))
        draw = ImageDraw.Draw(checker)
        for cy in range(0, thumb, 16):
            for cx in range(0, thumb, 16):
                if (cx // 16 + cy // 16) % 2:
                    draw.rectangle((cx, cy, cx + 15, cy + 15), fill=(190, 190, 190, 255))
        checker.alpha_composite(
            foreground,
            ((thumb - foreground.width) // 2, (thumb - foreground.height) // 2),
        )
        left = index % columns * cell + (cell - thumb) // 2
        top = index // columns * (thumb + label_height)
        sheet.paste(checker.convert("RGB"), (left, top))
        ImageDraw.Draw(sheet).text(
            (index % columns * cell + 6, top + thumb + 3),
            f"{record['id']}/{shot['id']}",
            fill="white",
            font=font,
        )
        ImageDraw.Draw(sheet).text(
            (index % columns * cell + 6, top + thumb + 15),
            str(record.get("art", {}).get("style", "")),
            fill=(190, 200, 190),
            font=font,
        )
    output = REPO_ROOT / "build" / "unique-character-preview" / f"{args.kind or 'all'}.png"
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, format="PNG", optimize=True)
    ok(f"wrote preview sheet: {output.relative_to(REPO_ROOT).as_posix()} ({len(ready)} shots)")
    return 0


# --- wiring ----------------------------------------------------------------


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "unique_characters",
        help="author, brief, and install reference art for the named cast",
    )
    actions = parser.add_subparsers(dest="action", required=True)

    add = actions.add_parser("add", help="add one unique character as a draft")
    add.add_argument("--character-id", required=True)
    add.add_argument("--name", required=True)
    add.add_argument("--role", choices=sorted(VALID_ROLES), default="npc")
    add.add_argument("--path", choices=sorted(VALID_PATHS), default="unaffiliated")
    add.add_argument("--style", default="", help="art direction style slug")
    add.add_argument(
        "--shard",
        default="",
        help=(
            "write this character into its own catalog shard, e.g. 'wave-01'. Two agents "
            "authoring at once MUST use different shards: the primary file is rewritten "
            "from the writer's in-memory snapshot, so concurrent writers on one file lose "
            "whichever write lands second"
        ),
    )

    actions.add_parser("report", help="summarize the named cast and its shot coverage")
    actions.add_parser("check", help="fail on an invalid catalog or a missing installed image")
    diversity = actions.add_parser(
        "diversity",
        help="distribution of the cast across structural axes, and monoculture warnings",
    )
    diversity.add_argument(
        "--fail-on-warn",
        action="store_true",
        help="exit non-zero when a structural axis is a monoculture",
    )
    diversity.add_argument(
        "--include-drafts",
        action="store_true",
        help=(
            "count in-flight draft shells as well as canon. Off by default because a "
            "draft carries no authored choice and would move the distribution"
        ),
    )

    nxt = actions.add_parser("next", help="prioritize ungenerated shots")
    nxt.add_argument("--count", type=int, default=12)
    nxt.add_argument("--kind", choices=SHOT_KINDS)

    plan = actions.add_parser("plan", help="print the art brief for one shot")
    plan.add_argument("--character-id", required=True)
    plan.add_argument("--shot-id", required=True)

    install = actions.add_parser("install", help="normalize and register a rendered PNG")
    install.add_argument("--character-id", required=True)
    install.add_argument("--shot-id", required=True)
    install.add_argument("--source", required=True)
    install.add_argument("--prompt", required=True)
    install.add_argument("--source-name", required=True)
    install.add_argument("--license", required=True)
    install.add_argument("--seed", type=int)
    install.add_argument(
        "--generation-settings",
        default="",
        help='JSON object of the settings that produced the image, e.g. \'{"checkpoint": "..."}\'',
    )
    install.add_argument("--replace-generated", action="store_true")

    preview = actions.add_parser("preview", help="build a contact sheet of generated shots")
    preview.add_argument("--kind", choices=SHOT_KINDS)
    preview.add_argument("--limit", type=int, default=64)


def run(args) -> int:
    action = args.action
    if action == "add":
        return _add(args)
    if action == "install":
        return _install(_load_index(), args)
    if action == "plan":
        return _plan(_load_index(), args)
    if action == "check":
        # Tolerates an absent catalog on purpose: `check` runs in `tools check`,
        # and a gate that fails because nobody has authored a character yet would
        # be a gate nobody trusts. An empty catalog is a true statement, not a fault.
        #
        # `readable_catalog` rather than `_load_index` because a shard another agent
        # is mid-write on must not turn every read command into an error. A torn
        # shard is REPORTED below rather than silently ignored, so a permanently
        # broken one still surfaces.
        if not _catalog_paths():
            return _check([])
        torn = [path.name for path in _catalog_paths() if not _shard_is_complete(path)]
        result = _check(readable_catalog())
        for name in torn:
            fail(
                f"{name}: not every line parses, so it was skipped. An agent writing "
                f"this shard directly instead of through `unique_characters add --shard` "
                f"produces a torn file that blocks every reader."
            )
        return 1 if torn else result
    if action == "diversity":
        return _diversity_command(readable_catalog(), args)
    if action == "report":
        return _report(readable_catalog())
    records = _load_index()
    if action == "next":
        return _next(records, args.count, args.kind)
    if action == "preview":
        return _preview(records, args)
    raise ToolError(f"unknown action {action}")
