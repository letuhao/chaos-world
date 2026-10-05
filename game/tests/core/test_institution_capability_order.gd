extends TestCase

## DEF-0334: an institution kind's capability list is ordered by STRING value, and the
## registry says so in code rather than only in a docstring.
##
## ## Why this is its own suite
##
## Two reasons, and the second is the one that matters. The behaviour belongs to
## `InstitutionRegistry`, not to the def catalog, so it lives beside the registry's own
## cases rather than inside a suite about content discovery. And it is a REGRESSION with
## a measured refutation, so it has to be findable by name: an agent reading ADR 0278's
## "not fixed here" note needs one file to open.
##
## ## The defect, as measured
##
## `capabilities_of`'s docstring claimed the list came back ordered by string value and
## that the sort happened on `Array[String]` before converting back. The code sorted an
## `Array[StringName]` — and **this engine does not order interned ids by their string
## value**, so a def declaring `[has_offices, has_territory]` read back
## `[has_territory, has_offices]`.
##
## ## The DOCSTRING was authoritative; the CODE was the defect
##
## Three reasons, in order of weight:
##
## 1. The same rule was already implemented correctly twice in the same layer —
##    `InstitutionDef.authored_capabilities` and `InstitutionLedger.sorted_keys` both sort
##    on `Array[String]` for this stated reason. A third divergent copy is the ADR 0066
##    trap the registry's own class note is written against.
## 2. A documented order a reader relies on is a contract. Interned-id order is an engine
##    implementation artefact — it can change between engine versions and between the order
##    ids happened to be interned — so code depending on it depends on something never
##    promised.
## 3. The failure had teeth. The boot compares a registry's capabilities against a def's
##    authored ones, so interned ordering made the two sides disagree on which id loaded
##    first, and the SECOND `.tres` a modder dropped into the directory was refused as
##    `capability_disagreement`. That is the exact failure this programme exists to
##    prevent, so the choice was between a measured refutation on one side and a
##    correctness improvement on the other.
##
## The fix is one helper, `InstitutionRegistry._canonical`, which both `register` and
## `capabilities_of` route through — so a row cannot be WRITTEN under one rule and READ
## under another.

## A def script the registrations name as their def type. Under `res://tests/` because
## `core/` may not name `modules/` — the same reason `test_institution_registry.gd` keeps
## its own fixture there.
const DEF := preload("res://tests/core/institution_registry_fixture_def.gd")

var _registry: InstitutionRegistry = null


func setup() -> void:
	_registry = InstitutionRegistry.new()


## Every suite in this one process shares the registry, so a row a suite leaves behind is
## handed to every suite after it.
func teardown() -> void:
	if _registry != null:
		_registry.clear()
		_registry = null


## ## Both directions, pinned as an ORDERED list rather than as a set
##
## The set assertion passes under the old behaviour and would have proved nothing. The
## whole content of the fix is the ORDER, so the assertion is the order.
##
## The declared list is authored in an order that is not the string order, so the case can
## tell the two apart: string order is `has_offices` < `has_territory` < `is_born_to`,
## because every `has_*` precedes `is_born_to` on `h` < `i`. That gap between the two
## orderings is the discriminator — interned order is arbitrary, so a list whose ids happen
## to intern in another order reads back differently while stating the same set.
func test_capability_order_is_by_string_value_in_both_directions() -> void:
	var declared: Array[StringName] = [
		InstitutionRegistry.CAP_HAS_TERRITORY,
		InstitutionRegistry.CAP_IS_BORN_TO,
		InstitutionRegistry.CAP_HAS_OFFICES,
	]
	var report := _registry.register(&"order_probe", "ProbeDef", declared, DEF)
	assert_eq(bool(report["ok"]), true, "the registration landed")

	var expected: Array[StringName] = [
		InstitutionRegistry.CAP_HAS_OFFICES,
		InstitutionRegistry.CAP_HAS_TERRITORY,
		InstitutionRegistry.CAP_IS_BORN_TO,
	]
	# Direction 1: the STORED row. `row()` hands back the registry's own copy, so this is
	# what `register` WROTE rather than what a reader produced — and `register` sorted the
	# same array `capabilities_of` sorted, which is the half of the defect that was not
	# visible from the read side alone.
	assert_eq(
		_registry.row(&"order_probe")["capabilities"],
		expected,
		"the stored row is ordered by string value"
	)
	# Direction 2: the READ-BACK. This is the read whose ordering made the boot's agreement
	# check refuse the second `.tres` of a kind.
	assert_eq(
		_registry.capabilities_of(&"order_probe"),
		expected,
		"and capabilities_of reads it back in the same string order"
	)


