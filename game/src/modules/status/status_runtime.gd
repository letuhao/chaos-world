class_name StatusRuntime
extends RefCounted

## How a live `StatusEffect` on an actor resolves against its `StatusDef`
## (ADR 0086, ADR 0088, ADR 0090).
##
## ## Three rules this file exists to keep
##
## 1. **Ticking never adds or removes a `StatModifier`.** A status's stat effect is
##    computed ONCE at apply time and held; only the damage channel and the amplifier
##    channel change at tick time. `apply()` rebuilds remove-before-add
##    (`SocketEffects.apply`, `modules/socket/socket_effects.gd:39-48`), so rebuilding
##    can never accumulate drift.
## 2. **`Op.MULT` is never constructed here.** N instances would compound to 1024x
##    and make a status's strength a function of how often it was applied.
## 3. **The source tag is namespaced `status:<id>`.** `remove_modifiers_from` is an
##    exact-string filter (`core/actor_stats.gd:72-78`), so a bare id could collide
##    with `&"realm"` or an equipment instance id.
##
## ## Where the number comes from
##
## Not from the def. Potency is a share of the elemental term the hit landed,
## `element_power_<e>` (ADR 0088), so a rebalance is one `CombatTuning` edit and the
## ten defs never re-pin a literal.

const SOURCE_PREFIX := "status:"

## Per-actor live resolution, keyed by status id.
##
## **Deliberately NOT `Actor.module_data`.** ADR 0089 rules statuses session-only and
## names `module_data` as one of the two things it refuses, and `Actor.to_dict()`
## serializes `module_data` verbatim (`core/actor.gd:283`) — so a live-resolution
## record parked there would put potency, escalation state and authored def ids into
## every save. A static `WeakRef` table keeps the whole store out of the payload, and
## `WeakRef` rather than a bare reference so a discarded actor does not pin itself.
static var _by_actor: Dictionary = {}

## Duration, potency and escalation are resolved into this instance, and the instance
## is the only thing a tick reads. `tick_elapsed` and `ticks_elapsed` are the two
## accumulators that make a DoT resolvable: one decides WHEN the next pulse lands,
## the other makes an escalating burn escalate per pulse rather than per frame.
var def: StatusDef = null
var magnitude: float = 0.0
var stacks: int = 1
var tick_elapsed: float = 0.0
var ticks_elapsed: int = 0
var source: StringName = &""


static func _runtimes(actor: Actor) -> Dictionary:
	var key := actor.get_instance_id()
	var existing: Variant = _by_actor.get(key)
	if existing is Dictionary:
		var live: Variant = (existing as Dictionary).get("runtimes")
		if live is Dictionary:
			return live as Dictionary
	var fresh := {}
	# `weakref()` is the ONLY way to build a `WeakRef` -- there is no `WeakRef.new()`
	# and no `set_ref()` to fill one in afterwards (the class exposes `get_ref()` alone).
	# It holds the ACTOR, never the record dictionary: `weakref()` accepts an Object and
	# a `Dictionary` is not one. Weak-referencing the actor is what keeps a discarded
	# actor from pinning its own records -- the map holds an id and a payload, so nothing
	# here keeps the actor itself alive.
	#
	# Getting this wrong is SILENT past the abort: a bad call here throws before the
	# entry is stored, so `_runtimes` returned null, every `runtimes.get(id)` read null,
	# and the whole tick channel quietly resolved to "no status" while `apply` still
	# answered `ok: true`. The store is therefore built FIRST and the weakref second,
	# so the record is always reachable even if the weak handle is ever unavailable.
	var entry := {"actor": weakref(actor), "runtimes": fresh}
	_by_actor[key] = entry
	return fresh


## Drop one actor's records. The composition root calls this when an actor leaves the
## session; everything else expires naturally when the actor is collected.
static func forget(actor: Actor) -> void:
	if actor != null:
		_by_actor.erase(actor.get_instance_id())


static func source_for(status_id: StringName) -> StringName:
	return StringName("%s%s" % [SOURCE_PREFIX, String(status_id)])


