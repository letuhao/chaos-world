extends TestCase

## The APPLIER of organization progression, and the NON-TIER proof (D11).
##
## ## What this suite measures
##
## `InstitutionProgression` is the store the counter lives in and the verbs that
## move it, driving `Progressive` unchanged (ADR 0922's decides-never-commits
## split). The cases below pin the store's own rules: a table is GRADED at
## declare, a refusal writes nothing, the counter is per organization, the store
## is bounded and clears idempotently.
##
## ## The reference implementation: The Lantern Exchange, with NO tier code
##
## The last case loads the shipped `lantern_exchange.tres` — a `trading_guild`,
## a kind no tier module owns — registers it in the dispatcher carrying
## `Progressive`, declares it, grows it, and reads back that a milestone opened
## a REAL authored office (`clerk`). **No sect/clan/nation code is loaded or
## named anywhere in this file**, which is the point: growth is a capability any
## kind can claim, exactly as ADR 0922 makes expulsion or teaching.
##
## ## Every loop in this file is a `for`
##
## There is not one `while`. The walks are over fixed probe tables, over a
## literal `range`, or over the shipped def's own authored offices; none appends
## to the container it walks, so no bound can grow in lockstep with its own body
## and `test_no_unbounded_wait.gd` has nothing to reject.

## The shipped trading guild, READ and never mutated. A copy of a `.tres` that
## `load()` has cached would leak into every suite after this one.
const LANTERN := "res://data/packs/guilds/organizations/lantern_exchange.tres"
const LANTERN_ID := &"lantern_exchange"
## The ordinary office the guild authors, and the one the milestone opens: an
## id that names real authored content rather than a probe.
const CLERK := &"clerk"


func setup() -> void:
	# The store and the dispatcher are BOTH process state and the runner drives
	# every suite in ONE process: `setup` clears what a previous suite left,
	# `teardown` clears what this one does.
	InstitutionProgression.clear()
	InstitutionContract.instance().clear()
	expect_assertions(3)


func teardown() -> void:
	InstitutionProgression.clear()
	InstitutionContract.instance().clear()


# --- declare and read -------------------------------------------------------------


## Declaring grades the authored table through the capability and stores it; the
## read answers the whole derived state at zero, from the table and nothing else.
func test_declare_stores_a_graded_table_and_summary_reads_it() -> void:
	var declared := InstitutionProgression.declare(&"fixture_guild", _table(), 2)
	assert_eq(
		bool(declared.get("ok", false)),
		true,
		"the table is declared: %s" % str(declared.get("reason", ""))
	)
	assert_eq(InstitutionProgression.knows(&"fixture_guild"), true, "and the store knows it")
	var read := InstitutionProgression.summary(&"fixture_guild")
	assert_eq(bool(read.get("ok", false)), true, "the read answers")
	assert_eq(int(read["points"]), 0, "a fresh organization stands at zero")
	assert_eq(int(read["tier"]), 0, "below its first milestone")
	assert_eq(int(read["tiers"]), 2, "with the authored table length published")
	assert_eq(int(read["next_points"]), 3, "and the first threshold named")
	assert_eq(int(read["member_capacity"]), 2, "and its authored base capacity read")


