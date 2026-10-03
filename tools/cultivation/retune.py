"""Re-derive the balance scalars of the authored realm seeds, in place.

`cultivation seed` deliberately never overwrites a realm seed: it is a bootstrap for
a MISSING file, and a designer's hand-edited realm must survive it. That ruling is
right, and it is also why 24 of 30 seeds sat on a work budget from a deleted curve
with nothing to notice — the seeds and the ladder that produced them were two
ladders that nobody reconciled.

This is the reconciliation, as an explicit named act rather than a silent `--force`:

- it rewrites ONLY the balance scalars listed in `BALANCE_FIELDS`, leaving every
  other line of the `.tres` — id, item ids, meridian arrays, rewards, channel
  training — byte-identical. Authored intent outside the balance survives.
- it prints what it changed per realm, so a retune is reviewable rather than a
  surprise.
- `audit` asserts the on-disk scalars equal the ladders afterwards, so the two
  cannot drift apart again unnoticed. That assertion is the guard; this is the
  retune, and it never runs as part of `check`.
"""

from __future__ import annotations

import re

from ..common import REPO_ROOT, ToolError, info, ok
from . import ladder as ladder_module
from .report import DERIVED_FIELDS, REALM_DIR, load
from .seed import realms as ladder_realms

# The authored scalars this action owns. A field absent from a seed is an error,
# not something to append: adding a line the designer never asked for is exactly the
# silent overwrite this module exists to avoid.
BALANCE_FIELDS = (
    "progress_required",
    "physique_required",
    "quality_required",
    "quality_target",
    "integrity_target",
    "insight_required",
    "resonance_rank",
    "chance_base",
    "chance_cap",
)


def balance_values(realm_id: str, index: int, ratio: float) -> dict[str, str]:
    """The ladder's value for each balance field, formatted as it is stored."""
    return {
        "progress_required": f"{float(_budget(index))}",
        "physique_required": f"{ladder_module.physique_required(index, ratio):.1f}",
        "quality_required": f"{ladder_module.quality_gate(index):.6f}",
        "quality_target": f"{ladder_module.quality_ceiling(index):.6f}",
        "integrity_target": f"{ladder_module.integrity_target(index):.6f}",
        "insight_required": f"{_insight(index)}",
        "resonance_rank": f"{max(0, index - 17) if index >= 18 else 0}",
        "chance_base": f"{ladder_module.chance_base(index):.4f}",
        "chance_cap": f"{ladder_module.chance_cap(index):.4f}",
    }


def _budget(index: int) -> int:
    from .seed import labour_budget

    return labour_budget(index)


def _insight(index: int) -> float:
    return 10.0 + 6.0 * index + 2.0 * index * index


def rewrite(realm_id: str, index: int, ratio: float) -> tuple[str, list[str]]:
    """The seed text with its balance scalars replaced. Returns (text, changes)."""
    path = REALM_DIR / f"{realm_id}.tres"
    if not path.is_file():
        raise ToolError(f"missing realm seed: {path.relative_to(REPO_ROOT).as_posix()}")
    text = path.read_text(encoding="utf-8")
    values = balance_values(realm_id, index, ratio)
    changes: list[str] = []

    def replace(match: re.Match[str]) -> str:
        field, current = match.group(1), match.group(2)
        wanted = values.get(field)
        if wanted is None:
            return match.group(0)
        if field not in changes and current != wanted:
            changes.append(f"{field} {current} -> {wanted}")
        elif field not in changes:
            changes.append(f"{field} already {wanted}")
        return f"{field} = {wanted}"

    updated = re.sub(
        r"(?m)^(" + "|".join(BALANCE_FIELDS) + r") = (-?[\d.]+)$",
        replace,
        text,
    )
    missing = [field for field in BALANCE_FIELDS if f"{field} = " not in updated]
    if missing:
        raise ToolError(
            f"{realm_id}: seed declares no {', '.join(missing)}; this action rewrites authored"
            " lines and will not invent them"
        )
    return _drop_derived(updated, changes)


# `work_required`, `acupoint_work` and `meridian_work` are now derived in
# `BodyRealmSeed` from `progress_required` and the ladder index. A seed that still
# carries them is publishing a second copy of the same budget, which is what let the
# gate and its price drift apart in the first place. They are removed here rather than
# left to rot as "unknown property" lines that Godot's loader rejects.
DERIVED_LINES = re.compile(r"(?m)^(" + "|".join(DERIVED_FIELDS) + r") = -?[\d.]+\n")


def _drop_derived(text: str, changes: list[str]) -> tuple[str, list[str]]:
    removed = [match.group(1) for match in DERIVED_LINES.finditer(text)]
    if not removed:
        return text, changes
    return DERIVED_LINES.sub("", text), changes + [
        f"removed authored {name} (now derived)" for name in removed
    ]


def run() -> int:
    ratio = ladder_module.milestone_physique_ratio()
    if ratio is None:
        raise ToolError(
            "cannot read MILESTONE_PHYSIQUE_RATIO from BodyProgress; the physique floor is"
            " derived from the ladder's own grants and has no defensible default"
        )
    for index, (realm_id, _name, _tier) in enumerate(ladder_realms()):
        path = REALM_DIR / f"{realm_id}.tres"
        if not path.is_file():
            info(f"skip {realm_id}: no authored seed to retune")
            continue
        updated, changes = rewrite(realm_id, index, ratio)
        before = path.read_text(encoding="utf-8")
        if updated != before:
            path.write_text(updated, encoding="utf-8")
            removed = [line for line in changes if "removed authored" in line]
            moved = [line for line in changes if "already" not in line and line not in removed]
            info(f"R{index + 1:02d} {realm_id}: " + "; ".join(moved or removed))
    # Prove the write landed rather than trusting it: re-read every seed through the
    # same parser the validator uses.
    for realm_id, _name, _tier in ladder_realms():
        load(realm_id)
    ok("realm seeds retuned from the authored ladders")
    return 0
