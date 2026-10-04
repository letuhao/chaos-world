class_name CombatEffectApply
extends RefCounted

## ADR 0067's `effects[]` step: a mechanism's OWN state writes, applied AFTER health.
##
## ## What was broken, and why every suite stayed green
##
## `DamageProposal` carries `{amount, effects[]}` and ADR 0067 says of the second field:
## "`effects[]` are the path's own state writes and the spine applies them AFTER health".
## Nothing applied them. `CombatSpine.resolve_hit` read `amount` through
## `CombatProposalReader.amount_of` and never read `effects[]` again, so a body hit cost
## health and left NO wound and a mind hit cost nothing at all — ADR 0070's wound ledger,
## its necrosis and its irreversible flag, and ADR 0071's sea erosion, were all unreachable
## in play. `BodyWounds.apply_all` and `BodyDamage.apply_wounds` had zero callers in `src/`,
## which is the same shape `mind_damage.gd:420` was: a mechanism that computes a state
## write nobody consumes. Each mechanism suite tested `resolve` and asserted the effect was
## CARRIED, so a green suite proved the payload existed and never that it landed.
##
## ## Where it runs, and why LAST
##
## Last in `resolve_hit`, after S12, which is the literal reading of ADR 0067: S9 is the
## health write and everything here is downstream of it. It is therefore also downstream of
## S10's reflect and S11's leech, so a wound is never earned by damage the defender bounced
## back, and downstream of S12, whose roll consumes a SUBSTREAM seed rather than the
## caller's generator (`status_apply.gd`) — so nothing a wound does can re-roll a crit or a
## status later in the same exchange. It is a separate file for the budget reason too:
## `spine.gd` is already over the line count this repo caps files at, and the seam's
## "no `if/else on path_id`" property is easier to keep auditable when the dispatch is one
## file rather than four branches in the spine.
##
## ## It dispatches by EFFECT KIND, never by path
##
## The two kinds are the ones the mechanisms actually emit, read from their own constants
## rather than restated as literals: `BodyWounds.EFFECT_KIND` (`&"body.wound"`, written by
## `BodyDamage.resolve` at `body_damage.gd:130`) and `MindDamage.EFFECT_KIND`
## (`&"mind.erosion"`, written by `MindDamage._effects` at `mind_damage.gd:718`). A kind
## nobody wrote a branch for is IGNORED, not refused: a fourth mechanism is one new file
## plus one `match` arm, and until it exists its effects must not be able to crash a hit.
##
## ## A missing component is a SKIP, never a crash and never a substitute
##
## A target with no wound ledger bound takes the blow normally and loses the wound; a
## target with no sea attached takes the blow normally and loses the erosion. This file does
## NOT call `attach_wounds` and does NOT invent a sea — binding is the composition root's
## job (`CombatBoot.bind_mechanisms`, `CombatEngineApi.attach_wounds`), and an applier that
## created its own ledger would silently resurrect the state a save deliberately dropped
## ("this body was never hit" and "this body was hit and every wound decayed" are different
## facts — see `Actor._restore_versioned` and `test_wound_persistence.gd`).
##
## ## The sea's REAL mutators, and the one conversion worth stating
##
## `SeaOfConsciousness` has `add_turbulence(amount)` / `calm(amount)` for a turbulence
## DELTA and `set_clarity(value)` for an ABSOLUTE — so clarity is applied as
## `clarity + delta`, never assigned the delta. `add_turbulence` and `set_clarity` are the
## real method names (`sea_of_consciousness.gd:69` and `:85`); both are preferred through
## `has_method`/`call`, and the raw field is written only when the sea exposes no such
## method and DOES expose the property, which is `MindDamage._settle`'s existing shape for
## the same reason: a foreign object then answers without touching anything.
##
## The one conversion the payload forces: `MindDamage.KEY_AWARENESS` is a delta of the
## defender's AWARENESS **RATIO**, not of the pool. `_awareness_delta_of`
## (`mind_damage.gd:585`) is `-clampf(awareness * erosion, 0, 1)` where `awareness` is
## `current / maximum` — a `0..1` fraction of the reserve. The reserve is a `ResourcePool`
## in pool units, so the fraction is spent as `delta * pool.maximum`, and a target with no
## reserve at all reads `0.0` and is skipped rather than credited.

