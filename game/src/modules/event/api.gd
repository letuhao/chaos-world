class_name EventApi
extends RefCounted

## Public facade for the `event` module (BL-0054). Other modules may reference ONLY
## this file (`api.gd`).
##
## ## A world that changes, and WHO decides it changes
##
## An event is authored data (`EventDef`): a place, a trigger, a ladder of stages
## and a prize. This director opens one, holds it, walks it and resolves it. It
## decides nothing about HOW a number is produced — a war's quota and prize are
## `nation`'s (ADR 0085), a fate is `destiny`'s (ADR 0065), a counter is
## `destiny`'s, and a beat is `core`'s ledger (ADR 0113/0114).
##
## ## There is NO clock here, and this is the module's central rule
##
## ADR 0085: "There is no world tick, so nothing accrues on its own. Every accrual
## takes an explicit period count from a caller that owns time, and a module that
## invented a timer would be a second source of truth for when a save happened."
## DEF-0111 says the same from the other side.
##
## **So this director is PULL-BASED.** Nothing here advances on its own. A caller
## that owns time says "advance the world by N periods" and this module resolves
## exactly that many. Nothing here reads `Time.get_ticks*`, declares `_process` or
## reaches for `get_tree()`, and `tests/modules/event/test_event.gd` proves it three
## ways: the source contains none of those spellings, `advance` has no default for
## `periods`, and two identical pulls with no elapsed time between them resolve
## nothing extra.
##
## ## A beat is a proposal and the ledger is the only truth (ADR 0114)
##
## A stage's `on_enter` entries are BEATS. `EventBeatWriter` applies them to the ONE
## fact ledger, under ADR 0113's key, and that ledger is the world's memory. The
## occurrence id is minted from the caller-owned period, because "once" is
## answerable only by counting a monotone ledger.
##
## ## Ten verbs, and ten is a budget
##
## Nine facades already sit at the twelve-method cap, so "add a method" is not a
## free move in this program. `summary` folds the location read in, and `catalog()`
## folds the catalog report in, so a screen asks one question rather than chaining
## three calls.

## The `actor.module_data` key the versioned ledger persists under (ADR 0027).
const MODULE_KEY := EventState.MODULE_KEY
## The location an actor carries when none was ever set. Not a real
## `WorldLocationDef.location_id`: "nowhere in particular" must be representable, and
## `""` also means an event with no `location_id` may open anywhere.
const NOWHERE := ""


## Attach the module to `actor`. Restores any ledger a prior `Actor.from_dict`
## carried and normalizes it against the current catalog. Idempotent, and safe before
## anything has ever happened — which is the normal starting state.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	actor.set_module_data(MODULE_KEY, _ledger(actor))


## The authored catalog and a report on it, in ONE call: `events` keyed by id as
## primitives, the counts by kind, **every trigger naming a verb this module does not
## read**, and every rejected def with its reason.
##
## `unknown_verbs` is the part a tool cares about: a verb typo in a `.tres` would
## otherwise sit there until a player failed to open the event it locked. It is a KEY
## of this one payload rather than a verb of its own — the facade budget is real and
## a sub-read of a report nobody has to call twice is not worth a method.
static func catalog() -> Dictionary:
	return EventReadModel.report()


## Every event `actor` may open right now, as primitives.
##
## An event qualifies when its `trigger` passes against the ledger AND it is not
## already open AND it has not already resolved. `location_id` filters by place; an
## empty argument means "everywhere the ledger allows", which is what a world-level
## query asks.
##
## **An unmet trigger NEVER appears here**, and that is the property that makes this
## list trustworthy: `begin` re-checks the same gate rather than trusting this call,
## so a caller cannot open a locked event by skipping the filter.
static func available(actor: Actor, location_id: String = NOWHERE) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ledger := _ledger(actor)
	var here := (
		location_id if location_id != NOWHERE else String(ledger.get("location_id", NOWHERE))
	)
	for event_id in EventCatalog.instance().event_ids():
		var def := EventCatalog.instance().event_definition(event_id)
		if def == null:
			continue
		if String(def.location_id) != NOWHERE and String(def.location_id) != here:
			continue
		if EventState.is_active(ledger, event_id) or EventState.has_resolved(ledger, event_id):
			continue
		if not _triggered(actor, def):
			continue
		(
			out
			. append(
				{
					"event_id": String(event_id),
					"kind": String(def.kind),
					"display_name": String(def.display_name),
					"description": String(def.description),
					"location_id": String(def.location_id),
					"stage_count": def.stage_count(),
					"first_stage_id": String(def.first_stage_id()),
					"pay_rows": def.pay.size(),
					"is_conflict": def.kind == EventDef.KIND_SECT_WAR,
				}
			)
		)
	return out


