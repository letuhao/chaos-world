extends SceneTree

## Headless UI driver (ADR 0039). Runs a screen with no window, applies a script
## of commands, and prints one JSON document per step plus a final state.
##
## This is the code path a player drives: it calls the screen's public `setup`,
## `act_*` and `summary` methods rather than reaching into widgets, so an LLM
## reading this output sees exactly what a human sees. Nothing here bypasses the
## facade-only rule, so the driver cannot drive a screen the player could not.
##
## Usage:
##   godot --headless --path game -s res://tools/ui_driver.gd -- \
##     --screen res://src/ui/screens/body_cultivation_panel.tscn \
##     --path body --cmd summary --cmd act_cultivate
##
## Commands: `summary`, `refresh`, `focus_initial`, or any `act_<verb>` the
## screen exposes. An unknown verb is reported, never silently ignored.

const ACTOR_ID := &"cli_hero"
const EXIT_OK := 0
const EXIT_ERROR := 1
## Large enough for the seed items plus whatever a caller grants. The default
## inventory slot count fills up during seeding, which made `grant` silently add
## nothing.
const SLOT_CAPACITY := 512
## The session file. An LLM drives the game over many invocations, so the actor
## has to survive between them or no progress is ever observable.
const SESSION_PATH := "user://ui_cli_session.json"
## The readout's demo swing, priced so one press wounds without necrosing.
##
## ## Why the magnitude is `0.05` and it is a BODY swing now
##
## `BodyWounds.add` divides a strike's damage by the target's `body_integrity.maximum`,
## and `BodyDamage` prices a hit as `magnitude x ATTACK_PHYSICAL x <point multiplier>` —
## so the magnitude is multiplied by the thrower's own offense stat rather than being the
## damage. The harness hero is built `{PHYSIQUE: 20, COMPREHENSION: 10}`, so
## `ATTACK_PHYSICAL` reads `40.0` and one blow at `0.05` carries a severity of `0.2`.
##
## At the old `12.0` that was 600 damage, a severity of `6.0`, and **necrosis on the
## first press** — a permanent, irreversible loss (ADR 0070), which makes the wound arc
## this surface exists to show unreadable after one click. `0.05` is the middle of the
## band: one blow wounds (`WOUND_THRESHOLD` `0.05`), several accumulate visibly, and
## necrosis arrives after about six — which is the arc, in order, rather than all at
## once. Every figure here is fixture arithmetic and none of it reaches `game/data`.
const DRILL_MAGNITUDE := 0.05
## The magnitude an AUTHORED technique (`--technique`) is fired at, and the only
## difference from [constant DRILL_MAGNITUDE].
##
## ## Why the two numbers and not one
##
## `BodyWounds.add` divides a strike by the target's `body_integrity.maximum`, and the
## multiplier a `named` aim lands is whatever the AUTHORED meridian's best point reads —
## not the `lung` figure the synthetic def happens to produce. At `0.05` a `named` aim at
## a meridian with a weaker point multiplier lands under `WOUND_THRESHOLD` and the
## readout printed `No meridian carries a wound.`, which reads as "the aim was ignored"
## when the aim in fact worked: the reader had no way to see the meridian at all. One
## wound per strike is what makes the meridian legible on the panel, which is the whole
## point of firing shipped content.
##
## Still fixture arithmetic — it never reaches `game/data` — and it multiplies the
## technique's own `magnitude` nowhere: the harness overwrites `magnitude` with this, so
## the authored LADDER is not being measured, only the authored aim.
const DRILL_AUTHORED_MAGNITUDE := 0.2
const DRILL_SHARE := 0.8
## The fire affinity the qi drill swings with, so `element_power_fire` is non-zero and
## ADR 0069's elemental term is visible on the readout rather than reading `0.0` for
## lack of any affinity at all. Fixture arithmetic, same as `DRILL_MAGNITUDE`.
const DRILL_AFFINITY := 10.0
## The fixed seed the demo swing's generator is built from, so a re-run reproduces the
## same fight rather than printing a different verdict each invocation. Fixture
## arithmetic, same as [constant DRILL_MAGNITUDE].
const DRILL_SEED := 20260904
## The meridian the demo swing is aimed at.
##
## `body_cultivation`, not `qi_cultivation`, and that is the difference between a readout
## that prints a row and one that cannot: `QiDamage` emits no `effects[]` and its whole
## floor is the S8 chip, so every qi blow on a real `commonborn` reads `S4 proposed 0.00`
## and `S6 amount 1.00` — the chip floor doing all the work and the mechanism doing none.
## `BodyDamage` emits one `body.wound` effect per struck site (ADR 0070), so a body
## technique is the ONLY way this surface can render a wound, and a wound row is half
## of what the panel exists for.
##
## `&"lung"` is a real meridian — `game/data/body_cultivation/acupoints/minor_0.tres`,
## `minor_12.tres` and `minor_24.tres` all name it — so this is not an invented aim id.
## It is applied on the BODY path ONLY, matching production's `_readout_technique`: a
## `mind` swing carries no body aim id, because no shipped `TechniqueDef` ever does.
const DRILL_MERIDIAN := &"lung"

