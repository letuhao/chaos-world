class_name DestinyApi
extends RefCounted

## Public facade for the `destiny` module. Other modules may reference ONLY
## this file (`api.gd`).
##
## Concrete implementations live beside this file and are wired in `app/`.
##
## **Fate is earned, never chosen and never equipped** (ADR 0065). There is no
## slot to fill, no picker to open, and no revoke path — not for a penalty, not
## for a reset, not for a debug tool. A fate or destiny, once earned, is owed to
## the player permanently. That is the design, and it is why nothing in this
## facade removes anything.
##
## Two concepts, deliberately distinct:
##   - **Fate** — a consequence of one specific deed. Carries stat modifiers and
##     can be read as a gate condition.
##   - **Destiny** — the narrative identity a player accrues toward. Carries no
##     mandatory numbers; it exists to open or close story, quest and event
##     content that does not exist yet.
##
## Other modules earning fate is the intended use. Combat records a duel, a
## breakthrough path grants an oath, character creation grants an origin. This
## module never reaches back to call them: it is a write target, not a listener
## (ADR 0065).

## `actor.module_data` key the versioned ledger is persisted under (ADR 0027).
## The only key this module writes. It used to sit beside a `STATE_COMPONENT`
## never wired to an `Actor` component the way every sibling module's is — the
## same `&"destiny_state"` string in a second namespace, which reads like a
## second source of truth and is not one.
const MODULE_KEY := DestinyState.MODULE_KEY


## Attach the module to `actor`. Restores any ledger a prior `Actor.from_dict`
## carried, normalizes it against the current catalog, and rebuilds the stat
## projection and the `Actor.traits` mirror from the ledger. Idempotent, and
## safe to call before anything has been earned.
static func attach(actor: Actor) -> void:
	var ledger := DestinyState.normalize(
		actor.get_module_data(MODULE_KEY), _known_fates(), _known_destinies()
	)
	actor.set_module_data(MODULE_KEY, ledger)
	DestinyProjection.apply(actor, ledger)


## Earn a fate for `actor`. Exactly-once: earning a fate the actor already holds
## appends nothing and re-projects nothing. Returns the ledger so a caller can
## see the outcome without a second read.
##
## `source` names the system that earned it, for the ledger, the history trail
## and any consumer that wants to react to *how*. An unknown `fate_id` is
## refused rather than recorded: a fate the catalog does not define is a content
## bug, and storing it would create a fate nothing can ever pay out.
static func earn_fate(actor: Actor, fate_id: StringName, source: String = "") -> Dictionary:
	var ledger := _ledger(actor)
	if DestinyState.has_fate(ledger, fate_id):
		return ledger
	var def := FateCatalog.instance().fate_definition(fate_id)
	if def == null:
		return ledger
	ledger["fates"][String(fate_id)] = {
		"source": source,
		"sequence": _next_sequence(ledger),
	}
	_record(ledger, "fate", fate_id, source)
	_persist(actor, ledger, "fate", fate_id)
	return ledger


## Earn a destiny branch for `actor`. Exactly-once, and exclusive within its
## `group`: earning one refuses every other destiny in the same group, which
## holds for good. Also appends every fate in `grants_fates`, in authored order,
## so a destiny can carry its consequence with it.
##
## Refuses — returning the ledger unchanged — when `requires_destinies` or
## `requires_fates` are not all held, or when another destiny in the same group
## is held. A refused earn is not an error the caller must handle: it means the
## player did not earn this one, which is a normal outcome.
static func earn_destiny(actor: Actor, destiny_id: StringName, source: String = "") -> Dictionary:
	var ledger := _ledger(actor)
	if DestinyState.has_destiny(ledger, destiny_id):
		return ledger
	var def := FateCatalog.instance().destiny_definition(destiny_id)
	if def == null:
		return ledger
	if not DestinyGate.earnable(ledger, def):
		return ledger
	var entry := {
		"source": source,
		"sequence": _next_sequence(ledger),
		"bearing": def.bearing,
	}
	ledger["destinies"][String(destiny_id)] = entry
	_record(ledger, "destiny", destiny_id, source)
	for fate_id in def.grants_fates:
		if DestinyState.has_fate(ledger, fate_id):
			continue
		if FateCatalog.instance().fate_definition(fate_id) == null:
			continue
		ledger["fates"][String(fate_id)] = {
			"source": "destiny:%s" % destiny_id,
			"sequence": _next_sequence(ledger),
		}
		_record(ledger, "fate", fate_id, "destiny:%s" % destiny_id)
	_persist(actor, ledger, "destiny", destiny_id)
	return ledger


