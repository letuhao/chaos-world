"""Red-path self-tests for the i18n gate.

A guard that has never been seen to fail is not a guard (INC-0016), and the i18n validator
lives in Python where the GDScript suite cannot reach it. Each case builds a throwaway repo
tree, points the engine at it, and asserts the verdict — a clean tree is GREEN and each way of
being wrong is RED. One case runs the whole extract -> check loop, so the rewrite is proven,
not just asserted. Nothing here touches the real repository.
"""

from __future__ import annotations

import argparse
import csv
import json
import tempfile
from pathlib import Path

from ..selftest import case, expect, write
from . import catalog, engine

_MIGRATED = """extends Control


func _hint_text() -> String:
\treturn L.t("%s")
"""

_LEFTOVER = """extends Control


func _hint_text() -> String:
\treturn L.t("%s")
\treturn "Leftover"
"""

_HARDCODED = """extends Control


func _hint_text() -> String:
\treturn "Ready"
"""

_CONST_DICT = """extends Control


var REASON_TEXT := {
\t"no_actor": L.t("%s"),
}
"""

_STATIC_CONST = """extends RefCounted


const OUTCOME_TEXT := {
\t"fired": "the trap fired",
}


static func outcome_text(reason: String) -> String:
\treturn String(OUTCOME_TEXT.get(reason, reason))
"""


def _slug(english: str) -> str:
    return catalog.slug_for("UI", english)


def _tree(root: Path, source: str, catalog_text: str, baseline: dict | None = None) -> None:
    write(root / "game" / "src" / "ui" / "panel.gd", source)
    write(root / "game" / "locale" / "ui.tres", catalog_text)
    write(root / "game" / "locale" / "gaps.json", json.dumps(baseline or {}))


def _check(root: Path) -> int:
    return engine._check(argparse.Namespace(repo_root=str(root), action="check"))


def _extract(root: Path, write_mode: bool = True, scope: str = "sinks") -> int:
    return engine._extract(
        argparse.Namespace(
            repo_root=str(root), action="extract", write=write_mode, only=[], scope=scope
        )
    )


def _content_tree(root: Path, tres_text: str) -> None:
    """A minimal `game/data` content tree. NO catalog: content English lives in the `.tres`."""
    write(root / "game" / "data" / "items" / "probe.tres", tres_text)
    write(root / "game" / "locale" / "gaps.json", "{}")


def _export(root: Path, locale: str) -> int:
    return engine._export(argparse.Namespace(repo_root=str(root), locale=locale))


def _import(root: Path, locale: str, csv_path: Path) -> int:
    return engine._import(argparse.Namespace(repo_root=str(root), locale=locale, csv=str(csv_path)))


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


@case("i18n check: editing a catalog's English is GREEN (the key is stable)")
def _edited_english_is_green() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        key = _slug("Ready")
        # The row was copy-edited in place. The key is unchanged and opaque, so the gate must
        # pass: this is the whole point of a stable key over a content hash (ADR 0918).
        _tree(root, _MIGRATED % key, catalog.render("en", {key: "Ready to go"}))
        expect(_check(root) == 0, "a stable key survives an English edit with no re-key")


@case("i18n: assign_key reuses a key for the same text and mints a distinct one after an edit")
def _assign_key_is_stable() -> None:
    base = catalog.slug_for("UI", "Ready")
    expect(
        catalog.assign_key("UI", "Ready", {base: "Ready"}) == base,
        "the same text reuses its existing key",
    )
    fresh = catalog.assign_key("UI", "Ready", {base: "Ready to go"})
    expect(fresh != base, "a row edited away from that text forces a NEW key, not a clobber")
    expect(fresh not in {base}, "and the new key is free")


@case("i18n check: a 2-arg key that does not hash its inline English is RED")
def _inline_english_mismatch_is_red() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        source = (
            "extends Control\n\n\nfunc _hint_text() -> String:\n"
            '\treturn L.t("LOC_UI_DEADBEEF01", "Okay")\n'
        )
        _tree(root, source, catalog.render("en", {"LOC_UI_DEADBEEF01": "Okay"}))
        expect(_check(root) == 1, "a 2-arg key must hash the English it carries in source")


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


@case("i18n: a wrapped const dictionary is seen as a USE, not pruned as an orphan")
def _const_dict_is_a_use() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        key = _slug("The world has no one")
        _tree(root, _CONST_DICT % key, catalog.render("en", {key: "The world has no one"}))
        expect(_check(root) == 0, "the dict's L.t row is a use, so it is not an orphan")
        _extract(root)
        expect(_check(root) == 0, "extract keeps the row: the use is found inside the region")


