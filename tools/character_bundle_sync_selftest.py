"""Red-path self-tests for `tools character_bundle_sync publish-races`.

A write action is not exempt from the red-path rule. The separating decision: no `PortraitDef` may
be written for a species whose silhouette is not committed. A `publish-races` that always produces
one reproduces the false-claim class that DEF-0293 filed — a row asserting a resource nothing on
disk can answer for.

Every fixture is a temp dir patched over the tool's own `PORTRAIT_ROOT` and `GAME_DIR`; no case
writes the real tree.
"""

from __future__ import annotations

import argparse
import contextlib
import io
import re
import tempfile
from pathlib import Path

from . import character_bundle_sync as sync
from .common import GAME_DIR
from .selftest import case, expect


@contextlib.contextmanager
def _isolated_game_dir():
    """A temp dir patched over `sync.GAME_DIR` and `sync.PORTRAIT_ROOT`.

    `PORTRAIT_ROOT` is derived from `GAME_DIR` at module scope, so both are rebound: the silhouette
    check reads `GAME_DIR / layer.removeprefix("res://")`, and the write target is `PORTRAIT_ROOT`.
    """
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        portraits = root / "data" / "portraits"
        portraits.mkdir(parents=True)
        assets = root / "assets" / "characters" / "portraits"
        assets.mkdir(parents=True)
        # Map every def name to a silhouette that is NOT there, so every `publish-races` species
        # reports a missing layer. The check is: nothing is written.
        original_game = sync.GAME_DIR
        original_root = sync.PORTRAIT_ROOT
        sync.GAME_DIR = root
        sync.PORTRAIT_ROOT = portraits
        try:
            yield portraits
        finally:
            sync.GAME_DIR = original_game
            sync.PORTRAIT_ROOT = original_root


@case("character_bundle_sync: publish-races writes NOTHING when every silhouette is missing")
def _publish_races_refuses_an_unbacked_species() -> None:
    """The one decision that separates publish-races from a file generator.

    With a portraits root patched to an empty temp dir and a `GAME_DIR` whose portraits folder is
    empty, every species' `layer_paths` points at a PNG that is not there. The correct output is one
    refusal per species and ZERO files written. A tool that writes anyway is asserting, into the
    game's content directory, the existence of art it could not check.
    """
    args = argparse.Namespace(character_bundle_sync_action="publish-races", force=False)
    with _isolated_game_dir() as portraits:
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer), contextlib.redirect_stderr(buffer):
            code = sync.run(args)

        written = sorted(p.name for p in portraits.glob("*.tres"))
        expect(
            written == [],
            f"publish-races wrote {len(written)} defs with no silhouette to back them: "
            f"{written[:5]}",
        )
        out = buffer.getvalue()
        expect(
            "missing_layer" in out or "no committed silhouette" in out,
            "publish-races did not report WHY nothing was written; it said: "
            + (out[-140:] or "<silence>"),
        )
        expect(
            code == 1,
            f"publish-races returned {code} for an empty silhouettes dir; the refusal must be loud",
        )


@case("character_bundle_sync: the placeholder vocabulary is the five race defs', not invented")
def _placeholder_vocabulary_is_inherited_not_invented() -> None:
    """Every new PortraitDef describes itself in words `PortraitDef.trait_value` can answer.

    `visual_traits` uses `form:plain` and `palette:neutral`, copied from the five hand-authored race
    defs. Inventing a third value would be a trait nothing in the game matches — the failure mode
    where a variant key looks up a face and finds one that answers a different question.
    """
    real_traits: set[str] = set()
    for path in (GAME_DIR / "data/races").glob("*.tres"):
        real_traits.update(
            re.findall(r'&"([^"]+)"', path.read_text(encoding="utf-8", errors="replace"))
        )

    expect(
        "form:plain" in real_traits and "palette:neutral" in real_traits,
        f"the placeholder traits are absent from every race def: form:plain and palette:neutral "
        f"were invented rather than inherited. Found: {sorted(real_traits)[:12]}",
    )
