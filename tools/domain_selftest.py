"""Red-path self-tests for `tools domain audit` (INC-0016).

Separate from `tools/domain.py` for the same reason `tools/data_selftest.py` is
separate from `tools/data.py`: a validator is shipped code and a test of it is not,
and importing `domain.py` must not register cases. `tools/selftest_cases.py` imports
this module for the grep, one line.

Every case builds a temp `game/` tree and runs the audit BOTH ways: a corpus whose
fixture reward resolves is GREEN, and the SAME corpus with the item file absent — the
only difference under test — is RED. A gate that fired on everything would satisfy
the red half; a gate that resolved nothing would satisfy the green one. The rule
being graded is ADR 0216's consequences: a fixture reward or key the item corpus
cannot resolve answers `inventory_full` forever while reading as SEALED.
"""

from __future__ import annotations

import tempfile
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

from . import domain as domain_tool
from .selftest import case, expect, write

_TEMPLATE = """[gd_resource type="Resource" script_class="DomainTemplateDef" format=3]

[ext_resource type="Resource" path="res://src/data/domains/rooms/fixture_room.tres" id="1_room"]

[resource]
template_id = &"fixture_template"
min_rooms = 6
max_rooms = 10
room_pool = Array[RoomDef]([ExtResource("1_room")])
"""


def _room(reward: str, key: str = "") -> str:
    return (
        '[gd_resource type="Resource" script_class="RoomDef" format=3]\n\n'
        "[resource]\n"
        'room_id = &"fixture_room"\n'
        "fixtures = Array[Dictionary]([\n"
        '\t{"fixture_id": &"fixture_hoard", "kind": &"treasure", '
        f'"reward_item_id": &"{reward}", "reward_count": 1, "key_item_id": &"{key}", '
        '"requires_realm": &""}\n'
        "])\n"
    )


def _item(item_id: str) -> str:
    return (
        '[gd_resource type="Resource" script_class="ItemDef" format=3]\n\n'
        "[resource]\n"
        f'id = &"{item_id}"\n'
    )


@contextmanager
def _fixture(files: dict[str, str]) -> Iterator[domain_tool]:
    """Run the audit over a `game/` tree this module owns.

    The module's roots are redirected rather than shipped so a case can prove the
    converse — that removing the item file turns the SAME room red — and so nothing
    here depends on what the tree happens to author today.
    """
    with tempfile.TemporaryDirectory() as raw:
        game = Path(raw) / "game"
        for relative, text in files.items():
            write(game / relative, text)
        originals = (
            domain_tool.GAME_DIR,
            domain_tool.SRC_DOMAIN_ROOT,
            domain_tool.TEMPLATE_DIR,
            domain_tool.ROOM_DIR,
            domain_tool.ITEM_DIR,
        )
        domain_tool.GAME_DIR = game
        domain_tool.SRC_DOMAIN_ROOT = game / "src" / "data" / "domains"
        domain_tool.TEMPLATE_DIR = domain_tool.SRC_DOMAIN_ROOT / "templates"
        domain_tool.ROOM_DIR = domain_tool.SRC_DOMAIN_ROOT / "rooms"
        domain_tool.ITEM_DIR = game / "data" / "items"
        try:
            yield domain_tool
        finally:
            (
                domain_tool.GAME_DIR,
                domain_tool.SRC_DOMAIN_ROOT,
                domain_tool.TEMPLATE_DIR,
                domain_tool.ROOM_DIR,
                domain_tool.ITEM_DIR,
            ) = originals


_BASE = {"src/data/domains/templates/fixture_template.tres": _TEMPLATE}


@case("domain audit: a fixture reward the item corpus cannot resolve is RED")
def _unresolvable_reward_is_red() -> None:
    resolved = {
        **_BASE,
        "src/data/domains/rooms/fixture_room.tres": _room("fixture_relic"),
        "data/items/material/fixture_relic.tres": _item("fixture_relic"),
    }
    with _fixture(resolved) as tool:
        expect(tool._audit_command("error") == 0, "a resolvable reward passes the gate")
    dangling = {**_BASE, "src/data/domains/rooms/fixture_room.tres": _room("ghost_relic")}
    with _fixture(dangling) as tool:
        expect(tool._audit_command("error") == 1, "an unresolvable reward fails the gate")


@case("domain audit: a fixture KEY the item corpus cannot resolve is RED too")
def _unresolvable_key_is_red() -> None:
    resolved = {
        **_BASE,
        "src/data/domains/rooms/fixture_room.tres": _room("fixture_relic", "fixture_key"),
        "data/items/material/fixture_relic.tres": _item("fixture_relic"),
        "data/items/key/fixture_key.tres": _item("fixture_key"),
    }
    with _fixture(resolved) as tool:
        expect(tool._audit_command("error") == 0, "a resolvable key passes the gate")
    dangling = {
        **_BASE,
        "src/data/domains/rooms/fixture_room.tres": _room("fixture_relic", "ghost_key"),
        "data/items/material/fixture_relic.tres": _item("fixture_relic"),
    }
    with _fixture(dangling) as tool:
        expect(tool._audit_command("error") == 1, "an unresolvable key fails the gate")
