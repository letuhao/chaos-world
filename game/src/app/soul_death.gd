class_name SoulDeath
extends RefCounted

## Resolves one player death: guardian, or soul damage and a new body (ADR 0130).
##
## ## Why this lives in `app/` and not in a module
##
## **It is a composition-root concern, and that is a decision rather than a fallback.** Four
## modules take part — `soul` owns the ledger, `items` owns the guardian spend, `difficulty`
## owns the cost, and `CharacterCreationFlow` owns minting a body — and a module may reference
## another only through its facade, so no module can legally orchestrate all four. `app/` may
## depend on anything (`rules.py` LAYER_DEPS), so the rule lives here and stays testable as a
## plain `RefCounted` with every dependency injected. It holds no state and declares no
## `_process`: the existing frame driver polls it, which is what keeps the tree at exactly three
## drivers (`tests/app/test_status_clock.gd`).
##
## ## The rule, in order
##
## 1. **A guardian is spent if one is held.** The item is consumed through the existing
##    all-or-nothing `items` verb, so a refused spend costs nothing, the soul takes NO damage,
##    and the incarnation does not advance.
## 2. **Otherwise the soul pays, and the world does not.** Integrity falls by the difficulty
##    share of the authored base cost, clamped by the authored cap. Nothing else is touched —
##    no rewind, no undo, no second chance.
## 3. **A new body arrives into the arrival the GATE chose.** This class cannot name an
##    arrival; asking `SoulGate` is the whole of its authority, because a caller that could
##    choose would be the picker ADR 0065 forbids.
## 4. **A death that costs the soul is a WORLD FACT, recorded once** under
##    [constant FACT_ID]. The guardian branch returns above this step and records nothing —
##    a body the player kept was never buried, and a "deaths so far" fact that counted a
##    spent item is a count nothing can reconcile with the world.
## 5. **The ledgers RIDE the body swap, because the soul is what owns them** (ADR 0181).
##    `module_data` has the actor's lifetime and the new body is minted empty, so
##    [method _carry_facts] moves the `world_facts` rows across and [method _carry_destiny]
##    moves the `destiny_state` rows across beside it — moved, never summed, and before
##    `_rebind` so the composition root's `DestinyApi.attach` re-derives every projection
##    from what is already there. Nothing is re-earned and nothing is reset: a fate earned by
##    a person was earned by the soul, and the next body is wearing the same ledger.
## 6. **Then the arrival's MARKS are granted, on the body the death just earned them on**
##    (ADR 0190). Between the carry and the rebind — never at the mint, never at birth, never
##    on a guardian death, never on an out-of-lives death, and never on the incarnation-0
##    body: `the_walker_back_through_ash` is deliberately BOTH the first arrival and the
##    initial body, so a birth-path grant would claim a death that never happened.
##    `DestinyApi.earn_fate` and nothing else; an arrival is a receipt, not a claim
##    (ADR 0159).
## 7. **A CAUSE, and the rule that is new here** (ADR 0258 §5). Step 2 is now two causes rather
##    than one: the soul pays the same authored cost whether a wound fell it or the lifespan
##    did, so everything from step 2 onward is untouched and there is no second end-of-life
##    path. The cause is PUBLISHED (`cause`) on every branch rather than inferred from `reason`
##    — `reason` already carries at least four unrelated values across these branches, so a
##    consumer reading it to learn why a body ended is already inferring, and ADR 0190's rule
##    ("every key present on both branches") applies to the new key exactly as it does to the
##    old ones.
##
## ## Why `is_dead` below answers for age too, and why that is the whole wiring
##
## `poll_death` asks `is_dead` and nothing else, so an aged body at full health would never be
## resolved by the shipped path — the exact "tested, built and unwired" defect DEF-0109 records.
## Making the ONE predicate that says "this body no longer stands" also say it for age is the
## change that makes the cause live, and it costs no edit to any caller: the composition root's
## poll keeps asking the same question and gets a new answer.

## The authored base cost of a death before difficulty scales it. A constant here and not on
## the arrival, because a death costs what it costs regardless of which arrival is next.
const BASE_DEATH_COST := 20

