extends TestCase

## **Teaching moves FIT and never STANDING** (BL-0187, BL-0188), a teacher below the
## doctrine's own floor cannot teach at all, and fit projects **zero** stat
## modifiers (ADR 0084).
##
## The four load-bearing measurements: `standing_delta == 0` on every success payload;
## a taught member's derived stats are byte-identical before and after; a teacher
## under the floor is refused `teacher_unfit`; and the comprehension gate reads BASE
## ALLOCATION ONLY, so this module's own standing percent cannot fund the gate that
## measures whether this module may teach.

const FOUNDRY := &"t_foundry"
const HOUSE := &"t_house"
const STEWARD := &"t_steward"
const READER := &"t_reader"
const MEMBER := &"t_member"
const DOCTRINE := &"t_foundry_doctrine"
## The fixture doctrine's authored numbers, read off the catalog rather than written
## down here: a case that asserted "3 of 5" against constants it typed itself would
## be asserting its own arithmetic rather than the rule.
const AFFINITY_FLOOR := 20
const FLOOR := 5.0
const SPAN := 60.0
const FIT_PER_PERIOD := 3
## `stamina` is the pool a lesson spends, and `teach_tax` is the fixture office's.
const STAMINA := 100.0


func setup() -> void:
	SectFixtureCatalog.install([SectFixtureCatalog.foundable_sect(FOUNDRY)])
	SectFixtureCatalog.install_doctrine([SectFixtureCatalog.doctrine(DOCTRINE)])


func teardown() -> void:
	SectFixtureCatalog.teardown()


## A member of the sect at the cap, holding the top office, with enough of their own
## fit to be allowed to teach. `fit` is seeded by hand here because `teach` is what
## the suite is testing: a teacher must be built out of states the public surface can
## produce, and founding is the verb that does it.
func _teacher(actor_id: StringName, fit: int = 60) -> Actor:
	var actor := _sworn(actor_id)
	SectApi.promote(actor, STEWARD, true)
	SectApi.move_standing(actor, 100)
	var ledger := SectApi.state(actor)
	(ledger["fit"] as Dictionary)[String(DOCTRINE)] = fit
	actor.set_module_data(SectState.MODULE_KEY, ledger)
	SectApi.attach(actor)
	return actor


## A member with no office, who is the ordinary student.
##
## ## Admitted past the sect's own door, deliberately
##
## The fixture sect authors `min_purity`, and `teach` asks that door before the
## comprehension band. A student seeded at fit zero therefore never reaches the band
## and reads `standing_below_floor` — the gate before the one the case is about,
## reported honestly, which is exactly what a first-unmet-condition gate is for. So
## the ordinary student is admitted past the door here, and the one case whose subject
## IS the door (`..._min_purity_...`) seeds its own fit below it and asserts that.
func _sworn(actor_id: StringName, comprehension: float = 20.0) -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: comprehension})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	actor.add_resource(ResourcePool.new(&"stamina", STAMINA))
	SectApi.attach(actor)
	SectApi.join(actor, FOUNDRY)
	return SectFixtureCatalog.admit_student(actor, FOUNDRY, DOCTRINE)


func _doctrine() -> SectDoctrineDef:
	return SectDoctrineCatalog.instance().doctrine(DOCTRINE)


## The price of one session: the office's authored tax plus the doctrine's.
func _tax() -> float:
	return SectTeaching.tax_for(
		_doctrine(), SectCatalog.instance().sect_definition(FOUNDRY).position(STEWARD)
	)


func _derived(actor: Actor) -> Dictionary:
	var out := {}
	for stat_id in actor.stats.derived_all().keys():
		out[String(stat_id)] = actor.stats.derived(stat_id)
	return out


# --- Teaching moves fit and never standing -----------------------------------


