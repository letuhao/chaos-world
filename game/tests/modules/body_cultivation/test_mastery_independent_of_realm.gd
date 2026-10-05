extends TestCase

## ## PROPERTY 1 — MASTERY IS NOT REALM RANK
##
## The owner's first constraint, and the one that decides whether the rest of the
## system is worth anything. A body at the top of the ladder that has never held a
## maul must hold that maul at ZERO, and a body at the bottom that has swung one
## must be measurably better at it.
##
## ## The mechanism is structural, not a balance number
##
## `BodyPractice` keys mastery by WEAPON KIND — an id with no ordinal — and reads
## no realm anywhere. So this suite does not merely check the two curves happen to
## disagree today; it checks the way a realm could leak in, and that it is not
## reachable. The structural test is the one that survives a retune: it fails on
## the SOURCE, not on a number.

## The deep and the shallow ends of the shipped ladder. Any realm answers every
## read whether or not a body could walk there, which is what makes "high-realm
## novice" constructible at all.
const DEEP_REALM := &"primordial_origin"
const SHALLOW_REALM := &"qi_refining"
## `spear`, not `greatsword`: the property under test is that USE beats REALM, and the
## greatsword is gated behind `min_realm_index = 2`, so swinging one at `qi_refining` is
## refused before the loop earns anything and the assertion would be measuring the GATE
## rather than the separation. `spear` has no realm gate, which is what lets the shallow
## body actually swing.
const KIND := &"spear"
## One swing per rung of a 30-realm ladder: the cap names the ladder rather than
## being a budget to spend, and the loop exits on its own condition first.
const MAX_SWINGS := 30
## Reads that would make mastery a second copy of the ladder. `rank_id` and
## `body_realm` are here because a realm can leak in through data access as easily
## as through `RealmRate`, and the first two checks would not see either.
const _FORBIDDEN_READS := [
	"RealmRate",
	"RealmScaling",
	"RealmDefaults",
	"RealmDef",
	"rank_id",
	"body_realm",
	"realm_power",
]


## Any rung of the shared ladder, bypassing every gate. A realm is a piece of state
## here, never a prize, which is the whole point of the suite.
func _actor_at(realm_id: StringName) -> Actor:
	var actor := Actor.new(&"novice", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, realm_id))
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor, 128)
	BodyTraining.synchronize(actor)
	return actor


func _ledger(actor: Actor) -> BodyPractice:
	return actor.component(BodyCultivationApi.PRACTICE_ID)


func test_a_top_of_the_ladder_body_is_a_novice_with_an_untouched_weapon() -> void:
	var veteran := _actor_at(DEEP_REALM)
	var novice := _actor_at(SHALLOW_REALM)
	assert_eq(veteran.path(BodyPath.PATH_ID).rank_id, DEEP_REALM, "veteran is deep")
	assert_ne(
		RealmDefaults.ladder().index_of(DEEP_REALM),
		RealmDefaults.ladder().index_of(SHALLOW_REALM),
		"the two realms really are different rungs"
	)
	assert_eq(_ledger(veteran).mastery(KIND), 0.0, "a top-of-ladder body has never swung it")
	assert_eq(
		_ledger(novice).mastery(KIND), 0.0, "so does a first-realm body — neither starts ahead"
	)


## The converse, and the half that makes this a separation rather than a penalty:
## a shallow body that has USED the weapon beats a deep body that has not.
func test_use_beats_realm_for_a_single_weapon() -> void:
	var deep := _actor_at(DEEP_REALM)
	var shallow := _actor_at(SHALLOW_REALM)
	# The loop's real exit is the empty earn; the cap names the ladder's length and
	# is never reached, which is the point — a use loop that cannot converge is a
	# defect, so this one terminates on its own condition.
	var swings := 0
	while swings < MAX_SWINGS and float(BodyWeaponUse.wield(shallow, KIND)["earned"]) > 0.0:
		swings += 1
	assert_eq(swings, MAX_SWINGS, "every swing paid out — the loop is earnable to its cap")
	assert_eq(
		_ledger(shallow).mastery(KIND) > _ledger(deep).mastery(KIND),
		true,
		"a R1 body that swung beats a R30 body that did not"
	)


## The same loop, run at two realms, must pay identically. If a realm ever reached
## the payout this fails, whatever the ladders say.
func test_one_landed_strike_earns_the_same_at_every_realm() -> void:
	var shallow_report := BodyWeaponUse.wield(_actor_at(SHALLOW_REALM), &"spear")
	var deep_report := BodyWeaponUse.wield(_actor_at(DEEP_REALM), &"spear")
	assert_almost_eq(
		float(shallow_report["earned"]),
		float(deep_report["earned"]),
		"one landed spear pays the same on any rung of the ladder",
		0.0001
	)


## The structural guard, and the one that matters after a retune.
##
## `BodyPractice` is the only file that OWNS mastery. Nothing in it may read a
## realm: not the ladder, not `RealmRate`, not `RealmScaling`, not `RealmDef`.
## A value assertion cannot see a curve introduced tomorrow and a comment cannot
## see one introduced tonight — this reads the SOURCE, the same move
## `tests/core/test_realm_rate.gd` makes and for the same reason.
func test_no_realm_reads_the_mastery_ledger() -> void:
	var path := "res://src/modules/body_cultivation/practice.gd"
	var text := FileAccess.get_file_as_string(path)
	assert_ne(text.is_empty(), true, "the mastery ledger is readable")
	for name in _FORBIDDEN_READS:
		assert_eq(
			_mentions_outside_prose(text, name),
			false,
			"%s must not read `%s` — mastery is keyed by kind, never by rank" % [path, name]
		)


## Whether the file mentions `name` on any line that is not a `##` docstring. The
## comment that says "nothing here reads RealmRate" is this guard documenting
## itself, and a scan that counted it would have to be deleted in order to pass.
func _mentions_outside_prose(text: String, name: String) -> bool:
	for line in text.split("\n"):
		if line.strip_edges().begins_with("##"):
			continue
		if line.contains(name):
			return true
	return false
