# 0130 A soul re-embodies into an arrival it earned and the world never rewinds

- Status: Accepted
- Date: 2026-10-04
- Depends on: ADR 0065 (fate is earned, never chosen and never removed), ADR 0062 / 0109 (a
  race is a body plan that gates the paths it forbids), ADR 0127 (the soul outlives its actor),
  ADR 0129 (difficulty scales a fraction of what is carried)
- Resolves: the rebirth half of the soul feature

## Context

When a body dies with no guardian item spent, the soul takes damage and the player continues
as a new actor on a new arrival. The world does not rewind: what the first body built,
claimed, fought and depleted stays depleted, and every other actor's plans keep going.

The design pressure is ADR 0065, which forbids a picker over fates and destinies and makes
exclusivity within a group permanent. "The player selects a destiny path" cannot therefore
mean what it sounds like, and the feature has to be designed around that rather than by
weakening it.

Character creation exists and is real: `app/character_creation_flow.gd` asks one question —
how the hero arrived — and converts the answer into exactly one origin destiny. The screen
ships, but it is not routed, so no player reaches it. That is a hole in its own right and is
fixed in the same change.

## Decision

**A death costs the soul and never the world. The next body arrives into an origin the
module chose, and the ledger decides which — never the player.**

- **Death resolution is: spend a guardian if one is held, otherwise damage the soul and
  re-body.** A guardian is an ordinary consumable carrying a `guardian` tag, consumed through
  the existing items verb, which is all-or-nothing — so a refused spend costs nothing and the
  guardian path needs no new activation channel. A guardian-free death is the only thing that
  costs anything: the item is spent, integrity is untouched, and the incarnation does not
  advance.
- **The next origin is `SoulGate`'s answer, read from the ledger, not offered as a choice.**
  It is the first authored origin the ledger does not already hold, in authored order, with
  no randomness and no player input. Two souls that die identically get identical arrivals,
  which is what makes the rule testable.
- **The arrival is earned, and the ledger is the receipt.** ADR 0065 forbids a picker; it does
  not say an arrival can be earned only once ever. A new body carries an empty arrival ledger,
  so an origin in a different group is earnable without amending anything. Rebirth origins
  ship with no exclusivity group at all, because they are consequences rather than competing
  claims, and the gate's early return for an empty group is what makes them independently
  earnable.
- **A race is immutable for one body, and a new body legitimately re-answers it.** ADR 0062
  says a race is assigned once at conception and immutable for the actor's life — which is
  precisely a statement about one life. Rebirth mints a new actor, so the single existing
  write fires again. This is an amendment to ADR 0062's scope, not a contradiction of it, and
  it is why this ADR exists.
- **A death is a world fact and is recorded once.** It is written to the world fact ledger with
  a code-owned id, so quests and events can gate on how many times a soul has died. The write
  is registered with the fact-ledger writer census in the same change.
- **The world does not rewind, and there is no rewind verb.** Holdings, node conditions,
  resource depletion, institutional claims and every other actor's state are untouched by a
  death. There is no undo, no reload-into-the-past, and no branch.
- **Rebirth is a body swap, so every binding the old body held is re-bound explicitly.** One
  composition-root method swaps the actor for every screen, every attached module and every
  roster. A half-swapped body is the failure this names: the game reads two different actors
  and no test fails.

## Consequences

- **The guardian tag is authored content, not a new item category.** `ItemDef` already carries
  a tags field and no current rule reads it. An item the player must be able to find wants a
  source that is actually shipped — the gather route has no forager yet, so a guardian authored
  against it would be unobtainable in play while the acquisition audit counted it reachable.
- **Difficulty sets the cost, never the consequence.** ADR 0129's scalars scale how much
  integrity a death costs and how much a guardian is worth. They do not decide whether a
  death re-embodies, so a hard run is harder rather than different.
- **The creation screen must become reachable, and it is a boot-time screen rather than a nav
  route.** A routed screen must answer with a non-empty summary for the app's own actor, and
  the app's boot actor is not a created hero. Creation is therefore pushed by the composition
  root before the root route and popped on commit, and it must not gain a public mount method
  with no caller — which the reachability guard already fails on.
- **The multi-step creation program is bounded.** A returning soul re-answers presentation and
  affinity priority; it does not re-answer its arrival, and it carries the world fact ledger,
  institutional claims and its soul ledger forward untouched.
- **A repair anchor is owed.** A damaged soul needs somewhere in the world to be repaired, and
  the only building-adjacent module is `holdings` — at its facade cap, with no build verb at
  all. There is no building feature in this repo, so this is recorded as work rather than
  half-built here.