## The report keys, so a test and a readout name the same three numbers.
const KEY_APPLIED := &"applied"
const KEY_SKIPPED := &"skipped"
const KEY_IGNORED := &"ignored"

## The effect kinds this file dispatches on, named ONCE each. The values are the mechanism
## constants' values; the arms below match `BodyWounds.EFFECT_KIND` and
## `MindDamage.EFFECT_KIND` directly so a mechanism that renames its own id cannot leave
## this file dispatching a kind nothing emits.
const BODY_WOUND := BodyWounds.EFFECT_KIND
const MIND_EROSION := MindDamage.EFFECT_KIND


## Apply every effect one landed hit carried. `effects` is an `Array` of
## primitives-only Dictionaries — `CombatOutcome.effects()` is the production route, and it
## duplicates, so a mechanism mutating its own proposal afterwards cannot rewrite what this
## settled.
##
## Returns `{applied: {kind: count}, skipped, ignored}`, all primitives. `skipped` counts a
## KNOWN kind whose component the target does not carry; `ignored` counts a kind nothing
## here dispatches on. The two are separate numbers because they are separate answers: a
## missing ledger is an actor's build, an unknown kind is the engine's vocabulary.
static func apply(target: Actor, effects: Variant, tuning: CombatTuning = null) -> Dictionary:
	var applied: Dictionary = {}
	var skipped := 0
	var ignored := 0
	if target == null or not (effects is Array):
		return {KEY_APPLIED: applied, KEY_SKIPPED: skipped, KEY_IGNORED: ignored}
	for entry in effects as Array:
		if not (entry is Dictionary):
			ignored += 1
			continue
		var typed := entry as Dictionary
		var kind := StringName(typed.get(DamageProposal.KIND, &""))
		if kind == BodyWounds.EFFECT_KIND:
			if _wound(target, typed, tuning):
				applied[kind] = int(applied.get(kind, 0)) + 1
			else:
				skipped += 1
		elif kind == MindDamage.EFFECT_KIND:
			if _erosion(target, typed, tuning):
				applied[kind] = int(applied.get(kind, 0)) + 1
			else:
				skipped += 1
		else:
			ignored += 1
	return {KEY_APPLIED: applied, KEY_SKIPPED: skipped, KEY_IGNORED: ignored}


## `body.wound`: one meridian's severity onto the target's BOUND ledger.
##
## The bound ledger, never a fresh one. `BodyDamage.apply_wounds` built a
## `BodyWounds.new()` per call and threw it away, so even a call that reached
## `BodyWounds.apply_all` discarded every wound the ledger already carried — the
## accumulating ledger ADR 0070 is named for, one object per call. Read through
## `CombatEngineApi.wounds_of`, so the component key has ONE spelling.
##
## The severity carried is the mechanism's OWN S4 subtotal for this meridian
## (`BodyDamage.resolve`), and `BodyWounds.add` divides it by the integrity pool's
## `maximum` — which is why the chip floor can never mint a wound out of a strike the flat
## subtraction already refused.
static func _wound(target: Actor, entry: Dictionary, tuning: CombatTuning) -> bool:
	var ledger := CombatEngineApi.wounds_of(target)
	if ledger == null:
		return false
	var meridian := StringName(entry.get(BodyWounds.KEY_MERIDIAN, &""))
	if meridian == &"":
		return false
	ledger.add(target, meridian, _positive(entry.get(BodyWounds.KEY_SEVERITY, 0.0)), tuning)
	return true


## `mind.erosion`: turbulence up, clarity down, and an `ATTEND` strike's AWARENESS
## drained — the three writes `MindDamage._effects` puts in ONE entry, so a panel can never
## show a sea that went turbulent without the clarity it cost.
##
## All three deltas are S5-SCALED already: `MindDamage.mitigate` multiplied them by
## `(1 - mitigation)` before the spine ever saw them, so nothing here scales them a second
## time.
static func _erosion(target: Actor, entry: Dictionary, tuning: CombatTuning) -> bool:
	var sea: Variant = _sea_of(target, tuning)
	if sea == null:
		return false
	_turbulence(sea, _signed(entry.get(MindDamage.KEY_TURBULENCE, 0.0)))
	_clarity(sea, _signed(entry.get(MindDamage.KEY_CLARITY, 0.0)))
	_awareness(target, tuning, _signed(entry.get(MindDamage.KEY_AWARENESS, 0.0)))
	return true


