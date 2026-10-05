# 0254 Alignment is a three-axis matrix scored from action and read identically by every npc

- Status: Proposed
- Date: 2026-10-05
- Amends: nothing. Extends ADR 0091 (bond = cause ledger) and ADR 0066 (one authored
  constant, one file) with a read model layered on the same cause ledger.

## Context

**No moral axis existed.** Grep for evil/alignment/corrupt returned only `Stat.DAO_HEART`
(a will-scaled breakthrough stat) and `DualCultivationStats.CORRUPTION` (a cultivation
pool). `destiny_def.gd:31` has a `KARMA` tag nothing tracks. So "evil path → npc hates
you" was structurally unavailable, not merely under-tuned.

**`destiny/` owns conduct and is unreadable, and its ledger is the wrong shape.**
`SocialApi` cannot reach it; the only two cross-module mentions are prose comments
(`npc_state.gd:5`, `social_gate.gd:131`). Its earn is categorical and exactly-once
(`destiny/api.gd:47-55`), exclusive within a group (`:77-79`), permanent with no revoke,
and written **only by character creation** (`app/character_creation_flow.gd:288,291`) —
character creation, not play. A matrix needs to accumulate, accumulate many different
things, and be readable during play.

**All ~31 shipped causes are acts one actor did to another.** None expresses cruelty,
moral alignment or romance; nothing a matrix could read.

## Decision

### Where it lives: `social/`, as a read model over the cause ledger

- **Not `destiny/`.** It would need `social/ → destiny/` through `DestinyApi`, which is at
  its twelve-method cap (`rules.MAX_FACADE_PUBLIC_METHODS`), so a thirteenth verb is not
  available and one would have to be retired — a change to another agent's module for a
  feature that module cannot use. Worse, the data model is wrong: exactly-once exclusive
  branches cannot express "many small acts each mattered a little", and a no-revoke
  branch cannot express redemption. **Reported, not taken:** if `destiny/` later wants to
  gate content on alignment, the one-line change is `game/src/modules/destiny/api.gd` —
  add a `destiny/alignment.gd` collaborator reached from `social/`, leaving the facade at
  12. No `destiny/` file is edited by this change.
- **Not `core/`.** `core` may reference only `contracts/`, so an alignment matrix in
  `core` cannot read `SocialCauseDef` — the input it exists to weight. Putting it in
  `core` would mean a second cause vocabulary, which is the ADR 0066 failure mode with a
  moral hat on.
- **Not a new module.** One module = one reason to change. Alignment has no state of its
  own to own: it is *derived* from the ledger `social/` already owns, so a new module
  would be a second writer of the same fact — precisely what `SocialState.regard` was
  opened for and must not be duplicated by.

### The axes — three, chosen for what the fiction and the data already distinguish

| Axis | Fiction | Why this axis and not another |
|---|---|---|
| `justice` 刚正 | oaths kept, debts honoured, ground defended | the repo already separates an **oath** from a **market** act via `SocialCauseDef.kind`, and ADR 0091 separates **standing** from **trust** — so "kept your word" is a distinction the data already makes |
| `mercy` 仁善 | lives spared, pupils taught, the weak sheltered | `spared_in_combat` and `protected_from_death` are already authored as *persistent* — a mercy is remembered, a gift is not |
| `dominion` 霸道 | the powerless used, a supplicant's trust spent | the inverse of mercy and the ONLY axis corruption reads; also the only one a new cause can reach on its own |

A fourth axis was rejected: 唯我 (self-sovereignty) has no authored cause and no stat it
could be distinguished from `dominion`, so it would be an axis that is always zero.

### The combination rule, in one sentence, in one file

> **An authored cause moves each axis by its authored whole-number weight, scaled by
> `REPEAT_TAPER ^ times_this_actor_has_already_been_judged_by_it`.**

That is `SocialAlignmentMatrix.contribution(cause_id, seen, scale)`. Authored by NAME,
never derived from a cause's `standing` and never from an index (ADR 0050) — a −6.0 cause
is not automatically three units of moral weight, and **no `market` cause appears at all**:
winning a lot is not a moral position, and a bidder's hundred auctions must not be a moral
career. The `seen` counter advances only for a cause the matrix judges, so an unjudged
repeat cannot taper a judged one.

### Score AND rate — both, because they answer different questions

The owner ruled for a score; that is what ships as the primary artifact. The rate table
exists because a score alone is inert in ADR 0091's world, where a relationship is a
ledger and nothing in `social/` currently *reads* standing to scale it.

- **Score** — the three axes, read by every NPC identically. This is the alignment.
- **Rate** — `RATES[band] = {goodwill, hatred}`, applied by `SocialAlignmentTrack` to the
  **one bond passed in**. Corruption halves goodwill and doubles hatred (太吾绘卷's most
  transferable idea), and `trust` is **never** swayed in any band.

