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
## fractions (`crit_chance`, `evasion`) with multipliers where
## 1.0 means no change (`crit_damage`, `attack_speed`, `cultivation_rate`,
## `insight_gain`). One blanket "show rates as %" would report `crit_damage = 1.54`
## as 154%, which is a worse lie than a decimal. The label carries the unit instead.
const TABLE: Dictionary = {
	# --- base attributes -------------------------------------------------------
	&"physique": ["LOC_UI_PANELS_393BC0E140", 0],
	&"spirit": ["LOC_UI_PANELS_FE1E1FC935", 0],
	# ADR 0890: "Aptitude" names the twelve-point SOURCE layer now, so this stored
	# attribute reads as what it is — Talent.
	&"aptitude": ["LOC_UI_PANELS_AE362087AB", 0],
	&"comprehension": ["LOC_UI_PANELS_C7A91540E6", 0],
	&"agility": ["LOC_UI_PANELS_0FC9A6EDB3", 0],
	&"will": ["LOC_UI_PANELS_3E3E5802BD", 0],
	&"fortune": ["LOC_UI_PANELS_7517BDA593", 0],
	# --- resources -------------------------------------------------------------
	&"max_health": ["LOC_UI_PANELS_3DFBCDB809", 0],
	&"max_qi": ["LOC_UI_PANELS_6697E28CD8", 0],
	&"max_stamina": ["LOC_UI_PANELS_F2F5823524", 0],
	&"health_regen": ["LOC_UI_PANELS_B25C25E91A", 1],
	&"qi_regen": ["LOC_UI_PANELS_747CDA1BE1", 1],
	&"stamina_regen": ["LOC_UI_PANELS_707634C8FC", 1],
	# --- offence ---------------------------------------------------------------
	&"attack_physical": ["LOC_UI_PANELS_E2C3B5A7A1", 0],
	&"attack_spiritual": ["LOC_UI_PANELS_0398D277F2", 0],
	# Fraction. 0.05 must never print as 0.
	&"crit_chance": ["LOC_UI_PANELS_7586544DC7", 3],
	# ADR 0877 made `crit_damage` a `0.0`-baseline MAGNITUDE in rate-space rather than the
	# multiplier the old comment described, so the whole crit family prints at 3: one
	# point of comprehension is 0.004 and must not round to "0.00".
	&"crit_damage": ["LOC_UI_PANELS_1CA68A1AA1", 3],
	# ADR 0215: the DEFENCE halves of the crit contest, presented beside their offence
	# twins. `crit_resist` answers `crit_chance`, `crit_resist_damage` answers
	# `crit_damage`; one point of will is 0.003.
	&"crit_resist": ["LOC_UI_PANELS_3C4006D9A8", 3],
	&"crit_resist_damage": ["LOC_UI_PANELS_37183522D8", 3],
	&"penetration": ["LOC_UI_PANELS_D091C0C3C9", 1],
	# Multiplier: 1.0 means no change from base speed.
	&"attack_speed": ["LOC_UI_PANELS_0E3525A8D2", 2],
	# --- defence ---------------------------------------------------------------
	&"defense_physical": ["LOC_UI_PANELS_44D83A89D6", 0],
	&"defense_spiritual": ["LOC_UI_PANELS_BBD51128C0", 0],
	&"evasion": ["LOC_UI_PANELS_BCE8CF9905", 3],
	&"poise": ["LOC_UI_PANELS_2A8E07CC3B", 0],
	# ADR 0200: the will-derived MAGNITUDE the status gate actually reads (`will * 0.003`
	# through the mitigation ratio). The retired `status_resistance` spelling held this
	# seat until 2026-10-07; it is deliberately NOT declared here, because it resolves to
	# nothing on every actor and a label would print a stat nobody can move.
	&"status_defense": ["LOC_UI_PANELS_188A390D87", 3],
	&"damage_reduction": ["LOC_UI_PANELS_1E294FA339", 3],
	# --- pace and cost ---------------------------------------------------------
	&"move_speed": ["LOC_UI_PANELS_411D2E1AE0", 0],
	# Multiplier: 1.0 is the uninvested reading, not zero.
	&"cultivation_rate": ["LOC_UI_PANELS_387008023B", 2],
	&"qi_absorption": ["LOC_UI_PANELS_9257538930", 1],
	&"loot_bonus": ["LOC_UI_PANELS_9C8E614F1E", 3],
	&"cooldown_reduction": ["LOC_UI_PANELS_0128E84B58", 3],
	&"qi_cost_reduction": ["LOC_UI_PANELS_BB5F7BC336", 3],
	# Fraction, and the one the player acts on: 0.2 printed as "0" told a hero his
	# breakthrough was free.
	&"breakthrough_chance": ["LOC_UI_PANELS_B4A20AD258", 3],
	# --- cultivation -----------------------------------------------------------
	&"dao_heart": ["LOC_UI_PANELS_399F9C8C8D", 0],
	# Multiplier.
	&"insight_gain": ["LOC_UI_PANELS_467E6901F7", 2],
	# --- body path -------------------------------------------------------------
	&"bone_density": ["LOC_UI_PANELS_86D9C2A21A", 1],
	&"muscle_fiber": ["LOC_UI_PANELS_38D4D0B298", 1],
	&"organ_vitality": ["LOC_UI_PANELS_3B9662A9C6", 1],
	&"carry_capacity": ["LOC_UI_PANELS_1D9FA56700", 0],
	&"body_cultivation_power": ["LOC_UI_PANELS_C06C5596E2", 2],
	&"regeneration": ["LOC_UI_PANELS_506EB98F49", 2],
	&"acupoint_quality": ["LOC_UI_PANELS_3259BBD1B6", 2],
	&"acupoint_count": ["LOC_UI_PANELS_909E25C44F", 0],
	&"acupoint_blocked_count": ["LOC_UI_PANELS_A2C37943F9", 0],
	&"body_integrity": ["LOC_UI_PANELS_EAF394ACEB", 0],
	# --- qi path ---------------------------------------------------------------
	&"qi_affinity": ["LOC_UI_PANELS_4F6D9B5525", 1],
	&"qi_control": ["LOC_UI_PANELS_D602C2046A", 1],
	&"dantian_capacity": ["LOC_UI_PANELS_1C24900750", 1],
	&"dantian_quality": ["LOC_UI_PANELS_C3339E79E8", 2],
	&"dantian_full": ["LOC_UI_PANELS_9F8E3CF309", 0],
	&"qi_regen_rate": ["LOC_UI_PANELS_DCC7372830", 2],
	&"technique_cost_reduction": ["LOC_UI_PANELS_4057A64E8E", 3],
	&"technique_power": ["LOC_UI_PANELS_8A33D527FD", 1],
	&"flight_speed": ["LOC_UI_PANELS_182CD42AD4", 0],
	&"qi_sense_range": ["LOC_UI_PANELS_41F2957D22", 1],
	# --- mind path -------------------------------------------------------------
	&"perception": ["LOC_UI_PANELS_C0FFA17BF7", 1],
	&"mental_attack": ["LOC_UI_PANELS_91A58DCF15", 0],
	&"mental_defense": ["LOC_UI_PANELS_247E2ECD4F", 0],
	&"spiritual_sense_range": ["LOC_UI_PANELS_EEA2CF6C88", 1],
	# Renamed by ADR 0215 (the stats were `mind_focus_chance`/`mind_avoidance`). The
	# labels move with the ids on purpose: a stat called "Critical chance" that is read
	# ONLY by the mind mechanism would tell a player their qi crits are 0.05 higher,
	# which is exactly the misreading this table exists to prevent.
	&"mind_clarity": ["LOC_UI_PANELS_03543111F1", 3],
	&"mind_veil": ["LOC_UI_PANELS_3A35139C55", 3],
	&"illusion_resistance": ["LOC_UI_PANELS_1FB0579D9B", 3],
	&"mind_technique_power": ["LOC_UI_PANELS_F0FD2903EE", 1],
	&"comprehension_bonus": ["LOC_UI_PANELS_537EFBD1A9", 2],
	&"sea_capacity": ["LOC_UI_PANELS_9210A7E16F", 1],
	&"sea_clarity": ["LOC_UI_PANELS_D65FD55F90", 2],
	&"sea_turbulence": ["LOC_UI_PANELS_BBDEC08181", 3],
	&"sea_full": ["LOC_UI_PANELS_0046E0D362", 0],
	&"mind_power": ["LOC_UI_PANELS_D836128935", 0],
	&"awareness": ["LOC_UI_PANELS_2D35FD0096", 0],
	# The mind status contest (MindVocabulary): every control shape and expression channel
	# has an OFFENCE half (`mind_status_mastery_*`) and a DEFENCE half
	# (`mind_composure_*`). Rate-shaped, so 3 decimals like every other contest half.
	&"mind_status_mastery_slow": ["LOC_UI_PANELS_E7131AE58C", 3],
	&"mind_status_mastery_cost": ["LOC_UI_PANELS_F8CA96926E", 3],
	&"mind_status_mastery_falsify": ["LOC_UI_PANELS_E3B88CE0DF", 3],
	&"mind_status_mastery_invert": ["LOC_UI_PANELS_6EA72C0AEC", 3],
	&"mind_status_mastery_voice": ["LOC_UI_PANELS_61C1A4942D", 3],
	&"mind_status_mastery_intent": ["LOC_UI_PANELS_B86D7FC2A7", 3],
	&"mind_composure_slow": ["LOC_UI_PANELS_3740698F7E", 3],
	&"mind_composure_cost": ["LOC_UI_PANELS_C210B4D4C1", 3],
	&"mind_composure_falsify": ["LOC_UI_PANELS_BABB7B6275", 3],
	&"mind_composure_invert": ["LOC_UI_PANELS_DFA0FF8D1E", 3],
	&"mind_composure_voice": ["LOC_UI_PANELS_3D8B2BBAA0", 3],
	&"mind_composure_intent": ["LOC_UI_PANELS_AFBEE82DD0", 3],
	# --- combat-owned rates ----------------------------------------------------
	# These reach the sheet through the same "a modifier with no baseline is backed
	# at 0.0" path `actor_stats.gd` documents, so they are listed here to be read
	# rather than to be registered (ADR 0022/0068: never add them to `RATE_STATS`).
	&"accuracy": ["LOC_UI_PANELS_12A3A4F498", 3],
	&"absorption": ["LOC_UI_PANELS_C5D50E840F", 3],
	&"parry.rate": ["LOC_UI_PANELS_60FBC06B56", 3],
	&"parry.strength": ["LOC_UI_PANELS_02886A6AC8", 3],
	&"block.rate": ["LOC_UI_PANELS_BD135A3F40", 3],
	&"block.strength": ["LOC_UI_PANELS_080DC2FA3C", 3],
	&"reflect.rate": ["LOC_UI_PANELS_103DF54D3A", 3],
	&"reflect.resist.rate": ["LOC_UI_PANELS_E6815FB07A", 3],
	&"lifesteal.health": ["LOC_UI_PANELS_F61805F6A5", 3],
	&"leech_resist.health": ["LOC_UI_PANELS_502C72F67F", 3],
	&"lifesteal.qi": ["LOC_UI_PANELS_809FC486FA", 3],
	&"leech_resist.qi": ["LOC_UI_PANELS_0E2FE64187", 3],
	&"lifesteal.stamina": ["LOC_UI_PANELS_C4562AA0C0", 3],
	&"leech_resist.stamina": ["LOC_UI_PANELS_FCD8CC0CAB", 3],
	# --- the twelve aptitudes (ADR 0881/0890) ----------------------------------
	# The SOURCE layer's ids. `agility` is ALREADY declared above: it is the one id the
	# stored attribute and the roster deliberately share (`core/aptitude.gd`). Its entry
	# keeps the attribute's precision 0 while the sheet prints an aptitude point EXACT,
	# because a point can be fractional and the attribute cannot.
	&"might": ["LOC_UI_PANELS_9DA77C5E49", EXACT],
	&"fortitude": ["LOC_UI_PANELS_FD78CEDEE2", EXACT],
	&"vigor": ["LOC_UI_PANELS_F3BCD176B1", EXACT],
	&"onslaught": ["LOC_UI_PANELS_0CDBF51EA7", EXACT],
	&"composure": ["LOC_UI_PANELS_56EA925EF3", EXACT],
	&"pierce": ["LOC_UI_PANELS_1B02FC48CB", EXACT],
	&"focus": ["LOC_UI_PANELS_FE7F55B8BF", EXACT],
	&"bulwark": ["LOC_UI_PANELS_0D4FC55958", EXACT],
	&"retribution": ["LOC_UI_PANELS_8366443A86", EXACT],
	&"precision": ["LOC_UI_PANELS_3DD4DB5CE7", EXACT],
	&"ferocity": ["LOC_UI_PANELS_D8B36CAB95", EXACT],
}


## The label a player reads. An unlisted id falls back to the id itself: never a
## blank row (which reads as a stat the hero does not have) and never a silent
## substitution. The table holds the KEY, so this is the single place that resolves it.
static func label_for(id: StringName) -> String:
	var entry: Array = TABLE.get(id, [])
	if entry.is_empty():
		return String(id)
	return L.t(String(entry[0]))


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
