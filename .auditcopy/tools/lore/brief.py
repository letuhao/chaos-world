"""Agent brief generation. This is where "search before creating" is enforced.

A brief is not a task description. It carries the current state of the domain:
what already exists, which shapes are already overused, what the tool says is
missing, and the hard constraints the authored game data imposes. An agent that
receives this cannot help but search, because the answer to "does something like
this already exist" is printed in front of it.

The brief is regenerated from the bible every run, so it cannot go stale the way a
hand-written task list does - which is the failure the program is most exposed to,
because a stale brief sends an agent to build a fifth sword sect that already
exists.
"""

from __future__ import annotations

import json
from collections import Counter
from datetime import date

from ..common import GAME_DIR, REPO_ROOT, ToolError, ok
from .audit import diversity, domain_coverage, gaps
from .model import Bible

BRIEF_DIR = REPO_ROOT / "build" / "lore-briefs"

# Authored constraints the bible must respect. These are read from the real
# resources rather than restated here, so a balance change cannot leave the briefs
# asserting a tier band that no longer exists.
TIER_SOURCE = GAME_DIR / "data" / "world" / "tiers"
LAW_SOURCE = GAME_DIR / "data" / "world" / "laws"

ACCEPTANCE = [
    "Every entity validates: namespaced id, slug type, lowercase-slug tags, summary under "
    "480 characters, registered status, provenance naming you.",
    "Every entity you create carries at least two edges, and every entity you reference "
    "already exists or is created in this same batch.",
    "No entity duplicates an existing one: run the search yourself and quote what you "
    "searched in your summary.",
    "Each new entity answers WHY it exists, not only what it is: name the cause, the "
    "resource, the pressure or the need.",
    "Nothing cosmetic. A new sect that is only a new sect is a failure; a new sect that "
    "exists because of a mine, a border or a defeat is the deliverable.",
    "You write only your own domain file and your own edge shard. Never edit another "
    "domain's file and never edit the registry.",
]


def authored_constraints() -> dict:
    """Read the authored cosmology so the briefs cannot contradict the game."""
    tiers: dict[str, dict] = {}
    if TIER_SOURCE.is_dir():
        for path in sorted(TIER_SOURCE.glob("*.tres")):
            text = path.read_text(encoding="utf-8", errors="replace")
            tiers[path.stem] = {
                "realm_min": _scalar(text, "realm_min"),
                "realm_max": _scalar(text, "realm_max"),
                "law_slots": _scalar(text, "law_slots"),
                "life_forms": _array(text, "available_life_forms"),
                "time_flow": [_scalar(text, "time_flow_min"), _scalar(text, "time_flow_max")],
                "size": [_scalar(text, "size_min"), _scalar(text, "size_max")],
            }
    laws: dict[str, dict] = {}
    if LAW_SOURCE.is_dir():
        for path in sorted(LAW_SOURCE.glob("*.tres")):
            text = path.read_text(encoding="utf-8", errors="replace")
            laws[path.stem] = {
                "group": _scalar(text, "group"),
                "range": [_scalar(text, "value_min"), _scalar(text, "value_max")],
                "description": _scalar(text, "description"),
            }
    return {"tiers": tiers, "laws": laws}


def _scalar(text: str, name: str):
    import re

    found = re.search(rf"^{name}\s*=\s*([^&\n]+)", text, re.M)
    return found.group(1).strip() if found else None


def _array(text: str, name: str) -> list[str]:
    import re

    found = re.search(rf"^{name}\s*=\s*Array\[StringName\]\(\[([^\]]*)\]\)", text, re.M)
    if not found:
        return []
    return re.findall(r'&"([^"]+)"', found.group(1))


