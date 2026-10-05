extends TestCase

## Admission is the only place `clan` reads the two modules beneath it, and it is a
## gate over RECOGNITION rather than a grant: a clan may require the founder's line at a
## concentration, a body plan and a realm floor, and passing never grants any of them.
##
## These assert that the gate refuses honestly — with a reason per unmet rule — that a
## refused actor's ledger is untouched, and that a passing admission raises neither
## purity nor any stat.

const HOUSE := &"t_house"
const RIVAL := &"t_rival"
const SEALED := &"t_sealed"
const LINE := &"hearthborn"
const HIGH := &"t_high"
const LOW := &"t_low"

## Two rungs of the shared ladder. `LOW` demands `LOW_FLOOR`, so an actor below it and
## an actor exactly on it are both expressible.
const FIRST_REALM := &"qi_refining"
const THIRD_REALM := &"core_formation"
## `RealmLadder` assigns `index` from the array position, so the ladder is
## **0-based**: `qi_refining` is ordinal 0 and `core_formation` is ordinal 2. Every
## figure below is on that scale, and `min_realm` is authored on it too.
const LOW_FLOOR := 2
## Ordinal 8 on the shared ladder (`RealmDefaults.ladder()`), comfortably clear of
## `LOW_FLOOR`. Named rather than inlined so the ladder stays the single source of
## truth for what ordinal 8 is.
const EIGHTH_REALM := &"great_ascension"


func setup() -> void:
	(
		ClanFixtureCatalog
		. install(
			[
				ClanFixtureCatalog.open(HOUSE),
				ClanFixtureCatalog.open(RIVAL),
				ClanFixtureCatalog.sealed(SEALED, 0.9),
				ClanFixtureCatalog.housebound(HIGH, &"commonborn"),
				ClanFixtureCatalog.ranked(LOW, 2),
			]
		)
	)


func teardown() -> void:
	ClanFixtureCatalog.teardown()


func _born(purity: float = 0.5, race_id: StringName = &"commonborn") -> Actor:
	var actor := Actor.new(&"member", {Stat.PHYSIQUE: 10.0})
	ClanApi.attach(actor)
	BloodlineApi.attach(actor)
	BloodlineApi.set_purity(actor, LINE, purity)
	RaceApi.attach(actor)
	if race_id != &"":
		RaceApi.set_race(actor, race_id)
	return actor


func _unmet(verdict: Dictionary, index: int) -> Dictionary:
	return (verdict["unmet"] as Array)[index]


func _kinds(entries: Array) -> Array:
	var out: Array = []
	for entry in entries as Array:
		out.append(String((entry as Dictionary)["kind"]))
	out.sort()
	return out


# --- The open path -----------------------------------------------------------


func test_an_actor_who_meets_the_bar_is_admitted_and_starts_at_the_bottom() -> void:
	var actor := _born(0.5)
	var verdict := ClanApi.join(actor, HOUSE)
	assert_eq(bool(verdict["ok"]), true, "admitted")
	assert_eq((verdict["unmet"] as Array).is_empty(), true, "with nothing unmet")
	assert_eq(ClanApi.clan_of(actor), HOUSE, "the clan is recorded")
	assert_eq(ClanApi.rank_of(actor), &"outer", "at the clan's entry rank, whatever it is")
	assert_eq(ClanApi.standing_of(actor), 0, "joining is not earning")
	assert_eq(actor.traits.has(ClanState.trait_for(HOUSE)), true, "the clan mirror is projected")
	assert_eq(actor.traits.has(ClanState.rank_trait_for(&"outer")), true, "and the rank mirror")


func test_a_new_member_starts_at_whatever_rung_the_clan_publishes_first() -> void:
	var def := ClanDef.new()
	def.id = &"t_short"
	def.ranks = [&"member", &"elder"]
	def.standing_bands = [0, 10]
	ClanCatalog.shared._clans["t_short"] = def
	var actor := _born()
	assert_eq(bool(ClanApi.join(actor, &"t_short")["ok"]), true, "admitted")
	assert_eq(ClanApi.rank_of(actor), &"member", "the entry rung comes from the definition")
	assert_ne(ClanApi.rank_of(actor), &"outer", "and is not a hardcoded ladder constant")


