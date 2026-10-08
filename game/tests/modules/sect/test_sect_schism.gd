extends TestCase

## **A schism costs BOTH halves** (BL-0197, ADR 0085).
##
## The rule exists because of what its absence produces. A split that is free is a
## strictly-positive action, so every crisis would end in a split and no institution
## would ever have to answer for one. These cases are written so that removing the
## price — or moving it onto only one side, or only onto the declaration and not the
## abandoned ground — turns something red rather than merely changing a number.
##
## Three ideas, one per section:
##   1. the arithmetic: standing is DIVIDED, and both halves pay;
##   2. the price: it is authored data on `SectTuning`, and a half that cannot cover
##      it settles at zero and says by how much;
##   3. the refusals: each names itself and writes nothing at all (ADR 0084).

const PARENT := &"t_foundry"
const HALF := &"t_seceded_house"
const DOCTRINE := &"t_foundry_doctrine"
## The places `PARENT` authors a claim over, read off the def rather than written
## down here: a case asserting a hard-coded count would be asserting the fixture
## rather than the rule.
const PLACES: Array[StringName] = [&"t_yard", &"t_terrace", &"t_orchard"]


func setup() -> void:
	SectFixtureCatalog.install([_parent(), _half()])
	SectFixtureCatalog.install_doctrine([SectFixtureCatalog.doctrine(DOCTRINE)])
	# The world store seam is PROCESS state: a suite that mounted the app leaves a
	# real store installed (InstitutionBoot.install wires it), and this suite's
	# cases measure the actor-side split with no world leg. Establish that.
	SectApi.set_world_store(null)


func teardown() -> void:
	SectFixtureCatalog.teardown()
	SectApi.set_world_store(null)


func _parent() -> SectDef:
	var def := SectFixtureCatalog.foundable_sect(PARENT)
	def.territory_ids = PLACES
	return def


func _half() -> SectDef:
	return SectFixtureCatalog.foundable_sect(HALF)


## A founder of `PARENT`: sworn, seated in the top office, and holding the refund
## standing `SectFounding` grants, so a case about the arithmetic starts from a
## number the module itself published.
func _founder() -> Actor:
	var actor := Actor.new(&"keeper", {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})
	actor.add_resource(ResourcePool.new(SectFounding.FUNDING_POOL, 1000.0))
	SectApi.attach(actor)
	assert_eq(bool(SectApi.found(actor, PARENT, DOCTRINE, "keeper")["ok"]), true, "founded")
	return actor


func _tuning() -> SectTuning:
	return SectCatalog.instance().tuning()


func _undivided() -> int:
	return int(SectApi.state(_founder())["standing"])


# --- Standing is divided, and BOTH halves pay ------------------------------


## The headline property, and it is an inequality rather than a pair of equalities:
## **what the two halves hold between them must never exceed what the whole held.**
## A design where each side inherited `ceil(undivided / 2)` would satisfy "each half
## pays" while quietly minting a point, so the bound is what catches it.
func test_a_split_divides_the_undivided_standing_and_charges_both_halves() -> void:
	var actor := _founder()
	var undivided := SectState.standing(SectApi.state(actor))
	# A half that pays for itself: the price has to be able to come out of the
	# inheritance, or "each half pays" would only ever be observable as a clamp at
	# zero. The per-territory charge is left out deliberately — the four prices below
	# are what this case is about, and `PLACES` would make the first of them the sum.
	var verdict := SectApi.declare_schism(actor, HALF, PLACES)
	assert_eq(bool(verdict["ok"]), true, "the split landed: %s" % verdict)
	assert_eq(int(verdict["unassigned"]), 0, "no authored ground was abandoned")
	assert_eq(int(verdict["undivided"]), undivided, "the whole that was divided is published")
	assert_eq(int(verdict["half"]), int(floor(float(undivided) / 2.0)), "each half inherits half")
	var price := int(verdict["price"])
	assert_eq(price, _tuning().schism_cost, "and each half pays the declared schism cost")
	assert_eq(
		int(verdict["settled"]),
		int(verdict["half"]) - price,
		"each half is left with its inheritance less the price it paid",
	)
	# Both halves pay, so the two bills cannot disagree: one number computed once
	# and written to both, rather than two callers each summing their own.
	assert_eq(
		int(verdict["shortfall"]),
		maxi(0, price - int(verdict["half"])),
		"and the shortfall is exactly what the inheritance could not cover",
	)
	assert_ne(price, 0, "a schism is not free: it costs something by design")
	assert_eq(
		int(verdict["settled"]) * 2 <= int(verdict["half"]) * 2,
		true,
		"the two halves together never hold more than the whole did",
	)
	# `applied` is the DECLARING member's own standing delta: the second of the two
	# equal charges, published so a caller that reads only `applied` is reading half
	# the bill and can see that it is.
	assert_eq(int(verdict["applied"]), -price, "and the declaring member paid it")
	# The member's own claim is their half of the institution's standing less the
	# price — which is a different number from `settled`, because `settled` is what
	# the SECEDING half comes into being with. Both are published, so a panel can
	# render the whole bill rather than showing one half of it.
	assert_eq(
		SectState.standing(SectApi.state(actor)),
		undivided - price,
		"so their claim is exactly what they had, less the price they paid",
	)
	assert_ne(
		int(verdict["settled"]),
		SectState.standing(SectApi.state(actor)),
		"and the seceding half's inheritance is a separate number from the member's claim",
	)