var _screen: Node = null
var _actor: Actor = null
## The path the drive armed through the screen's selector, or `&""` when the caller used
## `--path` (or neither). Separate from `_drill_path` so both routes reach `_drill_def`:
## a `--path mind` drive and a drive that cycled to mind must fire the LITERAL same
## technique, which is the whole point of aligning the harness to production.
var _drill_chosen: StringName = &""
## The combat readout's drill body, built once in `_bind_read_models` and kept for the
## life of the run. A wound is a fact about a body that persists, so a fresh body per
## invocation would make the wound row unreadable.
var _drills: Actor = null
## The fight this drive is running, for a `--screen` that asked to fight (ADR 0197). Null
## for every other screen, and `_bind_fight_screen` is the only thing that writes it.
var _fight: FightLoop = null
var _failures: Array[String] = []


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var screen_path := _option(argv, "--screen")
	if screen_path.is_empty():
		_emit({"event": "error", "error": "--screen is required"})
		quit(EXIT_ERROR)
		return
	_screen = _instantiate(screen_path)
	if _screen == null:
		_emit({"event": "error", "error": "could not instantiate %s" % screen_path})
		quit(EXIT_ERROR)
		return
	_bootstrap_actor(argv)
	_bind_read_models()
	_emit(
		{
			"event": "ready",
			"screen": screen_path,
			"name": String(_screen.name),
			"fresh": not _loaded_session,
		}
	)
	for command in _commands(argv):
		_run_command(command)
	_save_session()
	_emit({"event": "final", "summary": _screen.summary()})
	quit(EXIT_OK if _failures.is_empty() else EXIT_ERROR)


# --- Actor ------------------------------------------------------------------

var _loaded_session := false


## Build or resume the actor the screen renders. Screens drive real gameplay
## state, so the driver hands them a real actor on a real path rather than a
## stub. A saved session is resumed unless `--fresh` asks for a clean one, which
## is what makes progress observable across invocations.
func _bootstrap_actor(argv: PackedStringArray) -> void:
	if not _screen.has_method("setup"):
		return
	_actor = Actor.new(ACTOR_ID, _base_attributes(_option(argv, "--path")))
	ItemsApi.attach(_actor, SLOT_CAPACITY)
	var path_id := _option(argv, "--path")
	var fresh := argv.has("--fresh")
	if not fresh and _restore_session(path_id):
		_screen.call("setup", _actor)
		return
	_attach_path(path_id)
	_stock_seed_items()
	_screen.call("setup", _actor)


## ## Why the base is PATH-SHAPED and not one literal
##
## The hero used to be built `{PHYSIQUE: 20, COMPREHENSION: 10}` — numbers chosen for
## the BODY drill swing alone (see `DRILL_MAGNITUDE`). So `--path qi` and `--path mind`
## produced an actor whose `spirit`, `aptitude` and `will` were all `0.0`, which is
## exactly the allocation that made qi propose nothing: the harness had been measuring
## the inert case and calling it the mechanism.
##
## The qi half now carries `SPIRIT`/`APTITUDE`/`WILL` and the mind half carries
## `WILL` plus the two `MindStats` attributes `MindProvider` reads, so each drill
## resolves through the mechanism it was asked for. `--path body` and a pathless
## invocation keep the original two-attribute build EXACTLY, because that is the
## severity arithmetic the wound arc is priced against and re-pricing it would move
## a shipped constant for no reason.
##
## These are fixture arithmetic and none of it reaches `game/data`.
func _base_attributes(path_id: String) -> Dictionary:
	var base := {Stat.PHYSIQUE: 20.0, Stat.COMPREHENSION: 10.0}
	match _canonical_path(path_id):
		String(QiPath.PATH_ID):
			base[Stat.SPIRIT] = 10.0
			base[Stat.APTITUDE] = 10.0
			base[Stat.WILL] = 10.0
		String(MindPath.PATH_ID):
			base[Stat.WILL] = 10.0
			base[MindStats.PERCEPTION] = 10.0
			base[MindStats.MENTAL_CLARITY] = 10.0
	return base


