class_name ActorStats
extends RefCounted

## Base attributes plus a source-tagged modifier stack. Derived stats are recomputed
## from base + modifiers and never stored as truth (ADR 0001).

var _base: Dictionary = {}
var _modifiers: Array[StatModifier] = []
var _derived: Dictionary = {}
var _providers: Array[StatProvider] = []
var _context: StatContext = null
var _provider_cache: Dictionary = {}
var _provider_version: int = -1
var _version: int = 0
var _dirty: bool = true
## The aptitude layer (ADR 0881/0882): points per aptitude id, resolved by
## `AptitudeTable`'s matrix into flat contributions on the channels its edges name.
## Separate from `_base` on purpose — an aptitude is a SOURCE, never a readable stat.
var _aptitudes: Dictionary = {}
## The ladder value `P(theta)` a MAGNITUDE edge scales by; pushed by `RealmScaling`.
var _aptitude_ladder: float = 1.0


func _init(base: Dictionary = {}) -> void:
	for id in Stat.BASE_ATTRIBUTES:
		_base[id] = float(base.get(id, 0.0))
	for key in base.keys():
		_base[key] = float(base[key])


func get_base(id: StringName) -> float:
	return float(_base.get(id, 0.0))


func set_base(id: StringName, value: float) -> void:
	_base[id] = value
	mark_dirty()


func base_dict() -> Dictionary:
	return _base.duplicate()


func base_ref() -> Dictionary:
	return _base


## Set one aptitude's points. The store is deliberately a dumb dict: an id outside
## `Aptitude.all_ids()` resolves nothing (the matrix's own share rule), and nothing here
## is user-picked — the three majors' resolution writes these.
func set_aptitude(id: StringName, points: float) -> void:
	_aptitudes[id] = points
	mark_dirty()


## Replace the whole aptitude store, the shape `RealmScaling` and the majors use.
func set_aptitudes(points: Dictionary) -> void:
	_aptitudes = points.duplicate()
	mark_dirty()


func aptitude(id: StringName) -> float:
	return float(_aptitudes.get(id, 0.0))


func aptitude_points() -> Dictionary:
	return _aptitudes.duplicate()


## The ladder value a MAGNITUDE edge scales by: the actor's own realm power, PUSHED by
## `RealmScaling.apply` — never computed here, because `ActorStats` does not know which
## realm an actor stands in. `1.0` is the neutral, and a non-finite or non-positive value
## reads as the neutral rather than poisoning every magnitude edge.
func set_aptitude_ladder(value: float) -> void:
	var ladder := value if is_finite(value) and value > 0.0 else 1.0
	if is_equal_approx(ladder, _aptitude_ladder):
		return
	_aptitude_ladder = ladder
	mark_dirty()


func aptitude_ladder() -> float:
	return _aptitude_ladder


## The aptitude layer as primitives (ADR 0888): a CACHE of the build, never the truth.
## `AptitudeGrant.apply` re-derives and REPLACES it at every refresh, so a restored value
## that disagrees with the build loses; the cache exists so a save carries the layer even
## before anything re-resolves it.
func to_dict() -> Dictionary:
	var points := {}
	for id in _aptitudes.keys():
		points[String(id)] = float(_aptitudes[id])
	return {"aptitudes": points, "aptitude_ladder": _aptitude_ladder}


## Restore [method to_dict]'s payload. Tolerant by construction: an absent, malformed or
## non-finite field is the default, which is what an old save means by not carrying one.
func from_dict(data: Dictionary) -> void:
	_aptitudes = {}
	var raw: Variant = data.get("aptitudes", {})
	if raw is Dictionary:
		for key in (raw as Dictionary).keys():
			_aptitudes[StringName(key)] = float((raw as Dictionary)[key])
	var ladder := float(data.get("aptitude_ladder", 1.0))
	_aptitude_ladder = ladder if is_finite(ladder) and ladder > 0.0 else 1.0
	mark_dirty()


func set_context(context: StatContext) -> void:
	_context = context
	_context.derived = _derived
	mark_dirty()


