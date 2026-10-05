extends TestCase

## **`SectApi.found` now runs on the generic founding path** (ADR 0271 decision 2,
## ADR 0083). This suite is the migration's own proof: the regression that matters is
## that a founding writes what it always wrote, and that the module no longer owns a
## second copy of the machinery.
##
## ## The three things a migration like this can break, measured
##
##   - **The ledger.** `SectFounding.write` used to build the skeleton, the roster, the
##     treasury, the obligation merge and the fit grant. `core/institution_founding.gd`
##     builds a CLAIM — eleven keys — and `SectState.normalize` owns the rest. Handing
##     one to the other without normalizing silently drops `doctrine`, `history`,
## `succession`, `schisms`, `applied_standing` and `granted_percent`, and a missing key
##     reads as an empty one.
##   - **The price.** `SectDef.founding_cost` is a four-key Dictionary and the generic
##     cost reader coerces a non-numeric value to `0`, so a profile carrying the raw
##     dictionary founds EVERY SECT FOR FREE without raising anything.
##   - **The strings.** A panel renders a reason it did not invent, so a refusal name
##     that moves is a visible change in what the game says.
##
## ## Shipped CONTENT drives most of this suite, not fixtures
##
## `SectFixtureCatalog` is installed by the eleven other sect suites and swapped back in
## their teardown, so a suite that wants the real `.tres` tree clears both singletons in
## its own `setup`. That is why "every shipped sect still founds" is a measurement here
## rather than a claim: a fixture cannot catch a `.tres` whose `founding_cost` is
## authored in a shape the adapter does not read.

const HOUSE := &"t_house"
const DOCTRINE := &"t_house_doctrine"
const FOUNDER := "keeper"
const FOUNDER_ID := &"keeper"

## Every verb a founding must never grow, and the two it must not have lost. ADR 0084
## says the refusal is pinned structurally because `tools arch` cannot see a method that
## does not exist; this is the same list `test_sect_no_power.gd` pins on the facade and
## it is repeated rather than imported so a facade rewrite cannot quietly narrow it.
const FORBIDDEN_VERBS := [
	"grant_stat",
	"grant_attribute",
	"set_base",
	"add_base",
	"power_up",
	"buff",
	"apply_modifier",
	"grant_modifier",
]

## `SectFounding`'s published surface after the migration, asserted as a WHOLE. The
## point is the ABSENCE: `write` is gone, so a module cannot grow a second ledger
## assembly path, and the delegating reads are named so they cannot be reimplemented by
## accident. **Methods only** — `get_script_method_list` does not publish constants, so
## `KIND`, `FUNDING_POOL` and the refusal names are checked as VALUES in the refusal case
## below rather than being listed here as if they were methods.
const PUBLISHED_FOUNDING := [
	"cost",
	"draw",
	"founded",
	"founder_fit",
	"funds",
	"profile",
	"registry",
	"treasury_lines",
]

## The keys `InstitutionFounding.write` is the authority for — the CLAIM. Every one of
## them is asserted equal to what the generic writer produces, which is the regression
## this suite exists for. The envelope keys below are deliberately NOT in this list:
## `history`, `applied_standing` and `granted_percent` are rewritten by `SectProjection`
## on the way to the actor, so comparing them against a fresh generic write compares a
## ledger against a ledger from a different moment in the same operation.
const GENERIC_CLAIM_KEYS := [
	"version",
	"institution",
	"position",
	"standing",
	"standing_cap",
	SectState.FOUNDER_KEY,
	"roster",
	"treasury",
	"obligation",
	"fit",
]

## The institution ledgers ADR 0271 decision 3 measured as carrying the same text
## coercion. `nation` is absent because `nation_state.gd` has no `_text` — it was never a
## copy — and naming it anyway would put a file in the list whose answer is "not
## applicable" rather than a measurement.
const INSTITUTION_LEDGERS := [
	"res://src/modules/clan/clan_state.gd",
	"res://src/modules/sect/sect_state.gd",
	"res://src/core/world_polity_ledger.gd",
]

## The bound is a RATCHET at TWO, not "at most one", and the difference is the point.
##
## The first version asserted `holders.size() <= 1` and was red on day one — correctly,
## because ADR 0271 decision 3 measured **three** copies and this slice removes one of
## them. `clan` and `world_polity_ledger` still carry the body. Asserting "at most one"
## would have been a guard only another two sessions' work could satisfy, which is the "a
## gate nobody can clear gets deleted" shape INC-0017 names.
##
## So the baseline is written down as a named number: a FOURTH copy fails, and each
## consolidation lowers it by one. Lowering the constant is part of the change that removes
## a copy, which is what stops the number going stale.
const LEDGER_COERCION_BASELINE := 2

var _born: Array = []


## The SHIPPED content tree, by nulling both catalog singletons. `teardown` puts them
## back the same way, so a suite that installed a fixture is unaffected and this suite
## never leaves a fixture behind either.
func setup() -> void:
	SectCatalog.shared = null
	SectDoctrineCatalog.shared = null


