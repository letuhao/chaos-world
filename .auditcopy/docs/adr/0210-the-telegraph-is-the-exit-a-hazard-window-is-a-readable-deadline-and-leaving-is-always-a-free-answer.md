# 0210 The telegraph is the exit: a hazard window is a readable deadline and leaving is always a free answer

- Status: Accepted
- Date: 2026-10-05
- Closes: BL-0843, and the telegraph half of BL-0842
- Depends on: ADR 0075 (accepted), ADR 0086, ADR 0089

## Context

Both `telegraph()` methods have zero production callers. Measured: the only call sites are
`tests/modules/domain/test_environment_field.gd:481,502,566` and
`tests/modules/domain/test_domain_fixture_reads.gd:66` — `EnvironmentField.telegraph`
(`environment_field.gd:502`) and `DomainFixtures.telegraph` (`domain_fixtures.gd:290`) are
read by no screen and no app. ADR 0075's "telegraph before damage" is therefore a claim.

Both already return the right *shape* — `bounds`, `telegraph_s` / `stay_budget`,
`mitigation_levers`, `boundary_visible`, `entered` (`environment_field.gd:502-524`) — and both
deliberately telegraph the **authored** number rather than the residual, so the UI never
learns the player's own gear (`environment_field.gd:509-511`). That discipline is correct and
this ADR keeps it.

What is missing is not a method. It is a **contract on what a telegraph must make
decidable**, and a caller.

## Decision

**A telegraph is a deadline the player can see, and the answer it offers is always "leave".**

- **A telegraph communicates four facts and nothing else:** the **volume** (`bounds`), the
  **kind** of harm, the **authored magnitude** (`amount` / `damage_share`, never the
  residual), and **how long the window lasts**. Mitigation levers are published because a
  player choosing to stay must know what staying could answer — but they are never scored.
- **A telegraph must be resolvable into an action.** The test: *can the player name what
  they will do differently after seeing this?* If the honest answer is only "now you know",
  it is decoration and must not be drawn as a warning.
- **Leaving is always free and always correct.** No zone and no trap may punish exit,
  interrupt it, or scale with the actor's remaining time inside. This is why the telegraph
  keeps the threat rather than removing it: a player who always retreats has learned the
  boundary and nothing about the cost, so the reason to stay has to be a **commitment**
  (ADR 0212), never a safe default.
- **Visibility is unfogged and permanent.** A zone's boundary is drawn from the moment the
  room is discovered, whether or not the actor is inside it — which is why
  `DomainMinimap._zones` deliberately does not fog (`domain_minimap.gd:172-176`). A hazard
  whose location is unknown cannot be routed around, and routing around is ADR 0075's own
  promise that a zone is a volume you route around or prepare for.
- **The window is authored content, already long enough to act on.** `telegraph_s` is 0.9–1.6
  s (`storm_gallery.tres:29-30`, `ash_chamber.tres:17-18`) and `stay_budget` 6–9 s
  (`ash_furnace.tres:12`, `ash_heart.tres:12`, `tide_vault.tres:12`). No new constant.

### What dies

`domain_explore.gd:157-168`'s `ARM_TICK := 2.0` — a presentation-layer number that exists only
so a second button press crosses the window. Once the trigger is presence (ADR 0211) there is
no press to size a tick against.

## Consequences

- **The caller is owed, and it is not a UI detail.** The read model already publishes the zone
  rows and their bounds (`domain_minimap.gd:182-201`); a scene draws from
  `DomainFixtures.telegraph` before it fires, and ADR 0075's contract becomes behaviour.
- **`residual_share` / `residual_amount` stay read-model only.** They exist so a player can
  price the *cost* of staying against their own gear without being told it in advance. That
  split — authored warning, personal price — is what stops the telegraph training a player
  to ignore it.
- **A telegraph that names a window no player can act in is an authoring error**, owned by
  the audit rather than the scene.