## A soul died and the body was re-embodied: a world fact (ADR 0130 §Decision).
##
## Spelled EXACTLY `FACT_ID`, because that is the name `tools/gate_reach.py`'s
## `code_owned_supply` resolves a code-owned producer by, and `tests/arch_rules/
## test_fact_ledger_writers.gd` asserts this exact spelling for every file in
## `CODE_OWNED_WRITERS`. A renamed const is not a rename: it is a producer the census
## stops counting, and a `.tres` demanding `soul_died` would then be reported dead while
## the game supplies it.
##
## A flat id in `WorldFact`'s ONE namespace and no prefix, per ADR 0113/ADR 0137: a
## prefixed id "reads as a working reference and silently grants nothing". It is never
## assembled at run time — `code_owned_supply` counts neither, so the id has to be this
## literal in this file.
const FACT_ID := &"soul_died"

## The one append-only marker key, naming the body this ledger was carried FROM.
##
## ## Why it is ADVISORY and not authoritative
##
## It answers the one question a copy cannot: "has this body ALREADY been given its parent's
## ledger?". Without it, a save taken after a death and restored on the next one re-copies a
## ledger onto a body that already had it — harmless today, because the copy is idempotent by
## the duplicate guard above, and the very next field added to the ledger could stop being. The
## flag itself is never load-bearing: the copy is correct with or without it, so nothing here may
## ever branch on it to decide whether a fate exists. It is a receipt, not a rule.
##
## It is written THROUGH `set_module_data`, whose payload is a `Dictionary` like every other
## value in `module_data` — core types the map that way, so a bare scalar would not compile —
## and `Actor.to_dict` copies the whole `String`-keyed dictionary verbatim, so it rides ADR
## 0027's existing mechanism and needs no `Actor` field, no migration and no envelope version.
const CARRIED_FROM_KEY := &"soul_fate_carried_from"

## The marker's one row. A wrapper rather than a bare string because `module_data` is
## `Dictionary[StringName, Dictionary]` — `Actor.set_module_data`'s second parameter is typed, so
## the value has to be a dictionary whatever this key means.
const CARRIED_FROM_FIELD := "from"

## Whether this exact body has already had its death written by this class.
##
## **A body-keyed marker, and the reason it is not the ledger's own count:** the ledger is
## shared with every other fact and it is CARRIED onto a re-embodied body that has not died
## yet, so `count >= 1` there means "this soul has died before", not "this body has died".
## Reading the count as the once-rule would refuse the new body's first death because it
## inherited the old body's history, and a soul could die once and never again. The marker is
## keyed by instance id, so it is about THIS body and only this body.
##
## In-memory only, deliberately. It is not save state: the thing it protects against is a
## repeated poll for a body that is still standing dead, and a body that died before a save is
## gone — the restored run polls a body that has not died yet, which is a first death and must
## be recorded.
static var _died_bodies: Dictionary = {}

## The composition root's arrival builder. Injected rather than called directly so this class
## names no `app/` type and stays a plain value object a test can drive.
var _mint_body: Callable = Callable()
## The composition root's re-binding callback, invoked with the new actor so every screen,
## roster and attached module follows the body swap.
var _rebind: Callable = Callable()


func _init(mint_body: Callable = Callable(), rebind: Callable = Callable()) -> void:
	_mint_body = mint_body
	_rebind = rebind


