class_name AttackContext
extends RefCounted

## One attack in flight, handed to a damage mechanism at S4 and S5 (ADR 0067).
##
## ## Why this carries `StatContext` and not `Actor`
##
## `contracts/` is the leaf layer: `LAYER_DEPS["contracts"] == {"contracts"}` and it
## is in `BARE_REF_UNITS` (`rules.py:60`), so a bare reference out of it to any other
## unit is unconditionally an arch violation. An `AttackContext` that held an `Actor`
## would be that violation. A `StatContext` is itself a `contracts/` type, so the
## seam can hand a mechanism exactly the read surface it needs and name it in a type
## annotation — and `StatContext` already exists to be exactly that (ADR 0002).
##
## A mechanism needing path STATE reads its OWN component off the context
## (`ctx.attacker.component(id)`), which returns a live `RefCounted` typed loosely
## for precisely this reason. It never needs the `Actor`.
##
## ## How the spine fills this in
##
## The spine builds one through the constructor and then writes the shared stages'
## facts with `set()`. It does that deliberately, and its comment says why: a named
## reference to a class another wave is mid-write on would turn their edit into a
## compile break here. So the fields the spine writes (`base`, `magnitude`, `rolled`,
## `crit`) are declared as real properties and are filled through them; the typed half
## is constructor-owned.
##
## ## What a mechanism may NOT do
##
## No scene tree, no `Actor`, no frame time, no `randf()`. Everything a mechanism
## decides must be a function of these fields, its own component, and `rng` — or the
## same inputs would produce a different hit on a replay (ADR 0067's float
## determinism). `rng == null` is the deterministic caller, and a mechanism that
## rolls anyway is not pure.

## The attacker's side at query time. Live references, not copies (ADR 0002).
var attacker: StatContext = null

## The target's side at query time.
var target: StatContext = null

## The attack's base magnitude AFTER the S1 gate — `CombatSpine.base_damage`, which is
## the technique's authored magnitude through the authored technique ladder
## (`TechniqueMagnitudeTable.factor`). S1's OUTPUT, never the technique's raw magnitude:
## that is what makes "S1 before S2" and "S1 before S4" observable at all — a mechanism
## reading `base` cannot see a pre-gate value.
var base: float = 0.0

## The injected generator, or null for a deterministic caller. A mechanism that
## receives null MUST NOT roll: with no generator the only deterministic answer is
## the one that consults no randomness at all.
var rng: RandomNumberGenerator = null

## The technique that launched this attack, when the caller knows it. Typed
## `StringName` and read from `data` rather than held as a `Resource`, because
## `TechniqueDef` lives in `modules/techniques/` and `contracts/` may not name it.
var technique_id: StringName = &""

## The realm that gated `base`, when the spine knows it. Empty means unknown, and a
## mechanism must read `base` rather than re-derive a rate from this — the rate is
## applied once, at S1, and never twice.
var realm_id: StringName = &""

## Path-specific authored inputs the seam does not name: qi's `element` /
## `element_share`, body's `aim_meridian`. This is how a mechanism's own
## requirements travel through the ONE context without a sixth stage, and how a
## fourth path's vocabulary grows without the seam growing with it. Primitives only.
var data: Dictionary = {}

## The band roll has been made and the hit landed. The spine writes this. A mechanism
## is only ever called on a landed hit (S2 before S4), so this is a fact, not a
## decision it may make.
var rolled: bool = false

## The S3 crit draw came up true. **A mechanism must never read this as an INPUT.**
##
## S4 before S6 is load-bearing (ADR 0067): crit multiplies what the mechanism
## produced and is never one of its terms, which is what stops the three mechanisms
## from disagreeing about a shared stat — they never see one. The field exists
## because the spine writes it and a field it cannot write would be a lie. The
## invariant is a review rule on mechanisms, not a type-level one: see
## `test_attack_context.gd`, which states it and the reason it is not enforceable
## here.
var crit: bool = false

## What the spine calls the same number as `base`. Declared so the spine's `set()`
## lands rather than silently creating nothing; reading `base` is canonical.
var magnitude: float = 0.0

## The objects the two sides were built from, when the caller had more than a
## `StatContext` to hand (the spine has `Actor`s). Kept untyped so `contracts/` never
## names one, and used ONLY to read live derived stats — see [method attacker_value].
var _attacker_source: Variant = null
var _target_source: Variant = null


