# 0211 A trap fires on presence: the trigger is the body, never the button

- Status: Accepted
- Date: 2026-10-05
- Closes: BL-0842
- Depends on: ADR 0210, ADR 0073, ADR 0089

## Context

A trap fires when the player presses Arm twice. `DomainFixtures.arm` (the *only* trap entry
point, `domain_fixtures.gd:157`) arms on the first call and fires on the second once
`elapsed >= telegraph_s` (`domain_fixtures.gd:181-183`). Its caller is a button:
`domain_explore.gd:597` → `arm_fixture` → `domain_boot.gd:566-569`. The screen had to invent
`ARM_TICK := 2.0` because authored windows are 0.9–1.6 s and a press below the shortest one
re-armed rather than fired (`domain_explore.gd:157-168`). **Standing on a trap does nothing.**

Three consequences, and the third is the load-bearing one:

1. The trap's cost is paid for having *inspected* it, not for having entered it. A player who
   walks over a trap is free; a player who reads the room pays.
2. The telegraph is unreachable by construction. The window opens and closes inside a single
   press, so there is no frame on which a player could leave (ADR 0210).
3. It makes the trigger an **action by the player**, which is the one trigger class that
   cannot produce a hazard in a game with no real-time layer to interrupt.

The hazard is not decorative — measured, a trap does cost health through a status
(`domain_fixtures.gd:_fire` → `StatusApi.resolve`, `status/api.gd:391`), and the zone behind
it costs health too (`environment_field.gd:_resolve`). The seam below the trigger is closed.

## Decision

**A trap's trigger is PRESENCE inside its authored footprint. A button may inspect a trap; it
may never detonate one.**

- **The trigger condition is overlap, evaluated per movement step**, against the fixture's
  authored `bounds` — the same frame the fixture is realized into an `Area2D` (ADR 0073).
  There is no second trigger vocabulary: `telegraph_s > 0` for a trap is what makes presence
  armable at all.
- **The state machine is one-way: `armed → telegraphing → spent`.** Presence arms it, the
  authored window elapses, it fires once and is spent for the run
  (`domain_fixtures.gd:181-183`, ledger at `STATE_KEY`, `domain_fixtures.gd:60`). It never
  re-arms, so a player is never taxed twice for one mistake.
- **A step that both enters and fully crosses the footprint in one frame still arms.** This
  is the rule `DomainFixtures.arm` already implements by always arming on the first call
  regardless of `delta` (`domain_fixtures.gd:160-164`) — it is preserved because a trap that
  fires on the frame it is touched is the untelegraphed hazard ADR 0075 refuses.
- **What the button does instead:** `arm_fixture` becomes `inspect_fixture`, which returns
  exactly what `DomainFixtures.telegraph` already returns (`domain_fixtures.gd:290-317`) and
  mutates nothing. Inspecting is free and safe, which is what makes looking at a trap the
  *right* play rather than a mistake.
- **A choice-triggered trap is a different kind and is refused.** If a trap ever needs the
  player to *do* something, it is authored as a puzzle fixture (`kind = puzzle`, which already
  answers wrong with an interruption and never with health — `domain_fixtures.gd:20-24`). The
  closed set stays three kinds (`domain_fixtures.gd:100-102`), so "a trap that fires on an
  action" is an authoring error rather than a new code path.

### Zones keep presence too, and they have always had it

`_apply_zones` runs at run entry and on **every room visit** (`domain_boot.gd:296`, `:368`),
so a zone already taxes a player for being in the room — but it taxes the whole room rather
than the authored `bounds`, which is the next finding below.

## Consequences

- **`ARM_TICK` is deleted** (`domain_explore.gd:168`); the elapsed time that used to arrive as
  a per-press `delta` arrives from the same per-frame tick ADR 0089's `StatusLoop` already
  owns. No second clock is introduced, and the trap's window stops being a UI concern.
- **Standing in a zone's `bounds` becomes a decision, not a room tax.** `domain_boot.gd:486-487`
  applies every zone the room authors with no overlap test against `zone.bounds`; ADR 0075's
  "zones are volumes, not globals" is therefore true of the data and false of the application.
  Fixing that is the trigger's second half and is owed to the same change.
- **A player who inspects every trap before touching one now pays nothing, and a player who
  charges across a room pays the full window.** That is the intended asymmetry, and it makes
  reading the floor the rewarded skill.
- **The `Arm` verb survives as `Inspect`**, so ADR 0075's boundary promise has a UI surface
  without inventing a thirteenth facade verb.