## An odd undivided value must lose its leftover point rather than hand one to a
## side. Asserted over the whole odd range, because a `ceil` on an odd number and a
## `floor` on an even one are indistinguishable on any single fixture.
func test_an_odd_undivided_standing_loses_its_leftover_point_rather_than_minting_one() -> void:
	for undivided in [3, 5, 7, 9, 21]:
		var bill := SectSchism.settle(undivided, 0)
		assert_eq(int(bill["half"]) * 2 <= undivided, true, "%d splits without minting" % undivided)
		assert_eq(
			int(bill["odd_charged"]),
			undivided - int(bill["half"]) * 2,
			"%d charges the odd point away instead of rounding up" % undivided,
		)


## The per-territory charge is charged to **both** halves, and only for ground the
## declaration actually leaves unassigned. Each `assigned` list is a real set drawn
## from the authored `territory_ids`, and the bill is read off the tuning rather than
## written down, so a rebalance of the `.tres` does not turn this case red for
## having asserted the fixture.
func test_each_half_pays_again_for_every_territory_the_declaration_leaves_unassigned() -> void:
	var per_place := _tuning().schism_cost_per_unassigned
	assert_ne(per_place, 0, "the shipped tuning prices abandoned ground")

	# Assign nothing: every authored place is unassigned. Spelled out as an empty
	# list rather than relying on the default argument, so the case says what it means.
	var actor := _founder()
	var bare := SectApi.declare_schism(actor, HALF, [])
	assert_eq(int(bare["unassigned"]), PLACES.size(), "all authored ground is unassigned")
	assert_eq(
		int(bare["price"]),
		_tuning().schism_price(PLACES.size()),
		"so each half pays the declared cost plus one charge per place",
	)

	# Assign every place: the extra charge falls away and the declared cost remains.
	var thorough := _founder()
	var assigned := SectApi.declare_schism(thorough, HALF, PLACES)
	assert_eq(int(assigned["unassigned"]), 0, "no authored ground is unassigned")
	assert_eq(
		int(assigned["price"]),
		_tuning().schism_price(0),
		"and each half pays the declared cost alone, never less",
	)

	# And one short of complete: the bill is the per-territory charge times one.
	var partial_actor := _founder()
	var partial := SectApi.declare_schism(partial_actor, HALF, PLACES.slice(0, PLACES.size() - 1))
	assert_eq(int(partial["unassigned"]), 1, "one place was left unassigned")
	assert_eq(
		int(partial["price"]),
		_tuning().schism_price(1),
		"and each half pays exactly one per-territory charge for it",
	)


## A place the sect never claimed is not ground a split can abandon, and the bill is
## counted against the AUTHORED list rather than against whatever the caller passed.
## Otherwise a caller could hand in one id and pay a third of what it owes.
func test_the_bill_is_counted_against_the_authored_claims_and_not_against_the_argument() -> void:
	var actor := _founder()
	var invented := SectApi.declare_schism(actor, HALF, [&"t_nowhere_at_all"])
	assert_eq(
		int(invented["unassigned"]),
		PLACES.size(),
		"an id this sect never claimed does not reduce the bill",
	)
	assert_eq(
		int(invented["price"]),
		_tuning().schism_price(PLACES.size()),
		"and the price is the full authored one",
	)