## Give a screen whatever read model it asks for by name. Some screens are not a
## plain view of the actor: `loot_encounter` takes a [LootBridge] of plain
## callables, because `loot` is not one of the modules `rules.UI_MODULES` declares
## and `ui/` may not name `LootApi`. Without this the driver instantiated the
## screen, bound nothing, and every verb read as "not available" — so a live
## feature measured as dead, and BL-0320 was filed against the game when the fault
## was the instrument. Mirrors `ItemWorkbenchApp._bind_route_screen`, which is the
## production site for the same wiring.
func _bind_read_models() -> void:
	if _actor == null:
		return
	if _screen.has_method("bind_bridge"):
		LootApi.attach(_actor)
		_screen.call("bind_bridge", _loot_bridge())
	if _screen.has_method("bind_strike"):
		_drills = _build_drills()
		# The same composition-root verbs the app uses, in the same order: enrol the
		# paths, THEN install. `CombatBoot.bind_mechanisms` reads `acupoints` /
		# `sea_of_consciousness` off the actor to choose a mechanism, and
		# `ActorFactory` enrols only after `build` returns — so installing first
		# measures every path's inputs as absent.
		ActorFactory.with_body_cultivation(_actor)
		ActorFactory.with_qi_cultivation(_actor)
		# Mind needs its sea on BOTH ends before `mechanism_for_hit` will let a mind
		# technique run at all: that gate asks whether the ATTACKER carries a sea, and
		# `MindDamage` erodes the DEFENDER's. Without the enrolment below, `--path mind`
		# silently fell back to the installed mechanism and the caller could not tell.
		ActorFactory.with_mind_cultivation(_actor)
		MindCultivationApi.attach_sea(_actor)
		MindCultivationApi.attach_sea(_drills)
		# `attach_sea` sizes a sea off a BASE attribute nobody allocates, and
		# `MindDamage` divides by `structural_capacity` — so without this
		# synchronize the drill's erosion was `0.0 / 0.0 == 0.0` and the mind line read
		# all zeros for a reason that had nothing to do with the mechanism. The DRILL
		# body needs the path too, not just the sea: `MindTraining.synchronize` returns
		# early on a pathless actor, which is what left the sea this mechanism erodes at
		# a capacity of `0.0` and the erosion with it. This is the same call
		# `_reattach_components` makes for `--path mind`.
		ActorFactory.with_mind_cultivation(_drills)
		MindTraining.synchronize(_actor)
		MindTraining.synchronize(_drills)
		# `ElementProvider` derives `element_power_<e>` from AFFINITY, and the qi drill
		# authors a `fire` element. A hero with no affinity reads `0.0` for it, so the
		# elemental term — the half of ADR 0069 the readout exists to show — was
		# `0.0` and only the raw term could carry a number. `ActorFactory.build` mounts
		# the provider, so this is a write on the actor, never a second attach.
		if _drill_path() == PathState.QI:
			_actor.set_affinity(ElementStats.FIRE, DRILL_AFFINITY)
			_drills.set_affinity(ElementStats.FIRE, DRILL_AFFINITY)
		# `ElementProvider` is idempotent and `ActorFactory.build` does NOT mount it —
		# the UI driver builds its hero with `Actor.new`, not through the factory, so
		# without this line `element_power_<e>` read `0.0` on both ends however much
		# affinity the actor held, and ADR 0069's elemental term was structurally dead
		# on the one surface that prints it. Both actors are on no realm, so
		# `apply_realm_modifiers` writes nothing and this attaches the provider alone.
		ElementsApi.attach(_actor)
		ElementsApi.attach(_drills)
		CombatBoot.install(_actor)
		CombatBoot.install(_drills)
		_screen.call(
			"bind_strike", Callable(self, "_drill_blow"), _drills, Callable(self, "_drill_context")
		)
		# The TECHNIQUE SELECTOR, the SAME seam the production route binds and for the
		# same reason: without it the screen can fire exactly one mechanism, so `--path`
		# would change the hero and nothing else — the instrument fault `_drill_path`'s
		# own docblock is about, repeated one layer up. Guarded by `has_method` so a
		# screen without the seam degrades to its own named refusal rather than aborting
		# the whole binding, exactly as `_bind_target_screen` guards the cast arm.
		if _screen.has_method("bind_technique"):
			_screen.call(
				"bind_technique", Callable(self, "_drill_select"), Callable(self, "_drill_armed")
			)
	if _screen.has_method("bind_fight"):
		_bind_fight_screen()


## The FIGHT seam (ADR 0197), which this driver could not bind and so measured as dead.
##
## ## Why this arm exists at all
##
## `bind_fight` was absent here, so a `--screen fight_screen.tscn` drive mounted the page,
## found all five verbs empty, and answered `no_fight_seam` on every press — the exact
## BL-0320 shape (`_bind_read_models`'s own docblock): a live feature measured as dead
## because the fault was in the INSTRUMENT, not the feature. The screen's own refusal was
## honest and the harness could not tell it apart from a game that cannot fight.
##
## ## And why the loop is MINTED here
##
## `FightLoop` is an `app/` type and this driver is a bare `SceneTree` with no composition
## root, so there is nothing to borrow a loop from. The harness builds the one the root
## would have built — `ItemWorkbenchApp` binds `ItemWorkbenchFight`'s verbs, and those
## are five `Callable`s over a `FightLoop` this file cannot name either. The five verbs
## below are therefore the SEAM, written out longhand: each one is the same call the root
## makes, so a fight driven here and a fight driven in the game resolve through the same
## spine on the same actors.
##
## The hero must carry `acupoints` and a sea before `CombatBoot.install` will let a
## mechanism run at it, and `start_fight` reads the opponent's enrolment to choose the
## path — so both actors are enrolled here in the same order the root uses: enrol, THEN
## install.
func _bind_fight_screen() -> void:
	if _actor == null:
		return
	# The order is the one `ItemWorkbenchBody._build_readout_target` documents and is not
	# optional: enrol the paths, THEN install, because `CombatBoot.bind_mechanisms` reads
	# `acupoints` / `sea_of_consciousness` off the actor to CHOOSE a mechanism and
	# installing first measures every path's inputs as absent. `start_fight` unlocks the
	# opponent's own twenty channels for the same reason on the other side.
	ActorFactory.with_body_cultivation(_actor)
	ActorFactory.with_qi_cultivation(_actor)
	ActorFactory.with_mind_cultivation(_actor)
	MindCultivationApi.attach_sea(_actor)
	MindTraining.synchronize(_actor)
	# ADR 0070: an aim at a meridian the target never unlocked is not struck at all, so
	# the HERO is unlocked too and not only the opponent `start_fight` builds.
	_actor.meridians.unlock_for_realm(&"qi_refining")
	CombatBoot.install(_actor)
	_fight = FightLoop.new(_actor)
	_screen.call("bind_fight", _fight_verbs())
	_screen.call("bind_combat_exit", Callable(self, "_empty_purge"))