## `Actor` extends `RefCounted`, so `free()` on one is a SCRIPT ERROR that aborts the
## rest of `teardown` — the measured shape from `test_institution_foundation.gd`. What an
## `Actor` needs is only that nothing keeps holding it, which is `_born.clear()`. Nothing
## in this suite instantiates a `Node`, and `queue_free()` is banned in `res://src` and
## never runs under `tools test` anyway.
func teardown() -> void:
	SectCatalog.shared = null
	SectDoctrineCatalog.shared = null
	_born.clear()


## The actor-id argument is DEFAULTED rather than required, because four cases drive the
## same actor through several steps and a required argument would have meant inventing
## four ids to say nothing. `funds` is the second argument and is the one a case reads,
## so it is a default too rather than a positional trap.
func _founder(actor_id: StringName = FOUNDER_ID, funds: float = 100000.0) -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	actor.add_resource(ResourcePool.new(&"stamina", 100.0))
	actor.add_resource(ResourcePool.new(SectFounding.FUNDING_POOL, funds))
	_born.append(actor)
	SectApi.attach(actor)
	return actor


func _def(sect_id: StringName) -> SectDef:
	return SectCatalog.instance().sect_definition(sect_id)


func _doctrine(doctrine_id: StringName) -> SectDoctrineDef:
	return SectDoctrineCatalog.instance().doctrine(doctrine_id)


# --- The regression that matters: the ledger is the same ledger ---------------


## ## THE case. A founding writes what the generic writer writes, plus the one key the
## ## sect owns, and nothing else.
##
## Asserted as an EQUALITY against the generic writer's own output rather than as a list
## of expected values. A list would re-state the migration's answer in this file, and the
## second writer is exactly the thing that just died — comparing against it proves the
## verb is still routed, which is the property the whole slice exists to establish. The
## handful of field facts below it are there so a failure names WHICH key drifted.
func test_found_writes_what_the_generic_writer_writes_plus_the_doctrine() -> void:
	var fixture := SectFixtureCatalog.foundable_sect(HOUSE)
	SectFixtureCatalog.install([fixture])
	SectFixtureCatalog.install_doctrine([SectFixtureCatalog.doctrine(DOCTRINE)])
	var actor := _founder()
	var verdict := SectApi.found(actor, HOUSE, DOCTRINE, FOUNDER)
	assert_eq(bool(verdict["ok"]), true, "the founding landed: %s" % str(verdict.get("reason", "")))
	var persisted := SectApi.state(actor)

	var expected := SectState.normalize(
		InstitutionFounding.write(
			SectFounding.registry(),
			SectFounding.profile(fixture, _doctrine(DOCTRINE)),
			FOUNDER,
			String(fixture.top_position().id)
		)
	)
	expected["doctrine"] = String(DOCTRINE)
	# Every key the generic writer is the authority for, and no others: the three the
	# projection REWRITES are asserted separately below rather than compared here, because
	# comparing a rebuilt ledger against a fresh write compares two moments of the same
	# operation and reports a difference that is the projection working.
	for key in GENERIC_CLAIM_KEYS:
		assert_eq(persisted[key], expected[key], "'%s' is the generic writer's own value" % key)
	assert_eq(
		String(persisted["doctrine"]),
		String(expected["doctrine"]),
		"and the doctrine is the sect's"
	)

	# ## The ENVELOPE survives, and this is the half a claim-shaped writer cannot supply
	#
	# `InstitutionFounding.write` knows nothing about a succession walk, a declared split
	# or a history trail. The first version of the migration handed its ledger straight
	# to `_record`, which reads `ledger["history"]`, and every founding in the game
	# aborted on a missing key — the symptom reads like a broken verb rather than a
	# missing envelope, which is why each key is pinned by name here.
	for key in [
		"doctrine",
		"history",
		"succession",
		"schisms",
		"applied_standing",
		"granted_percent",
	]:
		assert_eq(persisted.has(key), true, "the ledger carries '%s'" % key)
	assert_eq(
		(persisted["history"] as Array).size(), 1, "and the founding is the one line on the trail"
	)
	assert_eq(String((persisted["history"] as Array)[0]["kind"]), "found", "which is the founding")
	# The two grant-record keys are the PROJECTION's, written on the way to the actor
	# rather than by the founding — asserted here so their presence is a fact about the
	# projection reaching this ledger, and not an accident of the generic write.
	assert_eq(int(persisted["applied_standing"]), int(persisted["standing"]), "the projection ran")
	assert_ne(
		(persisted["granted_percent"] as Dictionary).is_empty(),
		true,
		"and granted the top office's allowlist its bounded percent"
	)
	# And the fields a founding is judged on, read off the authored def rather than off
	# numbers written here.
	assert_eq(String(persisted["institution"]), String(HOUSE), "sworn to the sect they founded")
	assert_eq(
		String(persisted["position"]),
		String(fixture.top_position().id),
		"seated in the top office the def names"
	)
	assert_eq(SectState.founder(persisted), FOUNDER, "and the founder is a plain id string")
	assert_eq(
		persisted["roster"][String(fixture.top_position().id)] as Array,
		[FOUNDER],
		"who is the first entry in that office's roster"
	)
	assert_eq(
		int(persisted["standing"]),
		mini(SectState.FOUNDER_REFUND_STANDING, maxi(1, fixture.standing_cap)),
		"on the refund standing, clamped into the sect's own cap"
	)
	assert_eq(
		SectState.fit(persisted, DOCTRINE),
		SectFounding.founder_fit(_doctrine(DOCTRINE)),
		"with the founding fit grant the doctrine's own floor allows"
	)