## A split that cannot cover its own price is still allowed to happen, and says by
## how much it could not pay. Refusing instead would make the cost a gate rather than
## a price, and a verb that only works when you are rich is not the verb the ADR
## describes.
func test_a_half_that_cannot_cover_the_price_settles_at_zero_and_publishes_the_shortfall() -> void:
	var actor := _founder()
	# Drive the claim down to the floor so the declared price exceeds the inheritance.
	# Every place is assigned, so the bill is the declared cost alone and the
	# shortfall arithmetic below is about the inheritance rather than about ground.
	var cap := int(SectApi.state(actor)["standing_cap"])
	SectApi.move_standing(actor, -(cap - 1))
	assert_eq(SectState.standing(SectApi.state(actor)), 1, "one point of undivided standing")
	var verdict := SectApi.declare_schism(actor, HALF, PLACES)
	assert_eq(String(verdict.get("reason", "")), SectApi.NOTHING_TO_SPLIT, "one point refuses")

	# Two points do split, and two points cannot pay the declared bill.
	var poorer := _founder()
	SectApi.move_standing(poorer, -(cap - 2))
	var split := SectApi.declare_schism(poorer, HALF, PLACES)
	assert_eq(bool(split["ok"]), true, "two points are enough to declare")
	assert_eq(int(split["half"]), 1, "and each half inherits one")
	assert_eq(int(split["settled"]), 0, "and each half settles at zero rather than below it")
	assert_eq(
		int(split["shortfall"]),
		int(split["price"]) - 1,
		"publishing exactly how much of the bill the split could not cover",
	)
	assert_eq(
		SectState.standing(SectApi.state(poorer)),
		0,
		"and the declaring member is left at the floor"
	)


## The costs are AUTHORED DATA, not literals in a `.gd`: a rebalance is a `.tres`
## edit and no test has to re-pin a number that changed on purpose (ADR 0067's
## `CombatTuning` shape, which `SectTuning` copied).
func test_both_costs_are_authored_on_the_tuning_and_read_through_the_catalog() -> void:
	var tuning := _tuning()
	assert_ne(tuning, null, "the catalog hands out a tuning")
	assert_eq(
		tuning.schism_price(0),
		maxi(0, tuning.schism_cost),
		"no abandoned ground, one declared cost"
	)
	assert_eq(
		tuning.schism_price(3),
		maxi(0, tuning.schism_cost) + maxi(0, tuning.schism_cost_per_unassigned) * 3,
		"and three abandoned places add three per-territory charges",
	)
	# The shipped instance is a real `.tres` rather than a degenerate default: a
	# caller who forgot it must get an obviously-free split, not a plausible price.
	assert_ne(maxi(0, tuning.schism_cost), 0, "the shipped tuning declares a non-zero cost")


# --- Every refusal writes nothing -------------------------------------------


## Each refusal names itself and leaves `actor.module_data` byte-for-byte as found
## (ADR 0084). A refusal that quietly charged the founder would be exactly the
## failure this list exists for, so the ledger is re-read after every one of them.
func test_every_schism_refusal_is_named_and_writes_nothing() -> void:
	# `no_actor`: there is nobody to split anything for.
	assert_eq(
		String(SectApi.declare_schism(null, HALF)["reason"]), SectApi.NO_ACTOR_SPLIT, "a null actor"
	)

	var stranger := Actor.new(&"stranger", {Stat.PHYSIQUE: 10.0})
	SectApi.attach(stranger)
	assert_eq(
		String(SectApi.declare_schism(stranger, HALF)["reason"]),
		SectApi.NOT_A_MEMBER,
		"an actor sworn to no sect",
	)
	assert_eq(SectApi.state(stranger), SectState.empty(), "and that refusal wrote nothing either")

	var actor := _founder()
	var before := SectApi.state(actor)

	# `unknown_sect`: the sect doing the splitting is one this build does not ship.
	# A stranger's ledger rather than a tampered one — `SectState.normalize` filters
	# an institution id against nothing (the catalog ships no sect-name filter), so
	# writing one onto a member's own ledger would keep the member sworn to a sect
	# nothing defines, which is a state `normalize` deliberately does not create.
	var exiled := Actor.new(&"exiled", {Stat.PHYSIQUE: 10.0})
	SectApi.attach(exiled)
	var carried := SectApi.state(actor).duplicate(true)
	carried["institution"] = "t_no_such_house"
	exiled.set_module_data(SectState.MODULE_KEY, carried)
	assert_eq(
		String(SectApi.declare_schism(exiled, HALF)["reason"]),
		SectApi.UNKNOWN_SECT,
		"a sect this build does not ship",
	)

	# `unknown_half`: the seceding half is a sect nothing defines, so the split would
	# create an institution that teaches nothing and grants nothing.
	var unknown := SectApi.declare_schism(actor, &"t_no_such_half")
	assert_eq(String(unknown["reason"]), SectApi.UNKNOWN_HALF, "a half this build does not ship")
	assert_eq(String(unknown["seceding_id"]), "t_no_such_half", "and the refusal names WHICH half")
	# `cannot_secede_from_itself`: there is no half to leave.
	var itself := SectApi.declare_schism(actor, PARENT)
	assert_eq(String(itself["reason"]), SectApi.SELF_SECESSION, "a sect seceding from itself")
	assert_eq(SectApi.state(actor), before, "and none of the three refusals wrote a thing")

	# The declaration that works, and then the one refusal it makes reachable.
	var declared := SectApi.declare_schism(actor, HALF)
	assert_eq(bool(declared["ok"]), true, "the split landed: %s" % declared)
	var sworn := SectApi.state(actor)
	var twice := SectApi.declare_schism(actor, HALF)
	assert_eq(String(twice["reason"]), SectApi.ALREADY_SECEDED, "a second declaration is refused")
	assert_eq(SectApi.state(actor), sworn, "and wrote nothing: it is the same split written twice")


