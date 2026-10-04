# 0160 Learning costs progress, and mastery scales a passive's values only

- Status: Accepted
- Date: 2026-10-04
- Depends on: ADR 0053 (three states), ADR 0054 (passive = namespaced `StatModifier`), ADR 0055 (bounded ladders), ADR 0059 (path gate)
- Resolves: DEF-0206, DEF-0207

## Context

ADR 0055 published two numbers that nothing spent and nothing read:

- **Learning cost** — `LEARN_BASE = 100.0`, `LEARN_STEP = 1.03`, priced at
  `100 * 1.03^ordinal * MAG_GRADE`. `TechniqueGate.learn_price_for` computed it and
  `TechniqueReadModel` published it to the codex screen. No caller anywhere
  deducted it: `TechniquesApi.learn` was free, and its own docstring deferred the
  charge to "the caller", a caller that did not exist.
- **Mastery** — `power` x1.15 compounding. `TechniqueCasting` applied it to
  cooldown and qi cost, both of which are only reachable on an ACTIVE technique.
  `CodexEntry.effects_for(def)` ignored `mastery_rung` entirely, so a passive's
  contribution was byte-identical at rung 0 and rung 4.

ADR 0055 sized the learn step deliberately: *"study is cheaper than a breakthrough
everywhere and never runs ahead of it"*, measured against qi `progress_required`'s
`1.035714` floor at R29 to R30. That sentence names the quantity the price was
sized in — and nothing charged it, so the guarantee was free in the only sense
that made it worthless.

Both entries are one decision, because both are the same question asked twice:
**which existing quantity carries a technique's authored numbers?**

## Decision

### Learning is paid for in the technique's own path's progress

`TechniquesApi.learn` charges `TechniqueGate.learn_price_for(actor, def)` out of
the **`PathState.progress`** of the technique's own path. All-or-nothing, checked
before any deduction, and a shortfall refuses with `insufficient_progress` and a
`short` list naming the path, what it owed and what it held.

The evidence that decided the payer, in the order it was considered:

- **Not `qi`.** `qi` is a `ResourcePool`, so it was the obvious candidate — but a
  technique's qi cost *is* its cast cost, and qi refills from the reservoir on its
  own schedule. Charging study out of it prices **acquisition** in the currency of
  **execution**, which makes "may I afford to learn this" a question about combat
  timing rather than about cultivation. It is also the one cost an actor can avoid
  entirely by never casting — precisely the actor a study cost is aimed at.
- **Not `comprehension`.** `Stat.COMPREHENSION` is a **base attribute, not a
  pool**. `QiBreakthroughCondition`, `BodyBreakthroughCondition` and
  `MindAdvancement` all compare it against `comprehension_required`; it feeds
  `Stat.INSIGHT_GAIN`, which is the *rate comprehension grows at*;
  `TribulationEndurance` and `AscensionState` read it too. Draining it is not a
  transaction — it is a set of gates silently moving backwards, in three modules
  this one may not reach.
- **Not `insight`.** `Stat.INSIGHT_GAIN` is a derived **rate**, not a stock.
  Writing to it overwrites a composition rather than spending a quantity.
- **Not a new resource.** A dedicated study-point pool would be a new concept with
  no producer, no regeneration and no UI, and ADR 0055 sized `LEARN_STEP` against
  a quantity that already exists. Inventing one to hold a number authored for
  another would be a second ladder disagreeing with the first.
- **`PathState.progress` is the one quantity that is both spendable and about
  cultivation.** It accumulates from training and is compared against
  `RealmSeed.progress_required` by all three paths' breakthrough conditions. ADR
  0055's own guarantee — study cheaper than a breakthrough, never ahead of one —
  is a statement *about this number*, and naming it as the payer is what makes the
  published ladder mean something instead of being a price on a screen nobody pays.

**A SHARED technique is never charged.** `shared` is this module's own vocabulary,
not a `PathState` id, exactly as it takes a universal slot rather than a path slot
(ADR 0053). A DUAL technique is charged to its first path — the same one the slot
allocator reads first, so the payer and the slot cannot disagree.

**The facade grows no method.** The charge went *into* `learn` and the
affordability table into two private helpers. `TechniquesApi` stays at exactly 12.

### Mastery scales a passive's stat-channel values, and nothing else

`CodexEntry.effects_for(def)` multiplies each effect's value by
`TechniqueScales.multipliers_at(rung, def.mastery_rungs)["power"]` — with three
refusals, each of which is a decision rather than an omission:

- **`qi_cost` (0.94^n) and `cooldown` (0.96^n) do not reach a passive.** They
  discount what an **activation** pays. A passive has no cost block at all: every
  shipped passive pins `qi_cost == stamina_cost == cooldown == 0.0`, and
  `TechniqueCasting.activate` refuses one with `not_active`. A discount column
  applied to a zero is a number that reads as a benefit and pays nothing.
- **The pool-capacity channel does not scale.** `RealmScaling` already MULTs
  `MAX_QI` and `MAX_STAMINA` by the realm's own `power` (1.0x to 551.46x), and
  `QiTraining.synchronize` re-seals the qi pool from the **next** realm's authored
  `dantian_capacity`. A passive that multiplied its capacity contribution by 1.749
  would be a **fourth** multiplier on a number that already has three, and the
  least authored of them. This is the "double-counting with the realm ladder" risk
  made concrete, and it is why the split is by channel rather than by option id.
  **The channel is identified by the target id, not by `target_type`.** Measured
  across `master_option_pool.jsonl`: all nine `resource`-typed options are one-shot
  restorations (`scope: current` — `restore_health`, `restore_qi`, …) and none is a
  capacity, while the capacity options (`core_max_qi`, `core_max_stamina`) are
  typed `stat`. A `target_type` test therefore never fires, and the refusal it
  documents silently fails open — `max_qi` scaled by 1.749 at rung 4, which is the
  exact double-count this bullet exists to prevent. `CodexEntry._is_capacity`
  matches the id instead.
- **A narrower ladder cannot reach a rung it did not author.** The clamp reads the
  def's own `mastery_rungs`, so a def lowered to two rungs never carries rung 4's
  power.

**The unbounded-stacking objection, answered by measurement.** The scale is at
most `1.15^4 = 1.749`, every `cult_*` option declares `bounds.max = 9999.0`, and
`OptionCatalog.clamp_to_bounds` enforces that window at authoring time. The
contribution is rebuilt remove-all-then-re-add under one `technique:<id>` tag
(ADR 0054), and rung scaling is a pure function of the rung — so rebuilding any
number of times lands on the same value. `PASSIVE_OPTION_CAP` is untouched: a
passive still holds two options, and mastery does not change how many.

### A passive is NOT a permanent body change that mastery must avoid

The alternative reading — "a passive is a permanent body change, so scaling it
double-counts with the realm ladder" — is **rejected**, because it does not
describe what a passive is in this repo. A passive's options
(`cult_bone_density`, `cult_mental_defense`, `cult_qi_control`) are **stat
modifiers**, not realm scaling: they compose additively with `RealmScaling`'s MULT
on the derived value, sit under their own `technique:<id>` source, and stop the
moment the technique is unequipped. `RealmScaling` scales the *actor*;
`TechniqueEffects` scales a *body change this actor trained*. Those are different
mechanisms with different owners, which is the whole of ADR 0054. The double-count
that IS real is the resource-capacity one, and that is the one refused above.

## Consequences

- **Learning is now a purchase.** The codex screen's price is a real charge, the
  gate still answers before affordability does (`realm_unmet` is never answered
  with a price), and a refused learn writes nothing — no partial payment, no
  codex row, no persisted payload.
- **Study competes with the breakthrough.** A player standing one step from a
  breakthrough at `progress_required` now has a genuine choice between the pill and
  the manual. That is ADR 0055's stated intent, and it is the first time the
  ladder has had any effect on play.
- **A SHARED manual is free.** That is a deliberate consequence of `shared` not
  being a path, and it is the same rule that gives a shared technique a universal
  slot instead of a path one. Six shipped techniques take it.
- **The facade is still at 12 methods.** Both entries cost zero surface.
- **A passive at rung 4 is meaningfully stronger than at rung 0** — 1.749x its
  authored stat options — and rung 0 is exactly what it was before this ADR, so no
  existing save or balance figure moves.
- **Mastery of a passive is still unreachable from a player action.** `raise_mastery`
  has no UI verb (that half of DEF-0207 — a study action on the codex screen — is
  owned by `ui/`, which this module may not touch, and remains open as a content
  and screen obligation rather than a module defect). What this ADR closes is the
  *module* half: when a rung does move, the contribution moves with it, immediately
  and without a rebuild.

## What was explicitly NOT done

- No new resource. No new facade method. No change to `Actor`, `PathState`,
  `ResourcePool`, `OptionCatalog` or any file outside
  `game/src/modules/techniques/`.
- No change to `game/data/`. Every shipped passive's authored values are untouched;
  what changes is the multiplier a rung applies to them.
- No `cult_*` option's bounds were widened. The ladder fit inside them.