## The five ADR 0197 verbs, as `ItemWorkbenchFight.fight_verbs` publishes them.
##
## `_fight_exchange` passes **no seed**, exactly as `_fight_exchange` in the root does: a
## null generator means every strike lands (ADR 0087's S12), so a drive measures the
## engine's arithmetic rather than a sample of it. A reproducible run is a caller's
## decision, passed in as the seed it supplies.
func _fight_verbs() -> Dictionary:
	return {
		"begin": _fight_begin,
		"exchange": _fight_exchange,
		"age": _fight_age,
		"disengage": _fight_disengage,
		"read": _fight_read,
	}


func _fight_begin() -> Dictionary:
	if _fight == null:
		return {"ok": false, "reason": "no_fight_loop"}
	return _fight.start_fight()


func _fight_exchange() -> Dictionary:
	if _fight == null:
		return {"ok": false, "reason": "no_fight_loop"}
	return _fight.exchange(0)


func _fight_age(seconds: float) -> Dictionary:
	if _fight == null:
		return {"ok": false, "reason": "no_fight_loop"}
	return _fight.age(seconds)


func _fight_disengage() -> Dictionary:
	if _fight == null:
		return {"ok": false, "reason": "no_fight_loop"}
	return _fight.disengage()


func _fight_read() -> Dictionary:
	if _fight == null:
		return {}
	return _fight.summary()


## ADR 0089's combat-exit purge. A no-op here rather than a refusal: the driver holds no
## `StatusLoop`, so there is no combat-scope status to clear, and a screen that cannot
## purge must still be able to end a fight.
func _empty_purge() -> Array[String]:
	return []


## The harness half of the selector seam: arm the path `--path` asked for, refusing
## anything outside `PathState.ALL` for the reason the production seam does — an unknown
## id accepted here would silently resolve to the default and a caller would measure the
## wrong mechanism believing it had chosen one.
func _drill_select(path: Variant) -> bool:
	var wanted := StringName(path) if path is StringName or path is String else &""
	if not PathState.ALL.has(wanted):
		return false
	_drill_chosen = wanted
	return true


## The read half: no argument answers the armed path, `&"paths"` answers the whole set.
## The armed path is re-derived through `_drill_path` when `--path` named one, so a drive
## with `--path mind` and a drive that cycled to mind fire the LITERAL same def.
func _drill_armed(question: Variant = &"") -> Variant:
	if StringName(question) == &"paths":
		var out: Array[StringName] = PathState.ALL
		return out
	return _armed_drill_path()


## The path the demo swing is asked to travel.
##
## `TechniqueDef.path` is what `CombatBoot.mechanism_for_hit` reads (ADR 0161), and
## this driver hard-coded `PathState.BODY` on the one surface whose entire job is to
## read every stage of the spine. So `--path qi` and `--path mind` changed the HERO
## and changed nothing about the blow: the swing still asked for body, still resolved
## through `BodyDamage`, and the readout printed a wound row no matter which
## mechanism the caller came to measure. A flag that does not change the mechanism is
## an instrument fault wearing a feature's clothes — the same shape BL-0320 was
## filed for.
##
## Empty for an unknown `--path`, which reproduces the old fixed body swing exactly.
func _drill_path() -> StringName:
	match _canonical_path(_option(OS.get_cmdline_user_args(), "--path")):
		String(QiPath.PATH_ID):
			return PathState.QI
		String(MindPath.PATH_ID):
			return PathState.MIND
		String(BodyPath.PATH_ID):
			return PathState.BODY
	return &""


## What the swing fires THIS time, resolving the two ways a caller can name a path: the
## screen's selector (`_drill_chosen`, set by `act_cycle_path` / `act_choose_path`) wins
## over the `--path` flag, because a verb the caller typed after the flag is the more
## specific instruction. With neither, it is `--path` alone, so a bare drive behaves
## exactly as it did before the selector existed.
func _armed_drill_path() -> StringName:
	if _drill_chosen != &"":
		return _drill_chosen
	return _drill_path()


## The drill body the readout strikes, built through the SAME composition-root verbs
## `ItemWorkbenchApp._build_readout_target` uses (ADR 0174): `spawn_inhabitant` plus a
## body enrolment, so the target carries an `acupoints` set and a wound ledger and a
## body technique lands at a real meridian. It lives here for the reason `_loot_bridge`
## does — a screen cannot mint an `Actor`, because `app/` is a `PRIVATE_UNIT`.
##
## Built ONCE and kept: a fresh body per invocation would make the wound ledger
## unreadable, because a wound is a fact about a body that persists.
##
## ## Why `unlock_for_realm` is here and not only the enrolment
##
## `ActorFactory.with_body_cultivation` builds the integrity pool, the provider and the
## meridian NETWORK, but it does not open any channel — a freshly enrolled body is a
## sheet of twenty closed meridians. ADR 0070 is explicit that a `named` aim at a
## meridian this body has never unlocked is NOT struck at all ("there is no channel there
## to subtract from"), so every authored `aim_meridian` resolved to the empty site,
## `sites[]` was empty, and the readout printed `No meridian carries a wound.` for a
## technique whose aim was authored and correct. That is the same defect the whole body
## fixture exists to prevent (`body_damage_fixture.gd:110` makes the same call), and a
## readout that cannot show a named aim cannot be used to verify one.
##
## `qi_refining` is the realm index the shipped meridian defs unlock at tier 0, so all
## twenty channels exist — a body `random` aim has something to choose between as well.
func _build_drills() -> Actor:
	var drill := ActorFactory.spawn_inhabitant(&"readout_drills")
	ActorFactory.with_body_cultivation(drill)
	drill.meridians.unlock_for_realm(&"qi_refining")
	return drill


