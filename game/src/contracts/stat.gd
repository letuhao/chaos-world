class_name Stat
extends RefCounted

## Canonical stat ids. Modules may define their own StringName ids.

enum Op { FLAT, PERCENT, MULT }

# Base attributes — the only stored truth.
const PHYSIQUE := &"physique"
const SPIRIT := &"spirit"
const APTITUDE := &"aptitude"
const COMPREHENSION := &"comprehension"
const AGILITY := &"agility"
const WILL := &"will"
const FORTUNE := &"fortune"

const BASE_ATTRIBUTES := [
	PHYSIQUE,
	SPIRIT,
	APTITUDE,
	COMPREHENSION,
	AGILITY,
	WILL,
	FORTUNE,
]

# Derived stats — recomputed, never stored as truth.
const MAX_HEALTH := &"max_health"
const MAX_QI := &"max_qi"
const MAX_STAMINA := &"max_stamina"
const HEALTH_REGEN := &"health_regen"
const QI_REGEN := &"qi_regen"
const STAMINA_REGEN := &"stamina_regen"
const ATTACK_PHYSICAL := &"attack_physical"
const ATTACK_SPIRITUAL := &"attack_spiritual"
const CRIT_CHANCE := &"crit_chance"
const CRIT_DAMAGE := &"crit_damage"
const PENETRATION := &"penetration"
const ATTACK_SPEED := &"attack_speed"
const DEFENSE_PHYSICAL := &"defense_physical"
const DEFENSE_SPIRITUAL := &"defense_spiritual"
const EVASION := &"evasion"
const DAMAGE_REDUCTION := &"damage_reduction"
const POISE := &"poise"
## ADR 0200: `status_resistance` was a PERCENT capped at `0.8` and renamed to this
## MAGNITUDE, because mitigation is now derived from a pair of magnitudes and the percent
## is an output that may never be authored. The gate it needs is
## `will * 0.003 * (1 + ...)` over `(offender_power - defender_defense)` with the output
## bounded — an authored input that must grow, which is the whole distinction the ADR
## turns on. It is on `RealmScaling.SCALED_STATS`, so it climbs with the ladder instead of
## being authored flat against it.
##
## ## The id STRING changed and that is the load-bearing part
##
## `&"status_defense"` is a different id from `&"status_resistance"`, so a FLAT authored on
## the old string now lands on nothing. That is a deliberate, visible migration cost and not
## a silent one: `tools arch` / `tools deferred validate` both fail on an authored stat id
## no code declares, and `tests/modules/status` pins the refusal surface. Content that
## wants a flat mitigation budget says `core_status_defense` now.
const STATUS_DEFENSE := &"status_defense"
## Retired by ADR 0200 in favour of [constant STATUS_DEFENSE]. Declared so a reference to
## the old id fails to COMPILE with a name rather than silently reading `0.0` off an
## unbacked stat -- the exact shape `test_combat_stats_shape.gd` exists to catch. Do not
## add a read site for it; that is how a second vocabulary starts.
const STATUS_RESISTANCE := &"status_resistance"
const MOVE_SPEED := &"move_speed"
const CULTIVATION_RATE := &"cultivation_rate"
const QI_ABSORPTION := &"qi_absorption"
const BREAKTHROUGH_CHANCE := &"breakthrough_chance"
const DAO_HEART := &"dao_heart"
const INSIGHT_GAIN := &"insight_gain"
const LOOT_BONUS := &"loot_bonus"
const COOLDOWN_REDUCTION := &"cooldown_reduction"
const QI_COST_REDUCTION := &"qi_cost_reduction"