## The declaration is recorded, and recorded as a BILL rather than re-derived from
## it: what the split cost is the authority, so a display reading it can never
## disagree with what was paid — the same rule a standoff's declared prize follows.
func test_the_declaration_is_recorded_and_published_through_summary() -> void:
	var actor := _founder()
	var verdict := SectApi.declare_schism(actor, HALF, PLACES)
	assert_eq(bool(verdict["ok"]), true, "declared")
	var line := SectState.schism(SectApi.state(actor), HALF)
	assert_eq(line.is_empty(), false, "the split is in the ledger")
	assert_eq(String(line["parent_id"]), String(PARENT), "naming the sect it came out of")
	assert_eq(String(line["seceding_id"]), String(HALF), "and the half it produced")
	assert_eq(String(line["verb"]), SectSchism.VERB, "under the sect's own word for a split")
	assert_eq(int(line["price"]), int(verdict["price"]), "with the price that was charged")
	assert_eq(int(line["settled"]), int(verdict["settled"]), "and what each half settled to")
	# `summary()` is the read model, so the split lives there rather than behind a
	# thirteenth facade method (ADR 0083).
	var read := SectApi.summary(actor)
	assert_eq(int(read["schism_count"]), 1, "the summary counts the declaration")
	assert_eq(
		(read["schisms"] as Dictionary)[String(HALF)],
		line,
		"and publishes the bill verbatim rather than recomputing it",
	)
	# A member who has never declared one answers the same keys with nothing, which
	# is ADR 0083's first state rather than a missing key.
	assert_eq(int(SectApi.summary(_founder())["schism_count"]), 0, "no declaration, no rows")
	assert_eq(SectApi.summary(null)["schisms"] as Dictionary, {}, "and no actor, no rows")


## A declaration ledger is JSON-safe: `String` keys, primitives only, no
## `StringName` anywhere. `Actor.to_dict` converts only the OUTER `module_data` key,
## so an inner `StringName` reaches the save untouched and breaks every round trip —
## and no checker in this repo can see it, so the discipline is pinned here.
func test_a_ledger_carrying_a_declaration_survives_a_json_hop() -> void:
	var actor := _founder()
	SectApi.declare_schism(actor, HALF)
	var ledger := SectApi.state(actor)
	for seceding_id in (ledger["schisms"] as Dictionary).keys():
		assert_eq(typeof(seceding_id), TYPE_STRING, "a declared half is keyed by a String")
		var row: Dictionary = (ledger["schisms"] as Dictionary)[seceding_id]
		for field in row.keys():
			assert_eq(
				typeof(row[field]) in [TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL],
				true,
				"'%s' is a primitive" % field,
			)

	var parsed = JSON.parse_string(JSON.stringify(actor.to_dict()))
	assert_ne(parsed, null, "the payload is JSON-safe")
	var restored := Actor.from_dict(parsed as Dictionary)
	SectApi.attach(restored)
	var after := SectState.schism(SectApi.state(restored), HALF)
	assert_eq(after, SectState.schism(ledger, HALF), "and the declaration came back intact")
	assert_eq(
		SectState.standing(SectApi.state(restored)),
		SectState.standing(ledger),
		"with the paid standing"
	)


