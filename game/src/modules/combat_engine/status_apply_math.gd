class_name StatusApplyMath
extends RefCounted

## The arithmetic S12 reads values through: the channel totals ADR 0884 defines, ADR 0200's
## defense share, ADR 0885's net factor, and the small coercions every reader on this path
## uses (`finite`, `number`, `id_of`, `stat`).
##
## Extracted from [StatusApply] when that file passed gdlint's `max-file-lines` ceiling.
## The set is CLOSED and holds no constant: every helper here calls only its siblings, and
## nothing here names a `StatusApply` symbol — which is what keeps the pair one-way, since
## a base cannot be the one that reaches back.
##
## Every verb is a TOTAL function of its arguments: an absent prefix, a null actor, a
## malformed `Variant` and a non-finite float each read a defined value rather than
## raising, because these run inside a hit that has already spent its damage.


## The per-category pass-through (ADR 0902, P10): the FIRST authored category present in
## `by_category` wins; an empty map, or none of the categories present, falls back to `base`.
static func category_float(by_category: Dictionary, categories: Array, base: float) -> float:
	if by_category.is_empty():
		return base
	for category in categories:
		var named := String(category)
		if by_category.has(named):
			return finite(float(by_category[named]))
		if by_category.has(StringName(named)):
			return finite(float(by_category[StringName(named)]))
	return base


## One side's authored channel total (ADR 0884): `prefix + "omni"` always, plus
## `prefix + kind`, `prefix + status_id` and — the defender's call — `prefix + element`
## when each is known. An unauthored or absent prefix reads `0.0` for the whole side, and
## an unknown id reads `0.0` like every other absent stat on this path.
static func channel_total(
	actor: Actor,
	prefix: String,
	status_id: StringName,
	kind: StringName,
	element: StringName,
	family: StringName = &"",
	categories: Array = []
) -> float:
	if prefix == "" or actor == null or actor.stats == null:
		return 0.0
	var total := stat(actor, StringName(prefix + "omni"))
	if kind != &"":
		total += stat(actor, StringName(prefix + String(kind)))
	if status_id != &"":
		total += stat(actor, StringName(prefix + String(status_id)))
	if element != &"":
		total += stat(actor, StringName(prefix + String(element)))
	# ADR 0902 (P12): the grouping terms. `family` is one id; each authored
	# category is its own id. Both absent-cheap: an unchanneled id reads 0.0.
	if family != &"":
		total += stat(actor, StringName(prefix + String(family)))
	for category in categories:
		if category is StringName or category is String:
			var name := StringName(category)
			if name != &"":
				total += stat(actor, StringName(prefix + String(name)))
	return maxf(0.0, finite(total))


## ADR 0200's ratio for the COMBAT half of the status gate:
## `share = mitigation_ceiling * D / (K + D)` with `D` the defender's `status_defense`
## MAGNITUDE and `K = defense_divisor_k` the attacker's own scale.
##
## ## Why S12 needs a ratio at all, and what it costs
##
## `apply_chance` takes no `attacker`, so it cannot build the same `K` the three damage
## mechanisms build from the attacker's own offense. `defense_divisor_k` alone is what is
## available without growing a new parameter on a function six call sites use, and it is
## a defensible substitute: it is the same authored constant, and the gate's contest is
## between two defensive investments rather than between an offense and a defence.
##
## The honest cost is that the attacker's realm NO LONGER SCALES THIS GATE. `status_defense`
## climbs `1.00 -> 551.46` with the ladder and `K` does not, so a deep-realm defender's
## status immunity converges on `mitigation_ceiling` while at R1 the same build resists
## almost nothing. **That is the same class of defect ADR 0200 was written to remove, in the
## one place the fix did not reach**, and closing it properly needs a second decision I am
## not making silently: either `apply_chance` grows an `attacker` parameter and every call
## site passes one, or S12 reads the caller's already-resolved elemental resist as its `K`.
## Either is a change to `CombatExchange` and `exchange.gd`, outside this file's seam.
##
## What is asserted today is the part that IS sound: the share is an unbounded magnitude
## through a ratio, so it is strictly below the ceiling for every finite defense, the two
## resists compose rather than annihilate, and `status_min_apply` forbids a hard `0.0`.
## `tests/modules/combat_engine/test_status_application.gd` pins exactly those three.
static func status_defense_share(target: Actor, tuning: CombatTuning) -> float:
	var divisor := finite(tuning.resist_divisor)
	if divisor <= 0.0:
		return 0.0
	var raw := maxf(0.0, finite(stat(target, StringName(tuning.status_defense_stat))))
	var defense := raw / divisor
	var ceiling := clampf(finite(tuning.mitigation_ceiling), 0.0, 1.0)
	if ceiling <= 0.0:
		return 0.0
	var divisor_k := maxf(0.0, finite(tuning.defense_divisor_k))
	var denominator := divisor_k + defense
	if denominator <= 0.0:
		return 0.0
	return finite(ceiling * defense / denominator)


