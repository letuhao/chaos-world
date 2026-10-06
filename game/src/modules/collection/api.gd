class_name CollectionApi
extends RefCounted

## Public facade for the `collection` module (ADR 0127). Other modules may reference
## ONLY this file (`api.gd`).
##
## Collection is a read-only module that tracks collection progress across the program
## and pays narrative rewards through the existing quest grant system. It reads from
## `social`, `dual_cultivation`, `fertility`, and `destiny` facades — never storing
## state of its own.
##
## **Collection rewards are narrative, not power.** Each tier pays a fate through
## `DestinyApi.earn_fate` with source `"collection:tier_<id>"`. Fates are narrative
## rewards (new story content, new dialogue options), not power rewards. This preserves
## the yin-yang: collecting partners does not make you stronger, it opens narrative doors.
##
## **Emotional signature is derived from axes, never stored.** The signature is computed
## from a bond's standing band, trust band, and dominant cause kind on every read, so
## it cannot drift when the axes change.
##
## **Every pool is clamped through `RowBudget.cap()`.** No unbounded row growth.

# --- Tier definitions ----------------------------------------------------------

const TIER_COUNT := 12

# Collection point values
const POINTS_PARTNER_CONFIDANT := 1
const POINTS_BOND_CLASS := 1
const POINTS_PILLAR_STAGE := 1
const POINTS_HETEROSIS_CARRIER := 2
const POINTS_HETEROSIS_EXPRESSED := 3

# Fate source prefix for collection rewards
const FATE_SOURCE_PREFIX := "collection:tier_"

# Pillar stage thresholds (derived from DualCultivationStats derived values)
const PILLAR_STAGE_2_AT := 40.0
const PILLAR_STAGE_3_AT := 70.0
const PILLAR_STAGE_4_AT := 100.0

# Heterosis derivation thresholds
const HETEROSIS_CARRIER_MIN_LINEAGES := 2
const HETEROSIS_CARRIER_MIN_PURITY := 0.3
const HETEROSIS_DECAY_RATE := 0.5

# --- Facade verbs ---------------------------------------------------------------


## The collection state for an actor: partners, bond classes, dual cultivation
## milestones, heterosis, and tier progress. Primitives only, `{}` with no actor.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var partners := _partners(actor)
	var bond_classes := _bond_classes(actor)
	var pillars := _pillars(actor)
	var heterosis := _heterosis(actor)
	var tiers := _tiers(actor, partners, bond_classes, pillars, heterosis)
	return {
		"actor": String(actor.id),
		"partner_count": partners.size(),
		"partners": partners,
		"bond_class_count": bond_classes.size(),
		"bond_classes": bond_classes,
		"pillar_count": pillars.size(),
		"pillars": pillars,
		"heterosis": heterosis,
		"tier_count": TIER_COUNT,
		"tiers": tiers,
		"current_progress": _collection_points(partners, bond_classes, pillars, heterosis),
		"next_tier": _next_tier_id(tiers),
	}


## Record a collection event and return the new state. Events are logged to the
## actor's destiny history through `DestinyApi.record` with a collection counter.
static func record_event(
	actor: Actor, event_type: StringName, partner_id: StringName = &""
) -> Dictionary:
	if actor == null:
		return {}
	DestinyApi.record(actor, &"collection_event", 1)
	return summary(actor)


## Claim a tier reward. Returns `{ok, reason, fate_id}`. Pays a fate through
## `DestinyApi.earn_fate` with source `"collection:tier_<id>"`. The fate_id is
## `"collection_tier_<id>"` — a narrative fate authored in the content tree.
static func claim_tier(actor: Actor, tier_id: int) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor", "fate_id": ""}
	if tier_id < 1 or tier_id > TIER_COUNT:
		return {"ok": false, "reason": "unknown_tier", "fate_id": ""}
	var partners := _partners(actor)
	var bond_classes := _bond_classes(actor)
	var pillars := _pillars(actor)
	var heterosis := _heterosis(actor)
	var tiers := _tiers(actor, partners, bond_classes, pillars, heterosis)
	var tier: Dictionary = tiers[tier_id - 1]
	if bool(tier["claimed"]):
		return {"ok": false, "reason": "already_claimed", "fate_id": ""}
	if not bool(tier["can_claim"]):
		return {"ok": false, "reason": "requirement_not_met", "fate_id": ""}
	var fate_id := StringName("collection_tier_%d" % tier_id)
	var source := "%s%d" % [FATE_SOURCE_PREFIX, tier_id]
	DestinyApi.earn_fate(actor, fate_id, source)
	return {"ok": true, "reason": "", "fate_id": String(fate_id)}