## ## The module no longer OWNS a ledger writer, and that is what stops a second one
##
## `tools arch` reads references and method names, so it sees that `write` was deleted
## and would equally have seen it grow back. The published list is asserted whole, so a
## verb added later fails here whether or not its name is on the forbidden list.
func test_sect_founding_publishes_no_ledger_writer_of_its_own() -> void:
	var script: GDScript = load("res://src/modules/sect/sect_founding.gd")
	var published := _published(script)
	assert_eq(script == null, false, "the class loads at all")
	assert_eq(published.is_empty(), false, "the class's method list is readable")
	assert_eq(published, PUBLISHED_FOUNDING, "the founding surface is exactly this one")
	assert_eq(published.has("write"), false, "and the duplicated ledger writer is GONE")
	assert_eq(published.has("grant_founder_fit"), false, "along with its grant wrapper")
	for verb in FORBIDDEN_VERBS:
		assert_eq(published.has(verb), false, "SectFounding publishes no '%s'" % verb)


# --- The price ----------------------------------------------------------------


## ## Every SHIPPED sect still founds, and is charged what its `.tres` authors
##
## Driven off the real content tree rather than a fixture, because the thing that can
## break is the AUTHORED SHAPE: `founding_cost` is `{currency, amount, found,
## outstanding}` on disk and a number in the profile. A fixture authors the same shape,
## so this is the case that would catch a real `.tres` nobody tested.
##
## A `for` over `sect_ids()`, which is the catalog's OWN canonically sorted array: the
## bound is the content's own length and the body writes only into fresh local
## dictionaries, so nothing here grows the container it is walking.
func test_every_shipped_sect_still_founds_and_is_charged_its_authored_cost() -> void:
	var catalog := SectCatalog.instance()
	var ids := catalog.sect_ids()
	assert_ne(ids.size(), 0, "this build ships at least one sect")
	for sect_id in ids:
		var def := _def(sect_id)
		var doctrine_id := def.doctrine_id
		var price := int(SectFounding.cost(def)["outstanding"])
		var actor := _founder(&"founder_%s" % String(sect_id), float(price) + 1.0)
		var verdict := SectApi.found(actor, sect_id, doctrine_id, FOUNDER)
		assert_eq(
			bool(verdict["ok"]), true, "'%s' founds: %s" % [sect_id, str(verdict.get("reason", ""))]
		)
		# Charged EXACTLY the authored price — one point of headroom in the pool above, so
		# an off-by-one in either direction fails rather than rounding away.
		assert_almost_eq(
			SectFounding.funds(actor),
			1.0,
			"'%s' was charged its authored %d and left the rest" % [sect_id, price]
		)
		var ledger := SectApi.state(actor)
		assert_eq(String(ledger["institution"]), String(sect_id), "'%s' is sworn" % sect_id)
		assert_eq(String(ledger["doctrine"]), String(doctrine_id), "'%s' teaches" % sect_id)
		assert_eq(
			String(ledger["position"]),
			String(def.top_position().id),
			"'%s' seated the founder in its top office" % sect_id
		)
		assert_eq(
			(ledger["treasury"] as Dictionary).has("treasury_%s_all" % String(sect_id)),
			true,
			"'%s' opened its treasury through the generic writer" % sect_id
		)


