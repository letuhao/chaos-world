class_name StatPresenter
extends RefCounted

## How a stat id is put in front of a player: its label and its precision.
##
## ## Why this table exists
##
## `ActorStats.derived_all()` is open — `core` writes its own ids, each module's
## provider writes its own through `StatProvider.contribute`, and any stat carrying
## a modifier but no baseline is still backed at `0.0` so the ADR 0022 trap survives.
## The character sheet iterates that whole map, so *any* id can reach a player. Two
## things must then be true for each one, or the sheet is not observability:
##
## - it carries a label a player reads, not `qi_cost_reduction`;
## - the figure printed is the figure held. `StatRow` used to default to zero
##   decimals, so `acupoint_quality = 0.5` printed as `1` and
##   `breakthrough_chance = 0.2` printed as `0` — a rate shown as no rate at all.
##   A figure that is *wrong* is worse than one that is missing: the player cannot
##   tell it is wrong.
##
## ## The three options, and why this one
##
## 1. **Infer the decimals from the value.** Rejected. It makes the precision a
##    function of the build, so a stat's printed width changes as the hero levels
##    (`crit_chance` 0.05 at R1, 0.0525 at R20) and the number the player remembers
##    silently morphs. It also cannot distinguish a count that happens to be whole
##    from a rate that happens to be whole.
## 2. **Declare precision at each call site.** That is the trap that shipped the
##    defect: the call site is a *screen*, there are several, and an omission is
##    silent. A default that lies is the worst kind of default.
## 3. **Declare it per stat id, once, here.** Chosen. Precision becomes a property
##    of the stat rather than of the screen that happens to show it, so two screens
##    cannot disagree and a new screen cannot get it wrong by forgetting.
##
## ## `EXACT` is the honest failure
##
## An id missing from the table gets `EXACT`, which prints the float verbatim
## rather than rounding. So an unlisted stat is *ugly*, never *wrong*, and
## `StatPresenter.is_known` plus `tests/ui/test_stat_presenter.gd` turn the omission
## into a red test instead of a quiet lie. Correctness outranks tidiness here
## because the two are not comparable: a player who misreads their own crit chance
## makes every later decision from a bad premise.
##
## Ids are string literals, never `Stat.X` / `BodyStats.X`. `ui/` may not name a
## module's class, and naming `contracts`' `Stat` here would still have to be
## extended by hand every time a module invents an id — the triplication ADR 0066
## exists to prevent. The literals are reconciled against the live stat surface by
## a test, so the duplication has a checker instead of a convention.

## Decimal sentinel: print the float as held, never round it.
const EXACT := -1

