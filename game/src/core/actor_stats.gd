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
	# bearing distinction is not "percent" but "which axis": this is a RATE contest, and
	# AGENTS.md's rule is that a rate must never track a magnitude. It is deliberately NOT
	# re-tuned here either: ADR 0215 decides what a rate contest reads, and this change
	# must not collide with it. Until then the channel is simply unbounded, which is
	# strictly better than a ceiling a player can reach.
	# ADR 0215: the crit CHANCE contest is now `crit_chance / (crit_chance + crit_resist)`,
	# so the baseline is 0.0 (like ACCURACY / EVASION) rather than a bare 0.05 — the
	# contest ratio supplies the baseline, not a constant term.
	_put(Stat.CRIT_CHANCE, fortune * 0.002 + agility * 0.0005, buckets)
	# ADR 0215: the DEFENCE half of the crit-CHANCE contest. `CRIT_CHANCE` was published
	# with no counterpart, so a player could invest in crit chance with no answer — the
	# yin-yang defect. `will` is core's spiritual DEFENCE attribute (same reason as
	# CRIT_RESIST_DAMAGE below). Unbounded magnitude: a cap here would be the ADR 0200
	# defect in a fourth uniform.
	_put(Stat.CRIT_RESIST, will * 0.003, buckets)
	_put(Stat.CRIT_DAMAGE, 1.5 + comprehension * 0.004, buckets)
	# ADR 0215: the DEFENCE half of the CRIT-DAMAGE contest, and the half that did not
	# exist. `CRIT_DAMAGE` was published here with no counterpart anywhere, so a player
	# could buy crit size and had no way to resist it -- `AGENTS.md`'s yin-yang rule
	# makes that a DEFECT rather than a pending item, and ADR 0215 names the id.
	#
	# ## Why it is a MAGNITUDE and not a `minf`-ed fraction, on CRIT_DAMAGE's own rule
	# `CRIT_DAMAGE` carries a constant `1.5` term, and the `1.0`-baseline MULTIPLIER is
	# what makes this stat a RATE regardless of its scale (`contracts/stat.gd:346`): `+10`
	# means a crit lands ten times as hard, not "+10%". So this one is unbounded — a cap
	# here would be the ADR 0200 defect in a third uniform, and the stat it answers must
	# be able to grow against a 551x ladder.
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
	# TOGETHER or the contest is not a contest: scaling only one side would make a
	# defender's answer to a deep-realm crit grow while the crit it answers did not, so
	# `1.0 - crit_resist_damage` would climb past `0.0` on its own. Both are magnitudes in
	# the attacker's own comprehension/will terms, and both ride the ladder the same way.
	#
	# `0.5` means a crit against this defender lands at half: the S6 multiplier is
	# `crit_damage * (1 - CRIT_RESIST_DAMAGE)` floored at `0.0`, NOT a division, so a
	# fully invested defender refusing every crit is a REACHABLE limit and not an
	# asymptotic one -- which is deliberate, and is what keeps "you cannot crit me" from
	# being a free immunity that the ladder can never beat.
	_put(Stat.CRIT_RESIST_DAMAGE, 1.0 + will * 0.004, buckets)
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
	_put(Stat.DAO_HEART, will, buckets)
	_put(Stat.INSIGHT_GAIN, 1.0 + comprehension * 0.01, buckets)
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