# --- The purity arm ----------------------------------------------------------


func test_join_refuses_when_the_member_does_not_carry_the_founders_line() -> void:
	var actor := _born(0.2)
	assert_eq(ClanApi.admission_unmet(actor, SEALED).size(), 1, "one complaint")
	var verdict := ClanApi.join(actor, SEALED)
	assert_eq(bool(verdict["ok"]), false, "refused")
	assert_eq(String(verdict["reason"]), "unmet", "as unmet, not as a malformed gate")
	assert_eq(_kinds(verdict["unmet"]), ["purity"], "about purity")
	var entry := _unmet(verdict, 0)
	assert_almost_eq(entry["required"], 0.9, "the bar the clan published")
	assert_almost_eq(entry["actual"], 0.2, "and what the member actually carries")
	assert_ne(String(entry["label"]), "", "with a label to render")


func test_a_refused_admission_changes_nothing_about_the_actor() -> void:
	var actor := _born(0.2)
	var before := ClanApi.state(actor)
	assert_eq(bool(ClanApi.join(actor, SEALED)["ok"]), false, "refused")
	assert_eq(ClanApi.state(actor), before, "the ledger is untouched")
	assert_eq(actor.traits.has(ClanState.trait_for(SEALED)), false, "and no mirror was left")


func test_an_unknown_clan_is_refused_rather_than_admitting_everyone() -> void:
	var actor := _born()
	var verdict := ClanApi.join(actor, &"t_no_such_clan")
	assert_eq(bool(verdict["ok"]), false, "content nothing defines admits nobody")
	assert_eq(_kinds(verdict["unmet"]), ["clan"], "and says so")
	assert_eq(ClanApi.clan_of(actor), &"", "nothing was written")


func test_a_clan_with_no_founding_line_admits_anybody() -> void:
	var actor := _born(0.0)
	var def := ClanCatalog.shared._clans[String(HOUSE)] as ClanDef
	def.founding_bloodline = &""
	def.min_purity = 0.0
	assert_eq(ClanApi.admission_unmet(actor, HOUSE), [], "no bar, no complaint")
	assert_eq(bool(ClanApi.join(actor, HOUSE)["ok"]), true, "admitted")


# --- The body-plan arm -------------------------------------------------------


func test_join_refuses_a_body_the_clan_does_not_recognise() -> void:
	var actor := _born(0.5, &"stoneborn")
	var verdict := ClanApi.join(actor, HIGH)
	assert_eq(bool(verdict["ok"]), false, "refused")
	assert_eq(_kinds(verdict["unmet"]), ["body"], "about the body plan")
	var entry := _unmet(verdict, 0)
	assert_eq(String(entry["id"]), "commonborn", "the required body")
	assert_eq(String(entry["actual"]), "stoneborn", "and the body the actor has")


func test_a_second_clan_cannot_steer_a_recognition_the_body_does_not_fit() -> void:
	var actor := _born(0.5, &"stoneborn")
	assert_eq(bool(ClanApi.join(actor, HOUSE)["ok"]), true, "a body-agnostic clan admits it")
	assert_eq(bool(ClanApi.join(actor, HIGH)["ok"]), false, "while a body-bound one does not")


func test_an_actor_with_no_race_is_refused_by_a_clan_that_names_one() -> void:
	var actor := _born(0.5, &"")
	assert_eq(bool(ClanApi.join(actor, HIGH)["ok"]), false, "refused")
	assert_eq(
		String(_unmet(ClanApi.join(actor, HIGH), 0)["actual"]),
		"",
		"and the actual body is empty rather than guessed"
	)


# --- The realm arm -----------------------------------------------------------


func _on_ladder(rank_id: StringName) -> Actor:
	var actor := _born()
	actor.set_path(PathState.new(PathState.BODY, rank_id))
	return actor


