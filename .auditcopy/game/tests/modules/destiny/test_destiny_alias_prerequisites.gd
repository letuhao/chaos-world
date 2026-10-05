extends TestCase

## **An alias prerequisite is satisfiable.** `DestinyGate.holds_destiny()` resolved a
## `gate_aliases` entry in both directions, and only the `has_destiny` verb asked it.
## `earnable()` and `unmet_prerequisites()` — the two that decide whether a destiny
## may be earned at all, and the two a panel reads to explain why it has not — asked
## `DestinyState.has_destiny`, which is a raw key lookup and answers "is this exact
## string a key".
##
## That made `requires_destinies = [&"the_returned"]` — the one pattern
## [member DestinyDef.gate_aliases] exists to permit — a prerequisite that could
## never be satisfied by anything, including earning the destiny that declares it.
## The docstring said "story can be authored before the destiny it will answer for
## exists", and the two prerequisites that could have honoured that were reading a
## different function from the one the docstring describes.
##
## These assert the RESOLUTION, not the prose: an alias is one answer with the
## destiny that declares it, in every read path that asks about holding, and the two
## paths that decide earnability agree with the gate verb that already agreed.

## The declaring destiny: it exists, and it ships the alias `the_returned`.
const RETURNED := &"t_the_one_who_returned"
## The alias — a pure narrative id. **No `.tres` of its own exists**, which is the
## whole point of an alias and the reason the raw key lookup could never find it.
const ALIAS := &"t_the_returned"
## A destiny that requires the ALIAS, not the definition.
const GATED := &"t_the_returned_instrument"
## A sibling the actor does not hold, so "the gate opened" cannot be confused with
## "nothing was ever required".
const UNHELD := &"t_the_one_who_stayed"
## A second alias on the same definition, so a multi-alias declaration is covered and
## not just the single-entry shape the shipped content happens to use.
const SECOND_ALIAS := &"t_come_back_again"


func setup() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[],
			[
				DestinyFixtureCatalog.aliased_destiny(RETURNED, [ALIAS, SECOND_ALIAS]),
				DestinyFixtureCatalog.gated_destiny(GATED, [], [ALIAS]),
				DestinyFixtureCatalog.plain_destiny(UNHELD),
			]
		)
	)


func teardown() -> void:
	DestinyFixtureCatalog.teardown()


