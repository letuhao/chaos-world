extends TestCase

## ADR 0133's OPEN scale question, MEASURED rather than ruled (BL-0348): how does the qi
## climb's damage compare with the AUTHORED boss vitality down the realm ladder?
##
## ## Why this file asserts almost nothing
##
## The question is an OWNER decision — "either boss vitality scales with realm or damage
## normalises" — and a test that encoded either answer would be a ruling by the wrong
## author. So this file measures, prints, and asserts only what is true whatever the
## ruling: the qi row is finite and strictly rising, and every hits-to-kill built from an
## authored vitality is a positive finite number. THE PRINTED TABLE IS THE DELIVERABLE.
##
## ## Where the numbers come from
##
## The damage half is the qi mechanism's own `resolve`/`mitigate` over a fixture actor
## stood at the realm (`RealmScaling` + the element realm modifiers, in the order
## `test_qi_damage_realm.gd` documents). The vitality half is the AUTHORED
## `LootTier.vitality`, read through `LootApi.domains()` so the figure moves with the
## content rather than with a copy of it: every authored tier at that realm is reported
## as min/median/max, because several encounter families (qi, mind, body) fight at one
## realm and the census must not pick a favourite.

## The realms sampled: R1, R6, R11, R16, R21, R26, R30. Read off the ladder so a retune
## cannot silently mislabel a column.
const REALM_INDICES: Array[int] = [0, 5, 10, 15, 20, 25, 29]
## A tier-2 element, so the row is not a tier-1 row measured twice. The share is
## AUTHORED because BL-0348 ruled the tuning default to `0.0`.
const ATTACKING_ELEMENT := ElementStats.LIGHTNING
## The defender's own element, distinct from the attacker's, so the matchup is a real
## read rather than a tie.
const DEFENDER_ELEMENT := ElementStats.WATER
const MEASURED_SHARE := 0.8

var _qi: Variant = preload("res://tests/modules/combat_engine/qi_damage_fixture.gd").new()
var _tuning: CombatTuning = null


func setup() -> void:
	_tuning = CombatTuning.shipped()
	_qi.setup()


## The measure, then the assertions, then the headline — one test, so the printed table
## and the pass/fail cannot come from two different runs of the arithmetic.
func test_the_damage_and_vitality_ladders_are_measured() -> void:
	var rows: Array[Dictionary] = []
	for index in REALM_INDICES:
		rows.append(_row(index))
	_print_table(rows)
	_assert_well_formed(rows)
	# The census' headline: the two growth factors over the sampled span. Printed rather
	# than asserted, because which way the ratio SHOULD go is the open question.
	var first: Dictionary = rows[0]
	var last: Dictionary = rows[rows.size() - 1]
	print(
		(
			"CENSUS qi grows %.1fx, authored vitality (median) grows %.1fx over %s -> %s"
			% [
				float(last["qi"]) / maxf(1e-9, float(first["qi"])),
				float(last["vitality_median"]) / maxf(1e-9, float(first["vitality_median"])),
				String(first["realm"]),
				String(last["realm"]),
			]
		)
	)


func _row(realm_index: int) -> Dictionary:
	var realm: RealmDef = RealmDefaults.ladder().realms()[realm_index]
	var realm_id: StringName = realm.id
	var vitality := _vitality_at(realm_id)
	return {
		"realm": String(realm_id),
		"power": float(realm.power),
		"qi": _qi_hit(realm_id),
		"vitality_min": vitality["min"],
		"vitality_median": vitality["median"],
		"vitality_max": vitality["max"],
		"count": vitality["count"],
	}