## id -> [label, decimals]. `decimals` is a count, or `EXACT`.
## Rates are NOT converted to percentages, deliberately: `Stat.RATE_STATS` mixes
## fractions (`crit_chance`, `evasion`, `status_resistance`) with multipliers where
## 1.0 means no change (`crit_damage`, `attack_speed`, `cultivation_rate`,
## `insight_gain`). One blanket "show rates as %" would report `crit_damage = 1.54`
## as 154%, which is a worse lie than a decimal. The label carries the unit instead.
const TABLE: Dictionary = {
	# --- base attributes -------------------------------------------------------
	&"physique": ["Physique", 0],
	&"spirit": ["Spirit", 0],
	&"aptitude": ["Aptitude", 0],
	&"comprehension": ["Comprehension", 0],
	&"agility": ["Agility", 0],
	&"will": ["Will", 0],
	&"fortune": ["Fortune", 0],
	# --- resources -------------------------------------------------------------
	&"max_health": ["Max health", 0],
	&"max_qi": ["Max qi", 0],
	&"max_stamina": ["Max stamina", 0],
	&"health_regen": ["Health regen", 1],
	&"qi_regen": ["Qi regen", 1],
	&"stamina_regen": ["Stamina regen", 1],
	# --- offence ---------------------------------------------------------------
	&"attack_physical": ["Physical attack", 0],
	&"attack_spiritual": ["Spiritual attack", 0],
	# Fraction. 0.05 must never print as 0.
	&"crit_chance": ["Crit chance", 3],
	# Multiplier, not a fraction: 1.54 means x1.54.
	&"crit_damage": ["Crit damage", 2],
	&"penetration": ["Penetration", 1],
	# Multiplier: 1.0 means no change from base speed.
	&"attack_speed": ["Attack speed", 2],
	# --- defence ---------------------------------------------------------------
	&"defense_physical": ["Physical defence", 0],
	&"defense_spiritual": ["Spiritual defence", 0],
	&"evasion": ["Evasion", 3],
	&"poise": ["Poise", 0],
	&"status_resistance": ["Status resistance", 3],
	&"damage_reduction": ["Damage reduction", 3],
	# --- pace and cost ---------------------------------------------------------
	&"move_speed": ["Move speed", 0],
	# Multiplier: 1.0 is the uninvested reading, not zero.
	&"cultivation_rate": ["Cultivation rate", 2],
	&"qi_absorption": ["Qi absorption", 1],
	&"loot_bonus": ["Loot bonus", 3],
	&"cooldown_reduction": ["Cooldown reduction", 3],
	&"qi_cost_reduction": ["Qi cost reduction", 3],
	# Fraction, and the one the player acts on: 0.2 printed as "0" told a hero his
	# breakthrough was free.
	&"breakthrough_chance": ["Breakthrough chance", 3],
	# --- cultivation -----------------------------------------------------------
	&"dao_heart": ["Dao heart", 0],
	# Multiplier.
	&"insight_gain": ["Insight gain", 2],
	# --- body path -------------------------------------------------------------
	&"bone_density": ["Bone density", 1],
	&"muscle_fiber": ["Muscle fibre", 1],
	&"organ_vitality": ["Organ vitality", 1],
	&"carry_capacity": ["Carrying capacity", 0],
	&"body_cultivation_power": ["Cultivation power", 2],
	&"regeneration": ["Regeneration", 2],
	&"acupoint_quality": ["Huyệt quality", 2],
	&"acupoint_count": ["Open huyệt", 0],
	&"acupoint_blocked_count": ["Jammed huyệt", 0],
	&"body_integrity": ["Body integrity", 0],
	# --- qi path ---------------------------------------------------------------
	&"qi_affinity": ["Qi affinity", 1],
	&"qi_control": ["Qi control", 1],
	&"dantian_capacity": ["Dantian capacity", 1],
	&"dantian_quality": ["Dantian quality", 2],
	&"dantian_full": ["Dantian full", 0],
	&"qi_regen_rate": ["Qi regen rate", 2],
	&"technique_cost_reduction": ["Technique cost reduction", 3],
	&"technique_power": ["Technique power", 1],
	&"flight_speed": ["Flight speed", 0],
	&"qi_sense_range": ["Qi sense range", 1],
	# --- mind path -------------------------------------------------------------
	&"perception": ["Perception", 1],
	&"mental_clarity": ["Mental clarity", 1],
	&"mental_attack": ["Mental attack", 0],
	&"mental_defense": ["Mental defence", 0],
	&"spiritual_sense_range": ["Spiritual sense range", 1],
	# Renamed by ADR 0071 / BL-0114. The labels move with the ids on purpose: a stat
	# called "Critical chance" that is read ONLY by the mind mechanism would tell a player
	# their qi crits are 0.05 higher, which is exactly the misreading this table exists
	# to prevent (see its module docblock).
	&"mind_focus_chance": ["Mind focus chance", 3],
	&"mind_avoidance": ["Mind avoidance", 3],
	&"illusion_resistance": ["Illusion resistance", 3],
	&"mind_technique_power": ["Mind technique power", 1],
	&"comprehension_bonus": ["Comprehension bonus", 2],
	&"sea_capacity": ["Sea capacity", 1],
	&"sea_clarity": ["Sea clarity", 2],
	&"sea_turbulence": ["Sea turbulence", 3],
	&"sea_full": ["Sea full", 0],
	&"mind_power": ["Mind power", 0],
	&"awareness": ["Awareness", 0],
	# --- combat-owned rates ----------------------------------------------------
	# These reach the sheet through the same "a modifier with no baseline is backed
	# at 0.0" path `actor_stats.gd` documents, so they are listed here to be read
	# rather than to be registered (ADR 0022/0068: never add them to `RATE_STATS`).
	&"accuracy": ["Accuracy", 3],
	&"absorption": ["Absorption", 3],
	&"parry.rate": ["Parry rate", 3],
	&"parry.strength": ["Parry strength", 3],
	&"block.rate": ["Block rate", 3],
	&"block.strength": ["Block strength", 3],
	&"reflect.rate": ["Reflect rate", 3],
	&"reflect.resist.rate": ["Reflect resist rate", 3],
	&"lifesteal": ["Lifesteal", 3],
}


## The label a player reads. An unlisted id falls back to the id itself: never a
## blank row (which reads as a stat the hero does not have) and never a silent
## substitution.
static func label_for(id: StringName) -> String:
	var entry: Array = TABLE.get(id, [])
	if entry.is_empty():
		return String(id)
	return String(entry[0])


## How many decimal places this id is printed at, or `EXACT` when the id is not in
## the table. `EXACT` is the honest reading of "nobody declared this".
static func decimals_for(id: StringName) -> int:
	var entry: Array = TABLE.get(id, [])
	if entry.is_empty():
		return EXACT
	return int(entry[1])


## Whether this id has a declared label and precision.
static func is_known(id: StringName) -> bool:
	return TABLE.has(id)


## Every declared id, sorted, so a test can diff the table against the live stat
## surface without depending on dictionary ordering.
static func known_ids() -> Array:
	var out: Array = TABLE.keys()
	out.sort()
	return out
