class_name HoldingsApi
extends RefCounted

## Public facade for the `holdings` module (ADR 0097). Owns who holds a resource node,
## what it has yielded, and the standoff a contested claim opens.
##
## ## Four owner kinds, zero module edges
##
## An `actor`, a `clan`, a `sect` and a `nation` may all hold a node. Those live in four
## modules that do not contain each other, and `tools/arch`'s bare-reference detector
## **excludes `modules/*`** — so a holder check that called into all three would build a
## cycle the gate cannot see. Instead resolution is an **injected `Callable`**
## (`set_resolver`), the `NpcApi.set_minter` seam verbatim. `app/` installs it.
##
## ## A claim never moves ground
##
## `claim` on held ground writes ONE challenger row and leaves `holder` byte-identical
## (ADR 0085). That invariant is the whole difference between a claim and a conquest, and
## `test_holdings_claim.gd` pins it.
##
## ## Yield is a ledger line, never items
##
## `accrue` adds units to `line[node_id]` — ids and counts, `InstitutionClaim.obligation`'s
## shape. An institution never holds a pile of goods (BL-0191).
##
## ## There is no clock
##
## Every accrual takes an explicit `periods` from a caller that owns time (DEF-0111), and a
## module that invented a timer would be a second source of truth for when a save happened.

## The `actor.module_data` key the versioned ledger persists under (ADR 0027).
const MODULE_KEY := HoldingsState.MODULE_KEY

## The ceiling on tracked contested nodes, so a ledger cannot grow without bound.
const MAX_CONTESTED := 32

static var _store: RefCounted = null
static var _resolver: Callable = Callable()
static var _events: HoldingsEvents = null


## The event contract, for a consumer to subscribe to. On the facade and not behind a
## projection because a subscriber in another module has to be able to reach it (ADR 0093).
static func events() -> HoldingsEvents:
	if _events == null:
		_events = HoldingsEvents.new()
	return _events


## Read the ledger, from wherever it lives.
##
## ## Why the store is injected, and why it is not `module_data`
##
## A node's holder is a WORLD fact, but this repo has no world store: `LootState` is
## `actor.module_data` and dies with the actor, and `DomainApi` erases its map on leave
## keeping only `discovered`. Storing a holder per actor is not a simplification, it is a
## **correctness bug**: two actors each keep their own copy of the ledger, so a rival
## reads a held node as vacant and overwrites the holder outright — precisely the silent
## conquest ADR 0085 forbids. So the ledger is owned by an injected store and every verb
## reads and writes THAT, while `attach` keeps the per-actor mirror for the save.
##
## `set_store` installs a holder for the shared ledger — any object with `read_ledger()`
## and `write_ledger(ledger)`. The default is the actor-scoped `module_data` mirror, which is
## correct for a single-player save and **wrong** the moment a second holder exists, so
## `app/` installs a real world store. `WorldLedger` below is the in-memory one a test uses,
## and the shape a real store should copy.
##
## The names are deliberately not `load`/`save`: those are global GDScript builtins, and a
## `RefCounted` method of that name resolves to the builtin — a compile error rather than a
## loud failure, so it stays invisible until someone runs it.
static func set_store(store: RefCounted) -> void:
	_store = store


## Attach the module to `actor`: restore and normalize whatever a prior `Actor.from_dict`
## carried. Idempotent, and safe on an actor who holds nothing — holding nothing is the
## ordinary starting state, not a failure.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	actor.set_module_data(MODULE_KEY, HoldingsState.normalize(actor.get_module_data(MODULE_KEY)))


## Install the holder resolver. `app/` passes a callable taking `(kind, id)` and answering
## `{"ok": true}` or `{"ok": false, "reason": "unknown_sect"}`.
##
## With nothing installed, a claim by an institution refuses `no_resolver` and writes
## nothing — a null injection fails loudly rather than dereferencing nothing (ADR 0002).
static func set_resolver(resolver: Callable) -> void:
	_resolver = resolver


