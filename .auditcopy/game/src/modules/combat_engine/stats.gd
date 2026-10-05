class_name CombatStats
extends RefCounted

## The defensive vocabulary's stat ids (ADR 0068) and the defaults the spine reads.
##
## ## These ids live HERE, not in `contracts/stat.gd`
##
## `Stat` is core vocabulary — the seven attributes and the derived stats every path
## already shares. Twenty more combat-only ids would put combat vocabulary in core,
## and ADR 0068's own consequence says it plainly: a module may define its own ids.
## `CombatStats` is that module's list. Adding an id here costs no `contracts/` change
## and no schema bump.
##
## ## The ADR 0022 trap, and why `RATE_IDS` exists
##
## `Stat.DAMAGE_REDUCTION` is FLAT with a `0.0` baseline and is deliberately ABSENT
## from `Stat.RATE_STATS`. A `PERCENT` modifier on a `0.0`-baseline stat evaluates to
## `(0.0 + 0.0) * (1 + p) = 0.0` — a silent no-op that shipped on 44 items, validated
## clean because the contract that validated it was itself wrong.
##
## Every rate-shaped id below has a `0.0` baseline and the same trap. `Stat.RATE_STATS`
## is hand-written over STATIC core ids, so these combat-owned ids are invisible to it
## and **must not be added to it** — ADR 0022's cheaper guard is to derive membership
## from the baselines. `RATE_IDS` is that derived membership for combat's own ids, and
## `tests/modules/combat/test_combat_stats_shape.gd` is the SHAPE TEST ADR 0068
## requires: each one must have a zero-or-rate default and must be authored `op: FLAT`,
## `unit: "rate"`. Adding a rate-shaped id without that is the defect class, silent by
## construction.
##
## ## Defaults are DEFAULTS, not balance
##
## The numbers here are the neutral reading of a stat nobody has invested in, so an
## unstatted actor is parried 0% of the time rather than 50% (ADR 0068). They are not
## the shipped balance — the shipped balance for the spine's own arithmetic lives in
## `combat_damage.tres` (`CombatTuning`), and any rate VALUE in real play arrives as a
## `StatModifier`. This file holds the ids and their neutral shape, nothing else.

# --- Offensive vocabulary -----------------------------------------------------

## Reduces the defender's `EVASION` for this attacker. Flat, because `EVASION` is a
## rate and a rate is contested by subtraction, never by multiplication (ADR 0068).
const ACCURACY := &"accuracy"
## How hard the attacker cuts the defender's elemental guard, as a RATE in the same
## `[0, 1]` space as `resist`, so it can be SUBTRACTED from a resistance before the clamp
## (ADR 0069). A read-only input to a mechanism's `mitigate`, never a stage of the spine.
##
## ## Why this is `penetration.rate` and NOT `Stat.PENETRATION`
##
## It was `&"penetration"`, which is core's id, and core derives that one in POINTS
## (`spirit * 0.5`, `core/actor_stats.gd:156`). One string, two quantities: an actor with
## spirit 10.0 derived `5.0`, which `_resistance_of` then subtracted from a resistance
## living in `[0, 1]` — so every elemental resistance in the game read `0.0` and mastery
## penetration could never be observed at all. Nothing caught it because
## `test_no_combat_id_is_a_core_stat_id` compared against `Stat.BASE_ATTRIBUTES +
## Stat.RATE_STATS`, and core's DERIVED ids are in neither list; that test now probes a
## live actor instead, which is the only check that sees this class.
const PENETRATION := &"penetration.rate"
## Scales the attacker's amount up. Read at S7 with `REDUCTION`, and only there.
const AMPLIFICATION := &"amplification"
## The flat subtraction applied at S7. Reads `Stat.DAMAGE_REDUCTION` too; see
## `RESIST_REDUCTION` for why both are summed rather than replaced.
const REDUCTION := &"reduction"
## Share of the amount a defender returns as a post-shield bounce (S10). Bounded below
## 1.0 so thorns can at most tie against an equal-health attacker (ADR 0068).
const REFLECT_RATE := &"reflect.rate"
## Scales the bounced amount. The bounce carries no element payload, so it is neither
## re-mitigated nor able to crit (ADR 0068).
const REFLECT_DAMAGE := &"reflect.damage"
## How hard the defender blunts a bounce: the same rate contest as parry, at the same
## rate scale, and terminal — a bounce that loses it does not bounce again.
const REFLECT_RESIST_RATE := &"reflect.resist.rate"
## Scales that blunting.
const REFLECT_RESIST_DAMAGE := &"reflect.resist.damage"

# --- Defensive vocabulary -----------------------------------------------------

## Share of an incoming amount a defender refuses before it reaches the spine. The
## shield's contribution is `SHIELD_CAPACITY`; this is everything else.
const ABSORPTION := &"absorption"
## Chance, contested against `ACCURACY` / `EVASION`, that an attack is parried (S2).
## Carved out of the TOP of the would-have-been-a-hit region.
const PARRY_RATE := &"parry.rate"
## Scales `PARRY_RATE` without changing its sign: at zero it reads zero, so a
## `strength`-only investment still parries 0% rather than a sigmoid's 0.5.
const PARRY_STRENGTH := &"parry.strength"
## What parrying costs the defender: `break` spends poise, `shred` spends the ability
## to parry again. Both are read by the defensive response, not by the spine.
const PARRY_BREAK := &"parry.break"
const PARRY_SHRED := &"parry.shred"
## Block's twin of the four above. Same band, same contest, one vocabulary.
const BLOCK_RATE := &"block.rate"
const BLOCK_STRENGTH := &"block.strength"
const BLOCK_BREAK := &"block.break"
const BLOCK_SHRED := &"block.shred"