func _hero(id: StringName = &"hero") -> Actor:
	var actor := Actor.new(id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	DestinyApi.attach(actor)
	return actor


func _gated() -> DestinyDef:
	var def := FateCatalog.instance().destiny_definition(GATED)
	assert_ne(def, null, "the gated fixture destiny is in the catalog")
	return def


# --- The defect: the alias prerequisite was permanently unmet ------------------


## The claim the module's own docstring makes, executed.
##
## `earnable()` is what `DestinyApi.earn_destiny` asks before it writes, so a
## prerequisite `earnable()` cannot see is a destiny that can never be earned at
## all — through the facade, not merely through a read verb.
func test_a_prerequisite_naming_an_alias_is_satisfied_by_earning_the_declaring_destiny() -> void:
	var actor := _hero()
	# Before: nothing held, so the prerequisite IS outstanding and both readers say so.
	assert_eq(
		DestinyApi.has_destiny(actor, ALIAS),
		false,
		"nothing is held yet, so the alias resolves false through the one resolver"
	)
	assert_eq(
		DestinyGate.earnable(DestinyApi.state(actor), _gated()),
		false,
		"and the gated destiny is not earnable"
	)

	# The act under test: earn the DEFINITION, which declares the alias. The ledger
	# gains the key `t_the_one_who_returned` and NOT `t_the_returned` — so a raw key
	# lookup against the authored prerequisite misses by construction, which is the
	# defect this file exists to pin shut.
	DestinyApi.earn_destiny(actor, RETURNED, "story")
	assert_eq(
		DestinyApi.destinies(actor),
		[RETURNED] as Array[StringName],
		"the ledger records the definition only; the alias is never a key in it"
	)

	# The alias and the declaring destiny are ONE answer.
	assert_eq(DestinyApi.has_destiny(actor, ALIAS), true, "the alias resolves true")
	assert_eq(DestinyApi.has_destiny(actor, RETURNED), true, "and so does the definition")
	assert_eq(
		DestinyGate.holds_destiny(DestinyApi.state(actor), ALIAS),
		true,
		"through the resolver itself, on a bare ledger and with no actor"
	)

	# **The assertion that was red before the fix:** the alias prerequisite is met,
	# so the gated destiny may now be earned. This is the story the feature promises.
	assert_eq(
		DestinyGate.earnable(DestinyApi.state(actor), _gated()),
		true,
		"THE DEFECT: an alias prerequisite is satisfiable by the destiny that declares it"
	)
	# And end to end, through the public verb — a gate that is `earnable()` but cannot
	# be earned would only mean the check moved somewhere else.
	DestinyApi.earn_destiny(actor, GATED, "story")
	assert_eq(
		DestinyApi.has_destiny(actor, GATED),
		true,
		"and DestinyApi.earn_destiny actually grants it, so the rule is the one that runs"
	)


## The mirror direction, which is the one the shipped content uses: earning an
## ALIAS satisfies a prerequisite authored against the DEFINING destiny.
##
## Forward resolution (`holds_destiny` finds the definition, then its aliases) and
## reverse resolution (the id is not a definition, so the catalog is scanned) are two
## different code paths. A prerequisite read raw could be wrong in both.
func test_a_prerequisite_naming_the_definition_is_satisfied_by_holding_an_alias() -> void:
	var actor := _hero()
	# A SECOND gated destiny, this one requiring the DEFINING id rather than the
	# alias — installed per-test because `setup()` cannot take a parameter and a
	# shared catalog would be the wrong shape to test two questions against.
	(
		DestinyFixtureCatalog
		. install(
			[],
			[
				DestinyFixtureCatalog.aliased_destiny(RETURNED, [ALIAS, SECOND_ALIAS]),
				DestinyFixtureCatalog.gated_destiny(GATED, [], [RETURNED]),
				DestinyFixtureCatalog.plain_destiny(UNHELD),
			]
		)
	)
	# Earn the DEFINITION, which is the only id that can be earned: an alias is a
	# NAME for a destiny, not a destiny, and `earn_destiny` refuses an id with no
	# definition — deliberately, because a pure narrative alias ships no `.tres` and
	# a ledger key nothing can pay out is worse than a refusal. So the alias is
	# resolved on READ, never written on EARN.
	DestinyApi.earn_destiny(actor, ALIAS, "story")
	assert_eq(
		DestinyApi.destinies(actor),
		[] as Array[StringName],
		"earning a bare alias records nothing, because it names no destiny"
	)
	DestinyApi.earn_destiny(actor, RETURNED, "story")
	assert_eq(
		DestinyApi.destinies(actor),
		[RETURNED] as Array[StringName],
		"the ledger records the DEFINITION, under its own id and never the alias's"
	)
	assert_eq(
		DestinyGate.earnable(DestinyApi.state(actor), _gated()),
		true,
		"and holding the definition satisfies a prerequisite naming its ALIAS"
	)
	assert_eq(
		DestinyApi.has_destiny(actor, RETURNED),
		true,
		"while the definition also answers true for the alias that names it"
	)


## Every alias on a definition resolves, not only the first. `the_one_who_returned`
## ships one; a declaration is an ARRAY, and an implementation that stopped at the
## first entry would be correct against today's content and wrong against tomorrow's.
func test_every_declared_alias_satisfies_the_same_prerequisite() -> void:
	for alias in [ALIAS, SECOND_ALIAS]:
		var actor := _hero(&"hero_%s" % String(alias))
		DestinyApi.earn_destiny(actor, RETURNED, "story")
		assert_eq(
			DestinyApi.has_destiny(actor, alias),
			true,
			"'%s' is one of the definition's declared aliases, so it resolves" % alias
		)
		assert_eq(
			DestinyGate.earnable(DestinyApi.state(actor), _gated()),
			true,
			"and the alias prerequisite is met by it as by any other"
		)


# --- The two readers must not contradict each other, or the gate verb ----------


## `unmet_prerequisites()` is what `DestinyApi.summary()` renders under
## `blocked_by`. Before the fix it reported the alias permanently unmet while
## `earnable()` — once fixed — opened the gate: two published statements about one
## destiny, flatly contradictory, on the same screen.
##
## The invariant is not "the list is right" but "the list agrees with `earnable()`",
## because that is the property which was broken: two functions answering one
## question differently.
func test_the_unmet_list_agrees_with_earnable_in_both_states() -> void:
	var actor := _hero()
	var ledger := DestinyApi.state(actor)
	# Closed: both readers report the prerequisite outstanding, exactly once.
	assert_eq(DestinyGate.earnable(ledger, _gated()), false, "not earnable before the deed")
	var blocked := DestinyGate.unmet_prerequisites(ledger, _gated())
	assert_eq(blocked.size(), 1, "and exactly one prerequisite is outstanding")

	# Open: the list goes EMPTY, because an entry here is a claim that something is
	# still owed. Leaving the alias in it is what made `blocked_by` a permanent lie.
	DestinyApi.earn_destiny(actor, RETURNED, "story")
	ledger = DestinyApi.state(actor)
	assert_eq(DestinyGate.earnable(ledger, _gated()), true, "earnable after the deed")
	assert_eq(
		DestinyGate.unmet_prerequisites(ledger, _gated()),
		[] as Array[Dictionary],
		"and nothing is outstanding, so no panel can report a door that is open"
	)
	# The shape every consumer depends on: `unmet.is_empty()` means `earnable`.
	assert_eq(
		DestinyGate.unmet_prerequisites(ledger, _gated()).is_empty(),
		DestinyGate.earnable(ledger, _gated()),
		"the two readers never disagree about whether the door is open"
	)


## While the prerequisite IS outstanding, the entry names the alias the author
## WROTE — not the definition behind it.
##
## This is a decision, not a side effect. The entry is read by a panel showing the
## reason a destiny has not arrived, so it has to speak the author's vocabulary:
## rewriting `the_returned` into `the_one_who_returned` names a destiny they never
## wrote and does not tell them what to go and earn. The resolving happens in the
## QUESTION, not in the reporting.
func test_an_outstanding_alias_prerequisite_reports_the_id_the_author_wrote() -> void:
	var ledger := DestinyApi.state(_hero())
	var blocked := DestinyGate.unmet_prerequisites(ledger, _gated())
	assert_eq(blocked.size(), 1, "one outstanding prerequisite")
	var entry := blocked[0]
	assert_eq(String(entry["kind"]), "destiny", "it is a destiny prerequisite")
	assert_eq(
		String(entry["id"]),
		String(ALIAS),
		"named as authored — the alias, which is what the content says"
	)
	assert_eq(bool(entry["required"]), true, "and it is required")
	assert_eq(
		String(entry["label"]),
		"Requires the destiny '%s'" % String(ALIAS),
		"so the label is renderable without resolving anything itself"
	)


# --- What must NOT resolve ----------------------------------------------------


## Alias resolution widens to an id a definition DECLARES and to nothing else. The
## fix must not have turned `earnable()` into a looser check than the gate verb —
## `none_of` and `any_of` over destinies are built on the same resolver, so a
## prerequisite that accepted an arbitrary id would also let a branch close.
func test_an_unrelated_id_does_not_satisfy_an_alias_prerequisite() -> void:
	# `UNHELD` is a real, plain destiny with no aliases declared on it. Holding it
	# must not stand in for the alias.
	(
		DestinyFixtureCatalog
		. install(
			[],
			[
				DestinyFixtureCatalog.aliased_destiny(RETURNED, [ALIAS, SECOND_ALIAS]),
				DestinyFixtureCatalog.gated_destiny(GATED, [], [ALIAS]),
				DestinyFixtureCatalog.plain_destiny(UNHELD),
			]
		)
	)
	var actor := _hero()
	DestinyApi.earn_destiny(actor, UNHELD, "story")
	var ledger := DestinyApi.state(actor)
	assert_eq(
		DestinyGate.earnable(ledger, _gated()),
		false,
		"holding a different destiny leaves the alias prerequisite outstanding"
	)
	assert_eq(
		DestinyGate.unmet_prerequisites(ledger, _gated()).size(), 1, "and it is still reported"
	)
	# An id no definition declares, and no alias claims, resolves to nothing at all.
	# RETURNED is deliberately NOT in this list: it is the DESTINY that declares
	# '%s', and holding it MUST satisfy a prerequisite naming that alias - that is
	# the whole point of the reverse resolution. Listing it here would assert the
	# opposite of the fix, and the failure would read as a resolver bug when it is
	# a test that contradicted its own subject.
	for unrelated in [&"t_never_authored", &"t_the_returned_typo"]:
		DestinyApi.earn_destiny(actor, unrelated, "story")
	ledger = DestinyApi.state(actor)
	assert_eq(
		DestinyGate.earnable(ledger, _gated()),
		false,
		"an id no definition declares and no alias claims does not satisfy '%s'" % ALIAS
	)
	assert_eq(
		DestinyGate.earnable(DestinyApi.state(_hero()), _gated()),
		false,
		"and holding nothing at all does not satisfy it either"
	)


## An id TWO definitions declare as an alias resolves to nothing, exactly as
## [method DestinyGate.holds_destiny] already decided for the gate verb. A contested
## alias is not a prerequisite met twice; it is a content defect, and resolving it to
## whichever definition the scan reached first would let one alias satisfy both
## exclusive branches of one group.
func test_an_alias_claimed_by_two_destinies_satisfies_no_prerequisite() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[],
			[
				DestinyFixtureCatalog.aliased_destiny(RETURNED, [ALIAS, SECOND_ALIAS]),
				DestinyFixtureCatalog.aliased_destiny(UNHELD, [ALIAS]),
				DestinyFixtureCatalog.gated_destiny(GATED, [], [ALIAS]),
			]
		)
	)
	var actor := _hero()
	# Earning BOTH claimants satisfies neither: the resolver refuses to widen.
	DestinyApi.earn_destiny(actor, RETURNED, "story")
	DestinyApi.earn_destiny(actor, UNHELD, "story")
	assert_eq(
		DestinyApi.has_destiny(actor, ALIAS),
		false,
		"a contested alias resolves false even with both claimants held"
	)
	assert_eq(
		DestinyGate.earnable(DestinyApi.state(actor), _gated()),
		false,
		"so it satisfies no prerequisite, and the gate verb and earnable() agree"
	)


