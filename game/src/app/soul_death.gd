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
## Returns `{ok, reason, died, guardian, damage, soul, arrival, body_id, incarnated, fact,
## fact_count}`. `ok` is true whenever a death was resolved — a death the player survived via a
## guardian is a resolved death, not a refusal — and `reason` names what happened so a screen
## can say it without inferring an outcome from a message.
##
## **A guardian death is not a death.** It returns early, ABOVE the fact write, because the
## body never fell: the item was spent and the player keeps the body they had. Counting it
## would make "how many times has this soul died" answer higher than the number of bodies
## the world buried, and the quest step asking that question is the reason the fact exists.
func resolve(actor: Actor, base_cost: int = BASE_DEATH_COST) -> Dictionary:
	if actor == null:
		return _refuse("no_actor")
	var guardian := SoulApi.spend_guardian(actor)
	if bool(guardian.get("ok", false)):
		# A guardian costs the ITEM and nothing else. Integrity is untouched and the incarnation
		# does not advance, because the body that just fell is the body the player keeps.
		_heal(actor)
		return {
			"ok": true,
			"reason": "guardian_spent",
			"died": false,
			"guardian": String(guardian.get("def_id", "")),
			"damage": 0,
			"soul": SoulApi.soul(actor),
			"arrival": "",
			"body_id": String(actor.id),
			"incarnated": false,
			"fact": "",
			"fact_count": WorldFact.count(actor, FACT_ID),
		}
	# No guardian: the soul pays. Difficulty supplies the FRACTION; this class supplies the
	# amount, which is why a difficulty row can never decide how much a death costs.
	var cost := _scaled_cost(actor, base_cost)
	var damaged := SoulApi.damage(actor, cost, "death")
	var arrival := SoulApi.next_arrival(actor)
	var verdict := SoulApi.verdict(actor)
	if not bool(verdict.get("ok", false)):
		# Out of lives: the soul ledger says so and there is no body to hand back. The soul keeps
		# its damage — a run that ended is still a run that happened, so it IS a death and it IS
		# recorded. Nothing re-embodies, but a soul that ran out of lives died on the last body
		# it had, and a quest asking how many deaths a soul has earned must hear about it.
		var spent := _record_death(actor)
		return {
			"ok": true,
			"reason": "soul_spent",
			"died": true,
			"guardian": "",
			"damage": int(damaged.get("applied", 0)),
			"soul": SoulApi.soul(actor),
			"arrival": String(arrival),
			"body_id": "",
			"incarnated": false,
			"fact": String(FACT_ID),
			"fact_count": spent,
		}
	return _rebody(actor, arrival, damaged)


## Record that this soul died, ONCE, into the world fact ledger (ADR 0130 §Decision). Returns
## the ledger's count for [constant FACT_ID] afterwards.
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


## Whether `actor` is currently dead, read as `health <= 0.0`.
##
## The predicate the poll asks, kept here so the ONE definition of "dead" lives beside the ONE
## rule that acts on it. Nothing else in the tree should re-derive it.
func is_dead(actor: Actor) -> bool:
	if actor == null:
		return false
	var pool := actor.resource(&"health")
	return pool != null and pool.current <= 0.0


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


## What this death costs the soul, from the authored base and difficulty's share, clamped by
## difficulty's cap. Refuses `no_difficulty` by falling back to the BASE cost rather than to
## zero: a missing preset must be inert, never a free death.
func _scaled_cost(actor: Actor, base_cost: int) -> int:
	var scalars := DifficultyApi.scalars(actor)
	if scalars.is_empty():
		return base_cost
	var share := float(scalars.get("soul_damage_share", 1.0))
	var cap := float(scalars.get("death_loss_cap", 1.0))
	return maxi(1, mini(int(float(base_cost) * share), int(float(base_cost) * cap)))


## Mint the new body through the gate's arrival and swap every binding to it.
##
## ## Why the incarnation is passed IN rather than read by the mint
##
## The body id is derived from the soul's incarnation, and this runs BEFORE `reincarnate`, so a
## mint that read the ledger would see the OLD count and mint the id the previous body already
## holds — two Actors with one id, which is a world where the second is invisible because every
## ledger and roster is keyed by it. So the count is computed here, from the ledger this method
## is already reading, and handed over: the mint cannot be out of step with the soul.
func _rebody(actor: Actor, arrival: StringName, damaged: Dictionary) -> Dictionary:
	var ledger := SoulApi.state()
	var next_incarnation := int(ledger.get("incarnation", 0)) + 1
	if not _mint_body.is_valid():
		return {
			"ok": false,
			"reason": "no_body_mint",
			"died": true,
			"guardian": "",
			"damage": int(damaged.get("applied", 0)),
			"soul": SoulApi.soul(actor),
			"arrival": String(arrival),
			"body_id": "",
			"incarnated": false,
			"fact": String(FACT_ID),
			"fact_count": _record_death(actor),
		}
	var minted := _mint_body.call(String(arrival), next_incarnation) as Dictionary
	if not bool(minted.get("ok", false)):
		return {
			"ok": false,
			"reason": String(minted.get("reason", "body_mint_failed")),
			"died": true,
			"guardian": "",
			"damage": int(damaged.get("applied", 0)),
			"soul": SoulApi.soul(actor),
			"arrival": String(arrival),
			"body_id": "",
			"incarnated": false,
			"fact": String(FACT_ID),
			"fact_count": _record_death(actor),
		}
	var body := minted.get("actor", null) as Actor
	var body_id := "" if body == null else String(body.id)
	# BEFORE the rebind, and on the body that fell. `WorldFact.record` needs an actor whose
	# ledger it can write, and the new body is minted EMPTY — so the write happens against the
	# falling body and the carry below moves it. See `_record_death`.
	var death_count := _record_death(actor)
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
	var reborn := SoulApi.reincarnate(actor, body_id)
	if body != null and _rebind.is_valid():
		# Every screen, roster and attached module follows the body. A half-swapped body is the
		# failure this names: the game reads two different actors and no test fails.
		_rebind.call(body)
	return {
		"ok": bool(reborn.get("ok", false)),
		"reason": String(reborn.get("reason", "")),
		"died": true,
		"guardian": "",
		"damage": int(damaged.get("applied", 0)),
		"soul": SoulApi.soul(actor),
		"arrival": String(reborn.get("arrival", arrival)),
		"body_id": body_id,
		"incarnated": bool(reborn.get("ok", false)),
		"fact": String(FACT_ID),
		"fact_count": death_count,
	}


func _refuse(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"died": false,
		"guardian": "",
		"damage": 0,
		"soul": {},
		"arrival": "",
		"body_id": "",
		"incarnated": false,
		"fact": "",
		"fact_count": 0,
	}
