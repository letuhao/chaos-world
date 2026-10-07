class_name StatusLoop
extends RefCounted

## The composition root's status tick (ADR 0089). Wiring, not rules: `app/` owns the
## clock and calls [method StatusApi.tick_statuses]; the `status` module owns what
## ticking means.
##
## ## Why this file exists
##
## Measured 2026-10-02, `Actor.tick_statuses` had ZERO production callers — only
## `tests/core/test_actor_statuses.gd:18,26`. No DoT could tick, no status could
## expire, ADR 0075's environment hazard had nothing to ride, and ADR 0071's
## `mind_deviation` was a label. A status system nobody can tick is decoration.
##
## ## One caller, one clock
##
## `InputHandler.tick` was that caller, and ADR 0056's deletion of the prototype
## took it with it: the game now has no per-frame driver at all. This loop is the
## wire the next one is meant to call, and it deliberately hangs off nothing rather
## than inventing a clock — a `Node` with `_process` would be a second, and ADR 0056
## forbids a stateful system in `app/`; this holds no state of its own, only the
## actor it ticks, so it is wiring the way `ActorFactory` and `ScreenRoutes` are.
## Restoring a caller is DEF-0111's shape: an explicit `periods`/frame delta from
## whoever owns time, never a wall clock read in here.
##
## ## The one accumulator, and why this is still wiring
##
## "holds no state of its own" was true while it only aged statuses. It now also runs
## the three combat ticks, one of which (`MindDamage.tick_collapse`) reads a continuous
## timer whose accumulator ADR 0071 puts in the CALLER — this module may not add a field
## to a component it does not own. So this file holds exactly one mutable number,
## [member _collapse_held], and it holds it for a module rather than owning a feature
## system: there is no cooldown table, no slot array, no persistence key, and
## `APP_STATE_MARKERS` still sees one signal rather than the two it needs to flag. A
## timer someone else owns and resets belongs on the wire; a rule that changes with the
## data belongs in the module that owns the data.
##
## ## Session-only
##
## Nothing here persists. ADR 0089: statuses never enter `Actor.to_dict()`, so a save
## carries no status and loading an older save is unaffected. The collapse accumulator
## is in the same position for the same reason — it is derived from sea state every
## frame, never written to a payload, and a loaded actor starts its window from the sea
## it actually carries. The schema has since moved on for other reasons (ADR 0140,
## wounds); that is not this loop's doing and does not reach it.

## Seconds of real time per gestation DAY. `FertilityApi.advance` measures its step in
## days — it divides by an authored `gestation_days` — so the frame delta is converted
## here, where a frame is the thing that has seconds. Authored as a constant rather than
## inlined so the cadence is greppable: a pregnancy of N days must last N * this many
## frames, and that relation should be checkable by reading one line.
##
## **Turn tier, deliberately NOT a world period** (ADR 0173:48, "frame delta converted
## where a frame has seconds"). Pregnancy resolves on the COMBAT clock, inside one
## period, with the world frozen while it does — so a gestation day is one second of
## combat time. Reading it off the ladder (`PERIOD_SECONDS / 12` periods per day) would
## make every pregnancy 120x longer: a balance change, not a migration. There is no
## `TimeLadder` magnitude equal to one second, so it is authored here and stays.
##
## **`_TURN` is the unit, spelled in the NAME because that is all a reader has.** A
## constant called `SECONDS_PER_*` reads as "seconds per something on the ladder", which
## is the conversion ratio this file deliberately is not: two units cross here, and the
## single-source guard's vocabulary cannot tell which one without the suffix. The suffix
## is what keeps the guard STRICT rather than exempted — `test_time_ladder_single_source`
## names this file as the near-miss that proves the vocabulary gap was closed by
## renaming the declaration and not by waving it through.
const SECONDS_PER_GESTATION_DAY_TURN := 1.0

## Seconds above `RUPTURE_THRESHOLD` a sea must hold CONTINUOUSLY full turbulence before
## `MindDamage.tick_collapse` demotes it. This loop is the CALLER that owns the
## accumulator (ADR 0071: the mechanism may not add a field to a component it does not
## own), so the timer lives here. `&""` actor carries no sea, and a sea that changes
## under `attach` starts the window over -- a timer that survived a target swap would be
## a collapse credited to a sea that never held the turbulence.
##
## **An hour, expressed as whole PERIODS off the SSOT rather than retyped** (ADR
## 0173:49, "a held window in seconds"). It is the ceiling on an accumulator rather than
## a cadence the world runs on, and the shipped 3600.0 was thirty 120-second periods —
## so the ladder's base ratio is the one number this reads now, exactly as
## `RealmRate.RATE_STEP` is read rather than copied. Value unchanged; a retuned period
## carries the belt with it instead of leaving it pinned to a stale world.
const MAX_COLLAPSE_HELD := TimeLadder.PERIOD_SECONDS * 30.0

var _actor: Actor

## How long the actor's sea has been held at full turbulence, in seconds. The collapse
## timer, and the ONLY piece of mutable state this loop owns. It is a bounded float, not
## a table, and it is reset whenever no sea is present so it cannot grow without limit.
var _collapse_held: float = 0.0

