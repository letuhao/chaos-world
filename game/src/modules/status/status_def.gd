class_name StatusDef
extends Resource

## One authored status (ADR 0090). The catalogue is `.tres` content and never code,
## exactly as `ElementDef` is the precedent for elements (ADR 0004): adding a status
## is a file, and every number a designer would tune lives here rather than in a
## literal inside a rule.
##
## ## What is authored here, and what is deliberately NOT
##
## These are exactly the ADR 0086 instance fields a designer decides: the identity,
## the element it rides, how it resolves, how long it lasts, and the levers that
## reduce it. The NUMERIC magnitude is absent on purpose — potency is a share of the
## elemental term the hit already landed, read from `element_power_<e>` and scaled by
## a `CombatTuning` field (ADR 0088/0090), so pinning a number per status would invent
## a second magnitude vocabulary that a rebalance has to edit twenty times.
## `magnitude_cap` is the one ceiling that IS authored, because a bound is a designer's
## to own.
##
## ## `mitigation_tags` is mandatory, and is the whole counterplay contract
##
## Empty is an authoring error, not a free tax: ADR 0090 restates ADR 0075's rule for
## a hazard zone, and a status nothing answers to is a debuff with no answer. So is a
## set that is affinity-only — that denies a player with the wrong spirit root any
## authored counterplay (the rule `domain_map_contract.gd` already enforces for zones).
##
## ## `on_landed_blow` is the SELECTOR, and it is authored rather than derived
##
## ADR 0105 makes a landed blow inflict the ELEMENT's status, and each tier-1 element
## ships TWO statuses (`fire_immolation` and `fire_pyre`), so "the element's status" is
## a choice someone has to make. Deriving it would mean picking one of the pair in code
## — by filename, by catalogue order, by kind — which is a balance number wearing a
## tie-break's name, and it would silently move if a third status were authored on that
## element. So the choice is a boolean a designer flips, exactly as ADR 0090 makes every
## other per-status decision a `.tres` field.
##
## It defaults to `false` rather than to some sensible default, because the wrong default
## here is the one that hurts: a def authored without it loads, resolves, ticks and is
## perfectly legal, and simply never rides a blow. A default of `true` would put every
## status a future author forgets about on every landed blow.
##
## The HOW MUCH is deliberately NOT here. ADR 0087's `status_chance` is the caller's gate
## — a stat a build moves — and ADR 0088's potency is `element_power_<e>` read by
## `StatusApply`. Two authored numbers here would be a second gate and a second magnitude
## vocabulary; see `StatusApi.status_for_element`, which takes the chance as an argument
## for that reason.
##
## ## `payload` carries what is not a stat
##
## Exactly what ADR 0086 says: the damage channel (`pool`, `share_per_pulse`), the
## control gates, the amplification wiring, the authored `StatModifier` list, and the
## one line of player-facing text a status screen shows. Values inside `modifiers` are
## PER UNIT OF MAGNITUDE, so one authored number states the whole curve and
## `magnitude_cap` bounds it.

## Tier-1 五行 only. Restated rather than read from `ElementStats.BASE_ELEMENTS`:
## `tools new_module` grants this module `core` + `contracts` alone, and a bare
## cross-module reference is an edge `tools arch` cannot see (AGENTS.md:140 calls that
## class of dependency invisible). `tests/modules/status/test_status_catalogue.gd`
## asserts this list still equals `ElementStats.BASE_ELEMENTS`, so the restatement
## cannot drift.
const TIER_ONE_ELEMENTS: Array[StringName] = [
	&"metal",
	&"wood",
	&"water",
	&"fire",
	&"earth",
]

## Tier 2, restated for the same reason (ADR 0110 lifts ADR 0090's tier-1-only clause).
## `tests/modules/status/test_status_catalogue.gd` asserts both lists still equal their
## `ElementStats` counterparts, so neither restatement can drift.
const TIER_TWO_ELEMENTS: Array[StringName] = [
	&"lightning",
	&"ice",
	&"wind",
	&"light",
	&"dark",
]

