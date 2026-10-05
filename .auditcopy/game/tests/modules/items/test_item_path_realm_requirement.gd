extends TestCase

## ADR 0059: the path-scoped realm gate on `ItemRequirement`, and DEF-0087's
## implementation.
##
## `ItemRequirement.min_realm_index` takes the actor's BEST path on purpose, so an
## item never demands one specific cultivation system. That is right for equipment and
## wrong for a technique: a qi technique gated on "best path" is learnable by an actor
## whose body is at R30 and whose qi has never moved past R3 — precisely the build the
## path-typed slots exist to make a mistake. `min_path_realm` reads ONE named path's
## rank instead, and composes with the best-path gate rather than replacing it.
##
## Everything ADR 0052 guarantees still holds and is proved by the sibling suite; what
## is pinned here is the part the new field could break:
##   - a path gate reads its OWN path, not the actor's strongest one
##   - it is an ALL-OF, so a dual technique commits both of its paths
##   - `is_empty()` counts it, or a path-gated profile reports as unrestricted
##   - the `unmet()` row names the short path, so a panel re-derives nothing


## Attach the items module BEFORE paths are set: `attach` rebuilds actor state, so a
## path set first is silently lost — the same ordering trap the sibling suite documents.
func _actor() -> Actor:
	var stats := {Stat.PHYSIQUE: 10.0, Stat.WILL: 10.0, Stat.SPIRIT: 10.0}
	var actor := Actor.new(&"wielder", stats)
	ItemsApi.attach(actor, 50)
	return actor


## Give the actor ONE path, at a realm.
func _on_path(actor: Actor, path_id: StringName, realm_id: StringName) -> Actor:
	actor.set_path(PathState.new(path_id, realm_id))
	return actor


func _def_with(requirement: ItemRequirement) -> ItemDef:
	var def := ItemDef.new()
	def.id = &"test_relic"
	def.grade = ItemGrade.MORTAL
	def.category = ItemCategory.EQUIPMENT
	def.requirement = requirement
	return def


func _equip(actor: Actor, def: ItemDef) -> bool:
	if ItemsApi.inventory(actor) == null:
		ItemsApi.attach(actor, 50)
	ItemsApi.inventory(actor).add_instance(ItemInstance.new(def.id))
	return ItemsApi.equip_item(actor, Equipment.WEAPON, def)


# --- the gate reads its own path, not the best one ----------------------------


## The bug ADR 0059 exists to prevent. Body and qi are both at R30, qi is at R3, and
## the profile names qi. A best-path gate would wave this actor through; the path gate
## must not.
func test_a_path_gate_is_unmet_when_the_named_path_is_behind_the_best_one() -> void:
	var floor := RealmDefaults.ladder().index_of(&"spirit_sea")
	var requirement := ItemRequirement.new()
	requirement.min_path_realm = {PathState.QI: floor}
	var def := _def_with(requirement)

	var actor := _actor()
	actor.set_path(PathState.new(PathState.BODY, &"primordial_origin"))
	actor.set_path(PathState.new(PathState.QI, &"core_formation"))
	var best := RealmDefaults.ladder().index_of(&"primordial_origin")
	var named := RealmDefaults.ladder().index_of(&"core_formation")
	assert_eq(best >= floor, true, "the BEST path would clear a scalar floor")
	assert_eq(named < floor, true, "the named qi path does not")
	assert_eq(named, floor - 8, "eight ordinals short, asserted concretely")
	assert_eq(requirement.unmet(actor).is_empty(), false, "so the path gate refuses")
	assert_eq(_equip(actor, def), false, "and the item does not equip")


## The same profile, once the named path arrives. Nothing else moved, so this is the
## gate and only the gate.
func test_a_path_gate_is_met_once_the_named_path_reaches_its_floor() -> void:
	var floor := RealmDefaults.ladder().index_of(&"spirit_sea")
	var requirement := ItemRequirement.new()
	requirement.min_path_realm = {PathState.QI: floor}
	var def := _def_with(requirement)

	var actor := _actor()
	actor.set_path(PathState.new(PathState.BODY, &"primordial_origin"))
	assert_eq(requirement.unmet(actor).is_empty(), false, "qi has no path state yet")
	actor.set_path(PathState.new(PathState.QI, &"spirit_sea"))
	assert_eq(requirement.unmet(actor).is_empty(), true, "exactly at the floor passes")
	assert_eq(_equip(actor, def), true, "and the item equips")


## An all-of, never an either-of: a DUAL technique commits BOTH of its paths, so a
## second path is a second investment rather than a free slot.
func test_a_two_path_gate_is_met_only_when_both_paths_reach_their_floors() -> void:
	var requirement := ItemRequirement.new()
	requirement.min_path_realm = {
		PathState.QI: RealmDefaults.ladder().index_of(&"spirit_sea"),
		PathState.BODY: RealmDefaults.ladder().index_of(&"spirit_manifestation"),
	}
	var actor := _actor()
	actor.set_path(PathState.new(PathState.QI, &"spirit_sea"))
	assert_eq(requirement.satisfied_by(actor), false, "one path alone is not enough")

	actor.set_path(PathState.new(PathState.BODY, &"spirit_manifestation"))
	assert_eq(requirement.unmet(actor).is_empty(), true, "both at their floors is met")
	assert_eq(requirement.satisfied_by(actor), true, "so the profile is satisfied")


# --- is_empty must count it ---------------------------------------------------


