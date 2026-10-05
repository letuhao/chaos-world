# 0180 the qi path charges at the gate and gates only on what a player can act on

- Status: Accepted
- Date: 2026-10-04
- Closes: DEF-0214, DEF-0227, DEF-0228, BL-0757
- Amends: ADR 0096 (the fourth role stays deleted), ADR 0141 (the repair price is unchanged)
- Amends: ADR 0150, ADR 0158, ADR 0164 (the read model still reports the enforced gate)

## Context

Three properties on the qi path were authored, wired, rendered — and bought the player
nothing. All three were re-derived from the source before any was ruled, per BL-0619,
and two of the briefs' conclusions did not survive the re-derivation.

**DEF-0228, `dantian_tier`, was vacuous. Confirmed, and worse than "ungated".**
Authored on all 30 seeds (`realm_seed.gd:25`), written by `synchronize`
(`training.gd:24`), published at `api.gd:96`, rendered as a row name
(`qi_cultivation_screen.gd:42,155`). `_dantian_ready` read injured/progress/
comprehension/quality/ratio and never tier. Two measurements decided it. The bands
are 9 `lower` / 9 `middle` / 12 `upper` — a restatement of the ladder's own Mortal /
Spirit / Immortal split, so the row said nothing the realm line beside it did not
already print. And the bands are **not monotone**: `tribulation(lower) ->
spirit_condensation(middle)` and `spirit_ascension(middle) -> earth_immortal(upper)`
step up. Since the only writer reads the realm the actor is **standing in**, a tier
floor would have been unsatisfiable at exactly those two boundaries and free at the
other 27 — the `body_physique_gate_dead` shape transplanted.

**DEF-0214, `cultivate` costs nothing. Confirmed, and the corpus says it is the
price.** `training.gd:31-59` spends no qi, no clock and no item, and its comment
(`:44-48`) argues about a deadlock, never a price — it was never priced on purpose.
What the corpus adds: **`dantian_fill_required` is `1.0` on all 30 seeds.** The gate
demands a *full* reservoir everywhere, `cultivate` is the only verb that fills one,
and the ladder's own `progress_required` (100 → 2900) is the meter. The free verb IS
the gate's price.

**DEF-0227, `cancel_attempt` unwired. Confirmed, and the proposed fix was wrong.**
`rg cancel_attempt game/src game/tests` found one hit — the definition. The entry
proposed publishing it on both facades. Re-derivation shows body and mind cancel a
**stored attempt**: `BodyAdvancement._end` and `MindAdvancement._end` both call
`committed.cancel()` on a `BodyAttempt`/`MindAttempt` carrying `trial_complete`, and
both document it as a *refund* — "the pill stays spent and no deviation is owed: the
trial never ran". Qi has **no attempt to cancel**: `QiBreakthroughTransaction.execute`
(`:92-168`) validates, consumes the pill, rolls and resolves in one call, and no
`QiAttempt` or `trial_complete` exists in the module. So qi's `cancel` was the
semantic **opposite** of its siblings' under the same name — it inflicted a deviation
unconditionally, with no roll and no pill spent.

## Decision

**1. `dantian_tier` is DELETED**, from the seed class, all 30 `.tres`, `synchronize`,
`panel_state`, the screen's row label, and `Dantian` (`tier`, `set_tier`,
`LOWER/MIDDLE/UPPER`, and its save round trip). House style, ADR 0096: prefer deletion
when a property cannot be made to earn its place. It could not be made to gate
anything without re-authoring 30 seeds against a threshold the ladder's own shape
contradicts. Rejected: *gate on it* — two boundaries become unreachable. Rejected:
*keep the label* — a label for the realm the player is already looking at.

**2. `cultivate` STAYS FREE, and the gate is named as the price.** All 30 realms
demand a full reservoir; the free verb fills it; `progress_required` meters the
sittings. The other two halves are priced and reachable: `train_channel` spends
`training_item`, `attempt_breakthrough` spends `breakthrough_item`, and
`qi_gate_ladder_findings` grades all three roles resolve in content. Rejected: *price
the sitting in qi* — the gate wants the reservoir full while the verb would be
charging out of it, and the two demands cancel into the deadlock `training.gd:44-48`
already documents having happened once. Rejected: *price it in time* — no qi verb
reads a clock, and the three paths' free verbs are uniform by design.

**3. `cancel_attempt` is DELETED, not published.** `QiAdvancement.cancel_attempt` and
`QiBreakthroughTransaction.cancel` are gone; `_deviate` keeps exactly one call site,
the failed roll inside `execute`. Rejected: *publish it* (the deferred entry's
suggestion) — it would have shipped a button that halves progress, scars the dantian
and burns a channel under a name meaning "abandon safely". Rejected: *keep it for a
future two-phase attempt* — qi is single-phase, and a verb whose precondition does
not exist on this path is dead weight with a misleading name.

**4. The read model and the verb share ONE candidate list (BL-0757).**
`_training_candidates` returns the gate's channels and nothing else. The tail it
appended was `MeridianDefaults.all()`, contradicting `training.gd:202-206`, which
refuses to charge the realm's elixir for work the gate never asked for. The docstring
claiming the tail existed "so a spare elixir has somewhere to go" is deleted with it:
a docstring the code contradicts is the rot, not the code.

## Consequences

- Four guards, one per ruling, each with a **synthetic-fixture red path**: a
  re-declared `dantian_tier`, a `cancel_attempt` declaration, a `_training_candidates`
  that reaches `MeridianDefaults`, and a `cultivate` that spends or fails to fill. A
  green guard is not a tested guard (INC-0016).
- Q1's guard asserts the two band edges from a preserved map, so a re-authored ladder
  that moved an edge is caught as a changed count — the deletion is not a taste call.
- Q2's guard asserts `cultivate` spends no item and *adds* qi, plus that every realm
  demands `dantian_fill_required == 1.0` and authors all three consumables, so the
  "the gate is the price" claim is checked rather than asserted in prose.
- Q3's guard counts `_deviate` CALL SITES, not verbs — a voluntary door is a second
  call site — and separately proves the failed roll still deviates, so deleting the
  voluntary verb did not delete the consequence.
- An old save carrying `"tier"` still loads: `from_dict` reads named keys, asserted.
- **Fixed in passing, not mine:** `test_qi_training.gd::test_train_channel_repairs_an_
  injured_channel` stocked `training_item` and asserted the channel elixir repairs a
  burn — the defect ADR 0141 deleted, still asserted, and the exact opposite of
  `test_qi_repair_pricing.gd:110-120`. Two suites contradicted; only the pricing one
  was right. Now stocks `recovery_item`. Pre-existing, verified byte-identical to HEAD.
- **Still deferred:** the mind path's own unwired `start`/`resolve`/`cancel`
  (BL-0151) is untouched — this ruling covers the qi half only, and mind's
  two-phase attempt means publishing its `cancel` is a real fix there.