## Open an event: write the active row, apply its opening beats, and — for a
## `sect_war` — ask `NationApi` to DECLARE the standoff.
##
## Refuses, with a named reason, `unknown_event` / `already_active` / `trigger_unmet` /
## `wrong_location` / `too_many_active_events` / `event_authors_no_stage`. The trigger
## is re-evaluated HERE rather than trusted from `available`, so this verb is the one
## authority on whether an event may open.
##
## `period` is the caller's own period count for the moment the event opens. It is
## never read from a clock.
static func begin(actor: Actor, event_id: StringName, period: int = 0) -> Dictionary:
	if actor == null:
		return EventState.refuse(EventState.R_NO_ACTOR, {"event_id": String(event_id)})
	var def := EventCatalog.instance().event_definition(event_id)
	if def == null:
		return EventState.refuse(EventState.R_UNKNOWN_EVENT, {"event_id": String(event_id)})
	var first := def.stage_at(0)
	if first == null:
		return EventState.refuse(EventState.R_NO_STAGES, {"event_id": String(event_id)})
	var ledger := _ledger(actor)
	if EventState.is_active(ledger, event_id):
		return EventState.refuse(EventState.R_ALREADY_ACTIVE, {"event_id": String(event_id)})
	if EventState.has_resolved(ledger, event_id):
		return EventState.refuse(EventState.R_ALREADY_RESOLVED, {"event_id": String(event_id)})
	if (ledger["active"] as Dictionary).size() >= EventState.MAX_ACTIVE:
		return EventState.refuse(EventState.R_TOO_MANY_ACTIVE, {"event_id": String(event_id)})
	var here := String(ledger.get("location_id", NOWHERE))
	if String(def.location_id) != NOWHERE and String(def.location_id) != here:
		return EventState.refuse(
			EventState.R_WRONG_LOCATION,
			{"event_id": String(event_id), "location_id": here, "required": String(def.location_id)}
		)
	var gate := EventGate.evaluate(actor, def.trigger)
	if not bool(gate.get("ok", false)):
		return EventState.refuse(
			EventState.R_TRIGGER_UNMET, {"event_id": String(event_id), "reason_detail": gate}
		)

	var at := maxi(0, period)
	var entry := {
		"stage_id": String(first.stage_id),
		"opened_period": at,
		"periods_held": 0,
		"last_resolved_period": at,
		"territory_id": "",
		"standoff_id": "",
		"declared": false,
		"history": [],
	}
	var opened := _record(ledger, "opened", event_id, String(def.kind))
	(entry["history"] as Array).append(opened)

	# **The declaration happens BEFORE the beats and is recorded on the row.** A war
	# with no declared prize must never open (ADR 0085), so if `declare_war` refuses,
	# the whole `begin` refuses and nothing was recorded in either ledger.
	#
	# **`_declare` is the BUILDER and THIS is the recorder.** It writes nothing into
	# `ledger`; it returns what `nation` decided and the three lines below are the
	# only place a declaration reaches this module's ledger. Do not pass `ledger` to
	# it: `NationApi._declare` takes one because that one IS a recorder, and the
	# leading-argument convention was copied here after the split had already
	# happened. `test_the_declaration_lands_on_the_event_row_not_wherever_the
	# builder_happens_to_look` is the test that fails if it is passed again.
	if def.kind == EventDef.KIND_SECT_WAR:
		var declaration := _declare(actor, def, at)
		if not bool(declaration.get("ok", false)):
			return declaration
		entry["standoff_id"] = String(declaration["standoff_id"])
		entry["territory_id"] = String(declaration.get("territory_id", ""))
		entry["declared"] = true
		(entry["history"] as Array).append(
			_record(ledger, "declared", event_id, String(entry["standoff_id"]))
		)

	(ledger["active"] as Dictionary)[String(event_id)] = entry
	ledger["period"] = maxi(int(ledger["period"]), at)
	_persist(actor, ledger)

	var beats := _offer_beats(actor, ledger, def, def.opening_beats())
	WorldEventBus.conflict_triggered(
		String(actor.id), event_id, float(def.stage_count()) * EventPrize.STABILITY_COST_PER_PERIOD
	)
	return _ok(
		ledger,
		{
			"event_id": String(event_id),
			"stage_id": String(first.stage_id),
			"opened_period": at,
			"beats": beats["applied"],
			"standoff_id": String(entry["standoff_id"]),
			"territory_id": String(entry["territory_id"]),
			"declared": bool(entry["declared"]),
		}
	)


