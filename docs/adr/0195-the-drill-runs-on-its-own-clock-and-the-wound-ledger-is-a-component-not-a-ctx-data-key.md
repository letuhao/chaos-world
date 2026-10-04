# 0195 The drill runs on its OWN clock, and the wound ledger is a COMPONENT, not a `ctx.data` key

- Status: Accepted
- Date: 2026-10-04

## Context

Three dead seams in the combat engine, found by audit. None of them is a wrong number;
each is a piece of machinery that was built, wired to nothing, and left looking live.

**1. The drill body was never ticked.** `StatusLoop` (ADR 0106) holds exactly one actor
and the composition root builds it for the HERO. The readout's drill body
(`ItemWorkbenchBody._readout_target`, ADR 0174) is in no loop. So on the one body a
player can actually strike:

- ADR 0070's wound DECAY never ran — severity only ever rose, and the necrosis arc the
  panel exists to render was a one-way ratchet;
- ADR 0071's rupture bleed and sea COLLAPSE never ran, so `MindDamage.tick_collapse`'s
  three-second demotion window could not advance on anything reachable.

Every suite driving `BodyDamage.decay` / `MindDamage.tick_rupture` /
`MindDamage.tick_collapse` directly stayed green throughout, which is the whole defect
class `tests/app/test_status_loop_combat_ticks.gd` was written to catch.

**2. `BodyDamage.WOUNDS_KEY` was a second, dead path to wound state.**
`body_damage.gd` wrote `ctx.data["body_wounds"]` from a `p_wounds` builder parameter,
on the stated reason that "the wound layer rides `ctx.data`". Nothing read it:
`breakdown` reads `AIM_MERIDIAN_KEY` / `AIM_MODE_KEY` / `TUNING_KEY` and never it,
production has always passed `null` (`combat_boot.gd`), and `BodyLocation.wounds_of`
existed solely to read it — with no production caller and a fallthrough of
`BodyWounds.new()` that answered non-null for every input, including none.

Wounds in fact settle through a different and correct route:
`CombatEffectApply._wound` -> `CombatEngineApi.wounds_of`, off the `body_wounds`
COMPONENT that `CombatBoot.install` binds and `Actor._wounds_dict` serialises
(ADR 0140). So the `ctx.data` channel could only ever have DISAGREED with the thing a
save carries.

**3. A test that could not fail.** `test_body_damage_aim.gd` asserted
`BodyLocation.new().wounds_of(hollow) != null`. Because the function's own fallthrough
was `BodyWounds.new()`, that assertion passes for every input under every implementation
— a deleted test wearing an assertion's clothes.

## Decision

**1. The drill gets its OWN `StatusLoop`, ticked from the existing frame.**

`StatusLoop` is a `RefCounted` with a single `_actor`, so the drill cannot ride the
hero's loop without either rebuilding it (resetting the hero's collapse window every
frame) or redesigning the wire ADR 0106 exists to keep singular. So it is a SECOND
INSTANCE, bound to the drill and driven by `_tick_drill(delta)` on the frame that
already exists.

**This is not ADR 0106's failure.** 0106's named defect is a second CLOCK — a second
`_process`, or a wall-clock read. This adds neither: one more call on the one frame,
handed that frame's own `delta`, and skipped entirely when no drill has been minted.
`tests/app/test_status_clock.gd`'s allowlist names the frame DRIVERS and is unchanged.

The loop is REBUILT when the drill is reminted, not re-attached, because the collapse
accumulator belongs to the sea that earned it — `StatusLoop.attach` says so, and
carrying one body's window onto another's is exactly the failure that reset avoids.

**2. The growth guards are `StatusLoop`'s, and that is why this runs FOREVER.**

`decay` moves severity DOWN only and the ledger holds one row per meridian; `tick_rupture`
spends `minf(loss, maximum)` out of a pool clamped to `[0, maximum]`; `tick_collapse`
resets `held` on every outcome and `MAX_COLLAPSE_HELD` clamps the accumulator. None of
the three creates state, and none can grow any. Nothing else needed inventing — the
guards were already written for "every frame, forever" and this is that frame.

**3. `WOUNDS_KEY`, the `p_wounds` parameter and `BodyLocation.wounds_of` are DELETED.**

Deletion, not wiring. There is nothing to wire TO: the ledger is component state and the
component is what every reader, the applier and the save payload already use. A
`ctx.data` channel for it would be a second answer about one fact, and the honest
number of channels for one fact is one.

This **corrects ADR 0174's stated reason for the seam** ("the wound layer rides
`ctx.data`"), which was unfulfilled — the sentence named an intent the code never
carried out, and keeping it would have left a false reason on the record for the next
reader.

**4. The vacuous row is REPLACED, not deleted.**

`test_body_damage_aim.gd` now asserts the claim that can fail in both directions: a body
with no ledger reads `null` (never a silently minted one), and a body with one reads
back the BOUND object BY IDENTITY — because a ledger re-created per read could never
accumulate, which is precisely the defect the deleted function's fallthrough would have
hidden.

## Consequences

- **A drill now decays, bleeds and collapses, visibly.** The wound arc and ADR 0071's
  "the loser is disarmed for a minute" are behaviour on a reachable body rather than
  theory.
- **The drill ages while the page is closed**, exactly as the hero does: the tick is
  session-only and the drill carries nothing a save would carry.
- **No arithmetic changed.** No file under `game/src/modules/combat/` had a number
  touched; `body_damage.gd` lost a parameter and a constant, `body_location.gd` lost a
  constant and a method.
- **ADR 0174's `ctx.data` sentence is superseded** by this ADR. Everything else in 0174
  stands.
- **`element_share` on a body technique remains inert, and that is CORRECT**: ADR 0070's
  formula has no share term, so a pure-body technique authoring one is inert data, not a
  broken seam. A DUAL `body+mind` technique is not a gap — its authored share reaches
  the MIND mechanism (`MindDamage.builder` reads `element_share` into `SHARE_KEY`), and
  `CombatBoot.ctx_builder_for` picks exactly one builder per hit, so there is no channel
  that reaches nothing. Body techniques carrying no `element_share` is a content choice
  and is left alone.