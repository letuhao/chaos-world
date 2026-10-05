# 0091 A relationship is a cause ledger and a class is derived from it

- Status: Accepted
- Date: 2026-10-03

## Context

The brief: an npc carries social and relationship stats, **the same as the player**, stored as an extension of the shared actor base. `Actor` already had `relationships: Dictionary` (a partner-id to float map) and `set_relationship` / `affinity_with`, but nothing wrote it, nothing read it, and nothing could answer a question it was supposed to answer.

`DEF-0009` records exactly this: "tags and relationships are not observable — no stat provider reads them yet." The gap was not a missing reader. It was that one float per partner cannot express what a cultivation world's relationship actually is, and — the load-bearing problem — **a total is buyable**. Any model where standing is a single additive score has a player answer to it: gift-spam the merchant until the number crosses a threshold. The repo has already rejected this shape twice (ADR 0022 on the social-stat trap, ADR 0062's rule that a gate reading a stat is a gate an item can satisfy).

The second problem is symmetry. If the player has a relationship system and npcs have a "disposition field," every future feature needs two code paths and the two will disagree.

## Decision

**A bond is a ledger of authored causes plus two axes. The relationship class is a pure function of those, derived on read and never stored.**

- `SocialCauseDef` (authored `Resource`) is the only writer of a bond. `standing`, `trust`, `persistent`, `promotes_to`. A cause is a named act — `sparred_in_combat`, `gifted_item`, `honoured_a_debt`, `betrayed_oath` — so "why do these two hate each other" survives a save and a reload.
- `SocialBond` holds two axes, **standing** (do they regard you) and **trust** (will they rely on you), plus a **floor** per axis and the cause ledger. Standing and trust are distinct because a famous liar has high standing and no trust, and because price reads standing while teaching reads trust.
- `SocialBondClass.classify(standing, trust, distinct_kinds)` returns one of nine classes, positive (`stranger → acquaintance → friend → confidant → sworn`) or negative (`suspect → hostile → grudge → nemesis`). **Nothing stores it**, so two actors who both fought the same boss cannot disagree about what that made them.
- **The anti-farm rule caps the whole positive ladder**, and it is enforced at the top of `classify` rather than at the friend step — writing it at the friend step alone leaves a large total skipping the guard entirely, which is the hole this ADR exists to close.
- **Reaching `friend` takes two distinct KINDS of act, not two distinct causes** (`SocialCauseDef.kind`). Counting causes was the original rule and it did not hold: a merchant's ledger offers several gift-tier causes, so two of them cleared a two-CAUSE bar while both were the same act — buying something. A friendship rests on `gift` + `combat`, or `gift` + `oath`. `SocialBond.kinds` is the sticky set the rule reads, and it round-trips; a save written before it existed falls back to one kind per cause, so an old ledger lands on the class it always did.
- **A gate reads the ledger, never a stat.** `SocialApi.gate(actor, requirement)` evaluates `bond_at_least`, `trust_at_least`, `standing_at_least`, `caused_by`, `all_of`/`any_of`/`none_of` against the ledger. A stat can be satisfied by an item; a ledger cannot. The aggregate verbs read their children under `"of"`, the key every other gate in the repo uses, and count **children** rather than unmet reasons — a reason count compared against a child count made `any_of` refuse whenever one child passed and another failed with two reasons.
- **Decay moves each axis toward its floor**, never toward zero. A persistent cause (`honoured_a_debt`, `shared_brotherhood`) raises the floor, so time moves a bond toward the promise it was given rather than toward a stranger.
- **Symmetry is a fact about the type.** One `SocialState` per actor, in `module_data[social_state]` — the player and every npc carry the identical type, so "npcs have social stats, same for player" needs no second code path to stay true.
- **No core schema bump.** The ledger rides the `module_data` block `Actor.to_dict` already round-trips (ADR 0027), so core never names a social type and `SCHEMA_VERSION` stays at 4.
- The provider emits **module-owned ids only** (`social_reputation`, `social_reach`, `social_trust`). A provider's contribution replaces the baseline of the stat it names (ADR 0026), so emitting a core id here would silently overwrite what the mind path derived.