## Resolve a death for `actor`. The ONE entry point; every other method here is its step.
##
## Returns `{ok, reason, cause, died, guardian, damage, soul, arrival, body_id, incarnated,
## fact, fact_count, marks, ungranted_marks}`. `ok` is true whenever a death was resolved — a
## death the player survived via a guardian is a resolved death, not a refusal — and `reason`
## names what happened so a screen can say it without inferring an outcome from a message.
##
## ## `cause` is the NEW key, and it is ADDITIVE exactly like `marks` (ADR 0190)
##
## It is [constant SoulAge.CAUSE_DEATH] on every wound and [constant SoulAge.CAUSE_AGE] when
## the lifespan ended the body, and it is PRESENT on all four branches including `_refuse` —
## present, not conditional, because a consumer reading a verdict must never have to ask which
## branch produced it. The existing keys are untouched and a consumer that does not know the key
## reads the same dictionary it read before.
##
## ## The age cause answers `died`, `damage` and `fact` as follows, and each is a DECISION
##
##   - `died` is `true`: a body the lifespan reached has ended. This is a death with a cause,
##     which is the whole of ADR 0258 §5.
##   - `damage` is the AUTHORED cost, not `0`. The brief offered "0 — the body simply expired";
##    rejected, because `damage` already has one meaning on this verdict (integrity the soul
##    lost) and a second reading here would make the key branch-dependent, which is exactly the
##    hole ADR 0190's full-key-set rule exists to close. An age death that reported `damage: 0`
##    would also print through `SoulLedgerPanel`'s "Cost %d integrity" with a cost of zero —
##    a lie told by the panel's own template. Same number, same `_scaled_cost`, same clamp.
##   - `fact` is [constant FACT_ID] and it SHARES the count with a wound death, deliberately.
##    The counting question ADR 0130 mandates is "how many times has this soul's body ended",
##    and a body that reached the end of its authored life ended. The question that must NOT
##    hear about it — "how many times did this hero fall in battle" — is a DIFFERENT fact, and
##    the right answer for it is that no such fact exists yet. Inventing a second id here would
##    put a new id in the ledger with no quest reading it and no content declaring it, which is
##    the ADR 0137 shape (a fact with no demand) rather than an answer.
##   - `soul` is the damaged ledger, `incarnated`/`body_id`/`arrival`/`marks` behave exactly as
##    they do on the wound branch, because it is the SAME downstream path.
##
## ## The GUARDIAN takes precedence, and that is a DECISION rather than an accident
##
## Read the guardian branch first and it needs no argument about ordering — it is already
## first, and an age check placed above it would spend nothing. The question is whether the
## two causes may BOTH apply, and they may not.
##
## **A guardian PREVENTS an age death, and the argument is ADR 0130's own.** A guardian is an
## ordinary consumable carrying the `guardian` tag, spent through the all-or-nothing `items`
## verb, whose entire authored effect is to stand in for a body that would otherwise have been
## lost. There is no narrower reading of "the body fell and a guardian kept it" that covers a
## combat wound but not a lifespan. It is the player buying one more body, at the authored price
## of the item, and the item's authored restoration is what makes the spend succeed at all. The
## other reading — a guardian saves a body from a killer but not from time — has no support
## anywhere in the ADRs, invents a category of harm the content cannot express, and leaves the
## player holding a dead-on-arrival item the one time its use is thematically guaranteed.
##
## So age is checked AFTER the guardian has declined, and a soul holding one is rescued from the
## lifespan exactly as it is from a blade. `_heal` restoring health is then the whole of what
## the rescue is: an aged body that gets its lifespan back is a younger body with a young soul,
## because age lives on the BODY (ADR 0258 §2) and the body was never swapped.
##
## ## THE ORDER IS THE WHOLE THING, and it is why this cannot be a second resolver
##
## guardian -> age -> pay -> gate -> re-body. An age check placed ABOVE the guardian would
## expire a hero who is holding the item that exists to prevent exactly that; one placed after
## the gate would let the run end without saying why. [method resolve] is the only path and
## `is_dead` is the only predicate, so there is no arrangement of the tree in which an age
## death skips the guardian, the fact write or the marks window.
##
## ## A REFUSAL IS NEVER SILENT
##
## `SoulAge.read` answers a named reason for every missing seam and expires nobody, so a tree
## without ADR 0258 §2's field and without a wired clock behaves EXACTLY as it does today.
func resolve(actor: Actor, base_cost: int = BASE_DEATH_COST) -> Dictionary:
	if actor == null:
		return _refuse("no_actor")
	var guardian := SoulApi.spend_guardian(actor)
	if bool(guardian.get("ok", false)):
		# A guardian costs the ITEM and nothing else. Integrity is untouched and the incarnation
		# does not advance, because the body that just fell is the body the player keeps — and
		# the lifespan is inside that clause, for the reason the docblock gives.
		_heal(actor)
		return {
			"ok": true,
			"reason": "guardian_spent",
			"cause": SoulAge.CAUSE_DEATH,
			"died": false,
			"guardian": String(guardian.get("def_id", "")),
			"damage": 0,
			"soul": SoulApi.soul(actor),
			"arrival": "",
			"body_id": String(actor.id),
			"incarnated": false,
			"fact": "",
			"fact_count": WorldFact.count(actor, FACT_ID),
			# A guardian death is not a death, so no arrival was earned and no mark was granted.
			# The keys are present rather than absent so a consumer reading the verdict never has
			# to ask which branch it came from (ADR 0190).
			"marks": [] as Array[StringName],
			"ungranted_marks": [] as Array[StringName],
		}
	# No guardian. THE AGE CAUSE SITS HERE — above the soul's damage and below nothing, so it
	# cannot re-body a hero who was rescued, and above the gate, so an out-of-bodies age death
	# is still named rather than arriving as a silent `soul_spent`.
	var aged := SoulAge.answer_for(actor)
	var cause := SoulAge.CAUSE_AGE if bool(aged.get("expired", false)) else SoulAge.CAUSE_DEATH
	# No guardian: the soul pays. Difficulty supplies the FRACTION; this class supplies the
	# amount, which is why a difficulty row can never decide how much a death costs.
	var cost := _scaled_cost(actor, base_cost)
	var damaged := SoulApi.damage(actor, cost, String(cause))
	var arrival := SoulApi.next_arrival(actor)
	var verdict := SoulApi.verdict(actor)
	if not bool(verdict.get("ok", false)):
		# Out of lives: the soul ledger says so and there is no body to hand back. The soul keeps
		# its damage — a run that ended is still a run that happened, so it IS a death and it IS
		# recorded. Nothing re-embodies, but a soul that ran out of lives died on the last body
		# it had, and a quest asking how many deaths a soul has earned must hear about it.
		# An age death arrives here too, and it is the SAME event with a different cause: the
		# lifespan is named on the verdict, and the world hears about the run ending either way.
		var spent := _record_death(actor)
		return {
			"ok": true,
			"reason": "soul_spent",
			"cause": cause,
			"died": true,
			"guardian": "",
			"damage": int(damaged.get("applied", 0)),
			"soul": SoulApi.soul(actor),
			"arrival": String(arrival),
			"body_id": "",
			"incarnated": false,
			"fact": String(FACT_ID),
			"fact_count": spent,
			# Out of lives: the arrival is named on the verdict but never lived in, so no mark
			# was granted. The gate owed an arrival this soul had no body left to arrive into
			# (ADR 0190).
			"marks": [] as Array[StringName],
			"ungranted_marks": [] as Array[StringName],
		}
	return _rebody(actor, arrival, damaged, cause)