## Take an unheld `node_id` for `owner_ref`. Charges `claim_cost` as obligation TERMS and
## needs the holder to already hold at least `claim_floor` nodes — ADR 0248's
## concentration gate, answered from this ledger rather than from a political number a
## `{kind, id}` ref does not carry.
##
## **On a held node this opens a standoff instead**: one challenger row, and `holder` is
## untouched (ADR 0085). Returns `{ok, reason, contested}` so a caller can tell a claim from
## a challenge — they are different situations and a panel renders them differently.
static func claim(actor: Actor, node_id: StringName, owner: Dictionary) -> Dictionary:
	var state := _state(actor)
	if not ResourceNodeCatalog.instance().has_definition(node_id):
		return _refuse(actor, node_id, HoldingsState.UNKNOWN_NODE, state)
	if not HoldingsState.knows(state, node_id):
		# A node the ledger has never seen is recorded as vacant rather than invented: the
		# node exists, its value does not (ADR 0083). Its CONDITION is the exception, and it
		# is seeded from the def's `depletion` rather than left at 0: `accrue` spends
		# condition and refuses `depleted` once `left <= 0`, so a node recorded with no
		# reserve is refused on the very first period it is ever worked. `depletion` is
		# documented as "periods of yield before the node rests", so 0 there means
		# INEXHAUSTIBLE — which `accrue` already reads as "spend nothing", and seeding from
		# it keeps one meaning for the number in both places.
		var def := ResourceNodeCatalog.instance().definition(node_id)
		state["nodes"][String(node_id)] = {
			"owner": {},
			"condition": 0 if def == null else maxi(0, def.depletion),
			"resting": 0,
		}
	var held := HoldingsState.holder(state, node_id)
	if not OwnerRef.is_vacant(held) and not held.is_empty():
		return _challenge(actor, state, node_id, owner)
	var resolved := _resolve(owner)
	if not bool(resolved["ok"]):
		return _refuse(actor, node_id, String(resolved["reason"]), state)
	var def := ResourceNodeCatalog.instance().definition(node_id)
	if not _meets_floor(state, def, owner):
		return _refuse(actor, node_id, HoldingsState.CLAIM_BELOW_FLOOR, state)
	_ensure_entry(state, node_id)
	state["nodes"][String(node_id)]["owner"] = owner.duplicate(true)
	_charge_claim_cost(state, def, owner)
	_save(actor, state)
	events().node_claimed.emit(String(actor.id), node_id, String(owner.get("id", "")))
	return {"ok": true, "reason": "", "contested": false, "owner": owner.duplicate(true)}


## Give up `node_id`. **Always permitted and never free**: the obligation lines the claim
## charged stay written, because a holder who walks away from a claim has not un-paid it.
## Only a refusal is `cannot_release_foreign`.
static func release(actor: Actor, node_id: StringName, owner: Dictionary) -> Dictionary:
	var state := _state(actor)
	if not HoldingsState.knows(state, node_id):
		return _refuse(actor, node_id, HoldingsState.UNKNOWN_NODE, state)
	var held := HoldingsState.holder(state, node_id)
	if OwnerRef.is_vacant(held) or held.is_empty():
		return _refuse(actor, node_id, HoldingsState.NO_HOLDER, state)
	if String((held as Dictionary).get("id", "")) != String(owner.get("id", "")):
		return _refuse(actor, node_id, HoldingsState.HOLDER_MISMATCH, state)
	# Written as the explicit VACANT marker rather than `{}`. ADR 0083's three states are
	# load-bearing: `{}` means "not a node at all", and using it for a released node makes an
	# unclaimed vein indistinguishable from a vein that does not exist — which is exactly
	# what a claim reads to decide between taking ground and challenging ground.
	state["nodes"][String(node_id)]["owner"] = OwnerRef.vacant()
	_save(actor, state)
	events().node_released.emit(String(actor.id), node_id, String(owner.get("id", "")))
	return {"ok": true, "reason": "", "owner": OwnerRef.vacant()}


