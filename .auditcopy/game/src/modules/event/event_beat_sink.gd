class_name EventBeatSink
extends BeatSink

## The `event` module's end of ADR 0114: a beat handler that claims a beat whose fact
## the AUTHORED WORLD is written about, and resolves it by reporting which open event
## that fact has unblocked — and nothing else.
##
## ## This is the same shape as `quest/quest_beat_handler.gd`, deliberately
##
## `handles(beat, context) -> bool`, `resolve(beat, context) -> Dictionary` returning
## `{claimed, reason}` plus JSON-safe detail, both arguments `Variant`, both a null
## context claiming nothing. That is the shape `BeatSink` declares and that ADR 0117
## line 36-42 froze, and it is the shape the contract suite exercises, so a second
## spelling would be a second contract rather than a second consumer.
##
## ## Where it differs from the quest sink, and why both differences are load-bearing
##
## **1. It reads the beat through `WorldBeat.coerce`, not by hand.** `quest_beat_handler`
## re-derives `fact` and `source` from the raw dictionary itself. ADR 0117 line 70-73
## names `WorldBeat.coerce` as the single place a beat is read from either spelling,
## because `contracts/` may not name `core` and every sink was otherwise re-deriving
## the nesting — and one of them got it wrong. This module may name `core`
## (`tools/arch/registry.json` lists it among `event`'s deps), so it uses the coercer
## rather than repeating the pattern the ADR measured.
##
## **2. It does NOT advance the world, and that is the point.** `QuestApi.advance`
## takes no period count, so a sink may call it. **`EventApi.advance` requires an
## explicit `periods` and refuses one that is absent** — ADR 0085's pull-based tick and
## DEF-0111's "every accrual takes an explicit count from a caller that owns time".
## There is no honest `periods` a beat sink could supply: a beat is "a thing happened",
## not "a period elapsed", so a sink that passed `1` would invent a clock and make the
## world's stage ladder advance on whatever happened to produce a beat. So this sink
## REPORTS what the fact unblocked and leaves the pull to the caller that owns the
## moment. `advance` still has exactly one production caller question open — see
## `docs/deferred.jsonl` — and guessing at it here would be that guess, in a worse
## place.
##
## ## "Record, then resolve" — this sink must not re-record
##
## ADR 0117 line 46: the ledger already carries the beat when `resolve` runs, because
## the director writes at `beat_director.gd:122` before consulting any sink. A sink
## that called `WorldFact.record` here would double-count every beat in the game. Every
## verb below is a pure read.
##
## ## Priority: register `QuestBeatHandler` FIRST
##
## Registration order IS priority (ADR 0117 line 52), so an actor with an active quest
## watching a fact gets the quest's completion rather than this module's report. That
## is the right order: a quest step is a specific promise, and this module's answer is
## the general one. Registering this sink first would starve every quest.

## The beat fields this sink reads. ADR 0114 fixes `WorldBeat` as
## `{id, fact, amount, source}`; [method WorldBeat.coerce] reads both that value object
## and the plain dictionary an event stage builds.
const BEAT_FACT := "fact"
const BEAT_SOURCE := "source"

## The reason `resolve` gives when `handles` said no. The same word
## `QuestBeatHandler.resolve` uses, so a director report reads the same whichever sink
## declined.
const REASON_NOT_HANDLED := "not_handled"


## Whether this sink owns `beat`: true when the beat's `fact` is one the AUTHORED world
## is written about — some `EventDef` names it as a beat it fires or as a requirement a
## stage gates on.
##
## A cheap predicate over the catalog and the beat, with NO ledger read: whether a fact
## is authored is a content question and does not change between two beats in the same
## frame. A fact no event names is left for another handler, or recorded unclaimed,
## which ADR 0114 says is correct — a fact that happened is true whether or not a
## handler cared.
##
## A null actor still claims here, and the asymmetry with `QuestBeatHandler` is
## deliberate: "is this id authored" is a question about the CONTENT TREE, which is
## process-wide, not about a per-actor ledger. `resolve` then finds no open event for
## nobody and reports that, so a beat offered with no owner still gets an honest answer
## rather than being silently unhandled.
## `_context` is named with the leading underscore because this predicate genuinely
## does not need it — see above. The ARITY and types still match `BeatSink`, which is
## what makes this an override rather than a widened signature; only the name is local.
func handles(beat: Variant, _context: Variant = null) -> bool:
	var fact := _fact_of(beat)
	if fact == &"":
		return false
	return _authored_facts().has(String(fact))


## Resolve `beat`: report which open event of `actor` this fact has unblocked.
##
## **This sink records nothing.** The beat is already in the ledger — the director
## records before it consults (ADR 0117 line 46) — so a resolve that re-recorded would
## be a double-count. It also does not advance the world: see the class docstring.
##
## Carries the `BeatSink` keys `claimed` and `reason`, plus the detail a director
## reports verbatim: which events were watching, which of their gates this fact
## satisfies now, and the fact's count and `since` as the ledger holds them AFTER the
## director's write. A sink that could only say "yes" would leave the director
## re-deriving the answer from module internals it is forbidden to reach.
func resolve(beat: Variant, context: Variant = null) -> Dictionary:
	if not handles(beat, context):
		return {"claimed": false, "reason": REASON_NOT_HANDLED, "satisfied": [], "watching": []}
	var actor := _actor_of(context)
	var fact := _fact_of(beat)
	var source := _source_of(beat)
	var satisfied: Array[Dictionary] = []
	var watching: Array[String] = []
	for event_id in _watching(actor, fact):
		watching.append(String(event_id))
		for stage_id in _satisfied_stages(actor, event_id, fact):
			satisfied.append({"event_id": String(event_id), "stage_id": String(stage_id)})
	return {
		"claimed": true,
		"reason": "",
		"ok": true,
		"fact": String(fact),
		"source": source,
		"watching": watching,
		"satisfied": satisfied,
		# Read AFTER the director's record, so these are the numbers a caller would
		# gate on — including `since`, the count at first record, which is what makes
		# "has this happened exactly once" answerable from one row.
		"count": EventFacts.count_of(actor, fact),
		"since": 0 if actor == null else WorldFact.fact(actor, fact).since,
	}


