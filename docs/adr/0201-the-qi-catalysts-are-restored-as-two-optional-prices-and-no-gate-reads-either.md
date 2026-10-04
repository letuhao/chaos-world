# 0201 the qi catalysts are restored as two optional prices, and no gate reads either

- Status: Accepted
- Date: 2026-10-05
- Supersedes: ADR 0096 (its deletion of the family is reversed; its reasoning stands)
- Amends: ADR 0180 (its "a fourth role is the wrong fix" claim, for this path)
- Closes: DEF-0040, DEF-0036 (already recorded done on evidence that was stale)

## Context

ADR 0096 deleted 90 qi catalyst items. Its own `DEF-0036` asked the question and the
owner has now answered yes: add the seed field and consume it in qi training. Two of
its three reasons still stand and this ruling is built to satisfy them rather than to
argue them away.

**Reason one — nothing consumed them.** Measured before editing: 0 `*_catalyst.tres`
under `game/data`, while `tools/generate_qi_items.py:240-241` still minted both
families. Re-derived, not taken from the defer entry: `DEF-0040`'s "120 orphans"
counted items and recipes; the surviving half was the generator.

**Reason two — a mandatory item in a gate position removes the player's only lever.**
Dantian quality is raised by `cultivate`, a free action, and every one of the 30 seeds
demands `dantian_quality_required`. Tax that behind a mandatory consumable and "did I
cultivate well" becomes "do I hold the item". This is the objection that mattered.

**Reason three was that the content was incoherent** — all 90 were `restore_health`
sticks, and one was named after a component qi does not have. That reason is answered
by deletion of the mislabelled *content*, not of the roles: the 60 items regenerated
here carry no modifier at all (`ItemDef.fixed_modifiers` empty, ADR 0009's
progression payload), and neither is named after a component qi lacks. `sea_catalyst`
stays deleted: the sea of consciousness is the mind path's container, and ADR 0096 was
right about that one.

## Decision

**Two `@export` roles on `QiRealmSeed` (`realm_seed.gd`), and NEITHER is a gate.**
`QiBreakthroughCondition` reads progress, comprehension, quality, fill, the pill and the
channels. A catalyst read in a gate position is now a failing audit, not a taste call.

- **`dantian_catalyst`** is consumed by `QiTraining.cultivate`
  (`training.gd:_buy_overflow_quality`), once per sitting whose circulation OVERFLOWS a
  reservoir the gate already demands be full. The overflow becomes one step of quality
  PAST the next realm's own floor (`CATALYST_QUALITY_STEP = 0.05`), and
  `cultivate` stops refining exactly at that floor. So the catalyst buys roll
  certainty (`QiChance.of` = `0.05 + 0.5 × quality`, capped 0.55) that the free verb
  structurally cannot reach. Nothing that reaches a realm requires one.
- **`meridian_catalyst`** is consumed by `QiTraining.train_off_gate_channel`, published
  as `QiCultivationApi.train_off_gate_channel` (facade 8 → 9 against a cap of 12). It
  pays for one step on a channel the NEXT realm's gate does **not** name, and refuses a
  gate-named channel, an injured one (`recover`'s price, ADR 0141), and one with nothing
  left to learn. The body holds 20 channels and a gate names 4-8, so the rest are real
  work with no price; ADR 0158 rejected widening the *selection walk* because the
  realm's ELIXIR is the gate's price, and a second item is what makes the same work
  honest. Its effects are `MeridianNetwork.get_flow_bonus` (every later sitting reads it)
  against `get_capacity_bonus` (a wider reservoir, which `fill_required == 1.0` then
  demands more absolute qi to fill) — a real trade-off, not a rounding error.

**Why this is a choice and not a fourth tax.** Both roles are per-realm and neither
banks, so a player picks WHICH of the two preparations to spend on — and pays nothing by
picking neither. The elixir ladder that walks the gate is untouched.

**The generator's `Ext_resource` bug is fixed.** Every template wrote `script =
Ext_resource("1_item")`; Godot's text parser accepts only `ExtResource`, and the 120
files it produced were unloadable (`Parse Error: Unexpected identifier 'Ext_resource'`
at line 6). Nobody caught it because ADR 0096 deleted every file this script had ever
written — the generator had produced nothing loadable in the current tree. All four
templates are corrected.

Rejected: *a fourth gate role*, which is the rejection ADR 0096 already made and
recorded. Rejected: *give them a fourth consumable role alongside `training_item`* — the
elixir ladder already prices the gate. Rejected: *a depth step past the standing realm's
`channel_refinement_cap`*, which looked like the meridian answer until the boundary audit
was read: `qi_gate_demands_more_depth_than_the_realm_below_offers` proves the gate is
reachable inside the standing cap at all 29 boundaries, so depth past it buys a gate
nothing and is dead content. Rejected: *buy certainty by raising quality with no
overflow trigger* — then the trigger is invisible and a player pays for a sitting that
would have happened anyway. Rejected: *one verb with two prices chosen by the gate*,
because the price would depend on the next realm's seed, which the caller cannot read,
so one press would cost one of two items chosen by data the caller never saw.

## Consequences

- 60 items and 60 recipes regenerated (`qi_<realm>_dantian_catalyst`,
  `_meridian_catalyst`); the run is idempotent. Both families are exempt from the
  modifier-coverage check because a seed field now names them (`DEF-0040`'s mechanism).
- **Four new findings in `tools/cultivation/audit.py`**, each with a synthetic-fixture
  red path in `tools/cultivation/mutate.py`: `qi_catalyst_unconsumed`,
  `qi_catalyst_gated`, `qi_catalyst_unauthored`, `qi_catalyst_item_missing`. The gate
  assertion is the anti-0096 guard: it reads `breakthrough_condition.gd` as CODE LINES
  ONLY (comments stripped first, ADR 0188) and fails on a catalyst named in any verb of
  it.
- `game/tests/modules/qi_cultivation/test_qi_catalyst_never_prices_a_gate.gd` proves
  ADR 0096's objection cannot apply: all 29 boundaries close on an actor holding no
  catalyst, a gate-named channel refuses the catalyst verb while the elixir still walks
  it, and a burn still costs `recovery_item`.
- **Stays deleted:** the 30 `qi_<realm>_sea_catalyst` items and their recipes. The sea is
  the mind path's container; qi has no such component to strengthen.
- **Stays deferred:** `qi_<realm>_breakthrough_pill` still has two recipes, as ADR 0096
  recorded. Unchanged by this ruling.
- **HANDOFF:** `qi_cultivation_screen.gd` renders no off-gate channel row, so
  `train_off_gate_channel` is reachable from the facade and from no screen yet — the same
  shape ADR 0158 handed off and ADR 0164 closed for the selection verb.