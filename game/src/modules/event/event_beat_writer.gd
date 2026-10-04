class_name EventBeatWriter
extends RefCounted

## Where a beat goes, and the one place the event module touches another module's
## ledger (ADR 0114).
##
## ## A beat is a proposal; the sink applies
##
## ADR 0114: "A handler never mutates. It returns a proposal; the director applies."
## So this writer takes a BEAT — `{id, fact, amount, actor_id, source}` — and applies
## it. Nothing in this file decides *what* happened; the authored `on_enter` rows and
## the caller that pulled the periods decide that, and this is the only path by which
## a fact the world gains becomes a count in a ledger.
##
## ## The fact ledger is `WorldFact`'s, and this file calls it
##
## ADR 0113 places the ledger at `actor.module_data["world_facts"]` and
## `core/world_fact.gd` owns it. **This writer records through `WorldFact.record`
## and normalises nothing itself.** It used to carry its own `normalize` and its own
## `record` over the same key, which meant an event beat silently rewrote every
## other system's rows into `{id, count}` and dropped their `since` — the field
## `WorldFact`'s "has this happened exactly once" gate reads. One writer, one key.
## `core` is a declared dependency of `event` in `tools/arch/registry.json`, so the
## edge is declared rather than inferred.
##
## ## The beat is RECORDED and then RESOLVED by one director (DEF-0171)
##
## A beat used to stop at this file: `WorldFact.record` wrote the ledger and nothing
## asked what it meant, so `EventBeatSink` — registered by `app/world_pulse.gd` and
## never consulted for an authored event's own fact — was decoration, and ADR 0117's
## "recorded *then resolved* by one director" was half true. A module may not reach a
## director (ADR 0093), so the beat is pushed **up** to the composition root through
## an injected `Callable` ([method set_offer_resolver], the `NpcApi.set_minter`
## inversion), and `WorldPulse.offer_event_beat` hands it to the one director. The
## write is DELEGATED rather than duplicated: exactly one `WorldFact.record` runs per
## beat on either path, which is why re-offering these beats from `WorldPulse` would
## double-count and this file does not ask it to.
##
## ## The npc roster is reached through the FACADE, injected by `app/`
##
## This writer used to reach into `actor.module_data["npc_state"]` and write the
## tally table itself — a SECOND writer for a table `NpcApi.tally` owns. Two writers
## means the verb check (`advance_verb`) and the `MAX_TALLY_KEYS` cap apply to one
## path and not the other, and the two can disagree about the same save. `NpcApi` is
## at its twelve-method facade cap, so the seam is not a new verb but an injected
## resolver, exactly the `set_minter` inversion ADR 0002 describes: `app/` installs
## `Callable(NpcApi, "tally")` and `event/` names no npc type at all.
##
## The constant below is kept only as the reason a null injection is refused rather
## than as a key this file writes. A `NpcState` bare reference here would report
## ZERO boundary violations (`BARE_REF_UNITS` excludes `modules/*`) and a cycle
## written that way would be invisible to `_find_cycle` — the exact hazard ADR 0083
## documents.

## The roster key `NpcApi` persists under, named for diagnostics only. Nothing in
## this file reads or writes it: the tally goes through the injected facade verb.
const NPC_ROSTER_KEY := &"npc_state"

## The injected tally verb: `Callable(NpcApi, "tally")`, installed by
## `NpcBoot.install` from the composition root. Null until `app/` runs, which is a
## loud refusal (`no_tally_resolver`) rather than a silent skip — an authored
## `npc_tally` beat that quietly tallies nothing is BL-0658 again.
static var _tally_resolver: Callable = Callable()

## The injected OFFERER: `app/` passes `Callable(WorldPulse, "offer_event_beat")`
## so an authored `on_enter` beat is RECORDED AND THEN RESOLVED by the one director
## (ADR 0117 line 46). Null until `app/` runs, and the fallback below is the module
## recording on its own — which is the honest half-truth: a composition root that
## exists resolves the beat, and one that does not still records the fact.
static var _offer_resolver: Callable = Callable()


## Inject the roster's tally verb. `app/` passes `Callable(NpcApi, "tally")`.
##
## Following the `set_minter` precedent: the module never names `NpcApi`, and a
## missing injection fails loudly at the call site instead of dereferencing nothing.
static func set_tally_resolver(resolver: Callable) -> void:
	_tally_resolver = resolver