## ADR 0059's explicit warning: `is_empty()` must include the dictionary. Left out, a
## profile carrying only a path gate reports as unrestricted and silently admits
## everyone — the gate would exist and never run.
func test_a_path_only_profile_is_not_empty() -> void:
	var open := ItemRequirement.new()
	assert_eq(open.min_path_realm, {}, "a path gate defaults to empty")
	assert_eq(open.is_empty(), true, "and an empty path dictionary is no restriction")

	var gated := ItemRequirement.new()
	gated.min_path_realm = {PathState.QI: 5}
	assert_eq(gated.is_empty(), false, "a non-empty path dictionary is a restriction")
	assert_eq(gated.unmet(_actor()).is_empty(), false, "and it is enforced, not admitted")


# --- unmet() names the path ---------------------------------------------------


## The row's `id` IS the path id, so a panel can say which path is short without
## re-deriving the gate.
func test_unmet_reports_the_short_path_as_the_row_id() -> void:
	var floor := RealmDefaults.ladder().index_of(&"spirit_sea")
	var requirement := ItemRequirement.new()
	requirement.min_path_realm = {PathState.QI: floor}
	var actor := _actor()
	actor.set_path(PathState.new(PathState.BODY, &"primordial_origin"))
	actor.set_path(PathState.new(PathState.QI, &"core_formation"))

	var problems := requirement.unmet(actor)
	assert_eq(problems.size(), 1, "one problem")
	assert_eq(problems[0]["kind"], ItemRequirement.PATH_REALM, "it is a path gate")
	assert_eq(problems[0]["id"], PathState.QI, "and its id IS the failing path id")
	assert_eq(problems[0]["required"], floor, "reporting the authored floor")
	assert_eq(
		problems[0]["actual"], RealmDefaults.ladder().index_of(&"core_formation"), "and the actual"
	)
	assert_ne(String(problems[0]["label"]), "", "with a human label naming the path")


# --- it composes with min_realm_index -----------------------------------------


## The two gates have two meanings and both are reported. `min_realm_index` stays the
## "any path" gate, so a profile carrying both can fail on either alone.
func test_a_path_gate_composes_with_the_realm_gate() -> void:
	var requirement := ItemRequirement.new()
	# The best-path gate asks for ordinal 20; the path gate asks for qi at 10.
	requirement.min_realm_index = 20
	requirement.min_path_realm = {PathState.QI: 10}
	var def := _def_with(requirement)

	# Mind is below 20 and qi is below 10, so BOTH gates fail and both are listed.
	var both_short := _on_path(_actor(), PathState.MIND, &"spirit_sea")
	both_short.set_path(PathState.new(PathState.QI, &"core_formation"))
	var both := requirement.unmet(both_short)
	assert_eq(both.size(), 2, "both gates are reported, not just the first")
	assert_eq(both[0]["kind"], ItemRequirement.REALM, "the realm gate first")
	assert_eq(both[1]["kind"], ItemRequirement.PATH_REALM, "then the path gate")
	assert_eq(both[1]["id"], PathState.QI, "naming the path")
	assert_eq(both[0]["actual"], RealmDefaults.ladder().index_of(&"spirit_sea"), "mind at 10")
	assert_eq(_equip(both_short, def), false, "and the item is refused")

	# Body alone clears 20, so the realm gate is satisfied and ONLY the path gate fails.
	# This is the meaning difference between them: the best-path gate cannot be the one
	# that refuses here.
	var realm_ok := _actor()
	realm_ok.set_path(PathState.new(PathState.BODY, &"primordial_origin"))
	realm_ok.set_path(PathState.new(PathState.QI, &"core_formation"))
	var only_path := requirement.unmet(realm_ok)
	assert_eq(only_path.size(), 1, "only the path gate fails")
	assert_eq(only_path[0]["kind"], ItemRequirement.PATH_REALM, "and it is the path gate")
	assert_eq(only_path[0]["id"], PathState.QI, "still naming the path")

	# And with both gates met, the profile is satisfied.
	var ready := _on_path(_actor(), PathState.QI, &"primordial_origin")
	ready.set_path(PathState.new(PathState.BODY, &"primordial_origin"))
	assert_eq(requirement.satisfied_by(ready), true, "both floors cleared")


# --- an absent path is unmet, not excused -------------------------------------


## A path the actor has never started counts as ordinal 0, not "no opinion": the gate
## named a path, so an actor who has not taken it cannot be reading a rank off it.
func test_a_path_the_actor_has_not_started_counts_as_unmet() -> void:
	var requirement := ItemRequirement.new()
	requirement.min_path_realm = {PathState.MIND: 3}
	var actor := _on_path(_actor(), PathState.QI, &"primordial_origin")
	assert_eq(actor.path(PathState.MIND), null, "the mind path was never started")
	assert_eq(actor.path(PathState.QI).rank_id, &"primordial_origin", "while qi is at R30")

	var problems := requirement.unmet(actor)
	assert_eq(problems.size(), 1, "an absent path is unmet, not excused")
	assert_eq(problems[0]["id"], PathState.MIND, "reported under the path it names")
	assert_eq(problems[0]["actual"], 0, "as ordinal 0")
	assert_eq(requirement.satisfied_by(actor), false, "so the requirement is refused")

	# Starting the path at the floor satisfies it, which proves the failure above was
	# about the missing path rather than about the floor.
	actor.set_path(PathState.new(PathState.MIND, &"nascent_soul"))
	assert_eq(requirement.satisfied_by(actor), true, "reached the floor on the mind path")


## An actor with no paths at all still cannot satisfy a floor above ordinal 0 — the
## gate is not special-cased into admitting anyone.
func test_an_actor_with_no_paths_fails_any_nonzero_path_floor() -> void:
	var requirement := ItemRequirement.new()
	requirement.min_path_realm = {PathState.QI: 1}
	assert_eq(requirement.satisfied_by(_actor()), false, "no paths, so no rank to read")
	var problems := requirement.unmet(_actor())
	assert_eq(problems[0]["actual"], 0, "reported as ordinal 0")
