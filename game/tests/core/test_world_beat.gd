extends TestCase

## The claim that something happened (ADR 0114).
##
## These assert the three properties the ADR buys: a beat is well-formed or
## names itself, it round-trips as primitives because a beat travels into save
## blobs and UI summaries, and it carries NO consequence — building one, asking a
## sink about it and having a sink claim it all leave the ledger untouched. That
## last one is the distinction the whole ADR exists to draw: a fact that happened
## is true whether or not a handler cared, so recording it is a separate act from
## asking about it.

const THIRD_BEAR := &"killed_boar@3"
const BOAR := &"killed_boar"

# --- A beat is well-formed, or it names itself -------------------------------


## `make` builds a valid beat from its four fields, and the defaults are the ones
## a single occurrence needs: one of this fact, from a caller that has not
## volunteered an audit trail.
func test_make_builds_a_valid_beat() -> void:
	var beat := WorldBeat.make(THIRD_BEAR, BOAR)
	assert_eq(beat.is_valid(), true, "the beat is valid")
	assert_eq(beat.id, THIRD_BEAR, "it carries the occurrence id")
	assert_eq(beat.fact, BOAR, "and the fact it accrues to")
	assert_eq(beat.amount, 1, "one is the default amount")
	assert_eq(beat.source, "", "and no source was volunteered")
	var sourced := WorldBeat.make(THIRD_BEAR, BOAR, 2, "quest:silver_marsh")
	assert_eq(sourced.source, "quest:silver_marsh", "a beat can name where it came from")
	assert_eq(sourced.amount, 2, "and how much it claims")


## An occurrence id must be unique PER OCCURRENCE (ADR 0114), so the third boar
## is `killed_boar@3` and not `killed_boar`. The key is that id and nothing else:
## the ledger's count is the only record of multiplicity.
func test_occurrence_key_is_the_caller_minted_id() -> void:
	assert_eq(
		WorldBeat.make(THIRD_BEAR, BOAR).occurrence_key(), "killed_boar@3", "the key is the id"
	)
	assert_eq(
		WorldBeat.make(BOAR, BOAR).occurrence_key(), "killed_boar", "whatever id the caller minted"
	)
	assert_ne(
		WorldBeat.make(BOAR, BOAR).occurrence_key(),
		WorldBeat.make(THIRD_BEAR, BOAR).occurrence_key(),
		"so two occurrences of the same fact are two distinct keys"
	)


## `is_valid` refuses a beat that names nothing, and refusal is what a sink
## author reads rather than an exception three stages later. `make` does not
## repair it: a beat claiming no fact has no honest reading.
func test_a_beat_naming_nothing_is_invalid() -> void:
	assert_eq(WorldBeat.make(&"", BOAR).is_valid(), false, "no occurrence id is not a beat")
	assert_eq(WorldBeat.make(THIRD_BEAR, &"").is_valid(), false, "nor is no fact")
	assert_eq(WorldBeat.make(&"", &"").is_valid(), false, "and neither together is")
	assert_eq(WorldBeat.new().is_valid(), false, "so a bare instance is not one either")


## An amount claims that something HAPPENED, so it is floored at one. A zero or
## negative claim is a caller bug that `WorldFact.record` refuses with
## `non_positive` anyway; no beat exists in a shape the ledger would reject.
func test_an_amount_is_floored_at_one() -> void:
	assert_eq(WorldBeat.make(THIRD_BEAR, BOAR, 0).amount, 1, "zero still claims one")
	assert_eq(WorldBeat.make(THIRD_BEAR, BOAR, -5).amount, 1, "and so does a negative")
	assert_eq(WorldBeat.make(THIRD_BEAR, BOAR, 5).amount, 5, "a real amount is kept")


