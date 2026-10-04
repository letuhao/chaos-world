extends TestCase

## ADR 0091 / BL-0200: an institution's opinion of an actor lives in ONE place, and
## `clan` reaches it the way `sect` and `nation` do — by applying an AUTHORED cause
## through `SocialApi`, not by writing a float of its own.
##
## **Every assertion here reads `social` through its real facade.** None of them reads
## `SocialState.regard` through a private, and none of them reads the clan ledger and
## calls that a social advantage. The whole point of the bridge is that a consumer
## asking `SocialApi.summary(actor)["regard"]` sees the house, so that is the surface
## these hold it to.

const HOUSE := &"t_house"
const RIVAL := &"t_rival"
const LINE := &"hearthborn"

## The shipped `sworn_to_sect` magnitude, so "a house is worth less than an oath" is an
## assertion rather than a claim in a comment.
const SECT_STANDING := 2.0


func setup() -> void:
	ClanFixtureCatalog.install([ClanFixtureCatalog.open(HOUSE), ClanFixtureCatalog.open(RIVAL)])
	# The cause catalog is a process-wide singleton and sibling suites reset it to
	# whatever they happen to need, so every test starts from the shipped set. Without
	# this, a clan test that ran after `test_social_bond`'s `_single_cause` would find
	# `sworn_to_a_clan` missing and assert nothing at all.
	SocialCauseCatalog.instance().install_defaults()


func teardown() -> void:
	ClanFixtureCatalog.teardown()


func _born(purity: float = 0.5) -> Actor:
	var actor: Actor = Actor.new(&"member", {Stat.PHYSIQUE: 10.0})
	SocialApi.attach(actor)
	ClanApi.attach(actor)
	BloodlineApi.attach(actor)
	BloodlineApi.set_purity(actor, LINE, purity)
	return actor


func _member(purity: float = 0.5, standing: int = 0, clan_id: StringName = HOUSE) -> Actor:
	var actor := _born(purity)
	ClanApi.join(actor, clan_id, standing)
	return actor


## The read a consumer actually makes: `regard` keyed by INSTITUTION id.
func _regard(actor: Actor, institution_id: StringName) -> float:
	return float(
		(SocialApi.summary(actor)["regard"] as Dictionary).get(String(institution_id), 0.0)
	)


## ## What a join at `purity` SHOULD record at that house
##
## The admission is one authored cause applied at `ClanGate.recognition_scale`, so the
## regard a member appears with is the cause's magnitude TIMES the hinge factor. Every
## "the world formed an opinion" assertion below reads this rather than a literal,
## because the whole bridge is that these two numbers are the same number: spelling the
## answer `1.5` would freeze a curve and turn four tests into four copies of a constant
## rather than four readings of the mechanism.
func _weighed(purity: float) -> float:
	var cause_standing := float(
		SocialCauseCatalog.instance().cause_definition(ClanApi.CAUSE_SWORN).standing
	)
	return cause_standing * (ClanGate.UNSCALED + (1.0 - ClanGate.UNSCALED) * purity)


# --- The catalog ships the ids the bridge names -------------------------------


## ## Why this is its own test rather than an inline precondition
##
## `ClanApi._regard` IGNORES `apply_cause`'s verdict, exactly as `SectApi._regard` and
## `NationApi._regard` do — the refusal is real and legitimate, and aborting a
## membership change over it would be worse. That makes a missing cause id INVISIBLE:
## the join succeeds, every assertion below reads 0.0, and the suite would go green
## asserting nothing. So the catalog is checked against the ids the facade names, which
## is what turns that silent path into a failed test.
func test_the_shipped_catalog_carries_exactly_the_ids_the_facade_names() -> void:
	for cause_id in [ClanApi.CAUSE_SWORN, ClanApi.CAUSE_LEFT]:
		var cause := SocialCauseCatalog.instance().cause_definition(cause_id)
		assert_ne(cause, null, "'%s' ships in the cause catalog" % cause_id)
		assert_eq(
			cause.institutional,
			true,
			"'%s' is institutional, so its row is projected into regard" % cause_id
		)
		assert_eq(String(cause.kind), "clan", "'%s' counts as one kind of act" % cause_id)


# --- Joining opens the row ----------------------------------------------------


func test_a_member_appears_in_social_regard_for_that_house() -> void:
	var actor := _member(0.5)
	assert_almost_eq(
		_regard(actor, HOUSE), _weighed(0.5), "the house now holds an opinion about them"
	)
	assert_eq(
		SocialApi.bond_entry(actor, HOUSE)["causes"].has(String(ClanApi.CAUSE_SWORN)),
		true,
		"and the cause ledger names the act"
	)