## Every event id of `actor` that has a stage GATE naming `fact`. Open events only: a
## resolved event's ladder is finished and a closed event must not be re-driven by a
## later beat naming the same fact.
##
## Exposed so a director can route by priority without re-reading the catalog, and so a
## test can assert what a beat would claim — the same reason `QuestBeatHandler.watches`
## exists.
func watches(actor: Actor, fact: StringName) -> Array[String]:
	var out: Array[String] = []
	for event_id in _watching(actor, fact):
		out.append(String(event_id))
	return out


# --- Internals -------------------------------------------------------------


## The actor a beat is about, or null. `BeatSink`'s second argument is a `Variant`
## because `contracts/` may not name `core`, so the cast happens once here. Anything
## that is not an `Actor` — including the null a caller passes when there is nobody —
## reads as "no owner".
func _actor_of(context: Variant) -> Actor:
	if context is Actor:
		return context as Actor
	return null


## The fact a beat claims, read through [method WorldBeat.coerce] so both spellings
## resolve to one place. Empty when the value is not a beat in either spelling.
func _fact_of(beat) -> StringName:
	var claim: WorldBeat = WorldBeat.coerce(beat)
	if claim == null:
		return &""
	return claim.fact


## The audit-trail string a beat carries: `"combat"`, `"quest:<id>"`, `"event:<id>"`.
## Empty when absent, which the director reports as `"source": ""` rather than inventing
## one.
func _source_of(beat) -> String:
	var claim: WorldBeat = WorldBeat.coerce(beat)
	if claim == null:
		return ""
	return claim.source


## Every fact id any authored `EventDef` names — as an `on_enter` beat it fires or as a
## requirement a stage gates on. The set `handles` is a membership test against.
##
## Bounded by the authored tree, and computed per call because a def may be registered
## at run time (`EventCatalog.register`) and a cached set would then be stale — the same
## reason `EventCatalog.reload` exists. Composition roots pay this once per boot; a
## content tree that made it hot is a content tree with too many events, and
## `EventDef.MAX_STAGES` already bounds the ladder.
static func _authored_facts() -> Dictionary:
	var out := {}
	for event_id in EventCatalog.instance().event_ids():
		var def := EventCatalog.instance().event_definition(event_id)
		if def == null:
			continue
		for beat in def.opening_beats():
			out[String(beat.get(BEAT_FACT, ""))] = true
		for stage in def.stages:
			if stage == null:
				continue
			for fact in _requirement_facts(stage.requires):
				out[String(fact)] = true
			for beat in stage.on_enter:
				out[String(beat.get(BEAT_FACT, ""))] = true
	return out


## Every fact id named anywhere inside a requirement, composites included — one walk, so
## a fact behind three nested `all_of`s is found at the same depth as a bare one.
static func _requirement_facts(requirement: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	if requirement.is_empty():
		return out
	var verb := StringName(requirement.get("verb", ""))
	if verb == EventFacts.VERB_FACT:
		var fact_id := StringName(requirement.get("id", ""))
		if fact_id != &"":
			out.append(fact_id)
		return out
	var children = requirement.get("of", [])
	if children is Array:
		for child in children as Array:
			if child is Dictionary:
				out.append_array(_requirement_facts(child as Dictionary))
	return out


## The OPEN events of `actor` with a stage gate naming `fact`. An empty array for a
## null actor: there is no ledger, so nothing is being watched.
func _watching(actor: Actor, fact: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if actor == null or fact == &"":
		return out
	var ledger := EventApi.state(actor)
	for event_id in EventState.active_ids(ledger):
		var def := EventCatalog.instance().event_definition(event_id)
		if def == null:
			continue
		var entry := EventState.active_entry(ledger, event_id)
		var stage_id := StringName(entry.get("stage_id", &""))
		var next_id := def.next_stage_id(stage_id)
		if next_id == &"":
			continue
		var next := def.stage_named(next_id)
		if next != null and _requirement_facts(next.requires).has(fact):
			out.append(event_id)
	return out


## The next stages of `event_id` whose `requires` gate `fact` has now satisfied.
##
## Read AFTER the director's record, which is the whole ordering point (ADR 0117
## line 48: resolving first decides a crossing stage against a count that does not yet
## include the beat). Only the IMMEDIATE next stage is considered: a ladder is walked
## one period at a time by `advance`, and a sink that reported a stage three rungs down
## would be reporting a state the world has not reached.
func _satisfied_stages(actor: Actor, event_id: StringName, fact: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if actor == null:
		return out
	var def := EventCatalog.instance().event_definition(event_id)
	if def == null:
		return out
	var ledger := EventApi.state(actor)
	var stage_id := StringName(EventState.active_entry(ledger, event_id).get("stage_id", &""))
	var next_id := def.next_stage_id(stage_id)
	if next_id == &"":
		return out
	var next := def.stage_named(next_id)
	if next == null or not _requirement_facts(next.requires).has(fact):
		return out
	if bool(EventGate.evaluate(actor, next.requires).get("ok", false)):
		out.append(next_id)
	return out
