extends TestCase

## A destiny is the Chosen One / Revenger shape: branches inside one `group` are
## mutually exclusive, and earning one refuses every other in that group for good.
## These assert exclusivity is permanent rather than a swap, that prerequisites
## refuse an earn and record nothing when they are unmet, and that a destiny
## carries its `grants_fates` with it — in authored order, exactly once.

const OATH := &"t_oath_breaker"
const PLEDGE := &"t_blood_pledge"
const SEAL := &"t_sealed_blood"
const CHOSEN := &"t_chosen_one"
const RISE := &"t_rise_of_the_revenants"
const OATH_KEEPER := &"t_oath_keeper"
const BRANCH := &"fixture_branch"


func setup() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[
				DestinyFixtureCatalog.flat_fate(OATH, Stat.DEFENSE_PHYSICAL, 3.0),
				DestinyFixtureCatalog.flat_fate(PLEDGE, Stat.ATTACK_PHYSICAL, 2.0),
				DestinyFixtureCatalog.story_fate(SEAL),
			],
			[
				# Two branches of one group, and a grouped destiny that grants fates.
				DestinyFixtureCatalog.granting_destiny(CHOSEN, false, [OATH, PLEDGE, SEAL]),
				DestinyFixtureCatalog.granting_destiny(RISE, false, [PLEDGE]),
				# Ungrouped, so it is exclusive of nothing.
				DestinyFixtureCatalog.gated_destiny(OATH_KEEPER, [OATH], []),
			]
		)
	)


func teardown() -> void:
	DestinyFixtureCatalog.teardown()


func _hero(actor_id: StringName = &"keeper") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	DestinyApi.attach(actor)
	return actor


# --- Prerequisites ------------------------------------------------------------


func test_earning_a_destiny_whose_required_fates_are_unmet_is_refused() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, PLEDGE, "combat")
	var before := DestinyApi.state(actor)
	var ledger := DestinyApi.earn_destiny(actor, OATH_KEEPER, "story")
	assert_eq(DestinyApi.has_destiny(actor, OATH_KEEPER), false, "the destiny was not earned")
	assert_eq(ledger, before, "and nothing about the ledger changed")
	assert_eq(actor.get_module_data(DestinyState.MODULE_KEY), before, "nothing was persisted")
	# Earn the last prerequisite and the same call succeeds: a refusal is a normal
	# outcome, not a lock. It is also not a queue — the earn has to be made again
	# now that it can succeed.
	DestinyApi.earn_fate(actor, OATH, "oath")
	DestinyApi.earn_destiny(actor, OATH_KEEPER, "story")
	assert_eq(DestinyApi.has_destiny(actor, OATH_KEEPER), true, "once every fate is held")


func test_earning_a_destiny_whose_required_destinies_are_unmet_is_refused() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[DestinyFixtureCatalog.flat_fate(OATH, Stat.DEFENSE_PHYSICAL, 3.0)],
			[
				DestinyFixtureCatalog.plain_destiny(CHOSEN),
				DestinyFixtureCatalog.gated_destiny(RISE, [], [CHOSEN]),
			]
		)
	)
	var actor := _hero()
	var ledger := DestinyApi.earn_destiny(actor, RISE, "story")
	assert_eq(DestinyApi.has_destiny(actor, RISE), false, "the prerequisite is not held")
	assert_eq(ledger["destinies"] as Dictionary, {}, "so nothing was recorded")
	assert_eq(ledger["history"] as Array, [], "and no earn was announced")
	DestinyApi.earn_destiny(actor, CHOSEN, "story")
	assert_eq(DestinyApi.has_destiny(actor, CHOSEN), true, "the prerequisite is now held")
	# A refusal is not a queue: it records nothing, so the dependent is not
	# granted retroactively the moment its prerequisite lands. The same call has
	# to happen again now that it can succeed.
	assert_eq(
		DestinyApi.has_destiny(actor, RISE),
		false,
		"and the dependent was NOT granted retroactively"
	)
	DestinyApi.earn_destiny(actor, RISE, "story")
	assert_eq(DestinyApi.has_destiny(actor, RISE), true, "the same call succeeds once it is earned")


