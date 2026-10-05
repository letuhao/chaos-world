class_name EventReadModel
extends RefCounted

## The screen-facing read model: the catalog report, the def views and the location
## lookup. Split out of `EventApi` so the facade is only a DIRECTOR (open, hold,
## walk, resolve, pay) and the "what would a screen read" question lives beside the
## other read models, exactly as `NpcReadModel` and `NationProjection` do.
##
## Nothing here writes. Every verb is a pure read of the catalog, the ledger and the
## world module's authored locations, so a screen can call any of them freely without
## being able to change the world by looking at it.


## The whole authored tree plus its report, in one call. `unknown_verbs` is the part
## a tool cares about: a trigger naming a verb this module cannot read is a content
## typo that would otherwise sit in a `.tres` until a player failed to open the event.
static func report() -> Dictionary:
	var definitions := {}
	var by_kind := {}
	var problems: Array[String] = []
	for event_id in EventCatalog.instance().event_ids():
		var def := EventCatalog.instance().event_definition(event_id)
		if def == null:
			continue
		definitions[String(event_id)] = def_view(def)
		var kind_text := String(def.kind)
		by_kind[kind_text] = int(by_kind.get(kind_text, 0)) + 1
		for problem in def.problems():
			problems.append("%s: %s" % [String(event_id), problem])
	var rejected: Array[Dictionary] = EventCatalog.instance().rejected()
	for entry in rejected:
		problems.append(
			"%s: rejected (%s)" % [String(entry.get("id", "")), String(entry.get("reason", ""))]
		)
	return {
		"events": definitions,
		"count": definitions.size(),
		"by_kind": by_kind,
		"kinds": string_list(EventDef.KINDS),
		"verbs": string_list(EventGate.KNOWN_VERBS),
		"unknown_verbs": unknown_verbs(),
		"problems": problems,
		"rejected": rejected,
	}


## Every trigger or stage requirement in the authored tree naming a verb this module
## does not read. One recursive walk per event, so a typo nested inside an `all_of` is
## found too. Empty for a well-formed tree — and a test asserts that, because a gate
## checker that cannot fail is the shape ADR 0077 named.
static func unknown_verbs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event_id in EventCatalog.instance().event_ids():
		var def := EventCatalog.instance().event_definition(event_id)
		if def == null:
			continue
		for where in ["trigger", "stages"]:
			for verb in EventGate.verbs_in(
				def.trigger if where == "trigger" else all_requires(def)
			):
				if EventGate.KNOWN_VERBS.has(verb):
					continue
				if _already_reported(out, String(event_id), where):
					continue
				out.append({"event_id": String(event_id), "where": where, "verb": String(verb)})
	return out


## One event as primitives, for a catalog screen.
static func def_view(def: EventDef) -> Dictionary:
	return {
		"id": String(def.id),
		"display_name": String(def.display_name),
		"description": String(def.description),
		"kind": String(def.kind),
		"location_id": String(def.location_id),
		"stage_count": def.stage_count(),
		"stages": stage_list(def),
		"trigger": def.trigger.duplicate(true),
		"pay": def.pay.duplicate(true),
		"beats": def.opening_beats(),
		"is_conflict": def.kind == EventDef.KIND_SECT_WAR,
	}