## One blow for the readout, resolved through the SAME production entry point
## `ItemWorkbenchApp._readout_blow` calls — `CombatBoot.resolve_hit` — with a SEEDED
## generator so the swing is reproducible but still random, which is what a live fight
## has. A demo swing on the BODY path at a magnitude priced so one press wounds without
## necrosing — see [constant DRILL_MAGNITUDE].
##
## ## Why the generator is SEEDED and not `null`
##
## `null` is the right answer for the PRODUCTION readout (`_readout_blow` passes it, so
## every blow lands and a whiff is never shown). But ADR 0087's S12 refuses a `null`
## generator outright — "a null `rng` means NO DRAW and NO STATUS, never a `randf()`
## fallback" — so a null-rung drill reported `status withheld: no rng` for a reason that
## had nothing to do with the status producer and could not show S12 landing at all. The
## harness's job is to exercise the spine, and a seeded generator is exactly what a real
## caller injects, so the drill carries one: every blow still lands (the harness's band
## passes nothing that can miss at these stats), and the status roll is live. The seed is
## fixed so a re-run reproduces the same fight.
func _drill_blow(attacker: Actor, defender: Actor) -> Dictionary:
	if attacker == null or defender == null:
		return {}
	var def := _drill_def()
	var rng := RandomNumberGenerator.new()
	rng.seed = DRILL_SEED
	return CombatBoot.resolve_hit(attacker, defender, def, CombatEngineApi.tuning(), rng).to_dict()


## The readout's companion read: `{band, actor, mechanism}`, all primitives — the same
## shape `ItemWorkbenchApp._readout_context` hands the same screen, and for the same
## reason: the band roll and the stat line are separate facade reads and the mechanism is
## `CombatBoot`'s own per-hit answer, and none of the three is a field of `to_dict()`.
##
## Re-asking `mechanism_for_hit` here rather than stashing what the strike chose is
## deliberate: it is the SAME named question with the SAME inputs, so the two answers
## cannot disagree, and a screen that received the mechanism as a fourth field on the
## outcome payload would be trusting a value the engine never wrote.
func _drill_context() -> Dictionary:
	return {
		"band": CombatEngineApi.band(_actor, _drills, CombatEngineApi.tuning(), null),
		"actor": CombatEngineApi.summary(_actor),
		"mechanism": CombatBoot.mechanism_for_hit(_actor, _drill_def()),
	}


## The drill swing's authored inputs, built once for the life of the run so the strike
## and the context read literally the same def.
##
## ## WHY THIS NOW SHAPES ITS FIELDS THE WAY PRODUCTION DOES
##
## The production readout (`ItemWorkbenchApp._readout_technique`) fires a `TechniqueDef`
## whose fields depend on the path: `aim_meridian` on BODY, `element` on QI, nothing extra
## on MIND. This used to pin `aim_meridian` UNCONDITIONALLY, so `--path mind` measured a
## def carrying a body aim id into `MindDamage` — a shape the shipped game never builds.
## A harness that fires a technique production cannot build is measuring a different game,
## which is the whole defect: `tools ui drive` was answering questions about a fixture.
## The three per-path writes below are the same three `item_workbench_readout.gd` makes,
## so a drive and a route now produce the same def for the same `--path`.
##
## `--technique <id>` substitutes the SHIPPED `.tres` for this synthetic def, and that
## substitution is the only way a terminal can measure AUTHORED content. The synthetic
## def pins `aim_meridian` to [constant DRILL_MERIDIAN] and sets no element, so a drive
## run without the flag measures the harness's fixture — not one line of the 52 authored
## `.tres` — and would report a body path that resolves `random` while every shipped
## technique in fact names a meridian. `aim_meridian`, `element`, `element_share` and
## `mind_kind` are read as authored, because those are the content under test; only
## `magnitude` is replaced, and with [constant DRILL_AUTHORED_MAGNITUDE].
func _drill_def() -> TechniqueDef:
	var authored := _authored_def()
	if authored != null:
		return authored
	var def := TechniqueDef.new()
	var asked := _armed_drill_path()
	# A DUAL spelling is what `path_ids()` is for, but this harness asks for ONE path or
	# none, so an empty answer falls back to the body swing the driver has always made
	# rather than to a pathless technique that would take the installed mechanism.
	def.path = asked if asked != &"" else PathState.BODY
	def.magnitude = DRILL_MAGNITUDE
	def.element_share = DRILL_SHARE
	# Mind is the one path whose inputs are not an OFFENCE stat: `MindDamage` reads
	# `MENTAL_ATTACK` and erodes a sea, it never spends an amount. Without an authored
	# element the qi swing still resolves (`share` falls back to the tuning default),
	# but an element makes the readout's elemental term visible, which is the half of
	# ADR 0069 the panel exists to show.
	if def.path == PathState.QI:
		def.element = ElementStats.FIRE
	elif def.path == PathState.BODY:
		def.aim_meridian = DRILL_MERIDIAN
	return def