## Consequences

- Gift-spamming a merchant cannot buy a friendship, and the test that proves it is a suite assertion, not a review comment.
- A quest can gate on `caused_by: spared_in_combat` — "did you ever let him live" — which a threshold on a total can never express.
- A nemesis you genuinely admire is representable: negative standing, positive regard recorded on the cause ledger, no axis that has to be bent to say both.
- The relationship can decay without being erased, which is the difference between a grudge and a stranger.
- **Cost this ADR accepts:** the class ladder is nine fixed rungs, so a design that wants "seven shades of cool" authors a cause, not a rung. That is the intent.
- **Cost this ADR accepts:** `apply_cause` writes one direction only. The mirror is the caller's transaction, because how a merchant regards you is not the same fact as how you regard the merchant, and the module that owns the interaction is the one that knows whether the other party felt it.
- `SocialState.regard` is a read model for institutions (a clan, a sect) and is **not** a second writer of the clan module's own standing (ADR 0064). Reconciling those two is open, not decided here.

## `shared_brotherhood`: deliberately deferred, not wired (BL-0745)

**`promotes_to` works. What does not exist is a player act that produces `shared_brotherhood`, and inventing one is a product decision this ADR does not make.**

`SocialBondClass._promoted_class` reads the field correctly and is covered: a bond whose axes have earned a confidant and whose ledger carries a brotherhood promise classifies as `sworn`, the promise round-trips through a save, and the anti-farm rule still caps the whole positive ladder above it (`tests/modules/social/test_social_promotion.gd`). **The ladder's top rung is engine-reachable and player-unreachable.** The shipped catalog authors exactly one cause carrying `promotes_to`, and the four production `apply_cause` callers — `modules/sect/api.gd`, `modules/nation/api.gd`, `modules/fertility/seduction.gd` and `app/auction_standing.gd` — apply membership, office, conception and auction causes. None applies a personal oath, because none owns a player act that would mean one.

**Why it is deferred rather than wired.** Every existing cause is an act a *system* already observes: you joined, you were promoted, you conceived, you won the lot. `shared_brotherhood` is the first cause whose whole content is that **someone agreed to it**. That means the player must be able to *offer* it, the npc must be able to *refuse* it, and the refusal has to cost something or the act is a button. None of that exists: dialogue is deferred by `DEF-0014` and ADR 0092 declines to smuggle a conversation tree through `NpcStageDef`, there is no consent ledger, and no `app/` verb carries an offer. A brotherhood bolted onto the existing tally path would be precisely the thing this ADR exists to refuse — a top-of-ladder class granted by a repeatable call, with the anti-farm rule holding only because no one thought to repeat it.

**The design question, stated so it can be answered rather than re-derived.** *What does a player DO that swearing brotherhood with a specific person requires, and what does refusing cost?* Concretely: is an oath offered at a stage threshold (`sworn_servant` and its `oaths_sworn` counter already imply one for Elder Wei), at an authored quest step, or through a dialogue act? Is refusal passive (nothing happens) or costly (standing, trust, an opportunity)? And is the promise **mutual** — ADR 0091 leaves the mirror to the caller's transaction, so a one-sided `apply_cause` makes the *player's* regard sworn while the elder's is untouched, which is a second question the answer has to settle.

**What this costs while it is open.** Every `SocialApi.gate` authored `at_least: SWORN` is permanently unreachable from play, exactly as it is today. That is recorded here rather than discovered later: the field is correct, the engine path is correct and tested, and the missing piece is a player-facing act nobody has designed. Wiring a cause nothing produces, or removing `shared_brotherhood` and `promotes_to` to stop the dead rung from reading as a bug, would both be worse than saying so.

### Correction (2026-10-05, npc/social ledger reconciliation) — appended, nothing above is edited

**Line 43's "four production `apply_cause` callers" is still four. This section records what
changed, because the same four sites are cited by BL-0745 and BL-0751 and both had drifted
into wrong arithmetic on top of a correct site list.**

