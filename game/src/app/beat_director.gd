class_name BeatDirector
extends RefCounted

## The one place a beat is resolved (ADR 0114). Wiring, not rules — the same shape
## as [code]StatusLoop[/code] (ADR 0089): a `RefCounted` in the composition root
## that holds the collaborators and calls them, owns no clock, persists nothing and
## is not an autoload.
##
## ## Why this file exists
##
## ADR 0114 was Accepted on 2026-10-03 with `contracts/beat_sink.gd` and
## `core/world_beat.gd` in place and **no director**. `BeatSink` had zero
## implementers and zero callers. `EventBeatWriter` recorded beats from inside the
## `event` module, consulting nobody, and `QuestBeatHandler` sat unused — so the
## two halves of ADR 0114 were both live and neither could reach the other, and
## the only caller of `QuestApi.advance` in the whole repository was a test. A
## world event recorded a fact that completed a quest's step and the quest did not
## complete.
##
## ## What the director owns, and what it does not
##
## **It owns: one beat reaches exactly one decision, and is recorded exactly once.**
## Sinks are consulted in registration order, the first that claims wins, and its
## [method BeatSink.resolve] is the only one called — a claim is not a veto and a
## second claimant is never asked. The ledger write happens whether or not anyone
## claimed, because a fact that happened is true whether or not a handler cared.
##
## **It does not own "did this already fire".** ADR 0114 assigns that to the
## caller, and it is right to: `WorldFact`'s ledger is monotone over `fact`, so it
## can only answer "how many times", never "has this specific occurrence been
## counted". The honest cost is that the caller mints an id unique per occurrence
## (`killed_boar@3`), and NOTHING HERE can catch a caller that does not. A registry
## of applied ids would answer the question for one session and then disagree with
## the ledger after a save/load — which is the ADR 0066 failure mode with a
## different name: a second copy of a truth that the first copy owns. So there is
## no such registry, deliberately. [method offer] reports the occurrence id it was
## handed so a caller can see it, and [method BeatSink] refuses what it cannot
## judge.
##
## ## Record BEFORE resolve, and why that order is load-bearing
##
## A sink's proposal is computed against the ledger, so the ledger must already
## contain the beat. `QuestBeatHandler` calls `QuestApi.advance`, which reads the
## ledger's counts; resolve-first records after the crossing step was already
## decided against the old count and the quest completes on the *next* beat, or
## never. Recording first is still "recording is not dispatching" — the two acts
## are separate, and this only fixes which one happens first.
##
## ## Modules may not reach this
##
## A module reaches its sinks through `app/`, not the other way round (ADR 0093:
## announce, never request). This file is the composition root's, so it may name
## `core` and the module facades it wires; nothing in `modules/` may name it.

## The sinks, in the order they are consulted. First claim wins, so registration
## order IS priority and is therefore part of the contract, not an implementation
## detail. Typed as the contract so a structural imitation cannot be added by
## accident — that is the failure `BeatSink` exists to prevent.
var _sinks: Array[BeatSink] = []


## Register `sink` as a candidate. Later registrations are consulted later, and a
## sink already registered is not added twice: a duplicate would be a second
## handler answering the same beat.
func add_sink(sink: BeatSink) -> void:
	if sink == null or _sinks.has(sink):
		return
	_sinks.append(sink)


## The registered sink names, in priority order. A director with zero sinks is not
## a stub — it is a recorder, which is the property that lets one subsystem ship
## before another has a sink at all.
func sink_names() -> Array[String]:
	var out: Array[String] = []
	for sink in _sinks:
		out.append(sink_name(sink))
	return out