## Every element a status may ride: all ten. A status on an element outside this set is
## REJECTED at construction, never clamped — an unknown element is a load-time refusal
## because a def that names nothing resolvable would otherwise load and silently never
## apply (ADR 0039's rule, applied to the vocabulary rather than to a number).
const AUTHORED_ELEMENTS: Array[StringName] = TIER_ONE_ELEMENTS + TIER_TWO_ELEMENTS
const KINDS: Array[StringName] = [
	&"dot",
	&"stat_modifier",
	&"control",
	&"amplifier",
	&"burst",
]
const SCOPES: Array[StringName] = [&"combat", &"cultivation"]
const STACKING: Array[StringName] = [&"refresh", &"stack", &"replace"]
## Where a status's magnitude comes from. A closed vocabulary, so a typo is an
## authoring error rather than a silently inert status.
const MAGNITUDE_UNITS: Array[StringName] = [
	&"element_power",
	&"health_share",
	&"stat_modifier",
	&"sibling_amp",
]
## How the status resolves. Ten mechanics, ten statuses: the two statuses of one
## element are never the same effect wearing a different element (ADR 0090 refuses a
## catalogue that is twenty damage numbers).
const MECHANICS: Array[StringName] = [
	&"bleed",
	&"drain",
	&"sunder",
	&"regrowth",
	&"slow",
	&"wave",
	&"escalating_burn",
	&"feed_siblings",
	&"brace",
	&"root",
]
## The four mitigation levers, identical to `EnvironmentZoneDef.LEVERS`. Restated for
## the same reason `TIER_ONE_ELEMENTS` is, and asserted equal by the test tree; one
## purge vocabulary is read by combat, environment and consumables alike (ADR 0086).
const LEVERS: Array[StringName] = [&"affinity", &"gear", &"technique", &"pill"]
## Pools a status may spend. A bounded pool write is a channel, not a damage formula.
const POOLS: Array[StringName] = [&"health", &"qi", &"stamina"]
const OPS: Array[StringName] = [&"flat", &"percent"]
## Stats a PERCENT modifier on is refused for, because authoring one is a mistake:
## `ActorStats._put` resolves `(base + flat) * (1 + percent)`, and for every id below a
## PERCENT is either a guaranteed no-op or an author-confusing rounding error. **The
## list is a single authoring convention covering FIVE differently-shaped stats**, and
## the note on each is what tells a designer which of the two they are in.
##
## ## The two shapes in this list, MEASURED rather than asserted (DEF-0262, 2026-10-04)
##
## - `damage_reduction` is the ONLY one whose baseline is the CONSTANT `0.0`. A PERCENT
##   there is the literal ADR 0022 defect: `(0.0 + 0.0) * (1 + p) = 0.0` for every `p`,
##   44 items once granted nothing at all.
## - The other four are `minf(cap, attribute * k)` — ADR 0022's `attribute-gated` shape,
##   which stays in `Stat.RATE_STATS` because the cap term makes FLAT the worse error.
##   Their baseline is a small NON-ZERO number, so a PERCENT is not *literally* inert, and
##   an earlier revision of this comment claimed they read `0.0` for every actor and
##   that PERCENT was "meaningful in normal play". **Both halves were wrong.** Measured
##   through a real `ActorStats`: `status_resistance` on a shipped race's own `will` of
##   `2.0` reads `0.006`, not `0.0`.
##
## So for the attribute-gated four the refusal is a CONVENTION, not an arithmetic
## necessity: the lever is much smaller than the author of `percent 0.2` will picture,
## and a FLAT states the same intent on a 0..1 stat unambiguously. Refusing it anyway is
## what stops five ids from spelling the same number two ways.
##
## Per-stat gate arithmetic, each measured against the authored content:
## - `evasion`        = `minf(0.6, agility * 0.0015)`        needs agility 400;   authored 1..15
## - `status_resistance` = `minf(0.8, will * 0.003)`       needs will 250;      authored 3..52.9
## - `cooldown_reduction` = `minf(0.4, comprehension * 0.002)`
##   needs comprehension 500; authored 0..18
## - `qi_cost_reduction` = `minf(0.5, aptitude * 0.001)`   needs aptitude 500;  authored 1..13
## - `damage_reduction`  = `0.0`                           needs nothing
##
## Every gate is one to two orders of magnitude past the top of its authored range. The
## attribute-gated four therefore sit at a SMALL fraction of their cap in real play, and
## that is the stat's shape working: ADR 0087's multiplicative form still bottoms out at
## `1.0 * (1 - 0.8) = 0.2` and `status_min_apply` is the floor under THAT.
##
## The audit is checked against the STAT, never against the status that carries it
## (ADR 0090). `tests/modules/status/test_status_refusals.gd` pins each id against a
## real `ActorStats` baseline rather than against this list, so a stat moved in or out
## fails the suite rather than silently changing what `problems()` refuses.
const ZERO_BASELINE_STATS: Array[StringName] = [
	&"cooldown_reduction",
	&"damage_reduction",
	&"evasion",
	&"qi_cost_reduction",
	&"status_resistance",
]
## `StatusEffect.is_permanent()`'s sentinel, restated as a duration a designer can
## author: a CULTIVATION gift with no expiry.
const DURATION_FOREVER := -1.0