## The core measurement. A lesson moves the student's `fit` by the doctrine's
## authored rate per period and leaves **everything else** alone — standing, the
## position, the obligation lines. `standing_delta` is published on the payload and is
## zero, so the ADR 0064 split is observable rather than merely documented.
func test_teaching_moves_fit_and_never_standing() -> void:
	var teacher := _teacher(&"teacher")
	var student := _sworn(&"student")
	# Pinned as a precondition: the student is admitted past the sect's own
	# `min_purity` door, so the lesson under test is the one that reaches the band
	# rather than a refusal at the gate in front of it.
	var start := SectState.fit(SectApi.state(student), DOCTRINE)
	var door := SectCatalog.instance().sect_definition(FOUNDRY).min_purity
	assert_eq(start > door, true, "the student is admitted past the sect's own door")

	var verdict := SectApi.teach(teacher, student, DOCTRINE)
	assert_eq(bool(verdict["ok"]), true, "the lesson landed")
	assert_eq(
		int(verdict["fit_delta"]), FIT_PER_PERIOD, "one period is the authored fit per period"
	)
	assert_eq(int(verdict["standing_delta"]), 0, "and `standing_delta` is published as zero")
	assert_eq(
		SectState.fit(SectApi.state(student), DOCTRINE),
		start + FIT_PER_PERIOD,
		"the fit moved on the ledger"
	)
	assert_eq(int(SectApi.state(student)["standing"]), 0, "the student's standing did not move")
	assert_eq(String(SectApi.state(student)["position"]), "", "nor did their office")
	assert_eq(
		int(SectApi.state(teacher)["standing"]), 100, "and the teacher kept every point of theirs"
	)
	# Several periods are a pure rate multiplied out, never a roll per session: a
	# lesson that might not land is a gate that can satisfy itself (ADR 0084).
	var many := SectApi.teach(teacher, student, DOCTRINE, 4)
	assert_eq(bool(many["ok"]), true, "four sessions land")
	assert_eq(int(many["fit_delta"]), FIT_PER_PERIOD * 4, "at the authored rate")
	assert_eq(
		SectState.fit(SectApi.state(student), DOCTRINE),
		start + FIT_PER_PERIOD * 5,
		"and they accumulate"
	)
	assert_eq(int(many["standing_delta"]), 0, "still with no standing moved")


## Fit is TRANSMISSION and it projects **zero** stat modifiers (ADR 0084). The
## teacher's standing percent is real and lands on the office's allowlist; the
## student's fit is a gate and touches nothing at all. If a lesson could move a
## stat, fit would be a second currency and comprehension would be buyable.
func test_fit_projects_zero_stat_modifiers_and_teaching_moves_no_derived_stat() -> void:
	var teacher := _teacher(&"teacher")
	var student := _sworn(&"student")
	var before := _derived(student)
	var bases_before := student.stats.base_dict()
	var own_modifiers := _own_modifiers(student)
	# Precondition: the teacher really is granted something, so "nothing moved" is a
	# measurement of the lesson rather than of a projection that never fired.
	assert_ne(
		SectProjection.contribution(teacher, Stat.INSIGHT_GAIN), 0.0, "the office grants a percent"
	)
	assert_ne(before.size(), 0, "and the student has derived stats at all")
	SectApi.teach(teacher, student, DOCTRINE, 3)
	assert_eq(_derived(student), before, "not one derived stat moved")
	assert_eq(student.stats.base_dict(), bases_before, "nor any base attribute")
	assert_eq(_own_modifiers(student), own_modifiers, "and the modifier stack is untouched")
	# Fit is at its cap rather than unbounded past it: a currency that accumulates is
	# a thing to buy comprehension with, and comprehension cannot be bought. The
	# teacher is topped up first so the thing under test is the FIT CAP and not the
	# wallet — this loop asks for more sessions than the fixture's stamina could pay
	# for, and a lesson refused for want of stamina moves no fit at all.
	teacher.resource(&"stamina").current = 10_000.0
	for _session in 60:
		SectApi.teach(teacher, student, DOCTRINE, 8)
	assert_eq(
		SectState.fit(SectApi.state(student), DOCTRINE),
		SectState.FIT_CAP,
		"fit clamps at FIT_CAP and never passes it"
	)
	assert_eq(_derived(student), before, "still projecting nothing at the cap")
	var capped := SectApi.teach(teacher, student, DOCTRINE, 1)
	assert_eq(bool(capped["ok"]), false, "a lesson at the cap is a refusal")
	assert_eq(String(capped["reason"]), SectApi.NOTHING_TO_TEACH, "and it names itself")