## Record progress on a named counter. Counters only ever rise: fate accrues,
## it is never refunded. Returns the value after the delta. A negative `amount`
## is clamped to zero movement rather than unwinding a counter.
static func record(actor: Actor, counter_id: StringName, amount: int = 1) -> int:
	var ledger := _ledger(actor)
	var total := DestinyState.counter_value(ledger, counter_id)
	if amount > 0:
		total += amount
		ledger["counters"][String(counter_id)] = total
		_record(ledger, "counter", counter_id, str(amount))
		# The APPLIED delta is threaded through rather than re-derived from the
		# ledger: `_persist` reads `total` back off it, and after an earlier record
		# the two differ, so passing the total twice announces "moved by 3" on a
		# step that moved it by one.
		_persist(actor, ledger, "counter", counter_id, amount)
	return total


## The recorded value of a counter, 0 when never recorded.
static func counter(actor: Actor, counter_id: StringName) -> int:
	if actor == null:
		return 0
	return DestinyState.counter_value(_ledger(actor), counter_id)


## Whether `actor` holds `fate_id`. The question a gate asks.
static func has_fate(actor: Actor, fate_id: StringName) -> bool:
	if actor == null:
		return false
	return DestinyState.has_fate(_ledger(actor), fate_id)


## Whether `actor` holds `destiny_id`, or any alias authored for it. Alias
## resolution is NOT re-implemented here: `DestinyGate.holds_destiny()` is the one
## place that knows an id and its aliases are the same answer in both directions,
## and the facade asks it rather than keeping a copy to drift from the gate's.
static func has_destiny(actor: Actor, destiny_id: StringName) -> bool:
	if actor == null:
		return false
	return DestinyGate.holds_destiny(_ledger(actor), destiny_id)


## Every destiny the actor holds, canonically ordered. A plain id list, so a
## caller that needs reasons asks `gate()` and one that needs names asks the
## catalog through `summary()`.
static func destinies(actor: Actor) -> Array[StringName]:
	if actor == null:
		return []
	return DestinyState.destiny_ids(_ledger(actor))


## Every fate the actor holds, canonically ordered.
static func fates(actor: Actor) -> Array[StringName]:
	if actor == null:
		return []
	return DestinyState.fate_ids(_ledger(actor))


## Whether gated content may open for `actor`.
##
## `requirement` is authored data, never code. It is either an empty dictionary
## — ungated, always open — or a `{verb: ..., ...}` map naming exactly one of
## the gate verbs (`has_fate`, `has_destiny`, `counter`, `all_of`, `any_of`,
## `none_of`).
##
## Returns `{ok: bool, reason: String, unmet: Array[Dictionary]}` where each
## unmet entry is `{kind, id, required, actual, label}` — the same shape
## `ItemRequirement.unmet()` produces, so a panel renders a reason it did not
## invent. `ok` is the whole answer; the rest is for display.
static func gate(actor: Actor, requirement: Dictionary) -> Dictionary:
	var verdict := DestinyGate.evaluate(actor, requirement)
	if not bool(verdict.get("ok", false)) and actor != null:
		DestinyProjection.events().gate_failed.emit(
			String(actor.id), String(verdict.get("reason", "")), requirement
		)
	return verdict


## The actor's versioned ledger exactly as core persists it. This is the payload
## a save carries, so a caller never reaches into `actor.module_data`.
static func state(actor: Actor) -> Dictionary:
	if actor == null:
		return DestinyState.empty()
	return DestinyState.normalize(
		actor.get_module_data(MODULE_KEY), _known_fates(), _known_destinies()
	)


