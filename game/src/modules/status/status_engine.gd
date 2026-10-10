class_name StatusEngine
extends RefCounted

## The `status` module's runtime machinery: the effect a def resolves to, the
## per-instance ledger ([method runtimes]), the ICD lockout, the pulse and its
## amplifiers, the meters, and the prune/purge that keep the ledger and the actor's
## statuses in step.
##
## Extracted from `StatusApi` when that facade outgrew gdlint's `max-file-lines`
## ceiling. The facade names this file; this file names NO `StatusApi` symbol, so the
## pair cannot load in a cycle. The one verb the facade still publishes from here is
## [method set_icd_default], kept as a delegate because the composition root and the
## status suites call it through the facade.
##
## Every verb here is called by the facade's public verbs AFTER their own refusals,
## so a refused apply/tick still writes nothing at all.

## The re-application lockout a def without its own `icd` uses (ADR 0902, P4).
## Pushed from `CombatTuning.status_icd_default` at boot; `0.0` = no ICD. The
## status module owns this because it owns the per-instance clock the check reads.
static var _icd_default: float = 0.0


## Remove the statuses carrying `instances`, in place, and let the same reconcile
## every other purge runs release their records and modifiers. INSTANCE-keyed where
## [method _purge] is id-keyed (ADR 0902, P3), because `coexist` siblings share an id.
static func purge_instances(actor: Actor, instances: Array[int]) -> void:
	for index in range(actor.statuses.size() - 1, -1, -1):
		if instances.has(actor.statuses[index].instance_id):
			actor.statuses.remove_at(index)
	reconcile(actor)
	actor.mark_stats_dirty()


## ADR 0902 (P7): a `meter`-kind status fills from the VALUE events its own pulses pay
## — the second of the one accumulator's two sources (hit counts are the first, T4's
## landed-blow path). Crossing the authored `payload.meter.every` publishes
## `status_meter_fired`; `reset_on_burst` follows the same residual rule as every other
## counter. A def that is not a meter is a no-op here, so every shipped def is
## byte-identical.
static func feed_meter(
	actor: Actor, instance_id: int, runtime: StatusRuntime, amount: float
) -> void:
	if actor == null or runtime == null or runtime.def == null:
		return
	var def := runtime.def
	if def.kind != &"meter":
		return
	var config: Variant = def.payload.get("meter", {})
	if not (config is Dictionary):
		return
	var authored := config as Dictionary
	var every := maxf(0.0, float(authored.get("every", 0.0)))
	if every <= 0.0:
		return
	var reset_on_burst := bool(authored.get("reset_on_burst", true))
	if StatusCounters.advance(actor, instance_id, every, reset_on_burst, amount):
		# The discharge (ADR 0902, P7): the meter pays one pulse of its own channel
		# when it crosses, beside the announced fact.
		pulse(actor, runtime)
		StatusEvents.note_meter_fired(actor.id, def.id, instance_id, amount)


# --- Internals ---------------------------------------------------------------