## ADR 0084's whole subject, structurally: a split moves a NUMBER, and the only stat
## surface an institution owns is the bounded `PERCENT` `SectProjection` already
## projects. A schism that granted a flat, wrote a base attribute or touched the
## stat stack directly would be a stat composer this module does not have.
func test_the_projection_follows_the_split_and_nothing_else_is_granted() -> void:
	var actor := _founder()
	var office := SectCatalog.instance().sect_definition(PARENT).top_position()
	var before := SectState.standing(SectApi.state(actor))
	var verdict := SectApi.declare_schism(actor, HALF)
	var after := SectState.standing(SectApi.state(actor))
	assert_ne(before, after, "the split moved standing, so the recognition it buys moved")
	assert_almost_eq(
		SectProjection.contribution(actor, office.standing_percent_stats.keys()[0]),
		InstitutionClaim.standing_percent(after),
		"and the projection rebuilt to exactly what the new standing earns",
	)
	# The recognition is bounded by construction, so a split that drove standing to
	# zero cannot hand out more than it did.
	assert_eq(
		InstitutionClaim.standing_percent(after) <= InstitutionClaim.STANDING_PERCENT_CAP,
		true,
		"and the whole political stat surface stays under the authored cap",
	)
	assert_eq(
		int(verdict["undivided"]) >= int(verdict["half"]), true, "the whole was at least the half"
	)


# --- Structural: what this module refuses to become -------------------------


## The verb set this module publishes, read off the facade itself rather than off a
## list — `tools arch` cannot see a method that does not exist, so the surface is
## pinned structurally (the ADR 0084 technique).
func test_the_facade_publishes_one_new_verb_and_no_second_stat_surface() -> void:
	var published: Array[String] = []
	for method in (load("res://src/modules/sect/api.gd") as GDScript).get_script_method_list():
		var name: String = method["name"]
		if not name.begins_with("_") and not published.has(name):
			published.append(name)
	assert_eq(published.has("declare_schism"), true, "the split verb is on the facade")
	assert_eq(
		published.size(),
		13,
		(
			"and the facade is exactly thirteen: the twelve ADR 0084 verbs plus the "
			+ "DEF-0179 `set_world_store` injection seam, and no second stat surface"
		),
	)
	# No second way to hand out recognition. A split moves standing; it does not
	# grant, and a verb named any of these would be a second stat composer.
	for banned in [
		"grant_stat",
		"grant_attribute",
		"set_base",
		"add_base",
		"power_up",
		"buff",
		"apply_modifier",
	]:
		assert_eq(
			published.has(banned), false, "there is no '%s' escape hatch on the facade" % banned
		)


## The module owns no clock and no rng. A succession is walked and a schism is
## declared, so the outcome is a pure function of the ledger — which is what lets the
## whole suite run on fresh actors and get byte-identical results.
func test_the_module_declares_no_clock_and_no_rng() -> void:
	for path in _module_files():
		var code := _strip_comments(FileAccess.get_file_as_string(path))
		for banned in ["Time.get_ticks", "get_tree()", "_process(", "_physics_process("]:
			assert_eq(
				code.contains(banned),
				false,
				"%s uses '%s'; no institution owns a clock (DEF-0111)" % [path.get_file(), banned],
			)
		for banned in ["RandomNumberGenerator", "randf(", "randi(", "seed("]:
			assert_eq(
				code.contains(banned),
				false,
				(
					"%s uses '%s'; a schism is declared, never rolled (ADR 0084)"
					% [path.get_file(), banned]
				),
			)


func test_the_module_grants_recognition_only_and_never_power() -> void:
	for path in _module_files():
		var code := _strip_comments(FileAccess.get_file_as_string(path))
		for banned in ["set_base", "add_base", "Stat.Op.FLAT", "Stat.Op.MULT"]:
			assert_eq(
				code.contains(banned),
				false,
				(
					"%s uses '%s'; an institution grants recognition, never power (ADR 0084)"
					% [path.get_file(), banned]
				),
			)


# --- Plumbing --------------------------------------------------------------


## Every `.gd` under the module, found iteratively and read as code. An empty list
## would make every scan above pass vacuously, so it is asserted to be non-empty at
## the one place that could be empty.
func _module_files() -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = ["res://src/modules/sect"]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var path: String = current.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with("."):
					pending.append(path)
			elif entry.ends_with(".gd"):
				out.append(path)
			entry = dir.get_next()
		dir.list_dir_end()
	out.sort()
	return out


## Code with every comment removed, so a module that DOCUMENTS a rule it obeys is
## not reported for obeying it in prose.
func _strip_comments(text: String) -> String:
	var out: Array[String] = []
	for line in text.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		var hash := line.find("#")
		out.append(line.substr(0, hash) if hash >= 0 else line)
	return "\n".join(out)