func test_a_refused_prerequisite_names_what_is_missing_and_by_who() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[DestinyFixtureCatalog.flat_fate(OATH, Stat.DEFENSE_PHYSICAL, 3.0)],
			[
				DestinyFixtureCatalog.plain_destiny(CHOSEN),
				DestinyFixtureCatalog.plain_destiny(RISE),
				DestinyFixtureCatalog.gated_destiny(&"t_apostle", [OATH], [CHOSEN]),
			]
		)
	)
	var actor := _hero()
	var unmet := DestinyGate.unmet_prerequisites(
		DestinyApi.state(actor), FateCatalog.instance().destiny_definition(&"t_apostle")
	)
	assert_eq(unmet.size(), 2, "both prerequisites are named")
	assert_eq(String(unmet[0]["kind"]), "destiny", "the missing destiny first")
	assert_eq(String(unmet[0]["id"]), String(CHOSEN), "by id")
	assert_eq(bool(unmet[0]["required"]), true, "and as required")
	assert_eq(String(unmet[0]["label"]), "Requires the destiny 't_chosen_one'", "with a label")
	assert_eq(String(unmet[1]["kind"]), "fate", "then the missing fate")
	assert_eq(String(unmet[1]["label"]), "Requires the fate 't_oath_breaker'", "with its label")
	assert_eq(
		DestinyGate.unmet_prerequisites(DestinyApi.state(actor), null),
		[],
		"no definition, nothing unmet"
	)
	DestinyApi.earn_destiny(actor, CHOSEN, "story")
	DestinyApi.earn_fate(actor, OATH, "oath")
	DestinyApi.earn_destiny(actor, &"t_apostle", "story")
	var def := FateCatalog.instance().destiny_definition(&"t_apostle")
	assert_eq(
		DestinyGate.unmet_prerequisites(DestinyApi.state(actor), def),
		[],
		"nothing outstanding once held"
	)


# --- Group exclusivity --------------------------------------------------------


func test_a_second_destiny_in_the_same_group_is_refused_once_one_is_held() -> void:
	var actor := _hero()
	var earned := DestinyApi.earn_destiny(actor, CHOSEN, "story")["destinies"] as Dictionary
	assert_eq(earned.size(), 1, "the first is earned")
	var ledger := DestinyApi.earn_destiny(actor, RISE, "story")
	assert_eq(DestinyApi.has_destiny(actor, RISE), false, "the second is refused")
	assert_eq(DestinyApi.has_destiny(actor, CHOSEN), true, "and the first is untouched")
	assert_eq(DestinyApi.destinies(actor), [CHOSEN], "the ledger holds one branch")
	var branch = (ledger["destinies"] as Dictionary).get(String(CHOSEN), null)
	assert_eq(branch is Dictionary, true, "the held branch still has a ledger entry")
	if branch is Dictionary:
		assert_eq(
			String((branch as Dictionary).get("bearing", "")),
			"You are bound to t_chosen_one.",
			"and it still carries its authored bearing"
		)


func test_exclusivity_is_permanent_rather_than_a_swap() -> void:
	var actor := _hero()
	DestinyApi.earn_destiny(actor, CHOSEN, "story")
	var before := DestinyApi.state(actor)
	var projection_before := DestinyProjection.contribution(actor, Stat.ATTACK_PHYSICAL)
	# Asking for the other branch, again and again, must not trade one for the
	# other: there is no swap path, so the first choice stands for good.
	for attempt in 3:
		DestinyApi.earn_destiny(actor, RISE, "story")
		assert_eq(DestinyApi.destinies(actor), [CHOSEN], "attempt %d changed nothing" % attempt)
	assert_eq(DestinyApi.state(actor), before, "the ledger is byte-for-byte what it was")
	assert_eq(
		DestinyProjection.contribution(actor, Stat.ATTACK_PHYSICAL),
		projection_before,
		"and the projection the first branch paid for is still in place"
	)
	# A restore cannot reopen the branch either: the ledger already holds one, so
	# re-attaching never re-runs the earn that would have swapped it.
	var restored := Actor.from_dict(actor.to_dict())
	DestinyApi.attach(restored)
	DestinyApi.earn_destiny(restored, RISE, "story")
	assert_eq(DestinyApi.destinies(restored), [CHOSEN], "a restored actor keeps its branch")


