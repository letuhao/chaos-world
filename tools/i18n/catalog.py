"""Slug derivation and the text `Translation` catalogs under `game/locale/`.

A catalog is a Godot text resource holding `key -> text` for ONE locale and ONE owner:

    [gd_resource type="Translation" format=3]

    [resource]
    locale = "en"
    messages = {
    "LOC_UI_PANELS_AB12CD34": "Wait a season",
    }

It is loaded by `core/localize.gd`, which registers every `res://locale/**/*.tres`. The `en`
catalog holds the source English; `<owner>.<locale>.tres` holds a real locale. All rows are
written sorted so a diff names one string per line.

## The key is STABLE once assigned, not a re-derivation of the text

`assign_key` picks a key the first time a string is extracted and it is **opaque from then
on**. Editing the English is then a one-row data edit that never re-keys and never orphans a
translation — the reason a slug exists at all. The content hash is only the *generator*, and
`check` therefore does NOT require a row to hash to its key.
"""

from __future__ import annotations

import hashlib
import re
from pathlib import Path

from ..common import ToolError
from .policy import CATALOG_DIR, SLUG_HASH_LEN, SLUG_PREFIX

## The header of every generated catalog. `format=3` is Godot 4's text-resource version.
_HEADER = '[gd_resource type="Translation" format=3]\n\n[resource]\n'
_ROW = re.compile(r'^"(?P<key>[^"]+)"\s*:\s*"(?P<value>(?:[^"\\]|\\.)*)"\s*,?\s*$')

## Bound on the collision nonce. Two distinct texts sharing a hash is a 40-bit coincidence, so
## reaching this is a bug in the derivation, not a busy key space — fail loudly rather than spin.
MAX_KEY_ATTEMPTS = 64


def slug_for(prefix: str, english: str) -> str:
    """The base id for `english` within `prefix`: `LOC_<prefix>_<hash>`.

    A *generator*, not the identity: use [func assign_key] to pick a key, which keeps the
    id stable when the text changes.
    """
    digest = hashlib.sha1(english.encode("utf-8")).hexdigest()[:SLUG_HASH_LEN].upper()
    return f"{SLUG_PREFIX}_{prefix}_{digest}"


def assign_key(prefix: str, english: str, taken: dict[str, str]) -> str:
    """A STABLE key for `english` within `prefix`, given the rows `taken` ({key: text}).

    - An existing row that already holds this exact text is REUSED, so a duplicate string
      shares one row and one translation.
    - Otherwise the content hash is minted. If that key is already taken by DIFFERENT text —
      the row was edited in place — a deterministic nonce is appended until a free key is
      found. `taken` is read in sorted order so the choice never depends on dict order.
    """
    for key in sorted(taken):
        if taken[key] == english:
            return key
    base = slug_for(prefix, english)
    if base not in taken:
        return base
    for nonce in range(1, MAX_KEY_ATTEMPTS + 1):
        candidate = slug_for(prefix, f"{english}\x00{nonce}")
        if candidate not in taken:
            return candidate
    raise ToolError(
        f"could not assign a free key for {english!r} in {prefix} after {MAX_KEY_ATTEMPTS} attempts"
    )


def escape(value: str) -> str:
    """Escape a string into a single-line Godot literal (the catalog is one row per line)."""
    out = (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )
    return out


def unescape(value: str) -> str:
    """Inverse of [func escape] for the escapes the catalog can hold."""
    out: list[str] = []
    index = 0
    table = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}
    while index < len(value):
        char = value[index]
        if char == "\\" and index + 1 < len(value):
            nxt = value[index + 1]
            out.append(table.get(nxt, nxt))
            index += 2
            continue
        out.append(char)
        index += 1
    return "".join(out)


def catalog_path(repo_root: Path, stem: str, locale: str = "en") -> Path:
    """`game/locale/<stem>.tres` for English, `game/locale/<stem>.<locale>.tres` otherwise."""
    name = f"{stem}.tres" if locale == "en" else f"{stem}.{locale}.tres"
    return repo_root / CATALOG_DIR / name


def load(path: Path) -> dict[str, str]:
    """The `slug -> text` rows of a catalog, or `{}` when it does not exist yet."""
    if not path.is_file():
        return {}
    text = path.read_text(encoding="utf-8")
    rows: dict[str, str] = {}
    for line in text.splitlines():
        match = _ROW.match(line.strip())
        if match:
            rows[match.group("key")] = unescape(match.group("value"))
    return rows


def render(locale: str, messages: dict[str, str]) -> str:
    """The full text of a catalog, rows sorted by key so the file is deterministic."""
    lines = [_HEADER.rstrip("\n"), f'locale = "{locale}"', "messages = {"]
    for key in sorted(messages):
        lines.append(f'"{key}": "{escape(messages[key])}",')
    lines.append("}")
    return "\n".join(lines) + "\n"


def save(path: Path, messages: dict[str, str], locale: str = "en") -> bool:
    """Write `messages` to `path`, sorted. Returns True when the bytes changed on disk."""
    text = render(locale, messages)
    if path.is_file() and path.read_text(encoding="utf-8") == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    # newline="" keeps the generated file LF on every platform, so the diff is one row per
    # string rather than a line-ending flip of the whole file.
    with path.open("w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    return True
