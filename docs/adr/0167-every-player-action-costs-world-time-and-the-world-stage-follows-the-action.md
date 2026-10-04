# 0167 Every player action costs world time, and the world stage follows the action

- Status: Proposed
- Date: 2026-10-04
- Depends on: ADR 0089 (one clock), 0113 (a monotone fact ledger), 0114/0117 (one offer point), DEF-0111 (no module owns a clock)

## Context

- The ONE player-reachable world-time verb is `act_wait_season` (`ui/screens/world_map_screen.gd:83`) -> `ui/panels/world_pulse_reader.gd:47` -> `app/item_workbench_app.gd:1246-1250` -> `app/item_workbench_play.gd:94` -> `WorldPulse.advance_periods(1)` (`app/world_pulse.gd:222`).
- It is the only *player-chosen* path. `_process` also pulls `_world.pull(delta)` (`app/item_workbench_app.gd:601-602`), but that converts wall-clock seconds, so a player who acts fast never earns a period from it — and this ADR deletes that pull.
- `advance_periods` is already "a verb rather than a timer" (`world_pulse.gd:214-221`) and clamps to `MAX_PERIODS_PER_PULL` = 8 (`:95`). `PERIOD_SECONDS` = 120.0 (`:88`): one period is two real minutes.
- **Every other player action is instantaneous in world time.** Cultivation verbs take no time parameter at all: `QiCultivationApi.cultivate/meditate(actor, amount)` (`modules/qi_cultivation/api.gd:218,239`), `MindCultivationApi.cultivate/meditate(actor)` (`modules/mind_cultivation/api.gd:149,153`; step is a module const, `:20-21`), `BodyCultivationApi` likewise (`modules/body_cultivation/api.gd:185,190`). `amount` is a **qi** amount, not seconds — `gain := amount * RealmRate.factor(...)` (`modules/qi_cultivation/training.gd:42`). So is crafting (`modules/items/api.gd:49`), combat (`modules/combat/api.gd:50`), domain delve (`modules/domain/api.gd:107`), loot, socket/enchant, sect/nation/clan and trade.
- Everything downstream already consumes an **explicit integer period count from the caller that owns time**: `EventApi.advance(_actor, periods)` (`world_pulse.gd:342`), `_settle_institutions(periods)` (`:349` -> `app/institution_resolver.gd`, cadences 1/4/16 at `:48-50`), `AnchorApi.repair(actor, periods)` (`item_workbench_play.gd:126-129`).
- The period loop already exists and is bounded: `for index in periods: offer(PERIOD_FACT, 1, PERIOD_SOURCE)` (`world_pulse.gd:353-354`). `offer` is the one beat offer point in `app/` (`:232`); `BeatDirector` records before it resolves (`app/beat_director.gd:135`) and exactly two sinks are registered (`world_pulse.gd:180-181`).

## Decision

- **There is no skip button.** Time is not spent from a menu; it is paid for by acting. A player who wants the world to move chooses something to *do*, and the world moves because they did it.
- **There is no real-time clock.** `_process` keeps its status tick, death poll and autosave, and loses `_world.pull(delta)` (`app/item_workbench_app.gd:601-602`): time advances only through the explicit verb. Idle is frozen, a hitch is not a world event, and nothing is banked between frames (`world_pulse.gd:127-129`). **This deletes code**, and the pull it lived in goes with it.
- **A time cost is a property of the action, declared where the action already is**, paid through the existing explicit-verb path (`advance_periods`-style). Never `Time.get_ticks*` outside `app/` (ADR 0089, DEF-0111). Never a new frame driver — `tests/app/test_status_clock.gd:222-230` pins exactly three (`item_workbench_app`, `nav_probe`, `player_adapter`), and none is owed here.
- **One unit: the period.** Every accrual verb in the tree already takes an integer period count, so a coarse unit would be a conversion table somebody gets wrong; nothing is expressed in seconds, and no second calendar unit is introduced here. **The period's relation to larger spans is not decided here**: the clock is one SSOT and the magnitudes above a period are authored there (ADR 0173). The panel still says "A season passes" / "Wait a season" (`ui/panels/world_pulse_panel.gd:39,51`) while paying one period; whether a season becomes a name the UI may display is 0173's call, not this ADR's number.
- **The four costs, and what lands in each:**

