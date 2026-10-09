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
	# A null actor earns nothing. Refused here rather than at `_persist`, because
	# the ledger is computed against `DestinyState.empty()` for a null actor and
	# the write is what actually crashes. A consumer wiring an earn through a
	# half-built actor gets "nothing happened" instead of an engine error.
	var ledger := _ledger(actor)
	if actor == null:
		return ledger
	if DestinyState.has_fate(ledger, fate_id):
		return ledger
	var def := FateCatalog.instance().fate_definition(fate_id)
	if def == null:
		return ledger
	if not DestinyGate.fate_earnable(ledger, def):
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
	# Same refusal as `earn_fate`: nothing is written for an actor that is not
	# there, and the write is what would crash.
	if actor == null:
		return ledger
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
## Register the starter pack `destiny_id` hands a body, REPLACING the default kit.
##
## The replacement is the whole contract and it is deliberate: a pack is one
## complete answer to "what does this body begin holding", so filing a second one
## under the same destiny overwrites the first. Re-running this verb on every boot
## is therefore how a pack is corrected, and a pack authored twice is a fix, not
## a doubled kit. See [method DestinyStarterPacks.register].
##
## Refused — writing nothing — for an empty `destiny_id`, for a `destiny_id` the
## catalog does not ship (a pack filed under a destiny no body can ever hold can
## never be resolved, so storing it would read as a working registration), and for
## a malformed row set, which [method DestinyStarterPack.make] names by reason.
##
## Registering grants nothing. The pack is DATA — authored item ids and counts —
## and turning rows into real instances is the composition root's call to
## `ItemsApi.generate`, which is why this module declares no `items` dependency
## for a feature about what a player starts holding.
static func register_starter_pack(destiny_id: StringName, rows: Array) -> Dictionary:
	return DestinyStarterPacks.instance().register(
		destiny_id, rows, FateCatalog.instance().destiny_definition(destiny_id) != null
	)


## What `actor` begins holding: `{pack_id, source, replaced, destiny_id, entries}`,
## primitives only, one entry per authored role.
##
## `replaced` is true exactly when a destiny this actor holds has registered a
## pack, and `entries` then carries the REGISTERED kit and nothing else — the
## default's rows are absent, not merged in. That is the property a caller can
## assert and a test can mutate, and it is the reason the read exists as a
## dictionary rather than a pack object: a caller mints from `entries` without
## ever holding a reference this module could mutate underneath it.
##
## A null actor is answered with the default rather than refused, because "what
## would this body start with" has an answer before the body exists and a
## composition root that builds the actor and asks in one breath must not have to
## order those two calls.
static func starter_pack(actor: Actor) -> Dictionary:
	var destiny_ids: Array[StringName] = []
	if actor != null:
		destiny_ids = DestinyState.destiny_ids(_ledger(actor))
	var answer := DestinyStarterPacks.instance().resolve(destiny_ids)
	var view := (answer["pack"] as DestinyStarterPack).to_dict()
	view["replaced"] = bool(answer["replaced"])
	view["destiny_id"] = String(answer["destiny_id"])
	view["has_actor"] = actor != null
	return view


static func record(actor: Actor, counter_id: StringName, amount: int = 1) -> int:
	# A null actor is refused rather than scored against the empty ledger: without
	# this the call returned `amount` for an actor that does not exist, so a
	# consumer wiring a beat through a half-built actor would be told a counter
	# moved when nothing was written. Every other read verb already null-checks.
	if actor == null or counter_id == &"":
		return 0
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