## Offer one beat to the sinks for `actor`, and record it exactly once.
##
## Returns a primitives-only report. Refusals name themselves:
##   `no_actor`        — there is nobody whose ledger could hold this.
##   `invalid_beat`    — the value is not a beat in either spelling.
##   `no_occurrence_id`— it does not name WHICH occurrence (ADR 0114's once-rule).
##   `no_fact`         — it names no fact to accrue to.
##   `no_amount`       — it claims a non-positive amount, which `WorldFact.record`
##                       would refuse anyway, so it is refused here with the same
##                       cause rather than three stages later.
## On a refusal nothing is written and no sink is consulted: a claim that cannot be
## read is not offered to anybody. **A refusal also moves no destiny counter**, and
## says so: `counter_total` is 0 on every refusal path, so the one report shape
## carries the answer whether or not the beat was recorded.
##
## ## A beat that a fate reads also moves that fate's counter
##
## `destiny`'s gate verb `counter` reads `DestinyApi.counter`, and nothing else in
## the tree writes one. So after the sinks are consulted and before the report is
## built, [method DestinyProjection.on_fact_recorded] moves the counter this beat's
## fact is authored against — the mapping is an explicit table, never a name match.
## That closes DEF-0121/DEF-0181 (`duels_won`, `kills` and the rest were
## permanently 0, so the verb was theatre) without a second dispatcher and without a
## frame driver. See `modules/destiny/destiny_projection.gd` for why it is here
## rather than in a sink.
func offer(actor: Actor, beat) -> Dictionary:
	if actor == null:
		return _report(false, "no_actor", "", &"", 0, "", false, {}, "")
	var claim: WorldBeat = WorldBeat.coerce(beat)
	if claim == null:
		return _report(false, "invalid_beat", "", &"", 0, "", false, {}, "")
	if claim.id == &"":
		return _report(
			false, "no_occurrence_id", "", claim.fact, claim.amount, claim.source, false, {}, ""
		)
	if claim.fact == &"":
		return _report(
			false, "no_fact", String(claim.id), &"", claim.amount, claim.source, false, {}, ""
		)
	if claim.amount < 1:
		return _report(
			false,
			"no_amount",
			String(claim.id),
			claim.fact,
			claim.amount,
			claim.source,
			false,
			{},
			""
		)

	# Record FIRST. See the class docstring: a sink proposes against the ledger,
	# so the ledger has to already carry the beat.
	var written := WorldFact.record(actor, claim.fact, claim.amount)
	var recorded := bool(written.get("ok", false))

	# Then consult, in priority order, and stop at the first claim. The `break` is
	# the invariant: two sinks resolving one beat is how a reward gets paid twice.
	var winner: BeatSink = null
	for sink in _sinks:
		if sink.handles(claim, actor):
			winner = sink
			break

	var outcome: Dictionary = {}
	var claimed := false
	if winner != null:
		outcome = winner.resolve(claim, actor)
		claimed = bool(outcome.get("claimed", true))

	# ## The `destiny` bridge — the last step, after everything above
	#
	# `destiny`'s gate verb `counter` reads `DestinyApi.counter`, and until this
	# dispatch existed nothing in the shipped tree ever wrote one: all nine authored
	# counter ids sat at 0 forever, so `{verb: &"counter", id: &"duels_won", need: 3}`
	# in a `.tres` could never open (DEF-0121, DEF-0181).
	#
	# **Here, and nowhere else, for two reasons.**
	# 1. *One writer.* `beat_director.gd:122` is the ONE place a beat is made
	#    true in production — `WorldPulse.offer` reaches it, and `WorldPulse.offer`
	#    is the only offer point in `app/` (class docstring). Dispatching here gives
	#    the `counter` verb a writer without a second dispatcher, which is ADR
	#    0114's named failure under a different name.
	# 2. *After the sinks, never instead of one.* A sink is PURE and the director
	#    applies (ADR 0117); a beat is still recorded whether or not a handler cared.
	#    The counter moves after the winner holds its own report, so a beat belonging
	#    to the quest or the event module is not diverted, and the report below still
	#    names `claimed_by`.
	#
	# `DestinyProjection.on_fact_recorded` is a pure lookup followed by one call to
	# `DestinyApi.record` — the facade's own monotone verb. It weakens nothing,
	# lowers nothing, and adds no frame driver.
	var counter := DestinyProjection.on_fact_recorded(actor, claim.fact, claim.amount)
	return _report(
		recorded,
		"",
		String(claim.id),
		claim.fact,
		claim.amount,
		claim.source,
		claimed,
		outcome,
		"" if winner == null else sink_name(winner),
		# Present on every report, and 0 for the overwhelming majority of beats. An
		# audit reads `counter_id == ""` as "this beat moved no fate counter" without
		# having to know which facts are wired.
		0 if counter <= 0 else counter
	)


## Offer every beat in `beats` and return one report per beat, in the order given.
##
## A `for` over the array and nothing else: the caller owns how many beats a moment
## has, and a refusal on one beat does not skip the rest — a mis-authored beat must
## not swallow the beats after it.
func offer_all(actor: Actor, beats: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for beat in beats:
		out.append(offer(actor, beat))
	return out


# --- Internals -------------------------------------------------------------


## The name `sink` is reported under, everywhere this class names one.
##
## A class name first, then the script's own file, then `anonymous`. The last
## step is not a corner case: a script with no `class_name` — a sink written as an
## inner class in a test, which is the right way to write one — has neither a
## global name nor a resource path, and reporting "" for it would make every "who
## answered this beat" assertion untestable. Public rather than private so a test
## asserts against this and not against a copy of it.
static func sink_name(sink: BeatSink) -> String:
	if sink == null:
		return ""
	var script: Script = sink.get_script() as Script
	if script == null:
		return "anonymous"
	var named: String = script.get_global_name()
	if named != "":
		return named
	var file := script.resource_path.get_file()
	return file if file != "" else "anonymous"


## One primitives-only report. `outcome` is COPIED key by key and only where it
## does not collide with the report's own keys, so a sink cannot overwrite
## `recorded` with its own idea of the word — the director owns what it recorded.
##
## `counter_total` is the destiny counter the beat moved, AFTER the move, and 0 for
## every refusal and for every beat no fate reads. **Always present**, including on
## a refusal, so the report keeps ONE shape: a caller can read `counter_total`
## without first asking whether the beat was recorded. It rides here rather than
## into `detail` because the director produced it, not a sink, and a sink must not
## be able to overwrite it the way `detail`'s copy rule exists to prevent.
static func _report(
	ok: bool,
	reason: String,
	beat_id: String,
	fact: StringName,
	amount: int,
	source: String,
	claimed: bool,
	outcome: Dictionary,
	claimed_by: String,
	counter_total: int = 0
) -> Dictionary:
	var out := {
		"ok": ok,
		"reason": reason,
		"beat_id": beat_id,
		"fact": String(fact),
		"amount": amount,
		"source": source,
		"claimed": claimed,
		"claimed_by": claimed_by,
		"counter_total": counter_total,
		"resolve_reason": String(outcome.get("reason", "")),
		"detail": {},
	}
	var detail := {}
	for key in outcome.keys():
		var name := String(key)
		if name == "claimed" or name == "reason" or name == "ok":
			continue
		detail[name] = outcome[key]
	out["detail"] = detail
	return out
