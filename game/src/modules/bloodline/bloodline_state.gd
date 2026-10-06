class_name BloodlineState
extends RefCounted

## The versioned purity ledger, stored as a plain dictionary under
## `actor.module_data["bloodline_state"]` (ADR 0027 pattern). Core persists it without
## ever naming a bloodline.
##
## **This ledger is the single source of truth.** `actor.traits` carries a
## `bloodline:`-namespaced mirror for cheap reads, and the actor carries a
## `bloodline_ledger` component holding a derived summary for a pure provider to read.
## Both are derived and are rebuilt from here on every projection — never trusted.
##
## ## The constants are the module's contract
##
## `RETENTION`, `FLOOR` and `BLEND_CONSTANT` live HERE rather than in a `.tres`
## because they are not content: they are the arithmetic every lineage obeys, and
## `game/tests/modules/bloodline/test_purity_reachability.gd` is the test that holds
## them to it.
##
## They are derived from the fixed point outward, never picked. The map
## `x -> x * RETENTION + BLEND_CONSTANT` converges to `BLEND_CONSTANT / (1 - RETENTION)`,
## so `BLEND_CONSTANT = FLOOR * (1 - RETENTION)`. An earlier draft of ADR 0063 named
## the additive term `BLEND_FLOOR` and got this wrong: with `0.55` retention and a
## `0.10` constant the fixed point was `0.222`, the named floor never applied, and the
## published `0.70`/`0.85` tiers were unreachable by any inheritance path. Renaming it
## and deriving it is the fix, and the reachability test is what makes it stick.

const SCHEMA_VERSION := 1
## `actor.module_data` key.
const MODULE_KEY := &"bloodline_state"
## Every stat modifier a lineage contributes is tagged with this prefix, so a
## re-projection can strip and rebuild the whole contribution from the ledger.
const SOURCE_PREFIX := "bloodline:"
## The `Actor.traits` mirror prefix.
const TRAIT_PREFIX := "bloodline:"

## Share of a parent's purity a child keeps, before the blend constant is added. One
## generation of pure-by-pure inheritance keeps 0.745 of what came in, and a line that
## only breeds with itself still converges on `FLOOR` — which is the whole
## anti-compounding guarantee.
const RETENTION := 0.70
## The authored concentration a line settles at however long it is carried. A tier at
## or below this would be granted to everyone forever and could gate nothing; a tier
## above `RETENTION + BLEND_CONSTANT` could never be inherited at all.
const FLOOR := 0.15
## `FLOOR * (1 - RETENTION)`. Named for its role in the affine map rather than for the
## floor it produces, which is what the earlier draft got wrong.
const BLEND_CONSTANT := 0.045
## ADR 0125. The carrier floor: the purity a lineage settles at when the heterosis
## spike has fully decayed but the lineage is still carried. Just under the common
## threshold, so a carrier is always dormant — the spike is the only way across.
const OUTBREED_FLOOR := 0.417
## ADR 0125. The instability counterpart: the lineage's own authored modifiers are
## discounted by up to this at peak spike, derived at read time from the current
## purity's distance above the carrier floor.
const INSTABILITY_MAX_DISCOUNT := 0.34


## The stat source id one lineage contributes under.
static func source_for(id: StringName) -> StringName:
	return StringName("%s%s" % [SOURCE_PREFIX, id])


## The `Actor.traits` mirror id one lineage is reflected under.
static func trait_for(id: StringName) -> StringName:
	return StringName("%s%s" % [TRAIT_PREFIX, id])


## True when a stat modifier source belongs to this module.
static func is_own_source(source: StringName) -> bool:
	return String(source).begins_with(SOURCE_PREFIX)


## THE core function: the concentration a child of `parent_a` and `parent_b` carries
## for one lineage.
##
## **The mean is load-bearing.** Blending toward the *maximum* would make every
## pairing behave identically — a strong parent would swallow a weak one — which
## collapses the entire marriage-and-alliance layer this system exists to support. On a
## mean, an outsider spouse is a real and measurable cost (`1.0` with `0.0` yields
## `0.395`, a viable carrier below `rare`), so who an actor beds is a decision rather
## than a formality. The result is clamped to `[0, 1]`, so no amount of pairing
## produces an unbounded super-bloodline.
##
## ## ADR 0125: the heterosis excess rides on top, and only on divergence
##
## `divergence` is the pair's Jaccard distance over lineage-id sets, computed once
## per pairing in `BloodlineResolver.resolve` (`0.0` same family, `1.0` unrelated).
## The excess `0.70 * m * divergence * (1.0 - m)` fires only above zero, so the
## inbred fixed point is untouched: at `D == 0` this is the same affine map, and
## the default `0.0` keeps every caller that does not compute divergence on it.
static func inherit(purity_a: float, purity_b: float, divergence: float = 0.0) -> float:
	var m := (purity_a + purity_b) * 0.5
	var excess := 0.70 * m * divergence * (1.0 - m)
	return clampf(m * RETENTION + BLEND_CONSTANT + excess, 0.0, 1.0)


## ADR 0125's instability counterpart: the factor the lineage's own authored
## modifiers are scaled by while a spike is active. Derived at read time from
## the current purity's distance above the carrier floor, so no ledger stores
## it and a restored save re-derives the same number: `1.0` at or below the
## floor (no discount), down to `1.0 - INSTABILITY_MAX_DISCOUNT` at the
## first-generation ceiling and past it.
static func instability_discount(purity: float) -> float:
	var span := first_generation_ceiling() - OUTBREED_FLOOR
	if span <= 0.0:
		return 1.0
	var spike_remaining := clampf((purity - OUTBREED_FLOOR) / span, 0.0, 1.0)
	return 1.0 - INSTABILITY_MAX_DISCOUNT * spike_remaining