## The last band this loop synced the age projection for (ADR 0902, P8/BL-0924). `&""`
## means "never synced", so an actor's FIRST tick installs its band pair — the age
## system's own "installed at conception" — and a fresh loop can never mistake a loaded
## actor for one it already projected.
var _band: StringName = &""


func _init(actor: Actor = null) -> void:
	_actor = actor
	# ADR 0902 (P4): the fallback ICD flows from the shipped tuning into the status
	# module, where the per-instance lockout clock lives. A value, not state:
	# setting it twice is the same as once.
	var combat_tuning := CombatEngineApi.tuning()
	if combat_tuning != null:
		StatusApi.set_icd_default(float(combat_tuning.status_icd_default))


## Adopt an actor after construction, for a caller that built the loop first. The
## loop stays a pure wire either way.
##
## The collapse accumulator resets on every adopt, for the reason [constant
## MAX_COLLAPSE_HELD] names: the held seconds belong to the sea that earned them, and a
## new actor carries a sea that has held nothing.
func attach(actor: Actor) -> void:
	_actor = actor
	_collapse_held = 0.0
	_band = &""


func actor() -> Actor:
	return _actor


## Advance every status on the actor by `delta`. Call this from the frame driver
## that already exists; never from a loop of your own.
##
## Social bonds decay on this same call, deliberately. A relationship that faded on a
## different clock from a status that expired would be a relationship whose timing nobody
## could reason about, and this loop is already the composition root's only time wire
## (ADR 0089, ADR 0091).
##
## Technique upkeep settles here for the same reason, and because it is the SAME
## defect: `TechniquesApi.settle_upkeep` measured zero production callers, so an
## unaffordable upkeep never suspended anything outside a test (DEF-0151). Two
## systems aging on two clocks would be two systems whose timing nobody could reason
## about.
##
## The `delta` MUST be passed. Omitting it makes the facade settle immediately, and
## this loop is called once per FRAME — so a technique with a 60-second upkeep would
## be charged sixty times a second and be unaffordable within a second. Passing the
## delta makes the facade accumulate it and settle only when an authored interval has
## actually elapsed, which is why the cadence belongs to the techniques module and not
## here: the same reason `event` owns its own `periods`.
##
## Pregnancy rides here for the same reason as the other two, and with the same caveat
## written larger: `FertilityApi.advance` divides by a gestation length in DAYS, so it
## needs a period, not the raw frame delta. Passing seconds unchanged would make a
## 30-day pregnancy last tens of thousands of frames. The conversion is named here
## rather than hidden inside the module, because this loop is the only place that knows
## what a frame is worth.
##
## ## The three COMBAT TICKS ride here, and why this loop is the only place they can
##
## `CombatSpine` has a stage for a HIT and none of the three below: `BodyDamage.decay`
## (ADR 0070's decay half), `MindDamage.tick_rupture` (ADR 0071's ONLY health cost on
## the mind path) and `MindDamage.tick_collapse` (ADR 0071's headline — the loser is
## disarmed for a minute, not killed). All three measured ZERO production callers in
## `game/src`, and `CombatBoot`'s own docblock says so and names this loop as the place
## they belong. Two systems aging on two clocks would be two systems whose timing nobody
## could reason about, so they take the same `delta` on the same frame as the statuses.
##
## `CombatBoot` cannot host them: `APP_STATE_MARKERS` (`tools/arch/rules.py:180`) rejects
## a stateful system in `app/`, and a combat tick with an accumulator is state. This loop
## already owns the one accumulator ADR 0071 needs.
##
## ## The guards, because these run EVERY frame FOREVER
##
## `delta` is normalised ONCE here, at the top, and every tick below is handed the same
## `step`: a non-finite or negative frame is `0.0`. All three callees already guard their
## own inputs, but each returns the value it was handed in at least one key, and one of
## them (`held`) is ADDED to across ticks — a frame carrying `INF` would poison an
## accumulator nothing downstream can repair. One guard here is the only place that has
## to be right.
##
## The growth hazards, stated rather than assumed:
##
##   - `decay` can only move severity DOWN (`maxf(floor, before - rate*step)`), and the
##     ledger holds at most one entry per meridian, so a per-frame call cannot grow it.
##   - `tick_rupture` spends `minf(loss, maximum)` out of a pool that clamps to
##     `[0, maximum]`, so it cannot drive health below zero however long it runs.
##   - `tick_collapse` resets `held` to `0.0` on every outcome that fires — a collapse, a
##     sea with no successor, a calmed sea — so the only growth path is a window the
##     tuning never reaches. [constant MAX_COLLAPSE_HELD] is the belt to that pair of
##     braces: an hour of full turbulence is far past `RUPTURE_COLLAPSE_TIME 3.0`, and a
##     frame that then resumes the window is the same answer a reset gives.
##
## None of the three CREATES state. Decay reads the ledger `CombatBoot.bind_mechanisms`
## bound and reports `{}` for an actor that has none; rupture and collapse read the sea
## through `MindCultivationApi.sea` and decline a null. An actor that has never been hit
## therefore pays three dictionary reads a frame and gains nothing, which is the point:
## the ticks exist for a fight, not to manufacture one.
func tick(delta: float) -> Dictionary:
	if _actor == null:
		_collapse_held = 0.0
		return {"ok": false, "reason": "no_actor", "ticked": 0, "damage": 0.0, "expired": 0}
	var step := delta if is_finite(delta) else 0.0
	var result := StatusApi.tick_statuses(_actor, step)
	result["bonds"] = NpcBoot.tick(_actor, step)
	# The ids whose suspension state flipped, so a caller can react to a suspension
	# without re-reading the whole loadout.
	result["technique_suspensions"] = _strings(TechniquesApi.settle_upkeep(_actor, step))
	result["born"] = FertilityApi.advance(_actor, step * SECONDS_PER_GESTATION_DAY_TURN)
	_tick_combat(step, result)
	result["age_band"] = _sync_age_band()
	return result


