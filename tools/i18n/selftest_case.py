"""Red-path self-tests for the i18n gate.

A guard that has never been seen to fail is not a guard (INC-0016), and the i18n validator
lives in Python where the GDScript suite cannot reach it. Each case builds a throwaway repo
tree, points the engine at it, and asserts the verdict — a clean tree is GREEN and each way of
being wrong is RED. One case runs the whole extract -> check loop, so the rewrite is proven,
not just asserted. Nothing here touches the real repository.
"""

from __future__ import annotations

import argparse
import json
import tempfile
from pathlib import Path

from ..selftest import case, expect, write
from . import catalog, engine

_MIGRATED = """extends Control


func _hint_text() -> String:
\treturn L.t("%s", "Okay")
"""

_LEFTOVER = """extends Control


func _hint_text() -> String:
\treturn L.t("%s", "Okay")
\treturn "Leftover"
"""

_HARDCODED = """extends Control


func _hint_text() -> String:
\treturn "Ready"
"""


def _slug(english: str) -> str:
    return catalog.slug_for("UI", english)


def _tree(root: Path, source: str, catalog_text: str, baseline: dict | None = None) -> None:
    write(root / "game" / "src" / "ui" / "panel.gd", source)
    write(root / "game" / "locale" / "ui.tres", catalog_text)
    write(root / "game" / "locale" / "gaps.json", json.dumps(baseline or {}))


def _check(root: Path) -> int:
    return engine._check(argparse.Namespace(repo_root=str(root), action="check"))


def _extract(root: Path, write_mode: bool = True) -> int:
    return engine._extract(
        argparse.Namespace(repo_root=str(root), action="extract", write=write_mode, only=[])
    )


@case("i18n: slug is deterministic and prefix-scoped")
def _slug_is_stable() -> None:
    expect(_slug("Ready") == _slug("Ready"), "the same English hashes to the same key")
    expect(
        catalog.slug_for("ITEM", "Ready") != _slug("Ready"),
        "the same English in another area is a different key",
    )
    expect(_slug("Ready") != _slug("Ready."), "a different English is a different key")


@case("i18n: escape/unescape round-trips quotes, newline, tab and a backslash")
def _escape_round_trips() -> None:
    for value in ('He said "hi"', "line\nbreak", "tab\there", "back\\slash", ""):
        expect(catalog.unescape(catalog.escape(value)) == value, f"round-trip {value!r}")


@case("i18n check: a consistent, fully migrated tree is GREEN")
def _consistent_is_green() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        key = _slug("Okay")
        _tree(root, _MIGRATED % key, catalog.render("en", {key: "Okay"}))
        expect(_check(root) == 0, "a migrated file with a matching catalog passes")


@case("i18n check: a leftover sink in a migrated file is RED")
def _leftover_is_red() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        key = _slug("Okay")
        _tree(root, _LEFTOVER % key, catalog.render("en", {key: "Okay"}))
        expect(_check(root) == 1, "a file that uses L.t and still hardcodes a sink must fail")


@case("i18n check: a key missing from the catalog is RED")
def _missing_row_is_red() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _tree(root, _MIGRATED % _slug("Okay"), catalog.render("en", {}))
        expect(_check(root) == 1, "a used key with no catalog row must fail")


@case("i18n check: an orphan catalog row is RED")
def _orphan_is_red() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        key = _slug("Okay")
        _tree(
            root,
            _MIGRATED % key,
            catalog.render("en", {key: "Okay", _slug("Nobody"): "Nobody uses me"}),
        )
        expect(_check(root) == 1, "a catalog row no source uses must fail")


@case("i18n check: a key whose hash does not match its English is RED")
def _wrong_hash_is_red() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _tree(
            root,
            _MIGRATED % "LOC_UI_DEADBEEF01",
            catalog.render("en", {"LOC_UI_DEADBEEF01": "Okay"}),
        )
        expect(_check(root) == 1, "a hand-edited key that does not hash its English must fail")


@case("i18n check: a UI script that GAINED a sink since the baseline is RED")
def _growth_is_red() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _tree(root, _HARDCODED, catalog.render("en", {}), baseline={})
        expect(_check(root) == 1, "new hardcoded English past the baseline must fail")


@case("i18n extract then check: the rewrite is GREEN and idempotent")
def _extract_round_trip() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _tree(root, _HARDCODED, catalog.render("en", {}))
        source = root / "game" / "src" / "ui" / "panel.gd"
        _extract(root)
        rewritten = source.read_text(encoding="utf-8")
        expect("L.t(" in rewritten, "the sink now calls the resolver")
        expect(_check(root) == 0, "the rewritten tree passes the gate")
        _extract(root)
        expect(source.read_text(encoding="utf-8") == rewritten, "a second extract changes nothing")