## Turbulence is a DELTA on the sea, and the sea has a mutator per direction:
## `add_turbulence` for what the strike added and `calm` for the negative a future kind
## might carry. A zero delta writes nothing rather than emitting a `changed` for no change.
static func _turbulence(sea: Variant, delta: float) -> void:
	if is_zero_approx(delta):
		return
	if delta > 0.0:
		_settle(sea, &"turbulence", &"add_turbulence", delta)
	else:
		_settle(sea, &"turbulence", &"calm", -delta)


## Clarity is an ABSOLUTE setter over a delta payload: `set_clarity` clamps to `[0, 1]`
## and takes a value, so the delta is added to the sea's own reading first. Reading through
## `get()` is what keeps this module from naming a `mind_cultivation` type it may not
## depend on.
static func _clarity(sea: Variant, delta: float) -> void:
	if is_zero_approx(delta):
		return
	var now := clampf(_signed(_read(sea, &"clarity", 0.0)), 0.0, 1.0)
	_settle(sea, &"clarity", &"set_clarity", clampf(now + delta, 0.0, 1.0))


## The AWARENESS reserve, spent as a fraction of its own maximum — see the module docblock
## for why the payload is a ratio and the pool is in units. `ResourcePool.change` clamps to
## `[0, maximum]`, so a strike can empty the reserve and can never invent a negative one.
static func _awareness(target: Actor, tuning: CombatTuning, delta: float) -> void:
	if is_zero_approx(delta):
		return
	var pool: Variant = _pool_of(target, tuning.awareness_pool_id)
	if pool == null:
		return
	var maximum := _positive(_read(pool, &"maximum", 0.0))
	if maximum <= 0.0 or not (pool is Object):
		return
	if not (pool as Object).has_method(&"change"):
		return
	(pool as Object).call(&"change", delta * maximum)


## The sea attached to `target`, through the component key AUTHORED on `CombatTuning`
## (`sea_component`, shipped as `&"sea_of_consciousness"`) rather than a `mind_cultivation`
## constant named here — the same edge discipline `MindDamage._sea_of` uses, and the third
## reader of one field. Null for a target nobody attached a sea to: a supported state, and
## the caller's cue to skip rather than to invent.
static func _sea_of(target: Actor, tuning: CombatTuning) -> Variant:
	if tuning == null or tuning.sea_component == &"":
		return null
	var bag: Variant = _read(target, &"components", null)
	if not (bag is Dictionary):
		return null
	return (bag as Dictionary).get(tuning.sea_component, null)


## Write a field through its REAL mutator when the object has one, else through the field
## itself, and only when the object exposes that property. Both halves are load-bearing: a
## `set()` on an absent property pushes an engine warning and this project treats warnings as
## errors, so the whole file would fail to compile.
static func _settle(sea: Variant, field: StringName, method: StringName, amount: float) -> void:
	if sea == null or not (sea is Object):
		return
	var holder := sea as Object
	if holder.has_method(method):
		holder.call(method, amount)
		return
	for entry in holder.get_property_list():
		if StringName(entry.get("name", &"")) == field:
			holder.set(field, amount)
			return


static func _pool_of(target: Actor, pool_id: StringName) -> Variant:
	if target == null or pool_id == &"":
		return null
	return target.resource(pool_id)


## `Object.get` with a fallback, never `Object._get` — the latter is an engine hook and a
## same-arity declaration collides with it, which fails the whole file to compile.
static func _read(value: Variant, key: StringName, fallback: Variant) -> Variant:
	if value == null or not (value is Object):
		return fallback
	var result: Variant = (value as Object).get(key)
	return result if result != null else fallback


## A delta read off a payload, SIGN PRESERVED and non-finite refused. `maxf(NaN, 0.0)` is
## `NaN`, and the spine's single non-finite guard sits at S6's entrance — which a mind
## amount of `0.0` never reaches — so every number this file reads passes through here.
static func _signed(value: Variant) -> float:
	if not (value is float or value is int):
		return 0.0
	var number := float(value)
	return number if is_finite(number) else 0.0


static func _positive(value: Variant) -> float:
	return maxf(0.0, _signed(value))
