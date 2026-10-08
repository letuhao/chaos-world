extends TestCase

## The projection trap, pinned: `NationProjection.build` SUMS the bounded percent
## of every held office, while `InstitutionProjection.grant` writes ONE percent per
## id per tag. Handing the grant the union of allowlists would grant the one
## percent and silently DROP the sum — a silent loss, worse than compounding
## because nothing looks wrong. So `apply` grants once per office under a
## PER-OFFICE tag, and this suite is the proof the sum survives: the first case
## reads 0.20 where a union-grant would leave 0.10, and the rebuild case reads the
## same sum twice where a compounding grant would climb.

const NATION := &"t_sum_nation"
const SEAT_A := &"t_seat_a"
const SEAT_B := &"t_seat_b"
## Standing 100 at the shipped rate of 0.001 is exactly the 0.10 cap.
const STANDING := 100
const PERCENT := 0.10


func _office(stats: Array) -> NationOfficeDef:
	var def := NationOfficeDef.new()
	var allow := {}
	for stat_id in stats:
		allow[String(stat_id)] = 0.0
	def.standing_percent_stats = allow
	return def


func _defs() -> Dictionary:
	return {
		String(SEAT_A): _office([Stat.PHYSIQUE]),
		String(SEAT_B): _office([Stat.PHYSIQUE, Stat.COMPREHENSION]),
	}


func _ledger() -> Dictionary:
	return {
		"standing": STANDING,
		"offices": {String(SEAT_A): "holder", String(SEAT_B): "holder"},
	}


func _hero() -> Actor:
	return Actor.new(&"holder", {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})


## How many DISTINCT source tags this module owns on the actor. `own_sources`
## answers one entry per modifier, so two stats under one office tag read as two —
## the mechanism this asserts is tags, not modifiers.
func _distinct_sources(actor: Actor) -> int:
	var tags := {}
	for source in NationProjection.own_sources(actor):
		tags[String(source)] = true
	return tags.size()


func test_two_offices_recognising_one_stat_grant_the_sum() -> void:
	var actor := _hero()
	var granted := NationProjection.apply(actor, _ledger(), _defs(), NATION)
	assert_almost_eq(float(granted.get("physique", 0.0)), 2.0 * PERCENT, "the record is the sum")
	assert_almost_eq(
		float(granted.get("comprehension", 0.0)), PERCENT, "the unshared stat grants once"
	)
	assert_almost_eq(
		NationProjection.contribution(actor, Stat.PHYSIQUE),
		2.0 * PERCENT,
		"the stack holds the sum: a union-grant would read 0.10 here"
	)
	assert_almost_eq(
		NationProjection.contribution(actor, Stat.COMPREHENSION),
		PERCENT,
		"and the unshared stat lands once"
	)
	assert_eq(_distinct_sources(actor), 2, "one source tag per office, not one per nation")


func test_reapplying_the_projection_is_free_of_consequence() -> void:
	var actor := _hero()
	NationProjection.apply(actor, _ledger(), _defs(), NATION)
	var before := NationProjection.contribution(actor, Stat.PHYSIQUE)
	NationProjection.apply(actor, _ledger(), _defs(), NATION)
	assert_almost_eq(
		NationProjection.contribution(actor, Stat.PHYSIQUE),
		before,
		"a rebuild grants the sum once, not twice"
	)
	assert_eq(_distinct_sources(actor), 2, "and still one tag per office")


func test_a_vacant_seat_grants_nothing() -> void:
	var actor := _hero()
	var ledger := {
		"standing": STANDING,
		"offices": {String(SEAT_A): "", String(SEAT_B): "holder"},
	}
	var granted := NationProjection.apply(actor, ledger, _defs(), NATION)
	assert_almost_eq(float(granted.get("physique", 0.0)), PERCENT, "only the held seat counts")
	assert_almost_eq(
		NationProjection.contribution(actor, Stat.PHYSIQUE), PERCENT, "on the stack too"
	)


func test_every_shipped_office_allowlist_validates_so_record_and_stack_agree() -> void:
	# A refused grant writes nothing for that office while the summed record still
	# counts it. Shipped content must never exercise that path: every authored id
	# must have a derivation, or holding the office would silently under-grant.
	var actor := _hero()
	var catalog := NationCatalog.instance()
	for nation_id in catalog.nation_ids():
		var offices := catalog.office_definitions(nation_id)
		for office_id in offices.keys():
			var def: NationOfficeDef = offices[office_id]
			var unknown: Variant = InstitutionProjection.unknown_stat(
				actor, def.standing_percent_stats
			)
			assert_eq(unknown, null, "%s/%s names only derivable stats" % [nation_id, office_id])