## The shipped `TechniqueDef` `--technique` names, or null when the flag is absent or the
## id is unknown.
##
## Resolved through `TechniqueCatalog` — the SAME content tree the game loads, walked by
## declared `id` rather than by filename (ADR 0056) — so a drive that names
## `body_tiger_palm` fires the def a live cast would, and an unknown id is REPORTED
## rather than silently falling back to the fixture. A silent fallback is the instrument
## fault this whole flag exists to remove: a harness that quietly measured its own fixture
## while the caller believed it was measuring shipped content is BL-0320 wearing a
## feature's clothes.
##
## `duplicate(true)` because a `.tres` is a SHARED resource: the catalogue hands back ONE
## instance per id, and writing `magnitude` onto it would mutate every other reader of
## that content for the rest of the process. The copy is what the harness edits.
func _authored_def() -> TechniqueDef:
	var wanted := _option(OS.get_cmdline_user_args(), "--technique")
	if wanted.is_empty():
		return null
	var def := TechniqueCatalog.instance().definition(StringName(wanted))
	if def == null:
		_emit({"event": "error", "command": "technique", "error": "no such technique: " + wanted})
		_failures.append("technique")
		return null
	var copied := def.duplicate(true) as TechniqueDef
	copied.magnitude = DRILL_AUTHORED_MAGNITUDE
	return copied


func _loot_bridge() -> LootBridge:
	var bridge := LootBridge.new()
	bridge.list_domains = Callable(LootApi, "domains")
	bridge.enter_domain = Callable(LootApi, "enter_domain")
	bridge.leave_domain = Callable(LootApi, "abandon")
	bridge.pickup = Callable(LootApi, "pickup")
	bridge.pickup_all = Callable(LootApi, "pickup_all")
	bridge.reclaim = Callable(LootApi, "reclaim")
	bridge.read_state = Callable(LootApi, "summary")
	return bridge


## Give the actor the items every realm gate needs, so a caller is not stuck at
## R1 forever with no way to satisfy the breakthrough gate. Data-driven, not a
## shortcut: these are the real realm items the facade checks for.
func _stock_seed_items() -> void:
	for def_id in _seed_item_ids():
		# The authored definition, via the game's one stable-id resolver
		# (ADR 0007). A fabricated `ItemDef.new()` stub is NOT equivalent: it made
		# this harness report a seeded pill the realm gate could not see, which
		# reads exactly like a broken gate.
		var def := Crafting.resolve(def_id)
		if def == null:
			_emit({"event": "error", "command": "seed", "error": "no such item: " + def_id})
			_failures.append("seed")
			continue
		ItemsApi.inventory(_actor).add(def, 999)


func _seed_item_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for path_id in PathState.ALL:
		# `training_item` is qi and mind's channel elixir; `strengthening_item` is
		# body's. Seeding only one leaves the other path unable to train a channel.
		for seed_id in [
			&"breakthrough_item",
			&"strengthening_item",
			&"training_item",
			&"recovery_item",
			&"sea_catalyst",
		]:
			var seed: Variant = _realm_seed(path_id, seed_id)
			if seed != null and seed != "":
				var item_id := StringName(seed)
				if not out.has(item_id):
					out.append(item_id)
	return out


## Ask a path's realm seed for one item id. The driver reads the seed object
## directly because the harness may build an actor; a screen never does this.
func _realm_seed(path_id: StringName, field: StringName) -> Variant:
	var state := _actor.path(path_id)
	if state == null:
		return null
	match path_id:
		PathState.BODY:
			return BodyRealmSeed.for_realm(state.rank_id).get(field)
		PathState.QI:
			return QiRealmSeed.for_realm(state.rank_id).get(field)
		PathState.MIND:
			return MindRealmSeed.for_realm(state.rank_id).get(field)
	return null


# --- Session ---------------------------------------------------------------


## Restore the saved actor if one exists and its path still matches. A path
## mismatch starts fresh rather than restoring a body actor into a mind screen.
func _restore_session(path_id: String) -> bool:
	if not FileAccess.file_exists(SESSION_PATH):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SESSION_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed
	if String(data.get("path", "")) != _canonical_path(path_id):
		return false
	var restored := Actor.from_dict(data.get("actor", {}))
	if restored == null:
		return false
	_actor = restored
	# Re-attach the path's components WITHOUT enrolling it again: `_attach_path`
	# would `set_path` a fresh R1 state and discard everything just restored.
	_reattach_components(path_id)
	_loaded_session = true
	return true


## Persist the actor so the next invocation resumes where this one stopped.
func _save_session() -> void:
	if _actor == null or not _screen.has_method("setup"):
		return
	var file := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"path": _current_path(), "actor": _actor.to_dict()}))
	file.close()


func _current_path() -> String:
	for path_id in PathState.ALL:
		if _actor.path(path_id) != null:
			return String(path_id)
	return ""