## Accrue `periods` of `node_id`'s yield into its line, and charge the holder's upkeep.
## Both are ledger arithmetic in `periods` — there is no tick (DEF-0111).
##
## Refuses `no_periods` for zero or fewer, `node_resting` while the node rests after
## depletion, and `depleted` once its condition is spent and it has no reserve left.
static func accrue(
	actor: Actor, node_id: StringName, owner: Dictionary, periods: int
) -> Dictionary:
	var state := _state(actor)
	if periods <= 0:
		return _refuse(actor, node_id, HoldingsState.NO_PERIODS, state)
	if not ResourceNodeCatalog.instance().has_definition(node_id):
		return _refuse(actor, node_id, HoldingsState.UNKNOWN_NODE, state)
	var held := HoldingsState.holder(state, node_id)
	if OwnerRef.is_vacant(held) or held.is_empty():
		return _refuse(actor, node_id, HoldingsState.NO_HOLDER, state)
	if String((held as Dictionary).get("id", "")) != String(owner.get("id", "")):
		return _refuse(actor, node_id, HoldingsState.HOLDER_MISMATCH, state)
	var def := ResourceNodeCatalog.instance().definition(node_id)
	var entry := state["nodes"][String(node_id)] as Dictionary
	if int(entry.get("resting", 0)) > 0:
		entry["resting"] = maxi(0, int(entry.get("resting", 0)) - 1)
		return _refuse(actor, node_id, HoldingsState.NODE_RESTING, state)
	var yield_units := def.yield_per_period * periods
	# Depletion spends CONDITION, not the accrued line: a node that produced this period
	# still produced it. Upkeep is charged whatever the yield, which is what makes an
	# exhausted holding a cost rather than a free plateau.
	if def.depletion > 0:
		var left := maxi(0, int(entry.get("condition", 0)))
		var spent := mini(left, periods)
		entry["condition"] = left - spent
		if left <= 0:
			return _refuse(actor, node_id, HoldingsState.DEPLETED, state)
	var gained := HoldingsState.accrue(state, node_id, yield_units)
	_charge_upkeep(state, def, periods, owner)
	_save(actor, state)
	events().node_accrued.emit(
		String(actor.id), node_id, String(owner.get("id", "")), periods, gained
	)
	return {
		"ok": true,
		"reason": "",
		"periods": periods,
		"yielded": gained,
		"accrued": HoldingsState.accrued(state, node_id),
		"condition": int(entry.get("condition", 0)),
	}


## Settle `units` off `node_id`'s accrued line, into the caller's own accounting. The
## holdings module is the only authority for the line; what the units become is the
## caller's business, because turning a line into items is the economy's call.
static func settle(actor: Actor, node_id: StringName, units: int) -> Dictionary:
	var state := _state(actor)
	if units <= 0:
		return _refuse(actor, node_id, HoldingsState.NO_PERIODS, state)
	var settled := HoldingsState.settle(state, node_id, units)
	if settled <= 0:
		return _refuse(actor, node_id, HoldingsState.NO_PERIODS, state)
	_save(actor, state)
	return {
		"ok": true,
		"reason": "",
		"settled": settled,
		"accrued": HoldingsState.accrued(state, node_id),
	}


## Pay a declared conflict prize against `node_id`. **Called by the conflict module, never by
## the holder** — one module owns how a conflict ends (BL-0185).
##
## `prize` is `ownership` (the holder swaps), `recognition` (a standing delta the caller
## applies to the institution) or `tribute` (the loser owes the line for `tribute_periods`).
## Holdings NEVER computes a standing delta: ADR 0084 says an institution's political number
## is written by the institution's own module, and this one has no edge to it.
static func apply_prize(actor: Actor, node_id: StringName, prize: Dictionary) -> Dictionary:
	var state := _state(actor)
	var contest := HoldingsState.contest(state, node_id)
	if contest.is_empty():
		return _refuse(actor, node_id, HoldingsState.UNKNOWN_NODE, state)
	var kind := StringName(prize.get("prize", &""))
	match kind:
		&"ownership":
			var winner: Dictionary = (prize.get("winner", {}) as Dictionary).duplicate(true)
			state["nodes"][String(node_id)]["owner"] = winner
		&"recognition":
			pass  # The political layer writes standing; holdings records that it was owed.
		&"tribute":
			var periods := maxi(0, int(prize.get("tribute_periods", 0)))
			var line_key := String((prize.get("loser", {}) as Dictionary).get("id", ""))
			if periods > 0 and line_key != "":
				var def := ResourceNodeCatalog.instance().definition(node_id)
				var owed := maxi(
					0, int((contest.get("challenger", {}) as Dictionary).get("upkeep", 0))
				)
				_owe_tribute(state, line_key, def, periods, owed)
		_:
			HoldingsState.resolve_contest(state, node_id)
			return _refuse(actor, node_id, "unknown_prize", state)
	HoldingsState.resolve_contest(state, node_id)
	_save(actor, state)
	# **This is the conflict-to-story seam.** A decided standoff announces the prize it paid
	# and nothing else: the consumer decides whether it is a chronicle line, a quest step or a
	# screen. The holder is reported as it now stands, which is empty for a recognition or
	# tribute prize — those moved no holder, and a consumer that read the empty string as an
	# abandoned node would be inventing an outcome the conflict never reached.
	events().prize_applied.emit(
		String(actor.id),
		node_id,
		String(kind),
		String(HoldingsState.holder(state, node_id).get("id", "")),
		String((prize.get("winner", {}) as Dictionary).get("id", ""))
	)
	return {"ok": true, "reason": "", "prize": String(kind)}