## THE PULL-BASED TICK. Move every open event forward by exactly `periods` and
## resolve whatever that reaches.
##
## Nothing in this module advances without this call, and this call does nothing
## without an explicit `periods` count: there is no clock behind it (ADR 0085,
## DEF-0111). `periods <= 0` settles NOTHING and writes nothing, because a settlement
## is not a negative accrual.
##
## Per period, for each open event:
##   1. the current stage's `duration_periods` must have elapsed — the stage holds
##      for that many WHOLE periods and the NEXT pull is what moves it, so
##      `duration_periods = 0` advances on the very next period;
##   2. the next stage's `requires` must pass against the ledger;
##   3. its `on_enter` beats are offered, and one period of upkeep announced.
## On the FINAL stage the prize is paid — through [method _pay] exactly once — and the
## event leaves `active` with its period written into `resolved`.
##
## Returns `{ok, periods, advanced, resolved, held}`.
##
## `periods` carries **NO default**, and that is enforced by a test reading this
## file's source: a default of `1` makes `advance(actor)` legal, which is a timer
## that fires whether or not any time was owed to it (ADR 0085, DEF-0111). If a
## default is ever added here, `test_advance_declares_no_default_period_count` goes
## red.
static func advance(actor: Actor, periods: int) -> Dictionary:
	if actor == null:
		return EventState.refuse(EventState.R_NO_ACTOR)
	var ledger := _ledger(actor)
	if periods <= 0:
		return _ok(ledger, {"periods": 0, "advanced": [], "resolved": [], "held": []})
	var advanced: Array[Dictionary] = []
	var resolved: Array[Dictionary] = []
	var held: Array[Dictionary] = []
	## Verdicts a stage authored for ANOTHER event (DEF-0315). Collected here and delivered
	## at the END of this method, never inside the loop: `resolve` re-reads the ledger and
	## persists its own result, so a call from inside the loop would be clobbered by this
	## method's final `_persist`.
	var pending_verdicts: Array[Dictionary] = []
	for step in periods:
		# The world's own period counter moves once per elapsed period, BEFORE any
		# event is consulted — so `period` is what the caller said happened even when
		# no event is open to notice it.
		ledger["period"] = int(ledger["period"]) + 1
		var at := int(ledger["period"])
		for event_id in EventState.active_ids(ledger):
			# One event, at most one stage, per period: an event whose every stage
			# holds for zero periods would otherwise clear its whole ladder in a single
			# pull. The active list is re-read each period because `resolved` and
			# `active` are mutated as this loop goes.
			var entry := EventState.active_entry(ledger, event_id)
			if entry.is_empty():
				continue
			var def := EventCatalog.instance().event_definition(event_id)
			if def == null:
				continue
			var stage_id := StringName(entry.get("stage_id", ""))
			var stage := def.stage_named(stage_id)
			if stage == null:
				continue
			entry["periods_held"] = int(entry.get("periods_held", 0)) + 1
			# **A stage holds for `duration_periods` WHOLE periods and moves on the
			# next one.** `held <= duration` holds; `held > duration` advances. The
			# off-by-one matters because `duration_periods = 0` and `= 1` would
			# otherwise behave identically — both moving on the first pull — which
			# would make an authored `1` mean "holds for no time at all" and would
			# collide with `EventStageDef`'s own "zero resolves at the next pull".
			if int(entry["periods_held"]) <= stage.duration_periods:
				(ledger["active"] as Dictionary)[String(event_id)] = entry
				(
					held
					. append(
						{
							"event_id": String(event_id),
							"stage_id": String(stage_id),
							"periods_held": int(entry["periods_held"]),
							"required": stage.duration_periods,
						}
					)
				)
				continue
			var next_id := def.next_stage_id(stage_id)
			if next_id == &"":
				resolved.append(_pay(actor, ledger, def, event_id, at))
				continue
			var following := def.stage_named(next_id)
			if following == null:
				resolved.append(_pay(actor, ledger, def, event_id, at))
				continue
			var gate := EventGate.evaluate(actor, following.requires)
			if not bool(gate.get("ok", false)):
				# The ladder is BLOCKED, not finished: the event stays open and says
				# why, so a screen can show what is holding it rather than an event
				# that quietly stopped existing.
				(entry["history"] as Array).append(
					_record(
						ledger,
						"held",
						event_id,
						"%s: %s" % [String(next_id), gate.get("reason", "")]
					)
				)
				(
					held
					. append(
						{
							"event_id": String(event_id),
							"stage_id": String(stage_id),
							"next_stage_id": String(next_id),
							"reason": String(gate.get("reason", "")),
						}
					)
				)
				(ledger["active"] as Dictionary)[String(event_id)] = entry
				continue
			(entry["history"] as Array).append(
				_record(
					ledger, "advanced", event_id, "%s->%s" % [String(stage_id), String(next_id)]
				)
			)
			entry["stage_id"] = String(next_id)
			entry["opened_period"] = at
			entry["periods_held"] = 0
			(ledger["active"] as Dictionary)[String(event_id)] = entry
			var beats := _offer_beats(actor, ledger, def, following.on_enter)
			# A stage that DECIDES another event queues its verdict; it is delivered after
			# this advance's write, below (DEF-0315).
			var pending := _pending_verdict(following)
			if (
				not pending.is_empty()
				and not _has_verdict(pending_verdicts, String(pending["war_id"]))
			):
				pending_verdicts.append(pending)
			# **The settlement happens, and only then is it announced.**
			# `world_upkeep_paid` used to fire here with two numbers and no write behind
			# them, because `EventPrize.settle_period` — the only thing in the repository
			# that reaches `WorldApi.trigger_conflict` — had ZERO callers. A signal that
			# announces a settlement which never happens is the VACUOUS class, and the
			# function's own docstring already says what it is for. So the call is here,
			# and the announce follows its answer: the bus now reports something that
			# actually moved the world, or says nothing at all.
			#
			# **The severity is the stage's whole authored duration times the per-period
			# rate, both read from the module's own constants.** `EventPrize
			# .STABILITY_COST_PER_PERIOD` is the rate the world's own `trigger_conflict`
			# multiplies, so this is what one stage costs the world in stability — derived
			# from the def, never a second magic multiplier declared here.
			#
			# **A refusal is a report, never a crash.** `WorldApi.trigger_conflict`
			# refuses `no_world` on an actor with no created realm, and an event running
			# on such an actor must still advance (ADR 0085: the ladder is not the
			# realm's), so nothing is announced when nothing settled and the answer
			# travels on the report instead.
			var settled := EventPrize.settle_period(
				actor, def, float(following.duration_periods) * EventPrize.STABILITY_COST_PER_PERIOD
			)
			if bool(settled.get("ok", false)):
				WorldEventBus.upkeep_paid(
					String(actor.id),
					float(following.duration_periods),
					EventPrize.STABILITY_COST_PER_PERIOD
				)
			WorldEventBus.evolved(String(actor.id), stage_id, next_id)
			(
				advanced
				. append(
					{
						"event_id": String(event_id),
						"from_stage_id": String(stage_id),
						"stage_id": String(next_id),
						"period": at,
						"beats": beats["applied"],
						# Carried so a panel can say the world paid for this rather than
						# inferring it from the absence of a refusal.
						"upkeep_settled": bool(settled.get("ok", false)),
						"upkeep_reason": String(settled.get("reason", "")),
					}
				)
			)
	_persist(actor, ledger)
	# ## The verdicts, delivered AFTER this advance's own write is on the ledger (DEF-0315)
	#
	# A stage that decides another event (a tournament's final ruling on a war) authored a
	# verdict, and this is where it lands. It runs here rather than inside the loop because
	# `resolve` re-reads and re-persists the ledger — a call from inside would be overwritten
	# by the `_persist` above. The order is the one the rest of this module holds: the stage
	# is RECORDED first, then the contest it decided is resolved.
	var verdicts: Array[Dictionary] = []
	for pending in pending_verdicts:
		var delivered := resolve(actor, StringName(pending["war_id"]), String(pending["winner_id"]))
		(
			verdicts
			. append(
				{
					"war_id": String(pending["war_id"]),
					"winner_id": String(pending["winner_id"]),
					"outcome": delivered,
				}
			)
		)
	# The ledger is re-read because a delivered verdict mutated it through its own writer.
	return _ok(
		_ledger(actor) if not verdicts.is_empty() else ledger,
		{
			"periods": periods,
			"advanced": advanced,
			"resolved": resolved,
			"held": held,
			"verdicts": verdicts,
		}
	)