## Inject the director's offerer. `app/` passes `Callable(WorldPulse,
## "offer_event_beat")`.
##
## ## Why this exists at all (DEF-0171)
##
## `EventBeatSink` is registered by `WorldPulse.bind_director` and was **never
## consulted for an authored event beat**, because this writer went straight to
## `WorldFact.record`. So ADR 0117's "recorded *then resolved* by one director" was
## half-true: the recording half was real and the resolving half was not, and a
## quest step watching an event's own fact stayed outstanding forever.
##
## ## Why the fallback is NOT a silent skip
##
## With no offerer installed this file still records, because a fact that happened
## is true whether or not a handler cared (ADR 0114). What it cannot do is resolve,
## and the report says so: `offered` is `false`, so a caller can tell "recorded and
## nobody claimed it" from "nobody was listening at all". The module's own suites
## keep passing without a composition root, which is what makes the seam testable
## from both sides.
static func set_offer_resolver(resolver: Callable) -> void:
	_offer_resolver = resolver


## The `on_enter` entry kinds a beat may carry.
##
## `fact` is the whole vocabulary's default and the only one ADR 0114's ledger needs.
## `npc_tally` is a second destination for the SAME proposal rather than a second
## beat type: a stage may say "the world remembers this, AND the herald heard it",
## and both are one claim about one occurrence. A kind outside this set is DROPPED
## and reported in `skipped` — a mis-authored beat fails loudly rather than silently
## recording nothing.
const KIND_FACT := &"fact"
const KIND_NPC_TALLY := &"npc_tally"
const KINDS: Array[StringName] = [KIND_FACT, KIND_NPC_TALLY]


## Offer one beat and apply it. Returns the outcome, so a caller can see whether the
## beat landed without reading the ledger back.
##
## `occurrence` mints the beat id per ADR 0114's once-rule: the caller NAMES the
## occurrence (`killed_boar@3`) because a monotone ledger can only answer "has this
## fired" by counting. It is a caller's own counter, never a clock read.
static func offer(actor: Actor, beat: Dictionary, occurrence: int) -> Dictionary:
	var fact_id := StringName(beat.get("fact", ""))
	if fact_id == &"":
		return {"ok": false, "reason": "no_fact", "skipped": 1}
	var amount := int(beat.get("amount", 1))
	if amount <= 0:
		return {"ok": false, "reason": "no_amount", "skipped": 1}
	var kind := StringName(beat.get("kind", KIND_FACT))
	if not KINDS.has(kind):
		return {"ok": false, "reason": "unknown_beat_kind", "kind": String(kind), "skipped": 1}

	var beat_id := EventFacts.occurrence_id(fact_id, occurrence)
	# ## THE ORDER IS THE WHOLE POINT (ADR 0117 line 46: record, then resolve)
	#
	# The ledger write below is DELEGATED to the injected offerer when one is
	# installed, and the offerer hands the beat to `BeatDirector.offer` — which
	# **records it and then resolves it in that order**, because a sink's proposal is
	# computed AGAINST the ledger: resolving first decides a crossing gate against a
	# count that does not yet include this beat, and the quest step completes a period
	# late or never. ADR 0117 measured that reversal; it is not a preference.
	#
	# So there is exactly ONE `WorldFact.record` per beat on either path, which is the
	# whole reason the seam is a delegation and not an extra call. This is the shape
	# [code]WorldPulse.offer[/code] already has for every other beat in the game —
	# offer it, and the director both records and resolves — which is why the event
	# module's beats were the last ones still bypassing it.
	#
	# With no offerer the write below is the whole job: a fact that happened is true
	# whether or not a handler cared (ADR 0114). The report then marks the beat
	# un-resolved, so "recorded and nobody listened" stays distinguishable from
	# "recorded and a sink answered".
	var written := _record(actor, fact_id, amount, beat_id, String(beat.get("source", "")))
	if not bool(written.get("ok", false)):
		# A ledger that would not take the beat is REFUSED rather than assumed away,
		# and the refusal is returned verbatim so the caller can name it.
		return {"ok": false, "reason": String(written.get("reason", "")), "skipped": 1}

	var tallied := false
	var tally_reason := ""
	if kind == KIND_NPC_TALLY:
		tally_reason = _tally_npc(
			actor,
			StringName(beat.get("npc_id", "")),
			StringName(beat.get("verb", "")),
			String(beat.get("source", ""))
		)
		tallied = tally_reason == ""

	var resolved := bool(written.get("claimed", false))
	var resolve_reason := (
		"" if bool(written.get("ok", false)) else String(written.get("reason", ""))
	)
	return {
		"ok": true,
		"beat_id": String(beat_id),
		"source": String(beat.get("source", "")),
		"kind": String(kind),
		"fact_id": String(fact_id),
		"count": int(written.get("count", 0)),
		"npc_tallied": tallied,
		# Always present, "" on a success: one report shape means a caller can read
		# WHY a beat tallied nothing without having to re-derive it.
		"npc_tally_reason": tally_reason,
		# ## The dispatch half, in the same shape.
		#
		# `offered` says the director was reached; `claimed` says a sink took it. A
		# false `offered` with a false `claimed` is a COMPOSITION ROOT THAT IS NOT
		# THERE, which is a different diagnosis from a beat nobody wanted — and that
		# difference is exactly what DEF-0171's "half true" looked like from outside.
		"offered": bool(written.get("recorded", false)),
		"claimed": resolved,
		"claimed_by": String(written.get("claimed_by", "")),
		"resolve_reason": resolve_reason,
	}


