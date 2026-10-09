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
## and the projection's suites (`test_status_projection.gd`,
## `tests/app/test_age_band_projection.gd`) assert the pair installs and swaps as ONE unit:
## a band transition that wrote one half without the other fails there. The STRICT
## behavioural ordering the pairing deserves lives in
## `tests/modules/status/test_age_band_statuses.gd`: on every band whose wear half is a
## cost, clarity-only strictly dominates wear-only on every authored axis, and the
## first-ash asymmetry is asserted in the direction that band authors rather than one
## direction for all four.
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

## The projection TRACK id (ADR 0902 P8, BL-0924): the table's bands are its rungs, each
## the band's own (wear, clarity) pair, so a band transition is ONE
## `StatusProjection.sync` that withdraws the previous pair before writing the next.
const TRACK := &"age"

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


## Every band's id pair, youngest first — the rung list `StatusProjection.sync` walks.
static func rungs() -> Array:
	var out: Array = []
	for row in _table().bands():
		out.append(ids_for(StringName(row.get("band", ""))))
	return out


## The rung index `actor` currently stands on: [method band_for]'s answer, mapped through
## the same ordered rows, so the projection cannot disagree with the read model.
static func stage_of(actor: Actor) -> int:
	var band := band_for(actor)
	var rows := _table().bands()
	for index in rows.size():
		if StringName(rows[index].get("band", "")) == band:
			return index
	return 0


## Sync `actor`'s age projection: the current band's pair installed, the previous band's
## withdrawn. The band is the DRIVING SCALAR — this reads it and writes the statuses, and
## nothing here touches a clock (the caller that owns time decides when to sync).
static func sync(actor: Actor) -> Dictionary:
	return StatusProjection.sync(
		actor, TRACK, stage_of(actor), rungs(), StatusProjection.MATCH_PREFIX
	)


## The band `actor` is standing in, read against its EFFECTIVE lifespan.
##
## ## Delegated, not computed
##
## The computation lives in `AgeBandTable.band_for_actor` — the one function that turns
## an age and a lifespan into a band — because two of them is the ADR 0066 failure this
## file used to carry beside it. Everything below the old body said still holds (the
## lifespan is `RealmDefaults.LIFESPAN`'s published read; the calendar is `TimeLadder`
## derived once, now in the table's static), so this is the same answer through one door.
static func band_for(actor: Actor) -> StringName:
	return AgeBandTable.band_for_actor(actor)


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
## and the numbers behind them. This is what `StatusApi.summary` publishes under `age`.
## The cap a former version of this sentence cited (`rules.MAX_FACADE_PUBLIC_METHODS`) is
## DELETED (`tools/arch/rules.py`): the facade is measured by FAN-IN now, so the read
## model is a key on `StatusApi.summary`, never a second accessor.
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