## Resolve an event by an INJECTED verdict — a `CombatApi.exchange` a caller ran, a
## tournament result, a tribunal's ruling (ADR 0085: "verdicts arrive from outside").
##
## This is the ONE place `NationApi.resolve_conflict` is called from, and it is called
## for the quota and the prize it already declared. **The quota is never re-derived
## here**: `begin` stashed the standoff id, `resolve` hands it straight back, and
## `nation` decides whether that verdict closes the war.
##
## Refuses `not_active`, `already_resolved`, `not_a_conflict` (an event whose kind is
## not a war), `not_declared`, and `no_winner` — an empty `winner_id` on a conflict is
## refused rather than defaulting to one side, because a war with no winner is a
## withdrawal and `nation` owns that word.
##
## A non-conflict event resolves here too: its prize is paid and it is closed, which
## is the same code path minus the delegation.
static func resolve(actor: Actor, event_id: StringName, winner_id: String = "") -> Dictionary:
	if actor == null:
		return EventState.refuse(EventState.R_NO_ACTOR, {"event_id": String(event_id)})
	var ledger := _ledger(actor)
	if not EventState.is_active(ledger, event_id):
		var reason := (
			EventState.R_ALREADY_RESOLVED
			if EventState.has_resolved(ledger, event_id)
			else EventState.R_NOT_ACTIVE
		)
		return EventState.refuse(reason, {"event_id": String(event_id)})
	var def := EventCatalog.instance().event_definition(event_id)
	if def == null:
		return EventState.refuse(EventState.R_UNKNOWN_EVENT, {"event_id": String(event_id)})
	var entry := EventState.active_entry(ledger, event_id)
	var at := int(ledger["period"])

	if def.kind != EventDef.KIND_SECT_WAR:
		return _pay(actor, ledger, def, event_id, at, winner_id)

	if not bool(entry.get("declared", false)):
		return EventState.refuse(EventState.R_NOT_DECLARED, {"event_id": String(event_id)})
	var standoff_id := StringName(entry.get("standoff_id", ""))
	if standoff_id == &"":
		return EventState.refuse(EventState.R_NOT_DECLARED, {"event_id": String(event_id)})
	if String(winner_id) == "":
		return EventState.refuse(EventState.R_NO_WINNER, {"event_id": String(event_id)})

	# **The delegation.** `NationApi.resolve_conflict` counts one injected verdict
	# against the declared quota and pays the DECLARED prize when the quota is met.
	# This module never computes the tally, never reads a combat stat and owns no
	# rng (ADR 0085); it hands over a winner and reads back what `nation` decided.
	var verdict := NationApi.resolve_conflict(actor, standoff_id, StringName(winner_id))
	if not bool(verdict.get("ok", false)):
		return EventState.refuse(
			EventState.R_UNKNOWN_WINNER,
			{"event_id": String(event_id), "standoff_id": String(standoff_id), "verdict": verdict}
		)
	(entry["history"] as Array).append(
		_record(
			ledger,
			"delegated",
			event_id,
			(
				"%s|%s|%s"
				% [String(standoff_id), String(winner_id), String(verdict.get("outcome", ""))]
			)
		)
	)
	entry["last_resolved_period"] = maxi(int(entry.get("last_resolved_period", 0)), at)
	(ledger["active"] as Dictionary)[String(event_id)] = entry
	if bool(verdict.get("closed", false)):
		var paid := _pay(actor, ledger, def, event_id, at, winner_id)
		WorldEventBus.conflict_resolved(
			String(actor.id), standoff_id, StringName(verdict.get("outcome", "resolved"))
		)
		var closed: Dictionary = paid
		closed["delegated"] = {
			"standoff_id": String(standoff_id),
			"winner_id": String(winner_id),
			"outcome": String(verdict.get("outcome", "")),
			"verdicts": int(verdict.get("verdicts", 0)),
			"territory_transferred": String(verdict.get("territory_transferred", "")),
		}
		return closed
	_persist(actor, ledger)
	# A quota NOT yet met is not a refusal: it is a war still being fought. Hand back
	# what `nation` counted, leave the event open, and say so.
	return _ok(
		ledger,
		{
			"event_id": String(event_id),
			"closed": false,
			"paid": false,
			"delegated": true,
			"standoff_id": String(standoff_id),
			"winner_id": String(winner_id),
			"verdicts": int(verdict.get("verdicts", 0)),
			"quota_not_met": true,
		}
	)