## ## Rate ids a MODULE owns, declared here so the content gates can resolve them
##
## These strings are the modules', not core's. They are restated in this file for one
## reason: `RATE_STATS` below is the ONLY membership list both content gates read —
## `status/status_def.gd:372` (a `StatusDef` FLAT) and `tools/data.py:2085`
## (`_resolve_rate_stats`, a fate FLAT). A module cannot add its own ids to another
## module's constant, and a per-module mirror like `CombatStats.RATE_IDS` reaches
## neither gate: it is a shape test's subject, not an enforcement point. So a
## module-owned rate had no way to be registered at all, which is BL-0675 — ADR 0071
## renamed `critical_chance`/`dodge_chance` into `mind_focus_chance`/`mind_avoidance`
## and the registration had nowhere to follow.
##
## Declaring the const here as well as in the module gives `tools/data.py` a name to
## resolve against this file, which is all it needs to know. It is a SECOND SPELLING
## SITE, so it is checked rather than trusted:
## `tests/contracts/test_rate_stats_registration.gd` asserts each of these equals the
## owning module's const and fails naming the id if a rename moves one without the
## other.
##
## ## Membership is a claim about SHAPE, never about ownership
##
## Nothing here gives core a dial on any of these ids, and none of them is core's.
## The two properties are different questions, and two guards used to conflate them by
## inferring ownership FROM the `RATE_STATS` list below
## (`tests/modules/mind_cultivation/test_mind_renamed_stat_ids.gd`,
## `test_mind_stat_surface.gd`); they now probe a real `ActorStats` instead, the way
## `test_combat_stats_shape.gd:116` already had to.
const CONCEPTION_CHANCE := &"conception_chance"
const DUAL_CULTIVATION_RATE := &"dual_cultivation_rate"
const GESTATION_SPEED := &"gestation_speed"
const ILLUSION_RESISTANCE := &"illusion_resistance"
const MATERNAL_RESILIENCE := &"maternal_resilience"
const MIND_AVOIDANCE := &"mind_avoidance"
const MIND_FOCUS_CHANCE := &"mind_focus_chance"
const TECHNIQUE_COST_REDUCTION := &"technique_cost_reduction"
const TECHNIQUE_POWER := &"technique_power"

## The MIND-CONTROL vocabulary's eight contest stats, as the `SPELLING` rather than
## eight registrations.
##
## `MindVocabulary` (same directory) builds every one of them from a prefix and a
## suffix — an OFFENCE half `mind_status_mastery_<suffix>` and a DEFENCE half
## `mind_composure_<suffix>` over the four control shapes and the two expression
## channels. They are rate-shaped for the shape reason the nine above are: every one
## is `minf(CAP, attribute * step)` with `CAP` under `1.0`, published by
## `mind_cultivation/mind_mastery_provider.gd`.
##
## ## Why they are restated here rather than generated, and what keeps them honest
##
## The list must stay ONE flat literal for the reason the note on [constant RATE_STATS]
## gives (`tools/data.py:2085` extracts it with `\[(.*?)\]`, which stops at the first
## `]`), so a concatenation would hide every entry after the break from the fate gate.
## But eight hand-written ids is a hand-written list, and this file's own docblock
## records that hand-lists are how BL-0675 happened.
##
## So `tests/modules/mind_cultivation/test_mind_mastery_streams.gd` derives the
## expected set from [class MindVocabulary] — `SHAPES + CHANNELS` crossed with the two
## prefixes — and asserts this list EQUALS it. A shape or a channel added without a
## registration fails there, naming the id; a registration left behind by a rename
## fails there too. The literal is what the gates read; the derivation is what keeps
## it true.
##
## **The twelve ids are SPELLED, not generated.** `MindVocabulary.offence_id(&"slow")`
## reads as the obvious thing to write here and it cannot be: a `static func` call is
## not a constant expression in GDScript, so `const X := [MindVocabulary.offence_id(...)]`
## fails to parse and takes `actor.gd` and every dependent with it. The same reason
## the ladder below indexes `MIND_CONTROL_RATES[n]` rather than spreading it — both
## spellings are dictated by what a `const` accepts, and the derivation test above is
## what makes the spelling safe to hand-maintain.
const MIND_CONTROL_RATES := [
	&"mind_status_mastery_slow",
	&"mind_status_mastery_cost",
	&"mind_status_mastery_falsify",
	&"mind_status_mastery_invert",
	&"mind_status_mastery_voice",
	&"mind_status_mastery_intent",
	&"mind_composure_slow",
	&"mind_composure_cost",
	&"mind_composure_falsify",
	&"mind_composure_invert",
	&"mind_composure_voice",
	&"mind_composure_intent",
]

