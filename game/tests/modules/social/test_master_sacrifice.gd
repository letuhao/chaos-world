extends TestCase

## BL-0951 / ADR 0939, S10: the master's sacrifice — a mentor spends their OWN cultivation
## so a disciple's scarred past may mend.
##
## The RELATIONSHIP is the avenue's gate and the mentor's PERMANENT decline is its price.
## Both halves are asserted, not described: the gate reads the social ladder's own bond
## (never a numeric threshold a hostile bond could satisfy), and the decline scars the
## mentor's snapshot through `FoundationApi.scar`, which is never rebuildable.
##
## The strong bond is built from the SHIPPED causes the promotion suite already climbs to
## a confidant, so the gate is satisfied by real history rather than by one act.
##
## Every loop is a bounded `for`; there is no `while`.

const MENTOR := &"elder_wei"
const REALM := &"qi_refining"
const OTHER_REALM := &"spirit_condensation"

## The shipped causes whose axes reach a confidant (standing 24.0, trust 0.59) — the same
## set `test_social_promotion._confidant` climbs, so a retune of the ladder is felt here.
const CONFIDANT_CAUSES: Array[StringName] = [
	&"shared_brotherhood",
	&"helped_in_combat",
	&"spared_in_combat",
	&"taught_technique",
	&"protected_from_death",
	&"honoured_a_debt",
]


## The catalog is a process-wide singleton and several suites author their own causes, so
## every test starts from the shipped set rather than from whatever ran before it.
func setup() -> void:
	SocialCauseCatalog.instance().install_defaults()


func _disciple() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	SocialApi.attach(actor)
	return actor


func _mentor() -> Actor:
	return Actor.new(MENTOR, {Stat.PHYSIQUE: 20.0, Stat.WILL: 20.0})


## A bond deep enough to be a mentorship: the shipped causes whose axes earn a confidant.
func _befriend(disciple: Actor) -> void:
	for cause_id in CONFIDANT_CAUSES:
		SocialApi.apply_cause(disciple, MENTOR, cause_id)


func _seed(actor: Actor, realm_id: StringName, perfection: float) -> void:
	assert_eq(
		bool(FoundationApi.snapshot(actor, realm_id, perfection).get("ok", false)),
		true,
		"seed snapshot %s at %f" % [String(realm_id), perfection]
	)


func test_a_mentor_sacrifice_mends_the_disciple_and_declines_the_mentor() -> void:
	var disciple := _disciple()
	_befriend(disciple)
	var mentor := _mentor()
	_seed(disciple, REALM, 0.1)
	_seed(mentor, REALM, 1.0)
	var age_before := disciple.age_years
	var result := SocialApi.master_sacrifice(disciple, mentor, REALM)
	assert_eq(bool(result.get("ok", false)), true, "the sacrifice resolves: %s" % str(result))
	assert_eq(
		String(result.get("reason", "")), SocialMasterSacrifice.OK_SACRIFICED, "named sacrificed"
	)
	var mended: Dictionary = result.get("mended", {})
	assert_eq(bool(mended.get("ok", false)), true, "the disciple's mend lands")
	assert_almost_eq(
		float(mended.get("after", -1.0)),
		0.1 + SocialMasterSacrifice.DISCIPLE_MEND,
		"by exactly the authored step"
	)
	assert_almost_eq(
		FoundationApi.snapshot_for(disciple, REALM),
		0.1 + SocialMasterSacrifice.DISCIPLE_MEND,
		"on the disciple's record"
	)
	var scarred: Dictionary = result.get("scarred", {})
	assert_eq(bool(scarred.get("ok", false)), true, "the mentor's decline lands")
	assert_almost_eq(
		float(scarred.get("after", -1.0)),
		1.0 - SocialMasterSacrifice.MENTOR_SCAR,
		"deepening the mentor's scar"
	)
	assert_almost_eq(
		FoundationApi.snapshot_for(mentor, REALM),
		1.0 - SocialMasterSacrifice.MENTOR_SCAR,
		"on the mentor's record"
	)
	assert_eq(float(result.get("years", 0.0)) > 0.0, true, "and the disciple spends time")
	assert_eq(disciple.age_years > age_before, true, "which really ages them")


