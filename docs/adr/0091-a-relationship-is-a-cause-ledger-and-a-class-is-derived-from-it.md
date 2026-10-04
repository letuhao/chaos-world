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