## ## Recording activity moves the counter and opens what the milestone authored
##
## The first accrual crosses milestone one (a position); the second crosses
## milestone two (a capability and a capacity). Both go through the capability's
## plan, so the store writes exactly what the contract derived.
func test_record_accrues_the_counter_and_opens_what_the_milestone_authored() -> void:
	assert_eq(
		bool(InstitutionProgression.declare(&"fixture_guild", _table(), 2).get("ok", false)),
		true,
		"the organization is declared"
	)
	var planned := InstitutionProgression.record(&"fixture_guild", 2, 1)
	assert_eq(
		bool(planned.get("ok", false)),
		true,
		"an active organization records: %s" % str(planned.get("reason", ""))
	)
	var plan: Dictionary = planned["plan"]
	assert_eq(int(plan["gained"]), 3, "gained is served plus admitted")
	assert_eq(int(plan["points"]), 3, "and the counter moved by exactly it")
	var first := InstitutionProgression.summary(&"fixture_guild")
	assert_eq(int(first["points"]), 3, "the store kept the new counter")
	assert_eq(int(first["tier"]), 1, "the first milestone was crossed")
	assert_eq(
		(first["opened_positions"] as Array).has("probe_office"),
		true,
		"and its authored position is open"
	)
	assert_eq(int(first["member_capacity"]), 2, "while the unreached milestone's capacity is not")
	var again := InstitutionProgression.record(&"fixture_guild", 3, 0)
	assert_eq(bool(again.get("ok", false)), true, "a second accrual lands")
	var second := InstitutionProgression.summary(&"fixture_guild")
	assert_eq(int(second["points"]), 6, "the counter accumulates rather than resets")
	assert_eq(int(second["tier"]), 2, "the second milestone was crossed")
	assert_eq(
		(second["opened_capabilities"] as Array).has("probe_contract"),
		true,
		"and its authored capability is open"
	)
	assert_eq(int(second["member_capacity"]), 6, "and its capacity landed on the base")


# --- refusals write nothing -------------------------------------------------------


## ADR 0044: an idle accrual is refused by name and the stored counter is
## BYTE-IDENTICAL afterwards; an undeclared organization refuses the write and
## answers `{}` to the read — ADR 0083's FIRST state, never a fabricated zero.
func test_a_refusal_writes_nothing() -> void:
	assert_eq(
		bool(InstitutionProgression.declare(&"fixture_guild", _table(), 0).get("ok", false)),
		true,
		"the organization is declared"
	)
	var idle := InstitutionProgression.record(&"fixture_guild", 0, 0)
	assert_eq(
		String(idle.get("reason", "")),
		Progressive.R_NOTHING_EARNED,
		"an idle accrual is refused by name"
	)
	assert_eq(
		int(InstitutionProgression.summary(&"fixture_guild")["points"]),
		0,
		"and the counter did not move"
	)
	var stranger := InstitutionProgression.record(&"nobody_declared_this", 3, 0)
	assert_eq(
		String(stranger.get("reason", "")),
		InstitutionProgression.R_UNKNOWN_RECORD,
		"an undeclared organization refuses the write"
	)
	assert_eq(
		InstitutionProgression.summary(&"nobody_declared_this").is_empty(),
		true,
		"and the read answers the empty first state"
	)


# --- declare refuses a broken table -----------------------------------------------


## The table is graded AT THE SEAM, so a milestone that would smuggle a stat
## surface, an out-of-order table, a duplicate declare and an empty id each
## refuse by name and leave the store without a row.
func test_declare_grades_the_table_and_refuses_a_broken_one() -> void:
	var smuggled := InstitutionProgression.declare(&"smuggler", [{"at": 3, "standing_cap": 200}])
	assert_eq(
		String(smuggled.get("reason", "")),
		Progressive.R_UNKNOWN_UNLOCK,
		"a standing_cap milestone is refused at declare"
	)
	assert_eq(InstitutionProgression.knows(&"smuggler"), false, "and no row exists")
	var unordered := InstitutionProgression.declare(&"unordered", [{"at": 5}, {"at": 2}])
	assert_eq(
		String(unordered.get("reason", "")),
		Progressive.R_MILESTONES_NOT_INCREASING,
		"an out-of-order table is refused at declare"
	)
	assert_eq(
		bool(InstitutionProgression.declare(&"duplicate", _table()).get("ok", false)),
		true,
		"the first declare"
	)
	assert_eq(
		String(InstitutionProgression.declare(&"duplicate", _table()).get("reason", "")),
		InstitutionProgression.R_ALREADY_DECLARED,
		"and a second is refused, never idempotent"
	)
	assert_eq(
		String(InstitutionProgression.declare(&"").get("reason", "")),
		InstitutionProgression.R_UNKNOWN_INSTITUTION,
		"an empty id names nothing"
	)


# --- the store is bounded and clears ----------------------------------------------


