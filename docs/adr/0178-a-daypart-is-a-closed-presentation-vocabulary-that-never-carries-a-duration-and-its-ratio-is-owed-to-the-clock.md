# 0178 A daypart is a closed presentation vocabulary that never carries a duration, and its ratio is owed to the clock

- Status: Proposed
- Date: 2026-10-04
- Depends on: ADR 0173 (the clock is one single source of truth; `core/time_ladder.gd` is the named home for time ratios, and it is **Proposed**, not written), ADR 0167 (a period is the unit), ADR 0175, ADR 0177
- Guard reused: `_no_stat_numbers` (`tools/unique_characters.py:390-426`)

## Context

A daily-life bundle wants four images per character and a schedule binding them to a place. The time key is the only missing piece, and it is missing more completely than it looks.

- **`period` is the only time unit in the game.** `PERIOD_SECONDS := 120.0` (`app/world_pulse.gd:88`) is "the ONE authored statement of how long a period is". `grep` for `age_years|elapsed_days|born_year|day_index|period_index|day_count|days_elapsed` over `game/src` returns **zero**. There is no day, month, season or year counter, and none is persisted.
- **Every ADRs propose to add one, and none has.** ADR 0167, 0169 and 0170 are all `Status: Proposed`; 0168 is `Superseded by ADR 0173`; 0173 is `Proposed`. The file they name, `core/time_ladder.gd`, **does not exist** — nor do `core/reconcile_stamp.gd` or `core/realm_lifespan_table.gd`. Verified absent.
- **`phase` is already taken.** `core/tribulation.gd:89` `var phase: StringName`, vocabulary `WARNING/TRIAL/CLIMAX/AFTERMATH`, rendered as a `"phase"` key at `ui/screens/tribulation_screen.gd:54` and `ui/panels/tribulation_panel.gd:91,137`. It is in the global `class_name` namespace.
- **A duration is a balance surface.** `_no_stat_numbers` exists because a number in a reference document is invisible to every gate that matters. A schedule row saying "2 periods" would be exactly that, reached by editing a JSONL nobody validates.
- **A second clock already exists un-governed.** `modules/save/save_clock.gd:34` declares its own `PERIOD_SECONDS := 120.0` and cites "ADR 0171" for the pending migration — but ADR 0171 is about `RATE_STATS` and never mentions it. ADR 0173 is the ADR that moves it, and 0173 is Proposed.
- **Time skipping makes a phase lossy.** `MAX_PERIODS_PER_PULL := 8` (`:95`) clamps **per call** and **drops the surplus** (`:206-210`), so a season-scale action is `8 + 8`. A daypart read after a jump is arithmetically right and temporally discontinuous.
- **Nothing in the bible grounds a time of day.** Across all **1155** lore entities, `dawn` 0, `dusk` 0, `nightfall` 0, `midday` 0, `each day` 0, `every day` 0. The 52 records matching `schedule` are all succession or tide scheduling, not daily life. **One** record in the whole bible is an occupation (`economy.spoil_hauler`).

## Decision

**A daypart is a closed presentation axis. It never carries a duration, and its ratio is owed to the clock.**

- **`daypart` is exactly `dawn | day | dusk | night`,** declared as a closed set beside `SHOT_KINDS` / `SLOT_KIND`, not a free string. It lives on the asset index (ADR 0175) and in the character line's `art.bundle.schedule`.
- **It carries NO count, NO duration, and NO period reference. It is never summed, never converted, and never compared.** It selects which rows a panel shows. That is the whole contract, and it is why no second clock is created: a presentation axis with no magnitude cannot drift from the clock.
- **Deriving it from `periods` is owed to ADR 0173's `TimeLadder` and is deliberately NOT done here.** A `PERIODS_PER_DAY` constant authored in an asset tool would be a third time constant alongside `world_pulse.gd:88` and `save_clock.gd:34` — the exact drift `AGENTS.md:52` names ("six independently-chosen caps would drift"). When 0173 lands, daypart becomes `TimeLadder`-derived and this ADR is superseded on that point alone.
- **The place axis is `place` and carries `WorldLocationDef.location_id`** — 4 shipped values, already durable (`world_spawn_state.gd:8`) and already a key on `EventDef`, `ShopDef` and `NpcRosterEntry`. **It is named `place`, not `location`**, because `contracts/location_resolver.gd:4` is the BODY path's meridian contract.
- **An activity is an id the game already publishes, never a new string.** Two existing sources, both authored:
  - **`SectPositionDef.duties` and `.authorities`** (`game/src/modules/sect/sect_position_def.gd:100,103`) — *"What the holder must do, as authored verb ids. **Counted, never executed**"* — already priced in periods (`:137-138`). Shipped ids include `haul_at_the_yard`, `attend_instruction`, `hold_the_line`, `teach`, `judge_the_yard`, `sit_with_the_vine`, `record_the_yard`, `counsel_a_bulwark`. **This is the repo's own precedent for an occupation**, and a routine should draw on it rather than invent a parallel taxonomy.
  - **Module verb names** — `cultivate`, `meditate`, `harvest`, `craft`, `buy`, `sell`, `raise_anchor`, `fight_wave`, `withdraw`, `visit_room` and the rest, each an existing `api.gd` symbol.
- **The schedule block is guarded by `_no_stat_numbers`, unchanged.** Any number in it is refused, which is what makes "no duration" enforceable rather than aspirational.
- **A schedule row is validated at `canon`:** `daypart` in the closed set, `place` a shipped `location_id`, `activity` an existing verb id, `shot_id` an existing shot. A `GAP` fails, a draft may carry one.

## Consequences

- **A daily bundle is authorable today with no `core/` change, no ADR dependency on an unwritten ladder, and no second clock.** The cost is that daypart is a presentation label rather than a derived value, which is stated here so nobody later "fixes" it by adding a ratio.
- **The naming hazards are closed:** `daypart` cannot collide with `Tribulation.phase`, `place` cannot be read as a meridian, and `activity` cannot become a free tag beside the already-free `NpcDef.tags` (`npc_def.gd:28`).
- **A schedule is a rendering rule, not reconciled state.** There is nothing to reconcile — the phase is a lookup — so it does not join ADR 0170's per-tier staleness stamp and does not need `core/reconcile_stamp.gd`.
- **`NpcApi` cannot be widened to read it.** At 12/12, a schedule read is a key on `NpcApi.summary`'s returned dictionary or a split, never a thirteenth method.
- **A live defect blocks trusting any place-keyed schedule and must be fixed first:** `NpcApi.presence_here(non_empty_location_id)` returns **zero rows in production**. `NpcBoot.populate_room` calls `NpcApi.populate(def_ids, role)` with two arguments (`app/npc_boot.gd:127`), `populate` calls `spawn` without forwarding `location_id` (`api.gd:373`), so every `NpcRosterEntry.location_id` is `""` and the filter at `npc_read_model.gd:69` drops every row. `grep 'presence_here' game/tests` returns **no matches** — it is untested.
- **Owed, not decided here:** the `save_clock.gd:34` duplicate and its wrong ADR citation; deriving daypart from `TimeLadder` when ADR 0173 lands; and authoring `economy/profession` past its single record so an occupation can become lore rather than stay a verb id.