## ## Asserted through `SocialApi.gate`, which is how any consumer would ask
##
## `regard_at_least` is the verb that makes this read model non-write-only, and it is
## the same question a house's own content will ask. Reading it here rather than
## inspecting `state.regard` is the difference between a feature and an implementation.
##
## ## Both bars are read off the bridge, and neither is a guessed magnitude
##
## The admission is ONE authored cause applied at `ClanGate.recognition_scale`, so at
## purity 0.5 it lands at `sworn_to_a_clan`'s authored 1.5 times `UNSCALED + (1 -
## UNSCALED) * 0.5` — 1.125 — which is BELOW 1.5 and well below the 6.0 at which the
## bond ladder calls someone an acquaintance. A bar written at a literal `1.0` therefore
## asserts that the hinge does not exist, and a bar at a literal `2.0` was passing only
## because the row happened to be small. Both below are derived from what the mechanism
## produces, so the gate is checked where the row actually stopped and a hundredth past
## it.
func test_a_house_can_gate_on_its_regard_through_the_real_social_gate() -> void:
	var actor := _member(0.5)
	var recorded := _weighed(0.5)
	assert_eq(
		bool(
			(
				SocialApi
				. gate(actor, {"verb": &"regard_at_least", "partner": HOUSE, "at_least": 0.5})["ok"]
			)
		),
		true,
		"a member is regarded by their house"
	)
	assert_eq(
		bool(
			(
				SocialApi
				. gate(actor, {"verb": &"regard_at_least", "partner": HOUSE, "at_least": 2.0})["ok"]
			)
		),
		false,
		"and the gate is a real bar rather than a yes"
	)
	assert_eq(
		bool(
			(
				SocialApi
				. gate(actor, {"verb": &"regard_at_least", "partner": HOUSE, "at_least": recorded})["ok"]
			)
		),
		true,
		"a gate at exactly what the admission recorded is satisfiable"
	)
	assert_eq(
		bool(
			(
				SocialApi
				. gate(
					actor,
					{"verb": &"regard_at_least", "partner": HOUSE, "at_least": recorded + 0.01}
				)["ok"]
			)
		),
		false,
		"and one hundredth over it is not"
	)


## The clan ledger is untouched by the bridge, so the two ledgers cannot disagree.
func test_opening_the_regard_row_writes_nothing_into_the_clan_ledger() -> void:
	var actor := _member(0.5, 0)
	assert_eq(ClanApi.standing_of(actor), 0, "joining is not earning: the ledger is unmoved")
	assert_eq(ClanApi.rank_of(actor), &"outer", "and the entry rank is still the entry rank")
	assert_almost_eq(_regard(actor, HOUSE), _weighed(0.5), "the world formed an opinion anyway")


func test_an_actor_who_belongs_to_no_house_is_regarded_by_nothing() -> void:
	var actor := _born(0.5)
	assert_eq(_regard(actor, HOUSE), 0.0, "no house has an opinion yet")
	assert_eq(
		(SocialApi.summary(actor)["regard"] as Dictionary).is_empty(),
		true,
		"and the read model says so rather than carrying a zero row"
	)


# --- Leaving closes it, by a different act -----------------------------------


func test_leaving_moves_regard_down_by_the_leaving_cause() -> void:
	var actor := _member(0.5)
	var joined := _weighed(0.5)
	assert_almost_eq(_regard(actor, HOUSE), joined, "joined")
	# The admission in, the leaving out, and the row SURVIVES: `SocialState` projects
	# from the bonds and `SocialBond.institutional` is sticky, so a house you left is
	# still a house the world holds an opinion about. That is the sect precedent exactly.
	#
	# `CAUSE_LEFT` is applied at the DEFAULT scale of 1.0, not through the hinge. It is
	# the act of walking out, and by then `leave` has not yet cleared the ledger — but the
	# cost of leaving must not depend on the lineage of a membership that is over, so the
	# bridge reaches it through `SocialApi` directly rather than through `ClanGate`'s
	# factor. The weight is asserted below rather than assumed.
	var left := float(SocialCauseCatalog.instance().cause_definition(ClanApi.CAUSE_LEFT).standing)
	ClanApi.leave(actor)
	assert_almost_eq(_regard(actor, HOUSE), joined + left, "the row survives at the net of both")
	var causes := SocialApi.bond_entry(actor, HOUSE)["causes"] as Array
	assert_eq(causes.has(String(ClanApi.CAUSE_SWORN)), true, "the oath is in the ledger")
	assert_eq(causes.has(String(ClanApi.CAUSE_LEFT)), true, "and so is the leaving")


