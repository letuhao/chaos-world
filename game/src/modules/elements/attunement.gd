class_name ElementAttunement
extends RefCounted

## The affinity door (ADR 0924, BL-0926): how an element a body was not born with
## gets its spark, and how any feature can register another way to grant one.
##
## ## The door, and why it is a seam
##
## A root opens in the novels through treasures, elixirs, life-bound dharma
## treasures and refining arts, and the list grows with the game. So this module
## resolves the GRANT — the tier gate, the cap, the affinity write — and the source
## owns its own requirement and consumption ([AffinitySource]). Treasures and
## awakening elixirs ship as this module's own DERIVED sources (item ids it already
## names); anything else registers through the facade, and a registered source wins
## on a bigger grant like any other.
##
## ## The price, tiered and capped (owner ruling 2026-10-08)
##
## A grant pays `GAIN_BY_TIER[element.tier]`, and it is gated by the SAME door that
## gates USING an element (`ElementMastery.usable`: the rank must reach the tier and
## the qi realm must allow it — one door, never a second opinion). A root stops at
## `CAP_BY_TIER[element.tier]`: affinity is the INNATE axis, and a rare resource
## buys a finite root — while everything that must scale with the ladder keeps
## scaling (mastery is uncapped and the realm multiplier is shared), so the cap
## bounds the root and never the climb.
##
## A grant never overshoots the cap: the last treasure into a nearly-full root pays
## only the room that is left, because a consumed item that grants nothing is a
## worse answer than a smaller number.
##
## ## What a source spends, and what is remembered
##
## `consume` is the source's own business (an item source consumes its item). A
## `once` source — the learned art's opening — is remembered as SPENT in the
## actor's `module_data`, so a save cannot re-open a root the art already opened.

const _ITEMS := preload("res://src/modules/items/api.gd")

## Where the once-only grants are remembered on the actor.
const MODULE_KEY := &"element_attunement"

## The two item families this module names itself, one per element.
const TREASURE_SUFFIX := "_awakening_treasure"
const AWAKENING_ELIXIR_SUFFIX := "_awakening_elixir"

## What one grant of each family pays, keyed by the element's TIER and never by the
## element (the same shape as `ELIXIR_GAIN_BY_TIER` in training.gd): the ruling's
## numbers, +2/+3/+5 for a treasure and double for the crafted elixir.
const TREASURE_GAIN_BY_TIER := {1: 2.0, 2: 3.0, 3: 5.0}
const ELIXIR_GAIN_BY_TIER := {1: 4.0, 2: 6.0, 3: 10.0}

## What a root-refining art's two loops pay: the learn-time opening mirrors the
## treasure's per-tier grant, and the refine is the slow +1 that runs to the cap.
const ART_GRANT_BY_TIER := {1: 2.0, 2: 3.0, 3: 5.0}
const ART_REFINE_STEP := 1.0

## Where a root stops, by tier. The innate axis is finite by design; the scaling
## axes (mastery, the realm multiplier) are what keep growing.
const CAP_BY_TIER := {1: 12.0, 2: 15.0, 3: 18.0}

## The named refusals. One vocabulary, so a screen and a test say the same thing.
const R_NO_ACTOR := "no_actor"
const R_UNKNOWN_ELEMENT := "unknown_element"
const R_LOCKED := "element_locked"
const R_AT_CAP := "at_cap"
const R_NO_SOURCE := "no_source"
const R_REFUSED := "refused"

## Every externally registered source, by id. Static because sources are DEFINITIONS
## (a treasure is not a property of one body) and the module resolves them per
## actor. Tests clear it; the app registers the first-party ones.
static var _registered: Dictionary = {}


static func treasure_id(element: StringName) -> StringName:
	return StringName("element_" + String(element) + TREASURE_SUFFIX)


static func awakening_elixir_id(element: StringName) -> StringName:
	return StringName("element_" + String(element) + AWAKENING_ELIXIR_SUFFIX)