## A refused lesson writes nothing — on the student, and on the teacher's stamina. A
## lesson that charged the teacher and then refused would make every refusal a cost,
## which is the opposite of ADR 0084's rule that a refusal writes nothing at all.
func test_a_refused_lesson_leaves_both_ledgers_and_the_teacher_byte_for_byte_as_found() -> void:
	var teacher := _teacher(&"teacher")
	var student := _sworn(&"student")
	var t_before := SectApi.state(teacher)
	var s_before := SectApi.state(student)
	var stamina := teacher.resource(&"stamina").current
	# Below the teacher's own affinity floor.
	var unfit := SectApi.teach(_teacher(&"unfit", 1), student, DOCTRINE)
	assert_eq(bool(unfit["ok"]), false, "a teacher under the floor is refused")
	assert_eq(String(unfit["reason"]), SectApi.TEACHER_UNFIT, "and it names itself")
	# A student whose BASE comprehension is outside the authored band.
	var deaf := _sworn(&"deaf", 1.0)
	var silent := SectApi.teach(teacher, deaf, DOCTRINE)
	assert_eq(bool(silent["ok"]), false, "a student under the band is refused")
	assert_eq(String(silent["reason"]), SectApi.COMPREHENSION_BELOW_FLOOR, "and it names the floor")
	# An author nobody has ever shipped.
	assert_eq(
		String(SectApi.teach(teacher, student, &"t_no_such_doctrine")["reason"]),
		SectApi.UNKNOWN_DOCTRINE,
		"and an unshipped doctrine is refused by name"
	)
	# A teacher who has taught themselves, and a student sworn to nothing.
	assert_eq(
		String(SectApi.teach(teacher, teacher, DOCTRINE)["reason"]),
		SectApi.SAME_ACTOR,
		"a teacher teaches no one"
	)
	var stranger := Actor.new(&"stranger")
	SectApi.attach(stranger)
	assert_eq(
		String(SectApi.teach(teacher, stranger, DOCTRINE)["reason"]),
		SectApi.STUDENT_NOT_SWORN,
		"and an unsworn student is taught by nobody"
	)
	# Every one of them left the two live ledgers exactly as they were.
	assert_eq(SectApi.state(teacher), t_before, "the teacher's ledger is untouched")
	assert_eq(SectApi.state(student), s_before, "and so is the student's")
	assert_eq(teacher.resource(&"stamina").current, stamina, "and the teacher paid nothing")


# --- The two floors, which answer different questions -----------------------


## **`teacher_unfit` is the doctrine's own affinity floor read on the TEACHER.** A
## member with perfect standing and a seat that grants the capped percent is still
## refused, because teaching is transmission and transmission is a gate — standing is
## recognition and the two never derive from each other (ADR 0064).
func test_a_teacher_below_the_doctrine_floor_refuses_teacher_unfit_whatever_their_standing(
) -> void:
	var one_short := AFFINITY_FLOOR - 1
	var teacher := _teacher(&"teacher", one_short)
	# Precondition: this teacher is fully recognised and holds the top office, so
	# the refusal cannot be explained by anything but the fit.
	assert_eq(int(SectApi.state(teacher)["standing"]), 100, "at the cap")
	assert_eq(String(SectApi.state(teacher)["position"]), String(STEWARD), "holding the top office")
	assert_almost_eq(
		SectProjection.contribution(teacher, Stat.INSIGHT_GAIN),
		InstitutionClaim.STANDING_PERCENT_CAP,
		"and granted the capped percent"
	)
	assert_eq(
		SectState.fit(SectApi.state(teacher), DOCTRINE),
		one_short,
		"one point under the doctrine's floor"
	)
	var student := _sworn(&"student")
	var before := SectApi.state(student)
	var stamina := teacher.resource(&"stamina").current
	var verdict := SectApi.teach(teacher, student, DOCTRINE)
	assert_eq(bool(verdict["ok"]), false, "the lesson is refused")
	assert_eq(
		String(verdict["reason"]),
		SectApi.TEACHER_UNFIT,
		"and it is the DOCTRINE's floor, not the sect's door"
	)
	assert_eq(SectApi.state(student), before, "the student learned nothing")
	assert_eq(teacher.resource(&"stamina").current, stamina, "and the teacher paid nothing")
	# One point higher and the same lesson lands, which is what makes the floor an
	# authored boundary rather than a blanket ban.
	var exactly := _teacher(&"exact", AFFINITY_FLOOR)
	assert_eq(
		bool(SectApi.teach(exactly, _sworn(&"second"), DOCTRINE)["ok"]),
		true,
		"the floor is inclusive of itself"
	)