## The live `StatusEffect` an authored def resolves to.
##
## ## Why this is more than `StatusEffect.new(id, life)`
##
## ADR 0086 is explicit that the contract is "a tagged, stackable INSTANCE" and ADR 0090
## is explicit that a `StatusDef` "carries exactly the instance fields of ADR 0086 that
## are AUTHORED". So the two halves are one object and this is the seam: a def that
## resolves into a bare `StatusEffect.new(id, life)` throws its authored half away and
## leaves every default, and those defaults are the silent kind — `tick_interval = 0.0`
## is the contract's "plain timer, never pays one" (`contracts/status_effect.gd`), so a
## DoT written that way still ages out, still shows as applied, and spends nothing. A
## `.tres` would have to be a `.tres` that does nothing at all.
##
## Each field is read through the def's own closed vocabulary rather than cast, because a
## def that names something outside it is refused at load (`StatusDef.problems`) and a
## bad cast here would be a second, quieter opinion about the same value.
static func effect_for(
	def: StatusDef, magnitude: float, life: float, grant_id: StringName = &""
) -> StatusEffect:
	var effect := StatusEffect.new(def.id, life)
	effect.magnitude = magnitude
	effect.magnitude_cap = def.magnitude_cap
	effect.tick_interval = maxf(0.0, def.tick_interval)
	effect.mitigation_tags = def.mitigation_tags.duplicate()
	effect.element = def.element
	effect.scope = (
		StatusEffect.Scope.CULTIVATION
		if def.scope == &"cultivation"
		else (StatusEffect.Scope.COMBAT)
	)
	effect.stacking = stacking_of(def.stacking)
	effect.kind = kind_of(def.kind)
	# ADR 0902 (P5): the application's own handle, carried on the effect so a
	# lifecycle sweep can find every instance ONE grant wrote.
	effect.grant_id = grant_id
	return effect


## A def's authored `stacking` as the contract's enum. REFRESH rather than a hard
## failure, because it is the contract's own default and a refactor that left this
## unreadable must not turn every re-application into a refusal.
static func stacking_of(stacking: StringName) -> StatusEffect.Stacking:
	match stacking:
		&"stack":
			return StatusEffect.Stacking.STACK
		&"replace":
			return StatusEffect.Stacking.REPLACE
		&"coexist":
			return StatusEffect.Stacking.COEXIST
		_:
			return StatusEffect.Stacking.REFRESH


## A def's authored `kind` as the contract's enum, for the same reason as `_stacking_of`.
static func kind_of(kind: StringName) -> StatusEffect.Kind:
	match kind:
		&"dot":
			return StatusEffect.Kind.DOT
		&"control":
			return StatusEffect.Kind.CONTROL
		&"amplifier":
			return StatusEffect.Kind.AMPLIFIER
		&"burst":
			return StatusEffect.Kind.BURST
		&"counter":
			return StatusEffect.Kind.COUNTER
		&"meter":
			return StatusEffect.Kind.METER
		&"contagion":
			return StatusEffect.Kind.CONTAGION
		_:
			return StatusEffect.Kind.STAT_MODIFIER


## The per-actor runtime store, delegated to `StatusRuntime` so there is exactly one
## owner of the id-keyed map. ADR 0089 keeps statuses out of the save payload entirely,
## and that works because the store is a `WeakRef` table rather than module data — a
## record parked in `actor.module_data` would put potency, escalation state and authored
## def ids into every save.
static func runtimes(actor: Actor) -> Dictionary:
	return StatusRuntime._runtimes(actor)


## Set the fallback ICD. A value, not a dispatch: deterministic and non-interactive.
static func set_icd_default(seconds: float) -> void:
	_icd_default = maxf(0.0, seconds)


## Whether a live same-id instance is still inside its ICD window (ADR 0902, P4).
## A same-id effect with NO runtime record cannot prove it is outside the window,
## so it refuses — the conservative reading, the same way a null rng never mints
## a free CC. Bounded `for` over the actor's list.
static func icd_refusal(actor: Actor, def: StatusDef) -> bool:
	var icd := def.icd if def.icd > 0.0 else _icd_default
	if icd <= 0.0:
		return false
	var store := runtimes(actor)
	for status in actor.statuses:
		if status.id != def.id:
			continue
		var runtime := store.get(status.instance_id) as StatusRuntime
		if runtime == null or runtime.icd_elapsed < icd:
			return true
	return false


## The live instance handle carrying `status_id` on `actor`, or 0 when none does
## (ADR 0902, P6=C). Bounded `for` over the actor's own list; the FIRST match is
## unique for every stacking except `coexist`, which [method record_landed_blow] names.
static func live_instance_for(actor: Actor, status_id: StringName) -> int:
	for status in actor.statuses:
		if status.id == status_id:
			return status.instance_id
	return 0