## The module's signal bus — the one instance every earn announcement fires on.
##
## ## What this cost: `counter` is no longer a facade verb
##
## The facade was AT [code]tools/arch/rules.py[/code]'s twelve-method cap, so
## reaching here was not free. What was retired is [code]counter(actor,
## counter_id)[/code] — the one public verb with **no caller in `game/src` at
## all**, counted over non-comment lines: every reader of a counter already holds
## the ledger [method state] hands back, and every writer holds it from the return
## value of [method record]. Read it as
## [code]DestinyApi.state(actor)["counters"][counter_id][/code].
##
## Two other verbs measured the same way and were kept, because a zero `src/`
## count is not a zero caller count: [method has_fate] is ten read sites and
## [method state] forty-nine, both almost entirely production assertions about a
## save round trip, and deleting those would have been deleting the checks rather
## than a redundancy. [method counter] was twenty, and unlike those it was a
## *convenience* over a dictionary key rather than a contract any gate could use.
##
## On the facade because a consumer has to be able to REACH it: `ui/` is a pure
## consumer and may name `destiny` only through this file, so a codex that listens
## to `fate_earned` / `destiny_earned` has exactly one legal way in. This is the
## house shape — [code]NpcApi.events()[/code], [code]HoldingsApi.events()[/code]
## and [code]EventApi.events()[/code] are the same verb on the same reason, the
## two newest of them at the full twelve.
##
## The bus itself still lives on [code]DestinyProjection[/code], and this returns
## it rather than keeping a second copy: one instance or the subscribers would be
## split across two buses and every listener would see nothing. Nothing outside
## the module emits through it — that stays the module's own rule.
static func events() -> DestinyEvents:
	return DestinyProjection.events()


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


## The total probability modifier for `probability_id` from all held fates
## and destinies (ADR 0274). Returns 0.0 when no modifier is authored.
##
## This is a READ, not a write: nothing is stored on the actor's stat stack.
## The modifier is computed on demand from the ledger, so it can never drift
## from the ledger or double-count. Consumers (combat, loot, breakthrough)
## call this when they need to know the total shift for a probability.
static func probability_modifier(actor: Actor, probability_id: StringName) -> float:
	if actor == null:
		return 0.0
	var total := 0.0
	var ledger := _ledger(actor)
	for fate_id in DestinyState.fate_ids(ledger):
		var def := FateCatalog.instance().fate_definition(fate_id)
		if def == null:
			continue
		for modifier in def.build_probability_modifiers():
			if modifier.stat == probability_id:
				total += modifier.value
	for destiny_id in DestinyState.destiny_ids(ledger):
		var def := FateCatalog.instance().destiny_definition(destiny_id)
		if def == null:
			continue
		for key in def.probability_modifiers.keys():
			if StringName(key) == probability_id:
				total += float(def.probability_modifiers[key])
	return total


## All probability modifiers for `actor`, as a flat dictionary of
## probability_id -> total shift (ADR 0274). Only probabilities with a
## non-zero total are included.
static func probability_modifiers(actor: Actor) -> Dictionary:
	var out := {}
	if actor == null:
		return out
	var ledger := _ledger(actor)
	for fate_id in DestinyState.fate_ids(ledger):
		var def := FateCatalog.instance().fate_definition(fate_id)
		if def == null:
			continue
		for modifier in def.build_probability_modifiers():
			var key := String(modifier.stat)
			out[key] = float(out.get(key, 0.0)) + modifier.value
	for destiny_id in DestinyState.destiny_ids(ledger):
		var def := FateCatalog.instance().destiny_definition(destiny_id)
		if def == null:
			continue
		for key in def.probability_modifiers.keys():
			var k := String(key)
			out[k] = float(out.get(k, 0.0)) + float(def.probability_modifiers[key])
	return out


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


## Every active difficulty event from all held fates (ADR 0404). Each entry is
## `{fate_id, event_type, magnitude, description}`, primitives only.
static func difficulty_events(actor: Actor) -> Array[Dictionary]:
	return DifficultyEventEngine.active_events(actor)


## The total difficulty modifier per event type, as a dictionary of
## `event_type -> float` (ADR 0404). Only event types with a non-zero total
## are included.
static func difficulty_modifier(actor: Actor) -> Dictionary:
	return DifficultyEventEngine.modifiers(actor)


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
	out["dialog"] = _dialog_summary(actor)
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
		# **Gated on `reveal`, and that is a published-key contract change (ADR
		# 0196, fate tag vocabulary).** `tags` used to be published unconditionally. It was harmless
		# while nothing read them; the moment a `tagged` gate exists, an unheld
		# hidden fate's tags become a spoiler channel — a codex can say "a gate
		# needs a duel-marked fate", and a player holding one learns that a
		# HIDDEN fate carries `duel` without ever earning it. `the_third_man_spared`
		# is `hidden` and carries `[mercy, duel]`, so this is not hypothetical.
		# An unheld hidden fate publishes `[]`; its real tags appear once held or
		# once the content is authored `revealed`.
		"tags": _string_list(def.tags) if reveal else [],
		"modifier_count": def.build_modifiers().size(),
		# Synergy edges (ADR 0383). Published unconditionally: they are prerequisite
		# hints, not spoilers — a player can see that a fate exists and what it needs
		# without seeing its effect. Gated on `reveal` for hidden fates, same as tags.
		"unlocks": _string_list(def.unlocks) if reveal else [],
		"requires": _string_list(def.requires) if reveal else [],
		"eligible_choices": _string_list(def.eligible_choices) if reveal else [],
	}