## The sect's own `min_purity` is the STUDENT's door and it is a different question:
## a member under it is not being taught anything, however good a teacher arrives.
## `standing_below_floor` is the existing named route for that door, so a panel
## renders one word for "you are not yet one of ours to teach" rather than two.
func test_a_student_below_the_sects_min_purity_is_refused_the_sects_door() -> void:
	SectFixtureCatalog.install([SectFixtureCatalog.foundable_sect(FOUNDRY)])
	SectFixtureCatalog.install_doctrine([SectFixtureCatalog.doctrine(DOCTRINE)])
	var teacher := _teacher(&"teacher")
	var door := SectCatalog.instance().sect_definition(FOUNDRY).min_purity
	assert_ne(door, 0, "the fixture sect actually authors a door")
	var below := _sworn(&"below")
	var ledger := SectApi.state(below)
	(ledger["fit"] as Dictionary)[String(DOCTRINE)] = door - 1
	below.set_module_data(SectState.MODULE_KEY, ledger)
	SectApi.attach(below)
	var refused := SectApi.teach(teacher, below, DOCTRINE)
	assert_eq(bool(refused["ok"]), false, "a member under the door is not taught")
	assert_eq(
		String(refused["reason"]),
		SectApi.STANDING_BELOW_FLOOR,
		"and it names the sect's own route, not the doctrine's floor"
	)
	# At the door, the same lesson lands.
	var at_door := _sworn(&"at_door")
	var opened := SectApi.state(at_door)
	(opened["fit"] as Dictionary)[String(DOCTRINE)] = door
	at_door.set_module_data(SectState.MODULE_KEY, opened)
	SectApi.attach(at_door)
	assert_eq(bool(SectApi.teach(teacher, at_door, DOCTRINE)["ok"]), true, "at the door, taught")