func add_provider(provider: StatProvider) -> void:
	_providers.append(provider)
	mark_dirty()


func clear_providers() -> void:
	_providers.clear()
	mark_dirty()


func mark_dirty() -> void:
	_dirty = true
	_version += 1


func provider_count() -> int:
	return _providers.size()


func add_modifier(modifier: StatModifier) -> void:
	_modifiers.append(modifier)
	mark_dirty()


func remove_modifiers_from(source: StringName) -> void:
	var kept: Array[StatModifier] = []
	for modifier in _modifiers:
		if modifier.source != source:
			kept.append(modifier)
	_modifiers = kept
	mark_dirty()


func modifier_count() -> int:
	return _modifiers.size()


func derived(id: StringName) -> float:
	_ensure()
	_ensure_providers()
	if _provider_cache.has(id):
		return float(_provider_cache[id])
	return float(_derived.get(id, 0.0))


func derived_all() -> Dictionary:
	_ensure()
	_ensure_providers()
	var out := _derived.duplicate()
	for id in _provider_cache.keys():
		out[id] = _provider_cache[id]
	return out


func _ensure() -> void:
	if _dirty:
		_recompute()
		_dirty = false


func _ensure_providers() -> void:
	if _context == null or _providers.is_empty():
		_provider_cache.clear()
		return
	if _provider_version == _version:
		return
	_provider_cache.clear()
	var buckets := _buckets()
	for provider in _providers:
		var contributed := provider.contribute(_context)
		for id in contributed.keys():
			# A provider's contribution is the baseline for the stat; the modifier
			# stack applies exactly once on top (ADR 0026).
			var b: Dictionary = buckets.get(id, {})
			var value := (
				(float(contributed[id]) + float(b.get("flat", 0.0)))
				* (1.0 + float(b.get("percent", 0.0)))
			)
			value *= float(b.get("mult", 1.0))
			_provider_cache[id] = maxf(0.0, value)
	_provider_version = _version


