extends TestCase

## The organization-progression capability, asserted on its own terms (D11,
## ADR 0922). The suite is the D3 half — `InstitutionContract.register` runs
## `contract_findings()` at load — and this file drives the same body plus the
## rules a registration-time probe cannot express.
##
## ## What this file is really guarding
##
## ADR 0084: an institution grants recognition, access and transmission, and
## NEVER power. Growth is the newest place a stat could sneak in, so the cases
## below pin the closed unlock vocabulary from both sides: the measurement that
## refuses a `standing_cap` raise (power below the percent's saturation, nothing
## above it — see the capability's class note), and the method-list scan that
## fails the moment a power verb is added here. The counter moves by exactly the
## work done, and time alone earns nothing.
##
## ## Every loop in this file is a `for`
##
## There is not one `while`. The walks are over fixed probe tables, over
## `get_method_list()`, or over a literal `range`; none appends to the container
## it walks, so no bound can grow in lockstep with its own body and
## `test_no_unbounded_wait.gd` has nothing to reject.

## The verbs a progression capability must never grow (ADR 0084's own list,
## plus the two shapes this design's rejection argument names). Checked against
## the live method list rather than trusted, because `tools arch` cannot see a
## method that does not exist.
const FORBIDDEN_VERBS: Array[String] = [
	"grant_stat",
	"grant_attribute",
	"set_base",
	"add_base",
	"power_up",
	"buff",
	"apply_modifier",
	"multiplier",
	"realm",
]


func setup() -> void:
	# The dispatcher is process state and every suite shares one process, so it
	# is cleared on BOTH ends: `setup` clears what a previous suite left,
	# `teardown` clears what this one does.
	InstitutionContract.instance().clear()
	expect_assertions(3)


func teardown() -> void:
	InstitutionContract.instance().clear()


# --- identity and the refusal vocabulary ------------------------------------------


## The capability names itself, passes its own suite, and publishes the reasons
## its verbs can return — the family's plus its own, assembled at read time so a
## second hand-maintained list cannot drift from the constants.
func test_the_capability_names_itself_and_passes_its_own_suite() -> void:
	var impl := Progressive.new()
	assert_eq(String(impl.capability_id()), "progressive", "the capability names itself")
	assert_eq(impl.contract_findings().is_empty(), true, "and passes its own suite")
	var reasons := impl.reasons()
	for own in impl.own_reasons():
		assert_eq(reasons.has(own), true, "own reason '%s' is in the assembled set" % own)
	assert_eq(
		reasons.has(InstitutionCapability.R_MALFORMED), true, "and the family's reasons ride along"
	)


# --- the counter ------------------------------------------------------------------


## The counter moves by exactly `served + admitted` and by nothing else, and an
## IDLE organization earns nothing EVEN WITH `periods` PRESENT: time is not a
## source, which is what makes growth a record of work rather than a clock
## (DEF-0111).
func test_the_counter_moves_by_exactly_the_activity_and_never_by_time() -> void:
	var impl := Progressive.new()
	var probe := _probe()
	var planned := impl.accrue(probe.duplicate(true))
	assert_eq(bool(planned.get("ok", false)), true, "an active organization accrues")
	var gained := int(probe["served"]) + int(probe["admitted"])
	var plan: Dictionary = planned["plan"]
	assert_eq(int(plan["gained"]), gained, "gained is served plus admitted")
	assert_eq(
		int(plan["points"]), int(probe["points"]) + gained, "and the counter moved by exactly it"
	)
	var idle := probe.duplicate(true)
	idle["served"] = 0
	idle["admitted"] = 0
	idle["periods"] = 99
	assert_eq(
		String(impl.accrue(idle).get("reason", "")),
		Progressive.R_NOTHING_EARNED,
		"an idle organization earns nothing, periods or not"
	)
	var bare := probe.duplicate(true)
	bare["milestones"] = []
	assert_eq(
		String(impl.accrue(bare).get("reason", "")),
		Progressive.R_NO_MILESTONES_AUTHORED,
		"and a counter with nothing to unlock refuses the write"
	)


# --- what growth buys, and what it must never buy ---------------------------------


