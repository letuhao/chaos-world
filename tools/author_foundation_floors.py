"""Author the cultivation ladder's FOUNDATION FLOORS (BL-0951 / ADR 0939).

One `min_foundation` per realm seed, for every path that has one: the carried foundation
an actor must hold before a breakthrough INTO that realm is allowed. The curve is a
design decision recorded here so retuning it is one edit rather than a 60-file sweep:

    min_foundation(ordinal) = clamp(0.05 * (ordinal - 3), 0.0, 0.8)

Ordinal is 1-based on the authored ladder (`realm_defaults.gd`, read through the one
parser in `tools/cultivation/seed.py`), so R1..R3 are free (the early realms teach), R4
asks 0.05, and the ladder tops out at 0.8 from R20 on. A PERFECTED run — every departure
snapshotted at 1.0 — clears every floor; a sloppy one (depth 0 everywhere) hits the wall
at R4, which each path's traversal matrix proves.

Each path authors the field on its OWN seeds (ADR 0939 ruling 1: the shared module owns
the record, each path implements its own rules over it), so the targets below are
`(directory, the scalar line the field follows)`. Idempotent: a seed that already authors
`min_foundation` is left alone, so a hand retune survives a re-run. Run with
`uv run python tools/author_foundation_floors.py`.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))

from tools.cultivation.seed import realms as ladder_realms  # noqa: E402

TARGETS: tuple[tuple[Path, str], ...] = (
    (ROOT / "game" / "data" / "qi_cultivation" / "realms", "channel_refinement_cap"),
    (ROOT / "game" / "data" / "body_cultivation" / "realms", "refinement_cap"),
    (ROOT / "game" / "data" / "mind_cultivation" / "realms", "channel_refinement_cap"),
)


def floor_for(ordinal: int) -> float:
    return round(min(0.8, max(0.0, 0.05 * (ordinal - 3))), 2)


def _author(directory: Path, anchor_field: str, ordinals: dict) -> tuple[list[str], list[str]]:
    wrote: list[str] = []
    kept: list[str] = []
    anchor_re = re.compile(rf"(?m)^{anchor_field} = -?\d+$")
    for path in sorted(directory.glob("*.tres")):
        raw = path.read_bytes()
        crlf = b"\r\n" in raw
        text = raw.decode("utf-8").replace("\r\n", "\n")
        id_match = re.search(r'(?m)^id = &"([^"]+)"', text)
        if not id_match:
            continue
        realm_id = id_match.group(1)
        if "min_foundation" in text:
            kept.append(realm_id)
            continue
        ordinal = ordinals.get(realm_id)
        anchor = anchor_re.search(text)
        if ordinal is None or anchor is None:
            continue
        value = floor_for(ordinal)
        text = text[: anchor.end()] + f"\nmin_foundation = {value}" + text[anchor.end() :]
        out = text.replace("\n", "\r\n") if crlf else text
        path.write_bytes(out.encode("utf-8"))
        wrote.append(f"{directory.name}: {realm_id} = {value}")
    return wrote, kept


def main() -> int:
    ordinals = {
        realm_id: index + 1 for index, (realm_id, _name, _tier) in enumerate(ladder_realms())
    }
    wrote: list[str] = []
    kept: list[str] = []
    for directory, anchor_field in TARGETS:
        rows, kept_rows = _author(directory, anchor_field, ordinals)
        wrote.extend(rows)
        kept.extend(kept_rows)
    print(f"wrote {len(wrote)} seed(s), kept {len(kept)} already-authored")
    for row in wrote:
        print(f"  + {row}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
