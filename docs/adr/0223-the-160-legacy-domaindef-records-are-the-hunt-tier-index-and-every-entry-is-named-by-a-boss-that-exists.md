# 0223 The 160 legacy `DomainDef` records are the hunt index, and every one is named by a boss that exists

- Status: Accepted
- Date: 2026-10-05
- Resolves: BL-0474 (the DECISION OWED), BL-0256's premise
- Corrects: the premise of BL-0474 and of ADR 0072:25 — the records are NOT orphaned
- Does not touch: `tools/data.py`, `tools/arch/families.json`, `game/data/**` — nothing under `game/` changes

## Context

BL-0474 asserts: *"game/data/domains/*.tres x160 … Grep for DomainDef in `game/src` returns
only PROSE in api.gd:30, loot_validator.gd:54, loot_content.gd:306 — zero code reads one, and
there is no adapter to DomainMap … Decide: adapt, migrate, or delete."* That grep is
**correct and the conclusion is wrong.** It proves the *class name* is never spelled in
production code — which is by design, because `loot` reads these records **without naming
their resource type**, precisely so it declares no dependency on `world`
(`loot_content.gd:19-22`).

### What the records actually are

`DomainDef` is three fields — `id`, `display_name`, `boss_ids`
(`modules/world/domain_def.gd:6-8`) — and it is the **index of the hunt**. A `BossDef`
carries `domain_id`; a `DomainDef` carries the roster of bosses inside one place. Together
they are the boss→place→boss join that makes "which fight happens where" a single query.

### Measured, on today's tree

| Fact | Count | How measured |
| --- | --- | --- |
| `DomainDef` `.tres` under `game/data/domains/` | 160 | `dir /b` |
| `LootEncounterDef` `.tres` under `game/data/loot/encounters/` | 160 | `dir /b` |
| Distinct `domain_id` across all encounters | 160 | regex over `^domain_id = &"…"` |
| Domains with **no** encounter naming them | **0** | set difference |
| Domains whose `boss_ids` is **empty** | **0** | regex over the `boss_ids` array |

`LootValidator.validate_domains` (`loot_validator.gd:116-131`) exists to keep this at zero,
and its comment records the history: *"That was true of 128 domains when BL-0338 was filed;
they all carry encounters now."* The repair already happened. **BL-0474 is describing a
state that was fixed before the finding was written.**

### The runtime path, named

- `LootApi.enter_domain` (`modules/loot/api.gd:68-89`) → `encounter_for_domain` →
  `LootEncounterDef` → its `tiers` → `LootState.enter`. **This is the production verb**, bound
  by `app/item_workbench_app.gd:574` and driven from `ui/screens/loot_encounter.gd`.
- The `DomainDef` is the **back-reference the validator uses** (`loot_validator.gd:436-460`):
  an encounter whose domain file is missing, whose `id` disagrees, or which lists a boss the
  domain does not, is refused **by name**. That is `LootValidator` refusing to let the
  encounter and the index drift apart — the records are the reference side of a checked join.
- `tools/data.py` reads them as a first-class family: `_DEFCLASS_TO_SCHEMA` (`data.py:206`),
  `_DEFCLASS_TO_TYPE` (`data.py:217`), schema `{"id","boss_ids"}` (`data.py:147`), and the
  `boss` route's membership rule ("hosted_boss") at `data.py:1451-1489`. `tools/arch/families.json:12`
  declares the family to the arch gate.

## Decision

**Keep all 160, un-renamed, in place. Rename their ROLE, not their schema: they are the
`HuntIndex`, and the disposition is "adopted", not "migrated" and not "deleted".**

- **A `DomainDef` is not a place and never was.** ADR 0072 made a domain a `DomainMap`; ADR
  0221 makes every domain generated. What survives is a different fact: *this roster of bosses
  is what you fight in this hunt.* That is a join table over the combat catalogue, not a
  half-built spatial format. It is legitimate content at its own scale.
- **The 3-field schema is final.** Adding `extent`, `rooms` or a `template_id` to it is
  refused: it would make the join table grow a second job. The spatial half lives in
  `DomainTemplateDef` (`src/data/domains/templates/`) and the boss half in `BossDef`.
- **`DomainDef` is renamed in a later, separate change** (the `class_name` is global namespace
  and every `.tres` names it in its header, so it is a 160-file edit with a real blast radius).
  That rename is a *clarity* change, not a disposition, and it is explicitly **out of scope
  here** so this ADR can land without touching `game/`.
- **`DomainApi.generate_and_enter` is the only entry into a *place*; `LootApi.enter_domain` is
  the only entry into a *fight*.** Two verbs, two scales, and a player crosses from one to the
  other when a map's `core` room hands off to a boss encounter. **Nothing is lost between
  them today**; a hunt *is* a place you fight in, so a domain template is what a hunt
  realizes and a `DomainDef` is what it is looked up by.

## Consequences

- **BL-0474 closes as DECIDED, and its premise is corrected in the record.** 160 rows are
  live, referenced, validated and audited content. "Nobody decided" was the failure; the
  decision is *keep*, on the evidence.
- **`tools data audit` is unaffected and must stay so.** The `domain` family keeps its
  schema entry and its type entry; deleting the `.tres` files would make `data.py:823`
  (`domain_id not in domains`) fail for 160 bosses, and deleting the family's registration
  would trip the "undeclared content family" hard error (`data.py:774`). Migration path =
  **none needed**, which is the strongest form of "does not break `tools data audit`".
- **ADR 0072:25 is now known to be half-wrong.** "All 160 authored `.tres` stay valid and
  audit-clean" was true and under-specified: they were never inert, so no migration was owed
  in the first place. This ADR supplies the reason ADR 0072 omitted.
- **DEF-0065's premise is stale** (`"BossDef/DomainDef data exists but no spawning or loot
  rolls"`): `LootApi.enter_domain`/`strike` ship and are bound in `app/`. Not edited here —
  that is `docs/deferred.jsonl`, shared.
- **Trade-off rejected: migrate the 160 into `DomainTemplateDef`.** Rejected: it would
  fabricate spatial content. 160 identical one-room maps with a synthetic extent and a
  synthetic `room_pool` is *worse* than the join table it replaced — it makes the corpus look
  like authored levels while adding no level design, and it would make `tools data audit`
  grade 160 templates it cannot cross-reference.
- **Trade-off rejected: delete the 160 and move `boss_ids` onto the encounter.** Rejected
  because it deletes the *second* side of a checked join (`loot_validator.gd:444-460`
  verifies the encounter's bosses against the domain's roster), and because 331 bosses'
  `domain_id` back-references would then have no index at all — `data.py:823` would report
  every one of them as "not a defined domain".
- **What would change my mind:** if the `domain` hunt scale is retired from the design (bosses
  fought outside any place, as ADR 0176's headless exchange already permits), the index has
  no referent and deletion becomes correct. Trigger to watch: `BossDef.domain_id` going
  optional. Until then the index is the thing that names where a fight is.

## Deferred by this ADR (named, not hidden)

1. The `DomainDef` → `HuntIndexDef` rename (160-file header edit + every test that spells the
   class: `test_world_defs.gd:20`, `test_unique_routes.gd:295,359`, `test_body_cultivation_
   acquisition.gd:141`). Pure rename, no behaviour change, **not done here** because it
   modifies `game/`.
2. The **hunt ↔ map handoff**: which `DomainMap` a given `DomainDef.id` realizes. Today the
   two are independent and both are reachable; joining them is a gameplay decision (BL-0394
   closed the enter-side chain, not this), and it is the one genuinely open question this ADR
   leaves.