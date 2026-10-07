"""i18n policy: what is in scope, which strings are player-facing, and the slug shape.

Policy lives here (it changes when the standard changes). The catalogs under
`game/locale/` are state, written by the tool. A finding is a string in a DISPLAY SINK: a
place the game hands text to a player.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

## Every slug is `LOC_<DOMAIN>_<HASH>`: a readable area prefix plus a content hash, so the
## id is stable across file moves and an English edit yields a new id rather than silently
## re-pointing an old translation (the reason slugs exist at all).
SLUG_PREFIX = "LOC"
SLUG_HASH_LEN = 10

CATALOG_DIR = "game/locale"

## Control properties that carry player-facing text, in `.gd` and `.tscn`.
TEXT_PROPERTIES = ("text", "tooltip_text", "placeholder_text")

## Authored-content fields (`.tres`) that carry player-facing text. Single-string and
## array-of-string alike: `names`/`manners`/`activities` are authored lists a composer picks
## from, and each element is a string a player reads.
CONTENT_FIELDS = (
    "display_name",
    "description",
    "title",
    "text",
    "line",
    "prompt",
    "flavor",
    "blurb",
    "caption",
    "label",
    "summary",
    "prose",
    "body",
    "teaser",
    "epithet",
    "motto",
    "quote",
    "note",
    "names",
    "manners",
    "activities",
)

## Whole-word tokens a GDScript identifier must contain to be a display sink: a `const`/`var`
## holding text, or a function returning text. Splitting on `_` and matching whole words is
## what keeps `NO_SELECT_SEAM` and `PRESET_SCENE` out while `EVENTS_TITLE_UNWIRED` is in.
DISPLAY_TOKENS = frozenset(
    {
        "TEXT",
        "LABEL",
        "TITLE",
        "LINE",
        "MESSAGE",
        "WORDING",
        "SUFFIX",
        "HEADING",
        "PROMPT",
        "HINT",
        "TOOLTIP",
        "REASON",
        "CAPTION",
        "FOOTER",
        "HEADER",
        "REPLY",
        "GREETING",
        # A composed persona's own wording: a default manner, an activity, a name, an opinion.
        "NAME",
        "MANNER",
        "ACTIVITY",
        "OPINION",
        "TELL",
        "PROSE",
        "BODY",
        "TEASER",
        "EPITHET",
        "MOTTO",
        "QUOTE",
    }
)

## A trailing `# i18n:off` on a line exempts that line's strings from extraction.
IGNORE_MARKER = "i18n:off"

## The resolver call the tool writes and reads (must match `core/localize.gd`).
RESOLVER = "L.t"


@dataclass(frozen=True)
class Domain:
    """The slug prefix and catalog file a path belongs to."""

    prefix: str
    catalog: str


def owner_of(rel: str) -> str | None:
    """The owner a path belongs to: the area whose catalog file holds its strings.

    An owner names BOTH the slug prefix and the catalog file (`game/locale/<owner>.tres`), so
    a key is recoverable to its file — `tools i18n check` requires it there. Split by area,
    not one shared file, so two owners never collide, and a mod ships its own owners.
    """
    path = rel.replace("\\", "/")
    if path.startswith("game/src/modules/"):
        rest = path[len("game/src/modules/") :]
        sub = rest.split("/", 1)[0]
        return _owner("", sub) if "/" in rest and sub else "modules"
    if path.startswith("game/src/core/"):
        return "core"
    if path.startswith("game/src/ui/"):
        rest = path[len("game/src/ui/") :]
        if "/" not in rest:
            return "ui"
        return _owner("ui", rest.split("/", 1)[0])
    if path.startswith("game/scenes/"):
        return "scenes"
    if path.startswith("game/data/"):
        sub = path[len("game/data/") :].split("/", 1)[0]
        if sub:
            return _owner("", sub)
    return None


def _owner(prefix: str, name: str) -> str:
    token = name.lower().replace("-", "_")
    return f"{prefix}_{token}" if prefix else token


def domain_of(rel: str) -> Domain | None:
    """The domain a repo-relative path belongs to, or None when out of scope."""
    owner = owner_of(rel)
    if owner is None:
        return None
    return Domain(owner.upper(), owner)


def scope_kind(rel: str) -> str | None:
    """The file kind a path is scanned as, or None when it is not in scope.

    `.gd` display text is not only in `ui/`: a module composes a persona or a realm name too
    (`npc_minor_composer.gd`'s default manner, `realm_defaults.gd`'s realm names), so a module
    and `core` are scanned as well. `app/` and `contracts/` are not: they compose no wording.
    """
    path = rel.replace("\\", "/")
    if path.endswith(".gd") and path.startswith(
        ("game/src/ui/", "game/src/modules/", "game/src/core/")
    ):
        return "gd"
    if (path.startswith("game/src/ui/") or path.startswith("game/scenes/")) and path.endswith(
        ".tscn"
    ):
        return "tscn"
    if path.startswith("game/data/") and path.endswith(".tres"):
        return "tres"
    return None


def has_display_token(name: str) -> bool:
    """Whether an identifier names a text sink (any `_`-separated word is a display token)."""
    return any(part.upper() in DISPLAY_TOKENS for part in name.split("_"))


def is_player_text(value: str) -> bool:
    """Whether a string literal is a candidate for translation.

    Not a space heuristic: single-word UI text ("Settings") is legitimate. What is excluded
    is what cannot be prose — empty strings, strings with no letter, resource paths, node
    paths, already-slugged values, and code tokens (`no_actor`, `display_name`, `crit_chance`)
    which are dictionary keys and lookups, not text.
    """
    text = value.strip()
    if not text:
        return False
    if not any(ch.isalpha() for ch in text):
        return False
    if text.startswith(("res://", "user://", "uid://", "/")):
        return False
    # A node path is `%Identifier` with no spaces; a FORMAT string (`"%s x%d"`) is a message and
    # must not be mistaken for one — the earlier blanket `%` guard dropped every such message.
    if re.fullmatch(r"%[A-Za-z_][A-Za-z0-9_]*", text):
        return False
    if text.startswith(f"{SLUG_PREFIX}_"):
        return False
    # `snake_case` with no space is an identifier (`display_name`, `no_actor`), and an all
    # lower-case dotted token (`api.gd`, `kind`) is a code value — neither is player text.
    if "_" in text and " " not in text:
        return False
    if re.fullmatch(r"[a-z0-9_.]+", text):
        return False
    # A single CamelCase token with no space is a code value (`QiDamage`, `GrowthLabel`),
    # not a label: "Settings"/"Ready" have no lower->upper seam, those do.
    if " " not in text and re.search(r"[a-z][A-Z]", text):
        return False
    return True