@export var id: StringName = &""
@export var element: StringName = &""
## Whether a landed blow carrying this element inflicts THIS status. The element→status
## mapping of ADR 0105, authored; see the docblock above for why it is not derived and
## why `false` is the safe default.
@export var on_landed_blow: bool = false
## Whether this status is inflicted by BEING SOMEWHERE rather than by a landed blow:
## an ADR 0075 environment zone, an ADR 0073 trap. An ambient def is a PLACE and not a
## blow, so it answers to the zone's or fixture's own `kind` rather than to one element,
## and `problems()` stops requiring one — see that method for why that is a relaxation
## of a gate rather than the deletion of one.
##
## ## Why this is authored rather than inferred from an empty element
##
## Inference would make every future typo into a hazard: a def whose `element` was
## forgotten would quietly become an ambient status and pass. Authored, the refusal is
## the same one thing everywhere — a def that has neither an element nor an ambient
## claim is an incomplete authoring, not a hazard.
##
## ## `false` is the safe default, for [member StatusDef.on_landed_blow]'s reason
##
## An ambient status is never reachable from `status_for_element`, because it declares
## no element to claim one.
@export var ambient: bool = false
@export var kind: StringName = &"dot"
@export var scope: StringName = &"combat"
@export var stacking: StringName = &"refresh"
@export var duration: float = 0.0
@export var magnitude_unit: StringName = &"stat_modifier"
@export var magnitude_cap: float = 0.0
@export var tick_interval: float = 1.0
@export var mitigation_tags: Array[StringName] = []
@export var payload: Dictionary = {}


func mechanic() -> StringName:
	return StringName(payload.get("mechanic", &""))


## The one line a status screen shows. Authored copy, not a code-composed sentence:
## the ten statuses are a fiction first and a number second.
func text() -> String:
	return String(payload.get("text", ""))


func is_permanent() -> bool:
	return duration < 0.0


func is_combat_scope() -> bool:
	return scope == &"combat"


## The authored `StatModifier` list, normalized to `{stat, op, value}`. Empty for a
## status whose whole effect is its damage channel (`water_deluge`) or whose effect is
## second-order over its siblings (`fire_pyre`) — both are legitimate, and neither
## contributes a stat.
func modifiers() -> Array:
	var out: Array = []
	for entry in payload.get("modifiers", []):
		if entry is Dictionary:
			out.append(entry)
	return out


