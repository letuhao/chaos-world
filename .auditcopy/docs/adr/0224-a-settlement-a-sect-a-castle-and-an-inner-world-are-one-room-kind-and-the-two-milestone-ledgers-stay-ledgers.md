# 0224 A settlement, a sect, a castle and an inner world are one room kind, and the two milestone ledgers stay ledgers

- Status: Accepted
- Date: 2026-10-05
- Resolves: BL-0255, and the conceptual half of BL-0219 (ADR 0163's seam is not re-litigated)
- Confirms: ADR 0163's decisions (a settlement is a `RoomDef` of `kind = settlement`; an inner
  world is a domain template, not a `WorldState` replacement and not a view over it)
- Narrows: BL-0255's wording. "Mapped over the existing `WorldState`" is the WRONG FRAMING and
  this ADR says so plainly.

## Context

The genre convention that works: a sect compound, a walled town and a cultivator's personal
realm are **the same kind of place, at different scales and with different owners** — a room
with residents, services and rules. What the genre avoids is modelling the private realm as a
*second world* with its own map system, its own save slot and its own navigation, because the
moment it does, it is a second game with its own balance, its own bugs and its own save
compatibility. The private realm stays interesting because it is **your** version of the same
place, gated by cultivation progress — not because it is somewhere new.

The repo already holds the right model in two pieces that do not agree on what they are:

- ADR 0073/0163: a settlement is a **`RoomDef` of `kind = settlement`**, naming an institution
  through a `fixtures` entry (`domain_settlement.gd:59` `settlement_ref`, `ref_kind` closed to
  `sect`, `domain_settlement.gd:66`). Implemented, read-only, writes nothing.
- `InsideWorld` (`core/inside_world.gd:10-20`) and `WorldState` (`core/world_creation.gd:26-39`).
  **Both are milestone ledgers of scalars.** `InsideWorld` is `tier`, `size`, `stability`,
  `qi_density`, `time_flow`, a `laws` dict and two anchor flags — no rooms, no graph, no
  coordinates. `WorldState` is the same shape one tier higher, plus `laws[]`, `layers[]`
  (a `WorldLayerState` is an id, a name and a `size_ratio` — a *band*, not a room),
  `inhabitants[]`, `resources`, two rates. Both serialize into `Actor.to_dict()`
  (`actor.gd:304-306, 380`) and both gate breakthroughs (`WorldAnchor.stage_met`).

**So BL-0255's premise is wrong in its verb.** "A settlement room mapped over the existing
`WorldState`" cannot be executed: there is nothing in `WorldState` to map *over*. A map
projected onto a ladder index is a room whose geometry owes itself to a realm number — a
second hierarchy wearing the first one's clothes. ADR 0163 rejected (b) and (c) for exactly
this; BL-0255 re-imported (c) in the language of "the room is the physical stand-in".

## Decision

**ONE concept, one room kind, and the ledgers keep their own job. A settlement room is the
*place*; `InsideWorld`/`WorldState` are the *milestones that earned it*; they are joined by an
authored id, never by a projection.**

1. **A settlement room IS what ADR 0163 says it is**, and this ADR adds nothing to it: a
   `RoomDef`, `kind = settlement`, carrying a `settlement_ref`. A **sect** is a settlement with
   `ref_kind = sect`; a **castle** is a settlement with an empty `ref_kind`; an **inner world**
   is a settlement whose template is bound to the actor's realm tier by *authoring*, not by
   code. One kind, four authors, zero new room kinds, zero new def classes.
2. **BL-0255's `world_anchor_ref` is REFUSED as an authored field on `RoomDef`.** The
   machinery it would need already exists: a settlement already names a thing outside itself
   through `fixtures`, with a closed `ref_kind` set, resolved by an injected `Callable` and
   refused by name (`domain_settlement.gd:66, 99-107, 152-159`). A second ref kind
   (`world_anchor`) is the same shape with a different word in it, and it is exactly the "new
   `ref_kind`" ADR 0163:100 put out of scope.
3. **The correct replacement for BL-0255's proposal:** if an inner-world room should grant
   the services of a created world, that is **`app/`**, one-way, on a milestone event —
   never a read from the map and never a read from the room by `world`. ADR 0163:70-72 already
   states this: *"Binding the two, if it is ever wanted, is a one-way write from a
   `WorldState` milestone into a run's `domain_id`, and belongs to `app/`."* **That sentence
   is the decision.** A milestone OPENS a template; the template does not project the milestone.
4. **The ledgers are never read by `domain`.** `InsideWorldProvider` reads
   `inside_world_qi_density` as a stat (`inside_world_provider.gd:9-16`); `WorldApi` verbs
   mutate `actor.world`. Neither is a place, and `domain` declaring either would be a cycle
   `tools arch` cannot see (`BARE_REF_UNITS` excludes `modules/*` — AGENTS.md:160).
5. **A settlement is `social` by definition and admits no hostile spawn** — already
   `RoomDef.default_band_for` (`room_def.gd:88-90`) and `is_hostile()`. A player fights
   *beside* a sect, not inside it, which is what keeps "my home" from becoming a difficulty
   dial.

## Consequences

- **BL-0255 closes as REFUTED-IN-WORDING, corrected in substance.** Its goal — "not a second
  system" — is right and is met; its mechanism — "mapped over the existing `WorldState`" —
  is impossible, and the ADR 0163 framing (a milestone opens a template) replaces it.
- **BL-0219's conceptual half closes.** Its remaining half is the sect *simulator* (roster,
  economy, politics) and stays open — a simulator is `sect`'s to own, and this ADR explicitly
  does not authorise one (ADR 0163:91-99).
- **The vocabulary holds for every screen**: `{}` = no settlement;
  `authors_no_settlement_ref` = a castle naming nothing; `unknown_settlement_ref` = a sect that
  does not resolve (ADR 0083's three-state rule, already implemented at
  `domain_settlement.gd:104-110`). ADR 0209 decides the *surface*; this ADR does not revisit it.
- **Trade-off rejected: one `InnerRealmDef` resource as a first-class "personal realm"
  content type.** Rejected — it is the second-system failure the genre pattern exists to
  avoid, and it would need its own spawner, minimap and scene realization.
- **Trade-off rejected: let `WorldState.layers` become rooms** (a layer gaining exits and a
  rect). Rejected because `layers` are read by exactly one thing, `WorldAnchor`'s
  proof-a-breakthrough-built-it (`world_anchor.gd:228, 268`); making them spatial would put a
  realm-gate's input under the map's authorship.
- **What would change my mind:** if a personal realm ever needs to *persist across sessions as
  a place* — rooms the player built, kept, and returned to — it stops being a template and
  becomes authored content in the player's save. That is a save-schema decision (ADR 0128),
  not a room-kind one, and it would need its own ADR.

## Not decided here

- Which template an inner world binds to per realm tier (authoring, not code).
- Whether `app/` wires the one-way milestone→template write (ADR 0163:72 says it is out of
  scope, and this ADR leaves it there).