## A read-only, primitive-only snapshot built for a codex UI: what the actor
## holds, and what exists but is still hidden. Held fates and destinies carry
## their full authored copy; hidden ones carry only a teaser and `held: false`.
##
## One call answers the whole screen, which is why the facade needs no separate
## catalog accessor for the UI: `items` and `body_cultivation` are already at
## the twelve-method cap and this module must not become the next one.
static func summary(actor: Actor) -> Dictionary:
	var ledger := _ledger(actor)
	var out := {
		"has_actor": actor != null,
		"actor_id": "" if actor == null else String(actor.id),
		"fate_count": (ledger["fates"] as Dictionary).size(),
		"destiny_count": (ledger["destinies"] as Dictionary).size(),
		"fates": {},
		"destinies": {},
		"hidden_fate_count": 0,
		"hidden_destiny_count": 0,
		"counters": {},
	}
	for counter_id in (ledger["counters"] as Dictionary).keys():
		out["counters"][String(counter_id)] = int((ledger["counters"] as Dictionary)[counter_id])
	for fate_id in FateCatalog.instance().fate_ids():
		var def := FateCatalog.instance().fate_definition(fate_id)
		if def == null:
			continue
		var entry: Dictionary = (ledger["fates"] as Dictionary).get(String(fate_id), {})
		var view := _fate_view(def, entry.has("source") or entry.has("sequence"))
		if not bool(view["visible"]):
			continue
		if not bool(view["held"]):
			out["hidden_fate_count"] = int(out["hidden_fate_count"]) + 1
		out["fates"][String(fate_id)] = view
	for destiny_id in FateCatalog.instance().destiny_ids():
		var def := FateCatalog.instance().destiny_definition(destiny_id)
		if def == null:
			continue
		var entry: Dictionary = (ledger["destinies"] as Dictionary).get(String(destiny_id), {})
		var held := entry.has("source") or entry.has("sequence")
		var view := _destiny_view(def, held)
		if not bool(view["visible"]):
			continue
		if not held:
			out["hidden_destiny_count"] = int(out["hidden_destiny_count"]) + 1
			# Folded in rather than exposed as a facade method: the facade is at
			# its twelve-method cap, and "what is still owed, and what is holding
			# it back" is exactly what a codex owes the player.
			var unmet := DestinyGate.unmet_prerequisites(ledger, def)
			view["available"] = unmet.is_empty()
			view["blocked_by"] = unmet
		out["destinies"][String(destiny_id)] = view
	return out


# --- Internals -------------------------------------------------------------


static func _ledger(actor: Actor) -> Dictionary:
	if actor == null:
		return DestinyState.empty()
	var pending: Dictionary = actor.get_module_data(MODULE_KEY)
	if pending.is_empty():
		attach(actor)
		pending = actor.get_module_data(MODULE_KEY)
	return DestinyState.normalize(pending, _known_fates(), _known_destinies())


## A known-fate filter for `normalize()`.
##
## `DestinyState` reads an EMPTY filter as "an unanswered question, not a
## denial" and keeps everything handed to it — `test_destiny_state.gd` asserts
## that deliberately, so the rule stays where it was authored. But a catalog
## that failed to load leaves this one empty, and then it can only mean "this
## build ships no fates", so an untrusted save would be persisted wholesale and
## the earn-only invariant (ADR 0065) would mean nothing.
##
## So the empty catalog is told apart HERE, at the one place that knows the
## filter came from the content tree and not a caller, and reported as **no
## filter** — which drops every entry, so an unreadable save is emptied rather
## than widened. The dropped ids are the ones no definition answers for.
static func _known_fates() -> Dictionary:
	var out := {}
	if not _catalog_loaded():
		return out
	for fate_id in FateCatalog.instance().fate_ids():
		out[String(fate_id)] = true
	return out