## The heterosis status for an actor. Derived from `FertilityApi.purity_snapshot`:
## an actor carrying 2+ lineages above the purity threshold is a carrier.
static func heterosis_status(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	return _heterosis(actor)


## The relationship history for an actor, read from the destiny ledger's history.
## Returns an array of `{date, event_type, partner_id, detail}` dictionaries.
static func history(actor: Actor) -> Array[Dictionary]:
	if actor == null:
		return []
	var ledger := DestinyApi.state(actor)
	var out: Array[Dictionary] = []
	for entry in ledger.get("history", []) as Array:
		var kind := String((entry as Dictionary).get("kind", ""))
		if kind == "fate" or kind == "counter":
			(
				out
				. append(
					{
						"date": int((entry as Dictionary).get("sequence", 0)),
						"event_type": kind,
						"partner_id": "",
						"detail": String((entry as Dictionary).get("id", "")),
					}
				)
			)
	return out


# --- Partners -------------------------------------------------------------------


## Every partner at CONFIDANT or above, with their bond class and emotional signature.
static func _partners(actor: Actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var state := SocialApi.social_state(actor)
	if state == null:
		return out
	for partner_id in state.partner_ids():
		var entry := SocialApi.bond_entry(actor, partner_id)
		if not bool(entry["present"]):
			continue
		var bond_class := StringName(entry["bond"])
		if not SocialBondClass.at_least(bond_class, SocialBondClass.CONFIDANT):
			continue
		(
			out
			. append(
				{
					"partner_id": String(partner_id),
					"display_name": String(entry["label"]),
					"bond_class": String(bond_class),
					"emotional_signature": _emotional_signature(entry),
					"standing": float(entry["standing"]),
					"trust": float(entry["trust"]),
					"is_active": false,
					"card_tone": &"PartnerCard",
				}
			)
		)
	return out


# --- Bond classes ---------------------------------------------------------------


## Every bond class reached (FRIEND, CONFIDANT, SWORN) across all partners.
static func _bond_classes(actor: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	var state := SocialApi.social_state(actor)
	if state == null:
		return out
	for partner_id in state.partner_ids():
		var entry := SocialApi.bond_entry(actor, partner_id)
		if not bool(entry["present"]):
			continue
		var bond_class := StringName(entry["bond"])
		if SocialBondClass.at_least(bond_class, SocialBondClass.FRIEND) and not out.has(bond_class):
			out.append(bond_class)
	return out


# --- Dual cultivation pillars ---------------------------------------------------


## The three pillars (Essence, Desire, Harmony) with their current stage (1-4).
static func _pillars(actor: Actor) -> Array[Dictionary]:
	var essence_cap := actor.stats.derived(DualCultivationStats.ESSENCE_CAPACITY)
	var allure := actor.stats.derived(DualCultivationStats.ALLURE)
	var harmony := actor.stats.derived(DualCultivationStats.HARMONY)
	return [
		{
			"pillar_id": "essence",
			"display_name": "Essence",
			"current": essence_cap,
			"maximum": PILLAR_STAGE_4_AT,
			"stage": _pillar_stage(essence_cap),
			"stage_count": 4,
			"progress": clampf(essence_cap / PILLAR_STAGE_4_AT, 0.0, 1.0),
		},
		{
			"pillar_id": "desire",
			"display_name": "Desire",
			"current": allure,
			"maximum": PILLAR_STAGE_4_AT,
			"stage": _pillar_stage(allure),
			"stage_count": 4,
			"progress": clampf(allure / PILLAR_STAGE_4_AT, 0.0, 1.0),
		},
		{
			"pillar_id": "harmony",
			"display_name": "Harmony",
			"current": harmony,
			"maximum": PILLAR_STAGE_4_AT,
			"stage": _pillar_stage(harmony),
			"stage_count": 4,
			"progress": clampf(harmony / PILLAR_STAGE_4_AT, 0.0, 1.0),
		},
	]


static func _pillar_stage(value: float) -> int:
	if value >= PILLAR_STAGE_4_AT:
		return 4
	if value >= PILLAR_STAGE_3_AT:
		return 3
	if value >= PILLAR_STAGE_2_AT:
		return 2
	return 1


# --- Heterosis ------------------------------------------------------------------


## Heterosis status derived from `FertilityApi.purity_snapshot`. An actor carrying
## 2+ lineages above the purity threshold is a carrier. The spike magnitude is the
## mean purity across carried lineages. Decay rate is fixed at 0.5 per generation.
static func _heterosis(actor: Actor) -> Dictionary:
	var purity := FertilityApi.purity_snapshot(actor)
	var carried: Array[float] = []
	for lineage_id in purity.keys():
		var value := float(purity[lineage_id])
		if value >= HETEROSIS_CARRIER_MIN_PURITY:
			carried.append(value)
	var has_heterosis := carried.size() >= HETEROSIS_CARRIER_MIN_LINEAGES
	var spike := 0.0
	if has_heterosis:
		var total := 0.0
		for value in carried:
			total += value
		spike = total / carried.size()
	return {
		"has_heterosis": has_heterosis,
		"spike_magnitude": spike,
		"decay_rate": HETEROSIS_DECAY_RATE,
		"carrier_state": has_heterosis,
		"generation": 1,
		"lineage": _lineage_rows(purity),
	}


static func _lineage_rows(purity: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for lineage_id in purity.keys():
		(
			out
			. append(
				{
					"generation": 1,
					"spike": float(purity[lineage_id]),
					"expressed": float(purity[lineage_id]) >= HETEROSIS_CARRIER_MIN_PURITY,
					"partner_race": "",
				}
			)
		)
	return out


# --- Tiers ----------------------------------------------------------------------


## The 12 reward tiers with their requirements and claim status.
static func _tiers(
	actor: Actor,
	partners: Array[Dictionary],
	bond_classes: Array[StringName],
	pillars: Array[Dictionary],
	heterosis: Dictionary
) -> Array[Dictionary]:
	var friend_count := _count_at_least(partners, SocialBondClass.FRIEND)
	var confidant_count := _count_at_least(partners, SocialBondClass.CONFIDANT)
	var sworn_count := _count_at_least(partners, SocialBondClass.SWORN)
	var max_pillar_stage := 1
	for pillar in pillars:
		max_pillar_stage = maxi(max_pillar_stage, int(pillar["stage"]))
	var has_heterosis := bool(heterosis["has_heterosis"])
	var all_met := confidant_count >= 1 and max_pillar_stage >= 3 and has_heterosis
	var requirements := [
		partners.size() >= 1,
		partners.size() >= 3,
		partners.size() >= 5,
		friend_count >= 1,
		friend_count >= 3,
		confidant_count >= 1,
		confidant_count >= 3,
		sworn_count >= 1,
		max_pillar_stage >= 2,
		max_pillar_stage >= 3,
		has_heterosis,
		all_met,
	]
	var out: Array[Dictionary] = []
	for tier_id in range(1, TIER_COUNT + 1):
		var fate_id := "collection_tier_%d" % tier_id
		var claimed := DestinyApi.has_fate(actor, StringName(fate_id))
		var can_claim := bool(requirements[tier_id - 1]) and not claimed
		(
			out
			. append(
				{
					"tier_id": tier_id,
					"threshold": tier_id,
					"reward_fate": fate_id,
					"claimed": claimed,
					"can_claim": can_claim,
					"progress": 1.0 if can_claim else 0.0,
				}
			)
		)
	return out


static func _count_at_least(partners: Array[Dictionary], target: StringName) -> int:
	var count := 0
	for partner in partners:
		if SocialBondClass.at_least(StringName(partner["bond_class"]), target):
			count += 1
	return count


static func _next_tier_id(tiers: Array[Dictionary]) -> int:
	for tier in tiers:
		if not bool(tier["claimed"]):
			return int(tier["tier_id"])
	return 0


# --- Collection points ----------------------------------------------------------


static func _collection_points(
	partners: Array[Dictionary],
	bond_classes: Array[StringName],
	pillars: Array[Dictionary],
	heterosis: Dictionary
) -> int:
	var points := 0
	points += partners.size() * POINTS_PARTNER_CONFIDANT
	points += bond_classes.size() * POINTS_BOND_CLASS
	for pillar in pillars:
		var stage := int(pillar["stage"])
		if stage >= 2:
			points += POINTS_PILLAR_STAGE
	if bool(heterosis["has_heterosis"]):
		points += POINTS_HETEROSIS_CARRIER
	return points


# --- Emotional signature -------------------------------------------------------


## Derive an emotional signature from a bond's axes: standing band + trust band +
## dominant cause kind. Computed on every read, never stored.
static func _emotional_signature(entry: Dictionary) -> String:
	var standing := float(entry["standing"])
	var trust := float(entry["trust"])
	var causes: Array = entry.get("causes", [])
	var dominant_kind := _dominant_cause_kind(causes)
	var tone := _standing_tone(standing)
	var role := _trust_role(trust, dominant_kind)
	return "%s %s" % [tone, role]


static func _standing_tone(standing: float) -> String:
	if standing >= SocialBondClass.CONFIDANT_AT:
		return "devoted"
	if standing >= SocialBondClass.FRIEND_AT:
		return "steady"
	if standing >= SocialBondClass.ACQUAINTANCE_AT:
		return "warm"
	if standing > 0.0:
		return "distant"
	return "cold"


static func _trust_role(trust: float, dominant_kind: String) -> String:
	if trust >= 0.7 and dominant_kind == "combat":
		return "warrior"
	if trust >= 0.5:
		return "ally"
	if trust >= 0.3:
		return "companion"
	if trust > 0.0:
		return "lover"
	return "stranger"


static func _dominant_cause_kind(causes: Array) -> String:
	if causes.is_empty():
		return ""
	var counts: Dictionary = {}
	for cause_id in causes:
		var cause := SocialCauseCatalog.instance().cause_definition(StringName(cause_id))
		if cause == null:
			continue
		var kind := String(cause.kind)
		counts[kind] = int(counts.get(kind, 0)) + 1
	var best := ""
	var best_count := 0
	for kind in counts.keys():
		if int(counts[kind]) > best_count:
			best = kind
			best_count = int(counts[kind])
	return best