## Record that this soul died, ONCE, into the world fact ledger (ADR 0130 §Decision). Returns
## the ledger's count for [constant FACT_ID] afterwards.
##
## ## ONE FACT FOR BOTH CAUSES, and the question that decides it
##
## `WorldFact.count(actor, FACT_ID)` answers "how many bodies has this soul ended", and that
## is the question ADR 0130's quest gate asks. A body that reached the lifespan ended, so it is
## counted; the count is the union and neither cause is visible inside it. That is correct for
## the question this fact was minted for and it is honest about its own limit — `fact_count`
## alone cannot tell a reader WHICH cause ended a body, and the answer to that is on `cause`,
## which is why `cause` is a key on the verdict rather than something read back off the count.
##
## ## Why a SEPARATE id was rejected
##
## The alternative — a second code-owned id for age — would be strictly worse for every consumer
## and no better for any: a quest that must now ask BOTH ids to learn the number it asked for,
## two rows in a ledger ADR 0113 calls "the world's memory" for one event, and a new id reaching
## `gate_reach`'s census with no authored `.tres` demanding it (ADR 0137: a fact with no demand
## is a content defect). Splitting it would also make the FIRST writer of each id the only place
## the split exists, which is how two producers of "a soul died" drift apart.
##
## ## `age` and `death` are both spellings of the same soul trail reason
##
## `SoulState._append` stores this string on the bounded damage trail, so an age death is
## findable in the soul's own history by cause name. It is the third string the trail carries
## (`test`, `first`, `death`) and none of them is parsed by anything in the tree.
##
## ## Why this is not a bare [code]WorldFact.record[/code]
##
## `app/item_workbench_app.gd::poll_death` re-arms on the actor id, so the shipped poll does not
## fire twice for one body — but that is the CALLER's once-rule, and a ledger that is monotone
## has no verb to take an accidental second accrual back (ADR 0113). A second `resolve` for a
## body that already died would therefore be permanent and unfalsifiable from the ledger's side.
## So the once-rule lives HERE, at the writer: a death already recorded against this body is
## counted, not re-recorded. The proof is the state of the world, not a caller's bookkeeping.
##
## ## Why the write lands on BOTH the falling body and the one it becomes
##
## `world_facts` lives at `actor.module_data["world_facts"]` (ADR 0113), which has the
## actor's lifetime — the same trap ADR 0127 names for the soul ledger. **Measured, not
## assumed**: a probe recorded a fact on a body, minted the rebirth body through the real
## `CharacterCreationFlow.build_forced`, and read it back — `before_swap=1`,
## `after_swap_on_new_body=0`. A reborn body arrives with an EMPTY ledger, so a write to the
## old body alone is erased by the very re-embodiment this fact describes, and the next
## death would count 1 forever.
##
## So the ledger is carried across the swap explicitly, and the carried copy is what the new
## body reports. It is not a second ledger: [method _carry_facts] moves the same rows rather
## than tracking anything of its own, and it is a no-op when the falling body holds none.
##
## **The carry moves the ledger, not the marker.** `_died_bodies` is keyed by instance id and is
## deliberately NOT carried: the new body has not died, so it must be free to record its own
## first death, and the carried `soul_died` count is the history that accumulates underneath it.
static func _record_death(actor: Actor) -> int:
	if actor == null:
		return 0
	if _death_already_recorded(actor):
		return WorldFact.count(actor, FACT_ID)
	_died_bodies[actor.get_instance_id()] = true
	var written := WorldFact.record(actor, FACT_ID, 1)
	return int(written.get("count", 0))