## A crossing milestone opens its authored ACCESS (positions, capabilities) and
## its authored CAPACITY (member_capacity), while an unreached one opens none of
## them. And the power-smuggling row is refused BY NAME: `standing_cap` is
## outside the closed set because raising it is power below the percent's
## saturation and nothing above it (ADR 0084 — the capability's class note
## carries the measurement).
func test_a_milestone_opens_access_and_capacity_and_never_a_stat() -> void:
	var impl := Progressive.new()
	var probe := _probe()
	var crossed := probe.duplicate(true)
	crossed["served"] = 4
	var planned := impl.accrue(crossed)
	assert_eq(bool(planned.get("ok", false)), true, "the second milestone is crossed")
	var plan: Dictionary = planned["plan"]
	assert_eq(
		(plan["opened_positions"] as Array).has("probe_office"),
		true,
		"the first milestone's position stays open"
	)
	assert_eq(
		(plan["opened_capabilities"] as Array).has("probe_contract"),
		true,
		"and the crossing milestone's capability opened"
	)
	assert_eq(
		int(plan["member_capacity"]),
		int(probe["base_capacity"]) + 4,
		"and its authored capacity landed on the base"
	)
	var smuggled := probe.duplicate(true)
	smuggled["milestones"] = [{"at": 3, "standing_cap": 200}]
	var refused := impl.accrue(smuggled)
	assert_eq(
		String(refused.get("reason", "")),
		Progressive.R_UNKNOWN_UNLOCK,
		"a standing_cap milestone is refused by name"
	)
	assert_eq(String(refused.get("key", "")), "standing_cap", "and the refusal names the key")
	var smuggled_opens := probe.duplicate(true)
	smuggled_opens["milestones"] = [{"at": 3, "opens": {"stats": ["poise"]}}]
	assert_eq(
		String(impl.progress(smuggled_opens).get("reason", "")),
		Progressive.R_UNKNOWN_UNLOCK,
		"and so is a stat list inside the opens map"
	)


# --- the authored table is graded before anything is read -------------------------


## Every table fault the capability can answer on its own, each refused BY NAME
## and none of them reading a value: an out-of-order table, an unreadable `at`, a
## row outside the closed keys, an `opens` list that is not a list, and a table
## past `MAX_MILESTONES`. The last fill is toward a FIXED count with an
## unconditional append — the accepted shape `test_no_unbounded_wait.gd`
## recognises.
func test_the_authored_table_is_graded_before_anything_is_read() -> void:
	var impl := Progressive.new()
	var probe := _probe()
	var out_of_order := probe.duplicate(true)
	out_of_order["milestones"] = [{"at": 5}, {"at": 2}]
	assert_eq(
		String(impl.accrue(out_of_order).get("reason", "")),
		Progressive.R_MILESTONES_NOT_INCREASING,
		"an out-of-order table has two answers and is refused"
	)
	var unreadable := probe.duplicate(true)
	unreadable["milestones"] = [{"at": "soon"}]
	assert_eq(
		String(impl.accrue(unreadable).get("reason", "")),
		InstitutionCapability.R_MALFORMED,
		"an unreadable threshold is malformed"
	)
	var bad_list := probe.duplicate(true)
	bad_list["milestones"] = [{"at": 3, "opens": {"positions": "clerk"}}]
	assert_eq(
		String(impl.accrue(bad_list).get("reason", "")),
		InstitutionCapability.R_MALFORMED,
		"an id list that is not a list is malformed"
	)
	var not_a_row := probe.duplicate(true)
	not_a_row["milestones"] = ["milestone"]
	assert_eq(
		String(impl.accrue(not_a_row).get("reason", "")),
		InstitutionCapability.R_MALFORMED,
		"a row that is not a map is malformed"
	)
	var too_many: Array = []
	for index in range(Progressive.MAX_MILESTONES + 1):
		too_many.append({"at": index})
	var crowded := probe.duplicate(true)
	crowded["milestones"] = too_many
	assert_eq(
		String(impl.accrue(crowded).get("reason", "")),
		Progressive.R_TOO_MANY_MILESTONES,
		"a table past MAX_MILESTONES is refused"
	)


