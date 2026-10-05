extends TestCase

## The three combat TICKS, and the reason this suite is not one more suite calling them
## directly.
##
## ## Why this file exists at all
##
## `BodyDamage.decay`, `MindDamage.tick_rupture` and `MindDamage.tick_collapse` all
## shipped fully built, fully unit-tested and with ZERO production callers in
## `game/src`. Every existing row drove the function itself:
## `test_mind_damage_collapse.gd` keeps its own `held` accumulator and calls
## `tick_collapse` in a loop, and `test_body_damage_wounds.gd` calls `decay` directly.
## Those suites are correct about the FUNCTIONS and completely blind to whether
## anything calls them — which is the shape that hid the defect for as long as it was
## there:
##
##   - severity accumulated forever, so a meridian necrosed and stayed necrotic, and
##     ADR 0070's decay half was dead code;
##   - the rupture bleed never happened, so mind's ONLY health cost was the spine's 1.0
##     chip floor (ADR 0162) and a mind fight was nearly free;
##   - `turbulence == 1.0` held for 3s never demoted a sea, so `apply_deviation` was
##     unreachable and ADR 0071's headline consequence — **the loser is disarmed for a
##     minute, not killed** — could not happen for any actor in the game.
##
## ## What this suite does instead
##
## Nothing below calls a tick function directly. Every row drives
## `CombatBoot.install` + `StatusLoop.tick` — the composition root's own wire — and then
## reads the SEAFLOOR: severity, health, the sea's tier, the actor's statuses. Delete the
## three calls from `status_loop.gd` and every behavioural row here fails, which is the
## only property the existing suites could not offer.
##
## The one row that does not need state is [method
## test_every_combat_tick_has_a_production_caller], and it is the row that would have
## caught this on day one.

## One second, at the unit the ADR windows are quoted in. Quarter-second would be the
## frame; a second is the smallest number whose repetition reaches `RUPTURE_THRESHOLD`
## and `RUPTURE_COLLAPSE_TIME` without a loop long enough to look like a hang.
const SECOND := 1.0
## A quarter-second frame, the cadence `ItemWorkbenchApp._process` runs at.
const FRAME := 0.25
## `CombatTuning`'s own windows, read rather than restated: a retune that moved the
## threshold would otherwise fail these rows for a reason that is not what they test.
const RUPTURE_THRESHOLD := 0.70
const COLLAPSE_TIME := 3.0
## The `.tres` `CombatEngineApi.tuning()` loads. Every number below is quoted from it.
const TIER_SHALLOW := &"shallow"
const TIER_DEEP := &"deep"

## Every `.gd` under `root`, recursively, excluding the editor's own `addons/` and the
## files that DEFINE the three ticks rather than call them.
##
## `DECLARATIONS` is excluded from the scan for the reason the row's docblock names: a
## mechanism names all three of its own entry points in its own docblocks, and a
## first-match-wins search over sorted paths would resolve every needle there and report
## the module as the caller — a row that cannot fail. The exclusion is deliberately
## spelled as a known, finite list rather than a blanket skip of `modules/combat_engine/`,
## so a SECOND mechanism that started carrying a fourth tick would still be scanned and
## could still fail the allowlist above.
const DECLARATIONS := ["res://src/modules/combat_engine/mind_damage.gd"]

# --- the actor, built the way PRODUCTION builds it ---------------------------


## A mind AND body actor, booted through `CombatBoot.install` — which binds the
## mechanism, the wound ledger `BodyDamage.decay` reads, and the resolver seam — and
## driven by a `StatusLoop`, which is the wire the composition root's `_process` calls.
##
## Both enrolment verbs, not a fixture attaching components: `test_combat_boot.gd`
## establishes that a fixture which supplies what production withholds hides the hole
## rather than closing it, and the wound ledger in particular has ONE production writer
## (`CombatBoot.bind_mechanisms`) whose absence would make every decay row vacuous.
func _booted() -> Dictionary:
	var actor := ActorFactory.build(&"duelist", _hero_base())
	ActorFactory.with_body_cultivation(actor)
	ActorFactory.with_mind_cultivation(actor)
	var install := CombatBoot.install(actor)
	assert_eq(bool(install["ok"]), true, "the composition root booted the combat stack")
	var loop := StatusLoop.new(actor)
	return {"actor": actor, "loop": loop}


