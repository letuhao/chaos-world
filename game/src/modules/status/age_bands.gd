class_name AgeBands
extends RefCounted

## ADR 0258 §3: which age band `actor` is standing in, and WHICH STATUSES that band is
## made of — the DEBUFF half and the BUFF half, which ship in the SAME change or not at
## all.
##
## ## Why this lives in `status` and is not a second system
##
## The age bands ARE statuses. `status/` already owns `StatusDef`, `StatusCatalog`, the
## modifier pipeline and the one tick loop, so a band is authored `.tres` content resolved
## through `StatusApi.apply_cultivation` and the whole existing machinery applies it. A
## parallel "age effect" system would be a second modifier composer, which is ADR 0026's
## exact prohibition.
##
## ## The PAIR, stated as the two halves this file reads
##
## | direction | axis                                              |
## |-----------|---------------------------------------------------|
## | DEBUFF    | cultivation gain rate falls                       |
## | DEBUFF    | body recovery and combat refresh slow             |
## | BUFF      | comprehension / dao-heart floor rises              |
## | BUFF      | social standing and recognition accumulate         |
##
## A band with only the debuff is a tax on whoever is unlucky to be old, which AGENTS.md's
## yin-yang rule calls a bug rather than a feature. Every band row therefore authors BOTH,
## and `tests/modules/status/test_age_band_statuses.gd` proves the pairing behaviourally:
## removing the buff half must leave a long-lived hero STRICTLY WORSE than removing the
## debuff half does.
##
## ## Why the status ids are derived from the BAND NAME rather than authored beside it
##
## A band's status ids are `age_<band>_wear` and `age_<band>_clarity`. Deriving them from
## one authored band name keeps the pair structurally inseparable: there is no way to author
## the debuff without the buff, because both come from the same band name through one
## function. The NUMBERS are in the `.tres` files, never here (ADR 0050).
##
## ## Nothing here reads a clock, and nothing here advances the age
##
## Age is written by the save restore and by `RaceProjection`'s birth write, and it is
## converted from the world clock's period count by `app/soul_age.gd`. This file only READS
## `actor.age_years`, which is the whole reason it can be a pure function of the actor — and
## the reason `status` needs no `TimeLadder` edge (ADR 0173: a span is handed DOWN by the
## caller that owns time, never measured here).

## The prefix every age status id carries. Distinct from the ambient hazard tree's ids on
## purpose: `StatusCatalog`'s two namespaces are "what a landed blow inflicts" and "what a
## place inflicts", and an age status is neither — it is installed by the body itself, at
## conception and whenever its band changes. Naming it with its own prefix means no screen
## listing a blown's worth of statuses can mistake an age band for one of them.
const PREFIX := "age_"

## The suffix the DEBUFF half of every band carries. A debuff is what a worn body costs.
const WEAR_SUFFIX := "_wear"

## The suffix the BUFF half of every band carries. The buff is what the same years bought.
const CLARITY_SUFFIX := "_clarity"

## The table, loaded once and cached. Loaded rather than `preload`ed because the `.tres`
## binds THIS script's sibling (`age_band_table.gd`) and a compile-time reference from a
## script that the table's own loader reaches is the load cycle `TimeLadder._table_resource`
## and `RealmDefaults.POWER` are written to avoid — here in the opposite direction.
static var _bands: AgeBandTable = null


## The status id carrying the DEBUFF half of `band`, derived from the band name so the
## pair cannot be separated. `age_gilded_wear` from `&"gilded"`.
static func wear_id(band: StringName) -> StringName:
	return StringName(PREFIX + String(band) + WEAR_SUFFIX)


## The status id carrying the BUFF half of `band`. `age_gilded_clarity` from `&"gilded"`.
static func clarity_id(band: StringName) -> StringName:
	return StringName(PREFIX + String(band) + CLARITY_SUFFIX)


## Both halves of `band`, DEBUFF first, in that order deliberately: a reader that shows one
## line wants the cost before the gain, because the cost is what the player is paying.
static func ids_for(band: StringName) -> Array[StringName]:
	return [wear_id(band), clarity_id(band)]