## The fate ids in `fate_id`'s choice group that the actor does not already hold,
## canonically ordered (ADR 0389). A fate the actor holds is not eligible to be
## offered. Empty when the fate is not part of a choice group or all choices
## are already held.
##
## This is a READ, not a write: nothing is stored on the actor. The UI calls
## this to decide whether to present a choice. The backend resolves the choice
## through existing earn logic — the player picks one and `earn_fate` records it.
static func eligible_choices(actor: Actor, fate_id: StringName) -> Array[StringName]:
	if actor == null:
		return []
	var def := FateCatalog.instance().fate_definition(fate_id)
	if def == null:
		return []
	var ledger := _ledger(actor)
	return def.unheld_choices(ledger)


## Whether the UI must present a choice for `fate_id`: multiple fates in the
## choice group are eligible (ADR 0389). The choice is a UI presentation of
## implicit eligibility, not a new earn path.
static func has_choice(actor: Actor, fate_id: StringName) -> bool:
	return eligible_choices(actor, fate_id).size() > 1


## The karmic virtue avenue (BL-0951 / ADR 0939, S12): spend the deeds the world remembers
## to mend a scarred past realm. The price is a DEED — read from the shared `WorldFact`
## ledger and impossible to buy — and `DestinyKarmicVirtue` owns the rule: which facts are
## virtue, how many a mend costs, and how the spent ones are tracked. This names it.
static func karmic_virtue(actor: Actor, realm_id: StringName = &"") -> Dictionary:
	return DestinyKarmicVirtue.mend_via_virtue(actor, realm_id)


## A codex row for one destiny branch.
##
## **`teaser` is published, and it is published UNCONDITIONALLY** — the same
## contract `_fate_view` states one function above. It used not to be published
## at all, and the row read `DestinyBranchRow._teaser()`'s
## `_view.get("teaser", "")` fell through to `description` on every destiny
## forever. That fall-through was masked, not harmless: for an unheld hidden
## branch `description` happens to BE the teaser (see below), so the dead read
## looked like it worked. It breaks the first time a hidden destiny is authored
## with an EMPTY `teaser` — `description` then is `""` too and the row renders a
## blank card for a branch it is supposed to hint at.
##
## The masking is deliberate and is NOT a reason to leave the key out:
## `description` carries the real copy once revealed and the teaser while locked,
## so the two fields answer different questions at different moments. A key that
## means "the description as it should read right now" cannot also be the source
## of the teaser for the moment when the description is withheld. The row reads
## the real field; the facade publishes the raw one.
static func _destiny_view(def: DestinyDef, held: bool) -> Dictionary:
	var reveal := held or def.visibility == DestinyDef.REVEALED
	return {
		"id": String(def.id),
		"held": held,
		"visible": def.is_visible(),
		"group": String(def.group),
		"display_name": String(def.display_name) if reveal else "",
		"description": String(def.description) if reveal else String(def.teaser),
		# Not gated on `reveal`. A revealed or held branch's teaser is simply its
		# own hint at what earning it promised, and `_fate_view` publishes it the
		# same way, so the two codex rows agree on what a view carries.
		"teaser": String(def.teaser),
		"bearing": String(def.bearing) if held else "",
		"grants_fate_count": def.grants_fates.size(),
	}


static func _string_list(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out


## Dialog generation summary (ADR 0398): every authored dialog assembled from
## base text + fate-held modifiers. Folded into `summary()` because the facade
## is at its twelve-method cap. Returns an array of
## `{dialog_id, npc_id, base_text, final_text, modifiers_applied}`.
static func _dialog_summary(actor: Actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dialog_id in DialogCatalog.instance().dialog_ids():
		out.append(DialogGenerator.generate(dialog_id, actor))
	return out