func test_join_refuses_an_actor_who_has_not_reached_the_realm_floor() -> void:
	var actor := _on_ladder(FIRST_REALM)
	var verdict := ClanApi.join(actor, LOW)
	assert_eq(bool(verdict["ok"]), false, "refused one rung short")
	assert_eq(_kinds(verdict["unmet"]), ["realm"], "about the realm")
	assert_eq(int(_unmet(verdict, 0)["required"]), LOW_FLOOR, "the floor the clan published")
	assert_eq(int(_unmet(verdict, 0)["actual"]), 0, "and the ordinal the actor reached")


func test_an_actor_with_no_path_at_all_reaches_no_ordinal() -> void:
	# The floor must not be satisfied by an actor whose rank cannot be read: an
	# unstarted path counts as 0, not as "no opinion".
	var actor := _born()
	var verdict := ClanApi.join(actor, LOW)
	assert_eq(bool(verdict["ok"]), false, "refused")
	assert_eq(int(_unmet(verdict, 0)["actual"]), 0, "on ordinal 0")


func test_an_actor_who_clears_the_realm_floor_is_admitted() -> void:
	var actor := _on_ladder(EIGHTH_REALM)
	assert_eq(ClanApi.admission_unmet(actor, LOW), [], "no complaint")
	assert_eq(bool(ClanApi.join(actor, LOW)["ok"]), true, "admitted")


# --- Clan is born from bloodline and never writes back to it -----------------


func test_passing_admission_raises_neither_purity_nor_any_stat() -> void:
	var actor := _born(0.5)
	var purity := BloodlineApi.purity_of(actor, LINE)
	var attack := actor.stats.derived(Stat.ATTACK_PHYSICAL)
	var health := actor.stats.derived(Stat.MAX_HEALTH)
	assert_eq(bool(ClanApi.join(actor, HOUSE)["ok"]), true, "admitted")
	assert_almost_eq(BloodlineApi.purity_of(actor, LINE), purity, "purity is untouched")
	assert_ne(BloodlineApi.purity_of(actor, LINE), 1.0, "and was not rounded up to 'awake'")
	assert_almost_eq(actor.stats.derived(Stat.ATTACK_PHYSICAL), attack, "no attack granted")
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), health, "no health granted")


func test_an_actor_with_no_bloodline_at_all_is_refused_a_bar_the_clan_published() -> void:
	var actor := Actor.new(&"member", {Stat.PHYSIQUE: 10.0})
	ClanApi.attach(actor)
	# Deliberately no `BloodlineApi.attach`: absence is zero concentration, not a
	# missing key, so the gate reads it rather than crashing.
	assert_almost_eq(BloodlineApi.purity_of(actor, LINE), 0.0, "carries none")
	var verdict := ClanApi.join(actor, SEALED)
	assert_eq(bool(verdict["ok"]), false, "refused")
	assert_almost_eq(_unmet(verdict, 0)["actual"], 0.0, "and the complaint reports zero")


# --- Membership is singular ---------------------------------------------------


func test_joining_a_second_clan_replaces_the_first_rather_than_stacking() -> void:
	var actor := _born()
	ClanApi.join(actor, HOUSE, 50)
	assert_eq(bool(ClanApi.join(actor, RIVAL, 20)["ok"]), true, "admitted to the second")
	assert_eq(ClanApi.clan_of(actor), RIVAL, "which replaced the first")
	assert_eq(ClanApi.standing_of(actor), 20, "with its own standing, not the old one's")
	assert_eq(actor.traits.has(ClanState.trait_for(HOUSE)), false, "the old mirror is gone")
	assert_eq(actor.traits.has(ClanState.trait_for(RIVAL)), true, "and the new one is on")
	assert_eq(
		actor.traits.has(ClanState.rank_trait_for(&"outer")),
		true,
		"the rank mirror is rebuilt at the new clan's entry rung"
	)


func test_joining_a_null_actor_is_refused_and_reads_as_nothing() -> void:
	var verdict := ClanApi.join(null, HOUSE)
	assert_eq(bool(verdict["ok"]), false, "refused")
	assert_eq(ClanApi.clan_of(null), &"", "and a null actor belongs to nothing")
	assert_eq(ClanApi.standing_of(null), 0, "with no standing")
