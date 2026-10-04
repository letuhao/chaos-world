extends TestCase

## `household_heir_registered` is reachable from PRODUCTION — the gap BL-0803 filed.
##
## `ClanHeir.register` shipped with zero production callers, so the fact it writes was
## watched by four authored quests (`the_account_left_open`, `the_station_you_held`,
## `the_terms_you_drafted`, `the_severed_calling`) and by the `oaths_sworn` destiny
## counter, and **nothing in the game could ever clear it**. ADR 0137 calls that a CONTENT
## defect rather than a missing producer only when no system models the act — here the act
## is modelled and simply had no caller, so the fix is a caller at the moment it belongs to.
##
## ## The moment, and why it is the ADMISSION
##
## There is no succession screen in this program, and `ClanApi` is already at
## `rules.MAX_FACADE_PUBLIC_METHODS`, so no "nominate an heir" button was ever available to
## wire. What exists, and what ADR 0064/0083 already make the house's own act, is
## **admission**: a clan is a lineage across generations, so the house admitting a member
## is stating where its line goes next, and the first admission into a house that publishes
## `heir` is what names the successor. `ClanApi.join` therefore calls `ClanHeir.register` —
## the OWNER of the moment writes (ADR 0113); nothing polls for an heir.
##
## ## These cases drive the PRODUCER, not the internal verb
##
## The load-bearing assertions below go through `ClanApi.join` and never through
## `ClanHeir.register` directly. A test that called the verb itself would keep passing if
## the wiring were deleted, which is exactly how this gap survived an audit.

const HOUSE := &"t_house"
## A house whose ladder stops at `core` and publishes no `heir` office at all.
const HOUSE_NO_HEIR := &"t_house_plain"
const HEIR := ClanHeir.HEIR_RANK


func setup() -> void:
	ClanFixtureCatalog.install([ClanFixtureCatalog.open(HOUSE), _house_without_an_heir()])


## A house whose ladder stops at `core`: it publishes no `heir` office, so no admission to
## it can ever name a successor. Built here rather than in the shared fixture because this
## is the ONE case in the module that needs a shortened ladder, and `LADDER` is the
## conventional `outer, inner, core, heir, head` every other fixture assumes.
func _house_without_an_heir() -> ClanDef:
	var def := ClanDef.new()
	def.id = HOUSE_NO_HEIR
	def.display_name = "A house with no heir office"
	def.description = "A fixture clan whose register has no column for a successor."
	def.founding_bloodline = &"hearthborn"
	def.min_purity = 0.0
	def.ranks = [&"outer", &"inner", &"core"] as Array[StringName]
	def.standing_bands = [0, 15, 40] as Array[int]
	return def


func teardown() -> void:
	ClanFixtureCatalog.teardown()


func _actor(actor_id: StringName) -> Actor:
	var actor := (
		Actor
		. new(
			actor_id,
			{
				Stat.PHYSIQUE: 10.0,
				Stat.WILL: 5.0,
				Stat.SPIRIT: 4.0,
				Stat.AGILITY: 6.0,
				Stat.COMPREHENSION: 3.0,
				Stat.APTITUDE: 3.0,
			}
		)
	)
	ClanApi.attach(actor)
	BloodlineApi.attach(actor)
	BloodlineApi.set_purity(actor, &"hearthborn", 0.5)
	return actor


# --- the wiring, which is the whole point --------------------------------------


## The one production path: a plain `join` records the fact with nothing else called.
func test_being_admitted_to_a_house_names_you_its_heir() -> void:
	var actor := _actor(&"newcomer")

	# Before: a bare actor is in no house, so the gate cannot already be satisfied. This
	# is half (b) of the gate-soundness rule — the fact must NOT pass for a fresh actor.
	assert_eq(WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED), 0, "no register yet")
	assert_eq(ClanApi.clan_of(actor), &"", "and no house either")

	var admitted := ClanApi.join(actor, HOUSE)

	assert_eq(bool(admitted["ok"]), true, "the house admitted the member")
	assert_eq(
		WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED),
		1,
		"the ADMISSION is what records the fact — no internal verb was called by hand"
	)
	assert_eq(ClanApi.rank_of(actor), HEIR, "and the member holds the rung it was given")