## The read model: every node the ledger knows, each with its live holder, condition, the
## line it has accrued, and any open challenge. `{}` when there is no actor.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var state := _state(actor)
	var nodes: Dictionary = {}
	for node_id in (state["nodes"] as Dictionary).keys():
		var entry := state["nodes"][node_id] as Dictionary
		var contest := HoldingsState.contest(state, StringName(node_id))
		var def := ResourceNodeCatalog.instance().definition(StringName(node_id))
		nodes[String(node_id)] = {
			"node_id": String(node_id),
			"known": ResourceNodeCatalog.instance().has_definition(StringName(node_id)),
			"vacant": OwnerRef.is_vacant(entry.get("owner", {})),
			"owner": (entry.get("owner", {}) as Dictionary).duplicate(true),
			"condition": int(entry.get("condition", 0)),
			"resting": int(entry.get("resting", 0)),
			"accrued": HoldingsState.accrued(state, StringName(node_id)),
			"contested": not contest.is_empty(),
			"conflict_id": String(contest.get("conflict_id", "")),
			"kind": String(def.normalized_kind()) if def != null else "",
			"yield_per_period": def.yield_per_period if def != null else 0,
			"upkeep_per_period": def.upkeep_per_period if def != null else 0,
		}
	return {
		"actor_id": String(actor.id),
		"nodes": nodes,
		"node_count": nodes.size(),
		"held_count": _held_count(state),
		"contested_count": (state["contested"] as Dictionary).size(),
		"catalog": ResourceNodeCatalog.instance().views(),
		"resolver_installed": _resolver.is_valid(),
		# ADR 0165: the criterion the audit found absent — a caller must be able to tell "no
		# store is wired" from "a store is holding an empty world", which before this were the
		# same answer. `MarketApi.summary` deliberately publishes no seam booleans and is proved
		# by behaviour instead, so this mirrors `CustodyApi` rather than inventing a new key.
		"store_installed": _store != null,
	}


## The ledger exactly as core persists it, so a caller never reaches into `module_data`.
static func state(actor: Actor) -> Dictionary:
	if actor == null:
		return HoldingsState.empty()
	var state := HoldingsState.normalize(actor.get_module_data(MODULE_KEY))
	actor.set_module_data(MODULE_KEY, state)
	return state


## Content audit: every authored node is usable.
static func validate() -> Array[String]:
	return ResourceNodeCatalog.validate()


# --- internals ---------------------------------------------------------------


## Open exactly one standoff against a held node. The holder is not touched.
##
## **The row is persisted**, not just built: a challenge that is returned but never written
## is a claim that silently did not happen, and the next challenger would open a second
## standoff on a node that already had one.
static func _challenge(
	actor: Actor, state: Dictionary, node_id: StringName, owner: Dictionary
) -> Dictionary:
	var resolved := _resolve(owner)
	if not bool(resolved["ok"]):
		return _refuse(actor, node_id, String(resolved["reason"]), state)
	if (state["contested"] as Dictionary).size() >= MAX_CONTESTED:
		return _refuse(actor, node_id, HoldingsState.ALREADY_CONTESTED, state)
	var opened := HoldingsState.contest_node(state, node_id, &"conflict_%s" % node_id, owner)
	if not bool(opened["ok"]):
		return _refuse(actor, node_id, String(opened["reason"]), state)
	_save(actor, state)
	# The holder is byte-identical across this write — that is ADR 0085's invariant, and the
	# signal says so explicitly so a consumer cannot read a challenge as a conquest.
	events().node_contested.emit(
		String(actor.id),
		node_id,
		String(HoldingsState.holder(state, node_id).get("id", "")),
		String(owner.get("id", ""))
	)
	return {
		"ok": true,
		"reason": "",
		"contested": true,
		"conflict_id": String(opened.get("conflict_id", "")),
		"holder": HoldingsState.holder(state, node_id),
	}


