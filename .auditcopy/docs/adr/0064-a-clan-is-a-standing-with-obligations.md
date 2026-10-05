# 0064 A clan is a standing with obligations, and it is the vocabulary social features will read

- Status: Accepted
- Date: 2026-10-02
- Depends on: ADR 0062 (a race is a body plan), ADR 0063 (a bloodline is a diluted inheritance)

## Context

Race (ADR 0062) and bloodline (ADR 0063) both describe a single actor. Neither says anything about
the actor's place in the world, and the world already has factions (ADR 0047) that describe
politics. So the obvious question is "why not just use factions".

Because a faction and a clan are different objects that the current world model conflates:

- A **faction** is a set of actors with a shared stance. It is flat — `qi_dao`, `body_dao`,
  `mind_dao` — and `Actor.faction` already points at one. It answers "which side are you on".
- A **clan** is a *lineage that persists across generations and holds a position*. It answers "who
  are your people, what did they earn, and what do you owe them". A clan has a founding bloodline, a
  standing that can be lost, and internal ranks — none of which a faction has.

If clans are folded into factions, every later social feature (reputation, marriage, inheritance of
position, rival houses, NPC lineage) has to reinvent them on top of a flat string id. Making the
clan a first-class object now is what makes those features *composable* instead of repeated.

## Decision

- **A clan is an institution, keyed by `clan_id`, and membership is a first-class actor fact.** It
  is **not** `Actor.faction`. `faction` stays the political alignment (ADR 0047); `clan` is the
  family. An actor may belong to no clan, and that is the normal starting state.
- **A clan carries a founding bloodline**, authored in its `ClanDef`, and it reads that bloodline's
  purity on a member as a **standing multiplier**, never as a stat the clan grants. This is the
  hinge that connects the three systems: a clan does not hand out power, it hands out
  *recognition*, and recognition scales what the member's own bloodline is worth.
- **Standing is a two-part integer: `standing` (earned, can fall) and `rank` (position within the
  clan).** Rank is discrete and authored (`outer`, `inner`, `core`, `heir`, `head`); standing is a
  continuous integer that a clan action moves. Rank is not derived from standing — a member can
  hold a high position on little standing, which is what makes it political rather than numeric.
- **Standing is symmetric with obligations: a clan owes a member `patronage` resources, and a
  member owes the clan `duty`.** Both are authored in `ClanDef`, both are readable, and neither is
  enforced by an automatic payment — the settlement verb belongs to the social features that land
  later. The clan publishes the *terms*; it does not collect them.
- **Clan is born from bloodline and never writes back to it.** Admission can require a purity
  threshold (`min_purity`), but passing never raises purity (ADR 0063). A clan cannot manufacture
  a lineage it does not have.
- **`clan` is its own module** with `contracts` + `core` + `race` + `bloodline` deps — it reads
  both — and nothing depends on it yet. It is the top of the lineage stack, so nothing can depend
  on it without a cycle.

## Consequences

- Race → bloodline → clan is a strict, acyclic dependency stack, and each module is independently
  testable because each only reads the ones below it.
- Later social features (reputation with factions, marriage, succession) read `ClanApi` and never
  re-derive what "my clan is" — that is the whole reason it is a module now.
- Standing is a vocabulary: reputation systems can compose against `standing` without owning it.
- A member of a high-standing clan with a diluted bloodline is a legitimate, interesting character
  — the clan recognises them, the lineage does not empower them. That gap is the point.
- Adding a clan is authoring a `.tres` under `game/data/clans/`, never code.