## ## The profile's price EQUALS the authored `founding_cost`, asserted rather than
## ## assumed
##
## `test_sect_founding.gd` already dropped its own price check, which is what this case
## buys. The claim is now: the number the generic writer charges is the number the `.tres`
## authors, for every shipped sect — so the translation cannot silently read a different
## key than the content writes. `outstanding` is the key the sect has always charged on
## and `amount` is its documented fallback, so both are checked.
func test_the_profile_price_equals_the_authored_founding_cost_for_every_shipped_sect() -> void:
	for sect_id in SectCatalog.instance().sect_ids():
		var def := _def(sect_id)
		var authored := int(
			def.founding_cost.get("outstanding", def.founding_cost.get("amount", 0))
		)
		var doctrine := _doctrine(def.doctrine_id)
		var profile := SectFounding.profile(def, doctrine)
		assert_eq(
			int(profile["founding_cost"]),
			authored,
			"'%s' hands the generic writer its authored price" % sect_id
		)
		# And the number, not the dictionary — the shape mismatch is the whole hazard.
		assert_eq(
			profile["founding_cost"] is int or profile["founding_cost"] is float,
			true,
			"'%s' hands over a NUMBER" % sect_id
		)
		assert_eq(
			int(SectFounding.cost(def)["found"]),
			authored,
			"'%s' publishes the same price as the shortfall a panel renders" % sect_id
		)
		# A negative authored cost clamps rather than paying its holder, on both sides.
		var cheap := SectFixtureCatalog.sect(sect_id, def.positions, def.standing_cap)
		cheap.founding_cost = {"currency": "silver", "amount": -50, "outstanding": -50}
		assert_eq(
			int(SectFounding.cost(cheap)["outstanding"]),
			0,
			"'%s' clamps a negative authored cost to zero" % sect_id
		)


## ## THE RED PATH for the price: a Dictionary handed straight over founds a sect for
## ## NOTHING, and raises nothing
##
## INC-0016: a guard nobody has seen fire is a guard nobody knows works. So the hazard
## the adapter exists to prevent is exercised here as its own case, through the generic
## writer directly with a hand-built dictionary profile — which is exactly what the
## migration would have shipped had the profile copied `def.founding_cost` verbatim.
func test_a_profile_carrying_the_authored_dictionary_would_found_a_sect_for_nothing() -> void:
	var fixture := SectFixtureCatalog.foundable_sect(HOUSE)
	SectFixtureCatalog.install([fixture])
	SectFixtureCatalog.install_doctrine([SectFixtureCatalog.doctrine(DOCTRINE)])
	var actor := _founder(&"naive", 0.0)
	var raw := SectFounding.profile(fixture, _doctrine(DOCTRINE))
	raw["founding_cost"] = fixture.founding_cost
	var report := InstitutionFounding.found(
		SectFounding.registry(), actor, raw, "naive", SectState.empty()
	)
	assert_eq(bool(report["ok"]), true, "the naive profile was NOT rejected — it cost nothing")
	assert_eq(int(report["charged"]), 0, "and it charged zero")
	assert_almost_eq(SectFounding.funds(actor), 0.0, "on an empty fund")
	# Which is why the adapter translates. Stated as its own assertion rather than left
	# as a comment, because the number that follows IS the fix and a reader who only
	# reads the passing case would not know the dictionary path was ever wrong.
	assert_eq(
		int(SectFounding.profile(fixture, _doctrine(DOCTRINE))["founding_cost"]),
		int(SectFounding.cost(fixture)["outstanding"]),
		"the adapter hands over the number, and the number is the price"
	)


## ## The funding pool is still the SECT's own namespace
##
## `sect_founding_funds` is written into every actor's save, so it is a compatibility
## surface rather than a rule worth sharing — the same reasoning `InstitutionLedger`
## gives for `SOURCE_PREFIX`. Two things are asserted: the pool id did not change under
## the migration (a rename would strand every fund in every save), and the generic writer
## charges the pool the PROFILE names rather than its own default.
func test_the_funding_pool_is_still_the_sects_own_save_namespace() -> void:
	assert_eq(
		SectFounding.FUNDING_POOL,
		&"sect_founding_funds",
		"the save namespace did not change under the migration"
	)
	assert_ne(
		SectFounding.FUNDING_POOL,
		InstitutionFounding.DEFAULT_FUNDING_POOL,
		"and it is deliberately not the generic default"
	)
	var fixture := SectFixtureCatalog.foundable_sect(HOUSE)
	SectFixtureCatalog.install([fixture])
	SectFixtureCatalog.install_doctrine([SectFixtureCatalog.doctrine(DOCTRINE)])
	var actor := _founder()
	var price := int(SectFounding.cost(fixture)["outstanding"])
	SectApi.found(actor, HOUSE, DOCTRINE, FOUNDER)
	assert_almost_eq(
		actor.resource(SectFounding.FUNDING_POOL).current,
		100000.0 - float(price),
		"and the generic writer charged the pool the profile named"
	)


# --- The two caps, asserted against the cap and not restated -------------------


