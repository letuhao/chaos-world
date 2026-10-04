# 0158 qi channel depth is selectable, and the selection verb is the facade's

- Status: Accepted
- Date: 2026-10-04
- Supersedes: ADR 0095 (only its "still dead, deliberately" list and its claim about the published
  helpers — both untrue; see Context)
- Amends: ADR 0095 (the depth gate it authored is now reachable)

## Context

ADR 0095 gave 26 of the 30 qi seeds a `required_channel_refinement` above 0, every one of them
demanding `strengthened`. It worked on paper: the gate reads state AND depth in one place,
`QiRealmSeed.channel_met` (`game/src/modules/qi_cultivation/realm_seed.gd:68`), and
`QiBreakthroughCondition._channels_ready` calls nothing else. Three of its claims are false.

1. **The depth half was unreachable through the only verb a player has.** `MeridianState.meets`
   is state-only by design (`game/src/core/meridian_state.gd:39`) — a rank comparison plus the
   injury flag. Every caller that chose WHICH channel to train skipped on
   `meets(required_channel_state)`, so from `body_integration` (seed index 4, depth 1) onward
   every channel already satisfied the state, every channel was skipped, and
   `QiTraining.refine_meridian` (`training.gd:176`) was never reached. 25 of the 25 depth
   boundaries walked in `test_qi_gate_walk.gd` stall at `strengthened` depth 0.
2. **"Publishes `can_train_channel` / `elixirs_to_gate` so a caller budgets a walk."** No
   caller in `src/` existed: `elixirs_to_gate` (`training.gd:253`) had none at all, and only
   the suite (`qi_gate_probe.gd:169`) called either. BL-0694 is right that the selection
   question was unanswerable from outside the module.
3. **"The qi transaction still does not call `Breakthrough.face_tribulation`."** It does,
   at `breakthrough_transaction.gd:115`.

ADR 0095 is immutable, so this supersedes it rather than editing it. Its other decisions —
`channel_met` as the single gate definition, `train_channel` refusing at the cap without
spending, the realm-seed cache, `attach` creating the dantian — stand and are not re-litigated.

## Decision

**The gate's completeness predicate is `QiRealmSeed.channel_met`, and `MeridianState.meets`
stays state-only.** Every caller of `meets` needs exactly a rank comparison:
`TechniqueDef.required_channel_state` (`technique_def.gd:87`) authors no depth companion and
`TechniqueGate` must not grow one; the mind path's seeds author no depth demand; and
`channel_met` composes both halves itself, so a depth term inside `meets` would make
`realm_seed.gd:70` dead while changing the meaning for the two callers that have no depth at
all. Adding it would have broken working code to fix a caller that never consulted it.

**Selection is one verb, not two predicates.** `QiTraining.train_next_channel` walks the gate's
own channels, skips the ones `channel_met` already satisfies, and spends an elixir through
`train_channel` on the first that still owes something; `QiCultivationApi.train_next_channel`
publishes it. Facade: 7 public methods to 8, against `MAX_FACADE_PUBLIC_METHODS` 12.

Rejected: *publish `can_train_channel` / `elixirs_to_gate` on the facade (BL-0694 as written).*
Then every caller reassembles `channel_met` from `panel_state`'s ingredients, and a reassembled
gate is ADR 0044's preview/action divergence — the defect this path already paid for once, and
which would now be written twice more (the qi and mind screens already differ). A caller that
wants the budget for a screen still reads `panel_state`'s `required_channel_depth`.
Rejected: *extend the selection to all twenty channels once the gate's four are done,* keeping
the screens' "keeps the button useful" behaviour. It charges the realm's elixir for sixteen
channels of work no gate asked for, at five times the walk's budget.
Rejected: *give `meets` a depth parameter.* A defaulted depth term is optional at every call
site, so the one caller that needed it would be the one to remember it.

## Consequences

- `tests/modules/qi_cultivation/test_qi_gate_walk.gd` walks all 25 depth boundaries pressing
  `train_next_channel` and nothing else — no `unlock_for_realm`, no forged refinement — and
  asserts each gate's state AND depth is satisfied, at the demanded depth exactly.
- `tests/ui/test_qi_channel_training.gd` drove the real selection loop at `qi_refining`, whose
  gate asks for depth 0: the single realm where a state-only skip is accidentally correct.
  That is why every suite was green.
- **Stays deferred (DEF-0214):** `cultivate` (`training.gd:31`) spends no qi, no time and no
  item, so all 30 realms are free work and only the three consumables are priced. Not decided
  here — a deliberate free-standing path and an unpriced ladder look identical in source.
- **HANDOFF to the UI owner:** `qi_cultivation_screen.gd:284` still carries its own selection
  loop and is still state-only. It should call the facade verb and name the returned id. Until
  then the depth gate is reachable in tests and not in play.
- `elixirs_to_gate` still has no `src/` caller; it is a suite convenience and this ADR does not
  make it one.