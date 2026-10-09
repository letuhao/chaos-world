extends TestCase

## The ONE claim-envelope normalizer, contract-tested (ADR 0922, ADR 0941).
##
## These are contract tests: `sect`, `clan`, `nation` and any modder's organization
## all read their save slot through `InstitutionEnvelope.normalize`, so a divergence
## here is a duplicated corruption policy discovered late — the ADR 0066 failure mode
## in the place it was measured (three `normalize()` bodies that disagreed).

const SHAPE := {
	"doctrine": {"kind": "text", "default": ""},
	"fit": {"kind": "lines", "cap": 100},
	"founder_id": {"kind": "text", "default": ""},
	"applied_standing": {"kind": "count", "default": 0},
	"granted_percent": {"kind": "ratio"},
	"history": {"kind": "list", "limit": 3},
	"claims": {"kind": "id_map", "known": "positions"},
}


func _shape() -> Dictionary:
	# `Callable()` cannot be built in a `const`, so the roster's row normalizer is
	# bound here. It mirrors `SectState`'s roster row: a list of ids under a key.
	var shape := SHAPE.duplicate(true)
	shape["roster"] = {"kind": "map", "row": Callable(self, "_roster_row"), "limit": 4}
	return shape


func _roster_row(entry: Dictionary, _out: Dictionary) -> Dictionary:
	if not (entry is Dictionary):
		return {}
	return {"ids": entry.get("ids", [])}


## ## The three states, kept apart
##
## `{}` (does not exist), a present record (exists), and a refusal are three different
## answers (ADR 0083), and a normalizer that collapsed the first two into one default
## is the defect this file exists to catch.
func test_an_absent_slot_reads_as_the_empty_envelope() -> void:
	var empty := InstitutionEnvelope.normalize({}, {}, _shape())
	assert_eq(empty["institution"], "", "no institution is named")
	assert_eq(empty["position"], "", "and no position")
	assert_eq(empty["standing"], 0, "and no standing")
	assert_eq(
	empty["standing_cap"],
	InstitutionClaim.DEFAULT_STANDING_CAP,
	"the cap is the published default, never a literal"
	)
	assert_eq(empty["version"], InstitutionEnvelope.LEDGER_VERSION, "stamped at the one version")


## A slot holding something that is not a dictionary at all — a hand-edited save, or a
## foreign payload — reads as the empty envelope rather than raising out of an attach.
func test_a_foreign_payload_reads_as_the_empty_envelope() -> void:
	for payload in ["a string", 42, [1, 2], null]:
		var out := InstitutionEnvelope.normalize(payload, {}, _shape())
		assert_eq(out["institution"], "", "a foreign payload names no institution")


## **Strict where the claim is unreadable.** The id fields and the standing pair ARE
## the claim, so a wrong-typed one discards the WHOLE record rather than inventing a
## membership and a standing out of bytes.
func test_a_wrong_typed_claim_field_discards_the_whole_record() -> void:
	for key in ["institution", "position", "kind"]:
		var payload := {"institution": "jade_court", "standing": 40, "standing_cap": 120}
		payload[key] = 42
		var out := InstitutionEnvelope.normalize(payload, {}, _shape())
		assert_eq(out["institution"], "", "a wrong-typed '%s' discards the record" % key)
	for key in ["standing", "standing_cap"]:
		var payload := {"institution": "jade_court", "standing": 40, "standing_cap": 120}
		payload[key] = "lots"
		var out := InstitutionEnvelope.normalize(payload, {}, _shape())
		assert_eq(out["institution"], "", "a wrong-typed '%s' discards the record" % key)


## A `bool` is not a count: `int(true)` would disguise a corrupt field as `1`.
func test_a_bool_is_not_a_count() -> void:
	var out := InstitutionEnvelope.normalize(
	{"institution": "jade_court", "standing": true}, {}, _shape()
	)
	assert_eq(out["institution"], "", "a bool standing is corruption, not a one")


## **Lenient where only a neighbour is unreadable.** An unreadable map is one unusable
## line beside good fields, so it drops that line and keeps the earned standing —
## losing standing because an unrelated line went bad is the worse failure.
func test_an_unreadable_map_keeps_the_earned_standing() -> void:
	var out := InstitutionEnvelope.normalize(
	{"institution": "jade_court", "standing": 40, "standing_cap": 120, "fit": [1, 2]}, {}, _shape()
	)
	assert_eq(out["institution"], "jade_court", "the membership survives")
	assert_eq(out["standing"], 40, "and the standing it earned")
	assert_eq(out["fit"], {}, "the unreadable map drops to empty")