## A sacrifice LOSES in transit: the mentor pays more than the disciple receives. This is
## what separates it from the dual-cultivation aid (S13), where the loss equals the gain.
func test_the_mentor_pays_more_than_the_disciple_gains() -> void:
	assert_eq(
		SocialMasterSacrifice.MENTOR_SCAR > SocialMasterSacrifice.DISCIPLE_MEND,
		true,
		"the mentor's decline exceeds the disciple's mend"
	)
	var disciple := _disciple()
	_befriend(disciple)
	var mentor := _mentor()
	_seed(disciple, REALM, 0.1)
	_seed(mentor, REALM, 1.0)
	SocialApi.master_sacrifice(disciple, mentor, REALM)
	var gained := FoundationApi.snapshot_for(disciple, REALM) - 0.1
	var lost := 1.0 - FoundationApi.snapshot_for(mentor, REALM)
	assert_eq(lost > gained, true, "the mentor's loss (%f) exceeds the gain (%f)" % [lost, gained])


## The gate: a stranger, or a bond below a confidant, cannot be a mentor.
func test_a_stranger_or_a_shallow_bond_cannot_be_a_mentor() -> void:
	var stranger := _disciple()
	var mentor := _mentor()
	_seed(stranger, REALM, 0.1)
	_seed(mentor, REALM, 1.0)
	var none := SocialApi.master_sacrifice(stranger, mentor, REALM)
	assert_eq(bool(none.get("ok", true)), false, "a stranger cannot be a mentor")
	assert_eq(
		String(none.get("reason", "")), SocialMasterSacrifice.R_NO_MENTORSHIP, "refused by name"
	)
	# One cause is a real bond, but not a mentorship.
	var shallow := _disciple()
	SocialApi.apply_cause(shallow, MENTOR, &"helped_in_combat")
	_seed(shallow, REALM, 0.1)
	var weak := SocialApi.master_sacrifice(shallow, mentor, REALM)
	assert_eq(bool(weak.get("ok", true)), false, "a shallow bond cannot be a mentor")
	assert_eq(
		String(weak.get("reason", "")), SocialMasterSacrifice.R_NO_MENTORSHIP, "refused by name"
	)


## A negative rung is never a mentor, whatever its magnitude — the comparison is by LADDER
## POSITION, so a hostile bond cannot satisfy the gate.
func test_a_hostile_bond_is_never_a_mentor() -> void:
	var enemy := _disciple()
	SocialApi.apply_cause(enemy, MENTOR, &"refused_the_oath")
	_seed(enemy, REALM, 0.1)
	var mentor := _mentor()
	_seed(mentor, REALM, 1.0)
	var result := SocialApi.master_sacrifice(enemy, mentor, REALM)
	assert_eq(bool(result.get("ok", true)), false, "a grudge is not a mentorship")
	assert_eq(
		String(result.get("reason", "")), SocialMasterSacrifice.R_NO_MENTORSHIP, "refused by name"
	)


func test_the_disciple_mend_stops_at_the_cap() -> void:
	var disciple := _disciple()
	_befriend(disciple)
	var mentor := _mentor()
	_seed(disciple, REALM, 0.45)
	_seed(mentor, REALM, 1.0)
	var result := SocialApi.master_sacrifice(disciple, mentor, REALM)
	var mended: Dictionary = result.get("mended", {})
	assert_almost_eq(
		float(mended.get("after", -1.0)), FoundationApi.MEND_CAP, "capped, never past it"
	)


## The decline floors at zero, and a mentor with nothing left is refused by name — the
## avenue's own natural bound on repetition.
func test_the_mentor_decline_floors_at_zero_then_refuses() -> void:
	var disciple := _disciple()
	_befriend(disciple)
	var mentor := _mentor()
	_seed(disciple, REALM, 0.1)
	_seed(mentor, REALM, 0.1)
	var first := SocialApi.master_sacrifice(disciple, mentor, REALM)
	var scarred: Dictionary = first.get("scarred", {})
	assert_almost_eq(float(scarred.get("after", -1.0)), 0.0, "the mentor's decline floors at zero")
	assert_almost_eq(FoundationApi.snapshot_for(mentor, REALM), 0.0, "on the record")
	var second := SocialApi.master_sacrifice(disciple, mentor, REALM)
	assert_eq(bool(second.get("ok", true)), false, "a ruined mentor cannot give again")
	assert_eq(
		String(second.get("reason", "")), SocialMasterSacrifice.R_MENTOR_RUINED, "refused by name"
	)


