extends TestCase

## ADR 0047's symmetry, extended by ADR 0085 to every tier and made STRUCTURAL:
## a stance is **one canonical row per unordered pair**, keyed by the two ids ordered
## lexicographically.
##
## The word structural is the load-bearing one. A rule that merely forbids a reversed
## write has one writer to police; a rule that makes the reversed key impossible to
## express has none. These cases are written to catch the difference: they do not
## assert that symmetry is maintained, they assert that a symmetric view CANNOT be
## produced any other way, and that the ledger normalizer folds a reversed key into
## the canonical one rather than keeping both.

const MARCH := &"march_of_the_nine_provinces"
const COURT := &"court_of_the_star"
## An actor id, so the self-pair refusal is testable too.
const SELF := &"polity_a"


func setup() -> void:
	# The world store seam is PROCESS state: a suite that mounted the app leaves a
	# real store installed (InstitutionBoot.install wires it), and this suite's
	# cases measure the actor-side ledger with no world leg. Establish that.
	NationApi.set_world_store(null)


func _actor(nation_id: StringName = MARCH) -> Actor:
	var actor := Actor.new(&"polity_a", {Stat.PHYSIQUE: 10.0})
	NationApi.attach(actor)
	NationApi.found(actor, nation_id, "polity_a")
	return actor


func test_the_pair_key_is_identical_under_a_swap() -> void:
	var forward := NationState.pair_key(SELF, COURT)
	var swapped := NationState.pair_key(COURT, SELF)
	assert_eq(forward, swapped, "the canonical key does not depend on argument order")
	# `String.split` hands back a PackedStringArray, which `assert_eq` cannot compare
	# against an Array literal; the pair is read back through the module's own split,
	# which is the production that a caller would use anyway.
	assert_eq(
		NationState.split_pair_key(forward),
		["court_of_the_star", "polity_a"],
		"the two ids are ordered lexicographically inside the key"
	)


func test_the_pair_key_splits_back_into_the_two_ids() -> void:
	var key := NationState.pair_key(SELF, COURT)
	assert_eq(
		NationState.split_pair_key(key),
		["court_of_the_star", "polity_a"],
		"the join is unambiguous and always splits back apart"
	)


func test_a_stance_read_with_the_ids_swapped_returns_the_identical_dictionary() -> void:
	var actor := _actor()
	var written := NationApi.set_stance(actor, COURT, &"allied")
	assert_eq(bool(written.get("ok", false)), true, "the stance was written: %s" % written)
	var key := NationState.pair_key(SELF, COURT)
	var forward: Dictionary = NationApi.state(actor)["stances"][key]
	var swapped: Dictionary = NationApi.state(actor)["stances"][NationState.pair_key(COURT, SELF)]
	assert_eq(forward, swapped, "the same row answers both orders")
	# And through `summary()`, which is what a screen actually reads.
	var view: Dictionary = NationApi.summary(actor)
	assert_eq(
		view["stances"][key],
		view["stances"][NationState.pair_key(COURT, SELF)],
		"the published view is symmetric too"
	)


func test_writing_a_stance_twice_updates_the_one_row_rather_than_adding_a_second() -> void:
	var actor := _actor()
	NationApi.set_stance(actor, COURT, &"rival")
	NationApi.set_stance(actor, COURT, &"truce")
	var stances: Dictionary = NationApi.state(actor)["stances"]
	assert_eq(stances.size(), 1, "one pair, one row")
	assert_eq(
		String(stances[NationState.pair_key(SELF, COURT)]["verb"]),
		"truce",
		"the later verb replaced the earlier one"
	)


func test_a_payload_carrying_both_orders_folds_into_the_canonical_row() -> void:
	# A hand-edited save, or a bug from an older build, can arrive carrying the same
	# pair twice. Keeping both would be a one-sided opinion by another name, so the
	# reversed key is folded in and the loser is never persisted.
	#
	# **The two orders are spelled out by hand, not asked of `pair_key`.**
	# `pair_key` canonicalizes, so `pair_key(COURT, SELF)` returns the SAME string as
	# `pair_key(SELF, COURT)` — a Dictionary literal holding both collapses to one
	# entry before `normalize` ever sees it, and the case would pass while testing
	# nothing. The ADR 0047 symmetry claim is that a NON-canonical key can reach disk,
	# so the fixture has to manufacture one to be worth anything.
	assert_ne(String(SELF), String(COURT), "the two ids of the pair differ")
	# `march_...` and `court_...` were chosen because they sort in OPPOSITE orders to
	# the way they are written here, so `MARCH|COURT` really is the non-canonical
	# spelling of `COURT|MARCH`. That is what makes the case worth having: `pair_key`
	# canonicalizes, so asking it for "the other order" hands back the canonical key,
	# the Dictionary literal below collapses to one entry before `normalize` ever
	# sees it, and the case would pass while proving nothing. Both spellings are
	# written out by hand, and the input size is asserted so it cannot go vacuous.
	var canonical := NationState.pair_key(MARCH, COURT)
	var reversed_key := String(MARCH) + NationState.PAIR_SEPARATOR + String(COURT)
	assert_ne(reversed_key, canonical, "the reversed spelling is genuinely not canonical")
	var payload := {
		"stances":
		{
			canonical: {"verb": "allied", "other_id": String(COURT), "sequence": 1},
			reversed_key: {"verb": "war", "other_id": String(MARCH), "sequence": 2},
		}
	}
	assert_eq(
		(payload["stances"] as Dictionary).size(),
		2,
		"the payload really carries both orders, or the case proves nothing"
	)
	var out := NationState.normalize(payload)
	assert_eq((out["stances"] as Dictionary).size(), 1, "and normalize folds them to one")
	assert_eq((out["stances"] as Dictionary).has(canonical), true, "stored under the canonical key")
	assert_eq(
		(out["stances"] as Dictionary).has(reversed_key), false, "and never under the reversed one"
	)