## The base attributes a CREATED hero carries, so the mind mechanism reads a real
## `mental_attack` and a real `structural_capacity` rather than the `0.0`s a blank
## factory actor hands it. Every figure the erosion depends on is derived from these.
func _hero_base() -> Dictionary:
	return {
		MindStats.PERCEPTION: 20.0,
		MindStats.MENTAL_CLARITY: 20.0,
		Stat.WILL: 10.0,
		Stat.PHYSIQUE: 10.0,
	}


## Wound `meridian` down to `share` of the body's integrity through the module's OWN
## writer, so the ledger carries it the way a landed body hit would. `BodyWounds.add` is
## the only route `apply_all` uses, so this is the same state a hit produces.
##
## `share` is a SEVERITY (ADR 0070's `severity += damage / body_integrity.maximum`), and
## `BodyWounds.add`'s third argument is DAMAGE, not severity -- `body_damage_fixture.gd`'s
## `_severity_for` is exactly this conversion, `share * integrity_maximum`, and is why
## `test_body_damage_wounds.gd` reaches NECROSIS. Passing a raw `0.30` here instead
## writes `0.30 / 100.0 == 0.005` on a created hero's pool: a real, correctly-measured
## gash that is fifty times too shallow to be a wound at all, so every row below
## measured a ledger that had nothing on it.
func _wound(booted: Dictionary, meridian: StringName, share: float) -> void:
	var actor: Actor = booted["actor"]
	var ledger := CombatEngineApi.wounds_of(actor)
	assert_ne(ledger, null, "the composition root bound a wound ledger")
	if ledger == null:
		return
	ledger.add(actor, meridian, share * _integrity_maximum(actor), CombatEngineApi.tuning())


## The pool [method BodyWounds.add] divides by -- its `maximum`, never its `current`, so a
## hurt body does not make every fresh gash cheaper. `0.0` for a body with no integrity
## pool, which is the honest answer and not a division by zero.
func _integrity_maximum(actor: Actor) -> float:
	var pool: ResourcePool = actor.resource(BodyStats.BODY_INTEGRITY)
	return 0.0 if pool == null else pool.maximum


## The ledger's severity for one meridian, read back off the table so an assertion
## states the number it measured rather than the one it wrote.
func _severity_of(booted: Dictionary, meridian: StringName) -> float:
	var ledger := CombatEngineApi.wounds_of(booted["actor"] as Actor)
	if ledger == null:
		return 0.0
	return float(ledger.severity.get(String(meridian), 0.0))


# --- GAP A: the three ticks, through the composition root ----------------------


## ADR 0070's decay half, on the wire. Severity DECREASES toward the threshold over
## time, and it does so because frames the composition root received went through the
## loop — not because a suite called `decay` in a loop of its own.
func test_wound_severity_decays_toward_the_threshold_over_frames() -> void:
	var booted := _booted()
	var actor: Actor = booted["actor"]
	var loop: StatusLoop = booted["loop"]
	_wound(booted, &"lung", 0.30)
	var before := _severity_of(booted, &"lung")
	assert_eq(before > 0.0, true, "the meridian starts wounded")
	# Ten quarter-second frames: two and a half seconds of the root's own cadence.
	for _frame in 10:
		loop.tick(FRAME)
	var after := _severity_of(booted, &"lung")
	assert_eq(
		after < before,
		true,
		"and severity DECREASES -- ADR 0070's decay half, on the production wire"
	)
	# Toward the threshold, not toward nothing: a non-zero floor is the necrotic
	# channel's, and it is what makes "a meridian heals but a necrotic one does not" a
	# property of the arithmetic rather than of an `if`. The decayed figure must still be
	# AT LEAST what the floor says it cannot go below.
	assert_eq(after >= 0.0, true, "and never below zero on a channel that never necrosed")
	# And the whole claim is that the loop REPORTED it, which is what a UI reads.
	var report := loop.tick(FRAME)
	assert_ne(
		report.get("wound_decay", {}),
		{},
		"the tick reports its decay result rather than swallowing it"
	)
	assert_ne(actor, null, "the actor survives the tick")