Why both: a rate alone (太吾绘卷's 立场 stance) cannot express "many small things each
mattered a little" — it is a multiplier, and multipliers do not accumulate. A score alone
is a number nothing in this module would read. The pair is also the yin-yang rule applied
to rates: goodwill and hatred ship together, because shipping only the hatred half makes
corruption strictly profitable.

### Why it does not leak the way DOS2's does

**The leak was never caused by a global score; it was caused by a global score being
APPLIED globally.** DOS2's own modding docs warn that flipping an alignment *entity* makes
every member hostile to every player, and that members "in a different area of the map"
find themselves in combat "for no intuitive reason". The owner requires one score, so the
defect has to be designed out of the *application*, not the score:

1. **The score is identical for all NPCs** — one number, no per-NPC weight, no per-NPC
   personality vector. `SocialAlignmentTrack.apply_swayed(bond, cause, band)` takes one
   bond and one band; it has no handle on a third party, so a reaction cannot name one.
2. **It is spent on the pair, never broadcast.** A cruelty to a supplicant that makes you
   corrupt changes that bond and no other. The band applies to the *next* act's rate on
   *that* pair.
3. **No NPC has an alignment opinion at all.** Alignment is never written onto an NPC. The
   only thing an NPC's ledger holds is what they did to you — so there is no stored
   verdict for the world to flip.
4. **The change is always explainable by an act the player just performed**, which is the
   exact property DOS2's warning denies.

Asserted in `tests/modules/social/test_social_alignment_matrix.gd`:
`test_one_pairs_reaction_does_not_change_another_npcs_read` — after five cruelties the
supplicant reads `nemesis` at −35.0, an unrelated merchant's standing is byte-identical to
before the band changed, and a never-met stranger still reads `stranger`. Plus
`test_the_sway_verb_takes_exactly_one_bond_and_a_band`, which pins the shape.

### Anti-farm and convergence

- `REPEAT_TAPER := 0.5` — exactly 0.5 so a decay is exact in binary and a test can assert a
  literal sum. Eight gifts = +2.4765625, less mercy than sparing one life (+3.0); the
  eighth gift is worth 1/128th of the first. Genre-correct (太吾绘卷 ×20% above a
  threshold, 鬼谷八荒 halves per heart tier) and a linear accumulator would read 8.0.
- **Alignment cannot buy a class.** A bond's class still reads axes and distinct KINDS
  (`SocialBondClass.classify`), and alignment is not one of its inputs — so six oaths
  cannot buy a friendship, and a large JUSTICE total buys no rank either.
- `SEEN_LEDGER_LIMIT := 64` bounds the per-actor repeat dictionary, and `AXIS_CAP := 20.0`
  bounds every axis — both named constants, both bounding the save's growth.

### Two facade verbs, to twelve exactly

`SocialApi` measured **10/12** before this change, so both slots were available:

- `apply_cause_aligned(actor, partner_id, cause_id, scale)` — a **separate** verb, not a
  flag on `apply_cause`, so the four production callers (`sect/api.gd:820`,
  `nation/api.gd:664`, `fertility/seduction.gd:137`, `app/auction_standing.gd:221`) keep
  the un-swayed path byte for byte and whichever agent wires the NPC side chooses to swing
  it deliberately.
- `alignment(actor)` — the read model, three axes + band + both rates in one call, because
  a panel needs both and neither alone tells it what to draw.

`NpcApi` (12/12) and `DestinyApi` (12/12) are untouched.

### Persistence

Rides `SocialState`'s own payload under the `alignment` sub-key, so `Actor.to_dict` alone
is a complete save and `core` never names a social type (ADR 0027). A save written before
this change has no key and restores **neutral** — the safe direction: nothing is
retroactively corrupted by a build that added axes.

## Consequences

- "Evil path → the NPC you wronged hates you" is now expressible, and it is not expressible
  for anyone who did not wrong *them*.
- Five new authored causes close the acts that had no vocabulary: `cruel_to_the_powerless`
  (the only way to become corrupt), `betrayed_a_supplicant`, `sheltered_a_supplicant`,
  `kept_a_guest_safe`, `refused_himself_the_cup`.
- **Cost this ADR accepts:** the axes are per-actor and permanent-ish — there is no decay
  on an axis, only the taper on new acts. A player who does one cruelty keeps the memory
  of it forever. That is deliberate (a reputation that fades is a reputation nobody can be
  held to) and reversible in one constant if it proves wrong.
- **Cost this ADR accepts:** `apply_cause` is still the path four production callers use, so
  alignment currently influences nothing in live play. That is a wiring decision for the
  agent owning `npc/`, not a gap in the matrix, and it is why `apply_cause` is unchanged.
- **Not built, deliberately:** a per-NPC stance (reintroduces per-NPC weights — the owner's
  constraint forbids it); UI (not owned here, and `SocialApi.alignment` is the contract a
  panel needs); axis decay; a `karma` gate wired to `destiny/` (that module is read-only to
  this change).