| class | cost | examples |
|---|---|---|
| instant | **0 periods, declared** | equip, read, browse, compare |
| period-scale | 1..8 periods | craft, train channel, trade, rest |
| season-scale | one coarse magnitude (ADR 0173) | meditation retreat, domain delve, travel, breakthrough |
| turn-scale | **0 world periods** | a combat round, a movement step |

- **Turn-scale costs are not world time.** A round resolves inside one period and the world does not move; a fractional period would need a second unit and a conversion table, and nothing needs one.
- **Combat is the exception, and it is unaffected.** It stays real-time: the turn tier still consumes real time and nothing above it does. Its elapsed real seconds convert to tier turns *afterward*, at ADR 0173's authored periods-per-second rate, handed to the same explicit verb every other cost uses. Combat is the only thing in the tree that spends a second, and it spends it through the one clock rather than through a second conversion.
- **A cost larger than `MAX_PERIODS_PER_PULL` is paid as bounded per-period steps, never as one call.** The clamp is per *call* (`world_pulse.gd:223`): a coarse cost is several calls of 8, not one call of N. `MAX_PERIODS_PER_PULL` stays 8 — a hitch must never walk an authored ladder to its end in one advance.
- **The existing `for index in periods` loop (`world_pulse.gd:353-354`) is the executor of a bounded cost** — one iteration per paid period, doing that period's work and offering that period's beat. A cost is a number, the loop already runs, and it is paid at a cadence a reviewer can count. A long skip is not this loop's job; that is ADR 0173's budget.
- **Meditation is the special case, and both halves must be expressible.** The player **chooses** how long to sit — that chosen length *is* the cost, declared by the caller, not a menu. The world's **interruption** is not the player's: a beat offered through `WorldPulse.offer` (`:232`) can stop the remaining steps at any whole period. **Gain is proportional to periods actually paid, not to periods declared**, so an interrupted retreat pays in part — which falls out of the loop above, because each paid period is one verb call.
- **Cultivation facades gain no time parameter.** `amount` stays a qi amount (`qi_cultivation/training.gd:42`); the caller that owns time decides how many periods of that work it is buying and calls the verb once per paid period. A `periods` argument on a module facade would put a time unit inside a module that may not own one.
- **Keep `act_wait_season`, demoted to an explicit out-of-combat wait of exactly one period, no argument.** Never a multi-period skip, disabled while anything is in flight. It is **not** retired: it is the only player-chosen engine of institution and event accrual, and retiring it before every action carries its own cost would strand both.
- **Every accrual verb keeps taking an explicit count from the caller that owns time.** `app/` still wires and counts — `_settle_institutions` keeps two integers and no table (`world_pulse.gd:426-429`); `app/` holds no ledger.
- **`WorldFact` stays monotone** (ADR 0113): a period that elapsed is recorded, never a mutable clock field in the ledger. **`WorldPulse.offer` stays the one beat offer point** (ADR 0114/0117); an interrupted retreat offers through it and nowhere else.

## Consequences

- **Free by construction:** the action classes stop being free, and the world stops advancing only when the player presses a button. No new clock, no new driver, no new module edge — the loop, the pulse and the director already exist.
- **Meditation becomes interruptible, so a partial retreat's qi/mind/body gain must be priced per period**, not per declaration. Existing tests assert `x == x` style instant verbs and will need period-priced siblings; the instantaneous path stays instant and is what `tools ui drive` exercises.
- **Content cost:** a season-scale action is several bounded steps and will feel long at `PERIOD_SECONDS` = 120.0. That base ratio is ADR 0173's to move, and `MAX_PERIODS_PER_PULL` stays 8 — retuning cadence is a separate decision, not a consequence smuggled in here.
- **`app/` keeps the one bridge** (`item_workbench_app.gd:1246-1250`). A screen still asks the pulse and never a module, so the panel that asks for an advance is the same panel for a wait and for a retreat.
- **Owed, not decided here:** the **persistence home for a declared cost** (an `int` in the caller's file today; a `core/` value object would need its own ADR); **interruption content** (which beats cut a retreat, at what cadence — an `event` decision, and the mechanism here is the per-period loop, not a tuning table); and **a coarser magnitude as a name the player reads**, which belongs to ADR 0173's clock.