## Every open event, as primitives. A screen's "what is happening right now".
static func active(actor: Actor) -> Array[Dictionary]:
	return EventReadModel.open_rows(actor)


## The actor's versioned ledger exactly as core persists it: the payload a save
## carries, so a caller (or the read model) never reaches into `actor.module_data`.
static func state(actor: Actor) -> Dictionary:
	return _ledger(actor)


## Move the actor to a `WorldLocationDef.location_id` (ADR 0113's durable world id).
##
## This is the only verb that writes a place, and it exists because the facade
## carries no `set_location` anywhere else: without it the ledger's `location_id`
## could never change and `begin` could only ever open an untied event. An unknown id
## is refused and named, and an empty id moves the actor back to `NOWHERE` — "nowhere
## in particular" is a real place to be, not a failure.
##
## Moving does NOT close what is open: a war does not end because somebody walked
## away from it, and the prize on an open conflict still reaches its winner.
static func set_location(actor: Actor, location_id: StringName) -> Dictionary:
	if actor == null:
		return EventState.refuse(EventState.R_NO_ACTOR)
	var id := String(location_id)
	if id != NOWHERE and not EventReadModel.location_known(id):
		return EventState.refuse(EventState.R_UNKNOWN_LOCATION, {"location_id": id})
	var ledger := _ledger(actor)
	ledger["location_id"] = id
	ledger["sequence"] = EventState.next_sequence(ledger)
	_persist(actor, ledger)
	return _ok(ledger, {"location_id": id, "active_count": (ledger["active"] as Dictionary).size()})