## Whether this exact body has already had its death written by this class.
##
## **A body-keyed marker, and the reason it is not the ledger's own count:** the ledger is
## shared with every other fact and it is CARRIED onto a re-embodied body that has not died
## yet, so `count >= 1` there means "this soul has died before", not "this body has died".
## Reading the count as the once-rule would refuse the new body's first death because it
## inherited the old body's history, and a soul could die once and never again. The marker is
## keyed by instance id, so it is about THIS body and only this body.
##
## In-memory only, deliberately. It is not save state: the thing it protects against is a
## repeated poll for a body that is still standing dead, and a body that died before a save is
## gone — the restored run polls a body that has not died yet, which is a first death and must
## be recorded.
static func _death_already_recorded(actor: Actor) -> bool:
	return bool(_died_bodies.get(actor.get_instance_id(), false))


## Copy the world fact ledger from `from` onto `to`, so a re-embodied soul's history survives
## the body swap. Idempotent: carrying an empty ledger writes nothing.
##
## **A duplicate guard, not a merge.** Two bodies each carrying `soul_died: 1` and a sum that
## adds them would report 2 deaths for 1, and `WorldFact`'s ledger is monotone with no verb to
## lower a count (ADR 0113), so a wrong count here is permanent. The rows are taken as the
## source of truth, never added to.
static func _carry_facts(from: Actor, to: Actor) -> void:
	if from == null or to == null:
		return
	var ledger: Dictionary = from.get_module_data(WorldFact.MODULE_KEY)
	if ledger.is_empty():
		return
	to.set_module_data(WorldFact.MODULE_KEY, ledger.duplicate(true))


