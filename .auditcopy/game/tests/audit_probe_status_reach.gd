extends TestCase

## AUDIT PROBE (scratch, deleted after the audit). Drives `CombatExchange.exchange`
## with each authored affinity and reports which status lands, plus whether the seven
## non-`on_landed_blow` COMBAT defs have ANY producer in `game/src`.

const DOMAIN := &"elemental_transcendent_domain"
const SWEEP := 24


func _delver(element: StringName, affinity: float) -> Actor:
	var actor := Actor.new(&"probe", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor)
	LootApi.attach(actor)
	LootApi.enter_domain(actor, DOMAIN, 1, 20260902)
	actor.set_affinity(element, affinity)
	return actor


func _probe_element(element: StringName) -> Dictionary:
	var actor := _delver(element, 0.6)
	var landed := {"id": "", "applied": 0, "tries": 0, "potency": 0.0}
	for index in SWEEP:
		var result := CombatExchange.exchange(actor, 7919 * (index + 1))
		if bool(result.get("evaded", true)):
			continue
		landed["tries"] = int(landed["tries"]) + 1
		var status := result.get("status", {}) as Dictionary
		if bool(status.get("applied", false)):
			landed["applied"] = int(landed["applied"]) + 1
			landed["id"] = String(status.get("id", ""))
			landed["potency"] = float(status.get("potency", 0.0))
	return landed


func test_audit_report() -> void:
	var report: Array = []
	report.append("=== REACHABLE VIA CombatExchange.exchange ===")
	for element in StatusDef.AUTHORED_ELEMENTS:
		var row := _probe_element(element)
		var mapped := String(StatusApi.status_for_element(element, 1.0))
		report.append(
			(
				"%-9s affinity=fire -> landed=%d applied=%d id=%-16s mapped=%-16s potency=%.4f"
				% [
					String(element),
					int(row["tries"]),
					int(row["applied"]),
					String(row["id"]),
					mapped,
					float(row["potency"])
				]
			)
		)
	report.append("--- no affinity at all ---")
	var none := _probe_element(&"", 0.0)
	report.append(
		(
			"elementless: landed=%d applied=%d id=%s"
			% [int(none["tries"]), int(none["applied"]), String(none["id"])]
		)
	)
	report.append("=== CATALOGUE ===")
	report.append(
		(
			"ids=%d rejected=%s"
			% [StatusApi.status_ids().size(), str(StatusCatalog.instance().rejected())]
		)
	)
	report.append("problems=%s" % str(StatusCatalog.instance().problems()))
	for status_id in StatusApi.status_ids():
		var def := StatusApi.definition(status_id)
		(
			report
			. append(
				(
					"%-16s element=%-9s kind=%-13s scope=%-11s unit=%-13s landed=%s cap=%.2f perm=%s"
					% [
						String(status_id),
						String(def.element),
						String(def.kind),
						String(def.scope),
						String(def.magnitude_unit),
						str(def.on_landed_blow),
						def.magnitude_cap,
						str(def.is_permanent()),
					]
				)
			)
		)
	report.append("=== CULTIVATION PRODUCERS ===")
	for status_id in StatusApi.status_ids():
		var def := StatusApi.definition(status_id)
		if def.is_combat_scope():
			continue
		var rows: Array = []
		for trial_type in TribulationBlessing.REWARD_TABLE.keys():
			var element := TribulationBlessing.REWARD_TABLE[trial_type] as StringName
			if TribulationBlessing.blessing_for(element) == status_id:
				rows.append(String(trial_type))
		report.append("%s <- trial types %s" % [String(status_id), str(rows)])
	report.append("=== BITE (ActorStats / pool) ===")
	report.append(_bite_report())
	report.append("=== VACUOUS GUARDS ===")
	report.append(_guard_report())
	print("\n".join(report))
	assert_eq(true, true, "audit probe ran")


