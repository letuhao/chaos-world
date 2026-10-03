extends TestCase

## TEMPORARY PROBE. Not a guard, not shipped. It dumps every derived stat the body
## path produces across a scenario matrix so two implementations of the meridian
## read can be diffed byte-for-byte. Deleted before commit.


func _build(meridian_steps: int, resonance: int, integrity: float, swap: bool) -> Actor:
	var actor := (
		Actor
		. new(
			&"probe",
			{
				Stat.PHYSIQUE: 10.0,
				Stat.AGILITY: 7.0,
				Stat.SPIRIT: 3.0,
				BodyStats.BONE_DENSITY: 10.0,
				BodyStats.MUSCLE_FIBER: 10.0,
				BodyStats.ORGAN_VITALITY: 10.0,
			}
		)
	)
	BodyCultivationApi.attach(actor)
	var pool := actor.resource(BodyStats.BODY_INTEGRITY)
	pool.current = integrity
	for i in meridian_steps:
		if i == 0:
			actor.meridians.unlock_for_realm(&"qi_refining")
		actor.meridians.open_meridian(&"lung")
		actor.meridians.expand_meridian(&"lung")
		if i == 0:
			actor.meridians.strengthen_meridian(&"lung")
		else:
			actor.meridians.refine_meridian(&"lung", i)
	if resonance > 0:
		actor.meridians.set_resonance_rank(resonance)
	if swap:
		var replacement: MeridianNetwork = MeridianNetwork.from_dict(actor.meridians.to_dict())
		actor.meridians = replacement
		actor.meridians.open_meridian(&"spleen")
		actor.meridians.expand_meridian(&"spleen")
		actor.meridians.strengthen_meridian(&"spleen")
	actor.mark_stats_dirty()
	return actor


func test_probe_matrix() -> void:
	var lines: Array[String] = []
	for steps in range(0, 3):
		for resonance in [0, 2, 4]:
			for integrity in [0.0, 50.0, 100.0]:
				for swap in [false, true]:
					var actor := _build(steps, resonance, integrity, swap)
					var all := actor.stats.derived_all()
					var keys := all.keys()
					keys.sort()
					var parts: Array[String] = []
					for key in keys:
						parts.append("%s=%.10f" % [String(key), float(all[key])])
					var label := "steps=%d res=%d integ=%.1f swap=%s" % [
						steps, resonance, integrity, str(swap)
					]
					lines.append("%s | %s" % [label, ", ".join(parts)])
					# The from_dict round trip is a separate row: it is the shape the
					# save/load tests exercise.
					var restored := Actor.from_dict(actor.to_dict())
					BodyCultivationApi.attach(restored)
					restored.mark_stats_dirty()
					var rall := restored.stats.derived_all()
					var rkeys := rall.keys()
					rkeys.sort()
					var rparts: Array[String] = []
					for key in rkeys:
						rparts.append("%s=%.10f" % [String(key), float(rall[key])])
					lines.append("%s RESTORED | %s" % [label, ", ".join(rparts)])
	lines.sort()
	for line in lines:
		print("PROBE| ", line)
	print("PROBE_ROWS=", lines.size())