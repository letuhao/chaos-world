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
	for property in WorldBeat.get_property_list():
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
		assert_eq(typeof(restored.to_dict()[key]), TYPE_STRING, "and every value")


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
		assert_eq(typeof(outcome[key]), TYPE_STRING, "and the outcome is primitives-only")
		assert_eq(outcome.keys().has("amount"), false, "with no effect payload attached")
