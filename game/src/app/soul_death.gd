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

## The authored base cost of a death before difficulty scales it. A constant here and not on
## the arrival, because a death costs what it costs regardless of which arrival is next.
const BASE_DEATH_COST := 20

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
## Returns `{ok, reason, died, guardian, damage, soul, arrival, body_id, incarnated}`. `ok` is
## true whenever a death was resolved — a death the player survived via a guardian is a
## resolved death, not a refusal — and `reason` names what happened so a screen can say it
## without inferring an outcome from a message.
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
		}
	# No guardian: the soul pays. Difficulty supplies the FRACTION; this class supplies the
	# amount, which is why a difficulty row can never decide how much a death costs.
	var cost := _scaled_cost(actor, base_cost)
	var damaged := SoulApi.damage(actor, cost, "death")
	var arrival := SoulApi.next_arrival(actor)
	var verdict := SoulApi.verdict(actor)
	if not bool(verdict.get("ok", false)):
		# Out of lives: the soul ledger says so and there is no body to hand back. The soul keeps
		# its damage — a run that ends is still a run that happened.
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
		}
	return _rebody(actor, arrival, damaged)


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
func _heal(actor: Actor) -> void:
	var pool := actor.resource(&"health")
	if pool != null:
		pool.change(pool.maximum - pool.current)


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
		}
	var body := minted.get("actor", null) as Actor
	var body_id := "" if body == null else String(body.id)
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
	}