## The one-generation ceiling for a lineage: `inherit(1.0, 1.0) == 0.745`. No content
## may author a threshold above it, or that lineage is dead on arrival. Exposed so a
## content test can say so rather than hardcoding the number a second time.
static func first_generation_ceiling() -> float:
	return inherit(1.0, 1.0)


## A known-lineage filter for this module. `known_bloodlines` comes from the catalog;
## an entry naming content that no longer ships is dropped rather than persisted, so a
## save from a wider content build cannot smuggle in a lineage the current build does
## not define. Every purity is clamped to `[0, 1]` on the way through.
##
## `applied` is deliberately NOT filtered by `known_bloodlines`: it records what the
## projection last put on the actor, including for content the catalog has since
## dropped, and that contribution still has to be subtracted — which is exactly when a
## missing definition would otherwise leave it stranded on the actor.
##
## A payload that cannot be read is diagnosed as empty rather than partially applied.
## Half a ledger is worse than none: the projection subtracts what the ledger says it
## already added, so a half-read ledger would subtract the wrong amount. An unreadable
## `lineages` field therefore discards the whole field; a single unreadable entry
## inside it is dropped on its own, because one bad number is not evidence that the
## rest of the dictionary is corrupt.
static func normalize(payload: Dictionary, known_bloodlines: Dictionary = {}) -> Dictionary:
	var out := {"version": SCHEMA_VERSION, "lineages": {}, "applied": {}}
	if payload.is_empty():
		return out
	var lineages = payload.get("lineages", {})
	if lineages is Dictionary:
		for key in (lineages as Dictionary).keys():
			var lineage_id := String(key)
			if lineage_id == "":
				continue
			if not known_bloodlines.is_empty() and not known_bloodlines.has(lineage_id):
				continue
			var value = (lineages as Dictionary)[key]
			if not (value is float or value is int):
				continue
			out["lineages"][lineage_id] = clampf(float(value), 0.0, 1.0)
	var applied = payload.get("applied", {})
	if applied is Dictionary:
		for key in (applied as Dictionary).keys():
			var lineage_id := String(key)
			if lineage_id == "":
				continue
			out["applied"][lineage_id] = _trait_list((applied as Dictionary)[key])
	return out


## The empty ledger.
static func empty() -> Dictionary:
	return normalize({})


## The concentration `ledger` carries for one lineage. 0.0 for a lineage it does not
## carry — absence is zero concentration, not a missing key.
static func purity(ledger: Dictionary, lineage_id: StringName) -> float:
	return float((ledger.get("lineages", {}) as Dictionary).get(String(lineage_id), 0.0))


## Every lineage `ledger` carries a concentration for, canonically ordered.
static func lineage_ids(ledger: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	var lineages: Dictionary = ledger.get("lineages", {})
	for key in lineages.keys():
		out.append(StringName(key))
	out.sort()
	return out


## Every lineage in `ledger` that has crossed its authored threshold, canonically
## ordered. Reads the catalog, so it is only as current as the content tree.
static func awake_ids(ledger: Dictionary) -> Array[StringName]:
	var catalog := BloodlineCatalog.instance()
	var out: Array[StringName] = []
	for lineage_id in lineage_ids(ledger):
		var def := catalog.bloodline_definition(lineage_id)
		if def != null and def.is_awake(purity(ledger, lineage_id)):
			out.append(lineage_id)
	return out


## `ledger` with `lineage_id` set to `clamp(value, 0, 1)`. Returns the ledger itself
## when the lineage is unknown, so a caller cannot smuggle in content nothing defines.
static func with_purity(ledger: Dictionary, lineage_id: StringName, value: float) -> Dictionary:
	var out := normalize(ledger)
	if lineage_id == &"":
		return out
	out["lineages"][String(lineage_id)] = clampf(value, 0.0, 1.0)
	return out


## The highest concentration `ledger` carries, or 0.0 when it carries none.
static func peak(ledger: Dictionary) -> float:
	var best := 0.0
	for lineage_id in lineage_ids(ledger):
		best = maxf(best, purity(ledger, lineage_id))
	return clampf(best, 0.0, 1.0)


## The mean concentration across every lineage `ledger` carries, or 0.0 when it
## carries none.
static func mean(ledger: Dictionary) -> float:
	var ids := lineage_ids(ledger)
	if ids.is_empty():
		return 0.0
	var total := 0.0
	for lineage_id in ids:
		total += purity(ledger, lineage_id)
	return clampf(total / float(ids.size()), 0.0, 1.0)


## The lineage ids the projection last put on the actor, unfiltered by the catalog.
static func applied_ids(ledger: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	var applied: Dictionary = ledger.get("applied", {})
	for key in applied.keys():
		out.append(StringName(key))
	out.sort()
	return out


## The trait ids recorded as projected for `lineage_id`.
static func applied_traits(ledger: Dictionary, lineage_id: StringName) -> Array[StringName]:
	var traits: Array[StringName] = []
	for value in (ledger.get("applied", {}) as Dictionary).get(String(lineage_id), []):
		traits.append(StringName(value))
	return traits


static func _trait_list(record) -> Array:
	var out: Array = []
	if record is Array:
		for value in record as Array:
			out.append(String(value))
	elif record is Dictionary:
		# Tolerates the older shape where a bare id stood in for a trait list.
		out.append(String((record as Dictionary).get("id", "")))
		out = out.filter(func(value): return value != "")
	return out