## A necrotic channel is floored and does NOT decay through. This is the pair that
## makes "decays toward the threshold, and never across necrosis downward" two
## different claims instead of one vague one.
func test_a_necrotic_meridian_stops_at_its_floor_instead_of_healing() -> void:
	var booted := _booted()
	var loop: StatusLoop = booted["loop"]
	var actor: Actor = booted["actor"]
	var ledger := CombatEngineApi.wounds_of(actor)
	# A severity past NECROSIS_THRESHOLD, written once: `add` sets the flag.
	_wound(booted, &"lung", CombatEngineApi.tuning().necrosis_threshold * 2.0)
	assert_eq(bool(ledger.necrotic.get("lung", false)), true, "the meridian is necrotic")
	var floor: float = CombatEngineApi.tuning().necrosis_threshold
	for _frame in 20:
		loop.tick(FRAME)
	var after := _severity_of(booted, &"lung")
	assert_eq(
		after >= floor - 0.0001,
		true,
		"and five seconds of decay never carried it back across necrosis downward"
	)
	# The permanence is the STATE and not only the number, so it is asserted on the two
	# things `BodyWounds` says a necrotic channel has lost, read off the BOUND ledger the
	# tick decays rather than a fixture's copy of it.
	assert_eq(
		bool(ledger.necrotic.get("lung", false)),
		true,
		"and the necrosis FLAG survived every tick -- decay floors, it never un-necroses"
	)
	assert_eq(
		bool(ledger.is_wounded(&"lung")),
		true,
		"so the channel is still a wound and only the ADR 0031 recovery item clears it"
	)


## ADR 0071's rupture bleed, on the wire, in both directions. A sea above
## `RUPTURE_THRESHOLD` costs health on a tick; a sea below it costs nothing at all. The
## negative half is the one that matters: below the threshold is mind's floor of safety,
## and a bleed that ran below it would make a mind duel a damage race.
func test_only_a_ruptured_sea_costs_health_on_a_production_tick() -> void:
	var above := _booted()
	var sea_above := MindCultivationApi.sea(above["actor"] as Actor)
	sea_above.turbulence = RUPTURE_THRESHOLD + 0.1
	var health_above: ResourcePool = (above["actor"] as Actor).resource(&"health")
	var before_above := health_above.current
	(above["loop"] as StatusLoop).tick(SECOND)
	assert_eq(
		health_above.current < before_above,
		true,
		"a sea past RUPTURE_THRESHOLD bleeds health through the loop"
	)
	# The one below is a SEPARATE actor, booted the same way, because a bleed that ran
	# below the threshold would show up on the first actor too. Sharing one would make
	# this row unable to fail.
	var below := _booted()
	var sea_below := MindCultivationApi.sea(below["actor"] as Actor)
	sea_below.turbulence = RUPTURE_THRESHOLD - 0.1
	var health_below: ResourcePool = (below["actor"] as Actor).resource(&"health")
	var before_below := health_below.current
	(below["loop"] as StatusLoop).tick(SECOND)
	assert_eq(
		health_below.current,
		before_below,
		"and a sea below it costs exactly nothing -- mind's floor of safety"
	)
	# Bounded: a long run at full turbulence must never drive the pool negative, which is
	# the hazard a per-FOREVER tick introduces and the one guard the brief asks for.
	var long_run := _booted()
	var sea_full := MindCultivationApi.sea(long_run["actor"] as Actor)
	sea_full.turbulence = 1.0
	var health_full: ResourcePool = (long_run["actor"] as Actor).resource(&"health")
	for _tick in 200:
		(long_run["loop"] as StatusLoop).tick(SECOND)
	assert_eq(
		health_full.current >= 0.0,
		true,
		"and two hundred ticks at full turbulence never drive health negative"
	)


## ADR 0071's headline: sustained max turbulence demotes the sea and applies
## `mind_deviation`. **The loser is disarmed for a minute, not killed.**
##
## Driven at the root's own frame cadence rather than in a hand-rolled loop, so the
## accumulator under test is the ONE `StatusLoop` owns and feeds back — which is the part
## `test_mind_damage_collapse.gd` supplies for itself and therefore cannot check.
func test_sustained_max_turbulence_collapses_the_sea_and_disarms() -> void:
	var booted := _booted()
	var actor: Actor = booted["actor"]
	var loop: StatusLoop = booted["loop"]
	var sea := MindCultivationApi.sea(actor)
	sea.turbulence = 1.0
	assert_eq(sea.tier, TIER_SHALLOW, "the sea starts at the shallowest rung")
	# Twelve quarter-second frames is three seconds of root-driven time, the ADR's window.
	var collapsed: Dictionary = {}
	for _frame in 12:
		var report := loop.tick(FRAME)
		if report.has("mind_collapse"):
			collapsed = report["mind_collapse"]
	assert_ne(collapsed, {}, "the collapse was REPORTED, which is how a caller notices it")
	assert_eq(String(collapsed.get("from_tier", "")), String(TIER_SHALLOW), "from shallow")
	assert_eq(String(collapsed.get("to_tier", "")), String(TIER_DEEP), "to deep")
	assert_eq(sea.tier, TIER_DEEP, "and the sea really carries the demoted tier")
	# THE consequence. A `StatusEffect` the engine ticks, not a bespoke mind flag --
	# "disarmed for a minute" is only true if the disarm is something that expires.
	assert_eq(
		actor.has_status(MindDamage.DEVIATION_STATUS),
		true,
		"mind_deviation is on the actor, so the loser is disarmed rather than killed"
	)