## Record this occurrence — OR route it to the injected offerer, which records it
## and resolves it in one step.
##
## **Exactly one `WorldFact.record` runs per beat, whichever branch this takes**, and
## that is the whole reason the seam is a delegation and not an extra call. An
## offerer installed means the DIRECTOR is the recorder (ADR 0117 line 44: "a beat
## is recorded exactly once whether or not a sink claimed it"); no offerer means this
## writer is the only thing between an authored `on_enter` and the world's memory,
## so it records and the report marks the beat un-resolved.
##
## Both branches answer the same keys, so nothing above branches on which one ran.
static func _record(
	actor: Actor, fact_id: StringName, amount: int, beat_id: StringName, source: String
) -> Dictionary:
	if _offer_resolver.is_valid():
		var offered: Variant = _offer_resolver.call(actor, fact_id, amount, beat_id, source)
		if offered is Dictionary:
			return offered as Dictionary
		return {"ok": false, "reason": "offer_resolver_returned_nothing"}
	return WorldFact.record(actor, fact_id, amount)


## Route an `npc_tally` beat into the roster's TALLY TABLE THROUGH THE FACADE.
##
## **This used to write `module_data["npc_state"]` directly, and that was the defect
## BL-0658 names.** The roster's tally is `NpcApi.tally`'s storage and `NpcApi.tally`
## is its only writer: it is the path that checks `advance_verb` (so an unrelated
## verb cannot walk a story npc up their ladder), enforces `NpcRosterEntry
## .MAX_TALLY_KEYS`, and is the one that advances the stage. A second writer skips
## all three, so an authored beat and a direct call could leave the same save saying
## two different things. Now the beat is a proposal and the facade applies it — which
## is also ADR 0114's rule ("a handler never mutates") applied to the roster.
##
## `source` is handed through so a save says which system earned the advance, in
## ADR 0114's own vocabulary (`event:<id>`, from `EventDef.fate_source`).
##
## Returns "" on success and a named reason otherwise, so a refusal is visible on
## the report rather than a beat that quietly tallied nothing.
static func _tally_npc(
	actor: Actor, npc_id: StringName, verb: StringName, source: String
) -> String:
	if actor == null or npc_id == &"" or verb == &"":
		return "incomplete_tally_beat"
	if _tally_resolver.is_null():
		push_error(
			(
				(
					"EventBeatWriter: an npc_tally beat named '%s' but no tally resolver is installed;"
					% String(npc_id)
				)
				+ " call EventBeatWriter.set_tally_resolver from app/ (NpcBoot.install does)"
			)
		)
		return "no_tally_resolver"
	var outcome: Variant = _tally_resolver.call(npc_id, verb, source)
	if not (outcome is Dictionary):
		return "tally_resolver_returned_nothing"
	if bool((outcome as Dictionary).get("ok", false)):
		return ""
	return String((outcome as Dictionary).get("reason", "tally_refused"))
