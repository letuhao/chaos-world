class_name ElementMastery
extends RefCounted

## The elemental-mastery cultivation path (ADR 0004/0005/0006). It advances along the
## shared realm ladder; `stage_names` is its own vocabulary for display only.

const PATH_ID := &"elemental_mastery"
const MAX_ELEMENT_TIER := 3

## ## The mastery BOND (BL-0938): one saturating curve and a cap keyed to the rise
##
## Mastery had no cost and no bound: `practise` was free and unlimited and the provider
## multiplied `mastery * 0.1` LINEARLY, so a few dozen sittings (measured: ~61 free
## presses to 2700) read `element_power_<e>` ~271x, past the whole authored realm ladder
## and priced in nothing. The bond is two parts and both are needed:
##
## 1. The OUTPUT saturates — `saturation(m) = m / (m + MASTERY_HALF)`, shared by the
##    power and crit terms, so every further point still pays but is worth less. At
##    `MASTERY_HALF` the curve is exactly half; it approaches 1.0 and never reaches it.
## 2. The INPUT is capped per element, keyed to the tier the body is PREPARING FOR: the
##    last realm of a tier reads the tier above, which is what keeps the qi ladder's
##    three authored element gates (900/1800/2700 at the tier rises) reachable on ONE
##    element — 1200/2000/3000 sit above them by construction (BL-0938's ruling).
##
## The cap is a policy on the TRAINING verbs (`ElementTraining.practise` / `use_elixir`),
## not a clamp on the read: a save that predates the cap keeps its mastery and its power,
## it just cannot grow further until the body rises.
const MASTERY_HALF := 300.0

## Per-element mastery ceiling by REALM TIER (`RealmDefaults.MORTAL`..`TRANSCENDENT`).
## Keyed by tier, never by ladder position: a realm inserted between two rises cannot
## shift a cap onto the wrong band, and the four rows sit above the three authored
## element gates (900/1800/2700) so the mono-element traversal keeps passing.
const CAP_BY_TIER := {1: 600.0, 2: 1200.0, 3: 2000.0, 4: 3000.0}

## The authored labour curve, INJECTED by the composition root (ADR 0173's pattern: the
## caller that owns the number hands it down). This module may not read another path's
## seeds, so an uninstalled source answers -1.0 and advancement refuses by name rather
## than inventing a threshold.
static var _progress_source: Callable = Callable()


## The saturating mastery curve, shared by `ElementProvider`'s power and crit terms.
## Non-finite and non-positive mastery read `0.0` — the same fail-safe the old linear
## read had, so a malformed channel contributes nothing instead of poisoning every
## derived stat the provider publishes.
static func saturation(mastery: float) -> float:
	if not is_finite(mastery) or mastery <= 0.0:
		return 0.0
	return mastery / (mastery + MASTERY_HALF)


## The rank a mastery question is priced at: the elemental path's own standing when the
## actor has enrolled it, the highest realm across its paths otherwise, and the first
## rung when it has no path at all. ONE home for the pick — a sitting's rate and its cap
## must never disagree about which realm a body stands in.
static func rank_of(actor: Actor) -> StringName:
	if actor != null:
		var state := actor.path(PATH_ID)
		if state != null:
			return state.rank_id
		var realm := RealmScaling.highest_realm(actor)
		if realm != null:
			return realm.id
	return RealmDefaults.ladder().realms()[0].id


## The per-element mastery cap at `rank_id`: the tier the body is PREPARING FOR, which is
## the NEXT realm's tier on the last rung of a tier and the standing tier everywhere
## else. An unknown rank reads tier 1, the same fail-safe `max_tier` uses.
static func cap_at_rank(rank_id: StringName) -> float:
	var ladder := RealmDefaults.ladder()
	var next := ladder.next(rank_id)
	var tier := ladder.tier_of(next.id) if next != null else ladder.tier_of(rank_id)
	if tier <= 0:
		tier = 1
	return float(CAP_BY_TIER.get(tier, CAP_BY_TIER[1]))


## The per-element mastery cap for `actor`'s standing.
static func cap_for(actor: Actor) -> float:
	return cap_at_rank(rank_of(actor))


static func path_def() -> CultivationPathDef:
	var def := CultivationPathDef.new()
	def.id = PATH_ID
	def.display_name = "Elemental Mastery"
	def.stage_names = _stage_names()
	return def


static func max_tier(rank_id: StringName) -> int:
	var realm_tier := RealmDefaults.ladder().tier_of(rank_id)
	if realm_tier <= 0:
		return 1
	return mini(MAX_ELEMENT_TIER, realm_tier)


static func can_use(rules: ElementRules, rank_id: StringName, element_id: StringName) -> bool:
	var entry := rules.element(element_id)
	if entry == null:
		return false
	return entry.tier <= max_tier(rank_id)