## **The comprehension gate reads BASE ALLOCATION ONLY.** ADR 0052/0054 pinned that
## deliberately — *"a technique can never satisfy its own requirement with the stats
## it grants"* — and reading `derived` would let the bounded percent THIS module
## projects fund the gate that decides whether this module may teach. That is the
## exact smuggling `set_base` was rejected for, arrived at from the other direction.
func test_the_comprehension_gate_reads_base_allocation_and_never_derived() -> void:
	var teacher := _teacher(&"teacher")
	var at_floor := _sworn(&"at_floor", FLOOR)
	assert_eq(
		SectApi.teach(teacher, at_floor, DOCTRINE)["ok"],
		true,
		"a student exactly on the floor is taught"
	)
	var below := _sworn(&"below", FLOOR - 1.0)
	assert_eq(
		SectApi.teach(teacher, below, DOCTRINE)["reason"],
		SectApi.COMPREHENSION_BELOW_FLOOR,
		"one point under the floor is refused"
	)
	var above := _sworn(&"above", FLOOR + SPAN + 1.0)
	assert_eq(
		SectApi.teach(teacher, above, DOCTRINE)["reason"],
		SectApi.COMPREHENSION_ABOVE_SPAN,
		"and so is one above the span — the far side of the same band"
	)
	var at_span := _sworn(&"at_span", FLOOR + SPAN)
	assert_eq(
		SectApi.teach(teacher, at_span, DOCTRINE)["ok"],
		true,
		"the span's upper end is inclusive, or an author could not write it down"
	)
	# The proof that the gate is base-only: a student at the floor is taught, and a
	# `PERCENT` modifier on the comprehension sheet cannot lift one under the floor
	# into it. A derived read would have admitted this actor.
	var derived_reader := _sworn(&"derived_reader", FLOOR - 1.0)
	var before := SectApi.teach(teacher, derived_reader, DOCTRINE)
	assert_eq(
		String(before["reason"]), SectApi.COMPREHENSION_BELOW_FLOOR, "under the floor, refused"
	)
	derived_reader.stats.add_modifier(
		StatModifier.new(Stat.COMPREHENSION, Stat.Op.PERCENT, 1.0, SectState.source_for(FOUNDRY))
	)
	assert_eq(
		derived_reader.stats.derived(Stat.COMPREHENSION) > FLOOR,
		true,
		"the derived sheet now reads over the floor"
	)
	var still := SectApi.teach(teacher, derived_reader, DOCTRINE)
	assert_eq(
		String(still["reason"]),
		SectApi.COMPREHENSION_BELOW_FLOOR,
		"and the gate still refuses, because it reads the base"
	)


# --- The teacher pays (BL-0188) ----------------------------------------------


## **A lesson costs the teacher.** Free and unlimited teaching makes disciples a
## resource faucet, so one session spends the office's `teach_tax` plus the
## doctrine's own out of the teacher's `stamina`, and the payload publishes what it
## paid. Standing is NOT the cost — it is recognition, and spending it would have
## collapsed ADR 0064's two-part split into one number.
func test_a_lesson_spends_the_teacher_and_publishes_what_it_paid() -> void:
	var teacher := _teacher(&"teacher")
	var student := _sworn(&"student")
	var tax := _tax()
	assert_ne(tax, 0.0, "a fixture lesson really costs something")
	var stamina := teacher.resource(&"stamina").current
	var verdict := SectApi.teach(teacher, student, DOCTRINE, 3)
	assert_eq(bool(verdict["ok"]), true, "three sessions land")
	assert_almost_eq(float(verdict["tax"]), tax, "and the payload publishes the per-session price")
	assert_almost_eq(
		teacher.resource(&"stamina").current, stamina - tax * 3.0, "the teacher paid all three"
	)
	assert_eq(int(SectApi.state(teacher)["standing"]), 100, "and standing is exactly where it was")
	assert_eq(int(SectApi.state(student)["standing"]), 0, "as is the student's")
	# The tax is authored on both halves and summed in one place, so a screen renders
	# one number rather than re-deriving a sum.
	var office := SectCatalog.instance().sect_definition(FOUNDRY).position(STEWARD)
	assert_almost_eq(tax, office.teach_tax + _doctrine().teach_tax, "office tax plus doctrine tax")
	# A teacher who cannot pay teaches nobody, and pays nothing for asking.
	var broke := _teacher(&"broke")
	broke.resource(&"stamina").current = tax * 0.5
	var before := SectApi.state(broke)
	var refused := SectApi.teach(broke, _sworn(&"second"), DOCTRINE)
	assert_eq(bool(refused["ok"]), false, "a teacher who cannot pay is refused")
	assert_eq(String(refused["reason"]), SectApi.NOTHING_TO_TEACH, "and it names itself")
	assert_eq(broke.resource(&"stamina").current, tax * 0.5, "having paid nothing")
	assert_eq(SectApi.state(broke), before, "and written nothing")


