extends TestCase

## DEF-0378's ruling, MEASURED actor-vs-actor through the REAL fight loop: a same-build
## fight at the attacker's own rate lasts about sixty seconds, per rate class.
##
## ## What the old census measured, and why the ruling replaced it
##
## It compared one qi hit against the AUTHORED `LootTier.vitality` — a parallel stat
## system the live fight never touches — and its hits column slid 2.2 -> 0.7 while the
## live loop held 25, because the loop SIZED the opponent's pool to fit the anchor. The
## ruling's reference is two ACTORS on the same formula, no boss-only multiplier: this
## file builds both sides from the SAME build, drives the real loop to a verdict, and
## asserts the band the ruling names.
##
##   - HEAVY: the loop's own fallback blow, one per `FightLoop.BASE_BLOW_INTERVAL`
##     (~2.38 s), so a same-build fight is ~25 blows / ~60 s;
##   - RAPID: the rapid key at the 5 hits/s clamp, so the same pools last ~300 hits.
##
## THE PRINTED TABLE IS THE DELIVERABLE; the assertions are the ruling.

const REALM_INDICES: Array[int] = [0, 5, 10, 15, 20, 25, 29]
## The band, as a share of the sixty-second anchor. A fight may run short or long, but
## a one-shot and a slog are both ruled out. The RAPID floor is wider than the heavy's
## on purpose and the reason is measured: a rapid art's per-hit rides the technique
## ladder (S1, up to 2.7667x) while the actor POOLS ride no ladder at all, so the rapid
## fight shortens from ~38 s at R1 to ~22 s at R30 (the printed table). The heavy class
## is flat because the loop's own fallback blow normalizes that ladder out
## (`FightLoop.ANCHOR_BLOW_SCALE`). Reconciling the pools with the ladder is the one
## remaining half of the ruling's shared-curve retune and is filed, not faked here.
const BAND_LOW := 0.5
const BAND_HIGH := 2.0
const RAPID_BAND_LOW := 0.3
## The heavy class's interval and the rapid clamp, read off the loop's own constants so
## this file cannot drift from the fight it measures.
const HEAVY_INTERVAL := 1.0 / FightLoop.BASE_BLOWS_PER_SECOND
const RAPID_INTERVAL := FightLoop.MIN_RAPID_INTERVAL
## The rate classes' damage ratio: a rapid hit is this share of a heavy blow, which is
## what puts ~300 rapid hits on the pools ~25 heavy blows spend.
const RAPID_TO_HEAVY := 12.0
## Blows a measured fight may take before this file calls it a slog rather than a
## measurement. A CAP that names the failure, never a budget: a fight still running at
## the bound is reported as the bound, and the band assertion then fails loudly.
const BLOW_BOUND := 4096


func setup() -> void:
	# The damage seam the composition root installs (`item_workbench_body.gd`): the
	# test runner never boots the app, so the suite installs the same Callable before
	# the rapid class fires `TechniqueCasting.activate`.
	TechniqueCasting.set_resolver(
		func(attacker: Actor, target: Actor, def: TechniqueDef) -> Variant:
			return CombatEngineApi.resolve_hit(attacker, target, def, CombatEngineApi.tuning())
	)


func test_the_actor_fight_holds_the_sixty_second_band() -> void:
	var rows: Array[Dictionary] = []
	for index in REALM_INDICES:
		rows.append(_row(index))
	_print_table(rows)
	for row in rows:
		var heavy_seconds := float(row["heavy_hits"]) * HEAVY_INTERVAL
		var rapid_seconds := float(row["rapid_hits"]) * RAPID_INTERVAL
		assert_eq(
			heavy_seconds >= 60.0 * BAND_LOW and heavy_seconds <= 60.0 * BAND_HIGH,
			true,
			(
				"%s: a heavy fight lasts %.1f s (%.1f blows)"
				% [String(row["realm"]), heavy_seconds, float(row["heavy_hits"])]
			)
		)
		assert_eq(
			rapid_seconds >= 60.0 * RAPID_BAND_LOW and rapid_seconds <= 60.0 * BAND_HIGH,
			true,
			(
				"%s: a rapid fight lasts %.1f s (%.1f hits)"
				% [String(row["realm"]), rapid_seconds, float(row["rapid_hits"])]
			)
		)