## ## The founding grant is bounded by BOTH of its ceilings
##
## The prompt's phrasing was "assert `SectState.FIT_CAP == 100` against the founding cap",
## and that assertion cannot be made: `FIT_CAP` bounds the fit AXIS and
## `FOUNDER_FIT_CAP` bounds the founding GRANT, they are different quantities, and both
## happening to be a round number is a coincidence rather than a relationship. Writing
## `FIT_CAP == FOUNDER_FIT_CAP` would assert the coincidence and would fail the day
## either was retuned for a real reason.
##
## So what is asserted is the two real bounds. The grant is a DERIVATION of the points
## rather than a second number, and it may never exceed the axis it is written onto — a
## grant past the ceiling would hand a founder fit the rest of the module clamps away on
## read, which is a grant that reads as smaller than it was.
func test_the_founding_grant_is_bounded_by_both_its_own_cap_and_the_fit_cap() -> void:
	assert_eq(
		SectFounding.FOUNDER_FIT_CAP,
		SectFounding.FOUNDER_FIT_POINTS,
		"the grant's cap is a derivation of the points, not a second number"
	)
	assert_eq(
		SectFounding.TREASURY_OPENING_PERIODS,
		InstitutionFounding.TREASURY_OPENING_PERIODS,
		"and the treasury's opening balance is the generic writer's own number"
	)
	## The doctrine list is SNAPSHOT before the loop. `install_doctrine` replaces the
## catalog singleton with one holding only what it was handed, so a case that read the
## catalog again on the second pass asked a catalog that no longer carried the first
## doctrine — and got `null` back, which aborted the case on `floor_fit` rather than
## reporting the failure it was written to find.
	var doctrine_ids := SectDoctrineCatalog.instance().doctrine_ids()
	assert_ne(doctrine_ids.size(), 0, "this build ships at least one doctrine")
	var doctrines: Array[SectDoctrineDef] = []
	for doctrine_id in doctrine_ids:
		doctrines.append(_doctrine(doctrine_id))
	var fixture := SectFixtureCatalog.foundable_sect(HOUSE)
	SectFixtureCatalog.install([fixture])
	SectFixtureCatalog.install_doctrine(doctrines)
	for doctrine in doctrines:
		var points := SectFounding.founder_fit(doctrine)
		assert_eq(
			points <= SectFounding.FOUNDER_FIT_CAP,
			true,
			"'%s' grants at most its own cap" % doctrine.id
		)
		assert_eq(
			points <= SectState.FIT_CAP, true, "'%s' grants at most the fit ceiling" % doctrine.id
		)
		assert_eq(
			points <= doctrine.floor_fit(),
			true,
			"'%s' grants at most the doctrine's own floor" % doctrine.id
		)
		# And what the PROFILE hands the generic writer is the same number, capped there
		# rather than on read: `positive_lines` keeps a count and the reader would clamp it
		# silently, which is the shape where a retune loses points without failing.
		var profile := SectFounding.profile(fixture, doctrine)
		var carried := int((profile["fit"] as Dictionary).get(String(doctrine.id), 0))
		assert_eq(carried, points, "'%s' carries exactly the grant into the ledger" % doctrine.id)
	# A null doctrine grants nothing rather than raising, which is the state a profile
	# naming no doctrine would be in.
	assert_eq(SectFounding.founder_fit(null), 0, "a founder of no doctrine is granted nothing")


## ## The ONE place a sect def's authored number meets the fit ceiling
##
## `SectDef.member_obligation_lines` clamps `instruction_<sect>` — the price of being
## taught at all — at `FIT_CAP`. That is the single join between a `.tres` author's
## `min_purity` and the ceiling, so it is the one worth pinning: a `min_purity` above the
## fit axis would open a debt no amount of teaching could ever discharge.
func test_a_sects_instruction_debt_is_clamped_at_the_fit_cap() -> void:
	for sect_id in SectCatalog.instance().sect_ids():
		var def := _def(sect_id)
		var lines := def.member_obligation_lines()
		if def.min_purity <= 0:
			assert_eq(
				lines.has("instruction_%s" % String(sect_id)),
				false,
				"'%s' opens no instruction debt it does not charge for" % sect_id
			)
			continue
		assert_eq(
			int(lines["instruction_%s" % String(sect_id)]),
			mini(def.min_purity, SectState.FIT_CAP),
			"'%s' clamps its instruction debt at the fit ceiling" % sect_id
		)
		assert_eq(
			int(lines["instruction_%s" % String(sect_id)]) <= SectState.FIT_CAP,
			true,
			"so it is dischargeable in principle"
		)


# --- The split, and the refusals -----------------------------------------------


## ## ADR 0064 through the founding path: a high office on thin standing is legal
##
## Both directions, separately, because a design that collapsed the pair into one number
## would pass a combined check — it would have no second number to contradict. What is
## new here is only the ROUTE: the numbers now arrive from `InstitutionFounding.write`
## rather than from `SectFounding.write`, so the split is measured on the generic
## writer's output for the first time.
func test_position_and_standing_never_derive_from_each_other_through_the_founding_path() -> void:
	var fixture := SectFixtureCatalog.foundable_sect(HOUSE)
	SectFixtureCatalog.install([fixture])
	SectFixtureCatalog.install_doctrine([SectFixtureCatalog.doctrine(DOCTRINE)])
	var actor := _founder()
	SectApi.found(actor, HOUSE, DOCTRINE, FOUNDER)
	var claim := SectState.claim(SectApi.state(actor))
	assert_eq(
		String(claim.position),
		String(fixture.top_position().id),
		"the founder is seated in the top office"
	)
	assert_eq(int(claim.standing), SectState.FOUNDER_REFUND_STANDING, "with the refund standing")

	# Direction one: a promotion writes the position and leaves the standing alone.
	var before := int(SectApi.state(actor)["standing"])
	var promoted := SectApi.promote(actor, &"t_member")
	assert_eq(bool(promoted["ok"]), true, "the promotion landed")
	assert_eq(
		String(SectApi.state(actor)["position"]),
		"t_member",
		"the position moved DOWN to the open office"
	)
	assert_eq(int(SectApi.state(actor)["standing"]), before, "and standing did not follow it")

	# Direction two: a standing change moves standing and leaves the position alone.
	var seat := String(SectApi.state(actor)["position"])
	SectApi.move_standing(actor, -30)
	assert_eq(int(SectApi.state(actor)["standing"]), before - 30, "standing moved")
	assert_eq(String(SectApi.state(actor)["position"]), seat, "and the position did not")