## One qi hit at `realm_id`, as the mechanism resolves and mitigates it. The defender
## carries one divisor's worth of the attacking element's DEFENSE, so mitigation is a
## real number rather than a tautological zero.
func _qi_hit(realm_id: StringName) -> float:
	var defense_points: float = _tuning.resist_divisor
	var attacker: Actor = _qi._attacker(ATTACKING_ELEMENT)
	var target: Actor = _qi._defender(ATTACKING_ELEMENT, defense_points)
	_stand_at(attacker, realm_id)
	_stand_at(target, realm_id)
	var technique: TechniqueDef = _qi._technique(ATTACKING_ELEMENT, MEASURED_SHARE)
	var ctx: AttackContext = _qi._context(
		attacker,
		target,
		ATTACKING_ELEMENT,
		MEASURED_SHARE,
		CombatSpine.base_damage(attacker, technique),
		DEFENDER_ELEMENT
	)
	var mechanism := QiDamage.new()
	mechanism.tuning = _tuning
	var resolved: DamageProposal = mechanism.resolve(ctx)
	var mitigated: DamageProposal = mechanism.mitigate(ctx, resolved)
	return mitigated.amount


## The authored vitality at `realm_id`, across every tier the loot content fights at that
## realm. `{}`-shaped: min/median/max/count, all zero when nothing is authored there —
## which the assertions treat as a census gap rather than as a zero.
func _vitality_at(realm_id: StringName) -> Dictionary:
	var values: Array[float] = []
	for entry in LootApi.domains():
		for tier in entry.get("tiers", []) as Array:
			var row := tier as Dictionary
			if StringName(row.get("realm", "")) != realm_id:
				continue
			var vitality := float(row.get("vitality", 0.0))
			if vitality > 0.0:
				values.append(vitality)
	values.sort()
	if values.is_empty():
		return {"min": 0.0, "median": 0.0, "max": 0.0, "count": 0}
	return {
		"min": values[0],
		"median": values[int(values.size() / 2)],
		"max": values[values.size() - 1],
		"count": values.size(),
	}


## Put an actor on the qi path at a realm and apply BOTH realm halves. The element half
## is re-applied because `RealmScaling.apply` clears the shared `realm` source tag
## wholesale — `test_qi_damage_realm.gd` measures that wipe, and this is the order it
## documents.
func _stand_at(actor: Actor, realm_id: StringName) -> void:
	actor.set_path(PathState.new(PathState.QI, realm_id))
	RealmScaling.apply(actor)
	ElementsApi.apply_realm_modifiers(actor)


func _assert_well_formed(rows: Array[Dictionary]) -> void:
	var previous_qi := 0.0
	var realms_with_vitality := 0
	for row in rows:
		var realm := String(row["realm"])
		var qi := float(row["qi"])
		assert_eq(is_finite(qi) and qi > 0.0, true, "%s: the qi hit is finite and positive" % realm)
		assert_eq(qi > previous_qi, true, "%s: the qi hit rises with the ladder" % realm)
		previous_qi = qi
		if int(row["count"]) <= 0:
			continue
		realms_with_vitality += 1
		var median := float(row["vitality_median"])
		var hits := median / qi
		assert_eq(
			is_finite(hits) and hits > 0.0,
			true,
			"%s: hits-to-kill from the authored vitality is positive and finite" % realm
		)
	assert_eq(
		realms_with_vitality >= rows.size() / 2,
		true,
		"at least half the sampled realms fight authored vitality, or the census is vacuous"
	)


func _print_table(rows: Array[Dictionary]) -> void:
	print("CENSUS realm | realm_power | qi_hit | vit_min | vit_median | vit_max | tiers | hits")
	for row in rows:
		var qi := float(row["qi"])
		var median := float(row["vitality_median"])
		print(
			(
				"CENSUS %s | %.3f | %.2f | %.0f | %.0f | %.0f | %d | %s"
				% [
					String(row["realm"]),
					float(row["power"]),
					qi,
					float(row["vitality_min"]),
					median,
					float(row["vitality_max"]),
					int(row["count"]),
					"n/a" if int(row["count"]) == 0 else "%.1f" % (median / qi),
				]
			)
		)