## Resolve a holder through the injected seam. Refuses closed, and refuses LOUDLY when
## nothing is installed, because an institution silently unable to hold anything is worse
## than an error.
static func _resolve(owner: Dictionary) -> Dictionary:
	if owner.is_empty():
		return {"ok": false, "reason": HoldingsState.NO_HOLDER}
	var kind := StringName(owner.get("kind", ""))
	if not OwnerRef.KINDS.has(kind):
		return {"ok": false, "reason": HoldingsState.UNKNOWN_OWNER_KIND}
	if not _resolver.is_valid():
		return {"ok": false, "reason": HoldingsState.NO_RESOLVER}
	var answered: Variant = _resolver.call(String(kind), String(owner.get("id", "")))
	if not answered is Dictionary:
		return {"ok": false, "reason": HoldingsState.UNKNOWN_OWNER}
	if not bool((answered as Dictionary).get("ok", false)):
		var reason := String((answered as Dictionary).get("reason", HoldingsState.UNKNOWN_OWNER))
		return {"ok": false, "reason": reason}
	return {"ok": true, "reason": ""}


## ## What `claim_floor` counts, and why it is not a standing (ADR 0248)
##
## **The count of resource nodes the holder ALREADY holds.** It is a concentration gate:
## you consolidate shallow ground before you may take the deep vein, and every number it
## is read against is in this ledger. Nothing outside this module is consulted, so the
## answer cannot drift from the world it describes.
##
## It used to read `owner.get("standing", 0)`, and that was an unreachable gate: an
## `OwnerRef` is `{kind, id}` (`contracts/owner_ref.gd`) and both production producers
## build exactly that, so the read was always 0 and **7 of the 16 authored nodes** refused
## `claim_below_floor` forever. There is no actor-global `standing` to have read instead —
## every `standing` in this repo is one institution's capped ledger (`ClanState`,
## `SectState`, `NationState`, `social`'s bond), so "the holder's standing" names no single
## number and a resource node has no business choosing one. See ADR 0248 for the rejected
## alternatives; the short version is that the ref shape is right and the GATE was wrong.
##
## **The floor is kind-agnostic on purpose.** The old rule refused every non-`actor` holder
## outright, which meant an institution could never take a floored node — a gate that
## answers one kind is not a gate, it is a type check. A count of ledger rows is a fact for
## all four `OwnerRef.KINDS` equally, and `_held_by` is that count.
static func _meets_floor(state: Dictionary, def: ResourceNodeDef, owner: Dictionary) -> bool:
	if def == null or def.claim_floor <= 0:
		return true
	return _held_by(state, owner) >= def.claim_floor


## How many nodes `owner` holds in this ledger. Counted from the ledger's OWN rows rather
## than from a summary of the catalog, so a node the ledger has never heard of contributes
## nothing — the gate is about ground actually taken, which is what `claim` writes.
##
## Keyed by [method OwnerRef.storage_key] rather than by bare `id`, because a clan and an
## actor may share an id and a count that collapsed them would answer one holder's floor
## with another's ground.
static func _held_by(state: Dictionary, owner: Dictionary) -> int:
	var key := _storage_key_of(owner)
	if key == "":
		return 0
	var held := 0
	for node_id in (state["nodes"] as Dictionary).keys():
		var holder = HoldingsState.holder(state, StringName(node_id))
		if holder.is_empty() or OwnerRef.is_vacant(holder):
			continue
		if _storage_key_of(holder) == key:
			held += 1
	return held


## `OwnerRef.storage_key` for a plain dictionary, or `""` for one naming nobody. The empty
## string is the refusal because a ledger key is never empty: `storage_key` is
## `"%s:%s"`, so no holder can produce one, and a nameless ref therefore matches nothing.
static func _storage_key_of(owner: Dictionary) -> String:
	var ref := OwnerRef.from_dict(owner)
	return "" if ref.is_empty() else ref.storage_key()


static func _charge_claim_cost(state: Dictionary, def: ResourceNodeDef, owner: Dictionary) -> void:
	if def == null or def.claim_cost.is_empty():
		return
	_owe(state, owner, def.claim_cost)