## ## ADR 0044 as a measurement, through the generic writer
##
## Every refusal above the point at which the pool is touched, so the actor is byte-for-byte
## what it was — the SAVE payload as well as the balance, because a pool that moved while
## the ledger did not is the half-state the property exists to forbid.
func test_a_refused_found_writes_nothing_through_the_generic_path() -> void:
	var fixture := SectFixtureCatalog.foundable_sect(HOUSE)
	SectFixtureCatalog.install([fixture])
	SectFixtureCatalog.install_doctrine([SectFixtureCatalog.doctrine(DOCTRINE)])
	var actor := _founder(&"pauper", 1.0)
	var before := _fingerprint(actor)
	var verdict := SectApi.found(actor, HOUSE, DOCTRINE, "pauper")
	assert_eq(
		String(verdict["reason"]), SectApi.FOUNDING_COST_UNMET, "an empty fund is refused by name"
	)
	assert_eq(_fingerprint(actor), before, "and the actor is byte-for-byte as it was")
	# The shortfall a panel renders is still this tier's to publish, and it carries the
	# authored COIN — which is precisely the key the generic path knows nothing about.
	assert_eq(int(verdict["required"]), int(SectFounding.cost(fixture)["outstanding"]), "required")
	assert_eq(String(verdict["currency"]), "silver", "in the coin the author wrote")
	assert_eq(verdict.has("force"), false, "and no override is offered")
	# A second founding is refused by the same shared name, and writes nothing either.
	var rich := _founder()
	assert_eq(bool(SectApi.found(rich, HOUSE, DOCTRINE, FOUNDER)["ok"]), true, "one founding lands")
	var sworn := _fingerprint(rich)
	var again := SectApi.found(rich, HOUSE, DOCTRINE, FOUNDER)
	assert_eq(
		String(again["reason"]),
		SectApi.ALREADY_FOUNDED,
		"a second founding is refused by the shared name"
	)
	assert_eq(_fingerprint(rich), sworn, "and changed nothing")


## ## A panel renders a reason it did not invent, so the STRINGS must not have moved
##
## The module's refusal names are now ALIASES of the shared constants, which is one value
## under two spellings. `unknown_sect` and `unknown_doctrine` are the exception and are
## deliberately NOT aliases: `core/` may not know that a sect is a thing, so the shared
## vocabulary says `unknown_institution`, and the sect's own spelling is what a screen and
## a history record have always quoted. Both facts are asserted, because "aliased" and
## "kept" are the two ways this could go wrong.
func test_the_refusal_names_a_panel_renders_are_unchanged() -> void:
	assert_eq(String(SectApi.NO_ACTOR), "no_actor", "no_actor is unchanged")
	assert_eq(String(SectApi.UNKNOWN_SECT), "unknown_sect", "unknown_sect is unchanged")
	assert_eq(String(SectApi.UNKNOWN_DOCTRINE), "unknown_doctrine", "unknown_doctrine is unchanged")
	assert_eq(String(SectApi.ALREADY_FOUNDED), "already_founded", "already_founded is unchanged")
	assert_eq(String(SectApi.NO_TOP_POSITION), "no_top_position", "no_top_position is unchanged")
	assert_eq(
		String(SectApi.FOUNDING_COST_UNMET), "founding_cost_unmet", "so is founding_cost_unmet"
	)
	# And the four shared ones are the SAME VALUE, not a copy that could drift.
	assert_eq(SectFounding.R_NO_ACTOR, InstitutionLedger.R_NO_ACTOR, "no_actor is one value")
	assert_eq(SectFounding.R_ALREADY_FOUNDED, InstitutionLedger.R_ALREADY_FOUNDED, "so is that one")
	assert_eq(SectFounding.R_NO_TOP_POSITION, InstitutionLedger.R_NO_TOP_POSITION, "and that one")
	assert_eq(
		SectFounding.R_FOUNDING_COST_UNMET, InstitutionLedger.R_FOUNDING_COST_UNMET, "and that one"
	)
	# The two that are NOT shared are proved not to be, which is what makes
	# `SectFounding.REASONS` a superset rather than a filtered copy to keep in step.
	assert_eq(
		InstitutionLedger.REASONS.has(SectFounding.R_UNKNOWN_SECT),
		false,
		"unknown_sect is this tier's own wording and the shared table does not carry it"
	)
	# Every key the module publishes resolves to itself, so a lookup by name cannot be a
	# silent null — the failure mode `InstitutionLedger.REASONS` exists to prevent.
	for name in SectFounding.REASONS.keys():
		assert_eq(String(SectFounding.REASONS[name]), String(name), "'%s' resolves" % name)