## ## Why each one above is rate-shaped, and which three are deliberately NOT
##
## The test for membership is the BASELINE, never the `unit:` an option declares:
## `tools/options.py:597` trusts that field, and it is wrong on 13 shipped options.
## Shape proof, one line each — a cap under `1.0`, or a `1.0 +`/`1.0 *` term that
## makes `1.0` mean no change:
##   conception_chance        fertility/provider.gd:18    clampf(0.05 + fertility*0.02, 0.0, 0.95)
##   dual_cultivation_rate    dual_cultivation/provider.gd:31
##     (1.0 + aptitude * 0.02) * (1.0 - deviation * 0.5)
##   gestation_speed          fertility/provider.gd:19    1.0 + (physique+spirit+aptitude)*0.01
##   illusion_resistance      mind_cultivation/provider.gd:63 minf(0.8, clarity*0.004 + will*0.002)
##   maternal_resilience      fertility/provider.gd:23    clampf((physique+will)*0.01, 0.0, 0.8)
##   mind_avoidance           mind_cultivation/provider.gd:62 minf(0.6, perception*0.002 + aw*0.05)
##   mind_focus_chance        mind_cultivation/provider.gd:61
##     minf(0.75, 0.05 + perception * 0.003 + awareness_ratio * 0.1)
##   technique_cost_reduction qi_cultivation/provider.gd:31 clampf(qi_control*0.002, 0.0, 0.5)
##   technique_power          qi_cultivation/provider.gd:32 (1.0 + qi_affinity*0.05) * factor
##
## Each of the nine is also AUTHORABLE — an option or a fate names it as a modifier
## target — which is what makes an unregistered one a defect rather than a tidiness
## gap: that is the whole reachability argument, and the registration test asserts it
## rather than trusting this paragraph.
##
## The two that declare `unit: "rate"` and are still magnitudes, so a FLAT on them
## is LEGAL content and registering them would refuse good work:
##   move_speed            core/actor_stats.gd:163   100.0 + agility * 2.0
##   penetration           core/actor_stats.gd:156   spirit * 0.5
## `element_defense_<e>` (elements/provider.gd:67, `maxf(0.0, affinity * 0.5 + will *
## 0.2)`) used to be the third such id and no longer is: ADR 0200 replaces the capped
## percent `element_resistance_<e>` with an unbounded MAGNITUDE, so its ten options now
## declare `op: FLAT` / `unit: magnitude` and a FLAT on them is what the content means.
## `loot_bonus` (core/actor_stats.gd:169, `fortune * 0.01`) is 0..4 bonus points clamped
## by `LootBonus.MAX_INPUT`, so `+0.5` there is an authored number rather than 50%.

