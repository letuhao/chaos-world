# 0181 Fate belongs to the soul and a rebirth carries the whole ledger rather than half of it

- Status: Accepted
- Date: 2026-10-04
- Depends on: ADR 0065 (fate is earned, never chosen and never removed), ADR 0127 (a soul
  outlives its actor and lives in an injected store), ADR 0130 (a soul re-embodies into an
  arrival it earned and the world never rewinds), ADR 0159 (an arrival is spent by the death
  that earns it), ADR 0134 (the consumer contract a caller may rely on), ADR 0113 (the fact
  ledger is the world's memory)
- Amends: the SCOPE of ADR 0065's "owned permanently", which was written about a single
  body's lifetime and had never been stated against a soul. Nothing in ADR 0065 is withdrawn
  and the ADR file is not edited; this is the cross-reference that scopes it.
- Resolves: the second of the two decisions DEF-0238 names as needing an owner ruling —
  "rebirth carries `world_facts` onto the new body while creation empties the destiny ledger,
  so after one death a counter reads 0 while its source fact reads the carried count and the
  monotone verb can never re-derive it"
- Consumes: `SoulDef.marks` (`game/src/modules/soul/soul_def.gd:32-34`), which is authored on
  all three shipped arrivals and read by NOTHING in `game/src` — the arrival marks were the
  hook this decision turns.

## Context

Two documents are each correct and together contradict each other.

ADR 0065 and `game/src/modules/destiny/` say a fate ledger is owned permanently. The ledger is
`actor.module_data["destiny_state"]` (`destiny_state.gd:21`), the only verb is monotone
(`api.gd:123-141`), there is no removal path, and `normalize()` may only drop an entry that is
unreadable or names content the catalog no longer ships (`destiny_state.gd:51-119`).

ADR 0127/0130 and `game/src/app/character_creation_flow.gd` say the opposite about what a death
costs. `SoulDeath._carry_facts` (`app/soul_death.gd:205-212`) copies the `world_facts` ledger
from the falling body onto the one it becomes — the same "the ledger has the actor's lifetime"
trap ADR 0127 names, acknowledged in the docstring, and fixed deliberately for facts.
`CharacterCreationFlow.build_forced` (`character_creation_flow.gd:191-218`) mints the new body
with `DestinyApi.attach` and therefore an **empty** destiny ledger, and its docstring says so
out loud: "the character's own destiny ledger starts empty, exactly as a first hero's does"
(`:176-180`).

So after one death the two memories disagree, and neither can be brought back into line:

- `WorldFact.count(body, "duels_won")` reads the pre-death count, because the fact ledger was
  carried.
- `DestinyApi.state(body)["counters"]["duels_won"]` reads 0, because the counter ledger was
  not.

A counter is not free-standing state. `DestinyProjection.COUNTER_FACTS`
(`destiny_projection.gd:29-56`) maps nine world facts onto nine fate counters, and the mapping
is a live subscription: `WorldFact.record` fires `DestinyProjection.on_fact_recorded`, which
is the only thing that has ever moved a counter (`destiny_projection.gd:242-246`). The value
in `counters` is therefore a *derived copy of the fact ledger*, and after a body swap the two
copies disagree while the derivation that produced one of them can never run again — the verb
is monotone and there is no re-derive. The player's codex reads one copy and a story gate reads
the other, and the same number is both permanently true and permanently zero.

**The framing of the problem is wrong about what is broken, and that changes the fix.** Nothing
is broken about the FACT ledger: carrying `world_facts` across a rebirth is correct and
measured (`soul_death.gd:154-170` records the probe: `before_swap=1`,
`after_swap_on_new_body=0`) and is what makes a second death count 2 rather than 1 forever.
What is broken is that the counter ledger — a projection OF the fact ledger — was left behind,
and that `build_forced` deliberately empties the ledger the codex renders. Those are two
separate half-measures, and fixing only one of them would still leave a player with a codex
that forgets.

So the question is not "which ledger wins". It is: **the fate ledger is one thing, and it
belongs to whoever the fate is about.** A fate earned by a deed was earned by a person, not by
a body plan, and the game already says so in the one place where it matters: the soul. The
fix is to carry the whole ledger, and to say plainly what that costs ADR 0065.

## Decision

**Fate belongs to the soul. A rebirth carries the entire destiny ledger — fates, destinies,
counters and history — onto the new body, and re-derives every projection from it. Nothing is
reset, nothing is re-earned, and nothing is copied by hand.**

This is Option A, taken in its strong form, and it is the only option that makes the two ledgers
stop disagreeing without inventing a rule for when one is authoritative.

- **The carry is a second copy of the same ledger, not a second ledger.** `SoulDeath._carry_facts`
  moves the rows; this change adds `SoulDeath._carry_destiny` beside it, which moves
  `actor.module_data["destiny_state"]` the same way. Nothing is summed, because both ledgers are
  monotone and a sum would report two duels for one (the duplicate-guard argument
  `_carry_facts:200-204` already makes). The carried copy is what the new body reports.
- **Projections are rebuilt by the existing `attach`, not by the carry.**
  `DestinyApi.attach` (`api.gd:39-45`) already normalizes the ledger against the current catalog
  and calls `DestinyProjection.apply`, which strips every `destiny:` contribution and rebuilds
  the stat modifiers and the `Actor.traits` mirror from the ledger. The carry only has to put
  the rows on the new actor **before** `adopt_actor` runs; the composition root's existing
  `DestinyApi.attach(actor)` line (`app/item_workbench_app.gd:553`, reached from
  `_attach_body_modules` on the rebirth branch) then does the re-derivation for free. Re-deriving
  by hand would be the ADR 0065 failure mode in reverse: a second stat composer.
- **Stat modifiers and `destiny:` traits DO cross the death, and they are applied to the new
  body's own stat stack.** A fate is the same fate in a smaller body, and the alternative — a
  codex showing an oath whose numbers silently vanished — is the bug, not the fix. The
  interaction with the new body's base attributes is the honest cost and is called out under
  Consequences.
- **An arrival destiny is still never granted, and still never earnable twice.**
  `build_forced` grants no `DestinyDef` and must continue to grant none: an arrival is a
  consequence recorded in `SoulState.origins`, and granting it through `earn_destiny` would put
  a rebirth into the `origin` exclusivity group and hand the player a picker ADR 0065 forbids
  (ADR 0159 measured this and kept the rule). What crosses is whatever the ledger already held.
  Because `DestinyApi.earn_destiny` is exactly-once and `DestinyGate.earnable` refuses an
  exclusive group for good (`destiny_gate.gd:60-74`), a destiny the soul already holds is
  already refused a second time — so "can an arrival destiny be earned twice" has the answer
  *no, by construction*, not by a new rule.
- **`build_forced`'s docstring is the thing that was wrong, and it is superseded here.** The
  claim "the character's own destiny ledger starts empty, exactly as a first hero's does" is
  true of the MINT and was read as true of the PLAYER. A first hero's ledger starts empty
  because nothing has been earned; a returning soul's ledger does not, and the sentence
  conflated the two. Superseded in place by this ADR; the code around it does not change.
- **The earn-only invariant is preserved exactly as ADR 0065 states it.** Stated plainly,
  because the question has to be asked: **this does NOT weaken ADR 0065.** Nothing in this
  change removes a fate, a destiny, a counter or a history row. `normalize()`'s drop rule is
  untouched. `DestinyProjection.strip()` remains reachable only from `apply()`. The invariant
  was never "a fate lives on one actor for the rest of time" — it was "nothing the game does
  takes a fate back", and a carry adds rows to a ledger; it removes none. What ADR 0065 does
  not address, and this ADR scopes, is **the LIFETIME** the word "permanently" is measured
  against: **owned for as long as the SOUL that earned it exists**, which for this game is the
  run, because a soul with no lives left is a soul that does not continue. That is the whole
  replacement claim, and it is narrower than ADR 0065's silence, not looser.
- **One append-only `module_data` key records the carry, and it is NOT a schema change to the
  save.** `module_data` is a `String`-keyed dictionary copied verbatim by `Actor.to_dict`
  (ADR 0027), so a new key is carried by an existing mechanism and needs no `Actor` field, no
  migration and no new envelope version. It exists so a save taken after a death can TELL that
  a carry already happened, which makes the operation exactly-once across a reload rather than
  best-effort within one process — the same argument `soul_death.gd:54-67` makes for
  `_died_bodies`, which it then declines to persist for a different reason.
- **Consumer contract (what `story` may rely on), restated for a gate author.** After this
  change, for any actor, `DestinyApi.state(actor)["counters"][c] >= WorldFact.count(actor, c_fact)`
  for every row of `COUNTER_FACTS`, and the two are EQUAL after any death. Therefore: a
  `counter` gate and a `has_fate` gate reading the same deed always agree; `DestinyApi.state`
  is the answerable one (ADR 0134 owns the surface); `WorldFact.count` remains the world's
  memory and is what a quest step or an event gates on; and a story consumer MUST NOT write
  either ledger to "fix" a disagreement — both are monotone and neither has a refund. A consumer
  may rely on `DestinyApi.attach` having been called on the body it reads, which the
  composition root guarantees for the fresh branch, the restore branch and the rebirth branch
  through one shared list (`item_workbench_app.gd:503-571`).

## Consequences

- **What a player sees: nothing, and that is the point.** After a death the codex
  (`ui/screens/destiny_screen.gd`, reading `DestinyApi.summary`) shows the same fates, the same
  destinies and the same counters it showed before, and the new body's stat panel shows the
  fate modifiers applied to its own numbers. The soul screen already says the body is new
  (`SoulApi.summary` publishes `incarnation`, and `CharacterCreationFlow.build_forced` returns
  `is_rebirth: true`), so the fiction already covers "you came back different". Nothing is owed
  to the player here that the game does not already show.
- **The one player-visible consequence worth naming: the new body is stronger.** Nine shipped
  fates carry flat or percent modifiers (`game/data/destiny/fates/*.tres`), and they now ride
  the second and third body as well as the first. Across a three-life ladder that is a real
  power curve with no authored source. This is the cost of Option A and it is not
  double-counted — `apply()` strips before it rebuilds, so a carried fate is applied once per
  body, never twice — but it is content balance, not correctness, and it belongs to whoever
  tunes `DestinyProjection` and the race ladder.
- **`SoulDef.marks` becomes live, and that is where authored rebirth content goes.** All three
  shipped arrivals already name marks (`the_walker_back_through_ash` → `soul_marked_once`,
  `the_one_who_was_carried_out` → `soul_marked_twice`, `debt_carried_forward`,
  `the_ledger_knows_your_name` → `the_ledger_knows_your_name`) and `SoulDef.marks` is read by
  NOTHING in `game/src` today — the field's own docstring says "the soul module never grants one
  itself; that is `destiny`'s ledger, on a body". It is an owed earn path, not owed UI: a
  rebirth arrival that grants no fate is an arrival with no authored identity in the module the
  whole world reads. **Granting a mark is an earn, and earns are exactly-once** — but the
  arrival ladder is walked ONCE, so a mark cannot be granted twice, and if the ledger is carried
  the grant would be an exactly-once no-op on the second visit anyway. Recorded as owed work,
  not built here.
- **Rejected, and why.** (A) *Keep fate per-body and amend ADR 0065 to say so* — this leaves
  the codex and the gate permanently disagreeing about a deed the player took, and no amount
  of prose fixes a counter that can never be re-derived. (B) *Carry only the counters, drop
  earned fate* — this is the worst of both: the numbers survive, the story does not, and the
  codex would report a duel count with no oath behind it. (C) *Re-derive the counters from the
  carried facts on the new body* — tempting, and rejected: it would need a lowering verb to make
  the re-derived value authoritative, which is precisely the removal path DEF-0112 refuses, and
  it would make `normalize()` able to lower a count because the player died.
- **What a consumer must NOT do.** No consumer may treat `counters` as recoverable: it is
  monotone, and a disagreement between the two ledgers is now a BUG to report, never a value to
  reconcile by writing. `story` in particular must gate on `DestinyApi.gate` (ADR 0134) and on
  `WorldFact.count` for world facts, and must not add a third place to remember either.
- **The test that proves this decision.** `game/tests/modules/soul/test_soul_fate_across_rebirth.gd`
  (new). The suite is named for the claim and asserts it in **one invariant and four guards**,
  each of which is RED against today's tree and GREEN after the change:
  1. **The invariant.** Record `duels_won` through the real bridge
     (`WorldFact.record(actor, &"duels_won", 3)` with
     `DestinyProjection.subscribe_to_fact_ledger()` installed, which is exactly what
     `item_workbench_app.gd:245` does), resolve a real death through
     `SoulDeath.resolve`, and assert on the NEW body that
     `DestinyApi.state(new)["counters"]["duels_won"] == 3` **and**
     `WorldFact.count(new, &"duels_won") == 3` — the two ledgers, equal, across the swap. This
     one case fails today with `0` against `3`.
  2. **Fate and destiny cross, and their projection is rebuilt rather than copied.** Earn a fate
     and an origin destiny through the real `CharacterCreationFlow.build` /
     `grant_origin`, die, and assert on the new body that `DestinyApi.fates(new)` and
     `DestinyApi.destinies(new)` are unchanged AND that `DestinyProjection.modifier_count(new)`
     equals what it was on the falling body. The second half is the one that catches a carry that
     copied rows without letting `attach` re-project — the numbers would be in the ledger and
     missing from the stat stack, which is the failure mode nothing else in the repo can see.
  3. **The earn-only invariant is still one-way.** After a rebirth, the old body's ledger and
     the new body's ledger are byte-equal under `DestinyState.normalize`, and a second
     `resolve` does not lower any counter or drop any entry — asserted by comparing the whole
     normalized ledger before and after.
  4. **An arrival still grants nothing.** Assert that after a rebirth
     `DestinyApi.destinies(new)` contains no id from `CharacterCreationFlow.origin_ids()` other
     than the one the first body earned, and that the new body's held-destiny set is exactly the
     old body's — which is the guard that keeps ADR 0065's exclusivity and ADR 0159's "an
     arrival is a receipt, not a claim" intact through this change.
  5. **No `soul -> destiny` edge is created.** The carry is performed in `app/`, which
     `LAYER_DEPS["app"] == {"*"}` exempts (`tools/arch/rules.py:27-32`), so `soul` keeps
     declaring exactly `contracts`, `core`, `items` (`tools/arch/registry.json:247-253`). A test
     asserting `soul`'s dependency set is the guard that keeps ADR 0127's refusal
     ("it may not depend on `destiny` … the edge becomes legal only when the soul carries the
     whole destiny ledger, which is a separate decision" — `soul/api.gd:30-33`) honest: this
     ADR takes that decision, and takes it the other way, by NOT creating the edge.
- **The save needs no schema change.** One new `module_data` key, carried by ADR 0027's
  existing verbatim copy. `Actor.to_dict` (`core/actor.gd:301-307,344`) and `from_dict` (`:397-398`) are not
  touched, no envelope version moves, and an old save with no such key normalizes to "never
  carried", which is exactly right: a save from before this change had a body that died, and on
  the next death it carries normally.
- **A second carry is a no-op, and the marker is what makes that true.** The carried ledger is
  already monotone and already exactly-once, so a duplicate carry cannot corrupt it — the
  duplicate guard `_carry_facts:200-204` gives is the same one. The marker key exists for the
  thing a copy cannot answer: whether this body has ALREADY been given its parent's ledger.
  Without it, a save/restore cycle across a death would re-copy a ledger onto a body that
  already had it (harmless today, but the next field added to the ledger could stop being), and
  the one thing that would catch it is a flag. The flag is advisory, not authoritative: the copy
  is idempotent either way, and the flag names which body was carried FROM.

## What a consumer (`story`) may rely on

| Claim | Where it comes from |
|---|---|
| `DestinyApi.state(actor)["counters"][c]` and `WorldFact.count(actor, fact)` never disagree after a death | this ADR; both ledgers are carried by one `app/` operation |
| A `counter` gate is answerable and monotone; it is the DERIVATION of a fact, not a second memory | `destiny_projection.gd:242-246`, ADR 0149 |
| A `has_fate` / `has_destiny` gate answer is unchanged by a death | this ADR; `DestinyGate.earnable` is exactly-once and exclusive forever (`destiny_gate.gd:60-74`) |
| `DestinyApi.attach` has run on any actor the composition root handed you | `item_workbench_app.gd:553` in `_attach_body_modules`, shared by the fresh, restore and rebirth branches |
| Writing either ledger to "correct" a disagreement is forbidden | both are monotone; no refund exists (ADR 0065, ADR 0113) |