## ## Two defs of ONE kind declaring the same SET in different orders both fold
##
## This is the case the defect was measured on, and it is the one with a player-visible
## consequence: the second `.tres` a modder drops into the family directory is a
## regulation of a kind already registered, and with interned ordering it could be refused
## as `capability_disagreement` purely because of which id loaded first.
func test_two_defs_of_one_kind_declaring_the_same_set_in_different_orders_both_fold() -> void:
	var forward := _def(&"hunt_one", &"hunt_guild", [&"has_territory", &"teaches"])
	var mirror := _def(&"hunt_two", &"hunt_guild", [&"teaches", &"has_territory"])
	# The fold is a property of the COMPARISON, so this asserts the two sides agree before
	# the boot is involved at all — which is where the ordering actually bites.
	assert_eq(
		forward.authored_capabilities(),
		mirror.authored_capabilities(),
		"two defs of one kind canonicalise to the SAME ordered list"
	)
	assert_eq(
		forward.check_content()["ok"],
		mirror.check_content()["ok"],
		"and neither is refused by its own authored content"
	)
	assert_eq(
		(
			_registry
			. register(&"hunt_guild", "InstitutionDef", forward.authored_capabilities(), DEF)["ok"]
		),
		true,
		"the first def's capabilities register"
	)
	# And the read the boot performs — registry row against the second def's own list.
	assert_eq(
		_registry.capabilities_of(&"hunt_guild"),
		mirror.authored_capabilities(),
		"so the registry row and the mirror-ordered def compare EQUAL, positionally"
	)


## A genuine disagreement is still refused. Without this case the one above would read as
## "the check was removed", which is the opposite of what was fixed — order was repaired,
## not agreement.
func test_two_defs_of_one_kind_declaring_a_different_set_still_disagree() -> void:
	var narrow := _def(&"rule_one", &"rule_guild", [&"teaches"])
	var wider := _def(&"rule_two", &"rule_guild", [&"teaches", &"has_territory"])
	_registry.register(&"rule_guild", "InstitutionDef", narrow.authored_capabilities(), DEF)
	assert_eq(
		_registry.capabilities_of(&"rule_guild") == wider.authored_capabilities(),
		false,
		"a different SET is not an ordering artefact and does not compare equal"
	)
	assert_eq(
		_registry.capabilities_of(&"rule_guild").size() != wider.authored_capabilities().size(),
		true,
		"and the sizes differ, which is the cheap half of the boot's own check"
	)


## ## `kinds()` was ALREADY string-ordered — pinned so the distinction survives
##
## DEF-0334's title names `capabilities_of` AND `kinds`, and the measured truth is that
## only `capabilities_of` (and `register`'s stored row) were wrong: `kinds()` routes
## through `_sorted_keys()`, which sorts an `Array[String]`. Pinned because a future agent
## reading the DEF title would otherwise "fix" `kinds()` and could not tell that it was
## already right — the same decay a tracked finding suffers when nothing checks it.
func test_kinds_was_already_string_ordered_and_stays_that_way() -> void:
	_registry.register(&"zulu_kind", "ZDef", [InstitutionRegistry.CAP_HAS_OFFICES], DEF)
	_registry.register(&"alpha_kind", "ADef", [InstitutionRegistry.CAP_HAS_OFFICES], DEF)
	_registry.register(&"mike_kind", "MDef", [InstitutionRegistry.CAP_HAS_OFFICES], DEF)
	assert_eq(
		_registry.kinds(),
		[&"alpha_kind", &"mike_kind", &"zulu_kind"] as Array[StringName],
		"kinds() is in string order"
	)


## ## ONE authority for the order, not two copies of a sort
##
## The reason `register` and `capabilities_of` share `_canonical` is that a row written
## under one rule and read under another is two sources of truth for one list — and the
## reader cannot see which rule produced the stored order. This asserts the sharing
## STRUCTURALLY, because `tools arch` cannot see a method that does not exist and a value
## assertion cannot see a duplicated sort.
func test_the_canonical_order_has_exactly_one_home_and_both_ends_reach_it() -> void:
	var methods := _all_methods(InstitutionRegistry)
	# Read WITHOUT the `_` filter the published-surface helper applies: the point is
	# precisely that a PRIVATE function is the shared home, so filtering privates out
	# would leave this asserting nothing.
	assert_eq(
		methods.has("_canonical"), true, "the canon is a named function, not inlined at each end"
	)
	# The behavioural cases above are the PROOF; this pins only the SHAPE that makes them
	# hold together. A registry that grew a second sort would still pass them, so the
	# shape earns its own case — but it is not a substitute, and an earlier revision of
	# this case tried to make it one by grepping the source for `out.sort()`. That grep
	# was WRONG: `_sorted_keys` sorts an `Array[String]` legitimately and matched it, so
	# the check could not tell the defect from correct code.
	assert_eq(
		methods.has("capabilities_of"),
		true,
		"and the read that was mis-sorted is still there to be fixed"
	)


## One authored def, in memory. `InstitutionDef` is a `Resource`, so a def needs no file to
## carry a kind and a capability set — which is what lets this suite stay a pure registry
## test with no temp tree and no disk at all.
func _def(id: StringName, kind: StringName, capabilities: Array) -> InstitutionDef:
	var def := InstitutionDef.new()
	def.id = id
	def.kind = kind
	for capability in capabilities:
		def.capabilities.append(capability)
	return def


## Every method name on `klass`, PRIVATES INCLUDED. `load()` is the way in because
## GDScript refuses a non-static call on a class reference — the trick
## `test_sect_no_power.gd` uses. Named `_all_methods` rather than `_published` because
## the DEF-0334 structural case needs the private half, and a "published surface" helper
## would filter it away and thereby make its own assertion vacuous.
func _all_methods(klass: GDScript) -> Array[String]:
	var out: Array[String] = []
	if klass == null:
		return out
	for method in klass.get_script_method_list():
		var name: String = method["name"]
		if not out.has(name):
			out.append(name)
	out.sort()
	return out