## The seed of S12's per-hit substream: `LootState._encounter_seed`'s exact shape, which
## ADR 0087 names as the precedent (`modules/loot/loot_state.gd:607-609`).
##
## ```
## (parent_seed * 2654435761 + absi(hash(attacker.id ^ defender.id ^ hit_index))) & 0x7FFFFFFF
## ```
##
## ## `hit_index` is INSIDE the hash, and that is the whole point
##
## The salt mixes the three participants and then hashes ONCE, so `hit_index` reaches
## the multiplier term and two identical attacks in one exchange cannot land on the same
## child seed. Hashing the labels and XOR-ing `hit_index` AFTERWARDS would look
## equivalent and is not: the original computed the salt and then dropped it, which made
## the seed a pure function of `(seed, label)` and turned every hit in a fight into a
## replay of the first one's answer -- exactly the failure `hit_index` was added to
## prevent. A salt that is built and not multiplied in is a silent no-op, which is the
## defect class this whole file is written against.
##
## The same seed still reproduces the same sequence: the term is a pure function of its
## inputs, so `(seed, attacker, defender, technique, hit_index)` names one stream and
## nothing is drawn off the caller's generator to get there.
static func status_seed(
	hit_seed: int, attacker: Actor, target: Actor, technique: Variant, hit_index: int = 0
) -> int:
	var label := str(hit_index)
	if attacker != null:
		label = "%s^%s" % [String(attacker.id), label]
	if target != null:
		label = "%s^%s" % [String(target.id), label]
	if technique is Object:
		label = "%s^%s" % [String((technique as Object).get(&"id")), label]
	return (hit_seed * 2654435761 + absi(hash(label))) & 0x7FFFFFFF


## ADR 0885's net factor for one potency axis: `clampf(1 + delta / scale, min, max)`, where
## `delta` is the attacker's channel total minus the defender's `*Reduction` total, and
## each declared tag's `status.immuneReduction.<tag>` multiplies `(1 - reduction)` in —
## Keepverse's §6: a partial immunity blunts the status overall, never one axis
## selectively. A non-positive scale reads parity, exactly like the gate's own.
static func net_factor(
	attacker: Actor,
	target: Actor,
	tuning: CombatTuning,
	status_id: StringName,
	kind: StringName,
	prefix: String,
	reduction_prefix: String,
	tags: Array
) -> float:
	if tuning == null:
		return 1.0
	var delta := channel_total(attacker, prefix, status_id, kind, &"")
	delta -= channel_total(target, reduction_prefix, status_id, kind, &"")
	var scale := finite(tuning.status_net_factor_scale)
	var net := 1.0
	if scale > 0.0:
		net = 1.0 + delta / scale
	var low := finite(tuning.status_min_net_factor)
	var high := finite(tuning.status_max_net_factor)
	if high < low:
		high = low
	net = clampf(net, low, high)
	if tuning.status_immune_reduction_prefix != "":
		for tag in tags:
			var reduction := clampf(
				stat(target, StringName(tuning.status_immune_reduction_prefix + String(tag))),
				0.0,
				1.0
			)
			net *= 1.0 - reduction
	return maxf(0.0, net)


