# 0261 A world is an authored universe above the save slot: many characters may share one world and the clock does not care which body carries it

- Status: Proposed
- Date: 2026-10-05
- Amends: ADR 0259 (the clock rides the shared world store — kept, and this says what a WORLD is)
- Depends on: ADR 0128 (the save envelope), ADR 0113 (a stable durable world id), ADR 0173 (one clock), ADR 0169 (a lifespan is a magnitude)

## Context

ADR 0259 settled *where* the clock persists: the save envelope's shared world store, a
seventh `WORLD_KEYS` entry beside holdings/market/custody/soul/anchor/polity. That answer
is body-independent already, which is what an era-spanning clock needs.

It does not say what a **world** is. Today `envelope.actor` and `envelope.world` are one
envelope: one character, one set of ledgers, one clock, one save slot. That is a single
character living in a single universe, and it cannot express a player who wants several
characters in one universe, or who wants to leave a universe behind and start again in
another.

ADR 0161's epoch overlay already assumes the answer: `WorldEpoch` is keyed by a world and a
retired world gets a **successor** rather than being deleted. A world is therefore already
a thing in the model — it simply has no identity above the save slot yet.

## Decision

- **A world is identified by a stable `world_id`, and it sits ABOVE the save slot.** A save
  slot is one CHARACTER; a world is what that character lives in. The direction is not
  cosmetic: the clock and the six ledgers must survive the loss of any single body, and a
  slot that owns them cannot express "three characters, one universe".
- **Many slots may name one `world_id`.** That is the multiverse case: several characters
  playing the same universe see the same clock and the same ledgers. A slot that names a
  different `world_id` is somewhere else entirely, and its clock does not interact.
- **The clock belongs to the WORLD, never to the slot.** ADR 0259's mechanism is kept and
  reinterpreted: the shared world store is reached through the `world_id` a slot names, so
  two slots on one world read one clock. Which body happens to be carrying it is not a fact
  the clock stores — the answer to "what year is it" must not change because the hero was
  rebuilt.
- **The clock is still a COUNT of periods, still advanced only by the composition root, still
  forward-only.** Nothing in this ADR relaxes ADR 0259 §3–5. A world is a bigger container,
  not a second clock: `TimeLadder` remains the only converter and no world may store years.
- **Creating a world is authoring, not generating.** A world is born from an authored seed
  and a set of authored `.tres`, exactly as a domain is (ADR 0072); "new universe" means a
  new authored seed, never a procedural one. That keeps a world reproducible from its id.
- **Leaving a world is not deleting it.** A slot may stop naming a `world_id`, and the world
  keeps its clock and its epoch until the player explicitly retires it. ADR 0170's rule that a
  retired world is retired-not-deleted is the same rule one level up.

## Consequences

- ADR 0259 stands. This says what a world is, not where its clock lives.
- A slot gains a `world_id`, and `save_slot.gd` gains whatever addressing that needs. Two
  slots may now share ledgers, which is the first time that is possible and therefore the
  first time a ledgers test can disagree with itself — `save_round_trip` must cover two
  slots on one world.
- A Transcendent's millennia outlive every body it has worn, which is the case the whole
  clock programme exists to represent. Before this ADR that was unrepresentable.
- A world is a natural save-scoped migration boundary: a change to world-shaped data
  affects every slot naming that world, which is easier to reason about than a change that
  affects every slot everywhere (ADR 0128's rule that a migration must never rewrite an
  actor payload).
- **Deferred, not decided:** whether two characters on one world can ever MEET (that is a
  multiplayer question, and this ADR only makes the shared state representable); how a world
  is listed or switched in the UI; and whether a retired world can be un-retired. None of
  them changes the shape above.

## Rejected

- **A world per slot, permanently.** One universe per character is what the tree has today,
  and it is the thing the player asked to be able to leave behind.
- **The clock on the actor.** ADR 0259 §1 already refuses it: `module_data` dies with the
  body, so a Transcendent's world date would reset on every rebirth.
- **A world that generates its own content on creation.** A procedurally generated world
  cannot be reproduced from its id, so two slots naming it could disagree — which is the
  failure a shared clock exists to prevent.