## The canonical path id for a `--path` value. The caller's short name and the
## module's path id differ (`qi` vs `qi_cultivation`), and the session file has to
## store one form or a resume never matches.
func _canonical_path(path_id: String) -> String:
	match path_id:
		"body":
			return String(BodyPath.PATH_ID)
		"qi":
			return String(QiPath.PATH_ID)
		"mind":
			return String(MindPath.PATH_ID)
		_:
			return path_id


## Enrol the actor on one cultivation path. Each module's facade owns the attach
## order, so the driver never reaches past it.
func _attach_path(path_id: String) -> void:
	if path_id.is_empty():
		return
	match path_id:
		"body":
			_actor.set_path(PathState.new(BodyPath.PATH_ID, &"qi_refining"))
		"qi":
			_actor.set_path(PathState.new(QiPath.PATH_ID, &"qi_refining"))
		"mind":
			_actor.set_path(PathState.new(MindPath.PATH_ID, &"qi_refining"))
		_:
			_fail("unknown path '%s'" % path_id)
			return
	_reattach_components(path_id)


## Attach the path's runtime components. Every facade's `attach` is idempotent, so
## this is safe on a fresh actor and on a restored one alike; unlike `_attach_path`
## it never enrols a path, so it cannot discard restored progress.
func _reattach_components(path_id: String) -> void:
	match path_id:
		"body":
			BodyCultivationApi.attach(_actor)
			BodyCultivationApi.attach_acupoints(_actor)
			BodyTraining.synchronize(_actor)
		"qi":
			QiCultivationApi.attach(_actor)
			QiTraining.synchronize(_actor)
		"mind":
			MindCultivationApi.attach(_actor)
			MindCultivationApi.attach_sea(_actor)
			MindTraining.synchronize(_actor)


# --- Commands ---------------------------------------------------------------


func _run_command(command: String) -> void:
	match command:
		"summary":
			_emit({"event": "summary", "value": _screen.summary()})
		"refresh":
			if _screen.has_method("refresh"):
				_screen.call("refresh")
			_emit({"event": "refresh", "value": _screen.summary()})
		"focus_initial":
			if _screen.has_method("focus_initial"):
				_screen.call("focus_initial")
			_emit({"event": "focus_initial", "focus_target": _focus_target()})
		_:
			_run_action(command)


## `act_cultivate` calls `act_cultivate()`. A verb the screen does not expose is
## reported, so a typo in a script fails loudly instead of passing silently.
##
## `call:<method>` reaches any public screen method with an optional payload, so
## a caller can drive selection helpers (`select_key`) that are not `act_*` and
## pass arguments to a zero-arg action. `grant:<item_id>` and `realm:<id>` seed
## the actor directly, which is what makes the game playable from a terminal.
func _run_action(command: String) -> void:
	if command.begins_with("call:"):
		_run_call(command.substr(5))
		return
	if command.begins_with("grant:"):
		_run_grant(command.substr(6))
		return
	if command.begins_with("realm:"):
		_run_realm(command.substr(6))
		return
	if command.begins_with("commit:"):
		_run_commit(command.substr(7))
		return
	# `strike` is `act_strike()`, `cultivate` is `act_cultivate()`. The CLI takes the
	# BARE VERB because that is the name every screen already publishes in its
	# `summary().enabled` table — `enabled.strike` is `strike`, not `act_strike`,
	# across every screen in `ui/screens/` — so a verb a screen declares it can
	# perform must be the same word the terminal drives, or the readout advertises a
	# verb no command line can reach. A screen exposing `act_strike` therefore
	# answers `--cmd strike`, which is what a caller reading its own summary expects.
	var action := command if command.begins_with("act_") else "act_" + command
	if not _screen.has_method(action):
		_emit({"event": "error", "command": command, "error": "no such action"})
		_failures.append(command)
		return
	var result: Variant = _screen.call(action)
	_emit({"event": "action", "command": command, "result": _jsonable(result)})


## `call:select_key=foo` or `call:equip_slot=accessory_a`. The payload is the part
## after the first `=`; without one the method is called with no arguments.
func _run_call(spec: String) -> void:
	var method := spec
	var args: Array = []
	var split := spec.find("=")
	if split >= 0:
		method = spec.substr(0, split)
		args.append(spec.substr(split + 1))
	if not _screen.has_method(method):
		_emit({"event": "error", "command": "call:" + method, "error": "no such method"})
		_failures.append(method)
		return
	var result: Variant
	if args.is_empty():
		result = _screen.call(method)
	else:
		result = _screen.call(method, args[0])
	_emit({"event": "action", "command": "call:" + method, "result": _jsonable(result)})


