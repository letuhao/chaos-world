# 0256 A first impression is seeded once, and an NPC's own ledger holds what it feels toward the player

- Status: Proposed
- Date: 2026-10-05

## Context

The owner named attraction and pursuit as a headline goal: **an NPC pursues the player
because she is a beautiful fairy, or has a special body, or her clan is rich.** The audit
that preceded this ADR measured the gap rather than assuming it:

- **No attraction concept existed anywhere.** Grepping `romance|court|suitor|attract|betroth|marriage|love`
  across `game/src` returned prose and two comments that named a relationship layer as
  future work (`bloodline_state.gd:71`, `bloodline_resolver.gd:21`). There was no field,
  no state and no code.
- **The only intimacy was player-initiated and one-sided.** `bound_in_intimacy`
  (`social_cause_catalog.gd:246`, +6.0 standing, +0.5 trust) and
  `modules/fertility/seduction.gd:122` record what two people did together — that is not
  the same as an NPC pursuing someone.
- **No gender, appearance or attractiveness field existed** on `NpcDef` or `Actor`, and
  `NpcDef` carries only `npc_id, display_name, inhabitant_id, tier, faction, tags, realm_id,
  base{}, stages[]`.

The direction was equally thin. ADR 0091 records as an **accepted cost** that
`SocialApi.apply_cause` writes one direction only, and in practice the entire NPC→player
direction was one hardcoded line: `BrotherhoodOath` writing `accepted_the_oath` to the
npc's own ledger (`social_brotherhood.gd:53,232`). There was no general case.

The reference research into the genre anchor (太吾绘卷) supplied the mechanic: **初见好感
is a SEEDED value** — base 3000, +300 per 10 charm, +3000 if the player is female, +6000
for friendly-sect clothing, −6000 for nudity — applied **once at meeting**, not
continuously. It also supplied three failure modes to design against: alignment affiliation
barely touches affinity; players find courtship incoherent when **traits gate it
invisibly**; and the 忠贞不渝 trait "cannot be courted **and** is very hard to lose", a
double gate on exactly the pursuit fantasy. Economy-derived affinity was the worst case of
all — one suitor's gifts cost 3.5M+ gold.

## Decision

### 1. The seed is a field on the NPC's ledger, and it is not the bond

`SocialAttractionSeed` holds one number per (npc, player) pair on the **NPC's own**
`module_data`. It is not standing, not trust and not a rung of `SocialBondClass`, and the
suite asserts the two never move together.

**What it may read — a closed list, and nothing else.** `seed_about` takes a flat
dictionary and honours only `SocialAttractionSeed.READ_KEYS`: `race_tags`, `bloodline_tags`,
`clan_standing`, `sect_tags`. Every input is a property of *who the player is*, fixed for
the character.

**What it may NOT read, and each line is a closed door:**

- **Not standing.** There is no standing argument anywhere in the file.
- **Not anything re-equippable** — no clothing, equipment, inventory, position, realm or
  stats. A seed readable from equipment is not an anti-farm rule with a hole; it has no
  anti-farm rule.
- **Not generation.** The player has no `sex` field. Rather than invent one for the seed
  specifically, **the generation is not an input at all** — which also means the gendered
  term the genre anchor carries is deliberately absent, and that absence is a decision
  rather than an oversight.
- **Not a function or a callable**, so a seed cannot reach out and read per-frame state.

**The friendly-sect term is the one deliberate exception to "nothing re-equippable"**, and
it is narrow on purpose: a sect is a *membership*, memberships are not re-equippable, and
its magnitude is a fraction of the base. Changing sect to farm it costs a whole standing
move on an institutional bond.

**"Her clan is rich" is served by clan STANDING, never by wealth.** Clan wealth is not a
field anywhere in this repo, and introducing one to feed an attraction seed would put a
money number on the reason a person likes somebody — the economy-gated-affinity trap in
its purest form. `economy` is already in `social`'s registry deps, so an author who later
wants a genuine wealth term has a legal place to read one.

### 2. It applies ONCE, and the state that makes that cheap is existence

`apply_once` is a no-op whenever a seed row exists, **whatever the magnitude would compute
to**; the value is not even computed on a second pass. There is no delta path, no refresh
verb and no decay. So the seed is identical on the first meeting and the thousandth, and
the verb itself reports `already_seeded` — the refusal is observable rather than intended.

### 3. The NPC→player direction is general, and it is a COLLABORATOR, not a facade verb

`SocialApi` and `NpcApi` are both at the 12-method cap (`rules.MAX_FACADE_PUBLIC_METHODS`)
and `tools arch` fails above it, so **neither grew**. The pursuit surface is four
collaborators in `social/` reached from `app/pursuit_app.gd`, which is the
`BrotherhoodOathApp` precedent (ADR 0196) exactly.

**`PursuitLedger` is not a second `SocialState` and holds no standing.** The regard axis
already lives on the npc's `SocialState` bond and is already bidirectional by type; the
existing mirror already writes there. What did not exist is the material that is *not*
regard: an impression that happened once, a disposition, and a claim. Putting standing here
too would be the ADR 0066 failure with a new name.

The general mirror is `PursuitStance.note_disposition`, the only writer of dispositions —
where `BrotherhoodOath` hardcoded one act for one verb.

### 4. The two gates are at different rungs, and neither is hidden

Courtship needs **both** a CONFIDANT on the *npc's own* bond (read through `SocialApi.gate`
at `SocialBondClass.CONFIDANT`, which is `PROMOTION_MIN_CLASS` — the ladder's own bar read
before the act, never a stat) **and** `OFFER_SEED_AT` on the seed. `PursuitStance.read`
publishes which of the two failed, so an affordance can say so before the player commits.
There is no trait that silently halves or doubles this, which is the direct answer to the
invisible-gate and double-gate findings.