func test_a_destiny_outside_every_group_is_exclusive_of_nothing() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH, "oath")
	var earned := DestinyApi.earn_destiny(actor, OATH_KEEPER, "story")["destinies"] as Dictionary
	assert_eq(earned.size(), 1, "an empty group is not all destinies")
	DestinyApi.earn_destiny(actor, CHOSEN, "story")
	DestinyApi.earn_destiny(actor, RISE, "story")
	# Two destinies are held: the branch, and the ungrouped one. The returned list
	# is in canonical order, so membership is what matters, not installation order.
	var held := DestinyApi.destinies(actor)
	assert_eq(held.size(), 2, "the ungrouped destiny coexists with one branch")
	assert_eq(held.has(OATH_KEEPER), true, "the ungrouped one is held")
	assert_eq(held.has(CHOSEN), true, "alongside the branch")
	assert_eq(held.has(RISE), false, "and never the refused branch")
	# A refutation through the rule itself, not the facade: an empty group is not
	# a wildcard, so an ungrouped destiny conflicts with nothing.
	var ungrouped := FateCatalog.instance().destiny_definition(OATH_KEEPER)
	assert_eq(
		ungrouped.conflicts_with(FateCatalog.instance().destiny_definition(CHOSEN)),
		false,
		"it conflicts with nothing"
	)
	assert_eq(
		FateCatalog.instance().destiny_definition(CHOSEN).conflicts_with(ungrouped),
		false,
		"and is not conflicted by it"
	)


func test_the_exclusivity_rule_reads_the_catalog_and_not_the_order_of_a_list() -> void:
	var actor := _hero()
	var chosen := FateCatalog.instance().destiny_definition(CHOSEN)
	var rise := FateCatalog.instance().destiny_definition(RISE)
	assert_eq(chosen.conflicts_with(rise), true, "two members of one group conflict")
	assert_eq(rise.conflicts_with(chosen), true, "in both directions")
	assert_eq(chosen.conflicts_with(chosen), false, "a destiny never conflicts with itself")
	# A group is resolved through the catalog by id, and the members come back in
	# the catalog's canonical order rather than in the order they were installed,
	# so the exclusivity rule cannot shift when content is reordered on disk.
	var group := FateCatalog.instance().destinies_in_group(BRANCH)
	assert_eq(group.size(), 2, "the branch group has both members")
	assert_eq(group.has(CHOSEN), true, "including the chosen one")
	assert_eq(group.has(RISE), true, "and the rise")
	assert_eq(group, FateCatalog.instance().destinies_in_group(BRANCH), "and the answer is stable")
	assert_eq(
		FateCatalog.instance().destinies_in_group(&""),
		[],
		"an empty group has no members: it means 'never exclusive'"
	)
	assert_eq(
		FateCatalog.instance().destinies_in_group(&"no_such_group"),
		[],
		"and a group nothing ships is empty, not every destiny"
	)
	# The rule lives in one place, and the facade calls it rather than repeating it.
	assert_eq(
		DestinyGate.earnable(DestinyApi.state(actor), chosen), true, "the first branch is earnable"
	)
	DestinyApi.earn_destiny(actor, CHOSEN, "story")
	assert_eq(DestinyGate.earnable(DestinyApi.state(actor), rise), false, "the second is not")
	assert_eq(
		DestinyGate.earnable(DestinyApi.state(actor), chosen), true, "and the first stays earnable"
	)
	assert_eq(
		DestinyGate.earnable(DestinyApi.state(actor), null),
		false,
		"no definition is never earnable"
	)


# --- A destiny carries its consequence with it --------------------------------