# --- Shield channels ----------------------------------------------------------

## How much the shield has left. Read-only input to S9 (ADR 0068).
const SHIELD_CAPACITY := &"shield.capacity"
## Multiplier on what the shield removes. Read-only input to S9.
const SHIELD_TOUGHNESS := &"shield.toughness"
## How much of the shield the attacker cuts before S9 runs.
const SHIELD_PEN := &"shield.pen"
## What the shield restores per second. NOT read by the spine: regen belongs to a
## combat tick, not to one hit's resolution, and a regen inside a resolve would
## reorder the stages it runs between.
const SHIELD_REGEN := &"shield.regen"

# --- Leech --------------------------------------------------------------------

## Share of the amount actually spent on the target's health returned to the attacker.
## Applied as a SEPARATE packet after the HP write (S11), never as a modification of
## the incoming hit: a heal that reduced the damage would make the two orders the same
## order, and the four load-bearing orderings would stop being load-bearing.
const LIFESTEAL := &"lifesteal"

## Every id this module owns, in the vocabulary order ADR 0068 lists them. Every id a
## content item, a technique or a mechanism may author.
const ALL_IDS: Array[StringName] = [
	ACCURACY,
	ABSORPTION,
	AMPLIFICATION,
	REDUCTION,
	PENETRATION,
	PARRY_RATE,
	PARRY_BREAK,
	PARRY_STRENGTH,
	PARRY_SHRED,
	BLOCK_RATE,
	BLOCK_BREAK,
	BLOCK_STRENGTH,
	BLOCK_SHRED,
	REFLECT_RATE,
	REFLECT_DAMAGE,
	REFLECT_RESIST_RATE,
	REFLECT_RESIST_DAMAGE,
	SHIELD_CAPACITY,
	SHIELD_TOUGHNESS,
	SHIELD_PEN,
	SHIELD_REGEN,
	LIFESTEAL,
]

## The rate-shaped ids: the combat-owned mirror of `Stat.RATE_STATS`, and the set the
## ADR 0022 shape test walks. Every one has a `0.0` default and must be authored
## `op: FLAT` with `unit: "rate"` — a `PERCENT` modifier on any of them is a silent
## no-op, and `Stat.RATE_STATS` cannot catch it because these ids are not its members.
const RATE_IDS: Array[StringName] = [
	ACCURACY,
	ABSORPTION,
	PENETRATION,
	PARRY_RATE,
	PARRY_STRENGTH,
	BLOCK_RATE,
	BLOCK_STRENGTH,
	REFLECT_RATE,
	REFLECT_RESIST_RATE,
	LIFESTEAL,
]

## The defaults of the rate-shaped ids. Every entry is `0.0`, deliberately: an
## unstatted actor contests nothing, so a linear-from-zero rate reads 0% and never a
## sigmoid's unchosen 0.5 (ADR 0068). Nothing here is shipped balance — the values
## arrive as `StatModifier`s; this is only the neutral reading.
const RATE_DEFAULTS: Dictionary = {
	ACCURACY: 0.0,
	ABSORPTION: 0.0,
	PENETRATION: 0.0,
	PARRY_RATE: 0.0,
	PARRY_STRENGTH: 0.0,
	BLOCK_RATE: 0.0,
	BLOCK_STRENGTH: 0.0,
	REFLECT_RATE: 0.0,
	REFLECT_RESIST_RATE: 0.0,
	LIFESTEAL: 0.0,
}

## The defaults of every non-rate id. These are also neutral readings, not balance: a
## shield with no capacity absorbs nothing, a strength of 1.0 scales nothing.
const DEFAULTS: Dictionary = {
	REDUCTION: 0.0,
	AMPLIFICATION: 0.0,
	REFLECT_DAMAGE: 1.0,
	REFLECT_RESIST_DAMAGE: 1.0,
	PARRY_BREAK: 0.0,
	PARRY_SHRED: 0.0,
	BLOCK_BREAK: 0.0,
	BLOCK_SHRED: 0.0,
	SHIELD_CAPACITY: 0.0,
	SHIELD_TOUGHNESS: 1.0,
	SHIELD_PEN: 0.0,
	SHIELD_REGEN: 0.0,
}


## The neutral reading of `id`: its `RATE_DEFAULTS` entry if it is rate-shaped, its
## `DEFAULTS` entry otherwise, and `0.0` for anything this module does not own — so a
## caller can ask an id it has not heard of without branching.
static func default_of(id: StringName) -> float:
	if RATE_DEFAULTS.has(id):
		return float(RATE_DEFAULTS[id])
	return float(DEFAULTS.get(id, 0.0))


## Whether `id` is rate-shaped. Derived from the baselines, the way ADR 0022 says
## membership should be derived rather than restated by hand.
static func is_rate(id: StringName) -> bool:
	return RATE_DEFAULTS.has(id)


## A `StatModifier` of the only shape ADR 0068 permits for a rate id. The single place
## a rate modifier is constructed, so a new caller cannot reach for `Op.PERCENT` on an
## id that cannot take one — and so the shape test has something to assert about the
## items this module grants.
static func rate_modifier(id: StringName, value: float, source: StringName) -> StatModifier:
	return StatModifier.new(id, Stat.Op.FLAT, value, source)