## Every refusal is named, and a refusal costs nothing (ADR 0044).
func test_refusals_are_named_and_cost_nothing() -> void:
	var disciple := _disciple()
	_befriend(disciple)
	var mentor := _mentor()
	var age_before := disciple.age_years
	_seed(disciple, REALM, 0.1)
	_seed(mentor, REALM, 1.0)
	assert_eq(
		String(SocialApi.master_sacrifice(null, mentor, REALM).get("reason", "")),
		SocialMasterSacrifice.R_NO_DISCIPLE,
		"a null disciple is named"
	)
	assert_eq(
		String(SocialApi.master_sacrifice(disciple, null, REALM).get("reason", "")),
		SocialMasterSacrifice.R_NO_MENTOR,
		"a null mentor is named"
	)
	assert_eq(
		String(SocialApi.master_sacrifice(disciple, disciple, REALM).get("reason", "")),
		SocialMasterSacrifice.R_SAME_ACTOR,
		"an actor cannot mentor themselves"
	)
	assert_eq(
		String(SocialApi.master_sacrifice(disciple, mentor, OTHER_REALM).get("reason", "")),
		SocialMasterSacrifice.R_NO_SNAPSHOT,
		"a realm the disciple never left has nothing to mend"
	)
	# A mentor who never left the named realm has no cultivation to give.
	var learner := _disciple()
	_befriend(learner)
	_seed(learner, REALM, 0.1)
	var novice := _mentor()
	assert_eq(
		String(SocialApi.master_sacrifice(learner, novice, REALM).get("reason", "")),
		SocialMasterSacrifice.R_MENTOR_NO_SNAPSHOT,
		"a mentor who never left the realm is refused by name"
	)
	assert_almost_eq(disciple.age_years, age_before, "and a refusal costs the disciple no life")


func test_a_disciple_at_the_cap_is_refused() -> void:
	var disciple := _disciple()
	_befriend(disciple)
	var mentor := _mentor()
	_seed(disciple, REALM, 0.6)
	_seed(mentor, REALM, 1.0)
	var result := SocialApi.master_sacrifice(disciple, mentor, REALM)
	assert_eq(bool(result.get("ok", true)), false, "a disciple at the ceiling has nothing to mend")
	assert_eq(
		String(result.get("reason", "")), SocialMasterSacrifice.R_MEND_CAPPED, "refused by name"
	)


## With no realm named, the transfer lands on the disciple's WEAKEST scar — the same
## default the elixir and the secret realm use, and the mentor gives in that same realm.
func test_the_realm_defaults_to_the_disciples_weakest_scar() -> void:
	var disciple := _disciple()
	_befriend(disciple)
	var mentor := _mentor()
	_seed(disciple, REALM, 0.4)
	_seed(disciple, OTHER_REALM, 0.2)
	_seed(mentor, REALM, 1.0)
	_seed(mentor, OTHER_REALM, 1.0)
	var result := SocialApi.master_sacrifice(disciple, mentor)
	assert_eq(bool(result.get("ok", false)), true, "the sacrifice resolves")
	assert_eq(String(result.get("realm", "")), String(OTHER_REALM), "on the weakest scar")
	assert_almost_eq(
		FoundationApi.snapshot_for(disciple, OTHER_REALM),
		0.2 + SocialMasterSacrifice.DISCIPLE_MEND,
		"the disciple's weakest is lifted"
	)
	assert_almost_eq(
		FoundationApi.snapshot_for(mentor, OTHER_REALM),
		1.0 - SocialMasterSacrifice.MENTOR_SCAR,
		"and the mentor declines in that same realm"
	)
	assert_almost_eq(
		FoundationApi.snapshot_for(disciple, REALM), 0.4, "the untouched realm stays put"
	)