## Copy the whole DESTINY ledger from `from` onto `to`, so the fates, destinies, counters and
## history a soul earned belong to the soul and not to the body plan it happened to be wearing
## (ADR 0181). Placed beside [method _carry_facts] and not inside it, because the two ledgers are
## separate keys with separate owners and a merge would be a second ledger rather than a carry.
##
## ## Why this is a carry and not a re-derive
##
## A fate counter is a DERIVATION of the fact ledger — `WorldFact.record` fires
## `DestinyProjection.on_fact_recorded`, which is the only thing that has ever moved a counter
## (`destiny_projection.gd`) — and `DestinyApi.record` is monotone with no verb to lower a count.
## So after the swap the two memories disagree for good: `WorldFact.count(body, "duels_won")` reads
## what `_carry_facts` moved, and `DestinyApi.state(body)["counters"]["duels_won"]` reads 0,
## permanently. Re-deriving the counters from the carried facts on the new body was rejected by
## ADR 0181: it would need exactly the lowering verb ADR 0065 forbids.
##
## ## Moved, never summed — the same guard, the same argument
##
## Two bodies each holding `duels_won: 3` and a sum that added them would report six for three,
## and both ledgers are monotone with no refund (ADR 0065, ADR 0113), so a wrong count here is
## permanent. The rows are taken from the falling body as the source of truth and never added
## to. No projections are hand-copied either: the carry only has to put the rows on the new actor
## BEFORE `_rebind`, and the composition root's own `DestinyApi.attach(actor)` normalizes the
## ledger and re-derives every modifier and `destiny:` trait from it — a second stat composer
## here is the ADR 0065 failure mode in reverse.
##
## A no-op on an empty ledger, so a hero who earned nothing has nothing written and a birth is
## not turned into a rebirth by this line existing.
static func _carry_destiny(from: Actor, to: Actor) -> void:
	if from == null or to == null:
		return
	var ledger: Dictionary = from.get_module_data(DestinyState.MODULE_KEY)
	if ledger.is_empty():
		return
	to.set_module_data(DestinyState.MODULE_KEY, ledger.duplicate(true))
	_note_carried_from(to, from)


## Record on `to` which body its destiny ledger came from. Called by [method _carry_destiny]
## and nowhere else, and it never touches the ledger — a marker that could rewrite what it
## annotates would stop being a marker.
static func _note_carried_from(to: Actor, from: Actor) -> void:
	if to == null or from == null:
		return
	to.set_module_data(CARRIED_FROM_KEY, {CARRIED_FROM_FIELD: String(from.id)})


## Whether `actor`'s body has ended — read as `health <= 0.0` OR as a lifespan reached
## (ADR 0258 §5).
##
## The predicate the poll asks, kept here so the ONE definition of "dead" lives beside the ONE
## rule that acts on it. Nothing else in the tree should re-derive it.
##
## ## WHY AGE IS IN HERE AND NOT IN `resolve`, and the cost that follows
##
## `resolve` is never called for a body nobody believes is dead: `poll_death` asks this and
## returns `{}` on `false`, and `FightLoop._decide`'s "would un-ring a death" argument is written
## against this exact predicate. An aged body sitting at full health answers `false` here, so
## the shipped path never asks `resolve` and the age cause is built, tested and unwired — the
## DEF-0109 defect verbatim. Hence the OR, and hence the cost: **this is a call into
## `SoulAge.read` on every poll of every body**, which reads two fields and does two integer
## divisions. That is bounded and cheap; what it buys is that a cause cannot exist without the
## poll being able to reach it.
##
## ## A MISSING SEAM READS FALSE, and this is the one place that matters most
##
## `SoulAge.read` answers `expired: false` with a named reason for every missing field or
## unwired clock, so the OR's second term is `false` on any tree that has not landed ADR 0258
## §2 and a wired `world_time`. The `age_years < 0.0` early return below exists so that is
## true on the FIRST term too: a body with no age field answers `false` from `is_dead` itself
## rather than falling through to a read that would have to report the same refusal twice. The
## sentinel is negative on purpose — `0.0` would read as "born today", which is a different
## claim, so nothing here compares against zero.
func is_dead(actor: Actor) -> bool:
	if actor == null:
		return false
	if SoulAge.age_years(actor) < 0.0:
		return false
	var pool := actor.resource(&"health")
	return (pool != null and pool.current <= 0.0) or SoulAge.has_expired(actor)


## Restore `actor` to full health, spent through `change` so the pool's `changed` signal still
## fires and every stat cache watching it invalidates. Assigning `current` would leave a
## screen showing a dead actor's numbers.
##
## ## `guardian_effectiveness` is read here, and only here
##
## The third ADR 0129 scalar. A harder preset makes the guardian a WEAKER rescue — it restores
## the pool to that fraction of full rather than all of it — which is the only reading that makes
## it a difficulty rather than a duplicate of `soul_damage_share`. It was authored and read by
## nothing until here, and a column no consumer reads is a preset that changes nothing a player
## can observe.
##
## **Floored at the pool's regen requirement, not at zero**: a guardian that leaves a body at 1
## health is a death deferred, not a death avoided, and the poll would fire again on the next
## frame with no guardian left to spend.
func _heal(actor: Actor) -> void:
	var pool := actor.resource(&"health")
	if pool == null:
		return
	var share := float(DifficultyApi.scalars(actor).get("guardian_effectiveness", 1.0))
	var target := minf(pool.maximum, maxf(pool.maximum * share, 1.0))
	if target <= pool.current:
		return
	pool.change(target - pool.current)


