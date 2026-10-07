extends TestCase

## ADR 0906: the status delta is realm-INVARIANT. The T10 measurement (recorded here)
## probed folding the realm power gap into the delta and found the raw gap saturates the
## 0..1 chance at any live weight — R1 vs R30 (powers 1 -> 551x) reads floor or ceiling
## immediately, and only same-tier pairs move at all — so a gap term is either dead or a
## cliff. The knob was deleted rather than left default-off, and this suite pins the
## invariant that replaced it: parity for every realm pair, in both directions, with the
## ladder's AUTHORED powers behind the probe.
##
## The probe writes `PathState.rank_id` directly — `RealmScaling.highest_realm` reads
## exactly that — so each actor's power is the ladder's authored one, not a fixture
## number restated here.


func _realm_actor(id: StringName, realm_id: StringName) -> Actor:
	var actor := CombatTestKit.actor(id)
	actor.paths[PathState.QI] = PathState.new(PathState.QI, realm_id)
	return actor


func _ladder() -> Array[RealmDef]:
	return RealmDefaults.ladder().realms()


func _chance(attacker: Actor, target: Actor) -> float:
	return StatusApply.apply_chance(
		attacker, target, CombatTestKit.shipped(), 1.0, &"", &"", &"", 0.0
	)


func test_every_realm_pair_reads_parity_in_both_directions() -> void:
	var realms := _ladder()
	assert_eq(realms.size() >= 3, true, "the ladder has realms to probe")
	var first := _realm_actor(&"tier_first", realms[0].id)
	var last := _realm_actor(&"tier_last", realms[realms.size() - 1].id)
	assert_almost_eq(
		_chance(first, last), 0.5, "the lowest realm against the highest reads parity", 1e-9
	)
	assert_almost_eq(_chance(last, first), 0.5, "and the reverse too", 1e-9)
	# The whole ladder, not just the ends: every adjacent pair reads parity.
	for index in realms.size() - 1:
		var lower := _realm_actor(StringName("tier_%d" % index), realms[index].id)
		var upper := _realm_actor(StringName("tier_%d" % (index + 1)), realms[index + 1].id)
		assert_almost_eq(
			_chance(lower, upper),
			0.5,
			(
				"realm %s against %s reads parity"
				% [String(realms[index].id), String(realms[index + 1].id)]
			),
			1e-9
		)


## The recorded measurement, kept in the run log: the raw gap across the ladder is what
## makes a gap term unshippable, and the smallest weight that would saturate the linear
## reading is DERIVED from the authored numbers rather than restated.
func test_the_measured_gap_is_why_no_gap_term_ships() -> void:
	var realms := _ladder()
	var first := realms[0]
	var last := realms[realms.size() - 1]
	var gap := last.power - first.power
	print("REALM-GAP r_first=", first.power, " r_last=", last.power, " gap=", gap)
	assert_eq(gap > 0.0, true, "the ladder's authored gap is real and positive")
	# The linear reading is `0.5 + delta / (2 * scale)`; a gap term `weight * gap` pins it
	# at the ceiling once `weight * gap >= scale`.
	var scale := CombatTestKit.shipped().status_rate_scale
	var saturating := scale / gap
	print("REALM-GAP smallest_saturating_weight=", saturating)
	assert_eq(
		saturating < 0.01,
		true,
		"the gap saturates the 0..1 delta below a one-percent weight — no live dial exists"
	)