## Register a source. Answers false for a malformed one rather than storing a source
## that would refuse every actor in silence: an id, an element, a positive amount and
## both callables are the contract.
static func register(source: AffinitySource) -> bool:
	if source == null or source.id == &"" or source.element == &"":
		return false
	if not (source.amount > 0.0) or not is_finite(source.amount):
		return false
	if not source.check.is_valid() or not source.consume.is_valid():
		return false
	_registered[source.id] = source
	return true


static func clear_registered_sources() -> void:
	_registered.clear()


## The cap of `element_id`'s root, from its authored tier. An unknown element reads
## the tier-1 cap rather than failing: a caller with no element has no root to cap.
static func cap_for(element_id: StringName) -> float:
	var entry := ElementDefaults.rules().element(element_id)
	var tier := 1 if entry == null else maxi(1, entry.tier)
	return float(CAP_BY_TIER.get(tier, CAP_BY_TIER[1]))


## The sources that could open `element_id` for `actor` RIGHT NOW, best first. The
## two derived item families plus every registered source whose element matches and
## whose requirement is met; a spent `once` source is not a candidate.
static func offers(actor: Actor, element_id: StringName) -> Array[AffinitySource]:
	var out: Array[AffinitySource] = []
	if actor == null:
		return out
	var entry := ElementDefaults.rules().element(element_id)
	if entry == null:
		return out
	var tier := maxi(1, entry.tier)
	out.append(
		_derived(
			StringName("treasure:" + String(element_id)),
			element_id,
			float(TREASURE_GAIN_BY_TIER.get(tier, TREASURE_GAIN_BY_TIER[1])),
			tier,
			"Awakening Treasure",
			false,
			treasure_id(element_id)
		)
	)
	out.append(
		_derived(
			StringName("elixir:" + String(element_id)),
			element_id,
			float(ELIXIR_GAIN_BY_TIER.get(tier, ELIXIR_GAIN_BY_TIER[1])),
			tier,
			"Awakening Elixir",
			false,
			awakening_elixir_id(element_id)
		)
	)
	var spent := _spent(actor)
	for key in _registered:
		var source: AffinitySource = _registered[key]
		if source.element != element_id:
			continue
		if source.once and spent.has(String(source.id)):
			continue
		out.append(source)
	var available: Array[AffinitySource] = []
	for source in out:
		if bool(source.check.call(actor)):
			available.append(source)
	# Best first: the biggest grant, then the id, so a tie cannot depend on a
	# dictionary's iteration order.
	available.sort_custom(
		func(a: AffinitySource, b: AffinitySource) -> bool:
			if a.amount != b.amount:
				return a.amount > b.amount
			return String(a.id) < String(b.id)
	)
	return available


## The read a screen renders: the root's affinity, its cap, and the next grant the
## door would pay. `{}` for an unknown element or no actor, and `blocked` names the
## refusal the press would answer with ("" when the press would land).
static func offer(actor: Actor, element_id: StringName) -> Dictionary:
	if actor == null:
		return {}
	var entry := ElementDefaults.rules().element(element_id)
	if entry == null:
		return {}
	var cap := cap_for(element_id)
	var current := actor.affinities.get_value(element_id)
	var view := {
		"affinity": current,
		"cap": cap,
		"gain": 0.0,
		"source": "",
		"label": "",
		"blocked": "",
	}
	if not ElementMastery.usable(actor, element_id):
		view["blocked"] = R_LOCKED
		return view
	if current >= cap:
		view["blocked"] = R_AT_CAP
		return view
	var available := offers(actor, element_id)
	if available.is_empty():
		view["blocked"] = R_NO_SOURCE
		return view
	var source := available[0]
	view["gain"] = minf(source.amount, cap - current)
	view["source"] = String(source.id)
	view["label"] = source.label
	return view