## What this death costs the soul: the authored base scaled by difficulty's share. Refuses
## `no_difficulty` by falling back to the BASE cost rather than to zero: a missing preset must
## be inert, never a free death.
##
## `death_loss_cap` is GONE (BL-0887), and this is why the signature is unchanged while the
## body is shorter. Measured from the authored table, the cap bound on NO preset: story is
## share 0.5 / cap 1.0 so the share was already the binding term, standard is 1.0 / 1.0, and
## hard is 1.5 / 1.5 so the clamp computed `min(30, 30)`. A column whose reader is a no-op is
## the same defect as a column with no reader, and the BL-0779 sweep missed it because it
## looked for the second shape only.
##
## What is lost, stated plainly: a cap is the right shape when a preset wants a damage
## multiplier that stops partway — share 3.0 with cap 2.0 means "twice as painful, never more".
## No shipped preset expressed that intent, so the programme has no damage ceiling. A future
## one arrives as a preset setting share ABOVE cap, which is why `DifficultyTable` carries a
## guard asserting every row has share <= cap.
func _scaled_cost(actor: Actor, base_cost: int) -> int:
	var scalars := DifficultyApi.scalars(actor)
	if scalars.is_empty():
		return base_cost
	var share := float(scalars.get("soul_damage_share", 1.0))
	return maxi(1, int(float(base_cost) * share))


