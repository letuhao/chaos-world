class_name BloodlineSummary
extends RefCounted

## A derived, read-only snapshot of one actor's ancestry: which lineages it carries,
## how concentrated each is, which of them are awake, and what that is currently worth.
##
## **Why this is a component rather than a catalog lookup.** `StatProvider.contribute`
## runs on every stat cache miss. If `BloodlineProvider` went to the catalog for each
## lineage it counted, a stat read would depend on mutable module state and defeat the
## caching `ActorStats` already does. So `BloodlineProjection` builds this once per
## projection and parks it on `actor.components`, and the provider reads only that.
##
## This mirrors how `RaceProjection` parks its resolved `RaceDef`.

## `actor.components` slot the facade's projection attaches.
const COMPONENT := &"bloodline_summary"

## Every carried lineage id, canonically ordered.
var lineages: Array = []
## One entry per carried lineage, keyed by its id. Derived; never the truth.
var entries: Dictionary = {}
## The subset of `lineages` that has crossed its authored threshold.
var awakened: Array[StringName] = []
var peak_purity: float = 0.0
var mean_purity: float = 0.0
## The bounded aggregate `BloodlineProvider` publishes as `bloodline_power`.
var bloodline_power: float = 0.0


## Every lineage `ledger` carries, canonically ordered, with each one's concentration
## and awake state resolved. Returns an empty summary for a ledger that carries
## nothing, so a consumer never has to test for null before iterating.
static func from_ledger(ledger: Dictionary) -> BloodlineSummary:
	var catalog := BloodlineCatalog.instance()
	var summary := BloodlineSummary.new()
	var total_power := 0.0
	for lineage_id in BloodlineState.lineage_ids(ledger):
		var def := catalog.bloodline_definition(lineage_id)
		var purity := BloodlineState.purity(ledger, lineage_id)
		var awake := def != null and def.is_awake(purity)
		var entry := {
			"id": String(lineage_id),
			"purity": purity,
			"awake": awake,
			"display_name": "" if def == null else def.display_name,
			"description": "" if def == null else def.description,
			"threshold": 0.0 if def == null else def.awaken_threshold,
			"known": def != null,
		}
		summary.entries[String(lineage_id)] = entry
		if awake:
			summary.awakened.append(lineage_id)
			total_power += _power_of(def, purity)
	summary.lineages = []
	for key in summary.entries.keys():
		summary.lineages.append(StringName(key))
	summary.lineages.sort()
	summary.peak_purity = BloodlineState.peak(ledger)
	summary.mean_purity = BloodlineState.mean(ledger)
	summary.bloodline_power = total_power
	return summary


## One lineage's entry, or null when the actor does not carry it.
func entry(lineage_id: StringName) -> Dictionary:
	return entries.get(String(lineage_id))


## The concentration carried for `lineage_id`, or 0.0.
func purity_of(lineage_id: StringName) -> float:
	var found := entry(lineage_id)
	return 0.0 if found == null else float((found as Dictionary)["purity"])


## Whether `lineage_id` has crossed its authored threshold. False for a lineage the
## catalog does not ship: content nothing defines cannot gate anything.
func is_awake(lineage_id: StringName) -> bool:
	var found := entry(lineage_id)
	return found != null and bool((found as Dictionary)["awake"])


## Every lineage carried, canonically ordered.
func lineage_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for lineage_id in lineages:
		out.append(StringName(lineage_id))
	return out


## Every lineage that is awake, canonically ordered.
func awake_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for lineage_id in awakened:
		out.append(StringName(lineage_id))
	return out


## How much a lineage contributes while awake. **The percent grants are NOT scaled by
## purity** — ADR 0063 is explicit that purity gates and does not scale, because a
## purity multiplier would hand a deep-realm actor a compounding advantage. The only
## weighting here is the tier the concentration sits in, which is bounded at 1.0, so a
## barely-awake carrier is worth the same as a pure one and the readout is purely
## "what is unlocked".
static func _power_of(def: BloodlineDef, _purity: float) -> float:
	if def == null or not def.has_modifiers():
		return 0.0
	var tier := BloodlineApi.rank_tier(def.awaken_threshold)
	var weight := 1.0
	match tier:
		&"founding":
			weight = 1.0
		&"rare":
			weight = 0.6
		_:
			weight = 0.3
	var total := 0.0
	for key in def.percent_modifiers.keys():
		total += absf(float(def.percent_modifiers[key]))
	return total * weight