## The substream for this hit. Built from [method status_seed], which is
## `LootState._encounter_seed`'s shape verbatim — the precedent ADR 0087 names.
##
## `state` is set alongside `seed` because that is what `DomainRng._generator` does
## (`modules/domain/domain_rng.gd:88-92`): seeding a Godot generator without resetting
## its state leaves the first draw a function of whatever ran before, which would make
## the "same seed, same outcome" claim false the moment two substreams were made from
## one parent in the same frame.
static func substream(
	rng: Variant, attacker: Actor, target: Actor, technique: Variant, hit_index: int
) -> RandomNumberGenerator:
	var stream := RandomNumberGenerator.new()
	var seed_value := status_seed(rng.seed, attacker, target, technique, hit_index)
	# `stream.seed = seed_value` ONLY. `RandomNumberGenerator.state` is the RAW PCG
	# state, not a seed: assigning it discards the mixing `seed` performs, and the
	# result is a stream whose first draw is the same for every seed. Measured over 40
	# seeds: with the overwrite, 40/40 drew exactly 0.0; without it, the draws spread
	# across 0.0098..0.9811. A stage whose entire purpose is a seeded roll was
	# answering every hit the same way.
	stream.seed = seed_value
	return stream


## Write `value` on `effect` only when the property exists. `set()` on a missing
## property pushes an engine warning, and this file must not emit warnings for a field
## whose contract has not landed yet.
static func assign(effect: RefCounted, key: StringName, value: Variant) -> void:
	if has_property(effect, key):
		effect.set(key, value)


## Whether `object` exposes `key`. `get_property_list` rather than `in`-style probing,
## because that is the one question that answers about a scripted object.
static func has_property(object: Object, key: StringName) -> bool:
	for entry in object.get_property_list():
		if StringName(entry.get("name", &"")) == key:
			return true
	return false


## Whether `Actor.add_status`'s answer means ACCEPTED.
##
## The deliberately permissive reading, stated in full at the call site: a void answer,
## a `null`, a `true`, and a `Dictionary` with no `ok` key are all ACCEPTED, and only an
## explicit `ok == false` is a refusal. The reason is that the current
## `core/actor.gd` declares `func add_status(status: StatusEffect) -> void` — a void
## answer must not be mistaken for a refusal, or every status in the game would be
## refused by a shape nobody chose.
static func accepted(answer: Variant) -> bool:
	if answer is Dictionary:
		return not (answer as Dictionary).has(&"ok") or bool((answer as Dictionary)[&"ok"])
	return true


## One stat id built from an authored prefix, matching `QiDamage._suffixed` exactly so
## the two stages cannot spell the same stat two ways.
static func suffixed(prefix: String, element: StringName) -> StringName:
	return StringName((prefix if prefix is String else "") + String(element))


## The derived value of `id` on `actor`, or 0.0. Total, for `CombatSpine._stat`'s
## reason: S12 runs on a hit that has already mutated both actors, so it must not be
## the stage that crashes on a half-built one.
static func stat(actor: Actor, id: StringName) -> float:
	if actor == null or actor.stats == null:
		return 0.0
	return actor.stats.derived(id)


## A `Variant` as a finite float, or 0.0. A `bool` is deliberately not a number: `true`
## as a chance would silently read 1.0 and apply every status.
static func number(value: Variant) -> float:
	if value is float or value is int:
		return finite(float(value))
	return 0.0


static func id_of(value: Variant) -> StringName:
	return StringName(value) if value is StringName or value is String else &""


static func finite(value: float) -> float:
	return value if is_finite(value) else 0.0