## One primitive-only read for a screen: where the actor is, what is open, what has
## resolved, what has been paid and what could open next. The location read is FOLDED
## in rather than being a thirteenth verb — the facade budget is a real constraint
## and "where am I and what is happening" is one question.
static func summary(actor: Actor) -> Dictionary:
	return EventReadModel.summary(actor)


## The signal bus, so a consumer can subscribe without this module reaching into it.
## The bus ANNOUNCES; nothing on it is a request (ADR 0093).
static func events() -> WorldEvents:
	return WorldEventBus.instance()


# --- Internals -------------------------------------------------------------


static func _catalog() -> EventCatalog:
	return EventCatalog.instance()


static func _ledger(actor: Actor) -> Dictionary:
	if actor == null:
		return EventState.empty()
	return EventState.normalize(actor.get_module_data(MODULE_KEY), _catalog().known_ids())


static func _persist(actor: Actor, ledger: Dictionary) -> void:
	actor.set_module_data(MODULE_KEY, EventState.normalize(ledger))


static func _ok(ledger: Dictionary, detail: Dictionary = {}) -> Dictionary:
	var out := {"ok": true, "period": int(ledger.get("period", 0))}
	for key in detail.keys():
		out[String(key)] = detail[key]
	return out


static func _triggered(actor: Actor, def: EventDef) -> bool:
	return bool(EventGate.evaluate(actor, def.trigger).get("ok", false))