## The band `actor` is standing in, read against its EFFECTIVE lifespan.
##
## ## The lifespan is `RealmDefaults.LIFESPAN`'s published read, never a re-derivation
##
## `race/provider.gd` contributes `RaceStats.LIFESPAN` from exactly that table, so an age
## resolved against the published stat is compared against the same number the lineage
## screen shows and the age-death hook compares against. Three readers of one table is
## correct; two derivations of it would drift on the first tier retune (the ADR 0116
## mutation, in miniature).
##
## ## The calendar is `TimeLadder`, and the conversion happens ONCE, here
##
## `AgeBandTable` takes DAYS in both arguments precisely so this is the only place years
## become days. `TimeLadder` measures every ratio from the BASE (ADR 0173), so days-per-year
## is `ratio_for(&"year") / ratio_for(&"day")` — derived, never typed, so a retune of either
## row moves this with it instead of leaving a 365 lying beside it.
##
## ## A null actor, a zero lifespan and an unauthored calendar all answer the YOUNGEST band
##
## None of them is a claim about a body. `AgeBandTable.band_for` clamps a non-positive
## lifespan to `FIRST_ASH`, so the dangerous direction — a body with no species reading as
## the OLDEST band and being expired on its first frame — cannot occur here either.
static func band_for(actor: Actor) -> StringName:
	if actor == null:
		return AgeBandTable.FIRST_ASH
	var lifespan := _lifespan_of(actor)
	if lifespan <= 0.0:
		return AgeBandTable.FIRST_ASH
	var days_per_year := days_per_year()
	if days_per_year <= 0:
		return AgeBandTable.FIRST_ASH
	return BANDS.band_for(maxf(0.0, actor.age_years) * float(days_per_year), lifespan)


## Whole DAYS in one authored YEAR, or `0` when either magnitude is unauthored. Spelled as
## the two ladder rows rather than a constant for the reason `SoulAge.days_per_year` gives:
## a second copy of 365 is a second thing to keep correct.
static func days_per_year() -> int:
	var year_ratio := TimeLadder.ratio_for(&"year")
	var day_ratio := TimeLadder.ratio_for(&"day")
	if year_ratio < 1 or day_ratio < 1:
		return 0
	return year_ratio / day_ratio


static func _table() -> AgeBandTable:
	if _bands == null:
		_bands = load("res://src/core/age_band_table.tres") as AgeBandTable
	return _bands


## The EFFECTIVE lifespan in DAYS, read from the stat the race module already published.
## `0.0` for a body with no body plan, which is the honest "there is no lifespan" and is
## what makes [method band_for] answer the youngest band rather than divide by nothing.
static func _lifespan_of(actor: Actor) -> float:
	return maxf(0.0, actor.stats.derived(&"race_lifespan"))


## The whole age read as primitives, for a screen and a test: the band, both halves of it,
## and the numbers behind them. This is what `StatusApi.summary` publishes under `age`, and
## it is the read model rather than a verb — `status/api.gd` is at
## `rules.MAX_FACADE_PUBLIC_METHODS` and a thirteenth method is a facade split, not a new
## accessor.
##
## `{}` for no actor, so the "no actor" shape is the same one every panel in `src/ui/` uses.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var band := band_for(actor)
	var table := _table()
	var lifespan := _lifespan_of(actor)
	return {
		"band": String(band),
		"fraction": table.fraction_for(band),
		"age_years": maxf(0.0, actor.age_years),
		"lifespan_days": lifespan,
		"lifespan_fraction": _share(actor, lifespan),
		"wear_id": String(wear_id(band)),
		"clarity_id": String(clarity_id(band)),
		# Both ids as an array as well, so a panel renders one list instead of two
		# hand-assembled ones and cannot show one half of the pair on its own.
		"ids": _id_strings(band),
		"bands": table.bands(),
	}


## How far through its own life this body is, in `[0, 1]`, or `0.0` for a body with no
## lifespan. The same share `AgeBandTable.band_for` compares, published rather than
## recomputed by a screen — a screen that divided two numbers it had itself would be a
## second derivation of the same rule.
static func _share(actor: Actor, lifespan: float) -> float:
	var days_per_year := days_per_year()
	if lifespan <= 0.0 or days_per_year <= 0:
		return 0.0
	return clampf(maxf(0.0, actor.age_years) * float(days_per_year) / lifespan, 0.0, 1.0)


static func _id_strings(band: StringName) -> Array[String]:
	var out: Array[String] = []
	for id in ids_for(band):
		out.append(String(id))
	return out