## The spine's construction path. `p_attacker`/`p_target` are each side's
## `StatContext`, or an object carrying one (an `Actor`), or null.
##
## `p_technique` and `p_tuning` are accepted and NOT read: they exist so the spine can
## build a context in one call, and neither type may be named here. They are prefixed
## with an underscore so gdlint's `unused-argument` rule sees the intent rather than an
## oversight. Everything the spine then writes is done through the public properties,
## deliberately.
func _init(
	p_attacker: Variant = null,
	p_target: Variant = null,
	_p_technique: Variant = null,
	_p_tuning: Variant = null,
	p_base: float = 0.0,
	p_rng: RandomNumberGenerator = null,
	p_realm_id: StringName = &""
) -> void:
	_attacker_source = p_attacker
	_target_source = p_target
	attacker = _as_context(p_attacker)
	target = _as_context(p_target)
	base = maxf(0.0, p_base)
	magnitude = base
	rng = p_rng
	realm_id = p_realm_id


## The attacker's stat id, or 0.0 when there is no attacker. The read a mechanism
## uses instead of an `Actor`.
##
## A live derived read is preferred over the context's own table whenever the caller
## handed over more than a context, because a `StatContext` built here cannot see the
## owner's derived cache and would otherwise answer a BASE-only number for
## `ATTACK_PHYSICAL` — a silently halved attack that no test would blame on the
## context.
func attacker_value(id: StringName) -> float:
	return _stat_of(_attacker_source, attacker, id)


## The target's stat id, or 0.0. The twin of [method attacker_value].
func target_value(id: StringName) -> float:
	return _stat_of(_target_source, target, id)


## A path-owned authored input, or `fallback` when it is absent. Mechanisms read
## their own `data` keys through this so a missing authored field is a stated
## default at one place instead of a `.get()` at every call site.
func data_value(key: StringName, fallback: Variant = null) -> Variant:
	return data.get(key, fallback)


## Set one path-owned authored input. `Variant` on purpose: this dictionary is the
## seam's one extension point and it must not pretend to know a shape.
func set_data(key: StringName, value: Variant) -> void:
	data[key] = value


## A `StatContext`, or null. Accepts one directly, or reads one off an object that
## exposes `Actor`'s public collections — `stats`, `resources`, `traits`,
## `affinities`, `paths`, `components`, `meridians` — which is what lets the spine
## pass an `Actor` it already holds without `contracts/` ever naming `Actor`.
##
## The seventh argument is the source's OWN network, read by name and passed
## through live (ADR 0057). It is never reconstructed from `components`: the
## component bag is a module-owned lookup that answers null for every actor the
## game builds, so a six-argument build here silently denied every mechanism a
## meridian read this docstring promised. `null` stays the honest absent case — an
## object with no `meridians` property is a different fact from an actor whose
## channels nobody trained, and the mechanism reading it is the only caller that
## can tell them apart.
func _as_context(value: Variant) -> StatContext:
	if value is StatContext:
		return value as StatContext
	if value == null:
		return null
	var context := StatContext.new(
		_call(value, &"base_ref", {}),
		_read(value, &"resources", {}),
		_read(value, &"traits", null),
		_read(value, &"affinities", null),
		_read(value, &"paths", {}),
		_read(value, &"components", {}),
		_read(value, &"meridians", null)
	)
	return context if context.traits != null and context.affinities != null else null


## A stat from whichever side carries a live cache, preferring it.
func _stat_of(source: Variant, context: StatContext, id: StringName) -> float:
	if context == null:
		return 0.0
	var stats: Variant = _read(source, &"stats", null)
	if stats != null and stats.has_method(&"derived"):
		return float(stats.call(&"derived", id))
	return context.value(id)


## Read a property off any value that might be an `Object`, with a fallback.
##
## Named `_read` rather than `_get` because `Object` already defines `_get(StringName)`
## as an engine hook: declaring a same-arity `_get(value, key, fallback)` collides with
## it and Godot refuses the override, which fails the whole file to compile and cascades
## into "Could not resolve class" for everything that depends on it.
func _read(value: Variant, key: StringName, fallback: Variant) -> Variant:
	if value == null or not (value is Object):
		return fallback
	var result: Variant = (value as Object).get(key)
	return result if result != null else fallback


func _call(value: Variant, key: StringName, fallback: Variant) -> Variant:
	if value == null or not (value is Object):
		return fallback
	var holder: Variant = (value as Object).get(&"stats")
	if holder == null or not (holder is Object):
		return fallback
	if not (holder as Object).has_method(key):
		return fallback
	return (holder as Object).call(key)
