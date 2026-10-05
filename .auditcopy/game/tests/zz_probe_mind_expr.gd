extends TestCase

## ZZ PROBE — measurement only, deleted after the run.


func _actor(id: StringName, will: float, clarity: float) -> Actor:
	var actor := (
		ActorFactory
		.build(
			id,
			{
				Stat.WILL: will,
				MindStats.MENTAL_CLARITY: clarity,
				MindStats.PERCEPTION: clarity,
				Stat.COMPREHENSION: 10.0,
			}
		)
	)
	return ActorFactory.with_mind_cultivation(actor, &"qi_refining")


func test_zz_probe_expression() -> void:
	var attacker := _actor(&"expr_attacker", 40.0, 60.0)
	var target := _actor(&"expr_target", 10.0, 5.0)
	print("\n@@@ ZZ PROBE EXPRESSION — BEGIN @@@")
	for stat_id in [
		&"mind_status_mastery_voice", &"mind_composure_voice", &"mental_clarity", &"will",
		&"mind_status_mastery_intent", &"mind_composure_intent",
	]:
		print("  attacker.derived(", stat_id, ") = ", attacker.stats.derived(stat_id))
		print("  target.derived(", stat_id, ") = ", target.stats.derived(stat_id))
	var pool := target.resource(MindVocabulary.COMPOSURE_POOL) as ResourcePool
	print("  pool = ", pool, " current = ", pool.current if pool != null else -1.0)
	var projection := MindStatusCatalog.instance().definition(&"mind_voice")
	print("  def = ", projection, " harm=", projection.harm() if projection != null else -1.0)
	var parts_null := MindExpression.breakdown(projection, target, null)
	print("  breakdown(rng=null) = ", parts_null)
	var answer_null := StatusApi.mind_confront(attacker, target, &"mind_voice", null)
	print("  confront(rng=null) = ", answer_null)
	print("  pool after = ", pool.current if pool != null else -1.0)
	var parts_seed := MindExpression.breakdown(projection, target, RandomNumberGenerator.new())
	print("  breakdown(rng=seeded) = ", parts_seed)
	print("  pool now = ", pool.current if pool != null else -1.0)
	var pair := MindStatusCatalog.instance().definition(projection.counterpart_id())
	print("  pair = ", pair.id if pair != null else "&", " recovery=", (
		pair.recovery_per_beat() if pair != null else -1.0
	))
	print("@@@ ZZ PROBE EXPRESSION — END @@@\n")


func test_zz_probe_arithmetic() -> void:
	print("\n@@@ ZZ PROBE ARITHMETIC — BEGIN @@@")
	const DISABLED_COST := 3.29 / 1.5
	print("  DISABLED_COST = ", DISABLED_COST)
	print("  1 + (1 - 0.5) * DISABLED_COST = ", 1.0 + (1.0 - 0.5) * DISABLED_COST)
	print("  1.5 * DISABLED_COST            = ", 1.5 * DISABLED_COST)
	for pair: Array in [
		["mind_daze", 0.55, 0.35, 0.35],
		["mind_hush", 0.72, 0.35, 0.30],
		["mind_falsify", 0.60, 0.30, 0.32],
		["mind_unmake", 0.70, 0.25, 0.28],
	]:
		var floor_value := float(pair[1])
		var headroom := float(pair[2])
		var steepness := float(pair[3])
		var parity := floor_value + headroom * 0.5
		var best := floor_value + headroom
		var ratio := 1.0 + (1.0 - parity) * DISABLED_COST
		print(
			(
				"  %s: floor+headroom=%.4f parity=%.4f ratio=%.6f  (with 1.5 model: %.6f)"
				% [String(pair[0]), best, parity, ratio, 1.0 + (1.0 - parity) * 4.58]
			)
		)
		print(
			(
				"      needed DISABLED_COST for ratio=2.0: %.6f  for ratio=1.5: %.6f  steepness=%.2f"
				% [(1.0 / (1.0 - parity)), (0.5 / (1.0 - parity)), steepness]
			)
		)
	print("@@@ ZZ PROBE ARITHMETIC — END @@@\n")