## Whether `actor` may USE `element_id`: the elemental rank must reach the element's
## tier AND the actor's realm must allow it — both, deliberately (the owner's ruling).
## A body that never opened the path reads as the bottom rung, so tier 1 is the base
## spark every actor has and the advanced tiers are what awakening buys.
static func usable(actor: Actor, element_id: StringName, rules: ElementRules = null) -> bool:
	if actor == null:
		return false
	var resolved := rules if rules != null else ElementDefaults.rules()
	var entry := resolved.element(element_id)
	if entry == null:
		return false
	var rank := RealmDefaults.ladder().realms()[0].id
	var state := actor.path(PATH_ID)
	if state != null:
		rank = state.rank_id
	if entry.tier > max_tier(rank):
		return false
	# The REALM half reads the qi climb, not `highest_realm`: the elemental rank is a
	# path itself, so the highest realm would satisfy this condition by construction and
	# the second half of the ruling would be vacuous. The qi realm is the climb the
	# elements ride (ADR 0069's qi damage); with no qi path the highest realm stands in,
	# and a body with no path at all reads as the bottom rung — the same fail-safe the
	# rank half uses, so "no realm yet" is the base spark rather than a lockout.
	var realm_id := RealmDefaults.ladder().realms()[0].id
	var qi := actor.path(PathState.QI)
	if qi != null:
		realm_id = qi.rank_id
	else:
		var realm := RealmScaling.highest_realm(actor)
		if realm != null:
			realm_id = realm.id
	if entry.tier > max_tier(realm_id):
		return false
	return true


static func set_progress_source(source: Callable) -> void:
	_progress_source = source


static func threshold_for(realm_id: StringName) -> float:
	if not _progress_source.is_valid():
		return -1.0
	return maxf(-1.0, float(_progress_source.call(realm_id)))


## Whether `actor` has opened the elemental path. The Awaken action
## (`ElementsApi.begin`) is the only door; nothing enrolls implicitly.
static func enrolled(actor: Actor) -> bool:
	return actor != null and actor.path(PATH_ID) != null


## The mastery `actor` has earned on `element_id`, from the BASE layer the provider
## reads.
static func mastery_of(actor: Actor, element_id: StringName) -> float:
	if actor == null or actor.stats == null:
		return 0.0
	return maxf(0.0, actor.stats.get_base(ElementStats.mastery_id(element_id)))


## Every element's mastery summed: the currency the elemental climb is paid in.
static func total_mastery(actor: Actor) -> float:
	var total := 0.0
	for def in ElementDefaults.all():
		total += mastery_of(actor, def.id)
	return total


## The path's read for a screen and a test: standing, target, threshold, mastery, and
## whether the next rung is paid. `{}` when the path is not enrolled.
static func preview(actor: Actor) -> Dictionary:
	if not enrolled(actor):
		return {}
	var state := actor.path(PATH_ID)
	var next := RealmDefaults.ladder().next(state.rank_id)
	var threshold := -1.0 if next == null else threshold_for(next.id)
	return {
		"rank": String(state.rank_id),
		"stage": path_def().stage_name(state.rank_id),
		"target": "" if next == null else String(next.id),
		"threshold": threshold,
		"mastery": total_mastery(actor),
		"can_advance": next != null and threshold >= 0.0 and total_mastery(actor) >= threshold,
	}


## Raise the path one rung when the actor's TOTAL mastery meets the next realm's
## authored threshold. The advance itself is core's (`Breakthrough.try_advance`), so
## the elemental climb shares the one advancement shape with qi, body and mind.
static func advance(actor: Actor) -> Dictionary:
	if not enrolled(actor):
		return {"ok": false, "reason": "not_enrolled"}
	var state := actor.path(PATH_ID)
	var next := RealmDefaults.ladder().next(state.rank_id)
	if next == null:
		return {"ok": false, "reason": "max_rank", "rank": String(state.rank_id)}
	var threshold := threshold_for(next.id)
	if threshold < 0.0:
		return {"ok": false, "reason": "no_progress_source"}
	var mastery := total_mastery(actor)
	if mastery < threshold:
		return {
			"ok": false,
			"reason": "insufficient_mastery",
			"threshold": threshold,
			"mastery": mastery,
		}
	if not Breakthrough.try_advance(actor, PATH_ID, ElementBreakthroughCondition.new()):
		return {"ok": false, "reason": "refused"}
	return {"ok": true, "rank": String(next.id)}


static func _stage_names() -> Array[String]:
	return [
		"Spark",
		"Ember",
		"Kindling",
		"Blaze",
		"Attunement",
		"Resonance",
		"Channeling",
		"Confluence",
		"Convergence",
		"Elemental Sea",
		"Rising Tide",
		"Stormcall",
		"Maelstrom",
		"Elemental Avatar",
		"Lord of Elements",
		"King of Elements",
		"Emperor of Elements",
		"Sovereign of Elements",
		"Elemental Domain",
		"Elemental Law",
		"Elemental Edict",
		"Elemental Authority",
		"Elemental Hegemony",
		"Elemental Origin",
		"Primordial Element",
		"Dao of Elements",
		"Elemental Ascendant",
		"Elemental Transcendent",
		"Elemental Dao Ancestor",
		"Primordial Elemental Origin",
	]
