"""Report progress summary for ancient_china_low_cultivation pack."""

import json
from collections import defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_PATH = (
    REPO_ROOT
    / "game"
    / "assets"
    / "packs"
    / "ancient_china_low_cultivation"
    / "ancient_china_low_cultivation_pack.json"
)


def main():
    with open(PACK_PATH, encoding="utf-8") as f:
        pack = json.load(f)

    stats = defaultdict(lambda: {"total": 0, "gen": 0})
    for a in pack.get("assets", []):
        dom = a.get("domain", "")
        sub = a.get("sub_domain", "")
        for v in a.get("variants", []):
            stats[(dom, sub)]["total"] += 1
            if v.get("status") == "generated":
                stats[(dom, sub)]["gen"] += 1

    total_variants = sum(s["total"] for s in stats.values())
    total_gen = sum(s["gen"] for s in stats.values())
    print(
        f"Overall Pack Progress: {total_gen}/{total_variants} ({total_gen / total_variants * 100:.2f}%)\n"
    )

    current_dom = None
    for (dom, sub), d in sorted(stats.items()):
        if dom != current_dom:
            current_dom = dom
            print(f"\n--- Domain: {dom} ---")
        pct = (d["gen"] / d["total"]) * 100 if d["total"] else 0
        status_flag = "[DONE]" if d["gen"] == d["total"] else f"[{d['gen']}/{d['total']}]"
        print(f"  {sub:45} {status_flag:>10} ({pct:5.1f}%)")


if __name__ == "__main__":
    main()