## The live effect carrying `instance_id`, or null (ADR 0902, P3). Bounded
## `for` over the actor's list; the caller only asks with an id it just read
## off an answer, so `0` (not minted) matches nothing in practice.
static func effect_by_instance(actor: Actor, instance_id: int) -> StatusEffect:
	for status in actor.statuses:
		if status.instance_id == instance_id:
			return status
	return null


## The ONE resolution record of a live instance (ADR 0902, P3): reused across
## merges — refresh and stack mutate the held instance and must NOT mint a
## second record — and created on first appearance. Magnitude and stacks mirror
## the CORE effect, so one number keeps one home.
static func bind_runtime(actor: Actor, def: StatusDef, held: StatusEffect) -> StatusRuntime:
	var store := runtimes(actor)
	var runtime := store.get(held.instance_id) as StatusRuntime
	if runtime == null:
		runtime = StatusRuntime.new()
		runtime.def = def
		runtime.source = (
			StatusRuntime.source_for_instance(def.id, held.instance_id)
			if def.stacking == &"coexist"
			else StatusRuntime.source_for(def.id)
		)
		store[held.instance_id] = runtime
	runtime.magnitude = held.magnitude
	runtime.stacks = held.stacks
	# The application cleared the window (ADR 0902, P4): elapsed restarts here.
	runtime.icd_elapsed = 0.0
	return runtime


## Sweep every runtime whose instance left the actor's list. Expiry, replace
## and purge all land here, so the sweep lives in ONE place.
static func reconcile(actor: Actor) -> void:
	prune(actor, live_instances(actor))


## One tick channel of one status. Returns the damage it wrote.
##
## `magnitude_unit` names WHICH CHANNEL the status resolves through, and `pool` names
## how much of it is spent — a share of the potency, not an authored damage number.
## So `health_share` spends, `stat_modifier` holds modifiers already computed at apply
## time (ADR 0089: ticking never adds or removes one), and `sibling_amp` contributes
## nothing itself and exists only to feed the burns beside it.
static func pulse(actor: Actor, runtime: StatusRuntime) -> float:
	if runtime == null or runtime.def == null:
		return 0.0
	var def := runtime.def
	# A BURST spends itself AT ARRIVAL, which is `apply`'s call into this function.
	# It is deliberately NOT suppressed here: suppressing by kind inside `_pulse`
	# blocked the arrival spend too, so `water_deluge` landed nothing at all. The
	# no-respend rule lives in `tick_statuses`, which is the only other caller and
	# the only place "a second spend" is even possible.
	# TWO damage channels, not one. `health_share` is the flat bleed shape; the
	# `element_power` channel is the escalating burn, which resolves its magnitude
	# through the attacker's element power the same way any other qi term does. Both
	# spend; returning early for the second made `fire_immolation` a no-op that
	# still read as "applied", which is the failure this program exists to prevent.
	var spends_health := (
		def.magnitude_unit == &"health_share" or def.magnitude_unit == &"element_power"
	)
	if not spends_health:
		return 0.0
	var magnitude := StatusRuntime.pulse_magnitude(
		runtime, sibling_burns(actor, runtime), amplifier_gain(actor), amplifier_cap(actor)
	)
	if magnitude <= 0.0:
		return 0.0
	var pool_id := StringName(def.payload.get("pool", &"health"))
	var pool := actor.resource(pool_id)
	if pool == null:
		return 0.0
	var amount := magnitude * float(def.payload.get("share_per_pulse", 0.0))
	if amount <= 0.0:
		return 0.0
	actor.change_resource(pool_id, -amount)
	return amount