## Every defect that must stop this def from reaching play. Empty means authored
## correctly. Called by the facade's `validate()` and refused by `apply()`, so a bad
## `.tres` is rejected at construction rather than clamped at runtime (ADR 0039).
func problems() -> Array[String]:
	var out: Array[String] = []
	if id == &"":
		out.append("has no id")
	# ## The element gate is conditional, and the condition is AUTHORED
	#
	# Every one of the twenty in `res://data/statuses/` is inflicted by a landed blow
	# carrying an element, so naming one is how a def says which. An AMBIENT def is not:
	# an ADR 0075 zone applies it by the actor STANDING THERE, and what the zone is
	# hostile to is the zone's own `kind` -> element table
	# (`EnvironmentField.HOSTILE_ELEMENTS`), not a property of the status. Forcing
	# `fire` onto a furnace would be a lie the shipped catalogue would act on —
	# `StatusApi.status_for_element` would answer with it for every fire blow in the
	# game — so the gate asks the def which of the two it is instead of assuming.
	#
	# The relaxation is bounded in both directions: an AMBIENT def may name an element,
	# and is still checked against [constant AUTHORED_ELEMENTS] if it does; and a
	# non-ambient def names nothing and is refused exactly as before. Every other rule
	# below is untouched, so an ambient hazard still owes non-empty `mitigation_tags`
	# (ADR 0075), a resolvable channel and a positive cadence.
	if element == &"":
		if not ambient:
			(
				out
				. append(
					(
						"declares no element and does not claim to be ambient; every status a landed "
						+ "blow inflicts names the element it rides (author `ambient = true` for a hazard)"
					)
				)
			)
	elif not AUTHORED_ELEMENTS.has(element):
		out.append(
			(
				"element '%s' is not one of the ten authored elements; allowed: %s"
				% [String(element), _names(AUTHORED_ELEMENTS)]
			)
		)
	if not KINDS.has(kind):
		out.append("unknown kind '%s'; allowed: %s" % [String(kind), _names(KINDS)])
	if not SCOPES.has(scope):
		out.append("unknown scope '%s'; allowed: %s" % [String(scope), _names(SCOPES)])
	if not STACKING.has(stacking):
		out.append("unknown stacking '%s'; allowed: %s" % [String(stacking), _names(STACKING)])
	if not MAGNITUDE_UNITS.has(magnitude_unit):
		out.append(
			(
				"unknown magnitude_unit '%s'; allowed: %s"
				% [String(magnitude_unit), _names(MAGNITUDE_UNITS)]
			)
		)
	if tick_interval <= 0.0:
		out.append("tick_interval must be positive or the status can never resolve")
	if magnitude_cap <= 0.0:
		out.append("has no magnitude_cap, so an unbounded application has nothing to stop at")
	if not is_permanent() and duration <= 0.0:
		out.append("expires the moment it lands")
	out.append_array(_mitigation_problems())
	out.append_array(_mechanic_problems())
	out.append_array(_modifier_problems())
	return out


## Primitives only, so a screen and a test read the same dict (AGENTS.md's testable
## contract). A UI never touches the `Resource` behind a catalogue row.
func to_dict() -> Dictionary:
	var levers: Array = []
	for lever in mitigation_tags:
		levers.append(String(lever))
	var mods: Array = []
	for entry in modifiers():
		(
			mods
			. append(
				{
					"stat": String(entry.get("stat", "")),
					"op": String(entry.get("op", "")),
					"value": float(entry.get("value", 0.0)),
				}
			)
		)
	return {
		"id": String(id),
		"element": String(element),
		"ambient": ambient,
		"on_landed_blow": on_landed_blow,
		"kind": String(kind),
		"scope": String(scope),
		"stacking": String(stacking),
		"mechanic": String(mechanic()),
		"text": text(),
		"duration": duration,
		"permanent": is_permanent(),
		"magnitude_unit": String(magnitude_unit),
		"magnitude_cap": magnitude_cap,
		"tick_interval": tick_interval,
		"mitigation_tags": levers,
		"modifiers": mods,
		"pool": String(payload.get("pool", "")),
		"share_per_pulse": float(payload.get("share_per_pulse", 0.0)),
		"escalation_per_tick": float(payload.get("escalation_per_tick", 0.0)),
		"escalation_cap": float(payload.get("escalation_cap", 1.0)),
		"sibling_gain": float(payload.get("sibling_gain", 0.0)),
		"sibling_cap": float(payload.get("sibling_cap", 0.0)),
		"spends_on_apply": bool(payload.get("spends_on_apply", false)),
		"blockable": bool(payload.get("blockable", true)),
	}