## A beat carries no consequence: no reward field, no effect reference, no
## handler list. A proposal that could grant something would be a second accrual
## path beside the one monotone verb ADR 0113 defines, so the whole surface is
## four data members and a named factory.
func test_a_beat_carries_no_reward_and_no_effect() -> void:
	var names: Array[String] = []
	# On an INSTANCE, not on the class: `WorldBeat.get_property_list()` is a
	# non-static call on a class reference, which is a parse error, so this file
	# did not load at all and the property claim was never measured.
	for property in WorldBeat.new().get_property_list():
		names.append(String(property["name"]))
	for forbidden in ["reward", "effect", "effects", "handler", "handlers", "flag", "payload"]:
		assert_eq(names.has(forbidden), false, "a beat has no '%s'" % forbidden)
	assert_eq(names.has("amount"), true, "it carries the amount it claims")
	assert_eq(names.has("fact"), true, "the fact")
	assert_eq(names.has("id"), true, "the occurrence id")
	assert_eq(names.has("source"), true, "and the audit trail")


## The round trip is primitives-only, because a beat travels into a save blob
## and into a UI summary and a `StringName` is not a value in either. `from_dict`
## also COERCES rather than trusting: a save is untrusted input.
func test_a_beat_round_trips_through_json() -> void:
	var beat := WorldBeat.make(THIRD_BEAR, BOAR, 3, "combat")
	var restored := WorldBeat.from_dict(JSON.parse_string(JSON.stringify(beat.to_dict())))
	assert_eq(restored.id, THIRD_BEAR, "the id came back")
	assert_eq(restored.fact, BOAR, "and the fact")
	assert_eq(restored.amount, 3, "and the amount")
	assert_eq(restored.source, "combat", "and the source")
	assert_eq(restored.to_dict(), beat.to_dict(), "so the payload is byte-equal")
	for key in restored.to_dict().keys():
		assert_eq(typeof(key), TYPE_STRING, "every key is a String")
		# Not "every value is a String" — `amount` is an int by design and
		# `to_dict` casts `id`/`fact` deliberately for exactly this reason. The
		# claim is that nothing in the payload is a `StringName` or an object,
		# because a `StringName` survives a JSON hop as itself and then compares
		# unequal to the same name after a load.
		assert_eq(
			typeof(restored.to_dict()[key]) == TYPE_STRING_NAME,
			false,
			"'%s' came back as a plain value, not a StringName" % key
		)
		assert_eq(_is_json_safe(restored.to_dict()[key]), true, "'%s' survives the save hop" % key)


## A restored beat that lost fields comes back reporting itself invalid rather
## than refusing the load: one malformed claim in a save must not take every
## other claim with it.
func test_a_partial_payload_restores_as_an_invalid_beat_not_an_error() -> void:
	var restored := WorldBeat.from_dict({"id": THIRD_BEAR})
	assert_eq(restored.fact, &"", "the missing fact reads as empty")
	assert_eq(restored.amount, 1, "the missing amount reads as one")
	assert_eq(restored.is_valid(), false, "so the beat reports itself invalid")
	assert_eq(restored.occurrence_key(), "killed_boar@3", "while keeping the id it was given")


# --- A beat is a proposal, and a claim is not a dispatch ----------------------


## Building and reading a beat moves no ledger. This is the distinction ADR 0114
## draws: recording is not dispatching, and the ledger is the only truth.
func test_a_beat_on_its_own_records_nothing() -> void:
	var actor := Actor.new(&"hero")
	var beat := WorldBeat.make(THIRD_BEAR, BOAR, 4, "combat")
	var before := JSON.stringify(WorldFact.to_dict(actor))
	assert_eq(beat.to_dict().size(), 4, "the beat is a four-field claim")
	assert_eq(beat.is_valid(), true, "and a valid one")
	assert_eq(beat.occurrence_key(), "killed_boar@3", "and it names its occurrence")
	assert_eq(JSON.stringify(WorldFact.to_dict(actor)), before, "and the ledger never moved")
	assert_eq(WorldFact.count(actor, BOAR), 0, "so the fact was never recorded")
	assert_eq(WorldFact.has(actor, THIRD_BEAR), false, "nor the occurrence")