## Upkeep accrues against the HOLDER's own line, keyed by the holder rather than the node,
## so an institution's upkeep is visible as its obligation and never as a second pile of
## goods (BL-0191).
static func _charge_upkeep(
	state: Dictionary, def: ResourceNodeDef, periods: int, owner: Dictionary
) -> void:
	if def == null or def.upkeep_per_period <= 0:
		return
	var units := def.upkeep_per_period * periods
	var key := "%s:upkeep:%s" % [String(owner.get("kind", "")), String(owner.get("id", ""))]
	var line := state["line"] as Dictionary
	line[key] = int(line.get(key, 0)) + units


static func _owe_tribute(
	state: Dictionary, holder_id: String, def: ResourceNodeDef, periods: int, units: int
) -> void:
	var owed := maxi(0, int(def.upkeep_per_period)) * periods if def != null else units
	var key := "%s:tribute" % holder_id
	var line := state["line"] as Dictionary
	line[key] = int(line.get(key, 0)) + owed


## Record obligation TERMS against a holder's line. Terms and counts, never authored
## amounts, so retuning a rate never rewrites a save.
static func _owe(state: Dictionary, owner: Dictionary, terms: Dictionary) -> void:
	var key := String(owner.get("id", ""))
	if key == "":
		return
	var line := state["line"] as Dictionary
	for term in terms.keys():
		var line_key := "%s:term:%s" % [key, String(term)]
		line[line_key] = int(line.get(line_key, 0)) + int(terms[term])


static func _ensure_entry(state: Dictionary, node_id: StringName) -> void:
	if not (state["nodes"] as Dictionary).has(String(node_id)):
		state["nodes"][String(node_id)] = {"owner": {}, "condition": 0, "resting": 0}


static func _held_count(state: Dictionary) -> int:
	var held := 0
	for node_id in (state["nodes"] as Dictionary).keys():
		if not OwnerRef.is_vacant((state["nodes"][node_id] as Dictionary).get("owner", {})):
			held += 1
	return held


## Read the ledger. With a store installed the ledger is shared by every actor, so a rival
## sees what the holder sees; without one it falls back to the actor's own mirror, which is
## correct for a single-holder save and is why `attach` still mirrors there.
static func _state(actor: Actor) -> Dictionary:
	if _store != null and _store.has_method(&"read_ledger"):
		return HoldingsState.normalize(_store.call(&"read_ledger"))
	if actor == null:
		return HoldingsState.empty()
	return HoldingsState.normalize(actor.get_module_data(MODULE_KEY))


## Write the ledger back to the store when there is one, and always mirror it onto the
## actor so a single-player save still carries the holdings.
static func _save(actor: Actor, state: Dictionary) -> void:
	var normalized := HoldingsState.normalize(state)
	if _store != null and _store.has_method(&"write_ledger"):
		_store.call(&"write_ledger", normalized)
	if actor != null:
		actor.set_module_data(MODULE_KEY, normalized)


## ## The ONE place every refusal leaves this facade, and it ANNOUNCES (DEF-0221)
##
## Every verb below ends here rather than building its own dictionary, so the refusal
## ANSWER and the refusal ANNOUNCEMENT cannot be two code paths that drift. That is why
## `actor` and `node_id` became parameters: the identity a refusal announces is part of the
## refusal, and threading it explicitly means no module-level state can be stale when the
## emission fires.
##
## **The announcement is not the opposite of "a refusal wrote nothing" — it is beside it.**
## `holdings_events.gd` declares `holding_refused(actor_id, node_id, reason)` and says
## exactly why: "carries the named reason so a panel renders the rule it was given rather
## than inventing one (ADR 0084), and so an action failing is observable rather than
## silent". A rule that fired and changed no ledger is still a game rule firing: the player
## who was refused a vein needs the reason rendered, and a caller that polls `summary()`
## cannot tell a refusal from a verb nobody called.
##
## **The signal says a refusal, and it names one.** Every OTHER signal on this contract
## announces a fact already written and a consumer must never read one as a veto; this one
## announces that nothing was. So the two facts a caller needs are independent and both are
## carried: the returned dictionary says `ok: false` (no ledger write) and the signal says
## WHICH rule refused and ON WHICH NODE. Emitting here means no call site can forget to.
static func _refuse(
	actor: Actor, node_id: StringName, reason: String, state: Dictionary
) -> Dictionary:
	if actor != null:
		events().holding_refused.emit(String(actor.id), node_id, reason)
	return {"ok": false, "reason": reason, "contested": false, "holder": {}, "state": state}