def build_brief(bible: Bible, domain: str, *, batch: str, focus: str = "") -> str:
    spec = bible.registry.domains.get(domain)
    if spec is None:
        raise ToolError(
            f"unknown domain {domain!r}; try: {', '.join(sorted(bible.registry.domains))}"
        )
    entities = sorted(bible.by_domain().get(domain, []), key=lambda entity: entity.get("id", ""))
    type_counts = Counter(entity.get("type") for entity in entities)
    stats = diversity(bible).get(domain, {})
    domain_gaps = [issue for issue in gaps(bible) if domain in issue]
    constraints = authored_constraints()
    neighbours = _neighbour_summary(bible, domain)

    lines = [
        f"# Lore brief: {domain}",
        "",
        f"Batch `{batch}`. Generated {date.today().isoformat()} from the live bible.",
        f"Write ONLY `lore/bible/{domain}.jsonl` and `lore/edges/{batch}.jsonl`.",
        "",
        "## What this domain is for",
        "",
        spec["blurb"],
        "",
        f"Focus for this batch: {focus or 'whatever the gaps below say is missing.'}",
        "",
        "## ALREADY AUTHORED - search before you create",
        "",
        f"{len(entities)} entities exist in `{domain}`.",
    ]
    if entities:
        lines += ["", "| id | type | name | status |", "|---|---|---|---|"]
        for entity in entities[:120]:
            lines.append(
                f"| `{entity.get('id')}` | {entity.get('type')} | {entity.get('name')} "
                f"| {entity.get('status')} |"
            )
        if len(entities) > 120:
            lines.append(f"| ... and {len(entities) - 120} more; use `lore search` |")
    else:
        lines += ["", "NOTHING YET. This domain is empty - you are not at risk of duplicating."]

    lines += ["", "## Type distribution (do not add more of what already dominates)", ""]
    if type_counts:
        for kind, count in type_counts.most_common():
            lines.append(f"- `{kind}`: {count}")
    else:
        lines.append("- none yet")
    lines += [
        "",
        f"Tag entropy {stats.get('tag_entropy', 0):.2f}, type entropy "
        f"{stats.get('type_entropy', 0):.2f}, average degree "
        f"{stats.get('edge_density', 0):.1f}."
        + (
            "  **This domain is flagged MONOCULTURAL - add structural difference, not names.**"
            if stats.get("monocultural")
            else ""
        ),
    ]
    # `lore-gap` sits on every stub BY CONSTRUCTION, so naming it as overused
    # would tell each agent to avoid the one tag meaning "this needs writing" -
    # steering authors away from the entities that most need them.
    real_overused = [tag for tag, _ in stats.get("overused_tags", []) if tag != "lore-gap"]
    if real_overused:
        lines.append("Overused tags to avoid: " + ", ".join(f"`{tag}`" for tag in real_overused))

    lines += ["", "## What this domain is already connected to", ""]
    if neighbours:
        for other_domain, relations in sorted(neighbours.items()):
            lines.append(f"- `{other_domain}`: {', '.join(relations)}")
    else:
        lines.append("- nothing. You are starting an island, so expect to link outward hard.")

    lines += ["", "## GAPS the tool has found for this domain", ""]
    lines += [f"- {issue}" for issue in domain_gaps] or ["- none detected"]

    lines += [
        "",
        "## HARD CONSTRAINTS from authored game data",
        "",
        "These are read from `game/data/world/`. A world that contradicts them is wrong here",
        "no matter how good it reads, because the game already ships them.",
        "",
        "| tier | realms | law slots | life forms | time flow | size |",
        "|---|---|---|---|---|---|",
    ]
    for tier, data in sorted(constraints["tiers"].items()):
        lines.append(
            f"| {tier} | {data['realm_min']}-{data['realm_max']} | {data['law_slots']} | "
            f"{', '.join(data['life_forms']) or '-'} | {data['time_flow']} | {data['size']} |"
        )
    lines += ["", "| law | group | range | governs |", "|---|---|---|---|"]
    for law, data in sorted(constraints["laws"].items()):
        lines.append(f"| {law} | {data['group']} | {data['range']} | {data['description']} |")
    lines += [
        "",
        "Note the shape of it: there are 6 laws but the mortal tier holds only 3 slots, and",
        "size grows tenfold per tier while time flow grows faster. A world's law composition",
        "is therefore a CONSTRAINT on what can be cultivated there, not decoration. Use it.",
        "",
        "## Hard prohibitions",
        "",
        "- No sexual content, ever. Succubus, fertility and dual-cultivation are mechanical",
        "  concepts only; keep every description clinical and nonsexual.",
        "- English only.",
        "- Do not copy protected characters, terminology, factions, settings or plots from any",
        "  existing work. Extract abstract patterns, never names.",
        "- Do not hand-edit `lore/registry.json`.",
        "- Do not write to another agent's domain file.",
        "",
        "## Schema",
        "",
        "One JSON object per line in your domain file:",
        "",
        "```json",
        json.dumps(
            {
                "id": f"{domain}.example_slug",
                "domain": domain,
                "type": "lower-case-slug",
                "name": "Display Name",
                "summary": "Under 480 characters. What it is AND why it exists.",
                "tags": ["slug", "tags"],
                "status": "active",
                "provenance": {
                    "author": batch,
                    "created": date.today().isoformat(),
                    "basis": ["abstract-pattern:whatever you drew on"],
                },
                "attributes": {"key": "free-form, domain-specific"},
                "lore_ref": f"lore/prose/{domain}/example_slug.md",
            },
            indent=2,
        ),
        "```",
        "",
        "One JSON object per line in your edge shard:",
        "",
        "```json",
        json.dumps(
            {
                "from": f"{domain}.example_slug",
                "rel": "located_in",
                "to": "geography.somewhere",
                "status": "active",
                "since": "history.some_event",
                "note": "why this link exists",
            },
            indent=2,
        ),
        "```",
        "",
        "Registered relations: "
        + ", ".join(f"`{name}`" for name in sorted(bible.registry.relations)),
        "",
        "## Acceptance criteria",
        "",
        *(f"{index}. {rule}" for index, rule in enumerate(ACCEPTANCE, 1)),
        "",
        "## Before you finish",
        "",
        "```",
        "uv run python -m tools lore validate",
        f"uv run python -m tools lore gaps --domain {domain}",
        "```",
        "",
        "`validate` must report nothing for your batch. If it does, fix it; do not explain it.",
    ]
    return "\n".join(lines)


def _neighbour_summary(bible: Bible, domain: str) -> dict[str, set[str]]:
    """Which other domains this one already touches, and by which relation."""
    found: dict[str, set[str]] = {}
    for edge in bible.edges:
        source_domain = bible.entities.get(edge.source, {}).get("domain")
        target_domain = bible.entities.get(edge.target, {}).get("domain")
        if source_domain == domain and target_domain and target_domain != domain:
            found.setdefault(target_domain, set()).add(edge.rel)
        elif target_domain == domain and source_domain and source_domain != domain:
            found.setdefault(source_domain, set()).add(bible.registry.inverse(edge.rel))
    return found


def write_brief(bible: Bible, domain: str, *, batch: str, focus: str = "") -> str:
    text = build_brief(bible, domain, batch=batch, focus=focus)
    BRIEF_DIR.mkdir(parents=True, exist_ok=True)
    path = BRIEF_DIR / f"{domain}-{batch}.md"
    path.write_text(text + "\n", encoding="utf-8")
    ok(f"wrote brief: {path.relative_to(REPO_ROOT).as_posix()}")
    return text


def coverage_table(bible: Bible) -> list[dict]:
    return [{"domain": domain, **stats} for domain, stats in sorted(domain_coverage(bible).items())]
