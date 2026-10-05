# 0198 A sworn brotherhood is an offered pact that two ledgers move on, or a refusal that is charged

- Status: Accepted
- Date: 2026-10-04

Supersedes nothing. Answers the question ADR 0091 §"`shared_brotherhood`: deliberately
deferred, not wired (BL-0745)" left open, and leaves every line above it untouched.

## Context

ADR 0091 shipped a nine-rung relationship ladder and one authored cause,
`shared_brotherhood`, carrying `promotes_to: SocialBondClass.SWORN`. `promotes_to` has
two real readers (`SocialBond.apply`, `SocialBondClass._promoted_class`), so the
mechanism works and is covered — but **no production verb ever applied that cause**. The
ladder's top rung was engine-reachable and player-unreachable, and every
`SocialApi.gate` authored `at_least: SWORN` was permanently shut.

It stayed unwired for five audit rounds, and the reason was not an oversight. Every
shipped cause is an act a *system observes*: you joined, you were promoted, you
conceived, you won the lot. `shared_brotherhood` is the first cause whose entire content
is that **someone agreed to it**. A repeatable call that granted it would hand the top of
the ladder out from a button press — precisely the shape ADR 0091 exists to refuse.

The repo owner has ruled: build it, make it mutual, make it consent-based, and make
refusal cost something. This ADR records the four answers.

## Decision

### 1. The act is `offer_brotherhood`, and it is two beats

The player puts the oath to a named person. The offer is free and records itself; the
**answer** is read off the bond the two of them have actually built. No dialogue tree
(DEF-0014) and none is invented here — standing and trust ARE the answer, evaluated
through `SocialApi.gate` so the only statement of who may be sworn to is an authored
requirement.

**A friend may be PUT TO the oath. Only a confidant may SWEAR it.** That gap is the
design. It makes the exchange an exchange rather than a formality, and it makes the
refusal the *default* for anyone who offers early — reachable by any player, with no
authored content, by exactly the act the ruling names.

### 2. Mutual means BOTH ledgers move in the same call

ADR 0091 leaves the mirror of `apply_cause` to the caller's transaction. `BrotherhoodOath`
is that transaction: the player writes `shared_brotherhood` against the npc, **and the
npc writes `accepted_the_oath` back against the player**. Two `apply_cause` calls, two
`Actor`s, one agreement. A different cause id on the mirror, because "I swore with him"
and "he swore with me" are two entries in two ledgers, not one entry written twice.

This is possible only because ADR 0091 made the ledger symmetric by *type*. Both classes
are asserted from both sides — not assumed, because a one-sided implementation would read
`Sworn` on the player and `Confidant` on the elder, which is the shape ADR 0091's design
question named and refused.

A **witness** is the third leg: naming one writes `witnessed_an_oath` on the player↔witness
bond, so an authored `caused_by` gate opens on it and on nothing else.

### 3. Refusal is charged, and it is charged on the PLAYER

`refused_the_oath` is an authored cause (-4.0 standing, -0.15 trust) applied to the
player's bond with them. Being put to an oath and declined is something that happened to
*you*, and it is your regard the world records differently afterwards. Sized against the
ladder: two-thirds of `FRIEND_AT` and 30% of `CONFIDANT_TRUST`, so it is felt without being
fatal — the register of "he said not yet", not of being cast out.

It is a `kind: oath` cause like the acceptance, so a pair whose whole history is oaths
made and broken still tops out at an acquaintance. Refusing cannot be farmed into a
ladder.

### 4. Eligibility reuses the ONE gate system and names its reason

Two gates, both reading `SocialBondClass` rungs through `SocialGate.evaluate` via the
facade. `no_bond`, `not_friend`, `not_confidant`, `already_answered`, `unknown_npc` — every
refusal carries a reason, and the `unmet` array is the shared gate's own, so a panel
prints "Confidant, not Friend" without this module inventing a word.

**There is no second gate system.** That is deliberate: BL-0690 was a gate that read its
children under `"requirements"` while ten other modules use `"of"`, so an authored
aggregate gate opened itself. Nothing here aggregates, and nothing here reads a stat —
ADR 0062's rule is that a gate the ledger answers cannot be bought.

### The consent ledger records THAT AN OFFER HAPPENED — and nothing else

`ConsentLedger` lives on the player's `module_data` under its own key, so
`Actor.to_dict` is still the only save. A row carries the partner, the witness, the
outcome and the **cause id** that was charged — never a standing value. The bond is the
truth; the consent ledger says an offer was made and how it was answered. **Never a second
copy of a number** (ADR 0066).

An answered offer is one-shot. That is the anti-repeat rule: without it, offer → decline →
offer again is a button that mints the top rung on demand.

### The verb is in `app/`, and neither facade grew

`NpcApi` is at 12/12 and `SocialApi` sits at the cap, so neither may take a thirteenth
method (`rules.MAX_FACADE_PUBLIC_METHODS`). The exchange needs BOTH modules: it resolves
an `Actor` through `NpcApi` and writes two bonds through `SocialApi`, while `social/`
declares `["contracts", "core"]` and may not name `npc/`. So `BrotherhoodOath` lives
beside the facades and `BrotherhoodOathApp` — the verb a panel presses — lives in `app/`,
the one layer exempt from `LAYER_DEPS`. This is the `SoulArrivalMarks` shape (ADR 0190),
deliberately.

## Consequences

- `SWORN` is reachable by a player, through production, with a refusal that costs.
- A refusal is a **real, named, tested consequence**: the standing and trust assertions
  read the bond, so a future edit that removes the `apply_cause` in the refusal branch
  goes red while the return value still says `refused`.
- The anti-farm rule is not weakened. `test_a_history_of_nothing_but_oaths_never_reaches_sworn`
  applies six oath causes, all `promotes_to: SWORN`, and asserts the pair still reads
  `acquaintance`. The oath needs a career beside it, which is what makes the answer in the
  happy path an *earned* one.
- **Cost this ADR accepts:** there is no per-npc consent mood and no RNG. An answer is a
  pure function of the ledger, which means an elder's answer cannot vary with mood — the
  price of making an answer reproducible from a save and un-rerollable. It is also the
  price of not inventing the dialogue system DEF-0014 defers.
- **Cost this ADR accepts:** a sworn pair who later falls to a friend reads `Friend`, not
  `Friend (once sworn)`. ADR 0091's promotion is a ceiling re-checked on every read, and
  that is unchanged; a history of the act survives on the cause ledger, which is where
  "did we swear?" is answered.
- **Cost this ADR accepts:** the witness is a name, not a check. Nothing verifies the
  witness is present or willing; a content author who names one is asserting they stood
  there. A witness-eligibility gate is future work, not a hole in this.
- A second lane deliberately does **not** exist: there is no way to renew a brotherhood
  through this verb, because a renewal is a different act and would need its own authored
  cause. Refusing to author it now keeps the ladder honest.