**We deliberately do NOT couple gain and loss.** The genre's 情有独钟 trait reduces
affinity-gain 10–30% **and** affinity-loss 20–60%: hard to win is also hard to lose. Here
regard is an ordinary authored cause ledger, so a botched courtship is recoverable by doing
something else worth doing. A romance with no exit is a punishment, not a tragedy.

### 5. Exclusivity: yes, and it is per-claimer and structural

**An NPC may hold at most one claim against the player**, because
`PursuitLedger.claims` is keyed by player id — one slot, so a second claim overwrites the
first. Exclusivity decided by a threshold that could drift is a rule that eventually is
not a rule; this one cannot be two at once by construction, which is the shape
`BrotherhoodOath`'s `ledger.answered()` already chose.

**It is not global.** The genre's unfaithful-triad traits multiply pursuit difficulty
×500–2000%, i.e. it treats multiplicity as a trait. We do not: **several NPCs may pursue the
player at once.** The owner's headline is "an NPC pursues the player", the genre mechanic is
many suitors each individually gated, and a global one-partner lock would turn every other
suitor into dead content. The coupling this creates is deliberate — three suitors are three
independent confidant bonds, so the cost of pursuing many is that many bonds must be
earned — and it is the cost the ladder already prices.

### 6. Refusal is possible and it costs, following BL-0745

`PursuitClaim` is `BrotherhoodOath` a second time, deliberately: a stranger cannot be
claimed; the answer is read off the ledger with **no RNG**, so it is reproducible from a
save and cannot be re-rolled; refusal is the **default** for anyone who asks early and is
reachable with no authored content; and the exchange is one-shot.

**Refusal costs the PLAYER** −3.0 standing and −0.1 trust as the authored cause
`refused_the_court`, charged to the player's own bond — smaller than `refused_the_oath`'s
−4.0/−0.15, because being declined is a bad afternoon while a refused oath is a broken
word, and still a third of `FRIEND_AT`, so it is felt.

### 7. The distinct-KIND rule was not weakened, and pursuit is not a gift-farm bypass

All three courtship causes carry **`kind: court`**. Six answered courtships are six acts of
**one** kind, so `SocialBondClass.FRIEND_DISTINCT_CAUSES` tops that bond at an
ACQUAINTANCE however large the total, and **none of them names a class** — `shared_brotherhood`
remains the only shipped cause carrying `promotes_to`. Courtship also never out-earns
deeds: `answered_the_court` (+2.0) is worth less than being saved from death (+6.0),
because the player earns the first by being wanted and the second by being good. If that
ever inverts, the ladder is being priced by desirability.

### 8. Tier scoping, and what an untracked NPC cannot do

`PursuitStance.PERSISTENT_TIERS` names `story`/`major` — a named set rather than a tier
comparison, per `NpcTier.COMPOSED`. A `minor` composes on interaction and may carry one
seed; a `transient` composes and **writes nothing at all**, which is stronger than a row
nobody reads. The boot seam seeds on `npc_tracked` for every tier, and
`PursuitLedger.forget` drops a retired npc's rows, so an unobserved interest costs one
bounded dictionary row that dies with its owner.

**An untracked NPC cannot hold a claim, cannot refuse a player, cannot persist anything,
writes nothing to the player's ledger, and is never scanned for.** These five are a named
list (`untracked_limits`) asserted by the suite, so widening one is a review prompt. Note
the shape of the refusal limit: an untracked NPC has nothing for a refusal to cost against,
which is the whole reason it is safe for it to have no refusal.

### 9. No number reaches the player

Per decision 3, `PursuitStance.read` publishes `word`, `actions`, `may_court` and `reason`
— strings, bools and `StringName`s. The `numbers` key exists **solely** to hold the debug
read, and is populated only when `debug` is passed explicitly, which is the full debug
read hidden by default behind a user setting. The suite walks the whole published tree
recursively asserting no `float` or `int` appears at any depth, then re-runs it with
`debug` to prove the number is gated rather than absent.

## Consequences

- **The owner's sentence is now mechanically true**: an NPC can form a first impression of
  the player from who the player *is*, and act on it.
- **Re-equipping, changing sect and re-meeting cannot move an impression.** The state that
  enforces this is the seed's existence, so there is no code path for a farm to grow out of.
- **Both ledgers of a courtship move in one call**, the same mutuality contract ADR 0091
  deferred to the caller's transaction and `BrotherhoodOath` paid.
- **A refusal is a decision the player can see coming**, published by
  `PursuitApp.eligibility` before they commit, and it costs.
- **Cost this ADR accepts deliberately:** the seed cannot express player gender, so the
  genre anchor's largest single term (+3000 for a female player) is unavailable until a
  `sex` field exists on `Actor` — which is owned by `npc/`, not by this change.
- **Cost this ADR accepts deliberately:** no clothing term, so "friendly-sect clothing"
  and "nudity" are not modelled. Both are re-equippable, which is precisely the reason the
  seed refuses them.
- **Cost this ADR accepts:** `PursuitApp.compose` reads the tier from its **caller**, not
  from the `.tres`. An authored tier and the tier composed at are separate facts; conflating
  them would let a content file widen what persists.
- **Open, and deliberately not built here:** a player-facing pursuit panel. `ui/` is a pure
  consumer and `PursuitApp` is the contract it would render against; the copy carries no
  numbers because the read model cannot express one.
- **Open:** the alignment matrix does not touch affinity. The research found that to be the
  genre anchor's best-documented shortcoming, and it is a real design question here — it is
  recorded in the backlog rather than answered inside a feature that does not own the axis.