# --- The text coercion, and the grant's envelope -------------------------------


## ## `SectState._text` is a DELEGATION, and it still refuses what it always refused
##
## Three files carried this coercion and `InstitutionLedger.text` owns the reasoning now.
## The source half of the case is what makes it a delegation rather than a rewrite: a
## body that had been kept would be a second copy that could drift, and only the
## function's own body is scanned — `_claim_fields_readable` asks the same type question
## for a different purpose and is NOT a second coercion.
##
## The value half is the half a rewrite could break: `String(42.0)` RAISES in GDScript
## rather than yielding `"42.0"`, so a cast here would abort an attach instead of reading
## a corrupt field as absent.
func test_sect_state_text_is_a_delegation_and_still_refuses_a_corrupt_payload() -> void:
	var body := FileAccess.get_file_as_string("res://src/modules/sect/sect_state.gd")
	var own := _body(body, "static func _text(")
	assert_ne(own, "", "the coercion is findable, so the scan below read its body")
	assert_eq(
		own.contains("is String or value is StringName"),
		false,
		"_text carries no copy of the type test (InstitutionLedger.text owns it)"
	)
	assert_eq(
		own.contains("return fallback"),
		false,
		"nor of the fallback, which is the other half of the same decision"
	)
	# And it answers exactly what the shared coercion answers, over a table that covers
	# every branch: both text kinds pass, everything else falls back.
	for value in ["t_house", StringName("t_house"), 42.0, {}, [], null, true]:
		assert_eq(
			SectState._text(value, "fallback"),
			InstitutionLedger.text(value, "fallback"),
			"'_text' and the shared coercion agree on %s" % str(value)
		)
	# The CORRUPT PAYLOAD is diagnosed as empty and never partially applied: half a ledger
	# is worse than none, because it silently changes what the player is owed.
	for bad in [
		{"institution": 42.0},
		{"institution": "t_house", "position": Vector2(1.0, 2.0)},
		{"institution": "t_house", "standing": "not a number"},
		{"institution": "t_house", "doctrine": 7.0},
		{"institution": "t_house", SectState.FOUNDER_KEY: 1.0},
	]:
		var read := SectState.normalize(bad)
		assert_eq(String(read["institution"]), "", "a corrupt claim field discards the record")
		assert_eq(int(read["standing"]), 0, "and no half state survives")
		assert_eq((read["roster"] as Dictionary).is_empty(), true, "nor a roster")
		# The LENIENT half is asserted beside it: one unusable MAP beside three good
		# fields drops only that map, because losing earned standing because an unrelated
		# line went bad is the worse failure.
		var lenient := SectState.normalize(
			{"institution": "t_house", "standing": 40, "fit": "not a dictionary"}
		)
		assert_eq(
			int(lenient["standing"]), 40, "an unusable map does not take the standing with it"
		)
		assert_eq((lenient["fit"] as Dictionary).is_empty(), true, "only the map is dropped")