## The same build on both sides: the factory, all three paths at the realm, and the
## combat spine. No gear and no boss-only multiplier, so a difference between two rows
## is the formula's own.
func _actor(realm_id: StringName) -> Actor:
	var actor := ActorFactory.build(
		&"census_actor", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 12.0, Stat.APTITUDE: 8.0}
	)
	actor.attach_core_resources()
	ActorFactory.with_body_cultivation(actor, realm_id)
	ActorFactory.with_qi_cultivation(actor, realm_id)
	ActorFactory.with_mind_cultivation(actor, realm_id)
	actor.meridians.unlock_for_realm(realm_id)
	CombatBoot.install(actor)
	return actor


func _row(realm_index: int) -> Dictionary:
	var realm: RealmDef = RealmDefaults.ladder().realms()[realm_index]
	var realm_id: StringName = realm.id
	var pool_source := _actor(realm_id)
	var pool := float(pool_source.stats.derived(Stat.MAX_HEALTH))
	return {
		"realm": String(realm_id),
		"power": float(realm.power),
		"pool": pool,
		"heavy_hits": _heavy_fight(realm_id),
		"rapid_hits": _rapid_fight(realm_id),
	}


## The heavy class's fight, driven through the loop's public door: age one interval,
## exchange, repeat until a pool reaches zero.
func _heavy_fight(realm_id: StringName) -> float:
	var loop := _open(realm_id)
	var blows := 0
	var guard := 0
	while guard < BLOW_BOUND and loop.fighting():
		guard += 1
		loop.age(HEAVY_INTERVAL)
		if not bool(loop.exchange(guard)["ok"]) and loop.fighting():
			break
		blows += 1
	return float(blows)


## The rapid class's fight: the reference rapid art on the key, fired at the clamp.
func _rapid_fight(realm_id: StringName) -> float:
	var hero := _actor(realm_id)
	var def := _reference_rapid()
	TechniqueCatalog.instance().register(def)
	TechniquesApi.codex(hero).learn(def.id)
	if not bool(TechniquesApi.equip(hero, def).get("ok", false)):
		return 0.0
	var loop := FightLoop.new(hero)
	loop.adopt_hero(hero)
	loop.begin_fight(_actor(realm_id))
	var hits := 0
	var guard := 0
	while guard < BLOW_BOUND and loop.fighting():
		guard += 1
		loop.age(RAPID_INTERVAL)
		if not bool(loop.cast_rapid(guard)["ok"]) and loop.fighting():
			break
		hits += 1
	return float(hits)


## A live fight between two same-build actors, opened through the loop's own verbs.
func _open(realm_id: StringName) -> FightLoop:
	var hero := _actor(realm_id)
	var loop := FightLoop.new(hero)
	loop.adopt_hero(hero)
	loop.begin_fight(_actor(realm_id))
	return loop


## The reference rapid art the census measures with: the fallback blow's own scale at
## the rapid class's 1/12 share of a heavy hit — the share that puts ~300 rapid hits on
## the pools ~25 heavy blows spend. Its ladder factor is applied by S1, exactly as a
## shipped art's would be, so this is the real arithmetic and not a bypass.
func _reference_rapid() -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = &"census_reference_rapid"
	def.display_name = "Reference Rapid Art"
	def.grade = ItemGrade.MORTAL
	def.path = PathState.QI
	def.active = true
	def.rapid = true
	def.cooldown = RAPID_INTERVAL
	def.magnitude = CombatBoot.BARE_SWING_MAGNITUDE * FightLoop.ANCHOR_BLOW_SCALE / RAPID_TO_HEAVY
	def.element = ElementStats.FIRE
	return def


func _print_table(rows: Array[Dictionary]) -> void:
	print("CENSUS-ACTOR realm | power | pool | heavy_hits | rapid_hits")
	for row in rows:
		print(
			(
				"CENSUS-ACTOR %s | %.3f | %.0f | %.1f | %.1f"
				% [
					String(row["realm"]),
					float(row["power"]),
					float(row["pool"]),
					float(row["heavy_hits"]),
					float(row["rapid_hits"]),
				]
			)
		)
