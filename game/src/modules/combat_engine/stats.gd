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

## ## ADR 0215. This is the OFFENCE HALF of the hit contest, and it is a MAGNITUDE
##
## It was documented as "reduces the defender's `EVASION` … contested by subtraction,
## never by multiplication (ADR 0068)", and `CombatSpine.landed_chance` computed
## `1 - (evasion - accuracy) / rate_scale`. That subtraction is the DEFECT ADR 0215
## exists to remove: an absolute difference of the same quantity, against a constant
## divisor, saturates as the ladder widens the gap. It is now
## `accuracy / (accuracy + evasion)` — see [method CombatSpine.landed_chance].
##
## The id string is UNCHANGED, because the id was never the defect and renaming it
## would have silently disowned every shipped `core_evasion`-style option that names it.
## `Stat.ACCURACY` in `contracts/stat.gd` is the same string and
## `tests/modules/combat_engine/test_rate_ratio_contest.gd` asserts they are one id
## rather than two vocabularies.
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
## ADR 0215: the CONTEST is now `PARRY_RATE / (PARRY_RATE + PARRY_BREAK)` — a ratio of
## two magnitudes. ADR 0068's `rate_scale` divisor on the `parry.rate` band is GONE, and
## so is its reason ("a sigmoid returns 0.5 at parity"): the ratio returns `p` and not
## `0.5`, because the ratio is `p` — `offense / (offense + defence)` IS the share, and at
## parity that share is `0.5` by definition rather than by an accident of a curve.
##
## Carved out of the TOP of the would-have-been-a-hit region, and `PARRY_BREAK` is the
## answer half — the ADR's yin-yang pair, which ADR 0068 read as "break side is the
## attacker's, raise side is the defender's" but which it could not USE, because it had
## no formula to put them in. This file is that formula.
const PARRY_RATE := &"parry.rate"
## Scales `PARRY_RATE` without changing its sign: at zero it reads zero, so a
## `strength`-only investment still parries 0% rather than a sigmoid's 0.5. ADR 0215 does
## not change this: a `strength` is an AMPLIFIER on the magnitude, not a second contest.
const PARRY_STRENGTH := &"parry.strength"
## What parrying costs the defender: `break` spends poise, `shred` spends the ability
## to parry again. ADR 0215 makes `PARRY_BREAK` the DEFENCE half of the parry contest
## (the `break` side is the attacker's to apply, the `raise` side is the defender's to
## invest in — the ownership rule is unchanged, the FORM is). `PARRY_SHRED` remains a
## defensive RESPONSE read by no contest, for `CombatSpine._parry`'s reason: breaking the
## parry costs the defender poise and re-reads, which has no business inside a band roll
## that must stay one comparison.
const PARRY_BREAK := &"parry.break"
const PARRY_SHRED := &"parry.shred"
## Block's twin of the four above. Same band, same contest, one vocabulary. ADR 0215:
## `BLOCK_RATE / (BLOCK_RATE + BLOCK_BREAK)`.
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

## ## ADR 0215. The CONTEST pairs, and why this is a derivation rather than a comment
##
## Every rate contest this module owns is `offense / (offense + defense)`, so each one
## names its two halves here and [method contest] is the single place the formula lives.
## A contest named only by its offence half is how `accuracy` came to be defined as a
## SUBTRACTION off `evasion` in the first place, so the pair is data.
##
## `PARRY_BREAK` and `BLOCK_BREAK` MOVE from `DEFAULTS` into `RATE_DEFAULTS` in this
## change, which is the mechanical consequence of ADR 0215 rather than a tidiness pass:
## they stopped being "what parrying costs the defender" and became a half of a contest,
## so they need a neutral reading of `0.0` that a caller can add to a derived stat the
## way every other contest half is read.
const CONTESTS: Dictionary = {
	ACCURACY: &"evasion",
	PARRY_RATE: PARRY_BREAK,
	BLOCK_RATE: BLOCK_BREAK,
}

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