## ## At most ONE INSTITUTION LEDGER declares a text coercion body
##
## `ClanState._text` documents itself as "`sect_state.gd`'s `_text`, carried over
## unchanged", so this case was written to be green before and after the clan slice
## delegates: it asserts a BOUND, not a specific owner. A scan that named the expected
## file would go red the moment a second copy was deleted, which is the wrong moment for
## a consolidation guard to fire.
##
## ## The scan is a NAMED list, and that is measured rather than convenient
##
## The first version walked every `.gd` under `game/src/modules/` and found **six**
## `_text` definitions, four of them unrelated: `race_state.gd`, `world_spawn_state.gd`,
## `combat_engine/mind_damage.gd` and `loot/loot_content_records.gd` each coerce a field
## of their own, two of them with a DIFFERENT body (a bare `is StringName` branch, a
## `Resource.get` probe). A whole-module scan would therefore have been red on day one
## and would have measured "how many modules name a helper `_text`", which is not the
## question. ADR 0271 decision 3 named the three files that were actually copies —
## `ClanState`, `SectState`, `WorldPolityLedger` — and `nation` was never one, so the
## guard covers exactly the institution ledgers.
##
## A `for` over that CONSTANT array, writing into two fresh arrays: the bound is the list
## length and the body never grows the container it walks, so `test_no_unbounded_wait`
## has nothing to refuse. See `LEDGER_COERCION_BASELINE` for why the bound is two.
func test_the_text_coercion_copy_count_only_goes_down() -> void:
	var holders: Array[String] = []
	for rel in INSTITUTION_LEDGERS:
		var body := FileAccess.get_file_as_string(rel)
		assert_ne(body, "", "%s is readable" % rel)
		if _body(body, "static func _text(").contains("is String or value is StringName"):
			holders.append(rel)
	assert_eq(
		holders.size(),
		LEDGER_COERCION_BASELINE,
		(
			(
				"the copy count is %d, not more. Lower LEDGER_COERCION_BASELINE in the "
				+ "same change that removes a copy -- %s"
			)
			% [LEDGER_COERCION_BASELINE, ", ".join(holders)]
		)
	)
	assert_eq(
		holders.has("res://src/modules/sect/sect_state.gd"),
		false,
		"and sect's is no longer one of them"
	)
	# The delegation itself, on both branches, so the case is not satisfied by the file
	# being unreadable.
	assert_eq(
		SectState._text(42.0, "fallback"),
		InstitutionLedger.text(42.0, "fallback"),
		"and sect's answers exactly as the shared coercion does"
	)
	assert_eq(
		SectState._text("t_house", ""),
		InstitutionLedger.text("t_house", ""),
		"on the accepting branch too"
	)


# --- The refusal stays STRUCTURAL ----------------------------------------------


## ADR 0084's own answer: `tools arch` cannot see a method that does not exist, so the
## refusal is a test on the facade's published surface. Repeated here because the
## migration edited the verb that runs the founding — the one place a grant helper would
## have been most convenient to add and least visible once added.
func test_the_facade_still_publishes_no_power_granting_verb() -> void:
	var script: GDScript = load("res://src/modules/sect/api.gd")
	var published := _published(script)
	assert_eq(script == null, false, "the facade loads at all")
	assert_eq(published.is_empty(), false, "the facade's method list is readable")
	for verb in FORBIDDEN_VERBS:
		assert_eq(published.has(verb), false, "SectApi publishes no '%s'" % verb)
	# `found` is still exactly the verb it was: the migration added no thirteenth method.
	assert_eq(published.has("found"), true, "and founding is still on the facade")
	assert_eq(published.has("force_found"), false, "with no override beside it")


# --- Helpers -------------------------------------------------------------------


## Everything a `found` could possibly have written: the save payload AND the pool
## balance. A refused verb must leave both identical, so both are in the fingerprint.
func _fingerprint(actor: Actor) -> Dictionary:
	var pool = actor.resource(SectFounding.FUNDING_POOL)
	return {
		"pool": 0.0 if pool == null else pool.current,
		"save": actor.to_dict(),
	}


## Every public method name on an already-loaded script. Underscore-prefixed names are
## dropped, exactly as `tools/arch/enforce.py` drops them, so the list here and the gate
## count the same verbs.
##
## ## The `load()` is at the CALL SITE
##
## A `GDScript`-typed parameter handed the class reference, the same parameter handed a
## `res://` string, and a `String` parameter dispatched through a `match` to a literal
## inside the helper were all rewritten to get there; **none of them was the problem.**
## The problem was `assert_ne(published.is_empty(), false)` — the idiom for "not empty" in
## this framework is `assert_eq(x.is_empty(), false)`, and `assert_ne` asserts the
## OPPOSITE, so a perfectly readable surface reported itself unreadable. Three full runs
## were spent rewriting a working helper because the failure looked like a data problem
## and read like one. **It was then written inverted a fourth time** on the `script ==
## null` line beside it, which is the clearest evidence that the fix is the SHAPE
## (`assert_eq` on a boolean, never `assert_ne` against `false`) and not the individual
## line: four sites, three rewrites, and the last one was the very next edit.
##
## **The lesson is the one ADR 0084 already states**, and it is why the sibling suites
## spell the surface check the same way: an unreadable surface and a clean one must not
## produce the same verdict. `assert_eq(published.is_empty(), false, ...)` in front of
## every structural refusal is what makes them distinguishable, and both call sites also
## assert the script itself loaded.
func _published(script: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (script is GDScript):
		return out
	for method in (script as GDScript).get_script_method_list():
		var name: String = method["name"]
		if name.begins_with("_"):
			continue
		if not out.has(name):
			out.append(name)
	out.sort()
	return out


## The body of the function whose signature contains `signature`, cut at the next
## top-level `func`, or `""` when there is none. A bounded scan of an authored file, not
## a loop over anything a caller controls.
func _body(body: String, signature: String) -> String:
	var at := body.find(signature)
	if at < 0:
		return ""
	var tail := body.substr(at + signature.length())
	var stop := tail.find("\nstatic func ")
	if stop < 0:
		stop = tail.find("\nfunc ")
	if stop < 0:
		stop = tail.length()
	return tail.substr(0, stop)