func _mitigation_problems() -> Array[String]:
	var out: Array[String] = []
	if mitigation_tags.is_empty():
		out.append("publishes no mitigation_tags; a status nothing answers to is a flat tax")
		return out
	for lever in mitigation_tags:
		if not LEVERS.has(lever):
			out.append(
				"mitigation_tag '%s' names no lever; allowed: %s" % [String(lever), _names(LEVERS)]
			)
	if mitigation_tags.size() == 1 and mitigation_tags[0] == &"affinity":
		out.append(
			(
				"is mitigated by affinity alone, so a player with the wrong spirit root has "
				+ "no authored counterplay"
			)
		)
	return out


func _mechanic_problems() -> Array[String]:
	var out: Array[String] = []
	var name := mechanic()
	if not MECHANICS.has(name):
		out.append("payload names unknown mechanic '%s'" % String(name))
	if text().is_empty():
		out.append("carries no player-facing text")
	# A status has to RESOLVE against its magnitude, or it is decoration: the channel
	# it spends, the stat it holds, the escalation it grows, or the siblings it reads.
	# `metal_sever` is the case this rule catches — a bleed that names a pool but no
	# share spends nothing, so authoring it correctly would have been a silent no-op.
	if magnitude_unit == &"health_share":
		var pool := StringName(payload.get("pool", ""))
		if not POOLS.has(pool):
			out.append("health_share channel names no pool; allowed: %s" % _names(POOLS))
		if float(payload.get("share_per_pulse", 0.0)) <= 0.0:
			out.append("health_share channel spends nothing")
	elif magnitude_unit == &"stat_modifier":
		if modifiers().is_empty():
			out.append("is a stat_modifier with no authored modifier")
	elif magnitude_unit == &"sibling_amp":
		if float(payload.get("sibling_gain", 0.0)) <= 0.0:
			out.append("is a sibling amplifier with no authored sibling_gain")
	elif magnitude_unit == &"element_power":
		var spends := (
			float(payload.get("share_per_pulse", 0.0)) > 0.0
			or bool(payload.get("spends_on_apply", false))
			or float(payload.get("escalation_per_tick", 0.0)) > 0.0
		)
		if not spends:
			out.append("element_power channel never spends its magnitude")
	return out


## ADR 0090's load-bearing authoring rule: the op is validated against the STAT id.
## FLAT on a rate stat multiplies a 0..1 baseline; PERCENT on a zero-baseline stat is
## a guaranteed no-op. Either one silently deletes the status, so neither is clamped.
func _modifier_problems() -> Array[String]:
	var out: Array[String] = []
	for entry in modifiers():
		var stat_id := StringName(entry.get("stat", ""))
		var op := StringName(entry.get("op", ""))
		if stat_id == &"":
			out.append("authors a modifier with no stat id")
			continue
		if not OPS.has(op):
			out.append(
				(
					"stat '%s' declares unknown op '%s'; Op.MULT is banned for a status"
					% [String(stat_id), String(op)]
				)
			)
			continue
		if op == &"flat" and Stat.RATE_STATS.has(stat_id):
			(
				out
				. append(
					(
						"stat '%s' takes FLAT, but it is a RATE_STATS id: +10 means 1000%%. Use percent."
						% String(stat_id)
					)
				)
			)
		if op == &"percent" and ZERO_BASELINE_STATS.has(stat_id):
			(
				out
				. append(
					(
						(
							"stat '%s' has a 0.0 baseline for every actor this game builds, so PERCENT "
							+ "reads (0.0 + 0.0) * (1 + p) = 0.0 and grants nothing (ADR 0022). Use flat."
						)
						% String(stat_id)
					)
				)
			)
	return out


func _names(values: Array) -> String:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return ", ".join(out)