## A `BeatSink` answers a question about a beat and mutates nothing — ADR 0067's
## "a mechanism returns a proposal" applied to narrative. The base sink claims
## nothing, which is a correct no-op rather than a stub that lies, and
## `contracts/` may not name `core` (ADR 0114), so the beat arrives untyped.
func test_the_default_sink_claims_nothing_and_changes_nothing() -> void:
	var actor := Actor.new(&"hero")
	WorldFact.record(actor, BOAR, 2)
	var before := JSON.stringify(WorldFact.to_dict(actor))
	var sink := BeatSink.new()
	var beat := WorldBeat.make(THIRD_BEAR, BOAR, 1, "combat")
	assert_eq(sink.handles(beat), false, "the base sink claims nothing")
	var outcome := sink.resolve(beat)
	assert_eq(outcome["claimed"], false, "and resolves to no claim")
	assert_eq(JSON.stringify(WorldFact.to_dict(actor)), before, "with the ledger untouched")
	assert_eq(WorldFact.count(actor, THIRD_BEAR), 0, "so nothing was recorded on its behalf")
	for key in outcome.keys():
		assert_eq(
			_is_json_safe(outcome[key]),
			true,
			"'%s' survives a save round trip, so the outcome can travel into one" % key
		)
	assert_eq(outcome.keys().has("amount"), false, "with no effect payload attached")


# --- Every implementation ships these same assertions ------------------------
#
# ADR 0114's `BeatSink` is worth nothing as a name unless every implementation can
# be HELD to it. The base sink alone cannot do that: it is the one implementation
# guaranteed to exist, so a suite that only exercises it measures the abstract base
# and proves nothing about the sinks that matter.
#
# `QuestBeatHandler` is in the list because it is the first real sink, and the
# assertions are in THIS file rather than in its own suite because they are not
# quest-specific: they are what "implements `BeatSink`" means.


## Every `BeatSink` implementation the repo can see, as `{name, sink}` pairs.
##
## A fresh instance per entry, and the base is included on purpose: a contract
## suite that skips the abstract base cannot notice the base drifting away from
## the contract its subclasses implement.
func _implementations() -> Array[Dictionary]:
	return [
		{"name": "BeatSink", "sink": BeatSink.new()},
		{"name": "QuestBeatHandler", "sink": QuestBeatHandler.new()},
	]


## The contract itself, asserted against one named implementation.
func _assert_the_contract(actor: Actor, sink: BeatSink, name: String) -> void:
	var beat := WorldBeat.make(THIRD_BEAR, BOAR, 1, "combat")

	# Purity, part one: asking changes nothing. A sink that moved the ledger while
	# being consulted would make "resolved once" mean "applied as many times as
	# somebody looked".
	var before := JSON.stringify(WorldFact.to_dict(actor))
	sink.handles(beat, actor)
	assert_eq(JSON.stringify(WorldFact.to_dict(actor)), before, "%s.handles writes nothing" % name)
	sink.resolve(beat, actor)
	assert_eq(
		JSON.stringify(WorldFact.to_dict(actor)),
		before,
		"%s.resolve writes nothing: it proposes, the director applies" % name
	)

	# Every legal shape of the two arguments gets an answer rather than an error,
	# so a director holding an unknown or absent owner cannot crash the run.
	assert_eq(sink.handles(beat, null), false, "%s answers a null context" % name)
	assert_eq(sink.handles(null, actor), false, "%s answers a null beat" % name)

	# The context argument is OPTIONAL, and that is behavioural rather than a
	# reflection guess: a caller with no owner omits it instead of inventing one,
	# and the base stays usable as a no-op.
	assert_eq(sink.handles(beat), false, "%s.handles takes the beat alone" % name)
	assert_eq(bool(sink.resolve(beat)["claimed"]), false, "%s.resolve takes the beat alone" % name)

	# The declared keys, present and correctly typed whatever the sink decided.
	var outcome: Dictionary = sink.resolve(beat, actor)
	assert_eq(outcome.has("claimed"), true, "%s names whether it claimed" % name)
	assert_eq(typeof(outcome["claimed"]), TYPE_BOOL, "%s claims with a bool" % name)
	assert_eq(outcome.has("reason"), true, "%s names a reason" % name)
	assert_eq(typeof(outcome["reason"]), TYPE_STRING, "%s reasons with a String" % name)
	# And the whole payload survives the save hop, because a `Resource`, an `Actor`
	# or a callable in here would be a save-schema bug no gate can see.
	for key in outcome.keys():
		assert_eq(
			_is_json_safe(outcome[key]),
			true,
			"%s: '%s' is JSON-safe, so a director can copy it into an announcement" % [name, key]
		)