## The age projection's driver (ADR 0902, P8/BL-0924): this loop is the composition
## root's only time wire, so the band TRANSITION is detected here — one `band_for` read a
## frame — and the projection host does the writing (withdrawing the previous band's pair
## before installing the next). The host itself reads no clock; this caller owns time.
func _sync_age_band() -> String:
	var band := AgeBands.band_for(_actor)
	if band == _band:
		return String(band)
	# TIERED TRACKING (ADR 0092, AGENTS.md): only a body the game REMEMBERS gets the
	# age track — the player, or a roster-tracked npc. A transient/minor body mints no
	# roster entry, and projecting onto it would spend permanent statuses and a
	# per-band check on somebody the game forgets. The band is remembered either way,
	# so an untracked actor pays the gate ONCE per transition, never per frame.
	_band = band
	if not _age_tracked():
		return String(band)
	StatusApi.sync_age_band(_actor)
	return String(band)


## Whether `_actor` is tracked (ADR 0092): the attached player, or an id the roster
## carries. The TIER is never compared — the roster ENTRY is the fact a mechanism may
## read ("a mechanism never compares a tier", ADR 0092).
func _age_tracked() -> bool:
	if _actor == null:
		return false
	var player := NpcApi._player()
	if player == null:
		return false
	if _actor == player:
		return true
	var tracked: Array = NpcApi.state(player).get("tracked_ids", [])
	return tracked.has(String(_actor.id))


## The three combat ticks, reported under their own keys so a readout and a test read
## the same names the modules already publish. Split out from [method tick] so `tick`
## stays the wire it is and the combat half is readable on its own.
func _tick_combat(step: float, result: Dictionary) -> void:
	var wounds := CombatEngineApi.wounds_of(_actor)
	result["wound_decay"] = BodyDamage.decay(wounds, step, CombatEngineApi.tuning())
	# The shield's regen (ADR 0887): the build grants the pool and the spine binds it on
	# first use; this clock is the only place the refill has a delta to spend.
	CombatEngineApi.tick_shields(_actor, step)
	# The sea is bound ONCE and handed to both mind ticks, so the two halves cannot
	# disagree about which sea the frame was about.
	var sea: Variant = MindCultivationApi.sea(_actor)
	# `tick_rupture` is the one mind entry point declared WITHOUT `static` while
	# `tick_collapse` and `apply_deviation` both are, so it is the only one of the
	# three that cannot be spelled `MindDamage.tick_rupture(...)` and is reached
	# through an instance instead. Same call, same frame, same clock as the two below
	# -- the asymmetry is the mechanism's declaration, not this wire's.
	result["rupture"] = MindDamage.new().tick_rupture(sea, _actor, step)
	# The accumulator is THIS loop's, and it is reset to whatever the module answered --
	# which is `0.0` for a calmed sea, a demoted sea and a sea with no successor, and
	# therefore cannot carry an earlier fight's seconds into a later one.
	var collapse := MindDamage.tick_collapse(sea, _actor, step, _collapse_held)
	_collapse_held = minf(
		maxf(0.0, float(collapse.get(MindDamage.KEY_HELD, 0.0))), MAX_COLLAPSE_HELD
	)
	result["collapse"] = collapse
	if bool(collapse.get(MindDamage.KEY_COLLAPSED, false)):
		# A demotion is the one combat event a caller cannot reconstruct by re-reading
		# the sea afterwards: the tier that was lost is in this frame's report or in
		# no frame at all. Surfaced under its own key rather than buried in `collapse`
		# so a UI is not obliged to know the module's result shape to notice it.
		result["mind_collapse"] = {
			"from_tier": String(collapse.get(MindDamage.KEY_FROM_TIER, "")),
			"to_tier": String(collapse.get(MindDamage.KEY_TO_TIER, "")),
			"deviation": String(collapse.get(&"deviation", "")),
		}


func _strings(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out


## COMBAT-scope statuses are cleared on combat exit, by the same caller that ticks
## them (ADR 0089). CULTIVATION-scope statuses are never purged by combat state.
func exit_combat() -> Array[String]:
	return StatusApi.clear_combat_scope(_actor)