## Mint the new body through the gate's arrival and swap every binding to it.
##
## ## Why the incarnation is passed IN rather than read by the mint
##
## The body id is derived from the soul's incarnation, and this runs BEFORE `reincarnate`, so a
## mint that read the ledger would see the OLD count and mint the id the previous body already
## holds — two Actors with one id, which is a world where the second is invisible because every
## ledger and roster is keyed by it. So the count is computed here, from the ledger this method
## is already reading, and handed over: the mint cannot be out of step with the soul.
##
## `cause` is THROWN rather than read from the actor, because it is a fact about the resolve
## that is calling this method and not a property any body carries — the age field lives on the
## BODY and the falling body is about to be replaced by one that has never been old.
func _rebody(
	actor: Actor, arrival: StringName, damaged: Dictionary, cause: StringName = SoulAge.CAUSE_DEATH
) -> Dictionary:
	var ledger := SoulApi.state()
	var next_incarnation := int(ledger.get("incarnation", 0)) + 1
	if not _mint_body.is_valid():
		return {
			"ok": false,
			"reason": "no_body_mint",
			"cause": cause,
			"died": true,
			"guardian": "",
			"damage": int(damaged.get("applied", 0)),
			"soul": SoulApi.soul(actor),
			"arrival": String(arrival),
			"body_id": "",
			"incarnated": false,
			"fact": String(FACT_ID),
			"fact_count": _record_death(actor),
			# No body, so nothing to earn onto. `marks` names what the ARRIVAL owed, so a
			# caller can tell "the mint refused" from "the mint worked and the marks silently
			# vanished" (ADR 0190) - and `ungranted_marks` names the SAME ids, because every
			# one of them is ungranted. Reporting an empty `ungranted_marks` here would claim
			# the mint cost the player nothing, which is the one reading this branch must not
			# be able to produce.
			"marks": SoulArrivalMarks.marks_for(arrival),
			"ungranted_marks": SoulArrivalMarks.marks_for(arrival),
		}
	var minted := _mint_body.call(String(arrival), next_incarnation) as Dictionary
	if not bool(minted.get("ok", false)):
		return {
			"ok": false,
			"reason": String(minted.get("reason", "body_mint_failed")),
			"cause": cause,
			"died": true,
			"guardian": "",
			"damage": int(damaged.get("applied", 0)),
			"soul": SoulApi.soul(actor),
			"arrival": String(arrival),
			"body_id": "",
			"incarnated": false,
			"fact": String(FACT_ID),
			"fact_count": _record_death(actor),
			"marks": SoulArrivalMarks.marks_for(arrival),
			"ungranted_marks": SoulArrivalMarks.marks_for(arrival),
		}
	var body := minted.get("actor", null) as Actor
	var body_id := "" if body == null else String(body.id)
	# BEFORE the rebind, and on the body that fell. `WorldFact.record` needs an actor whose
	# ledger it can write, and the new body is minted EMPTY — so the write happens against the
	# falling body and the carry below moves it. See `_record_death`.
	var death_count := _record_death(actor)
	# `marks` is empty unless a body came back from the mint at all; a null body has nothing to
	# earn onto and `SoulArrivalMarks.grant` is the one place that says so rather than the
	# verdict reporting an empty success.
	var marks: Array[StringName] = []
	var ungranted_marks: Array[StringName] = []
	if body != null:
		_carry_facts(actor, body)
		# Beside the fact carry, above the rebind, and for the same reason it is not below it:
		# the new body must HOLD its parent's ledger before it is adopted, because the adopt
		# callback is what runs the composition root's module list and `DestinyApi.attach`
		# normalizes and re-projects from whatever is already on the actor. Carrying afterwards
		# would land the rows on a body whose projection had already been built from an empty
		# ledger, and the codex would render an oath whose numbers never reached the stat stack.
		# ADR 0181: fate belongs to the soul, and this is the line that makes it so.
		_carry_destiny(actor, body)
		# SECOND, and the order is the whole design (ADR 0190). The carry above is a WHOLESALE
		# OVERWRITE — `to.set_module_data(DestinyState.MODULE_KEY, ledger.duplicate(true))` — so
		# a grant placed before it is silently erased, and a grant placed after `_rebind` never
		# reaches the projection. Between the two is the only window in which an arrival mark both
		# survives the copy and is on the body `attach_actor` is about to adopt.
		var granted := SoulArrivalMarks.grant(body, arrival)
		marks = granted.get("marks", []) as Array[StringName]
		ungranted_marks = granted.get("ungranted", []) as Array[StringName]
	var reborn := SoulApi.reincarnate(actor, body_id)
	if body != null and _rebind.is_valid():
		# Every screen, roster and attached module follows the body. A half-swapped body is the
		# failure this names: the game reads two different actors and no test fails.
		_rebind.call(body)
	# VERIFY LAST, after `_rebind` — not after the earn above. `DestinyApi.attach` calls
	# `DestinyState.normalize`, which DROPS any fate id not in `_known_fates()`
	# (destiny/api.gd:321-327, destiny_state.gd:72). A typo'd mark therefore passes `has_fate`
	# at grant time and VANISHES at adopt, so a verification placed there would report the mark
	# held and the codex would not have it. Re-reading after the rebind catches the typo and the
	# null-body refusal in one place.
	if body != null:
		var still_missing: Array[StringName] = []
		for mark_id in marks:
			if not DestinyApi.has_fate(body, mark_id):
				still_missing.append(mark_id)
		if not still_missing.is_empty():
			ungranted_marks = still_missing
	return {
		"ok": bool(reborn.get("ok", false)),
		"reason": String(reborn.get("reason", "")),
		"cause": cause,
		"died": true,
		"guardian": "",
		"damage": int(damaged.get("applied", 0)),
		"soul": SoulApi.soul(actor),
		"arrival": String(reborn.get("arrival", arrival)),
		"body_id": body_id,
		"incarnated": bool(reborn.get("ok", false)),
		"fact": String(FACT_ID),
		"fact_count": death_count,
		# ADDITIVE keys (ADR 0190). The verdict keys above are consumed by
		# `SoulLedgerPanel.DEATH_TEXT` and the `last_death` envelope; adding to them breaks
		# nothing, and renaming or removing one would be a UI break.
		"marks": marks,
		"ungranted_marks": ungranted_marks,
	}


## The refusal. Every key is here, including [constant SoulAge.CAUSE_DEATH] as the cause: a
## `null` actor has no body and therefore no lifespan, so `death` is the honest answer rather
## than an empty string a consumer would have to special-case.
func _refuse(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"cause": SoulAge.CAUSE_DEATH,
		"died": false,
		"guardian": "",
		"damage": 0,
		"soul": {},
		"arrival": "",
		"body_id": "",
		"incarnated": false,
		"fact": "",
		"fact_count": 0,
		"marks": [] as Array[StringName],
		"ungranted_marks": [] as Array[StringName],
	}
