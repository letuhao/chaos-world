# 0226 A shipped piece of content is reachable from a catalog entry, and the guard reads the catalog, never the declaration

- Status: Accepted
- Date: 2026-10-05
- Resolves: BL-0256
- Extends: ADR 0060 (a verification tool must measure what its output claims — this is the
  reachability half it deferred), ADR 0188 (a guard reads code lines only), ADR 0075
  (a rule that hard-fails beats a warning nobody reads)

## Context

BL-0256's finding is exact and its example is now stale: *"Today: 160 `DomainDef` `.tres`, 7
`LootEncounterDef` `.tres` … the rule that would have caught 153 of 160 domains."* There are
**160** encounters now, and 0 orphan domains (ADR 0223 measured it; `LootValidator` enforces
it). So the class is proven — it was caught once, the repair happened, and nothing keeps it
caught.

**The real defect is structural, not a missing rule.** `tools/data.py` grades **declarations**:
it reads a `.tres`, checks that its references resolve, and reports a partition. It cannot see
whether any **shipped surface** offers that row. ADR 0060 already drew that line for items —
`RUNTIME_ROUTES` (`data.py:329`) declares, per source kind, the script + verbs + call sites
that must exist, and `_route_live` verifies them. The `domain` family got the same treatment
(`data.py:362-369`) **but its `domain:` route delivers nothing**: `tools data audit` prints
`delivered per live route … domain 0`, and that `0` is correct — a `domain:` source is
delivered by a boss *drop*, not by the domain.

**Two concrete holes this ADR closes:**

1. **The domain templates are three files with no catalog.** `src/data/domains/templates/`
   holds `ember_grotto`, `flame_valley_depths`, `stormwrack_reach`. They ship — they are
   loaded by `DomainApi.templates()` and `_template()` (`api.gd:66-137`), and
   `DomainBoot.enter_domain` is bound in production (`app/domain_bridge.gd:73`). Yet nothing
   in `tools/` grades them at all, because `DATA_ROOT` is `game/data` and these live under
   `game/src/data` (stated deliberately at `domain/api.gd:28-31`). **A fourth template
   dropped in tomorrow is invisible.** A template is exactly the kind of shipped-but-unreachable
   row BL-0256 names: authored, audited by nobody, reachable only if a screen happens to offer
   its id.
2. **The 9 room defs have the same problem one level down.** `src/data/domains/rooms/*.tres`
   is the shared kit (ADR 0073). `ember_grotto` draws 5, `stormwrack_reach` draws 7,
   `flame_valley_depths` draws 6 — so a room def referenced by no `room_pool` is content no
   map can ever contain.

## Decision

**The rule: a shipped `.tres` is reachable iff (a) some shipped CATALOG lists it, and (b)
that catalog is itself on a shipped surface. A guard reads the catalog; a declaration is
never evidence of its own reachability.**

### Where it lives so it cannot be bypassed

**`tools data audit`, because that is the only gate every content change passes**
(`tools check` runs it; AGENTS.md:29). Three properties make it unbypassable:

- **It cannot be switched off per-content.** There is no "declared but unshipped" escape
  hatch, and adding one is what produced the present hole: `game/src/data/**` sits outside
  `DATA_ROOT`, so the audit's silence reads as "clean" when it means "never looked".
- **It fails, it does not warn.** An unreachable shipped row is `fail`. The class of defect
  is a player-facing dead end, and ADR 0075 already picked "hard-fails" over "a warning
  nobody reads".
- **It reads the catalog, never the `.tres`.** A row that asserts its own reachability is
  the failure mode ADR 0060 documented for `ItemDef.sources` and rejected.

### Three rules, one per content root

| Root | The catalog | Reachability means |
| --- | --- | --- |
| `src/data/domains/templates/` | `DomainApi.templates()` walks the dir; a template is reachable iff **the directory walk returns it** AND a shipped surface offers `template_id` | present in the walk **and** named by `app/domain_bridge.gd`'s bound action list |
| `src/data/domains/rooms/` | `DomainTemplateDef.room_pool` across every shipped template | some template's `room_pool` names it |
| `game/data/domains/` | `LootContent.encounter_for_domain` | already enforced in GDScript by `LootValidator.validate_domains`; **`tools data audit` must not duplicate it** — it cross-references the join and leaves the "is it offered" half to the GDScript half |

**The escalation ladder, in one place:** a room def with no `room_pool` is an authoring error
(cheap, local, fix the pin); a template with no room def is an authoring error; a template no
surface offers is a **content-retirement** decision, not a bug — that is the one that needs a
person, and it is reported as a named census rather than a red gate, so a planned-but-unshipped
wave does not paint the tree permanently red (ADR 0060:41-45's reasoning, applied).

### The part that cannot be a Python gate, and where it goes instead

`DomainApi.generate_and_enter` refusing a template is a **runtime** fact, so it is a GDScript
test, not `tools data audit` — and per BL-0256 clause 4 it must **walk the filesystem**, never
a hand-written list of three ids (a list of three is the same defect in a new costume, and it
rots the day a fourth template lands). It asserts, per template in the walk:

1. every shipped template loads and its `room_pool` is non-empty;
2. **the union of every template's `room_pool` covers every shipped `RoomDef`** (a room in no
   pool is content no map can contain);
3. `generate_and_enter(actor, template_id, seed)` returns `ok` on a **real** actor built
   through the real `ActorFactory` attach order — not a bare `Actor`;
4. **the gate can fail**: a template whose `min_rooms` exceeds any seed's leaf budget is
   refused with a named reason. A reachability guard that only ever passes is ADR 0188's
   "a guard that cannot fail".

## Consequences

- **The 3 templates and 9 rooms stop being ungraded.** A fourth of either is now a gate
  failure, which is the point.
- **Nothing under `game/data/domains/` moves** — the `domain` family keeps its schema, its
  `tools/arch/families.json:12` registration and its 160 rows (ADR 0223), so `tools data audit`
  stays green through this change.
- **`DATA_ROOT` does not change.** Adding `game/src/data` to the walk is the mistake to avoid:
  the audit's schemas (`data.py:147`) describe the *loot* corpus, and the template/room schema
  is a different shape with different ref rules. Two roots, two rule sets, one gate.
- **Trade-off rejected: extend `tools/data.py`'s family registry to cover `src/data`.**
  Rejected because `DomainTemplateDef` is a generated-graph description with a
  `pins`/`room_pool` contract that none of the nine existing schemas model; shoe-horning it in
  would grade it with item-shaped rules and produce false passes.
- **Trade-off rejected: gate runtime reachability now (ADR 0060's refused option).** Still
  refused, and for the same reason: a template the UI has not offered yet is a planned wave, not
  a defect. The **catalog** question (is it in the walk, is it in a pool) is decided and gated;
  the **surface** question (is it on screen) is reported.
- **What would change my mind:** if templates ever stop being generated content and start being
  hand-placed, the catalog becomes a scene and this rule needs the `.tscn`→map reader ADR 0221
  refused — in which case the reachability question moves into the generator's contract test
  rather than the audit.

## Migration order (for whoever takes it)

1. Extend `tools/data.py` with a **second root** (`SRC_DATA_ROOT = game/src/data`) and one
   rule: every `rooms/*.tres` is in some `templates/*.tres`' `room_pool`.
2. Add the template census as a **reported** section (not `fail`) naming every shipped
   `template_id` and whether a surface offers it.
3. Add the GDScript suite over the filesystem walk with all four assertions above.
4. `uv run python -m tools data audit` — expect the census to print; expect no new failures.
5. Only then flip the census to `fail` for the `room_pool` half, which should already be green.