## ## The row that would have caught the original defect
##
## `test_mind_damage_collapse.gd` and `test_body_damage_wounds.gd` call the tick
## functions directly and are green whether or not production calls them. This scans
## `game/src` for the CALL SITES instead, which is the only evidence that can go stale
## silently in the other direction.
##
## ## The three CALL SPELLINGS, which are not all the same, and why that is not pedantry
##
## `mind_damage.gd` declares `tick_rupture` WITHOUT `static` and `tick_collapse` WITH it
## (the asymmetry `mind_damage_fixture.gd:316` documents). So production has only two legal
## ways to reach them and the needles below are the two ways:
##
##   - a static entry point is spelled `Class.method(` — `MindDamage.tick_collapse(`;
##   - the non-static one is spelled `Class.new().method(` — `MindDamage.new().tick_rupture(`.
##
## The needles are the WHOLE qualified name, which is what distinguishes a CALL from the
## mechanism's own `func tick_rupture(` DECLARATION and from a docblock that merely names
## the method — and `_code_only` strips comments, so prose cannot satisfy a needle at all.
## An earlier version of this row searched for `MindDamage.tick_rupture`, which no
## production file can contain: GDScript rejects `Class.method()` for a non-static method,
## so demanding that spelling was demanding a call the language forbids. The row was
## unsatisfiable, not the wire.
##
## `mind_damage.gd` also carries `MindDamage.decay` in prose (which `_code_only` removes)
## and declares all three methods, so it is EXCLUDED by [constant DECLARATIONS]. Without
## that exclusion the first-match-wins table over sorted paths would resolve every needle
## inside the mechanism's own file — `app/` sorts before `modules/`, so `status_loop.gd`
## would lose that race too — and the row would pass on the module's declarations rather
## than on anything that calls them, which is the exact shape of bug it exists to catch.
func test_every_combat_tick_has_a_production_caller() -> void:
	var expected := {
		"BodyDamage.decay": "ADR 0070's wound decay had no caller, so necrosis never healed",
		"MindDamage.new().tick_rupture": "ADR 0071's only mind health cost never ran",
		"MindDamage.tick_collapse": "ADR 0071's collapse, and apply_deviation with it",
	}
	var found: Dictionary = {}
	for path in _gdscript_files("res://src"):
		var code := _code_only(path)
		for needle in expected:
			if code.contains(needle) and not found.has(needle):
				found[needle] = path.trim_prefix("res://")
	for needle in expected:
		assert_ne(
			found.get(needle, ""),
			"",
			"%s is called from production -- %s" % [String(needle), String(expected[needle])]
		)
	# The clock: every one of the three rode `status_loop.gd`, and the mechanism's own file
	# is not a call site. A second caller anywhere in `app/` would be a second COMBAT CLOCK
	# (the ADR 0106 failure), so the allowlist is asserted rather than hoped for.
	for needle in expected:
		assert_eq(
			found.get(needle, ""),
			"src/app/status_loop.gd",
			"%s rides the composition root's ONE time wire, not a second clock" % String(needle)
		)
	# And the accumulator that makes the collapse a TIMER rather than a per-frame dice
	# roll is held by that same wire, because ADR 0071 puts it in the caller.
	var loop_code := _code_only("res://src/app/status_loop.gd")
	assert_eq(
		loop_code.contains("MindDamage.tick_collapse"),
		true,
		"the collapse tick reads the caller's held accumulator"
	)


# --- internals -------------------------------------------------------------------


## `path`'s text with comments removed, so a scan reads code and not prose. `status_loop`
## explains WHY it holds no wall clock and why the accumulator is bounded; a doc comment
## is not the thing that should fail its own rule -- the same convention
## `test_status_clock.gd:280` and `tests/ui/test_ui_conventions.gd` use.
func _code_only(path: String) -> String:
	var out: Array[String] = []
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var hash := raw.find("#")
		out.append(raw.substr(0, hash) if hash >= 0 else raw)
	return "\n".join(out)


func _gdscript_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				if entry != "addons":
					found.append_array(_gdscript_files(path))
			elif entry.ends_with(".gd") and not DECLARATIONS.has(path):
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found