## ## ADR 0215: what this list now means, and what stopped being true
##
## Membership used to be "a `[0, 1]` rate with a cap in its expression", which is why
## `ACCURACY` was here: it was defined as a subtraction off a capped evasion, so it
## behaved like a rate. It no longer is — it is an unbounded MAGNITUDE — so it leaves
## this list for the same reason `Stat.CRIT_CHANCE` left `Stat.RATE_STATS` at ADR 0200:
## a FLAT on a magnitude is an authored number, and refusing it would refuse good work.
##
## **`RATE_IDS` and `RATE_STATS` are different claims and the shape test is what keeps
## them apart.** `test_no_combat_rate_id_is_in_core_rate_stats` still holds: combat-owned
## ids are not core's members. What ADR 0215 changed is that combat's own claim is now
## "this id is a magnitude half of a contest", and every id in the list below is read
## through [method contest] or [method CombatBand.ratio].
const RATE_IDS: Array[StringName] = [
	ACCURACY,
	ABSORPTION,
	PENETRATION,
	PARRY_RATE,
	PARRY_BREAK,
	PARRY_STRENGTH,
	BLOCK_RATE,
	BLOCK_BREAK,
	BLOCK_STRENGTH,
	REFLECT_RATE,
	REFLECT_RESIST_RATE,
	LIFESTEAL,
]

## The defaults of the rate-shaped ids. Every entry is `0.0`, deliberately: an
## unstatted actor contests nothing, so a contest half reads 0 and the ratio answers
## `0.0` rather than a sigmoid's unchosen 0.5 (ADR 0068). Nothing here is shipped
## balance — the values arrive as `StatModifier`s; this is only the neutral reading.
const RATE_DEFAULTS: Dictionary = {
	ACCURACY: 0.0,
	ABSORPTION: 0.0,
	PENETRATION: 0.0,
	PARRY_RATE: 0.0,
	PARRY_BREAK: 0.0,
	PARRY_STRENGTH: 0.0,
	BLOCK_RATE: 0.0,
	BLOCK_BREAK: 0.0,
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
	PARRY_SHRED: 0.0,
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


## ADR 0215. `p = offense / (offense + defense)`, and the ONE place that shape is written
## inside this module.
##
## The four properties the ADR names are all consequences of the denominator rather than
## of any clamp, which is why there is nothing here to tune:
##
## - **It cannot saturate.** For every finite non-negative pair the result is strictly
##   inside `(0, 1)`, so a stronger attacker moves it toward `1.0` and never arrives.
## - **Doubling both halves changes nothing.** The ratio is homogeneous of degree zero,
##   so a contest means the same thing at R3 and at R30.
## - **At parity it is exactly `0.5`**, so a realm gap alone grants nothing.
## - **No scale constant exists to retune.** ADR 0068's `rate_scale` is not a dial here;
##   it is gone.
##
## ## Why `o + d == 0.0` reads `0.0` and is not a division by zero
##
## Two actors who have invested in neither half contest nothing, and `0.0` is the honest
## answer for a share: neither can land, so neither lands. The alternative — `INF` — is
## what a raw division returns, and it survives every `clampf`. `MindContest._finite`
## makes the same call for the same reason.
static func contest(offense: float, defense: float) -> float:
	var o := maxf(0.0, offense if is_finite(offense) else 0.0)
	var d := maxf(0.0, defense if is_finite(defense) else 0.0)
	var total := o + d
	if total <= 0.0:
		return 0.0
	return o / total


## The id `offense_id` is contested against, or `&""` when it is not half of a contest.
## Total on purpose: a caller asking about an id this module has never heard of gets an
## answer rather than an error, which is what lets [method contest_of] degrade to `0.0`.
static func counterpart_of(offense_id: StringName) -> StringName:
	return CONTESTS.get(offense_id, &"")


## [method contest] for two ACTORS rather than two numbers, so the contest halves are
## read the same way everywhere: `CombatStats.default_of` folded in, then `derived`,
## then the ratio. Never an absolute difference and never a difference against a scale.
##
## `null` on either side is `0.0`, so a half-built pair reads the neutral contest rather
## than crashing a hit that has already committed to mutating both of them.
static func contest_of(
	offense_id: StringName, offense: Actor, defense_id: StringName, defense: Actor
) -> float:
	if defense_id == &"":
		return 0.0
	return contest(
		default_of(offense_id) + derived_of(offense, offense_id),
		default_of(defense_id) + derived_of(defense, defense_id)
	)


## The derived value of `id` on `actor`, or `0.0` for a null actor. The same total read
## [method CombatBand.derived_of] performs, and duplicated rather than reached through it
## so this file stays a pure vocabulary with no dependency on the band roll.
static func derived_of(actor: Actor, id: StringName) -> float:
	if actor == null or actor.stats == null:
		return 0.0
	return actor.stats.derived(id)


## A `StatModifier` of the only shape ADR 0068 permits for a rate id. The single place
## a rate modifier is constructed, so a new caller cannot reach for `Op.PERCENT` on an
## id that cannot take one — and so the shape test has something to assert about the
## items this module grants.
static func rate_modifier(id: StringName, value: float, source: StringName) -> StatModifier:
	return StatModifier.new(id, Stat.Op.FLAT, value, source)
