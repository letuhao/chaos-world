"""Red-path self-tests for `tools portrait_fallback`.

A guard shipped in Python is unreachable from the GDScript suite, so nothing asserts it still goes
RED unless its cases are loaded (INC-0016). Separate module beside `race_from_lore_selftest`,
`png_provenance_selftest` and `render_durability_selftest`, because `tools/selftest_cases.py` is
shared and an append there cannot be committed without sweeping another session's cases (INC-0041).

## What each case proves

The defect: `authored_races()` read only `game/data/races/*.tres`, which holds 5 entries, while the
401-character cast names 30 species. So 347 characters had no fallback and could not be published at
all — and unlike the 17 `unique-0001` layers this was filed against, they were invisible, because a
character with no def does not appear in the def directory to be counted.

Each case pins one rule, and each also asserts the conforming case is NOT caught, so the rules
discriminate rather than refusing everything:

- a species with NO `RaceDef` is transcribed from the Lore Bible, not skipped
- an AUTHORED `RaceDef` outranks the Bible for the same species (precedence is the decision)
- an affinity with no assigned hue is NEUTRAL, and no colour is invented for it
- a tied top affinity is neutral rather than whichever sorted first
- EVERY species the catalog names resolves to a committed silhouette — the coverage assertion, which
  is the one that would have caught the original defect
"""

from __future__ import annotations

from . import portrait_fallback as pf
from .selftest import case, expect


@case("portrait_fallback: a species with NO RaceDef is transcribed from the Lore Bible")
def _species_without_racedef_comes_from_the_bible() -> None:
    """347 of 401 characters named a species with no `RaceDef`, so they had no fallback at all.

    The Bible already carries `affinities` per species, so the colour is authored data being read,
    not a per-species decision being invented here. A species skipped instead leaves its characters
    unpublishable, which is the defect.
    """
    lore = pf.lore_races()
    expect(
        len(lore) > 5,
        f"the Lore Bible yielded {len(lore)} race tint(s); the five hand-authored races are all it "
        "should find, so the Bible is not being read",
    )
    on_disk = {path.stem for path in pf.FALLBACK_ROOT.glob("*.png")}
    missing = sorted(set(lore) - on_disk)
    expect(
        not missing,
        f"{len(missing)} species the Bible describes have no committed silhouette: {missing[:6]}",
    )
    expect(
        "longwinter" in lore,
        "longwinter is one of the 21-character species this exists to cover, and is absent",
    )


@case("portrait_fallback: an AUTHORED RaceDef outranks the Lore Bible for the same species")
def _authored_racedef_outranks_the_bible() -> None:
    """Precedence is the whole decision, so it is asserted rather than assumed.

    `commonborn` exists as both a `.tres` and a Bible entity. If the Bible ever won, a retune of the
    game-facing table would be silently ignored by the fallback - the drift ADR 0253 exists to stop,
    reappearing through a different door.
    """
    text = (pf.GAME_DIR / "data/races/commonborn.tres").read_text(
        encoding="utf-8", errors="replace"
    )
    import re

    affinities = re.search(r"^affinities = \{(.+)\}\s*$", text, re.MULTILINE)
    expect(affinities is not None, "commonborn.tres declares no affinities line to compare against")
    authored = {race_id: rgb for race_id, rgb in pf.authored_races() if race_id == "commonborn"}
    expect(bool(authored), "commonborn is missing from authored_races()")
    if affinities is not None and authored:
        from_authored = pf._ranked_affinity_rgb(
            re.findall(r'"(\w+)":\s*([0-9.]+)', affinities.group(1))
        )
        expect(
            authored["commonborn"] == from_authored,
            f"authored_races() reports {authored['commonborn']} for commonborn, but its own .tres "
            f"says {from_authored}; the Bible overrode the game-facing table",
        )


@case("portrait_fallback: an affinity with no assigned hue is NEUTRAL, never invented")
def _unmapped_affinity_is_neutral() -> None:
    """`dark`, `light` and `wind` lead 15 of the 30 species and have no hue in `AFFINITY_RGB`.

    Inventing one here would be art direction this tool has no standing to make; the palette is
    `docs/art-direction.md`'s. NEUTRAL is the honest reading of "no colour identity assigned yet",
    and it is also visible: 15 species sharing one grey is a gap a reviewer can see,
    hue would be a decision nobody made.
    """
    expect(
        "dark" not in pf.AFFINITY_RGB and "light" not in pf.AFFINITY_RGB,
        "dark/light have acquired a hue in AFFINITY_RGB; if that was a deliberate art-direction "
        "decision, say so here rather than leaving the test to discover it",
    )
    rgb = pf._ranked_affinity_rgb([("dark", "9.0"), ("earth", "4.0")])
    expect(
        rgb == pf.NEUTRAL_RGB,
        f"an unmapped leading affinity produced {rgb}, not the neutral {pf.NEUTRAL_RGB}",
    )
    # And the control: a mapped one still colours.
    mapped = pf._ranked_affinity_rgb([("fire", "9.0"), ("earth", "4.0")])
    expect(
        mapped == pf.AFFINITY_RGB["fire"],
        f"a mapped leading affinity produced {mapped}, not {pf.AFFINITY_RGB['fire']}",
    )


@case("portrait_fallback: a TIED top affinity yields neutral, not whichever sorted first")
def _tied_affinity_is_neutral() -> None:
    """A body with two equal affinities has no single identity and must not be handed one by a sort.

    `sorted(..., key=(-value, name))` is deterministic, so the tempting implementation is to take
    `ranked[0]` and let the alphabet decide. That makes `earth` beat `fire` for every body carrying
    both at equal strength, which is an authored identity invented by a sort key.
    """
    expect(
        pf._ranked_affinity_rgb([("fire", "5.0"), ("earth", "5.0")]) == pf.NEUTRAL_RGB,
        "two affinities tied at the top produced a colour rather than the neutral placeholder",
    )
    expect(
        pf._ranked_affinity_rgb([]) == pf.NEUTRAL_RGB,
        "a species with no affinities produced a colour rather than the neutral placeholder",
    )


@case("portrait_fallback: EVERY species the catalog names has a committed silhouette")
def _every_catalog_species_is_served() -> None:
    """The coverage assertion, and the one that would have caught the original defect.

    Held against the CATALOG rather than the race table, because the catalog is what makes a
    fallback reachable: a body plan nobody is born as does not need a face.
    """
    catalog_ids = pf.catalog_races()
    expect(
        len(catalog_ids) > 5,
        f"the catalog named {len(catalog_ids)} body plan(s), which is the race table's count, so "
        "the catalog is not being read and this case measures the wrong thing",
    )
    on_disk = {path.stem for path in pf.FALLBACK_ROOT.glob("*.png")}
    unserved = sorted(set(catalog_ids) - on_disk)
    expect(
        not unserved,
        f"{len(unserved)} of {len(catalog_ids)} species the cast is born as have no silhouette: "
        f"{unserved[:8]}. Those characters cannot be published at all.",
    )
    derived = {race_id for race_id, _ in pf.authored_races()}
    expect(
        set(catalog_ids) <= derived,
        f"{sorted(set(catalog_ids) - derived)[:6]} are named by the catalog but absent from "
        "authored_races(), so `write` would never create them",
    )