func test_grants_fates_are_appended_in_authored_order_and_are_themselves_exactly_once() -> void:
	var actor := _hero()
	# One of the three is already held, so only the missing two are appended.
	DestinyApi.earn_fate(actor, PLEDGE, "combat")
	var ledger := DestinyApi.earn_destiny(actor, CHOSEN, "story")
	var sequences: Array = []
	var fates := ledger["fates"] as Dictionary
	var unsequenced: Array = []
	for fate_id in DestinyApi.fates(actor):
		# Fetched through `.get()` with the shape checked first: a typed local
		# assigned an unvalidated subscript ABORTS the function, and the runner
		# calls each test with `suite.call(name)`, so an aborted test reports green
		# with everything after the abort silently skipped.
		var entry = fates.get(String(fate_id), null)
		if entry is Dictionary and (entry as Dictionary).has("sequence"):
			sequences.append(
				{"id": String(fate_id), "sequence": int((entry as Dictionary)["sequence"])}
			)
		else:
			unsequenced.append(String(fate_id))
	assert_eq(unsequenced, [], "every held fate carries a sequenced ledger entry")
	sequences.sort_custom(func(a, b): return int(a["sequence"]) < int(b["sequence"]))
	assert_eq(
		_earned_order(sequences),
		[String(PLEDGE), String(OATH), String(SEAL)],
		"the two missing fates are appended in the order they were authored"
	)
	# A fate the destiny granted is exactly as permanent as one earned directly,
	# and the ledger records where it came from.
	assert_eq(
		String(_granted_source(fates, OATH)),
		"destiny:t_chosen_one",
		"a granted fate names the destiny that carried it"
	)
	DestinyApi.earn_destiny(actor, CHOSEN, "story")
	assert_eq(
		(DestinyApi.state(actor)["fates"] as Dictionary).size(),
		3,
		"no granted fate was appended twice"
	)


func test_everything_the_ledger_records_while_earning_a_destiny_is_persisted_together() -> void:
	var actor := _hero()
	DestinyApi.earn_destiny(actor, CHOSEN, "story")
	var stored: Dictionary = actor.get_module_data(DestinyState.MODULE_KEY)
	# The three effects are one operation: a half-applied earn — stats without a
	# ledger, a ledger without stats — is the one state a player cannot recover.
	assert_eq(DestinyApi.state(actor), stored, "the ledger is what is persisted")
	assert_eq(DestinyApi.has_destiny(actor, CHOSEN), true, "the destiny is held")
	assert_eq(DestinyApi.fates(actor).size(), 3, "its fates came with it")
	# A magnitude and a rate stay separate channels: the granted fates paid 3.0
	# flat and 2.0 flat, each with a tenth of itself as a percent.
	assert_eq(
		DestinyProjection.contribution(actor, Stat.DEFENSE_PHYSICAL),
		{"flat": 3.0, "percent": 0.3},
		"and its numbers landed"
	)
	assert_eq(
		DestinyProjection.contribution(actor, Stat.ATTACK_PHYSICAL),
		{"flat": 2.0, "percent": 0.2},
		"both flat bonuses, once each"
	)
	assert_eq(actor.traits.has(DestinyState.trait_for(CHOSEN)), true, "the trait mirror is in step")
	assert_eq(actor.traits.has(DestinyState.trait_for(SEAL)), true, "for the story fate too")
	assert_eq(_history_ids(stored)[0], String(CHOSEN), "the destiny is the first thing recorded")
	assert_eq(_history_ids(stored).size(), 4, "one record for the destiny and three for its fates")


func test_earning_an_unknown_destiny_is_refused_and_records_nothing() -> void:
	var actor := _hero()
	var before := DestinyApi.state(actor)
	var ledger := DestinyApi.earn_destiny(actor, &"t_no_such_destiny", "story")
	assert_eq(ledger, before, "a destiny the catalog does not define is not recorded")
	assert_eq(DestinyApi.destinies(actor), [], "nothing is held")
	assert_eq(_destiny_modifiers(actor), 0, "and nothing was projected")


