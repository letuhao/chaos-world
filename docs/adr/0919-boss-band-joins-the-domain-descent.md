# 0919 Boss band joins the domain descent

- Status: Accepted
- Date: 2026-10-08

## Context

Domain runs and loot bands were parallel systems that never met: a descent
entered rooms with no fight in them, and bands were entered only from the
loot screen. A boss fought underground minted nothing because no band was
ever entered there — the shape BL-0634 reported, with the mint itself
proven healthy (all named pairs mint on the exact defeat path).

## Decision

- A node config naming `loot_domain` (+ `loot_tier`, default 1) enters the
  boss band through an app-installed loot seam (`WorldmapApi.install_loot`,
  same shape as the domain and gate seams) right after the run starts. A
  refused band unwinds the just-entered run: a descent never strands a run
  with no fight in it.
- The return abandons the band first (rewards kept by the module; a cleared
  band's `not_in_domain` does not hold the return), then leaves the run.
  The return entry carries the band flag, so bandless descents skip the
  leave entirely.
- Boot verbs `strike` (production `CombatApi.exchange`, seed from the
  player's cell) and `take` (pickup by the strike's encounter id) are bound
  for the screen; the actor is the root's own, like every other seam.

## Consequences

- Descent → fight → loot → pickup → return works end to end in-game once
  the screen binds Strike/Take (screen files held by i18n-migration; that
  half follows when `game/src/ui` frees).
- What this ADR does NOT do: key-reach funding (a gated band refuses by
  name), or band persistence across sessions (the band is run state; rewards
  persist as inventory).
