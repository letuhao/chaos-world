"""Red-path self-tests for the catalog's render-durability rule.

A guard shipped in Python is unreachable from the GDScript suite, so nothing asserts it still goes
RED unless its cases are loaded (INC-0016). Separate module, beside `race_from_lore_selftest` and
`png_provenance_selftest`, because `tools/selftest_cases.py` is shared and an append there cannot be
committed without sweeping another session's in-flight cases (INC-0041).

## What each case proves

One defect, measured: `unique_characters daily-family` rebuilt each record's whole `daily_life`
family from fresh literal dicts, so a rendered daily shot lost its `path`, `source`, `prompt`,
`generated_on`, `license` and its `status: generated` on the next re-run. The catalog went to 10411
shot rows carrying ZERO paths, while git history never held 19 either - so the provenance had been
written, lost, and never committed.

Each case builds a shot with a render recorded, rebuilds the family, and asserts it survives:

- every reality field survives a rebuild
- `status: generated` is not regressed to `planned`
- AUTHORING fields (scene, pose, expression, framing) ARE rewritten, so the fix is not "keep
  everything" - a rebuild that preserved stale authoring would never re-brief a daypart
- a daypart with no prior row is unchanged
- `withdrawn` survives too, so a rebuild cannot quietly un-withdraw art that failed a visual audit

Every fixture is an in-memory record. No case reads or writes a shard, the real catalog, or the art
root.
"""

from __future__ import annotations

from . import unique_characters as uc
from .selftest import case, expect

#: A shot carrying every field a render writes. If the rebuild loses one, that is the defect.
RENDERED = {
    "id": "daily-life-0001-dawn",
    "slot": "daily_life",
    "kind": "scene",
    "canvas": [1536, 1024],
    "scene": "the old scene",
    "pose": "the old pose",
    "expression": "the old expression",
    "framing": "the old framing",
    "daypart": "dawn",
    "status": "generated",
    "path": "res://assets/characters/unique/unique-0001/daily_life/dawn.png",
    "source": "ComfyUI (unet (krea2/test.safetensors))",
    "prompt": "a plain figure at dawn",
    "generated_on": "2026-10-04",
    "license": "Generated locally for private use; source checkpoint license applies.",
    "seed": "851",
    "generation_settings": {"steps": 8, "cfg": 1.0},
    "withdrawn": "apparent age reads 18-35 against an authored 41",
}

#: The authoring fields a rebuild owns. Asserted to CHANGE, so the fix cannot be "preserve it all".
AUTHORING = ("scene", "pose", "expression", "framing", "canvas")


def _fresh(daypart: str) -> dict:
    """The shape `_daily_family_command` builds: authoring only, nothing about a render."""
    return {
        "id": f"daily-life-0001-{daypart}",
        "slot": "daily_life",
        "kind": "scene",
        "canvas": [1536, 1024],
        "scene": "the new scene",
        "pose": "the new pose",
        "expression": "the new expression",
        "framing": "the new framing",
        "daypart": daypart,
        "status": "planned",
    }


@case("unique_characters: rebuilding a daily_life family KEEPS the render it already recorded")
def _rebuild_preserves_the_render() -> None:
    """The measured defect, in miniature: one daypart, one render, one rebuild.

    Every reality field is checked by NAME rather than by a count, because a fix that preserved six
    of the seven would pass a count and is still the defect.
    """
    merged = uc._merge_shot_preserving_render(_fresh("dawn"), dict(RENDERED))
    for field in uc.RENDER_REALITY_FIELDS:
        expect(
            merged.get(field) == RENDERED[field],
            f"{field!r} was {merged.get(field)!r} after the rebuild, not the recorded "
            f"{RENDERED[field]!r}",
        )
    expect(
        merged["status"] == "generated",
        f"a rendered shot was relabelled {merged['status']!r} by a rebuild",
    )