## How many statuses ALREADY on the actor the amplifiers feed: the burns that spend
## through the `health_share` or `element_power` channel, excluding the one being
## pulsed, so a burn never counts as its own sibling and the channel can never double.
##
## ## Why the gate left THIS function
##
## It used to refuse unless `runtime.def.mechanic() == feed_siblings` — the pulsing
## status had to BE an amplifier. That is backwards: `fire_pyre` is a `sibling_amp`
## status with no pool of its own, so it spends nothing and `_pulse` returns before
## ever reaching this count. The two conditions were mutually exclusive, so
## `_sibling_burns` answered `0` for every burn in the game and both amplifiers were
## structurally inert at any magnitude (measured: `AMPLIFIER DELTA = 0.000000`).
##
## The count is now a property of the ACTOR — what is feeding the amplifiers — rather
## than of the status happening to be on its tick. Which siblings an amplifier feeds is
## authored per amplifier ([method _amplifier_gain] reads that def), not decided here.
static func sibling_burns(actor: Actor, runtime: StatusRuntime) -> int:
	# The `runtime.def == null` half is the non-vacuity guard: a caller that has no
	# resolved status cannot name the id to exclude, and counting against an unknown def
	# is how a pulse ends up multiplied by a sibling set it was never part of.
	if actor == null or runtime == null or runtime.def == null:
		return 0
	var count := 0
	for other in actor.statuses:
		if other.id == runtime.def.id:
			continue
		var other_runtime := runtimes(actor).get(other.instance_id) as StatusRuntime
		if other_runtime != null and feeds(other_runtime.def):
			count += 1
	return count


## Every live amplifier's authored `sibling_gain`, summed.
##
## ## Why the total rather than one def's number
##
## An amplifier's `sibling_gain` lives on ITS OWN def (`fire_pyre` authors 0.5,
## `wind_spread` 0.45), and the pulsing status authors none — which is the defect this
## reads past. The gain therefore has to be collected from the amplifiers present on the
## actor, and SUMMED so a body carrying both gets both: `fire_pyre` and `wind_spread`
## are two authored amplifiers with two authored gains, and a second one that quietly
## did nothing is the same defect wearing a different hat.
##
## Each def's gain is clamped to its own authored `sibling_cap` before it is added, so
## the channel saturates per amplifier instead of running away as amplifiers accumulate:
## a body with N amplifiers reaches at most `N * cap`, and no single amplifier can
## contribute an unbounded share. A status this module did not author carries no
## `StatusDef`, so it contributes nothing rather than being guessed at.
static func amplifier_gain(actor: Actor) -> float:
	var total := 0.0
	for _entry in amplifiers(actor):
		total += minf(_entry[&"gain"], _entry[&"cap"])
	return total


## The most the amplifier channel may add on top, as the MAXIMUM over the live
## amplifiers rather than their sum: the cap is the ceiling of the channel, not a
## per-amplifier budget, so stacking two amplifiers widens what they are allowed to add
## (see [method _amplifier_gain]) without also stacking the ceiling that bounds it.
static func amplifier_cap(actor: Actor) -> float:
	var cap := 0.0
	for _entry in amplifiers(actor):
		cap = maxf(cap, _entry[&"cap"])
	return cap