## Stats whose baseline is a fraction (0..1) or a multiplier (1.0 == no change).
## The module-owned ids at the top of this file are members too, on the shape test
## proved there; everything below this line is core's and is derived in
## core/actor_stats.gd from these scales:
##   crit_damage 1.5, attack_speed 1.0 (cap 2.5), cultivation_rate 1.0,
##   insight_gain 1.0, breakthrough_chance 0.1,
##   cooldown_reduction (cap 0.4), qi_cost_reduction (cap 0.5), damage_reduction 0.0.
## ADR 0200 deleted `crit_chance`'s `0.75`, `evasion`'s `0.6` and `status_resistance`'s
## `0.8`, so none of the three is a member any more and all three are MAGNITUDES. The three
## that kept their caps are a RATE axis, which is the ADR's own test: a cap on a mitigation
## or defense axis dies because that axis must scale, a cap on a rate axis stays.
## A FLAT modifier on any of the remaining ids is a content error: `+10` means 1000%, not
## +10. PERCENT is always valid on any stat; only FLAT on a rate stat is wrong.
## Membership requires a baseline that is not identically zero: actor_stats.gd
## resolves a stat as `(base + flat) * (1 + percent)`, so PERCENT on an
## always-zero baseline is a no-op. Two baseline shapes qualify:
##   constant term     - crit_damage/attack_speed/cultivation_rate/
##                       insight_gain/breakthrough_chance are non-zero always.
##   attribute-gated   - cooldown_reduction/qi_cost_reduction are gated on an
##                       attribute, but the gate is OUT OF REACH: see the note below.
## `damage_reduction` has baseline 0.0 and is deliberately absent (ADR 0022).
##
## ## Why the two remaining gated ids are listed as NON-ZERO here and refused anyway
##
## `cooldown_reduction` and `qi_cost_reduction` DO have an attribute-gated baseline — but
## the gate sits one to two orders of magnitude past the top of the AUTHORED attribute
## range, so the baseline contributes a small positive number and never the cap.
## **MEASURED 2026-10-04 (DEF-0262), through a real `ActorStats` and the real
## `StatusApply.apply_chance`, off `combat_damage.tres`:**
##
## | actor | `will` | `status_resistance` (now `status_defense`) | apply chance at gate 1.0 |
## | --- | --- | --- | --- |
## | a shipped race's own grant | 2.0 | 0.006 | 0.994 |
## | plus the best 5 equipment slots | 2.0 | 0.156 | 0.844 |
## | the largest authored `base_will` | 54.9 | 0.1647 | 0.8353 |
##
## That table is the whole argument ADR 0200 makes about `status_resistance` in one place:
## `base_will` is authored over **3.0..52.9** across 199 items, so the `0.8` cap needed
## `will >= 250` and was simply not reachable from authored content. The stat was a small
## defensive edge a build *tilts* rather than a wall it reaches, which was read as "the
## stat working as intended" and is in fact the defect: a mitigation axis authored flat
## against a 551x ladder. The coefficient is unchanged (`will * 0.003`) and the value at
## a race's own `will == 2.0` is still `0.006` at R1; what is gone is the cap, and
## `status_defense` is now on `RealmScaling.SCALED_STATS` so it climbs with the ladder.
##
## **So this is NOT the ADR 0022 defect the older revision of this comment described.** That
## comment claimed these ids read `0.0` and that PERCENT was "meaningful in normal
## play"; both halves were wrong — a PERCENT here multiplies a small NON-ZERO number and
## so does something, just very little.
##
## `ZERO_BASELINE_STATS` therefore refuses PERCENT on these ids for a DIFFERENT and
## correct reason: it is one authoring convention for all five, and `damage_reduction`
## is the one whose baseline really is the constant `0.0`. See the block above for the
## per-stat gate arithmetic.
##
## So the STRICTER rule is the one that is right, and it is the one
## `StatusDef.ZERO_BASELINE_STATS` enforces: a PERCENT on any of these five ids is a
## refused `.tres`, not a silent no-op (`tests/modules/status/test_status_refusals.gd`).
## An earlier version of this comment said PERCENT was "fine in normal play" on the
## attribute-gated four — that was the contracts layer telling designers a modifier
## works when it moves almost nothing. Membership below is unchanged (`RATE_STATS` is a
## claim about FLAT); the sentence above is a claim about PERCENT, and the two are
## different questions.
##
## ## ADR 0200 removed three entries, and the removals are the interesting part
##
## `CRIT_CHANCE`, `EVASION` and `STATUS_RESISTANCE` are GONE from this list because their
## `minf(cap, attribute * k)` caps are gone: `0.05 + fortune*0.002 + agility*0.0005`,
## `agility * 0.0015`, and `will * 0.003` are all unbounded MAGNITUDES now. `+10` on any of
## them is an authored number, not 1000%, so a FLAT is legal content and refusing it would
## be refusing good work.
##
## `tests/contracts/test_rate_stats_registration.gd` DERIVES membership from the published
## baseline rather than trusting this list, so the three had to leave on their own: the
## scanner classifies `minf(...)`/`clampf(...)` carrying a literal at or under `1.0` as
## rate-shaped, and with the `minf` gone none of the three is any more. That test is the
## gate ADR 0200 names for this list and it is updated in the same change.
##
## ## What STAYS, and the rule that decides it
##
## `ATTACK_SPEED` (2.5), `COOLDOWN_REDUCTION` (0.4) and `QI_COST_REDUCTION` (0.5) keep
## their caps and therefore keep their entries: a cap on a mitigation or defense axis dies
## because that axis must scale with the ladder, and a cap on a RATE axis stays because
## rate is not what power creep rides. An unbounded attack speed is a broken game, not a
## balance problem.
##
## The list is ONE flat literal on purpose: `tools/data.py:2085` extracts it with
## `\[(.*?)\]`, which stops at the first `]`, so concatenating two arrays here would
## silently hide every entry after the break from the fate gate.
const RATE_STATS := [
	ATTACK_SPEED,
	BREAKTHROUGH_CHANCE,
	COOLDOWN_REDUCTION,
	CONCEPTION_CHANCE,
	CRIT_DAMAGE,
	CULTIVATION_RATE,
	DUAL_CULTIVATION_RATE,
	GESTATION_SPEED,
	ILLUSION_RESISTANCE,
	INSIGHT_GAIN,
	MATERNAL_RESILIENCE,
	MIND_AVOIDANCE,
	MIND_FOCUS_CHANCE,
	QI_COST_REDUCTION,
	TECHNIQUE_COST_REDUCTION,
	TECHNIQUE_POWER,
	MIND_CONTROL_RATES[0],
	MIND_CONTROL_RATES[1],
	MIND_CONTROL_RATES[2],
	MIND_CONTROL_RATES[3],
	MIND_CONTROL_RATES[4],
	MIND_CONTROL_RATES[5],
	MIND_CONTROL_RATES[6],
	MIND_CONTROL_RATES[7],
	MIND_CONTROL_RATES[8],
	MIND_CONTROL_RATES[9],
	MIND_CONTROL_RATES[10],
	MIND_CONTROL_RATES[11],
]
