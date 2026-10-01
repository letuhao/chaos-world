"""Update Qi realm seed .tres files with calculated profile factors."""

import re
from pathlib import Path

REALM_DIR = Path(__file__).parent.parent / "game" / "data" / "qi_cultivation" / "realms"

REALMS = [
    ("qi_refining", "mortal", 1),
    ("foundation", "mortal", 2),
    ("core_formation", "mortal", 3),
    ("nascent_soul", "mortal", 4),
    ("spirit_transformation", "mortal", 5),
    ("void_refinement", "mortal", 6),
    ("body_integration", "mortal", 7),
    ("great_ascension", "mortal", 8),
    ("tribulation", "mortal", 9),
    ("spirit_condensation", "spirit", 1),
    ("spirit_sea", "spirit", 2),
    ("spirit_palace", "spirit", 3),
    ("spirit_manifestation", "spirit", 4),
    ("spirit_severing", "spirit", 5),
    ("spirit_unity", "spirit", 6),
    ("spirit_domain", "spirit", 7),
    ("spirit_sovereign", "spirit", 8),
    ("spirit_ascension", "spirit", 9),
    ("earth_immortal", "immortal", 1),
    ("heaven_immortal", "immortal", 2),
    ("golden_immortal", "immortal", 3),
    ("mystic_immortal", "immortal", 4),
    ("true_immortal", "immortal", 5),
    ("primordial_immortal", "immortal", 6),
    ("great_luo", "immortal", 7),
    ("dao_fruit", "immortal", 8),
    ("immortal_sovereign", "immortal", 9),
    ("transcendent", "transcendent", 1),
    ("dao_ancestor", "transcendent", 2),
    ("primordial_origin", "transcendent", 3),
]


def calc_factors(tier: str, local: int) -> dict:
    if tier == "mortal":
        P = 1 * (1.25 ** (local - 1))
    elif tier == "spirit":
        P = 8 * (1.22 ** (local - 1))
    elif tier == "immortal":
        P = 55 * (1.20 ** (local - 1))
    elif tier == "transcendent":
        P = 330 * (1.35 ** (local - 1))
    else:
        raise ValueError(f"Unknown tier: {tier}")

    return {
        "P": round(P, 2),
        "C": round(P**0.85, 2),
        "F": round(P**0.40, 2),
        "T": round(P**0.55, 2),
    }


def update_tres(realm_id: str, factors: dict) -> None:
    path = REALM_DIR / f"{realm_id}.tres"
    if not path.exists():
        print(f"SKIP {realm_id}: file not found")
        return

    text = path.read_text(encoding="utf-8")

    # Update or insert throughput_factor and technique_factor
    # These are new fields that may not exist yet
    if "throughput_factor" in text:
        text = re.sub(
            r"throughput_factor\s*=\s*[\d.]+",
            f"throughput_factor = {factors['F']}",
            text,
        )
    else:
        # Insert after dantian_capacity line
        text = re.sub(
            r"(dantian_capacity\s*=\s*[\d.]+)",
            f"\\1\nthroughput_factor = {factors['F']}",
            text,
        )

    if "technique_factor" in text:
        text = re.sub(
            r"technique_factor\s*=\s*[\d.]+",
            f"technique_factor = {factors['T']}",
            text,
        )
    else:
        # Insert after throughput_factor line
        text = re.sub(
            r"(throughput_factor\s*=\s*[\d.]+)",
            f"\\1\ntechnique_factor = {factors['T']}",
            text,
        )

    path.write_text(text, encoding="utf-8")
    print(f"OK   {realm_id}: P={factors['P']} C={factors['C']} F={factors['F']} T={factors['T']}")


def main() -> None:
    for realm_id, tier, local in REALMS:
        factors = calc_factors(tier, local)
        update_tres(realm_id, factors)


if __name__ == "__main__":
    main()
