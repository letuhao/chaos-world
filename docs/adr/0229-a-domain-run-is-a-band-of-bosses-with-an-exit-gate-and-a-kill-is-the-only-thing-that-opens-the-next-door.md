# 0229 A domain run is a band of bosses with an exit gate, and a kill is the only thing that opens the next door

- Status: Accepted
- Date: 2026-10-05
- Resolves: the encounter-loop question behind BL-0210 and BL-0634
- Depends on: ADR 0076 (an encounter is a stat-resolved exchange), ADR 0219 (tier is the
  band), ADR 0216 (what a domain pays), ADR 0228 (the player's blow)

## Context

Measured against the code, **a domain run already has a shape** — nobody designed it, it
fell out of `LootState`'s six rules:

- **E2** (`loot_state.gd:19-21`): a band that has not been cleared grants the next run, or
  resumes the one in flight. Re-entry at or below a cleared band is refused.
- **E3** (`loot_state.gd:19-21`): **the next boss spawns as soon as the previous one is
  defeated**, whether or not its reward was picked up. `_advance` finds the first undefeated
  boss and respawns, or marks the band cleared (`loot_state.gd:739-769`).
- **E4**: abandoning discards the in-progress boss and resumes at the first boss with no
  reward yet.
- **E1**: exactly one payload per `(domain, boss, tier, run)`, and the id is deterministic.

So the loop is already: *enter a band → fight its bosses in authored order → each kill mints
one reward and spawns the next → clear the band and the tier is spent forever*. That is a
correct and deliberately one-shot shape (ADR 0219 argues it).

**What is missing is that the loop is invisible to the map.** A band's bosses are
`LootTier.boss_tables` entries (`loot_tier.gd:40`) and nothing on the map, in the room list,
or in the minimap names which of them is still standing. `DomainMinimap` marks a `boss` POI
per **room tag** (`domain_minimap.gd:39-45`), which is a different vocabulary from
`boss_tables`. So the player can be standing in a domain they have already beaten three
bosses of, with no way to know what is left, and the domain's own `population()` lists
inhabitants the `loot` run knows nothing about.

**And the two halves of the run answer to different systems.** The boss is a dictionary in
`loot_state["active"]`; the placed creature is an `Actor` in the domain run's roster. A kill
on the placed creature writes nothing to `loot`; a kill on the boss writes nothing to
`domain`. Neither is readable by the other, and that is the whole reason a player cannot tell
whether they are making progress.

## Decision

**A domain run is a BAND OF BOSSES with an EXIT GATE. A kill is the only thing that opens the
next door. Nothing else advances a run — and the run's progress must be READABLE from the
place the player is standing.**

### The loop, one line each

1. **Enter** a band: `LootApi.enter_domain` (rule E2). One authored encounter per domain.
2. **See what is left.** The read model publishes `remaining` (the undefeated `boss_ids` of
   the active band) alongside the room the player is in. A map that cannot answer "what is
   still standing" is a corridor, not a run.
3. **Fight**, one press per blow, on the actor path (ADR 0228).
4. **Kill → mint → advance** (rule E3). The kill is the transition; nothing else is.
5. **Clear** the band: the last undefeated boss falls, the run ends, the tier is spent.
6. **Exit** is free and costs nothing (`act_leave` → `LootApi.abandon`, rule E4 — "discards
   the in-progress boss, never a reward").

### What each kill is WORTH, and who owns the row

| A kill of | Advances | Pays | Written by |
|---|---|---|---|
| the **active boss** (`loot_state["active"]`) | the band, rule E3 | one payload, rule E1, from the authored table | `LootState._defeat` |
| a **placed hostile** | nothing. The map does not clear for blood | **nothing today** | nothing yet |
| a **placed rival cultivator** | nothing | nothing today | nothing yet |

**This is the honest answer to "does killing an actor inside a domain progress anything":
today, no — and that is correct.** Rule E1 keys a payload on `domain/boss@tier#run`
(`loot_state.gd:162-163`), so a placed creature has no claim token and cannot mint without
one. Progress in this game is *band progress*, not *body count*: the run is a fight against a
named antagonist at a named tier, and the mobs on the way are the walk. Giving every rat a
loot roll would turn the run into a grind, which is exactly what ADR 0216 rejects in the
other direction.

**What a placed kill DOES change is the map — and that is its reward.** A hostile
inhabitant's body leaving the room is observable, and it is the only progression the
traversal layer is entitled to:

- the room's **population** drops by one and the read model republishes it
  (`DomainApi.population`);
- a hostile-only room can therefore become a **refuge** — the thing ADR 0208's `refuge`
  marker promises and ADR 0075's environment gates assume is possible;
- **discovery** persists (ADR 0207's fog: the room is remembered), so the change is legible
  on the remembered band rather than only while the player stands in it.

That is a real, small, legible reward — and it costs no new currency, no new table and no
second progression ledger.

### The exit gate

**Clearing a band is the gate; the exit is not.** A player may leave at any moment and loses
only the in-progress boss (rule E4). There is no "you cannot leave until you clear this"
rule, because a game that traps the player in a fight has replaced a decision with a
punishment. What the gate buys is the **tier**: rule E2 refuses re-entry to a cleared band,
so the run is a thing that happened once.

## Consequences

- **`remaining` is the smallest possible fix to invisible progress**, and it is a read, not a
  write. It composes with `DomainMinimap`'s existing POI vocabulary without inventing a
  second marker set.
- **A boss kill and a mob kill are deliberately different verbs with different payoffs**, and
  the UI must not present both as "Encounter cleared". One pays a table; the other pays the
  room.
- **The reward half of BL-0634 is untouched and must not be routed through the map path.** A
  boss that dies through the actor path (ADR 0228) still mints nothing, because `_defeat`
  reads `active["vitality"]`. What I need from the reward agent is stated in ADR 0228: a
  named `LootApi` verb taking a resolved encounter id, or a stated rule that a body kill
  pays nothing.
- **`abandon` must stay rule E4 and stay free.** Walking away is the pressure valve that
  makes committing to a band a decision rather than a formality.
- **No restock, no layer field, no timer** (ADR 0219 already decided; this does not reopen).

## Rejected

- **Every hostile drop pays something.** Rejected: it turns 336 authored tables into a grind
  economy and breaks rule E1's one-payload-per-encounter invariant at the same time. The map
  change is the honest small reward.
- **A kill counter on the band as progress.** Rejected: "7 of 9 things" is a quantity with no
  meaning the player can act on. The authored boss list is the thing they can act on.
- **Making the exit refuse until the band clears.** Rejected on the anchor's own terms: a
  player who cannot retreat cannot make a commitment, and commitment is what the anchor
  measures (ADR 0212's four levers).
- **Reading progress off `duels_won`.** Rejected: that counter includes the training dummy
  the fight page mints (`fight_loop.gd:206-222`) and mercy-spared duels, so it would report
  a run the player is not making.

## What would change my mind

- An owner ruling that a domain run is a **sweep** rather than a band — "clear every hostile
  in the place" — which would make the population read model the progression ledger and the
  placed kill the load-bearing one. That is coherent; it just is not this one, and it would
  move ADR 0228's reward answer from "nothing" to "the run".
- Authored content that makes a band's `boss_tables` the only hostile thing in the domain.
  Then the two vocabularies coincide by accident, `remaining` is redundant, and the map
  change is invisible — worth re-measuring before building it.