## The verdict a stage authors, as `{war_id, winner_id}`, or `{}` when it authors none or
## names an incomplete one (DEF-0315). Both halves are required: a war id with no winner is
## a withdrawal, and a winner with no war is nothing to resolve.
static func _pending_verdict(stage: EventStageDef) -> Dictionary:
	if stage == null or stage.resolves.is_empty():
		return {}
	var war_id := StringName(stage.resolves.get("war_id", &""))
	var winner := String(stage.resolves.get("winner_id", ""))
	if war_id == &"" or winner == "":
		return {}
	return {"war_id": String(war_id), "winner_id": winner}


## Whether `war_id` is already queued this advance. One advance delivers a war's verdict
## ONCE, so two stages naming the same war do not resolve it twice.
static func _has_verdict(queue: Array[Dictionary], war_id: String) -> bool:
	for row in queue:
		if String(row.get("war_id", "")) == war_id:
			return true
	return false


## A history row, built rather than shared. Every active row carries its OWN copy:
## several dictionary values in GDScript may share one backing store, so appending
## the same row object to two ledgers would let one event's write surface in
## another's history.
static func _record(
	ledger: Dictionary, kind: String, event_id: StringName, detail: String
) -> Dictionary:
	EventState.record(ledger, kind, event_id, detail)
	var history: Array = ledger["history"]
	if history.is_empty():
		return {}
	return (history[history.size() - 1] as Dictionary).duplicate(true)


## Offer a stage's beats through the one writer. The occurrence number is derived
## from the ledger's own count and this module's sequence — never from a clock — so a
## beat id is unique per occurrence (ADR 0114's once-rule) without this module
## keeping a second counter of its own.
static func _offer_beats(
	actor: Actor, ledger: Dictionary, def: EventDef, beats: Array[Dictionary]
) -> Dictionary:
	var applied: Array[Dictionary] = []
	var skipped := 0
	for beat in beats:
		var proposal := beat.duplicate()
		proposal["source"] = def.fate_source()
		proposal["actor_id"] = String(actor.id)
		var fact_id := StringName(proposal.get("fact", ""))
		var occurrence := maxi(1, EventFacts.count_of(actor, fact_id) + int(ledger["sequence"]))
		proposal["id"] = EventFacts.occurrence_id(fact_id, occurrence)
		var outcome := EventBeatWriter.offer(actor, proposal, occurrence)
		if bool(outcome.get("ok", false)):
			applied.append(outcome)
		else:
			skipped += 1
	return {"applied": applied, "skipped": skipped}


