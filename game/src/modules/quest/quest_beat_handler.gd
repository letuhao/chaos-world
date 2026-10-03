class_name QuestBeatHandler
extends BeatSink

## The `quest` module's end of ADR 0114: a beat handler that claims a beat whose
## fact an ACTIVE quest is watching, and resolves it by asking the quest module to
## re-read the ledger.
##
## ## The `BeatSink` contract
##
## ADR 0114 puts `BeatSink` in `contracts/beat_sink.gd` with two virtuals:
## `handles(beat, context) -> bool` and `resolve(beat, context) -> Dictionary`,
## and says a handler **never mutates** — it returns a proposal and the director
## applies. **This class extends that contract.** It did not when first written,
## because the contracts file had not landed yet: the handler widened `handles` to
## take `(beat, actor)` — a beat names nobody, and a fact ledger is per-actor —
## and a widened signature is not an override of anything, so nothing could be
## dispatched against it and nothing could be held to the contract tests. The fix
## was the contract's, not this file's: `context` is now a parameter of
## `handles`/`resolve`, and the two spellings agree.
##
## ## Why a quest handler is the right first consumer
##
## ADR 0114's whole argument is that three zero-caller seams
## (`NpcApi.advance_stage`, `NpcApi.tally`, `NationApi.resolve_conflict`) need ONE
## caller each at the place that owns the decision. The quest chain is the place
## that already answers "did the player just do the thing?", because that is
## literally what a quest step is. So: a world's interaction records a fact, the
## director offers the beat here, this handler claims it when an active quest
## cares, and `QuestApi.advance` decides what completed.
##
## **It claims a beat, it does not answer it.** `handles()` is a cheap predicate
## over the beat's `fact` and the active quests' watched facts — no ledger read,
## no gate, no allocation. A beat whose fact no active quest watches is left for
## another handler, or recorded unclaimed, which ADR 0114 says is correct: a fact
## that happened is true whether or not a handler cared.

## The beat field carrying the fact id. ADR 0114 fixes `WorldBeat` as
## `{id, fact, amount, source}`; a beat may also arrive as that plain dictionary,
## so both spellings are read.
const BEAT_FACT := "fact"


## Whether this handler owns `beat`: true when the beat's `fact` matches a step
## of some quest the actor in `context` has ACTIVE. A quest that is offered but not
## accepted, or already completed, does not claim — completion is once, and a
## completed quest must not be re-driven by later beats.
##
## A null actor claims nothing: an empty ledger has no active quests, and a
## handler that claims for "nobody" would resolve every beat in the game.
func handles(beat: Variant, context: Variant = null) -> bool:
	var actor := _actor_of(context)
	if beat == null or actor == null:
		return false
	var fact := _fact_of(beat)
	if fact == &"":
		return false
	return not _matching_quest_ids(actor, fact).is_empty()


## Resolve `beat`: hand it to `QuestApi.advance` and return the completion list.
##
## This is the ADR 0114 proposal, not a mutation — `advance()` reads the ledger
## and marks quests complete, but it never records a fact. Recording is the
## director's, from the caller's beat. The distinction is what keeps the ledger
## honest: a handler that recorded its own claim could manufacture a fact out of
## nothing.
##
## Carries the `BeatSink` keys `claimed` and `reason` plus the detail a director
## reports verbatim: which quests completed and what was paid. A sink that could
## only say "yes" would leave the director re-deriving the answer from module
## internals it is forbidden to reach.
func resolve(beat: Variant, context: Variant = null) -> Dictionary:
	if not handles(beat, context):
		return {"claimed": false, "reason": "not_handled", "completed": []}
	var actor := _actor_of(context)
	var source := _source_of(beat)
	var outcome := QuestApi.advance(actor, source)
	return {
		"claimed": true,
		"reason": "",
		"ok": true,
		"fact": String(_fact_of(beat)),
		"source": source,
		"completed": outcome.get("completed", []),
		"paid": outcome.get("paid", []),
		"unspent": outcome.get("unspent", []),
	}


## Every ACTIVE quest of `actor` that watches `fact`. The same predicate
## `handles()` uses, exposed so a director can route by priority without
## re-reading the ledger, and so a test can assert what a beat would claim.
func watches(actor: Actor, fact: StringName) -> Array[String]:
	var out: Array[String] = []
	for quest_id in _matching_quest_ids(actor, fact):
		out.append(String(quest_id))
	return out


# --- Internals -------------------------------------------------------------


## The actor a beat is about, or null.
##
## `BeatSink`'s second argument is a `Variant` because `contracts/` may not name
## `core` and `Actor` lives there, so the cast happens once here rather than in
## every override. Anything that is not an `Actor` — including the null a caller
## passes when there is nobody — reads as "no owner", and a sink with no owner
## claims nothing.
func _actor_of(context: Variant) -> Actor:
	if context is Actor:
		return context as Actor
	return null


## The active quest ids watching `fact`. Bounded by the authored quest count —
## a `for` over the ledger's active ids, never an open-ended search.
func _matching_quest_ids(actor: Actor, fact: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if fact == &"":
		return out
	var ledger := QuestState.normalize(actor.get_module_data(QuestState.MODULE_KEY))
	for quest_id in QuestState.active_ids(ledger):
		var def := QuestCatalog.instance().definition(quest_id)
		if def == null:
			continue
		if def.watches_fact(fact):
			out.append(quest_id)
	return out


## The fact a beat claims. Accepts either a `WorldBeat` value object (an object
## with a `fact` property, once `core/world_beat.gd` lands) or the plain
## dictionary ADR 0114 describes it as. Empty when neither shape carries one.
func _fact_of(beat) -> StringName:
	if beat is Dictionary:
		return StringName((beat as Dictionary).get(BEAT_FACT, ""))
	var value = beat.get("fact")
	if value == null:
		return &""
	return StringName(value)


## The audit-trail string a beat carries: `"combat"`, `"quest:<id>"`,
## `"event:<id>"` (ADR 0114). Empty when absent, which `QuestApi.advance` treats
## as "no source" rather than inventing one.
func _source_of(beat) -> String:
	if beat is Dictionary:
		return String((beat as Dictionary).get("source", ""))
	var value = beat.get("source")
	if value == null:
		return ""
	return String(value)