## Magnitude for one pulse, after the def's escalation and after the amplifier
## channel the actor's live amplifiers describe.
##
## ## Why `sibling_gain` is an ARGUMENT and not this def's payload
##
## It was read off `runtime.def`, and that made the amplifier channel structurally
## inert. `runtime.def` is the status BEING PULSED — `fire_immolation` — which authors
## no `sibling_gain` at all, so the branch never fired for any burn at any magnitude.
## The count was gated just as wrong: `StatusApi._sibling_burns` refused unless the
## pulsing def was itself a `feed_siblings` amplifier, and an amplifier is a
## `sibling_amp` status that spends nothing, so the two conditions could never both
## hold. Measured over a `fire_pyre` on the actor: **AMPLIFIER DELTA = 0.000000**, with
## the burn spending an identical `0.041600` either way.
##
## The numbers therefore arrive from the amplifiers PRESENT ON THE ACTOR, aggregated by
## [method StatusApi._amplifier_feed] and passed in. Only the caller can see the actor,
## which is the whole reason the aggregation is not in this file — and it is what keeps
## this function pure: it applies a curve, it does not look anything up.
##
## The curve is `raw * (1 + min(gain * siblings, cap))`. `gain` is what one live
## amplifier adds per feeding sibling and `cap` is the most the amplifier channel may
## add on top, both authored on the amplifier's `.tres` and neither invented here. A
## pyre with no burning sibling does nothing, and that is correct rather than a defect.
##
## ## Why the defaults matter
##
## `sibling_gain`/`sibling_cap` default to `0.0`, so the existing two-argument call is
## the un-amplified magnitude: a status with no amplifier beside it answers exactly as it
## did before the channel was read off the right object, and a caller that has not
## measured the actor's amplifiers cannot accidentally double a pulse.
static func pulse_magnitude(
	runtime: StatusRuntime, sibling_burns: int, sibling_gain: float = 0.0, sibling_cap: float = 0.0
) -> float:
	if runtime == null or runtime.def == null:
		return 0.0
	var raw := runtime.magnitude
	if float(runtime.def.payload.get("escalation_per_tick", 0.0)) > 0.0:
		var cap := maxf(1.0, float(runtime.def.payload.get("escalation_cap", 1.0)))
		raw *= (
			1.0
			+ (
				float(runtime.def.payload.get("escalation_per_tick", 0.0))
				* float(runtime.ticks_elapsed)
				/ cap
			)
		)
	var gain := maxf(0.0, sibling_gain)
	if gain > 0.0 and sibling_burns > 0:
		raw *= 1.0 + minf(gain * float(sibling_burns), maxf(0.0, sibling_cap))
	return clampf(raw, 0.0, runtime.def.magnitude_cap)


## The `StatModifier`s this status contributes at its current magnitude. Authored
## values are PER UNIT OF MAGNITUDE, so one authored number states the curve and
## `magnitude_cap` bounds it.
static func build_modifiers(runtime: StatusRuntime) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	if runtime == null or runtime.def == null:
		return out
	var source := runtime.source if runtime.source != &"" else source_for(runtime.def.id)
	for entry in runtime.def.modifiers():
		var stat_id := StringName(entry.get("stat", &""))
		if stat_id == &"":
			continue
		out.append(
			StatModifier.new(
				stat_id,
				_op_of(StringName(entry.get("op", &"flat"))),
				float(entry.get("value", 0.0)) * runtime.magnitude,
				source
			)
		)
	return out


## Remove this status's whole contribution and add it again at the current magnitude.
## Remove-before-add, so apply/rebuild cannot drift. `actor` null is a no-op: a status
## that is about to be applied to nothing is not an error worth crashing over.
static func apply_modifiers(actor: Actor, runtime: StatusRuntime) -> void:
	if actor == null or runtime == null or runtime.def == null:
		return
	actor.stats.remove_modifiers_from(source_for(runtime.def.id))
	for modifier in build_modifiers(runtime):
		actor.stats.add_modifier(modifier)
	actor.mark_stats_dirty()


## The whole contribution removed in full. This is what expiry calls, and it is the
## reason a rebuild after an expiry can never leave an orphan modifier behind.
static func clear_modifiers(actor: Actor, status_id: StringName) -> void:
	if actor == null or status_id == &"":
		return
	actor.stats.remove_modifiers_from(source_for(status_id))
	actor.mark_stats_dirty()


static func _op_of(op: StringName) -> Stat.Op:
	return Stat.Op.PERCENT if op == &"percent" else Stat.Op.FLAT