## Attune `element_id`: spend the best available source and raise the affinity.
##
## The refusals, in the order they are asked: an element the realm does not allow
## (`element_locked`, the same door the technique firing site uses), a root already
## at its cap (`at_cap`), no source whose requirement is met (`no_source`), and a
## source that refused to be spent (`refused`).
static func attune(actor: Actor, element_id: StringName) -> Dictionary:
	var gate := _gate(actor, element_id)
	if not bool(gate.get("ok", false)):
		return gate
	var available := offers(actor, element_id)
	if available.is_empty():
		return {"ok": false, "reason": R_NO_SOURCE}
	return _apply(actor, available[0], gate)


## Apply ONE registered source by id (ADR 0924): the learn-time grant a caller knows
## by name, rather than the pick-the-best form `attune` is. The same gate, cap and
## once-record rules apply, and an unknown or already-spent source reads `no_source`.
static func attune_source(actor: Actor, source_id: StringName) -> Dictionary:
	var source: AffinitySource = _registered.get(source_id)
	if source == null:
		return {"ok": false, "reason": R_NO_SOURCE}
	var gate := _gate(actor, source.element)
	if not bool(gate.get("ok", false)):
		return gate
	if source.once and _spent(actor).has(String(source.id)):
		return {"ok": false, "reason": R_NO_SOURCE}
	if not bool(source.check.call(actor)):
		return {"ok": false, "reason": R_NO_SOURCE}
	return _apply(actor, source, gate)


## The gate and the cap, in one place: the element must exist, the climb must allow
## its tier (`usable`), and the root must have room.
static func _gate(actor: Actor, element_id: StringName) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": R_NO_ACTOR}
	var rules := ElementDefaults.rules()
	var entry := rules.element(element_id) if rules != null else null
	if entry == null:
		return {"ok": false, "reason": R_UNKNOWN_ELEMENT}
	if not ElementMastery.usable(actor, element_id, rules):
		return {"ok": false, "reason": R_LOCKED}
	var cap := cap_for(element_id)
	var current := actor.affinities.get_value(element_id)
	if current >= cap:
		return {"ok": false, "reason": R_AT_CAP, "cap": cap}
	return {"ok": true, "element": element_id, "cap": cap, "current": current}


## Spend `source` and write the grant, capped at the room the gate measured.
static func _apply(actor: Actor, source: AffinitySource, gate: Dictionary) -> Dictionary:
	if not bool(source.consume.call(actor)):
		return {"ok": false, "reason": R_REFUSED, "source": String(source.id)}
	var element_id: StringName = gate.get("element", &"")
	var gain := minf(source.amount, float(gate.get("cap", 0.0)) - float(gate.get("current", 0.0)))
	ElementTraining.awaken(actor, element_id, gain)
	if source.once:
		_remember_spent(actor, source.id)
	return {
		"ok": true,
		"element": String(element_id),
		"gain": gain,
		"source": String(source.id),
		"label": source.label,
	}


## One item-backed source: the requirement is the item being held and the
## consumption is spending it, both closed over the id.
static func _derived(
	id: StringName,
	element_id: StringName,
	amount: float,
	tier: int,
	label: String,
	once: bool,
	item_id: StringName
) -> AffinitySource:
	var held := func(p_actor: Actor) -> bool: return _ITEMS.has_item(p_actor, item_id)
	var spend := func(p_actor: Actor) -> bool: return _ITEMS.consume_item(p_actor, item_id)
	return AffinitySource.make(id, element_id, amount, tier, label, once, held, spend)


static func _spent(actor: Actor) -> Array:
	var data := actor.get_module_data(MODULE_KEY)
	var spent: Variant = data.get("spent", [])
	return spent if spent is Array else []


static func _remember_spent(actor: Actor, source_id: StringName) -> void:
	var data := actor.get_module_data(MODULE_KEY)
	var spent: Variant = data.get("spent", [])
	var rows: Array = spent if spent is Array else []
	if not rows.has(String(source_id)):
		rows.append(String(source_id))
	actor.set_module_data(MODULE_KEY, {"spent": rows})