The count and the sites re-measure clean: `modules/sect/api.gd:820`,
`modules/nation/api.gd:664`, `modules/fertility/seduction.gd:137` and
`app/auction_standing.gd:221` are the only production callers, all real code and none a
comment. (Line 43 names `nation/api.gd` without a line; the call is at `:664`, not the `:563`
BL-0715 cites.) What is false is what those sites produce, and it is the distinction BL-0751
got wrong and this section's own "None applies a personal oath" is now ambiguous about:

- Two sites write **institution** bonds: `sect` and `nation`.
- `fertility/seduction.gd:137` applies `bound_in_intimacy` (**+6.0, personal**) — but it is
  the **success branch of the very attempt `can_meet` gates**, so it is behind a closed door.
- `app/auction_standing.gd:221` applies `won_auction` (+3.0), `outbid_in_auction` (−1.5) and
  `defaulted_on_a_bid` (−6.0) — **personal** bonds between two actors, live in production.

So "none applies a personal oath" is still true and remains the finding; what is wrong is any
arithmetic built on "production applies only institution ids", which two ledger entries did.
**The surviving gap is narrower than either stated:** the causes that clear
`Seduction.REQUIRED_STANDING` (6.0) and are applied to a person have no production call site —
`gifted_item`, `helped_in_combat`, `spared_in_combat`, `taught_technique`, `honoured_a_debt`,
`protected_from_death`, `shared_brotherhood`. None of the seven is named by any authored file
under `game/data`. Auction causes top a bond at an **acquaintance** regardless of total,
because all three share `kind: market` and `SocialBondClass.FRIEND_DISTINCT_CAUSES = 2` counts
distinct kinds.

**BL-0745's `blocked` classification is CONFIRMED by this pass, on both halves.**
`shared_brotherhood` still has no producer outside the catalog and the tests, and the design
question in line 47 is still unanswered. Nothing in this correction changes it; it is recorded
so the confirmation is on the ADR rather than only in a ledger row.

### Resolution (2026-10-04) — BL-0745 closed by ADR 0198. Nothing above is edited.

**The repo owner ruled: build it, mutual and consent-based, with a refusal that costs.
ADR 0198 answers all four questions and `shared_brotherhood` now has a production verb.**

- **The act** is `BrotherhoodOathApp.offer` — put the oath to a named person. A **friend may
  be asked**; only a **confidant may swear it**, which makes the refusal the default outcome
  for an early offer rather than a rare branch. The answer is read off the bond through
  `SocialApi.gate`; no dialogue tree was invented (DEF-0014 stands).
- **Mutual** is literal: the player's ledger takes `shared_brotherhood` and the npc's takes
  `accepted_the_oath`, in the same call. Both sides are asserted to read `Sworn`. This is the
  "the mirror is the caller's transaction" cost above, paid by `BrotherhoodOath`.
- **Refusal costs** an authored `refused_the_oath` (-4.0 standing, -0.15 trust) on the
  **player's** bond — two-thirds of `FRIEND_AT`, 30% of `CONFIDANT_TRUST`. `kind: oath`, so
  refusal cannot be farmed up the ladder. The tests assert the axes actually moved, so
  removing the charge is red while the return value still says `refused`.
- **Eligibility** reuses `SocialGate` through the facade at two rungs and refuses with
  `no_bond` / `not_friend` / `not_confidant` / `already_answered`. **No second gate system**
  — the BL-0690 lesson about `"of"` vs `"requirements"` applies to every gate here.

**A consent ledger** (`ConsentLedger`) rides the player's `module_data`, recording that an
offer happened and the cause id charged — **never a standing value**. The bond remains the
only copy of every number (ADR 0066). **Neither facade grew**: `NpcApi` is at 12/12 and
`SocialApi` at its cap, so the exchange is a `social/` collaborator reached from an `app/`
verb, which is where ADR 0091's "the mirror is the caller's transaction" said it had to go.

**The distinct-KIND rule was not weakened to make this work.** `test_a_history_of_nothing_but_oaths_never_reaches_sworn`
applies six oath causes — all `promotes_to: SWORN` — and the pair still reads `acquaintance`.
