"""READ-ONLY: reconcile the blocking-signature counts with the delivered-item edges,
and identify the single item still blocked when BOTH levers are pulled.
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools import data as D  # noqa: E402


def main() -> None:
    records, _ = D._load(D.DATA_ROOT)
    items = records["item"]
    recipes = records["recipe"]
    bosses = records["boss"]
    authored = D._authored_boss_drops(records)
    craft_live = D._route_live(D.RUNTIME_ROUTES.get("craft"))
    hosted, entered, drops, granted = (
        D._hosted_bosses(), D._entered_domains(),
        D._boss_drops(bosses, authored), D._granted_ids(),
    )

    def measure(shipped):
        roots, blocked = set(), {}
        for iid, item in items.items():
            un, ok = [], False
            for s in item["arrays"].get("sources", []):
                k = s.partition(":")[0]
                if k == "craft":
                    continue
                if k in shipped or (k == "boss" and s.partition(":")[2] in hosted) \
                   or (k == "starter" and iid in granted) \
                   or (k == "domain" and any(iid in drops.get(b, set())
                                             for b in entered.get(s.partition(":")[2], set()))):
                    ok = True
                    break
                un.append(k)
            (roots.add(iid) if ok else blocked.__setitem__(iid, tuple(sorted(set(un)))))
        reach = D._close_recipes(roots, recipes, craft_live)
        for i in reach - set(roots):
            blocked.pop(i, None)
        ins = {}
        for r in recipes.values():
            for o in r["arrays"].get("outputs", []):
                ks = set()
                for i in r["arrays"].get("inputs", []):
                    ks.update(blocked.get(i, ()))
                if ks:
                    ins.setdefault(o, set()).update(ks)
        for i, ks in ins.items():
            if i not in reach:
                blocked[i] = tuple(sorted(ks))
        return reach, blocked

    base, bb = measure(set())
    both, bt = measure({"quest", "gather"})
    out = {
        "base": len(base), "both": len(both),
        "edge_both": len(both) - len(base),
        "still_blocked_when_both_pulled": sorted(bt.keys()),
        "still_blocked_detail": {
            i: {
                "sources": items[i]["arrays"].get("sources", []),
                "category": items[i]["scalars"].get("category"),
                "blocked_by": bt[i],
            } for i in sorted(bt)
        },
    }

    # --- the exact blocking-signature partition, as the audit prints it ---
    out["audit_style_signatures_today"] = {
        "|".join(k) or "(no unshipped kind)": v
        for k, v in Counter(bb.values()).most_common()
    }

    # --- "declares ONLY gather" -- several readings, stated separately ---
    unshipped = {"gather", "quest"}
    only_g_never_unshipped_elsewhere = sum(
        1 for it in items.values()
        if {s.partition(":")[0] for s in it["arrays"].get("sources", [])} == {"gather"}
    )
    only_g_among_unshipped = sum(
        1 for i in bb
        if {k for k in bb[i]} == {"gather"}
    )
    only_g_declared_and_blocked = sum(
        1 for i in bb
        if "gather" in {s.partition(":")[0] for s in items[i]["arrays"].get("sources", [])}
        and not ({s.partition(":")[0] for s in items[i]["arrays"].get("sources", [])} & {"quest"})
    )
    out["gather_only_readings"] = {
        "declares gather and NOTHING else (whole corpus)": only_g_never_unshipped_elsewhere,
        "blocked, gather is its only UNSHIPPED kind": only_g_among_unshipped,
        "blocked, declares gather and not quest": only_g_declared_and_blocked,
    }
    only_q_among_unshipped = sum(1 for i in bb if {k for k in bb[i]} == {"quest"})
    out["quest_only_readings"] = {
        "blocked, quest is its only UNSHIPPED kind": only_q_among_unshipped,
    }

    # --- how much of each lever's edge is DIRECT vs UNLOCKED-BY-RECIPE-CLOSURE ---
    q, _ = measure({"quest"})
    g, _ = measure({"gather"})
    out["edge_decomposition"] = {
        "quest_direct_items_that_declare_it": len(
            [i for i in items if "quest" in {s.partition(":")[0] for s in items[i]["arrays"].get("sources", [])}
             and i in q and i not in base]
        ),
        "gather_direct_items_that_declare_it": len(
            [i for i in items if "gather" in {s.partition(":")[0] for s in items[i]["arrays"].get("sources", [])}
             and i in g and i not in base]
        ),
        "quest_edge_total": len(q) - len(base),
        "gather_edge_total": len(g) - len(base),
    }

    # --- the dangling-ref sub-case: what a route keyed on quest:<id> would free ---
    refs = set()
    for it in items.values():
        for s in it["arrays"].get("sources", []):
            if s.partition(":")[0] == "quest" and s.partition(":")[2]:
                refs.add(s.partition(":")[2])
    out["distinct_dangling_quest_refs"] = len(refs)
    authored_q = {p.stem for p in D.QUEST_DIR.glob("*.tres")} if D.QUEST_DIR.is_dir() else set()
    out["authored_quest_stems"] = sorted(authored_q)
    out["dangling_refs_that_resolve"] = sorted(refs & authored_q)

    print(json.dumps(out, indent=1, default=str, ensure_ascii=False))


if __name__ == "__main__":
    main()
