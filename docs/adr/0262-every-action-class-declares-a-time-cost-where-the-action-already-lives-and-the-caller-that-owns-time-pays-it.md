# 0262 Every action class declares a time cost where the action already lives, and the caller that owns time pays it

- Status: Proposed
- Date: 2026-10-05
- Depends on: ADR 0167 (the action-time contract), ADR 0173 (one clock, one budget), ADR 0089 (no module owns time), ADR 0095 (facades publish verbs, not timing)

## Context

ADR 0167 declares four action classes and says a time cost is "a property of the action,
declared where the action already is". Measured on this tree, one of the four exists.

A census of 119 actions across 39 modules found exactly ONE player-reachable world-time
verb before this ADR: `act_wait_season` (`ui/screens/world_map_screen.gd:83`), paying one
period. `ItemWorkbenchPlay.retreat` now pays a chosen length, and the panel's selector
prices it — but that is the season-scale class alone.

The other three are absent, and their absence is silent rather than refused:

- `ItemsApi.craft(recipe, inventory)` (`modules/items/api.gd:49`) — instantaneous.
- `DomainApi.generate_and_enter(actor, template_id, seed)` (`modules/domain/api.gd:107`) —
  instantaneous.
- `CombatApi.exchange(actor, seed)` (`modules/combat/api.gd:50`) — instantaneous.
- Travel, `SectApi.teach`, the auction and custody settles — all instantaneous, and several
  of them already hold a `periods` count they never spend on anything.

So "every player action costs world time" is currently true of one action class out of
four, and ADR 0167 reads as though all four shipped.

The `amount` a cultivation verb takes is a QI amount, not seconds, and that is load-bearing
rather than incidental: `modules/qi_cultivation/training.gd:42` computes
`gain := amount * RealmRate.factor(state.rank_id)`. `CULTIVATE_STEP := 25.0`
(`modules/qi_cultivation/api.gd:18`), `MEDITATE_STEP := 1.0` (`:19`), the mind pair
(`modules/mind_cultivation/api.gd:20-21`) and `BodyCultivationApi.STEPS`
(`modules/body_cultivation/api.gd:20`) are all magnitudes.

## Decision

- **The four classes stand, and each declares its cost where the action already lives.**
  A module owns the DURATION of its own action — that is content, and content lives beside
  its feature. It does not own the clock: no module reads `Time.get_ticks*`, declares
  `_process`, or learns what time it is (ADR 0089 / DEF-0111). The number is a `const`
  beside the verb, in the module, named for what it measures.
- **The period is the only unit any of them is expressed in.** `TimeLadder` is the only
  converter (ADR 0173), so a cost is an integer count of periods and never seconds. The
  season-scale costs are expressed as a magnitude the ladder already authors
  (`ratio_for(&"day")`), never as a literal that would drift on a retune.
- **The four costs:**

  | class | cost | who declares it |
  |---|---|---|
  | instant | **0 periods, declared** | equip, read, browse, compare, inventory sorting |
  | period-scale | 1..8 periods | craft, train a channel, trade, rest, an auction settle |
  | season-scale | one authored magnitude | a meditation retreat, a delve, travel between places |
  | turn-scale | **0 world periods** | one combat round, one movement step |

- **Turn-scale is not world time and is said so.** A round resolves inside one period and
  the world does not move; a fractional period would need a second unit and a conversion
  table, and nothing needs one. Combat converts its elapsed REAL time to world time
  afterwards, at ADR 0173's authored periods-per-second rate — which is BL-0890 and is
  still unbuilt. Until that rate exists, combat costs no world time at all, and that is a
  known hole rather than a decision.
- **A caller pays; a module never charges.** The screen or composition-root verb that owns
  the moment reads the declared cost, hands it to the one explicit path
  (`WorldPulse.advance_periods`, which chunk-plans and refuses rather than truncating), and
  calls the action ONCE PER PAID PERIOD. `cultivate(actor, amount)` keeps `amount` as a qi
  amount; adding a `periods` parameter to a cultivation facade would put a time unit inside a
  module that may not own one, which is why ADR 0167 refuses it.
- **An action whose cost exceeds one call is paid in bounded per-period steps, and an
  interruption pays only for the periods actually paid.** The retreat already does this:
  `retreat(periods)` reports `declared`, `paid` and `unpaid`, and gain is proportional to
  what was paid rather than to what was asked (ADR 0167's meditation clause).
- **Declaring 0 is mandatory.** An instant action states `ZERO` or an equivalent rather than
  saying nothing, so "this costs no world time" is a recorded decision a reviewer can
  disagree with — and so a test can census the declarations and fail on an action that has
  none. The failure this guards is the one measured above: four classes in an ADR and one
  in the tree.

## Consequences

- Crafting a single item ticks the world. So does one delve. That is the premise working:
  doing things is what moves time, and standing still is free.
- **The world will race.** If a player crafts in a loop, the world advances a period per few
  presses. That is intended — it is what makes a market worth visiting — but it means the
  event budget and the institution cadences are load-bearing in a way they were not when one
  button advanced everything. A craft loop is the cheapest way to age a world by decades,
  and that is a balance question this ADR creates rather than settles.
- A census becomes possible: a test that every published action verb either declares a cost
  or is on an explicit instant list. That test is what would have caught the three missing
  classes, and it is the honest answer to "how would we know".
- BL-0893 is answered as a decision. What remains is the work: four class tables, the
  per-verb declarations, the per-period call sites, and the census.

## Rejected

- **A single authored cost table keyed by verb name.** It would be a second SSOT beside the
  verbs, and a verb renamed without the table updated would silently become free — the same
  drift `realm_power_table` and `time_ladder` exist to prevent, in the one place where a
  stale key costs nothing to notice.
- **Putting `periods` on the cultivation facades.** Refused by ADR 0167 and measured at
  `training.gd:42`: `amount` is a qi magnitude and a module may not hold a clock.
- **Charging world time per combat round.** A fight would advance the calendar faster than a
  meditation, which inverts the fiction: a duel is a moment, a retreat is a season.