@case("unique_characters: a rebuild REWRITES the authoring fields it owns")
def _rebuild_rewrites_authoring() -> None:
    """Preserving everything would be its own defect: the rebuild would never re-brief a daypart.

    The rule is that AUTHORING fields belong to the rebuild and REALITY fields belong to the
    filesystem. A fix that kept the old scene would make `daily-family` a no-op that silently
    declines to re-brief, and the next run would report success having changed nothing.
    """
    merged = uc._merge_shot_preserving_render(_fresh("dawn"), dict(RENDERED))
    for field in AUTHORING:
        expect(
            merged.get(field) == _fresh("dawn")[field],
            f"{field!r} kept the stale {RENDERED[field]!r} instead of the freshly authored value",
        )
    expect(
        merged["daypart"] == "dawn",
        f"the member field was rewritten to {merged['daypart']!r}, which would re-key the family",
    )


@case("unique_characters: a daypart with NO prior row is returned unchanged")
def _new_daypart_is_untouched() -> None:
    """The ordinary first-run case, and the one a defensive merge can quietly break.

    `dusk` has no prior row because it was never rendered. Returning a copy rather than the original
    is harmless; returning an EMPTY dict, or refusing, would silently drop the fourth daypart from a
    family that is required to have four.
    """
    fresh = _fresh("dusk")
    merged = uc._merge_shot_preserving_render(fresh, None)
    expect(merged == fresh, f"a first-run daypart came back as {merged!r}, not {fresh!r}")
    expect(
        merged.get("daypart") == "dusk" and merged.get("status") == "planned",
        f"the fourth daypart is not a planned shot any more: {merged!r}",
    )
    # And an EMPTY prior row behaves like no row, rather than copying empties over real values.
    empty = uc._merge_shot_preserving_render(_fresh("dusk"), {})
    expect(empty == fresh, f"an empty prior row changed the shot: {empty!r}")


@case("unique_characters: a rebuild carries `withdrawn` forward, so bad art stays withdrawn")
def _rebuild_keeps_withdrawn() -> None:
    """`withdrawn` is the marker that keeps failing art out of the index, and it is per-shot.

    Dropping it on a rebuild would un-withdraw 22 renders that a visual audit rejected, and
    `art_index` would then index them - the tool would be the mechanism that publishes art it is
    supposed to be refusing.
    """
    withdrawn_only = {
        "id": "daily-life-0001-day",
        "slot": "daily_life",
        "kind": "scene",
        "canvas": [1536, 1024],
        "scene": "s",
        "pose": "p",
        "expression": "e",
        "framing": "f",
        "daypart": "day",
        "status": "planned",
        "withdrawn": "gate-green but non-conforming: brass jewellery a faction grants none of",
    }
    merged = uc._merge_shot_preserving_render(_fresh("day"), withdrawn_only)
    expect(
        merged.get("withdrawn") == withdrawn_only["withdrawn"],
        f"the withdrawn marker was dropped by a rebuild; the shot is now {merged!r}",
    )


@case("unique_characters: an EMPTY prior value never overwrites a real one")
def _empty_values_do_not_clobber() -> None:
    """A `None` or `""` in the prior row means "not recorded", not "recorded as blank".

    Copying it through would turn a rendered shot's `source` into `""` - the row then carries a path
    and no provenance, which is a weaker version of the very defect this rule exists to fix.
    """
    sparse = {"daypart": "dawn", "status": "planned", "source": "", "prompt": None, "path": None}
    merged = uc._merge_shot_preserving_render(_fresh("dawn"), sparse)
    expect(
        merged.get("source") is None and merged.get("prompt") is None,
        f"an empty prior value was written into the shot: {merged!r}",
    )
    expect(
        "source" not in merged and "prompt" not in merged,
        f"the rebuilt shot gained empty fields it never had: {sorted(merged)}",
    )
    expect(
        merged["status"] == "planned",
        f"a planned prior row was relabelled {merged['status']!r}",
    )