## The store carries at most `RECORD_LIMIT` organizations and clears
## idempotently — both halves are part of the surface because the runner drives
## every suite in ONE process. The fill is a `for` over a literal `range`
## appending toward a FIXED count, the accepted shape.
func test_the_store_is_bounded_and_clears_idempotently() -> void:
	for index in range(InstitutionProgression.RECORD_LIMIT):
		var answer := InstitutionProgression.declare(StringName("limit_%d" % index), _table())
		assert_eq(bool(answer.get("ok", false)), true, "row %d is declared" % index)
	var overflow := InstitutionProgression.declare(&"one_too_many", _table())
	assert_eq(
		String(overflow.get("reason", "")),
		InstitutionProgression.R_RECORD_LIMIT,
		"a table nobody bounds is a table every read walks, so the limit refuses"
	)
	assert_eq(
		InstitutionProgression.clear(),
		InstitutionProgression.RECORD_LIMIT,
		"clear answers its rows"
	)
	assert_eq(InstitutionProgression.clear(), 0, "a second clear is idempotent")
	assert_eq(InstitutionProgression.knows(&"limit_0"), false, "and the rows are gone")


# --- the reference implementation: a guild with NO tier code -----------------------


## ## The trading guild GROWS with no tier code
##
## `The Lantern Exchange` is a `trading_guild`: it is not a sect, it has no
## module, and nothing in this path loads one. The case registers the kind in
## the dispatcher carrying `Progressive`, declares the organization, records the
## work, and reads back that a milestone opened the `clerk` office — an id the
## def really authors, checked against the def rather than asserted as a string.
func test_a_non_tier_guild_grows_with_no_tier_code() -> void:
	var def := load(LANTERN) as InstitutionDef
	assert_ne(def, null, "the shipped guild loads")
	assert_eq(String(def.kind), "trading_guild", "a kind no tier module owns")
	for tier_kind in ["sect", "clan", "nation"]:
		assert_ne(String(def.kind), tier_kind, "and not one of the tier kinds")
	assert_eq(def.has_position(CLERK), true, "the office the milestone opens is authored")
	var contract := InstitutionContract.instance()
	var registered := contract.register(&"trading_guild", [Progressive.new()])
	assert_eq(
		bool(registered.get("ok", false)),
		true,
		"the guild claims the capability with no tier module: %s" % str(registered)
	)
	var found := contract.of(&"trading_guild", &"progressive")
	assert_eq(bool(found.get("has", false)), true, "and the dispatcher hands it back")
	var impl := found["capability"] as Progressive
	var dispatched := (
		impl
		. progress(
			{
				"kind": "trading_guild",
				"institution": String(LANTERN_ID),
				"points": 2,
				"milestones": _guild_table(),
				"base_capacity": 0,
			}
		)
	)
	assert_eq(bool(dispatched.get("ok", false)), true, "the dispatched instance reads")
	var declared := InstitutionProgression.declare(LANTERN_ID, _guild_table())
	assert_eq(
		bool(declared.get("ok", false)),
		true,
		"the guild's table is declared: %s" % str(declared.get("reason", ""))
	)
	var planned := InstitutionProgression.record(LANTERN_ID, 2, 0)
	assert_eq(
		bool(planned.get("ok", false)),
		true,
		"two duty periods of work are recorded: %s" % str(planned.get("reason", ""))
	)
	var read := InstitutionProgression.summary(LANTERN_ID)
	assert_eq(int(read["tier"]), 1, "the guild grew past its first milestone")
	assert_eq(
		(read["opened_positions"] as Array).has(String(CLERK)),
		true,
		"and the milestone opened the clerk's office"
	)


# --- helpers ----------------------------------------------------------------------


## The fixed probe table: two milestones, one per unlock axis, with thresholds
## the cases cross one at a time.
func _table() -> Array:
	return [
		{"at": 3, "name": "chartered", "opens": {"positions": ["probe_office"]}},
		{
			"at": 6,
			"name": "established",
			"opens": {"capabilities": ["probe_contract"], "member_capacity": 4},
		},
	]


## The table the guild is grown through: the same shape, with the SHIPPED
## guild's own authored office id as the thing that opens.
func _guild_table() -> Array:
	return [
		{"at": 2, "name": "chartered", "opens": {"positions": [String(CLERK)]}},
	]