func _bite_report() -> String:
	var out: Array = []
	for status_id in StatusApi.status_ids():
		var def := StatusApi.definition(status_id)
		var actor := Actor.new(&"bite", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
		actor.attach_core_resources()
		var stats_before: Array = []
		for entry in def.modifiers():
			stats_before.append(
				(
					"%s=%.5f"
					% [
						String(entry.get("stat", "")),
						actor.stats.derived(StringName(entry.get("stat", "")))
					]
				)
			)
		var applied := StatusApi.apply(actor, status_id, 1.0)
		var stats_after: Array = []
		for entry in def.modifiers():
			stats_after.append(
				(
					"%s=%.5f"
					% [
						String(entry.get("stat", "")),
						actor.stats.derived(StringName(entry.get("stat", "")))
					]
				)
			)
		var pool := "n/a"
		var health_before := actor.resource(&"health").maximum
		for _frame in 6:
			StatusApi.tick_statuses(actor, 1.0)
		var health_after := actor.resource(&"health").maximum
		if def.magnitude_unit == &"health_share" or def.magnitude_unit == &"element_power":
			pool = "health %.4f -> %.4f" % [health_before, health_after]
		elif (
			def.payload.get("pool", &"") == StringName("stamina")
			and actor.resource(&"stamina") != null
		):
			pool = (
				"stamina %.4f -> %.4f"
				% [actor.resource(&"stamina").maximum, actor.resource(&"stamina").maximum]
			)
		out.append(
			(
				"%-16s ok=%s before[%s] after[%s] pool[%s]"
				% [
					String(status_id),
					str(bool(applied.get("ok", false))),
					str(stats_before),
					str(stats_after),
					pool
				]
			)
		)
	return "\n".join(out)


func _guard_report() -> String:
	var out: Array = []
	var tuning := CombatEngineApi.tuning()
	out.append(
		(
			"status_min_apply=%.4f resist_cap=%.4f potency_floor=%.4f potency_scale=%.4f"
			% [
				tuning.status_min_apply,
				tuning.resist_cap,
				tuning.status_potency_floor,
				tuning.status_potency_scale
			]
		)
	)
	var actor := Actor.new(&"guard", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
	actor.attach_core_resources()
	out.append("baseline STATUS_RESISTANCE=%.5f" % actor.stats.derived(Stat.STATUS_RESISTANCE))
	for flat in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]:
		var a2 := Actor.new(&"guard", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
		a2.attach_core_resources()
		a2.stats.add_modifier(
			StatModifier.new(Stat.STATUS_RESISTANCE, Stat.Op.FLAT, flat, &"probe")
		)
		var res := float(a2.stats.derived(Stat.STATUS_RESISTANCE))
		(
			out
			. append(
				(
					"FLAT %.2f -> STATUS_RESISTANCE=%.5f ; apply_chance(1.0)=%.6f (fire, elem_resist 0)"
					% [
						flat,
						res,
						StatusApply.apply_chance(1.0, a2, tuning, 0.0, &"combat"),
					]
				)
			)
		)
	# landed-only gate: the exchange's boss guard bundle
	var a3 := _delver(&"fire", 0.6)
	var active := LootApi.summary(a3).get("active", {}) as Dictionary
	out.append("boss_guard=%s" % str(CombatExchange._boss_guard(active)))
	# max elemental resist
	for er in [0.0, 75.0, 100.0]:
		var a4 := Actor.new(&"guard", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
		a4.attach_core_resources()
		a4.stats.add_modifier(StatModifier.new(&"element_defense_fire", Stat.Op.FLAT, er, &"probe"))
		(
			out
			. append(
				(
					"element_defense_fire %.0f -> elem_resist=%.5f apply_chance=%.6f"
					% [
						er,
						StatusApply.elemental_resist(a4, a4, tuning, &"fire"),
						StatusApply.apply_chance(
							1.0,
							a4,
							tuning,
							StatusApply.elemental_resist(a4, a4, tuning, &"fire"),
							&"combat"
						),
					]
				)
			)
		)
	return "\n".join(out)