func _recompute() -> void:
	_derived.clear()
	var buckets := _buckets()
	_fold_aptitudes(buckets)

	for id in _base.keys():
		_put(id, float(_base[id]), buckets)

	var physique := _attr(Stat.PHYSIQUE)
	var spirit := _attr(Stat.SPIRIT)
	var aptitude := _attr(Stat.APTITUDE)
	var comprehension := _attr(Stat.COMPREHENSION)
	var agility := _attr(Stat.AGILITY)
	var will := _attr(Stat.WILL)
	var fortune := _attr(Stat.FORTUNE)

	_put(Stat.MAX_HEALTH, 50.0 + physique * 10.0, buckets)
	_put(Stat.MAX_QI, 20.0 + spirit * 6.0 + aptitude * 8.0, buckets)
	_put(Stat.MAX_STAMINA, 100.0 + physique + agility * 2.0, buckets)
	_put(Stat.HEALTH_REGEN, physique * 0.1, buckets)
	_put(Stat.QI_REGEN, aptitude * 0.2 + spirit * 0.1, buckets)
	_put(Stat.STAMINA_REGEN, 10.0 + agility * 0.5, buckets)
	_put(Stat.ATTACK_PHYSICAL, physique * 2.0, buckets)
	# `spirit` AND `aptitude`, and — since ADR 0183 — `will`.
	#
	# **Why `will` is here, and why it was a defect that it was not.** Both terms of
	# `QiDamage` multiply this stat (`t_0 = m_0 * a_0`, ADR 0069), so whatever reads
	# zero here makes the qi mechanism propose nothing and leaves S8's chip floor
	# doing all the work. `spirit` and `aptitude` are NOT attributes every body in
	# this game is born with: `stoneborn.tres` — a shipped origin, and the FIRST one
	# `CharacterCreationFlow.RACE_BY_ORIGIN` maps — grants `{physique: 4.0,
	# will: 1.0}` and nothing else. Its `ATTACK_SPIRITUAL` was therefore exactly
	# `0.0`, and a stoneborn could enrol on the qi path (only `mind_cultivation` is
	# closed to it) and swing for nothing.
	#
	# `will` is not a new constant smuggled in to paper over that. It is core's
	# EXISTING spiritual attribute and the line directly below already reads it
	# (`DEFENSE_SPIRITUAL = spirit * 1.2 + will * 0.6`), as do `POISE`,
	# `STATUS_RESISTANCE`, `DAO_HEART` and `BREAKTHROUGH_CHANCE`. The defect was that
	# the offence and defence halves of the same spiritual contest disagreed about
	# which attributes were spiritual: a body could DEFEND against qi without being
	# able to throw it. `will` carries the same `0.6` on both sides so the pair
	# cannot drift apart again.
	#
	# This is realm-scaled (`RealmScaling.SCALED_STATS`), so it moves every actor's
	# qi numbers by `0.6 x will x realm power`. Every actor with `will == 0` is
	# bit-for-bit unchanged, which is every fixture that pins this stat's value.
	_put(Stat.ATTACK_SPIRITUAL, spirit * 2.0 + aptitude * 0.5 + will * 0.6, buckets)
	# ADR 0200: `CRIT_CHANCE`'s `minf(0.75, …)` is DELETED. A cap on an INPUT is the defect
	# the ADR exists to remove — 0.75 made crit a solved fraction past R3 — and the load
	# bearing distinction is not "percent" but "which axis": this is a trigger, and
	# AGENTS.md's rule is that a rate must never track a magnitude. It is deliberately NOT
	# re-tuned here: ADR 0877 decides what a trigger reads (a flat delta over
	# `rate_scale`), and the channel is simply unbounded, which is strictly better than a
	# ceiling a player can reach.
	# ADR 0877: the crit CHANCE trigger is `clampf((crit_chance - crit_resist) /
	# rate_scale, 0, 1)`, so the baseline is 0.0 (like ACCURACY / EVASION) and equal
	# totals read exactly zero rather than a midpoint.
	_put(Stat.CRIT_CHANCE, fortune * 0.002 + agility * 0.0005, buckets)
	# ADR 0215: the DEFENCE half of the crit-CHANCE contest. `CRIT_CHANCE` was published
	# with no counterpart, so a player could invest in crit chance with no answer — the
	# yin-yang defect. `will` is core's spiritual DEFENCE attribute (same reason as
	# CRIT_RESIST_DAMAGE below). Unbounded magnitude: a cap here would be the ADR 0200
	# defect in a fourth uniform.
	_put(Stat.CRIT_RESIST, will * 0.003, buckets)
	# ADR 0877. The `1.5 +` baseline is DELETED: under the flat-delta rule the crit
	# bonus is `1 + rate_from_zero(crit_damage, crit_resist_damage, rate_scale)`, so a
	# constant multiplier term was a bonus no defender could ever contest — the free
	# advantage the rule removes. Like `CRIT_RESIST_DAMAGE`, this is now a
	# `0.0`-baseline MAGNITUDE, and a FLAT is the only modifier form that can move it.
	_put(Stat.CRIT_DAMAGE, comprehension * 0.004, buckets)
	# ADR 0215: the DEFENCE half of the CRIT-DAMAGE contest, and the half that did not
	# exist. `CRIT_DAMAGE` was published here with no counterpart anywhere, so a player
	# could buy crit size and had no way to resist it -- `AGENTS.md`'s yin-yang rule
	# makes that a DEFECT rather than a pending item, and ADR 0215 names the id.
	#
	# ## Why it is a MAGNITUDE and not a `minf`-ed fraction
	# A cap here would be the ADR 0200 defect in a third uniform: the stat it answers
	# (`CRIT_DAMAGE`, since ADR 0877 a flat bonus of `comprehension * 0.004`) must be
	# able to grow against a 551x ladder, so this half is unbounded and a FLAT is the
	# only modifier form that can move it.
	#
	# ## Why `will`, and why it is NOT on `RealmScaling.SCALED_STATS`
	# The pair must be the SAME KIND of number on both sides, so the defence half reads
	# the attribute its offensive twin already reads (`comprehension`) rather than a
	# module-owned `composure` core does not have. `will` is core's own spiritual
	# DEFENCE attribute and the line two below already reads it (`DEFENSE_SPIRITUAL`),
	# as do `POISE`, `STATUS_DEFENSE` and `BREAKTHROUGH_CHANCE` -- so a body may DEFEND
	# against a crit without being able to throw one, which is the exact asymmetry ADR
	# 0183 fixed on the qi side. `elements/provider.gd`'s `CRIT_RESIST_WILL_STEP` chose
	# `will` for the same reason: it is the one defence term a build with no combat
	# attribute of its own can move.
	#
	# ## Why it is NOT realm-scaled, stated rather than assumed
	# `CRIT_DAMAGE` is not on `SCALED_STATS` either, and the two halves must move
	# TOGETHER or the pair is not a pair: scaling only one side would make a defender's
	# answer to a deep-realm crit grow while the crit it answers did not, so the delta
	# would fall on its own. Both are magnitudes in the attacker's own comprehension/will
	# terms, and both ride the ladder the same way.
	#
	# `0.5` means a crit against this defender keeps half its bonus: the S6 multiplier is
	# `1 + rate_from_zero(crit_damage, crit_resist_damage, rate_scale)` (ADR 0877), so a
	# defender who MATCHES the attacker cancels the bonus to zero and one who LEADS
	# refuses it outright -- a REACHABLE limit rather than an asymptotic one, which is
	# what keeps "you cannot crit me" from being a free immunity the ladder never beats.
	#
	# ## Why the baseline is `0.0` and not `1.0 +`, which was a total misreading of the same line
	# A `1.0` baseline reads as "every crit refused" under every shape this stat has ever
	# had, so `1.0 + will * 0.004` meant the defender's half STARTED at the refusal
	# point: every crit in the game was cancelled on every actor. Not a balance extreme --
	# a dead channel, invisible because a crit that does nothing still looks like a crit
	# that was resisted.
	#
	# A `1.0` baseline would have been right for a MULTIPLIER (`crit_damage * resist`), and
	# that is the shape this was copied from. A multiplier and a share are not
	# interchangeable just because both are bounded in `[0, 1]`. `contracts/stat.gd` had to
	# lose the id from `RATE_STATS` for the same reason: on a `0.0` baseline a PERCENT is
	# the ADR 0022 no-op and a FLAT is the only form that can move it, which is precisely
	# what membership in `RATE_STATS` forbids.
	#
	# It is a MAGNITUDE, like `CRIT_RESIST` (the other half of the crit-CHANCE contest,
	# `will * 0.003`, also absent from `RATE_STATS`) — the pair reads the same attribute for
	# the same reason, and one of the two being a rate while its twin is a magnitude is
	# what let the wrong baseline look plausible in the first place.
	_put(Stat.CRIT_RESIST_DAMAGE, will * 0.004, buckets)
	_put(Stat.PENETRATION, spirit * 0.5, buckets)
	# `ATTACK_SPEED` is one of the three caps ADR 0200 DELIBERATELY KEEPS. See below.
	_put(Stat.ATTACK_SPEED, minf(2.5, 1.0 + agility * 0.008), buckets)
	_put(Stat.DEFENSE_PHYSICAL, physique * 1.5, buckets)
	_put(Stat.DEFENSE_SPIRITUAL, spirit * 1.2 + will * 0.6, buckets)
	# ADR 0200: `EVASION`'s `minf(0.6, …)` is DELETED, same reason as CRIT_CHANCE above.
	# The comment on `_crit` in `spine.gd` and the S2 docblock both quote this cap, so both
	# are corrected in the same change rather than left asserting a number that no longer
	# exists.
	_put(Stat.EVASION, agility * 0.0015, buckets)
	# ADR 0877. The OFFENCE half of the hit contest, DERIVED at last: it was declared
	# and never published, so every attack carried `accuracy == 0.0` and — under the
	# flat-delta rule — any defender with evasion at all was unhittable. The coefficient
	# matches EVASION's on purpose; the trailing constant is the attack's BASE accuracy,
	# so an equally-agile defender is hit half the time at the shipped `rate_scale`
	# (`0.005 / 0.01`), and out-evading the base takes about 3.3 more agility than the
	# attacker (`0.005 / 0.0015`), or authored accuracy content. Attribute-first so the
	# registration scanner reads it as the MAGNITUDE it is, never a multiplier.
	_put(Stat.ACCURACY, agility * 0.0015 + 0.005, buckets)
	_put(Stat.POISE, physique * 0.5 + will * 0.5, buckets)
	# ADR 0200: `STATUS_RESISTANCE` was `minf(0.8, will * 0.003)` and the cap needed
	# `will >= 250` against an authored `base_will` topping out at 54.9 (DEF-0262) — so it
	# was a dead stat at every realm a player could actually reach, and `0.8` was the only
	# number a designer could read. It is now `STATUS_DEFENSE`: the SAME authored
	# coefficient, unbounded, and it is the `D` of ADR 0200's ratio rather than a percent.
	# The value at a race's own `will == 2.0` is therefore still `0.006` at R1, and the
	# id is on `RealmScaling.SCALED_STATS` so it climbs with the ladder from there.
	_put(Stat.STATUS_DEFENSE, will * 0.003, buckets)
	_put(Stat.MOVE_SPEED, 100.0 + agility * 2.0, buckets)
	_put(Stat.CULTIVATION_RATE, 1.0 + aptitude * 0.02, buckets)
	_put(Stat.QI_ABSORPTION, aptitude * 0.5 + spirit * 0.2, buckets)
	_put(Stat.BREAKTHROUGH_CHANCE, 0.1 + comprehension * 0.01 + will * 0.005, buckets)
	# `will` PLUS this actor's heart scar: a crack is a NEGATIVE offset on the dao
	# heart's own base (`DaoHeart.crack`/`rebuild`), added here rather than applied as
	# a modifier because modifiers are not serialized and a scar that healed on reload
	# would be a lie (`DaoHeart`'s docblock). `_put` floors the effective value at zero.
	_put(Stat.DAO_HEART, will + _base.get(Stat.DAO_HEART, 0.0), buckets)
	# ## BL-0822: the rate is NOT a function of the quantity it grows
	#
	# This was `1.0 + comprehension * 0.01`, and TWO training paths multiply their
	# comprehension GAIN by this stat (`mind_cultivation/training.gd` and
	# `body_cultivation/training.gd`). So the gain was a function of the quantity it grew:
	# `dC = k(1 + 0.01 C)`, which is exponential in C, not linear in the work done.
	# Measured before the fix: comprehension compounded to 2.1e+37 on a long enough run,
	# which is past the range any gate in this game can price and past `double`'s useful
	# precision for the gates that read it. A rate that reads its own stock is a runaway by
	# construction, whatever coefficient it carries.
	#
	# `will` is the MIND path's own attribute - ADR 0013 sources `dao_heart` from it, and
	# the mind ladder is what this rate pays into - so the stat still scales with the actor
	# instead of being a flat 1.0, and it can be raised by content (sect offices grant
	# `insight_gain` directly). It is deliberately NOT `aptitude * 0.02`, which is
	# `CULTIVATION_RATE`'s formula: two stats sharing one expression is the second-copy
	# shape ADR 0116 forbids, and these are two different pipelines.
	_put(Stat.INSIGHT_GAIN, 1.0 + will * 0.01, buckets)
	_put(Stat.LOOT_BONUS, fortune * 0.01, buckets)
	# ADR 0200: `COOLDOWN_REDUCTION` (0.4) and `QI_COST_REDUCTION` (0.5) KEEP their caps,
	# deliberately and by the ADR's own stated test rather than by omission.
	#
	# The test: *a cap on a mitigation or defense axis DIES, because that axis must scale
	# with the ladder; a cap on a RATE axis STAYS, because rate is not what power creep
	# rides.* These three bound degenerate stacking on axes that do not scale with realm --
	# an unbounded attack speed is a broken game rather than a power-creep problem, and
	# removing their ceilings would cost a player nothing the ladder would otherwise have
	# given them. AGENTS.md says it more sharply: a rate must never track a magnitude
	# (ADR 0050), which is why these are the three that survive and not a rounding error.
	_put(Stat.COOLDOWN_REDUCTION, minf(0.4, comprehension * 0.002), buckets)
	_put(Stat.QI_COST_REDUCTION, minf(0.5, aptitude * 0.001), buckets)
	_put(Stat.DAMAGE_REDUCTION, 0.0, buckets)

	# A modifier on a stat NOTHING backs used to be discarded outright. `_recompute`
	# writes a fixed list of core ids and `_ensure_providers` writes whatever providers
	# contribute, so a FLAT modifier on a MODULE-owned id -- combat's `accuracy`,
	# `parry.rate`, `reflect.resist.rate` and the rest of `CombatStats.RATE_IDS`, which
	# have no provider and no core entry -- read `0.0` instead of its own value. The
	# modifier was on the actor and simply never applied.
	#
	# Back every remaining bucket at `0.0` through the SAME `_put` formula, so the ADR
	# 0022 trap is preserved rather than papered over: a FLAT reads `(0.0 + v) * 1 = v`,
	# and a PERCENT still reads `(0.0 + 0.0) * 1.25 = 0.0`, which is exactly why
	# `CombatStats.RATE_DEFAULTS` is all zeros and why ADR 0068 demands a shape test.
	# A percentage must not be able to conjure a rate out of nothing; a flat addition is
	# an authored number and has always been legal.
	for id in buckets.keys():
		if not _derived.has(id):
			_put(id, 0.0, buckets)