## The gate is non-trivial and satisfiable: it passes on an act and only on an act.
func test_the_fact_is_not_already_present_on_a_bare_actor_but_the_admission_clears_it() -> void:
	var actor := _actor(&"newcomer")
	assert_eq(WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED), 0, "not already true")
	ClanApi.join(actor, HOUSE)
	assert_eq(
		WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED),
		1,
		"a legal prior state — a member of no house — can reach it by being admitted"
	)


## A refusal writes nothing. The admission that does not land must not name an heir, or
## the fact would describe a membership that does not exist.
func test_a_refused_admission_records_no_heir() -> void:
	var actor := _actor(&"turnaway")

	# An unknown house id: admission refuses on `unmet` before any write.
	var refused := ClanApi.join(actor, &"t_house_that_does_not_ship")

	assert_eq(bool(refused["ok"]), false, "the house does not exist, so nobody was admitted")
	assert_eq(ClanApi.clan_of(actor), &"", "and the actor belongs to no house")
	assert_eq(
		WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED),
		0,
		"a refused admission is not a succession decision"
	)


## A house that publishes no `heir` rung never gets a fact claiming one exists. This is
## `ClanHeir.R_NO_HEIR_RANK` reached from production rather than from a test.
func test_a_house_with_no_heir_rung_never_names_an_heir() -> void:
	var actor := _actor(&"plain_child")

	var admitted := ClanApi.join(actor, HOUSE_NO_HEIR)

	assert_eq(bool(admitted["ok"]), true, "the house admitted the member")
	assert_ne(ClanApi.rank_of(actor), HEIR, "and it published no heir office to fill")
	assert_eq(
		WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED),
		0,
		"so the register says nothing about this house at all"
	)


## The ledger is monotone: a member who is already the heir is not re-registered by a
## second admission, and `already_heir` is the named refusal that keeps it that way.
func test_a_member_already_registered_is_not_registered_a_second_time() -> void:
	var actor := _actor(&"first_child")
	ClanApi.join(actor, HOUSE)
	assert_eq(WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED), 1, "named once")

	# Re-admitted to the same house, standing raised: a second join of the same member.
	ClanApi.join(actor, HOUSE, 10)

	assert_eq(
		WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED),
		1,
		"the same succession decision written twice is still one decision"
	)
	assert_eq(
		String(ClanHeir.register(actor)["reason"]),
		ClanHeir.R_ALREADY_HEIR,
		"and the verb itself names the refusal that produced it"
	)


## Two members admitted to the same house are two admissions, so the second is refused
## rather than swallowed — and the second member is left where the house put them.
func test_a_second_member_is_not_named_heir_over_the_first() -> void:
	var first := _actor(&"first_child")
	var second := _actor(&"second_child")
	ClanApi.join(first, HOUSE)

	ClanApi.join(second, HOUSE)

	assert_eq(ClanApi.rank_of(first), HEIR, "the first admission named the successor")
	assert_eq(
		WorldFact.count(second, ClanFacts.FACT_HEIR_REGISTERED),
		0,
		"and the second member was refused, so their own ledger says nothing"
	)


## Leaving does not erase the register. The succession decision is a historical fact about
## the world, not a mirror of a membership, so an actor who leaves still carries it — which
## is what makes the quest step a thing that HAPPENED rather than a thing that is true now.
func test_leaving_the_house_does_not_erase_the_record() -> void:
	var actor := _actor(&"departing")
	ClanApi.join(actor, HOUSE)
	assert_eq(WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED), 1, "registered")

	assert_eq(ClanApi.leave(actor), true, "the member walked out")

	assert_eq(ClanApi.clan_of(actor), &"", "they belong to no house now")
	assert_eq(
		WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED),
		1,
		"and the register they were written into did not close behind them"
	)