@case("i18n: a const holds a bare KEY, never a `var` (a `var REASON_TEXT` fails lint)")
def _static_const_holds_a_key() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _tree(root, _STATIC_CONST, catalog.render("en", {}))
        result = engine.scan_all(Path(root))[0][1]
        kinds = {finding.kind for finding in result.findings}
        expect("gd_const_kw" not in kinds, "the const stays a const (a var would fail lint)")
        expect(kinds == {"gd_const_key"}, "its literal becomes a bare key a reader resolves")


_CONTENT_TRES = """[gd_resource type="Resource" script_class="ItemDef" load_steps=2 format=3]

[resource]
id = &"probe"
display_name = "Jade Pendant"
"""


@case("i18n: content migrates the .tres field to a KEY and fills the owner catalog")
def _content_migrates_to_a_key() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _content_tree(root, _CONTENT_TRES)
        expect(_check(root) == 0, "an unmigrated field is a GAP, not a gate failure")
        _extract(root, scope="content")
        text = (root / "game" / "data" / "items" / "probe.tres").read_text(encoding="utf-8")
        expect(
            'display_name = "LOC_ITEMS_PROBE_DISPLAY_NAME"' in text,
            "the field now holds a readable key derived from the def id + field",
        )
        rows = catalog.load(root / "game" / "locale" / "items.tres")
        expect(rows.get("LOC_ITEMS_PROBE_DISPLAY_NAME") == "Jade Pendant", "and its English row")
        expect(_check(root) == 0, "the migrated tree passes the gate")


@case("i18n check: a migrated content key with no catalog row is RED")
def _content_key_without_a_row_is_red() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _content_tree(root, _CONTENT_TRES.replace("Jade Pendant", "LOC_ITEMS_PROBE_DISPLAY_NAME"))
        expect(_check(root) == 1, "the .tres holds a key no owner catalog carries")


@case("i18n export/import: a filled template becomes a subset locale catalog")
def _export_import_round_trip() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _content_tree(root, _CONTENT_TRES)
        _extract(root, scope="content")  # the en catalog must exist before a locale subset
        _export(root, "vi")
        template = root / "build" / "i18n" / "vi.csv"
        rows = list(csv.DictReader(template.read_text(encoding="utf-8").splitlines()))
        expect(len(rows) == 1, "the template carries the one string to translate")
        expect(rows[0]["english"] == "Jade Pendant", "with its English for reference")
        # A translator fills the `translation` column and hands the file back.
        filled = root / "filled.csv"
        write(
            filled,
            "key,owner,english,translation\n"
            + ",".join([rows[0]["key"], rows[0]["owner"], rows[0]["english"], "Ngoc Bi"])
            + "\n",
        )
        _import(root, "vi", filled)
        expect(_check(root) == 0, "the imported locale catalog is a valid subset")
        translated = catalog.load(root / "game" / "locale" / "items.vi.tres")
        expect(list(translated.values()) == ["Ngoc Bi"], "the row landed under the derived key")


_ARRAY_TRES = """[gd_resource type="Resource" script_class="NpcPlaceVoice" load_steps=2 format=3]

[resource]
id = &"qi_dao"
names = Array[String](["the woman sweeping", "the boy on the steps"])
plausible_tiers = Array[String](["minor"])
"""

_FORMAT_SINK = """extends Control


func _hint_text() -> String:
\treturn "%s x%d" % [_name, _count]
"""


@case("i18n: an array-valued display field keys each element")
def _array_field_keys_each_element() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write(root / "game" / "data" / "npc" / "probe.tres", _ARRAY_TRES)
        write(root / "game" / "locale" / "gaps.json", "{}")
        result = engine.scan_all(Path(root))[0][1]
        keys = [finding.key for finding in result.findings]
        expect(
            keys == ["LOC_NPC_QI_DAO_NAMES_1", "LOC_NPC_QI_DAO_NAMES_2"],
            f"each list element gets its own key, and a code array is ignored: {keys}",
        )


@case("i18n: a format string is keyed as the message, its arguments left as data")
def _format_string_is_keyed() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _tree(root, _FORMAT_SINK, catalog.render("en", {}))
        _extract(root)
        text = (root / "game" / "src" / "ui" / "panel.gd").read_text(encoding="utf-8")
        expect(
            'L.t("LOC_UI_' in text and '") % [_name, _count]' in text,
            f"the literal is keyed and the arguments stay: {text!r}",
        )
        rows = catalog.load(root / "game" / "locale" / "ui.tres")
        expect("%s x%d" in rows.values(), "the MESSAGE is the row, not the formatted result")
