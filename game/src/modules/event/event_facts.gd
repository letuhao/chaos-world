class_name EventFacts
extends RefCounted

## The event module's ONE reader of the world fact ledger (ADR 0113).
##
## ## The ledger's key is owned elsewhere, and read here by name
##
## ADR 0113 places the ledger at `actor.module_data["world_facts"]` under
## `WorldFactLedger`, in `core/`. **This file is the reader, not a second copy of the
## writer.** It normalizes what it finds into one shape, reads it, and writes back
## under the same key — so a ledger written by any other consumer is the ledger this
## module reads, and a beat this module offers lands where every other consumer
## looks for it.
##
## ## A fact is a THING THAT HAPPENED, not a reward
##
## `{id, count, since}` and nothing else. `record()` is monotone: it raises a count
## and never lowers one, which is what makes "did this already happen" answerable by
## counting and is why a beat's own id must be unique per occurrence (ADR 0114).
## Nothing in this class grants a fate, moves a currency or touches a stat.
##
## ## The one new verb in the requirement language
##
## `has_fact(id, need)` — `true` once the ledger has recorded `fact_id` at least
## `need` times. This is `{verb: "fact", id: <fact_id>, need: n}` in a trigger, and
## it is the ONLY addition to the `DestinyGate` / `SocialGate` shape. The composite
## verbs are reused untouched, so a fact-gated event is a content edit rather than a
## new gate system.

## `actor.module_data` key ADR 0113 fixes for the ledger. Named as a constant here
## rather than read from a module this one cannot see.
const MODULE_KEY := &"world_facts"
const SCHEMA_VERSION := 1
## The closed verb this module contributes to the shared requirement language.
const VERB_FACT := &"fact"


## The ledger as this module sees it, normalized field by field.
##
## An empty payload reads as an empty ledger — a world that has remembered nothing
## is a normal state, not an error, and the module must work against it before any
## event has ever fired.
static func ledger(actor: Actor) -> Dictionary:
	if actor == null:
		return normalize({})
	return normalize(actor.get_module_data(MODULE_KEY))


## The normalized ledger, JSON-round-trippable: string keys and integer counts
## throughout, because a file-backed save makes one JSON hop and a single number
## type must not leave `count` comparing unequal to itself after a load.
static func normalize(payload: Dictionary) -> Dictionary:
	var out := {"version": SCHEMA_VERSION, "facts": {}, "sequence": 0}
	if payload.is_empty():
		return out
	var data := payload as Dictionary
	out["sequence"] = maxi(0, int(data.get("sequence", 0)))
	var facts = data.get("facts", {})
	if not (facts is Dictionary):
		return out
	for fact_id in (facts as Dictionary).keys():
		var key := String(fact_id)
		if key == "":
			continue
		var entry = (facts as Dictionary)[fact_id]
		out["facts"][key] = {"id": key, "count": maxi(0, _count_of(entry))}
	return out


## How many times `fact_id` has been recorded. 0 when never recorded: a fact is
## monotone, so a missing row and a zero row are the same answer.
static func count_of(ledger: Dictionary, fact_id: StringName) -> int:
	var entry = (ledger.get("facts", {}) as Dictionary).get(String(fact_id), null)
	if not (entry is Dictionary):
		return 0
	return _count_of(entry)


## Whether the ledger holds `fact_id` at least `need` times. The question a gate asks.
static func has_fact(ledger: Dictionary, fact_id: StringName, need: int = 1) -> bool:
	if need < 1:
		need = 1
	return count_of(ledger, fact_id) >= need


## Raise a fact's count and return the ledger. **Monotone**: `amount` at or below
## zero writes nothing, because a fact that happened cannot be taken back (ADR
## 0065's rule applied to remembered things, which is what ADR 0113 inherits).
##
## `occurred_at` is the ledger's OWN sequence number, never a clock read: a fact
## whose age depended on when the file happened to be saved would make the world's
## memory depend on the save (DEF-0111).
static func record(
	ledger: Dictionary, fact_id: StringName, amount: int, occurred_at: int
) -> Dictionary:
	var key := String(fact_id)
	if key == "" or amount <= 0:
		return ledger
	var facts: Dictionary = ledger.get("facts", {})
	var prior = facts.get(key, null)
	var since := occurred_at
	var before := 0
	if prior is Dictionary:
		# `since` is the ledger sequence at which the fact FIRST occurred, and it is
		# carried forward rather than overwritten. `has("since")` and not a `> 0`
		# test, because sequence 0 is a real value: the first beat of a run records
		# at sequence 0 and a truthiness check would forget it on the second record.
		since = int((prior as Dictionary).get("since", occurred_at))
		before = _count_of(prior)
	facts[key] = {"id": key, "count": before + amount, "since": since}
	ledger["facts"] = facts
	ledger["sequence"] = maxi(int(ledger.get("sequence", 0)), occurred_at)
	return ledger


## The next occurrence id for a beat. ADR 0114's once-rule forces the CALLER to
## name the occurrence, because a monotone ledger can only answer "has this fired"
## by counting — so a beat for the third beast is `killed_boar@3` and the fourth is
## `killed_boar@4`. Built from a caller-owned sequence number, never from a clock.
static func occurrence_id(fact_id: StringName, occurrence: int) -> StringName:
	if occurrence > 0:
		return StringName("%s@%d" % [String(fact_id), occurrence])
	return StringName(fact_id)


## Every fact id the ledger holds, canonically ordered.
static func fact_ids(ledger: Dictionary) -> Array[StringName]:
	var strings: Array[String] = []
	for key in (ledger.get("facts", {}) as Dictionary).keys():
		strings.append(String(key))
	strings.sort()
	var out: Array[StringName] = []
	for key in strings:
		out.append(StringName(key))
	return out


static func _count_of(entry) -> int:
	if entry is Dictionary:
		return int((entry as Dictionary).get("count", 0))
	if entry is int or entry is float:
		return int(entry)
	return 0