## A refused admission is the case that matters most here: an actor turned away must
## not leave a regard row behind, because the world never met them at that house.
func test_a_refused_admission_moves_no_regard_at_all() -> void:
	SocialCauseCatalog.instance().install_defaults()
	ClanFixtureCatalog.install([ClanFixtureCatalog.sealed(&"t_sealed", 0.9)])
	var actor := _born(0.1)
	var verdict := ClanApi.join(actor, &"t_sealed")
	assert_eq(bool(verdict["ok"]), false, "the purity bar refused the admission")
	assert_eq(_regard(actor, &"t_sealed"), 0.0, "and no opinion was formed about them")


func test_leaving_an_actor_who_belongs_to_no_house_closes_no_row() -> void:
	var actor := _born(0.5)
	assert_eq(ClanApi.leave(actor), false, "refused")
	assert_eq(
		(SocialApi.summary(actor)["regard"] as Dictionary).is_empty(),
		true,
		"and there was no row to close"
	)


# --- The magnitudes are sized against the sect tier ---------------------------


## ## A house is worth less than an oath, and that is authored rather than incidental
##
## The whole tier is built on "membership is one act in a ledger meant to hold a career
## of them". `sworn_to_a_clan` at 1.5 sits under `sworn_to_sect` at 2.0 because entry
## to a house is usually arranged by someone else before the member could refuse it. If
## a later author raises it past the oath, this is the test that says so.
func test_entry_to_a_house_is_authored_worth_less_than_a_sworn_oath() -> void:
	var cause := SocialCauseCatalog.instance().cause_definition(ClanApi.CAUSE_SWORN)
	assert_almost_eq(float(cause.standing), 1.5, "a carrier's admission is recorded at 1.5")
	assert_almost_eq(SECT_STANDING, 2.0, "and the sect oath it is measured against is 2.0")
	assert_eq(float(cause.standing) < SECT_STANDING, true, "so a house ranks below an oath")