## Pay the prize and close the event. The once-guard is `EventState.paid`, written
## under the SAME write that removes the row from `active` — so there is no window in
## which a crash between the two would pay a second time (ADR 0061).
static func _pay(
	actor: Actor,
	ledger: Dictionary,
	def: EventDef,
	event_id: StringName,
	period: int,
	winner_id: String = ""
) -> Dictionary:
	if EventState.has_paid(ledger, event_id):
		# Already paid. Report it and change nothing: a second resolution must not
		# produce a second prize.
		#
		# `ok` and `reason` are present because EVERY other exit from this verb
		# carries them, and a caller that reads `outcome["ok"]` on this branch got
		# null and could not tell a successful no-op from a malformed answer. The
		# shape of a refusal is the house rule (ADR 0065's refuse-with-cause), so
		# the shape of a successful no-op is its mirror: same keys, no cause.
		return {
			"ok": true,
			"reason": "",
			"event_id": String(event_id),
			"kind": String(def.kind),
			"period": period,
			"resolved_period": EventState.resolved_period(ledger, event_id),
			"closed": true,
			"paid": true,
			"already_paid": true,
			"granted": [],
			"refused": [],
			"fate_source": "",
		}
	var prize := EventPrize.apply(actor, def, period)
	(ledger["paid"] as Dictionary)[String(event_id)] = {
		"period": period,
		"rows": int(prize.get("rows", 0)),
	}
	(ledger["resolved"] as Dictionary)[String(event_id)] = period
	(ledger["active"] as Dictionary).erase(String(event_id))
	var note := _record(ledger, "resolved", event_id, String(def.kind))
	if String(winner_id) != "":
		note["detail"] = "%s|%s" % [String(def.kind), String(winner_id)]
	_persist(actor, ledger)
	return {
		"event_id": String(event_id),
		"kind": String(def.kind),
		"period": period,
		"resolved_period": period,
		"closed": true,
		"paid": true,
		"already_paid": false,
		"granted": prize.get("granted", []),
		"refused": prize.get("refused", []),
		"fate_source": String(prize.get("fate_source", "")),
	}


## The one place a world event asks `nation` to declare a war.
##
## **`event` is the caller that `declare_war` and `resolve_conflict` had zero of.**
## The prize is declared here, read verbatim from the authored trigger, and is the
## shape `NationApi.declare_war` refuses when it is absent (ADR 0085: `war` is
## reachable ONLY through the declaration verb). The mode is `nation`'s own constant,
## and the quota is whatever that mode declares — this module never counts verdicts.
##
## ## A BUILDER, not a recorder — and that is why it takes no ledger
##
## This writes into `nation`'s ledger through `declare_war` and into nothing else.
## It does NOT touch this module's ledger, which is why its signature has no
## `ledger` parameter: the declaration reaches `actor.module_data` when `begin` copies
## `standoff_id` / `territory_id` / `declared` onto the row it then persists.
## Handing it a ledger would be a second writer over one dictionary for a record the
## caller already makes, and the caller's own `_record(ledger, "declared", ...)`
## would silently become dead.
static func _declare(actor: Actor, def: EventDef, period: int) -> Dictionary:
	var authored := _war_declaration(def.trigger)
	if authored.is_empty():
		return (
			EventState
			. refuse(
				EventState.R_STAGE_UNMET,
				{
					"event_id": String(def.id),
					"detail": "a sect_war declares its sides and its prize in its trigger",
				}
			)
		)
	var other_id := String(authored.get("other_id", ""))
	if other_id == "":
		return EventState.refuse(
			EventState.R_UNKNOWN_WINNER,
			{"event_id": String(def.id), "detail": "the declaration names no other_id"}
		)
	var prize := {
		"mode": String(authored.get("mode", NationState.SIEGE)),
		"transfer": String(authored.get("transfer", "")),
		"standing": authored.get("standing", {}),
	}
	var declared := NationApi.declare_war(
		actor, StringName(other_id), authored.get("territory_id", &""), prize
	)
	if not bool(declared.get("ok", false)):
		return EventState.refuse(
			EventState.R_STAGE_UNMET, {"event_id": String(def.id), "detail": declared}
		)
	return {
		"ok": true,
		"standoff_id": String(declared["standoff_id"]),
		"territory_id": String(authored.get("territory_id", "")),
		"quota": int(declared.get("quota", 0)),
		"period": period,
	}


## The `declare` child of an authored `sect_war` trigger, or `{}`. Fact and gate verbs
## are ignored here rather than refused: they gate the EVENT, and only the `declare`
## row is read as a declaration.
static func _war_declaration(trigger: Dictionary) -> Dictionary:
	var children = trigger.get("of", [])
	if children is Array:
		for child in children as Array:
			if not (child is Dictionary):
				continue
			if StringName((child as Dictionary).get("verb", "")) == &"declare":
				return (child as Dictionary).duplicate(true)
	return {}
