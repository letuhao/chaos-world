# 0938 action combat is a skill layer over the exchange baseline

- Status: Accepted
- Date: 2026-10-09
- Commissions: BL-0020 (its program starts after the cleanup wave; this ADR is its design pass)
- Depends on: ADR 0067 (one spine, one seam), ADR 0076 (the encounter exchange), the actor-vs-actor census (`test_damage_vitality_census`)

## Context

The exchange model is shipped and measured: `FightLoop` trades blows on an interval
(`BASE_BLOWS_PER_SECOND`), a rapid art at the 0.2 s clamp, and the actor-vs-actor census
pins the no-dodge fight at 25 blows / ~60 s across R1→R30. `CombatExchange` resolves an
encounter turn through ADR 0067's 11-stage spine, and `CombatDuel` owns the ONE ledger of
how a fight finished (`module_data["combat_duel"]`).

The owner commissioned action combat as its own program AFTER the cleanup: the exchange
stays the no-dodge BASELINE, and movement, dodging and ultimates are the player's skill
layer ON TOP — so the anchor's proof survives the feature.

## Decision

- **The baseline is frozen and pinned.** No layer verb is required to fight: with no dodge
  and no ultimate pressed, the same seed reproduces the same exchange, blow for blow.
  `test_damage_vitality_census` keeps the ~60 s anchor as the proof, and a layer slice that
  moves it is wrong.
- **A dodge is a PROPOSAL on S2, never a second resolution.** `FightLoop.dodge(seed)` opens
  a WINDOW (authored seconds, a stamina cost, a cooldown). A blow that lands inside the
  window resolves its S2 band roll as `missed` through the SAME one draw: i-frames are the
  window's authored length as an INPUT to the band, not a branch beside the spine
  (ADR 0067's rule). Its counterpart ships with it — evasion already pairs with accuracy —
  and the window costs stamina, because nothing is free.
- **An ultimate is a COSTED technique.** Qi and stamina plus a long cooldown, its magnitude
  authored like any art, resolved through the same spine S1–S11. It buys power with a cost
  and a wind-up; it never bypasses a stage.
- **One ledger.** `FightLoop` records a finished fight through `CombatDuel` (`record_win` /
  `record_defeat` / `record_spare`), exactly as `CombatExchange` does. The loop grows no
  tally of its own — a second counter is the ADR 0066 failure mode, and a spare stays a
  terminal state on the loser.
- **The arena/duel scene is the layer's home.** A scene that drives `FightLoop` with input —
  approach, dodge, ultimate — and renders the same `summary()` the screens already consume.
  The scene owns presentation and input only; every rule above lives in `app/`/`modules/`
  where the tests can reach it.

## Consequences

- The spine is unchanged: S2 gains an input, no stage is added, and the deterministic
  stream keeps its draw order — a dodge that consumed a different number of draws would
  desynchronise every replay.
- The layer is opt-in: an encounter that authors no windows plays exactly as today.
- The program's slices, in order: (1) the dodge window + i-frame proposal + its determinism
  test, (2) the ultimate cost model, (3) the arena/duel scene, (4) the ledger wiring proof
  plus a no-input reproduction test beside the census.
