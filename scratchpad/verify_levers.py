"""READ-ONLY verification of the gather/quest levers.

Uses tools/data.py's own loader and its own recipe closure, but re-implements the
root membership so a hypothetical lever can be simulated WITHOUT editing the repo.

Why re-implement rather than inject a Route: tools/data.py:1208-1217 documents
that a Route entry alone cannot move the count — `_runtime_roots` has a hard-coded
branch per kind and anything else falls through to `unshipped`. So a "shipped"
lever is modelled by treating the kind as delivering unconditionally (its ref is
either forbidden-by-vocabulary `gather`, or optional-and-dangling `quest`).

Never writes. Never imports Godot. Only reads .tres files under game/data.
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]  # scratchpad/ -> repo root
sys.path.insert(0, str(ROOT))

from tools import data as D  # noqa: E402


def roots_with(items: dict, shipped_kinds: set[str]) -> set[str]:
    """Items delivered outright when `shipped_kinds` deliver unconditionally.

    Mirrors tools/data.py:1225-1253 for the three existing kinds and adds the
    hypothetical ones. `craft` is still skipped: a recipe output is never a root.
    """
    hosted = D._hosted_bosses()
    domains = D._entered_domains()
    drops = D._boss_drops(items and {}, D._authored_boss_drops({}))  # placeholder, replaced
    granted = D._granted_ids()
    return hosted, domains, drops, granted


def main() -> None:
    records, malformed = D._load(D.DATA_ROOT)
    items = records.get("item", {})
    recipes = records.get("recipe", {})
    bosses = records.get("boss", {})
    authored = D._authored_boss_drops(records)

    craft_live = D._route_live(D.RUNTIME_ROUTES.get("craft"))

    hosted = D._hosted_bosses()
    entered = D._entered_domains()
    drops = D._boss_drops(bosses, authored)
    granted = D._granted_ids()

    def measure(shipped: set[str]) -> tuple[set[str], dict[str, tuple[str, ...]]]:
        roots: set[str] = set()
        blocked: dict[str, tuple[str, ...]] = {}
        for item_id, item in items.items():
            unshipped: list[str] = []
            delivered = False
            for source in item["arrays"].get("sources", []):
                kind = source.partition(":")[0]
                if kind == "craft":
                    continue
                if kind in shipped:
                    delivered = True
                    break
                if kind == "boss" and source.partition(":")[2] in hosted:
                    delivered = True
                    break
                if kind == "starter" and item_id in granted:
                    delivered = True
                    break
                if kind == "domain" and any(
                    item_id in drops.get(b, set()) for b in entered.get(source.partition(":")[2], set())
                ):
                    delivered = True
                    break
                unshipped.append(kind)
            if delivered:
                roots.add(item_id)
            else:
                blocked[item_id] = tuple(sorted(set(unshipped)))
        reachable = D._close_recipes(roots, recipes, craft_live)
        for item_id in reachable - set(roots):
            blocked.pop(item_id, None)
        # attribute craft-only outputs to their inputs' blocking kinds, as the repo does
        inputs: dict[str, set[str]] = {}
        for recipe in recipes.values():
            for output in recipe["arrays"].get("outputs", []):
                kinds: set[str] = set()
                for item_id in recipe["arrays"].get("inputs", []):
                    kinds.update(blocked.get(item_id, ()))
                if kinds:
                    inputs.setdefault(output, set()).update(kinds)
        for item_id, kinds in inputs.items():
            if item_id not in reachable:
                blocked[item_id] = tuple(sorted(kinds))
        return reachable, blocked

    base, base_blocked = measure(set())
    q_only, q_blocked = measure({"quest"})
    g_only, g_blocked = measure({"gather"})
    both, both_blocked = measure({"quest", "gather"})

    graph = D._obtainable(items, recipes)

    out: dict = {
        "items_total": len(items),
        "graph_obtainable": len(graph),
        "malformed": len(malformed),
        "craft_route_live": craft_live,
        "DELIVERABLE_TODAY": len(base),
        "BLOCKED_TODAY": len(base_blocked),
        "blocked_signatures_today": {
            "|".join(k): v for k, v in Counter(base_blocked.values()).most_common()
        },
        "LEVER_quest_only": len(q_only),
        "LEVER_quest_edge": len(q_only) - len(base),
        "LEVER_gather_only": len(g_only),
        "LEVER_gather_edge": len(g_only) - len(base),
        "LEVER_both": len(both),
        "LEVER_both_edge": len(both) - len(base),
        "still_blocked_with_both": len(both_blocked),
        "still_blocked_sigs_with_both": {
            "|".join(k): v for k, v in Counter(both_blocked.values()).most_common()
        },
        "unreachable_inputs_remaining_with_both": len(both_blocked),
    }

    # declared-kind census over the WHOLE corpus
    decl = Counter()
    for item in items.values():
        for s in item["arrays"].get("sources", []):
            decl[s.partition(":")[0]] += 1
    out["declared_kind_counts_whole_corpus"] = dict(decl.most_common())

    # declared-kind census over ONLY the blocked set (what actually blocks)
    bdecl = Counter()
    for item_id in base_blocked:
        for s in items[item_id]["arrays"].get("sources", []):
            bdecl[s.partition(":")[0]] += 1
    out["declared_kind_counts_blocked_only"] = dict(bdecl.most_common())

    # how many blocked items declare gather ONLY / quest ONLY / both / neither
    go = qo = gq = none = 0
    for item_id in base_blocked:
        kinds = {s.partition(":")[0] for s in items[item_id]["arrays"].get("sources", [])}
        has_g, has_q = "gather" in kinds, "quest" in kinds
        if has_g and has_q:
            gq += 1
        elif has_g:
            go += 1
        elif has_q:
            qo += 1
        else:
            none += 1
    out["blocked_by_signature_raw"] = {
        "gather_only": go,
        "quest_only": qo,
        "gather_and_quest": gq,
        "no_gather_no_quest": none,
    }

    # --- SAMPLE 10 gather items: description + category -----------------------
    gather_ids = sorted(
        i for i, it in items.items()
        if any(s.partition(":")[0] == "gather" for s in it["arrays"].get("sources", []))
    )
    step = max(1, len(gather_ids) // 10)
    out["gather_declaring_total"] = len(gather_ids)
    out["gather_category_census"] = dict(
        Counter(str(items[i]["scalars"].get("category", "?")).strip() for i in gather_ids).most_common(20)
    )
    out["gather_SAMPLE_10"] = [
        {
            "id": i,
            "category": items[i]["scalars"].get("category", ""),
            "description": items[i]["scalars"].get("description", "")[:200],
            "sources": items[i]["arrays"].get("sources", []),
            "blocked": i in base_blocked,
        }
        for i in gather_ids[::step][:10]
    ]

    # same for quest
    quest_ids = sorted(
        i for i, it in items.items()
        if any(s.partition(":")[0] == "quest" for s in it["arrays"].get("sources", []))
    )
    step = max(1, len(quest_ids) // 10)
    out["quest_declaring_total"] = len(quest_ids)
    out["quest_category_census"] = dict(
        Counter(str(items[i]["scalars"].get("category", "?")).strip() for i in quest_ids).most_common(20)
    )
    out["quest_SAMPLE_10"] = [
        {
            "id": i,
            "category": items[i]["scalars"].get("category", ""),
            "description": items[i]["scalars"].get("description", "")[:200],
            "sources": items[i]["arrays"].get("sources", []),
        }
        for i in quest_ids[::step][:10]
    ]

    # quest ref shape: dangling vs bare
    with_ref = with_bare = 0
    for i in quest_ids:
        for s in items[i]["arrays"].get("sources", []):
            if s.partition(":")[0] == "quest":
                if s.partition(":")[2]:
                    with_ref += 1
                else:
                    with_bare += 1
    out["quest_ref_split"] = {"with_dangling_ref": with_ref, "bare": with_bare}

    print(json.dumps(out, indent=1, default=str))


if __name__ == "__main__":
    main()
