# 0278 A new organization kind is a .tres drop: one generic def in core, automatic discovery, and no code

- Status: Proposed
- Date: 2026-10-06
- Depends on: ADR 0064 (position and standing never derive), ADR 0066 (one shared shape
  in `core`, never a per-module copy), ADR 0083 (three tiers, one vocabulary, not
  nested), ADR 0084 (recognition, access and transmission, never power), ADR 0085 (a
  claim confers no yield and no bonus), ADR 0184 (mods register through a locked
  context), ADR 0271 (a kind is registered, not nested; the `institutions` family)
- Amends: nothing. Supersedes nothing.
- Resolves: the CONTENT half of ADR 0271 §5 (the family is named; its def type and its
  discovery are decided here). The WIRING (`families.json`, `_wire_content_roots`,
  mod overlay roots) stays with the later slice.

## Context

ADR 0271 measured that a kind could not be added without editing a module, and named
the mod content family `institutions` — one directory, each `.tres` declares its
`kind`, the catalog dispatches on it — as a DECISION with the wiring deferred. It left
two questions this slice answers:

1. **What does a non-sect `.tres` look like** when `SectDef`, `NationDef` and `ClanDef`
   have three different shapes and three modules to read them?
2. **Does the generic `found` actually work for a kind that has no module** — or is it
   a `SectDef` refactor wearing a generic name?

## Decision

**1. ONE generic authored type: `core/institution_def.gd` + `core/institution_position_def.gd`,
both `Resource` and both in `core/`.** `core/` because `RESOURCE_HOME_UNITS` is
`("core", "modules")` and `core` is a LAYER, so the facade rule never applied and the
shared type creates zero new edges. Fields taken because a `found` genuinely needs
them or an author genuinely wants them: identity, `kind`, `capabilities`, `positions`,
`top_position_id`, `standing_cap`, `founder_standing`, `founding_cost`,
`member_duty_per_period`, `territory_ids`, `tags`; on a position, `capacity`,
`duties`, `authorities`, `duty_per_period`, `patronage_per_period` — the last two as a
PAIR, because an office that only takes is a debt collector and one that only gives is
a faucet.

**Deliberately absent, each because shipping it would be a field nothing reads:**
`doctrine_id`, `min_purity` (transmission is the `teaches` CAPABILITY and a doctrine is
`sect` content); `act_priority` (an `InstitutionBudget` rung); `claim` (a nation's own
earned standing, not a member's); `sect_ids`, `rival_ids`, `ranks`/`standing_bands`
(one module's edges, or a LADDER — ADR 0064/0083 keep a position an authored id);
`succession_*`, `standing_floor`, `teach_tax`; and `standing_percent_stats`, which is
the sharpest omission — ADR 0084 makes the allowlist the only stat surface an
institution has, but the code that consumes it is `SectProjection`, inside `sect`, so a
generic allowlist would be an author writing numbers that go nowhere. A guild position
recognises **nothing**, which `standing_percent` already answers as `0.0`.

**2. `kind` is an `@export`ed field and that field is the ONLY place it is written.**
Derived from the def type fails outright — `core` ships one type for every kind, so a
guild and a farmers' circle would be one kind sharing one capability set. Read from
the registry row makes a def's meaning depend on read order, so a catalog that has not
booted has no answer for a shipped `.tres` at all. The field travels with the resource:
`load()` yields a def and `def.kind` already answers. **The registry row is a CHECK,
never a second source** — `def.check(registry)` refuses an unregistered kind with
`unknown_kind` and never loads it as a default.

**3. `capabilities` are authored on the def, and every def of one kind must AGREE.**
Capabilities belong to a KIND, so per-organization authoring would let two `.tres` of
one kind disagree about one fact. `InstitutionBoot.register_def` registers the FIRST
def of a kind, folds an identical repeat, and refuses a disagreement as
`capability_disagreement`. `def.check` additionally refuses `offices_not_declared`
(positions under a kind with no `has_offices`) and `territory_not_declared` (claims
under a kind with no `has_territory`) — the two authoring slips that would otherwise be
silent.

**4. DISCOVERY IS AUTOMATIC.** `InstitutionBoot.install()` walks one directory through
`core/ContentScan` and registers whatever it finds. It names **no kind, no
organization and no def path**, and both the registry row's `def_type` label and its
`def_script` are read OFF the loaded resource — so a modder's own def class registers
under its own name with no edit to any code. The enumerated alternative is exactly the
wiring ADR 0271 calls the problem. A refused file is recorded in the returned report
and announced with a `push_warning`, never skipped silently.

**5. The three shipped organizations exercise three DIFFERENT capability sets**, so
each reaches a different branch of the generic `found`:

| `.tres` | `kind` | capabilities | what it proves |
|---|---|---|---|
| `lantern_exchange.tres` | `trading_guild` | `has_offices` | offices + a scarce seat + a capped room + an unbounded floor |
| `grey_horizon_hunt.tres` | `hunting_guild` | `has_offices`, `has_territory` | a claim that confers nothing (ADR 0085) and is charged again on a split |
| `torrent_field_circle.tres` | `farmers_circle` | `has_territory` | NO offices: a founder holds thick standing in NO position (ADR 0064) |

None claims `is_born_to` — a guild you join is not a family you are born into — and
none claims `teaches`, because **the generic slice cannot grant transmission**: a
doctrine and its fit floor are `sect` content, so a `teaches` guild would get an empty
fit axis and a hollow flag. Founding costs are 2400 / 1100 / 700 and recognition caps
150 / 100 / 60, so worth is priced in effort in both directions.

## Consequences

- **Generic `found` WORKS for a guild — measured, not asserted.**
  `test_institution_def.gd` founds the Exchange off its `.tres` alone and gets the
  authored charge, the founder seated in `first_ledger`, the roster of ids, four
  treasury lines, the membership line and the office's own line. **What remains
  sect-specific:** succession (`SectSuccession` walks it, and `succession_method` was
  dropped rather than duplicated), the stat allowlist and its projection
  (`SectProjection`), the fit axis and doctrine floors, and admission gates. A guild
  that teaches or that projects recognition is **not authorable yet** — see below.
- **The generic position drops the seat/room WORD.** `has_room` answers "is there
  room" and never "what shall I tell the player"; `seat_occupied` / `capacity_full`
  belong beside the gate that emits them and are removed by the sect migration, not
  restated here.
- **`InstitutionRegistry.capabilities_of` and `kinds` do NOT order interned ids by
  string value** — measured: a def declaring `[has_offices, has_territory]` reads back
  `[has_territory, has_offices]`, despite the docstring claiming a string sort. The
  boot's agreement check is therefore a SET comparison, and a test that had compared
  positionally refused the second `.tres` a modder dropped. Not fixed here: that file
  is committed foundation outside this slice's claim.
- **`install()` ships with ZERO production callers** — `app/item_workbench_body.gd` has
  another session's exclusive ownership. One line beside `EconomyBoot.install(a)`
  closes it. Recorded in `docs/deferred.jsonl`, not hidden.
- **A mod OVERLAY root is still unwired.** `install()` walks the shipped directory
  only; `_wire_content_roots` has no `institutions` arm, so a mod's root is skipped and
  announced. That is DEF-0326 plus the later wiring slice.
- **A registry is process state and is never serialized** (ADR 0271): a save carries
  `kind` as a plain `String` and nothing else.