## `grant:item_id` puts a stack of a real item in the actor's inventory, so a
## caller can satisfy a realm gate instead of being stuck at R1.
func _run_grant(def_id: String) -> void:
	if def_id.is_empty():
		_emit({"event": "error", "command": "grant", "error": "no item id"})
		_failures.append("grant")
		return
	var inventory := ItemsApi.inventory(_actor)
	if inventory == null:
		# A screen with no `setup` (the character sheet) never triggered
		# `_bootstrap_actor`, so the inventory is not attached yet.
		ItemsApi.attach(_actor, SLOT_CAPACITY)
		inventory = ItemsApi.inventory(_actor)
	if inventory == null:
		_emit({"event": "error", "command": "grant", "error": "no inventory"})
		_failures.append("grant")
		return
	# Resolve the AUTHORED definition through the one stable-id resolver the game
	# itself uses (ADR 0007), so a grant is indistinguishable from a real drop.
	# Fabricating a bare `ItemDef.new()` here once made this harness lie: it
	# reported `granted: 999` for a pill the realm gate still called missing.
	var def := Crafting.resolve(StringName(def_id))
	if def == null:
		_emit({"event": "error", "command": "grant", "error": "no such item: " + def_id})
		_failures.append("grant")
		return
	# `add` returns the LEFTOVER, not the amount added, so 0 means it all fit.
	var leftover := inventory.add(def, 999)
	_emit(
		{
			"event": "action",
			"command": "grant:" + def_id,
			"result":
			{
				"granted": 999 - leftover,
				"leftover": leftover,
				"inventory_count": inventory.count(StringName(def_id)),
			},
		}
	)


## `realm:rank_id` moves the actor onto a realm directly, so a caller can reach a
## late game state without playing every step up to it.
func _run_realm(rank_id: String) -> void:
	var state := _actor.path(_current_path_id())
	if state == null:
		_emit({"event": "error", "command": "realm", "error": "actor is on no path"})
		_failures.append("realm")
		return
	state.rank_id = StringName(rank_id)
	_refresh_after_move()
	_emit({"event": "action", "command": "realm:" + rank_id, "result": String(state.rank_id)})


## `commit:<index>` runs `WorldAnchor.commit(actor, index)` — the same core entry
## point a high-tier breakthrough runs, and the ONLY thing that creates an
## `AscensionState`, commits to a world, or grows the inside world.
##
## `realm:` sets `PathState.rank_id` and stops there. That shortcut moves the
## rank WITHOUT the milestone that rank is supposed to have earned, so every
## screen reading core's committed state rendered "No ascent begun" and every
## ascent verb refused — a state the shipped game cannot actually reach. The
## refusal was correct; the driver was manufacturing an impossible state and the
## refusal read as a dead end. Two independent reports hit this before it was
## fixed. `commit:` performs the real milestone so the ascent, the inside world
## and the R28+ gates are drivable from a terminal.
func _run_commit(argument: String) -> void:
	if _actor == null:
		_emit({"event": "error", "command": "commit", "error": "no actor"})
		_failures.append("commit")
		return
	var index := argument.to_int()
	if index == 0 and argument.strip_edges() != "0":
		_emit({"event": "error", "command": "commit", "error": "commit needs a realm index"})
		_failures.append("commit")
		return
	WorldAnchor.commit(_actor, index)
	_refresh_after_move()
	_emit(
		{
			"event": "action",
			"command": "commit:" + argument,
			"result":
			{
				"index": index,
				"ascension": _actor.ascension != null,
				"world": _actor.world != null,
			},
		}
	)


func _current_path_id() -> StringName:
	for path_id in PathState.ALL:
		if _actor.path(path_id) != null:
			return path_id
	return &""


## Re-synchronise the modules after a direct state change so the screen renders
## the new realm instead of a stale one.
func _refresh_after_move() -> void:
	match _current_path_id():
		PathState.BODY:
			BodyTraining.synchronize(_actor)
		PathState.QI:
			QiTraining.synchronize(_actor)
		PathState.MIND:
			MindTraining.synchronize(_actor)
	if _screen.has_method("refresh"):
		_screen.call("refresh")


func _focus_target() -> String:
	var view: Dictionary = _screen.summary()
	return String(view.get("focus_target", ""))


# --- Plumbing ---------------------------------------------------------------


## Mount the scene under the tree root.
##
## **A composition root needs its `_ready()` driven by hand.** The runner is a
## `SceneTree` whose `_initialize()` returns before the first frame, so `root` is not
## yet inside the tree and the engine never delivers `_ready()` — a leaf screen does
## not care, because the driver reaches it through its public verbs, but a root that
## BUILDS its actor and wires its modules would answer every command with the state it
## had before boot. `SeamHarness._mount` already does exactly this and says why
## (`tests/ui/seam_harness.gd`), so the two agree instead of the CLI silently
## measuring an unbooted app.
func _instantiate(path: String) -> Node:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate()
	if node != null and node.get_parent() == null:
		root.add_child(node)
		if node.has_method("_ready"):
			node.call("_ready")
	return node


func _option(argv: PackedStringArray, name: String) -> String:
	var index := argv.find(name)
	if index < 0 or index + 1 >= argv.size():
		return ""
	return argv[index + 1]


## Commands are every `--cmd <verb>` pair, in order.
func _commands(argv: PackedStringArray) -> Array[String]:
	var out: Array[String] = []
	var collecting := false
	for arg in argv:
		if arg == "--cmd":
			collecting = true
			continue
		if collecting:
			out.append(arg)
			collecting = false
	return out


## `JSON.stringify` rejects raw Objects, so reduce anything it cannot encode to a
## primitive. Keeping the output machine-readable is the point of this driver.
func _jsonable(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_DICTIONARY, TYPE_ARRAY:
			return JSON.stringify(value, "  ")
		_:
			return str(value)


func _emit(payload: Dictionary) -> void:
	print("UIJSON ", JSON.stringify(payload))


func _fail(message: String) -> void:
	_failures.append(message)