## The envelope clamps standing into `[0, cap]` and repairs a cap of zero or less to at
## least one: a cap that cannot be computed reports a ratio of zero and reads as an
## institution nobody respects.
func test_the_cap_is_repaired_and_the_standing_clamped() -> void:
	var out := InstitutionEnvelope.normalize(
	{"institution": "jade_court", "standing": 999, "standing_cap": 0}, {}, _shape()
	)
	assert_eq(out["standing_cap"], 1, "a zero cap is repaired to one")
	assert_eq(out["standing"], 1, "and the standing clamps into it")
	var over := InstitutionEnvelope.normalize(
	{"institution": "jade_court", "standing": -5, "standing_cap": 100}, {}, _shape()
	)
	assert_eq(over["standing"], 0, "a negative standing clamps to zero")


## A position is CONTENT. With a filter supplied, a claim naming a seat this build does
## not author is an unaffiliated claim — and the standing survives regardless, because
## a member who earned standing did so even if the seat is gone.
func test_an_unshipped_position_is_dropped_and_the_standing_kept() -> void:
	var out := InstitutionEnvelope.normalize(
	{"institution": "jade_court", "position": "ghost_elder", "standing": 40},
	{"position": {"elder": true}},
	_shape()
	)
	assert_eq(out["position"], "", "the unshipped seat is dropped")
	assert_eq(out["standing"], 40, "the earned standing survives it")
	var kept := InstitutionEnvelope.normalize(
	{"institution": "jade_court", "position": "elder", "standing": 40},
	{"position": {"elder": true}},
	_shape()
	)
	assert_eq(kept["position"], "elder", "a shipped seat is kept")
	var unanswered := InstitutionEnvelope.normalize(
	{"institution": "jade_court", "position": "anything"}, {}, _shape()
	)
	assert_eq(unanswered["position"], "anything", "an EMPTY filter is unanswered, not a denial")


## Every shape kind reads what it says it reads. One case per kind, so a new row added
## to the vocabulary without a reader fails here rather than at a save load.
func test_every_shape_kind_reads_its_own_value() -> void:
	var out := InstitutionEnvelope.normalize(
	{
			"institution": "jade_court",
			"doctrine": "iron_vine",
			"fit": {"iron_vine": 30, "still_water": 0, "bad": "x"},
			"founder_id": "hero_1",
			"applied_standing": 12,
			"granted_percent": {"poise": 0.04, "will": "bad"},
			"roster": {"elder": {"ids": ["a", "b"]}},
			"claims": {"river_march": "hero_1", "bad": 7},
			"history": [{"verb": "join"}, {"verb": "promote"}, {"verb": "teach"}, {"verb": "x"}],
	},
	{"positions": {"river_march": true}},
	_shape()
	)
	assert_eq(out["doctrine"], "iron_vine", "text reads its value")
	assert_eq(out["fit"], {"iron_vine": 30}, "lines keeps positives and drops a non-number")
	assert_eq(out["founder_id"], "hero_1", "a second text field reads too")
	assert_eq(out["applied_standing"], 12, "count reads its number")
	assert_eq(out["granted_percent"], {"poise": 0.04}, "ratio keeps numbers, drops the rest")
	assert_eq(out["roster"], {"elder": {"ids": ["a", "b"]}}, "map runs the row normalizer")
	assert_eq(out["claims"], {"river_march": "hero_1"}, "id_map filters known content")
	assert_eq((out["history"] as Array).size(), 3, "list honours its limit")


## `count` clamps at its authored cap when one is given.
func test_a_count_clamps_at_its_cap() -> void:
	var shape := {"stage": {"kind": "count", "cap": 8}}
	assert_eq(
	InstitutionEnvelope.normalize({"institution": "a", "stage": 50}, {}, shape)["stage"],
	8,
	"clamped to the authored cap"
	)
	assert_eq(
	InstitutionEnvelope.normalize({"institution": "a", "stage": 3}, {}, shape)["stage"],
	3,
	"and left alone below it"
	)


## A shape row naming a kind the vocabulary does not hold REFUSES BY NAME. A caller's
## invented shape is a shape nothing reads, and skipping it silently is how a field
## stops being normalized with nothing said (ADR 0184's unknown-family policy).
func test_an_unknown_shape_kind_refuses_by_name() -> void:
	var out := InstitutionEnvelope.normalize(
	{"institution": "a"}, {}, {"mystery": {"kind": "not_a_kind"}}
	)
	assert_eq(out.get("ok"), false, "the record refuses")
	assert_eq(out.get("reason"), InstitutionEnvelope.R_UNKNOWN_FIELD_KIND, "naming the shape fault")


## The envelope a writer persists is checked for save safety at the place the payload
## is built. A `StringName` KEY is the defect no checker can see until a load fails in
## front of the player, so it is caught here instead.
func test_a_save_unsafe_envelope_is_refused() -> void:
	var safe := InstitutionEnvelope.normalize({"institution": "jade_court"}, {}, _shape())
	assert_eq(
	InstitutionEnvelope.save_ready(safe).get("ok"), true, "a primitives-only envelope passes"
	)
	var unsafe := {"institution": "jade_court", &"sn_key": 1}
	assert_eq(
	InstitutionEnvelope.save_ready(unsafe).get("ok"),
	false,
	"a StringName key is caught where the payload is built"
	)