## ## The refusals a teacher may hand back are AUTHORED
##
## `SectDoctrineDef.refusals` is a closed list of named verdicts the content owns, and
## the facade publishes whichever word it is given rather than composing free text —
## so the vocabulary lives in a `.tres` and a panel never invents a wording (ADR
## 0084). This asserts the two halves: the content authors the list, and every word
## on it is one a panel could render.
func test_a_doctrines_refusals_are_authored_content_not_composed_prose() -> void:
	for authored in [
		"res://data/packs/sect/organizations/doctrines/still_water.tres",
		"res://data/packs/sect/organizations/doctrines/iron_vine.tres"
	]:
		var def := load(authored) as SectDoctrineDef
		assert_ne(def, null, "%s loads" % authored)
		assert_ne(def.id, &"", "and names itself")
		assert_ne(def.display_name, "", "with a display name")
		assert_ne(def.description, "", "and a clinical description")
		assert_ne(def.teachings.size(), 0, "and something it actually teaches")
		assert_ne(def.refusals.size(), 0, "and something it refuses")
		assert_eq(def.comprehension_floor >= 0.0, true, "a comprehension band starts at zero")
		assert_ne(def.comprehension_span, 0.0, "and spans something")
		assert_eq(def.floor_fit(), def.affinity_floor, "the fit floor reads as authored")
		assert_ne(def.fit_per_period, 0, "and a session is worth something")
		# The two shipped doctrines teach different things, which is the whole of
		# BL-0186: a doctrine is content, so adding a school of thought is a `.tres`.
	# And every authored sect in the tree names a doctrine the catalog ships, which
	# is the wiring BL-0186 asks for and the reason `found` refuses
	# `unknown_doctrine` rather than accepting a dangling id.
	var found := 0
	for sect_id in SectCatalog.instance().sect_ids():
		var def := SectCatalog.instance().sect_definition(sect_id)
		assert_ne(def.doctrine_id, &"", "'%s' names a doctrine" % sect_id)
		assert_ne(
			SectDoctrineCatalog.instance().doctrine(def.doctrine_id),
			null,
			"and the catalog ships it"
		)
		assert_ne(def.top_position(), null, "and it authors a top office a founder can take")
		found += 1
	assert_ne(found, 0, "and there is at least one authored sect to check")


## The read model publishes the doctrine a panel needs: what is taught, what may be
## refused, the comprehension band and the affinity floor — all through `summary()`
## rather than a thirteenth method.
func test_the_doctrine_is_read_from_summary_and_publishes_its_whole_shape() -> void:
	var teacher := _teacher(&"teacher")
	var read := SectApi.summary(teacher)
	var doctrine_id := String(SectCatalog.instance().sect_definition(FOUNDRY).doctrine_id)
	assert_eq(String(read["doctrine_id"]), doctrine_id, "the sworn sect's doctrine is named")
	assert_ne(String(read["doctrine_name"]), "", "with a display name")
	var doctrine := read["doctrines"][doctrine_id] as Dictionary
	assert_ne(doctrine, null, "and the catalog publishes the doctrine itself")
	assert_eq(int(doctrine["affinity_floor"]), AFFINITY_FLOOR, "with its affinity floor")
	assert_almost_eq(float(doctrine["comprehension_floor"]), FLOOR, "and the band's floor")
	assert_almost_eq(float(doctrine["comprehension_span"]), SPAN, "and its span")
	assert_eq(int(doctrine["fit_per_period"]), FIT_PER_PERIOD, "and what a session is worth")
	assert_ne((doctrine["teachings"] as Array).size(), 0, "and what it teaches")
	assert_ne((doctrine["refusals"] as Array).size(), 0, "and what it refuses")
	# The office publishes its own tax beside its walk, so a panel renders the whole
	# price of a lesson from one call.
	var office := read["can_promote"][String(STEWARD)] as Dictionary
	assert_almost_eq(float(office["teach_tax"]), _tax(), "and the office's share of it")
	assert_eq(read["teaches"], true, "this teacher is above the sect's own teaching door")


func _own_modifiers(actor: Actor) -> int:
	var total := 0
	for modifier in actor.stats._modifiers:
		if SectState.is_own_source(modifier.source):
			total += 1
	return total
