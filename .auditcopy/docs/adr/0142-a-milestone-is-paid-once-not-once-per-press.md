# 0142 A milestone is paid once, not once per press

- Status: Accepted
- Date: 2026-10-04
- Amends: ADR 0115 (a commit must never reinforce the anchor it creates)

## Context

ADR 0115 removed `strengthen_anchor()` from `WorldAnchor._commit_inside_world`
because the flag the commit stamped was exactly what the next realm's gate demanded.
It left `MindTraining.strengthen_anchor` as the only production route to
`anchor_strengthened`, which made the flag the milestone — and then left that verb
with no guard at all.

So presses 2..N each consumed the realm's channel elixir for an
`improve_stability(0.1)`, and that stability cannot fail a gate:

- `InsideWorld.is_stable` reads `>= 0.5`, and a committed anchor is created at
  exactly core's default of 0.5, so the first press already cleared it.
- `MindAnchor._commit_inside_world` REPLACES the world on a tier change, so the next
  commit discards the stability outright and the next anchor starts from 0.5 again.
- Its only live reader is `Tribulation._arena_quality` — a tenth of one percent per
  elixir.

A player holding five elixirs lost all five for a number nothing spent.

## Decision

- **"Already done" is `inside_world.anchor_strengthened`, read through one published
  predicate, `MindTraining.anchor_reinforced`.** `strengthen_anchor` refuses when it
  is true. ADR 0115 already defined the milestone as the flag; nothing read it.
- **The refusal is before the consume**, so a repeated press costs nothing.
- **The guard is per ANCHOR, not per actor or per run.** The next tier's commit
  creates a fresh, unpaid anchor and the milestone is payable again — otherwise the
  gate ADR 0115 restored would be unreachable at every tier past the first, which is
  the soft-lock in the other direction.
- **This is core's own "one artifact rather than a ratchet" rule
  (`WorldAnchor._commit_inside_world`) applied to the verb that pays for it.**
- **The refusal is an answer the player can act on, not a silent no-op.** The facade
  returns `bool`, and it is at its 12-method cap, so the milestone publishes no
  reason string of its own. It does not need one: the anchor gate
  `MindCultivationApi.preview` already publishes reads `value: true` with an empty
  `outstanding` from the moment the press succeeds, which IS the milestone's state.

## Consequences

- The R19-R30 traversal presses the milestone on boundaries that commit no new
  anchor. Those presses are now free refusals, which the traversal asserts as the
  contract rather than assuming every press succeeds.
- Raising an inside world's stability is a genuine gap and is NOT what this verb is
  for: nothing in the module may spend the milestone to do it. Stability has no
  priced owner.
- `anchor_reinforced` is on `MindTraining`, not the facade, so `ui/` cannot read it.
  The screen hides the button on realm and tier alone
  (`mind_cultivation_screen.gd:201`) and therefore still shows a button that
  refuses. Recorded in the backlog rather than widened here.