## A known-destiny filter for `normalize()`. Same rule as `_known_fates()`.
static func _known_destinies() -> Dictionary:
	var out := {}
	if not _catalog_loaded():
		return out
	for destiny_id in FateCatalog.instance().destiny_ids():
		out[String(destiny_id)] = true
	return out


## Whether the content tree loaded far enough for a filter derived from it to
## mean anything. Fates OR destinies, because a tree that lost one of the two is
## still partly loaded, and one filter keeping nothing while the other accepts
## everything is the failure this guards.
static func _catalog_loaded() -> bool:
	var catalog := FateCatalog.instance()
	return not catalog._destinies.is_empty() or not catalog._fates.is_empty()


static func _next_sequence(ledger: Dictionary) -> int:
	var highest := 0
	for key in (ledger["fates"] as Dictionary).keys():
		highest = maxi(highest, int((ledger["fates"] as Dictionary)[key].get("sequence", 0)))
	for key in (ledger["destinies"] as Dictionary).keys():
		highest = maxi(highest, int((ledger["destinies"] as Dictionary)[key].get("sequence", 0)))
	return highest + 1


static func _record(ledger: Dictionary, kind: String, id: StringName, detail: String) -> void:
	var history: Array = ledger["history"]
	# A bounded trail: enough to explain what the player is owed and in what
	# order, without growing a save forever.
	if history.size() >= DestinyState.HISTORY_LIMIT:
		return
	history.append(
		{"kind": kind, "id": String(id), "detail": detail, "sequence": _next_sequence(ledger)}
	)


## Persist, rebuild the stat projection and the trait mirror, then announce. The
## three effects are one operation because a half-applied earn — stats without a
## ledger, a ledger without stats — is the one state a player cannot recover from.
##
## `kind` is passed explicitly rather than inferred from the catalog: a counter
## id names no definition, and guessing would announce it as a destiny.
##
## `amount` is the delta a counter MOVED BY, which the ledger cannot answer once
## the delta is in it: `DestinyEvents.counter_changed` declares `amount` as the
## applied delta and `total` as the value after it, so `total - amount` recovers
## the previous value only when the caller was told the real delta.
static func _persist(
	actor: Actor, ledger: Dictionary, kind: String, earned_id: StringName, amount: int = 0
) -> void:
	actor.set_module_data(MODULE_KEY, ledger)
	DestinyProjection.apply(actor, ledger)
	var bus := DestinyProjection.events()
	match kind:
		"fate":
			bus.fate_earned.emit(
				String(actor.id),
				earned_id,
				String((ledger["fates"] as Dictionary).get(String(earned_id), {}).get("source", ""))
			)
		"destiny":
			bus.destiny_earned.emit(
				String(actor.id),
				earned_id,
				String(
					(ledger["destinies"] as Dictionary).get(String(earned_id), {}).get("source", "")
				)
			)
		_:
			var total := int((ledger["counters"] as Dictionary).get(String(earned_id), 0))
			bus.counter_changed.emit(String(actor.id), earned_id, amount, total)


static func _fate_view(def: FateDef, held: bool) -> Dictionary:
	var reveal := held or def.visibility == FateDef.REVEALED
	return {
		"id": String(def.id),
		"held": held,
		"visible": def.is_visible(),
		"display_name": String(def.display_name) if reveal else "",
		"description": String(def.description) if reveal else String(def.teaser),
		"teaser": String(def.teaser),
		"category": String(def.category),
		"tier": def.tier,
		"tags": _string_list(def.tags),
		"modifier_count": def.build_modifiers().size(),
	}


static func _destiny_view(def: DestinyDef, held: bool) -> Dictionary:
	var reveal := held or def.visibility == DestinyDef.REVEALED
	return {
		"id": String(def.id),
		"held": held,
		"visible": def.is_visible(),
		"group": String(def.group),
		"display_name": String(def.display_name) if reveal else "",
		"description": String(def.description) if reveal else String(def.teaser),
		"bearing": String(def.bearing) if held else "",
		"grants_fate_count": def.grants_fates.size(),
	}


static func _string_list(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