## Every stage as primitives, in authored order.
static func stage_list(def: EventDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for stage in def.stages:
		(
			out
			. append(
				{
					"stage_id": String(stage.stage_id),
					"display_name": String(stage.display_name),
					"requires": stage.requires.duplicate(true),
					"duration_periods": stage.duration_periods,
					"beats": stage.on_enter.duplicate(true),
				}
			)
		)
	return out


## Whether the build ships a `WorldLocationDef` under this id. A location the world
## module no longer authors reads as `false` rather than as a location, so a screen
## never renders a map marker for a place that is gone.
static func location_known(location_id: String) -> bool:
	if location_id == EventApi.NOWHERE:
		return false
	for entry in WorldApi.locations(null):
		if String(entry.get("location_id", "")) == location_id:
			return true
	return false


## Every open event, as primitives. A screen's "what is happening right now".
##
## `is_final_stage` is read from the INDEX, not from "this is the last row": an
## event whose def was re-authored shorter while one instance sat on its old stage
## would otherwise be reported as finished and auto-resolved.
static func open_rows(actor: Actor) -> Array[Dictionary]:
	if actor == null:
		return []
	var ledger := EventApi.state(actor)
	var out: Array[Dictionary] = []
	for event_id in EventState.active_ids(ledger):
		var entry := EventState.active_entry(ledger, event_id)
		var def := EventCatalog.instance().event_definition(event_id)
		var stage_id := StringName(entry.get("stage_id", ""))
		var stage := null if def == null else def.stage_named(stage_id)
		var index := -1 if def == null else def.stage_index_of(stage_id)
		(
			out
			. append(
				{
					"event_id": String(event_id),
					"kind": "" if def == null else String(def.kind),
					"display_name": "" if def == null else String(def.display_name),
					"location_id": "" if def == null else String(def.location_id),
					"stage_id": String(stage_id),
					"stage_name": "" if stage == null else String(stage.display_name),
					"stage_index": index,
					"stage_count": 0 if def == null else def.stage_count(),
					"opened_period": int(entry.get("opened_period", 0)),
					"periods_held": int(entry.get("periods_held", 0)),
					"duration_periods": 0 if stage == null else stage.duration_periods,
					"standoff_id": String(entry.get("standoff_id", "")),
					"territory_id": String(entry.get("territory_id", "")),
					"is_final_stage":
					def != null and stage != null and index >= def.stage_count() - 1,
				}
			)
		)
	return out


## One primitive-only read for a screen: where the actor is, what is open, what has
## resolved, what has been paid and what could open next. The location read is FOLDED
## in here rather than being a facade verb — the budget is a real constraint and
## "where am I and what is happening" is one question.
static func summary(actor: Actor) -> Dictionary:
	var catalog_size := EventCatalog.instance().event_ids().size()
	if actor == null:
		return {
			"has_actor": false,
			"location_id": EventApi.NOWHERE,
			"location_known": false,
			"period": 0,
			"sequence": 0,
			"active_count": 0,
			"resolved_count": 0,
			"paid_count": 0,
			"open": [],
			"resolved": {},
			"available": [],
			"catalog_count": catalog_size,
		}
	var ledger := EventApi.state(actor)
	var here := String(ledger.get("location_id", EventApi.NOWHERE))
	var open := open_rows(actor)
	return {
		"has_actor": true,
		"actor_id": String(actor.id),
		"location_id": here,
		"location_known": location_known(here),
		"period": int(ledger["period"]),
		"sequence": int(ledger["sequence"]),
		"active_count": open.size(),
		"resolved_count": (ledger["resolved"] as Dictionary).size(),
		"paid_count": (ledger["paid"] as Dictionary).size(),
		"open": open,
		"resolved": EventState.resolved_rows(ledger),
		"available": EventApi.available(actor),
		"catalog_count": catalog_size,
	}


static func string_list(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out


## Every stage's `requires` collapsed into one dictionary, for the one walk that looks
## for an unknown verb. Collapsing is safe here because `verbs_in` is asked only which
## verbs APPEAR — no verdict is ever computed from this, and a stage that gates on
## nothing contributes no child.
static func all_requires(def: EventDef) -> Dictionary:
	var children: Array[Dictionary] = []
	for stage in def.stages:
		if stage.requires.is_empty():
			continue
		children.append(stage.requires.duplicate(true))
	if children.is_empty():
		return {}
	return {"verb": EventGate.VERB_ALL_OF, "of": children}


static func _already_reported(seen: Array[Dictionary], event_id: String, where: String) -> bool:
	for entry in seen:
		if String(entry["event_id"]) == event_id and String(entry["where"]) == where:
			return true
	return false