# --- purity and the one write -----------------------------------------------------


## `progress` is a pure READ — a screen calls it once per frame, so a read that
## wrote would make the bar move under the reader — and `accrue` is the only
## verb that plans a write. Both leave the exact object they were handed
## byte-identical (ADR 0044), and two identical calls answer by TEXT, so no roll
## can be hiding in the comparison.
func test_progress_is_a_pure_read_and_accrue_is_the_only_plan() -> void:
	var impl := Progressive.new()
	var probe := _probe()
	var first := impl.progress(probe.duplicate(true))
	var second := impl.progress(probe.duplicate(true))
	assert_eq(JSON.stringify(first), JSON.stringify(second), "the read is deterministic")
	assert_eq(bool(first.get("ok", false)), true, "and answers")
	assert_eq(int(first["tier"]), 0, "a counter below the first milestone is tier zero")
	assert_eq(int(first["next_points"]), 3, "and next_points names the first milestone")
	var handed := probe.duplicate(true)
	impl.progress(handed)
	assert_eq(JSON.stringify(handed), JSON.stringify(probe), "the read wrote nothing")
	var handed_write := probe.duplicate(true)
	impl.accrue(handed_write)
	assert_eq(JSON.stringify(handed_write), JSON.stringify(probe), "and the plan wrote nothing")


# --- no power verb, structurally --------------------------------------------------


## ADR 0084's guard, restated for a contract: `tools arch` cannot see a method
## that does not exist, so the live method list is read and asserted to contain
## none of the power verbs. A future `grant_stat` fails HERE rather than in
## review.
func test_no_method_here_can_grant_power() -> void:
	var impl := Progressive.new()
	var names: Array[String] = []
	for entry in impl.get_method_list():
		names.append(String(entry["name"]))
	# The scan is non-empty and really sees this class's own verbs, so an empty
	# method list cannot pass as a clean one.
	assert_eq(names.size() > 0, true, "the method list is readable")
	assert_eq(names.has("accrue"), true, "and carries the capability's own verbs")
	var offenders: Array[String] = []
	for method in names:
		for forbidden in FORBIDDEN_VERBS:
			if method.contains(forbidden):
				offenders.append(method)
	assert_eq(offenders.is_empty(), true, "no method name grants power: %s" % str(offenders))


# --- registration and dispatch ----------------------------------------------------


## The capability registers through the same dispatcher a pack's would, is
## handed back by id, and proposes nothing on the lifecycle verbs it does not
## own — the default that keeps a kind carrying it inert rather than wrong.
func test_the_capability_registers_and_the_dispatcher_hands_it_back() -> void:
	var contract := InstitutionContract.instance()
	var registered := contract.register(&"progressive_probe_kind", [Progressive.new()])
	assert_eq(
		bool(registered.get("ok", false)),
		true,
		"a kind carrying progressive registers: %s" % str(registered.get("reason", ""))
	)
	var found := contract.of(&"progressive_probe_kind", &"progressive")
	assert_eq(bool(found.get("has", false)), true, "and the capability is reachable by id")
	assert_eq(found.get("capability") is Progressive, true, "as a live implementation")
	var period := contract.on_period(
		&"progressive_probe_kind", {"kind": "progressive_probe_kind", "institution": "probe"}, 1
	)
	assert_eq(
		bool(period.get("ok", false)),
		true,
		"the lifecycle fold consults it and it proposes nothing"
	)


# --- helpers ----------------------------------------------------------------------


## The fixed probe every case is built from: two authored milestones, a counter
## below the first, and activity that crosses exactly one of them.
func _probe() -> Dictionary:
	return {
		"kind": "contract_probe",
		"institution": "contract_probe",
		"points": 2,
		"base_capacity": 3,
		"served": 2,
		"admitted": 1,
		"milestones":
		[
			{"at": 3, "name": "chartered", "opens": {"positions": ["probe_office"]}},
			{
				"at": 6,
				"name": "established",
				"opens": {"capabilities": ["probe_contract"], "member_capacity": 4},
			},
		],
	}