## A prerequisite that requires ITSELF is refused by `data audit` and would be
## unsatisfiable by construction — but a self-reference that reaches the resolver as
## an ALIAS is a different thing: `ALIAS` is declared ON `RETURNED`, and if a gated
## destiny ever required `ALIAS` while `ALIAS` had no definition, it must not
## deadlock into "permanently unmet with no reason". It resolves to nothing, so it
## stays unmet — which is the honest answer, and is asserted here so the fix is not
## read as having made a self-cycle passable.
func test_an_unresolvable_prerequisite_stays_unmet_rather_than_opening() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[],
			[
				DestinyFixtureCatalog.aliased_destiny(RETURNED, [ALIAS, SECOND_ALIAS]),
				# A gated destiny that requires an id NOTHING declares — the shape a
				# content typo takes.
				DestinyFixtureCatalog.gated_destiny(GATED, [], [&"t_typo_of_the_returned"]),
			]
		)
	)
	var actor := _hero()
	DestinyApi.earn_destiny(actor, RETURNED, "story")
	var ledger := DestinyApi.state(actor)
	assert_eq(
		DestinyGate.earnable(ledger, _gated()),
		false,
		"an unresolvable prerequisite is still a prerequisite, and the fix is not a rewrite"
	)
	assert_eq(
		DestinyGate.unmet_prerequisites(ledger, _gated()).size(),
		1,
		"and it is still named, so a panel has something to render"
	)