## Every live `feed_siblings` amplifier on the actor, as `{gain, cap}` read off its own
## def. One walk so the gain and the cap cannot be counted over different sets.
static func amplifiers(actor: Actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if actor == null:
		return out
	var runtimes := runtimes(actor)
	for status in actor.statuses:
		var runtime := runtimes.get(status.instance_id) as StatusRuntime
		if runtime == null or not is_amplifier(runtime.def):
			continue
		(
			out
			. append(
				{
					&"gain": maxf(0.0, float(runtime.def.payload.get("sibling_gain", 0.0))),
					&"cap": maxf(0.0, float(runtime.def.payload.get("sibling_cap", 0.0))),
				}
			)
		)
	return out


static func is_amplifier(def: StatusDef) -> bool:
	if def == null:
		return false
	return def.magnitude_unit == &"sibling_amp" and def.mechanic() == &"feed_siblings"


## Whether this def is one the amplifiers feed. `magnitude_unit` decides rather than
## `kind`: `element_power` is what makes a status spend its magnitude, so it is the
## channel that can be fed, and a def whose own mechanic is `feed_siblings` is the
## amplifier being fed rather than a sibling — which is why `_sibling_burns` excludes
## the pulsing status by id as well.
static func feeds(def: StatusDef) -> bool:
	if def == null:
		return false
	return def.magnitude_unit == &"health_share" or def.magnitude_unit == &"element_power"


## The ONE live instance carrying `status_id`, or null — the same question
## `Actor.has_status` answers, except it hands back the instance the merge rule chose so
## a caller can read the strength that will actually pulse. Bounded `for` over the
## actor's live status list, which `tick_statuses` prunes.
static func live(actor: Actor, status_id: StringName) -> StatusEffect:
	for status in actor.statuses:
		if status.id == status_id:
			return status
	return null


static func live_instances(actor: Actor) -> Array[int]:
	var out: Array[int] = []
	for status in actor.statuses:
		out.append(status.instance_id)
	return out


static func count_lost(before: Array[int], after: Array[int]) -> int:
	var lost := 0
	for instance in before:
		if not after.has(instance):
			lost += 1
	return lost


## `categories` as plain strings for the read model: the summary contract is
## primitives only (ADR 0902, P13).
static func strings_of(values: Array[StringName]) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		out.append(String(value))
	return out


## Drop the runtime records and modifiers of instances the actor no longer
## carries, so an expired burn cannot leave a modifier or a stale magnitude
## behind. Keyed by INSTANCE (ADR 0902, P3): one `for` over a snapshot, with
## the sibling carrying another instance of the same id untouched.
static func prune(actor: Actor, live: Array[int]) -> void:
	var runtimes := runtimes(actor)
	var gone: Array[int] = []
	for instance in runtimes.keys():
		var runtime := runtimes.get(instance) as StatusRuntime
		if runtime == null or live.has(int(instance)):
			continue
		runtimes.erase(instance)
		StatusRuntime.clear_source(actor, runtime.source)
		gone.append(int(instance))
	if not gone.is_empty():
		# ADR 0902 (P6=C): a left instance's counters leave with it, so a successor
		# instance can never inherit a dead sibling's count.
		StatusCounters.drop_instances(actor, gone)


## Drop the purged ids from the actor's array, in place, and let `_prune` sweep the
## runtimes and modifiers they leave behind.
##
## ## Why the array is erased IN PLACE and never reassigned
##
## `StatusRegistry` holds that array BY REFERENCE (`core/actor.gd:143`,
## `StatusRegistry._init(statuses)`), which is deliberate: `FertilityApi.advance` erases
## from `actor.statuses` directly (`modules/fertility/api.gd:69`) and `EnvironmentField`
## reads it directly, so a shadow copy here would go stale the moment either ran.
## `actor.statuses = kept` therefore REBINDS the property to a brand new array while the
## registry keeps the old one — after which `actor.statuses` reads empty and
## `actor.has_status()` still answers for the purged ids, because every read of a status
## goes through the registry. That is the worst shape a purge can take: the module
## believes the combat debuff is gone while the rest of the game still has it.
##
## So this erases through the same reference the registry holds, exactly as fertility
## does. `_live_instances` is read AFTER the erasure, not before, so `_prune` sees the
## survivors -- reading it first meant the just-cleared ids counted as live and their
## modifiers were never released.
static func purge(actor: Actor, cleared: Array[String]) -> void:
	for index in range(actor.statuses.size() - 1, -1, -1):
		if cleared.has(String(actor.statuses[index].id)):
			actor.statuses.remove_at(index)
	# The runtime sweep is instance-keyed (ADR 0902, P3), so this is the same
	# reconcile every apply and expiry runs: what left the actor loses its record
	# and its OWN source tag's modifiers; coexist siblings stay untouched.
	reconcile(actor)
	actor.mark_stats_dirty()