## Every implementation answers `handles` and `resolve` for every legal shape of
## the two arguments, mutates nothing while doing it, and returns the declared
## keys. One loop over one list: a sink added later is covered by editing a list
## rather than by remembering.
func test_every_beat_sink_implementation_ships_the_contract() -> void:
	for entry in _implementations():
		_assert_the_contract(Actor.new(&"hero"), entry["sink"] as BeatSink, String(entry["name"]))


## The named implementations are real `BeatSink` subclasses, not structural
## imitations of one. This is what the repo rule ("any script implementing a
## `contracts/` interface must pass the same contract tests") actually turns on:
## a class that merely has the right method NAMES is not implementing the
## interface. `QuestBeatHandler` used to be exactly that — the right two methods,
## with a signature the contract could not call.
func test_every_named_sink_actually_extends_the_contract() -> void:
	for entry in _implementations():
		var sink: Object = entry["sink"] as Object
		assert_eq(
			sink is BeatSink,
			true,
			"%s is a BeatSink, not a structural copy of one" % String(entry["name"])
		)


## `is` is not sufficient on its own, because a director holds a sink in a
## `BeatSink`-typed slot: a sink whose `handles` takes a different arity is not
## callable there, whatever `is` reports. So the declared arity is checked too.
func test_every_named_sink_overrides_both_virtuals_with_the_contract_signature() -> void:
	for entry in _implementations():
		var sink: Object = entry["sink"] as Object
		var label := String(entry["name"])
		for method_name in ["handles", "resolve"]:
			var declared: Array = []
			for method in sink.get_method_list():
				if String(method["name"]) == method_name:
					declared = method["args"] as Array
					break
			assert_eq(declared.is_empty(), false, "%s declares %s()" % [label, method_name])
			assert_eq(
				declared.size(),
				2,
				(
					"%s.%s takes (beat, context), so a director typed on the contract can call it"
					% [label, method_name]
				)
			)


## How deep [method _is_json_safe] will walk before it stops. A cap and not a
## `while`: the recursion is the point, and an unbounded one on a cyclic payload
## would be exactly the runaway the arch rule exists to refuse.
const MAX_JSON_DEPTH := 4


## Whether `value` survives a JSON round trip: a primitive, or an Array/Dictionary
## of them. That is the bar `BeatSink.resolve` is documented at, and it is a
## property of the VALUE rather than of any one key, so the quest sink may report
## `completed: []` and still pass.
func _is_json_safe(value, depth: int = 0) -> bool:
	if depth > MAX_JSON_DEPTH:
		return false
	var kind := typeof(value)
	if (
		kind == TYPE_BOOL
		or kind == TYPE_INT
		or kind == TYPE_FLOAT
		or kind == TYPE_STRING
		or kind == TYPE_STRING_NAME
	):
		return true
	if kind == TYPE_ARRAY:
		for member in value as Array:
			if not _is_json_safe(member, depth + 1):
				return false
		return true
	if kind == TYPE_DICTIONARY:
		for key in (value as Dictionary).keys():
			if typeof(key) != TYPE_STRING:
				return false
			if not _is_json_safe((value as Dictionary)[key], depth + 1):
				return false
		return true
	return false