func test_a_pair_with_an_empty_or_malformed_key_is_dropped_not_guessed() -> void:
	var payload := {
		"stances":
		{
			"": {"verb": "allied", "other_id": "", "sequence": 1},
			"no_separator_here": {"verb": "war", "other_id": "", "sequence": 2},
			"polity_a|polity_a": {"verb": "war", "other_id": "", "sequence": 3},
		}
	}
	var out := NationState.normalize(payload)
	assert_eq(
		(out["stances"] as Dictionary).size(),
		0,
		"an unreadable or self-paired key is dropped rather than read as a stance"
	)


func test_a_stand_off_declares_the_one_canonical_war_row_for_its_pair() -> void:
	# `war` is reachable only through the declaration verb (ADR 0085), and declaring
	# writes exactly one `war` row for the pair — the same key any other verb would
	# use. So a declaration cannot leave a second, one-sided war behind.
	var actor := _actor()
	var declared := NationApi.declare_war(
		actor,
		COURT,
		&"river_march",
		{"mode": "contest", "transfer": "ownership", "standing": {String(SELF): 10}}
	)
	assert_eq(bool(declared.get("ok", false)), true, "the standoff was declared: %s" % declared)
	var stances: Dictionary = NationApi.state(actor)["stances"]
	assert_eq(stances.size(), 1, "one pair, one row")
	var key := NationState.pair_key(SELF, COURT)
	assert_eq(String(stances[key]["verb"]), "war", "and it is the `war` verb")


func test_a_self_pair_is_refused_rather_than_written_as_a_stance() -> void:
	var actor := _actor()
	var stance := NationApi.set_stance(actor, SELF, &"allied")
	assert_eq(bool(stance.get("ok", false)), true, "a stance to yourself is written, not refused")
	# A self pair has no lexicographic ORDER to it, so the canonical key collapses
	# both orders into one row that cannot express a two-sided opinion. It is
	# therefore refused by `declare_war`, which is the verb that would need two sides.
	var declared := NationApi.declare_war(
		actor, SELF, &"river_march", {"mode": "contest", "transfer": "ownership"}
	)
	assert_eq(bool(declared.get("ok", false)), false, "a standoff against yourself is refused")
	assert_eq(String(declared.get("reason", "")), "unknown_nation", "with a named reason")


func test_the_stance_verb_set_is_closed_and_an_unknown_one_names_itself() -> void:
	var actor := _actor()
	var closed: Array[StringName] = [&"rival", &"neutral", &"allied", &"truce", &"embargo", &"war"]
	for verb in closed:
		assert_eq(NationState.is_verb(String(verb)), true, "'%s' is in the closed set" % verb)
	# Anything outside it refuses, and the refusal NAMES the offending value rather
	# than defaulting to neutral — a stance nobody can read must fail loudly.
	var refused := NationApi.set_stance(actor, COURT, &"hostile")
	assert_eq(bool(refused.get("ok", false)), false, "'hostile' is not in the closed set")
	assert_eq(String(refused.get("reason", "")), "unknown_verb", "refused as unknown_verb")
	assert_eq(
		String(refused.get("verb", "")),
		"hostile",
		"and the refusal names the verb that could not be read"
	)


func test_war_is_refused_outside_the_declaration_verb() -> void:
	var actor := _actor()
	var refused := NationApi.set_stance(actor, COURT, &"war")
	assert_eq(bool(refused.get("ok", false)), false, "`war` is refused by set_stance")
	assert_eq(String(refused.get("reason", "")), "war_requires_a_prize", "with the named reason")
	assert_eq(
		(NationApi.state(actor)["stances"] as Dictionary).size(), 0, "and the refusal wrote nothing"
	)