## One membership cannot be farmed: the distinct-KIND rule reads `clan` for both causes,
## so a member who joined and left a hundred houses has still recorded one kind of act.
func test_house_membership_cannot_be_farmed_into_a_friendship() -> void:
	var actor := _born(0.5)
	var cycles := 12
	# A `while` with an explicit counter rather than a `for`: `for index in cycles`
	# declares its own `index`, which is a redeclaration in this build, and the loop
	# variable is not readable after the loop — so the "the loop really ran" proof below
	# needs a counter this function owns.
	var index := 0
	while index < cycles:
		ClanApi.join(actor, HOUSE, 0)
		ClanApi.leave(actor)
		index += 1
	# The counter is compared against `cycles`, not against `cycles - 1`: this loop runs
	# to `cycles` exactly and `index` ends on it. Reading the bound off the variable
	# rather than off a literal keeps the "the loop really ran" proof true however the
	# count is later retuned.
	var bond := SocialApi.social_state(actor).bond(HOUSE)
	assert_ne(bond, null, "the house is a row on the ledger")
	assert_eq(bond.distinct_kinds(), 1, "twelve join/leave cycles are still one kind of act")
	# ## The ceiling is the ladder's OWN, because membership never climbs it
	#
	# `SocialBondClass` calls a bond an acquaintance once it reaches `FRIEND_AT` (6.0)
	# holding TWO kinds of act. This bond holds one, so twelve cycles of ever-larger
	# arithmetic can never arrive — and that is the whole property, so it is asserted as
	# the property rather than as one spelling of its answer.
	#
	## The label is whatever the ladder answers, and it is NOT asserted to be
	## `acquaintance` at any specific figure: the admission is 1.5 weighted by the hinge,
	## and every join/leave pair moves the floor by a different amount at every purity, so
	## a hard-coded class here would be asserting a tuned constant rather than the
	## anti-farm rule. What is asserted is the THING that holds regardless of tuning — the
	## bond is not a stranger (a positive floor survived), and the one kind caps it well
	## short of the friendship the ladder reserves for a second kind of act.
	##
	## ## "A positive floor survived" names the FLOOR, and the axis was the wrong number
	##
	## The two are different and `SocialBond` documents the difference three times over:
	## an axis "carries a floor: the persistent part that decay never eats", `apply` says
	## "a decay toward the floor is always a move toward truth rather than toward
	## amnesia", and the cause catalog says `sworn_to_a_clan` is persistent so that
	## "ADR 0091's floor is what makes TIME drift toward that record rather than back to
	## a stranger". All three are about TIME. A later TRANSIENT cause still applies its
	## full negative to the CURRENT axis — the sect precedent verbatim, and
	## `test_leaving_moves_regard_down_by_the_leaving_cause` above already holds this
	## module to it at 1.125 - 1.0.
	##
	## ## So the axis dips below the floor by design, and here is the arithmetic
	##
	## `sworn_to_a_clan` is authored +1.5 (`social_cause_catalog.gd:276`) but arrives
	## scaled by `ClanGate.recognition_scale`, which at purity 0.5 reads 0.25 + 0.75 *
	## 0.5 = 0.625 — so one admission is worth **+0.9375**. `left_a_clan` is authored
	## -1.0 (`social_cause_catalog.gd:278`) and applied at the DEFAULT scale of 1.0,
	## because `leave` has already closed the membership and the cost of walking out must
	## not depend on a lineage that is over. Every pair therefore nets **-0.0625**, and
	## `standing` is below zero after N >= 2 cycles at every purity the hinge can produce
	## below 0.6667 (purity 0.6). `standing > 0` is not a property this mechanism has; it
	## is arithmetic that can never be satisfied, so asserting it was the bug.
	assert_eq(
		bond.causes.get(String(ClanApi.CAUSE_SWORN), 0) == cycles,
		true,
		"the house recorded all twelve admissions"
	)
	assert_eq(bond.standing_floor > 0.0, true, "and a positive floor survived them")
	# The floor is not merely positive, it is held at the ONE admission the very first
	# cycle recorded — `maxf` never lets a later, lower cycle walk it down. Read off
	# `_weighed`, the same mechanism the tests above assert, rather than at a literal, so
	# retuning `sworn_to_a_clan` or `UNSCALED` moves this bar along with the curve.
	assert_almost_eq(
		bond.standing_floor, _weighed(0.5), "at the weight one admission through the hinge recorded"
	)
	## ## The ceiling is the ladder's OWN ANSWER, not one of its constants
	##
	## `classify` returns at `distinct_causes < FRIEND_DISTINCT_CAUSES` before it reads
	## standing at all, so a one-kind bond cannot be a friendship at ANY total. The
	## `standing < FRIEND_AT` this replaces was that same property written as a tuned
	## constant, and a pure carrier reached it exactly: at purity 1.0 the hinge is 1.0,
	## each cycle nets +0.5, and twelve cycles land on standing 6.0 — not `< 6.0`. The
	## class cannot be that unlucky, so the class is what is asked.
	assert_eq(
		(
			SocialBondClass.POSITIVE.find(bond.bond_class())
			< SocialBondClass.POSITIVE.find(SocialBondClass.FRIEND)
		),
		true,
		"and one kind of act never reaches what two kinds would buy"
	)
	assert_eq(
		bond.distinct_kinds() < SocialBondClass.FRIEND_DISTINCT_CAUSES,
		true,
		"so however high the standing sums, the ladder cannot promote it to confidant"
	)
	assert_eq(index, cycles, "and the loop really did run twelve times")


# --- Re-joining a house is additive, and that is `social`'s arithmetic ----------


## Deliberately a property of `social` rather than of `clan`: a house that admits the
## same actor twice records two acts, and this module adds no dedupe of its own — a
## second copy of `social`'s arithmetic here is precisely the ADR 0066 failure mode the
## bridge exists to avoid.
func test_a_second_house_replaces_the_membership_and_the_first_row_is_untouched() -> void:
	var actor := _member(0.5, 40)
	assert_eq(ClanApi.clan_of(actor), HOUSE, "first house")
	ClanApi.join(actor, RIVAL, 40)
	assert_eq(ClanApi.clan_of(actor), RIVAL, "which replaced it")
	# The first house's row stands: it recorded an act that happened, and `social`
	# forgets a bond only when something asks it to. Both rows read the same weight
	# because `open()` founds RIVAL on the same line at the same purity.
	assert_almost_eq(_regard(actor, HOUSE), _weighed(0.5), "the first house holds its opinion")
	assert_almost_eq(_regard(actor, RIVAL), _weighed(0.5), "and so does the second")