## ADR 0882. What an actor has BUILT, resolved by the matrix and injected as a FLAT
## bucket BEFORE any `_put` runs, so the contribution enters the SAME
## `(base + flat) * (1 + percent) * mult` formula every other source does — exactly
## once, never double-stacked on a channel that also has an attribute formula.
##
## An actor with NO aptitudes resolves nothing AND loads nothing: every pre-aptitude
## actor is byte-identical to the tree before this wire existed.
func _fold_aptitudes(buckets: Dictionary) -> void:
	if _aptitudes.is_empty():
		return
	var table := AptitudeTable.shipped()
	if table == null:
		return
	var contributions := AptitudeMatrix.resolve(
		table.to_edges(), _aptitudes, table.share_exponent, table.contest_span, _aptitude_ladder
	)
	for id in contributions.keys():
		var b: Dictionary = buckets.get(id, {})
		b["flat"] = float(b.get("flat", 0.0)) + float(contributions[id])
		buckets[id] = b


func _put(id: StringName, base_value: float, buckets: Dictionary) -> void:
	var b: Dictionary = buckets.get(id, {})
	var value := (base_value + float(b.get("flat", 0.0))) * (1.0 + float(b.get("percent", 0.0)))
	value *= float(b.get("mult", 1.0))
	_derived[id] = maxf(0.0, value)


## Group the modifier stack into per-stat {flat, percent, mult} buckets.
## Single source of truth for modifier resolution, shared by core derived stats
## and provider-contributed baselines (ADR 0026).
func _buckets() -> Dictionary:
	var buckets := {}
	for modifier in _modifiers:
		var b: Dictionary = buckets.get(modifier.stat, {})
		match modifier.op:
			Stat.Op.FLAT:
				b["flat"] = float(b.get("flat", 0.0)) + modifier.value
			Stat.Op.PERCENT:
				b["percent"] = float(b.get("percent", 0.0)) + modifier.value
			Stat.Op.MULT:
				b["mult"] = float(b.get("mult", 1.0)) * modifier.value
		buckets[modifier.stat] = b
	return buckets


func _attr(id: StringName) -> float:
	return float(_derived.get(id, get_base(id)))
