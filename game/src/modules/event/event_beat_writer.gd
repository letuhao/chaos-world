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
## ## Both ledgers are named by CONSTANT, never by reaching into a sibling
##
## The fact ledger's key is ADR 0113's (`world_facts`, recorded in this module as
## `EventFacts.MODULE_KEY`) and the npc roster's is `NpcState.MODULE_KEY`, read by
## name rather than through `NpcApi`. `BARE_REF_UNITS` excludes `modules/*`, so a
## bare `NpcState` reference here would report ZERO boundary violations and a cycle
## written that way would be invisible to `_find_cycle` — the exact hazard ADR 0083
## documents. A constant cannot hide an edge: it is one string, greppable, and it
## has no type behind it for a cycle to travel through.

## The roster key `NpcApi` persists under, read by name rather than through a bare
## `NpcState` reference (see the class note on why a bare one would be invisible).
const NPC_ROSTER_KEY := &"npc_state"

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
static func offer(actor: Actor, beat: Dictionary, occurrence: int, sequence: int) -> Dictionary:
	var fact_id := StringName(beat.get("fact", ""))
	if fact_id == &"":
		return {"ok": false, "reason": "no_fact", "skipped": 1}
	var amount := int(beat.get("amount", 1))
	if amount <= 0:
		return {"ok": false, "reason": "no_amount", "skipped": 1}
	var kind := StringName(beat.get("kind", KIND_FACT))
	if not KINDS.has(kind):
		return {"ok": false, "reason": "unknown_beat_kind", "kind": String(kind), "skipped": 1}

	var ledger := EventFacts.ledger(actor)
	var beat_id := EventFacts.occurrence_id(fact_id, occurrence)
	var before := EventFacts.count_of(ledger, fact_id)
	EventFacts.record(ledger, fact_id, amount, sequence)
	_write_facts(actor, ledger)

	var tallied := false
	if kind == KIND_NPC_TALLY:
		tallied = _tally_npc(
			actor, StringName(beat.get("npc_id", "")), StringName(beat.get("verb", ""))
		)

	return {
		"ok": true,
		"beat_id": String(beat_id),
		"source": String(beat.get("source", "")),
		"kind": String(kind),
		"fact_id": String(fact_id),
		"count": maxi(before, EventFacts.count_of(ledger, fact_id)),
		"npc_tallied": tallied,
	}


## Write the ledger back under ADR 0113's key, normalized. Normalized on the way out
## so a hand-edited save cannot inject a wrong type into the next reader.
static func _write_facts(actor: Actor, ledger: Dictionary) -> void:
	actor.set_module_data(EventFacts.MODULE_KEY, EventFacts.normalize(ledger))


## Route an `npc_tally` beat into the roster's tally table, which is `NpcApi.tally`'s
## storage. The ROSTER is the write target; the stage advance that `tally` would also
## cause belongs to `NpcApi`, not to an event director — an event that silently walked
## a herald's story ladder would be ADR 0114's "three dispatchers" failure with a
## different name. Returns whether the row was written.
##
## The key is `tally`, not `counters`, because `NpcRosterEntry.to_dict` writes that
## exact key and a beat writing any other one would be a counter nothing ever reads.
## String keys throughout, for the reason on `NpcRosterEntry._string_keyed`: a
## `StringName` key survives a JSON hop as itself, while a save written by another
## tool would stringify it and then fail to find the verb again.
static func _tally_npc(actor: Actor, npc_id: StringName, verb: StringName) -> bool:
	if actor == null or npc_id == &"" or verb == &"":
		return false
	var roster = actor.get_module_data(NPC_ROSTER_KEY)
	if not (roster is Dictionary):
		return false
	var entries = (roster as Dictionary).get("entries", {})
	if not (entries is Dictionary):
		return false
	var entry = (entries as Dictionary).get(String(npc_id), null)
	if not (entry is Dictionary):
		return false
	var tally = (entry as Dictionary).get("tally", {})
	if not (tally is Dictionary):
		tally = {}
	var key := String(verb)
	tally[key] = int((tally as Dictionary).get(key, 0)) + 1
	(entry as Dictionary)["tally"] = tally
	(entries as Dictionary)[String(npc_id)] = entry
	(roster as Dictionary)["entries"] = entries
	actor.set_module_data(NPC_ROSTER_KEY, (roster as Dictionary).duplicate(true))
	return true
