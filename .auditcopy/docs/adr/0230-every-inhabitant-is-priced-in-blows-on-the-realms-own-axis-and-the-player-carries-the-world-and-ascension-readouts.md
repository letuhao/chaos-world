# 0230 Every inhabitant is priced in blows on the realm's own axis, and the player carries the world and ascension readouts

- Status: Accepted
- Date: 2026-10-05
- Resolves: BL-0315
- Depends on: ADR 0074 (one constructor, a role is a tag), ADR 0050 (realm strength is
  authored data keyed by realm id), ADR 0199 (boss vitality is the anchor pool at its realm's
  authored power), ADR 0228 (the player's blow)

## Context

**BL-0315's claim is half stale and must be re-measured before anyone works it.**

The stale half: "the player actor carries no ascension or world stats; only domain-spawned
inhabitants do." `ActorFactory.build` attaches **all three** core high-tier providers for
every actor it mints — `InsideWorldProvider`, `WorldCreationProvider`, `AscensionProvider`
(`actor_factory.gd:70-72`) — with a docblock arguing exactly this point ("a provider mounted
only by the paths that reach R19+ is a provider no other actor has",
`actor_factory.gd:59-69`). `spawn_inhabitant` and `spawn_npc` both route through `build`
(`actor_factory.gd:410,460`), so player, npc and mob share one spine. The four reds in
`tests/core/test_world_anchor.gd` it cites are asserted **green** there today
(`test_world_anchor.gd:353-379`).

**The half that is true, and is the real defect: magnitude is not on one axis.**

- The player is priced by `RealmScaling` (`realm_scaling.gd:25-32`): seven stats including
  `MAX_HEALTH` and both attacks multiplied by `RealmDef.power`, the 551x authored table.
- A domain creature is priced by the **same** `RealmScaling` (`domain_spawner.gd:124`) — so
  *attack and defence* are on one axis.
- But a creature's **survivability** is not: nothing sizes a placed creature's health pool.
  `attach_core_resources` gives it `50.0 + physique * 10.0` at `physique == 0` (measured and
  recorded at `fight_loop.gd:555-560`), against a hero pooling ~250 at the same realm.
  `FightLoop._size_opponent` fixes this for MINTED opponents with a flat `Stat.MAX_HEALTH`
  offset of `blow * ANCHOR_BLOWS_TO_KILL` (`fight_loop.gd:586-600`) — and deliberately does
  NOT apply it to authored actors, because "an authored actor's vitality is content"
  (`fight_loop.gd:546-554`).
- Meanwhile a `loot` boss is not an `Actor` at all: it is a dictionary whose vitality is
  `HITS_TO_KILL * BASE_HEALTH * RealmDef.power` (ADR 0199), and the shipped corpus measures
  **1875.0 minimum to 1654380.0 maximum** across 160 encounter files.

So a hero, a domain mob and a domain boss are on three different pools. That is the honest
shape of BL-0315 in 2026-10-05: **one realm axis for offence and defence, and three unrelated
places to stand for how long you last.**

## Decision

**There is ONE magnitude axis — `RealmDef.power`, keyed by realm id — and a creature's
survivability is priced in BLOWS against that same axis. The player carries the same core
high-tier providers every inhabitant carries.**

### 1. The providers: already built, now stated as a rule

`ActorFactory.build` is the **only** place a core high-tier provider is attached, for every
actor, and `add_provider` appends unguarded (`actor_factory.gd:67-72`). No enrolment verb
re-attaches. This is not a change; it is the ruling that keeps BL-0315 closed, so no agent
re-reads the entry and re-adds the providers somewhere reflexively.

`AscensionProvider` is attached for everyone from birth, including an actor with no world —
"no ascent = 0.0" is a value, not a hole (`test_world_anchor.gd:375-379`).

### 2. The axis: a creature's pool is `blows × a blow`, on the ladder

- **A placed creature's pool is a FLAT offset on `Stat.MAX_HEALTH`, sized in blows, and it
  COMPOSES with `RealmScaling`'s realm MULT** — exactly what `_size_opponent` already does and
  explains (`fight_loop.gd:563-571`). Both sides then scale together up the ladder, which is
  what keeps `hits_to_kill` near the anchor at every realm rather than only at R1.
- **That is a change of OWNER, not of formula.** Today the sizing lives in `FightLoop`, which
  is a *contest* and may not size an authored body. A placed creature's magnitude belongs to
  content and must be read from `InhabitantDef` — a new authored field, **in blows, not in a
  scale**. `blows_to_survive` is the same unit `HITS_TO_KILL` already is, so the corpus and the
  code speak one language.
- **`RealmDef.power` is never derived, and no new table exists.** A creature at `spirit_unity`
  reads its own authored blows and gets the ladder's multiplier for free, exactly as the hero
  does. This is the move ADR 0199 made for bosses and for the same reason: the alternative was
  normalising the engine's damage, which makes a magnitude a computed curve — the category
  error ADR 0050 exists to prevent.

### 3. The player carries the world and ascension readouts, and so does everyone

Already true. Recorded because BL-0315 asks for a decision and the answer must be durable:
**nobody may attach a core provider anywhere but `ActorFactory.build`.** A stat that reads
`0.0` on a mob because only the player's builder mounts it is exactly the dead surface this
repo keeps producing.

## Consequences

- **The hero and a mob become comparable numbers instead of two vocabularies.** A player who
  reads "this creature survives 25 of my blows" and "I survive 30 of its blows" is getting
  the fight's shape before it starts — which is the point of a same-ladder design.
- **The boss dictionary is not brought onto the actor path.** ADR 0199's numbers are content
  and correct, and `loot` may not depend on `combat_engine`. What changes is only that a
  *placed* creature and the *hero* share an axis; the run's boss stays `loot`'s, and ADR 0228's
  reward seam is where they meet.
- **`FightLoop._size_opponent` stops being the only sizer.** A placed creature is sized from
  its def, so the loop's copy is for minted opponents only — which is already what its
  docblock says, and this makes the code agree with the prose.
- **The guard that closes BL-0315 is structural, not argumentative:** a test asserting a
  `spawn_inhabitant` actor carries all three providers, plus one asserting a placed creature
  and the hero report near-equal `hits_to_kill` at two realms.

## Rejected

- **Normalise engine damage so the 551x ladder stops mattering.** Rejected by ADR 0050 and
  ADR 0199 both, and it is the only option that would have made a creature's authored pool mean
  the same thing at R1 and R30. It makes a magnitude a computed curve.
- **A new per-realm creature scale in `core/`.** Rejected: a fourth power-shaped table is
  exactly what AGENTS.md says needs an ADR *and* does not need here, because `RealmDef.power`
  already is the axis.
- **Give the player a dedicated `player_scale` multiplier.** Rejected: it is a second composer
  on the shared actor model, and it would make the hero incomparable with every other `Actor`
  — the premise of ADR 0074.
- **Keep `FightLoop` as the sizer for placed creatures too.** Rejected: it would size content
  from code and quietly disagree with an authored `InhabitantDef` the moment one exists.

## What would change my mind

- An owner ruling that a domain creature's durability is **narration, not arithmetic** — the
  map changes, the creature leaves, and no pool is ever priced. Then `blows_to_survive` is
  dead authoring and the honest answer is a one-blow outcome plus a corpse marker.
- Measured evidence that a placed creature's authored `base` already yields a near-constant
  `hits_to_kill` across the ladder without an offset — in which case the multiplier is a
  second opinion and should be deleted rather than moved.