## An alias is declared ON a destiny and names an id story content may ask
## about INSTEAD of that destiny. Resolution is therefore backward from the id a
## gate asks: `has_destiny(the_marked)` is true when either `the_marked` itself is
## held, OR one of the aliases declared on `the_marked` is held. The shipped
## content reads this way — `the_one_who_returned` declares the alias
## `the_returned` — so this is the direction that matters.
func test_has_destiny_answers_true_for_an_authored_gate_alias() -> void:
	const MARKED := &"t_the_marked_one"
	const HEIR := &"t_heir_of_the_revenants"
	# `the_marked` is the queried destiny and declares `heir` as one of its
	# aliases; `the_marked` is the only one that can actually be earned.
	(
		DestinyFixtureCatalog
		. install(
			[],
			[
				DestinyFixtureCatalog.aliased_destiny(MARKED, [HEIR]),
				DestinyFixtureCatalog.plain_destiny(HEIR),
			]
		)
	)
	var actor := _hero()
	# Nothing held yet: neither the queried id nor any of its aliases.
	for id in [MARKED, HEIR]:
		assert_eq(DestinyApi.has_destiny(actor, id), false, "'%s' is not held" % id)
		assert_eq(
			bool(DestinyGate.evaluate(actor, {"verb": &"has_destiny", "id": String(id)})["ok"]),
			false,
			"and a gate authored against '%s' is closed" % id
		)
	# Earning the ALIAS satisfies a gate authored against the destiny that named
	# it: the alias is as good as the destiny it stands in for.
	DestinyApi.earn_destiny(actor, HEIR, "story")
	assert_eq(DestinyApi.has_destiny(actor, MARKED), true, "the declaring destiny answers true")
	assert_eq(
		bool(DestinyGate.evaluate(actor, {"verb": &"has_destiny", "id": String(MARKED)})["ok"]),
		true,
		"and a gate authored against the declaring destiny opens"
	)
	assert_eq(DestinyApi.has_destiny(actor, HEIR), true, "the earned alias is still held")
	# Earning the declaring destiny is the mirror case: the id itself is held.
	var other := _hero(&"second")
	DestinyApi.earn_destiny(other, MARKED, "story")
	assert_eq(DestinyApi.has_destiny(other, MARKED), true, "the destiny is held directly")
	# An unrelated id — one with no definition and no alias — never resolves.
	for actor_under_test in [actor, other]:
		assert_eq(
			DestinyApi.has_destiny(actor_under_test, &"t_unrelated"),
			false,
			"an unrelated id still does not"
		)
	# The catalog is where the full set of answerable ids lives, so a gate panel
	# can list every id that opens a given destiny without re-deriving the rule.
	var gate_ids := FateCatalog.instance().destiny_gate_ids(MARKED)
	assert_eq(gate_ids.size(), 2, "the declaring destiny plus its one alias")
	assert_eq(gate_ids.has(MARKED), true, "itself is answerable")
	assert_eq(gate_ids.has(HEIR), true, "and so is the alias it declared")
	assert_eq(
		FateCatalog.instance().destiny_gate_ids(&"t_no_such_destiny"),
		[],
		"an unknown destiny names no gate ids"
	)


## The fate ids in the order they were earned.
func _earned_order(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		out.append(String(entry["id"]))
	return out


## The `source` a fate entry records, or "" when the entry is absent or
## unreadable — so a missing entry becomes a failed assertion naming the id rather
## than an abort of the test that was checking everything else.
func _granted_source(fates: Dictionary, fate_id: StringName) -> String:
	var entry = fates.get(String(fate_id), null)
	if entry is Dictionary:
		return String((entry as Dictionary).get("source", ""))
	assert_eq(entry is Dictionary, true, "the ledger holds an entry for '%s'" % fate_id)
	return ""


## The ids the history trail records, in order.
func _history_ids(ledger: Dictionary) -> Array:
	var out: Array = []
	for record in ledger["history"] as Array:
		out.append(String(record["id"]))
	return out


## How many stat modifiers this module currently owns.
func _destiny_modifiers(actor: Actor) -> int:
	return DestinyProjection.modifier_count(actor)
