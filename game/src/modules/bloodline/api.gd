class_name BloodlineApi
extends RefCounted

## Public facade for the `bloodline` module (ADR 0063). Other modules may reference
## ONLY this file (`api.gd`). Concrete implementations live beside this file and are
## wired in `app/`.
##
## **A bloodline is a diluted, unlock-gated inheritance, not an ability score.** It
## answers *how concentrated is this lineage in you*, *has it unlocked*, and *who were
## your parents* — never a level you grind.
##
## **Purity is monotonically decaying within one actor's life and is never raised.**
## Cultivation may raise a *race*-granted stat (ADR 0062), but no gameplay action in
## this module raises bloodline purity; the only way to be born purer is to be born to
## purer parents. Dilution is an accepted cost, not a bug to patch with a reset. The
## known genre answer — a purity-restoration quest beat — is recorded as a gap and
## deliberately not built here, because building it now would put an ability score
## behind the one number this system says is not an ability score.
##
## `set_purity` is therefore the one write verb, and it exists for the three places a
## ledger is legitimately authored — conception, character creation, and tests. Any
## caller that reaches for it in order to make an actor *stronger* is using the module
## against its own design.

## The stat-provider component slot. Underscored because it is wiring, not a question.
const _PROVIDER_COMPONENT := &"bloodline_provider"
## `actor.module_data` key the versioned ledger is persisted under (ADR 0027).
const MODULE_KEY := BloodlineState.MODULE_KEY

## The three published purity tiers. These are the ladder the constants are derived
## outward from: each threshold sits strictly inside `(FLOOR, 0.745]`, so each is worth
## exactly one more generation than the tier below it.
const TIER_FOUNDING := 0.72
const TIER_RARE := 0.55
const TIER_COMMON := 0.42


## Attach the module to `actor`. Restores any ledger a prior `Actor.from_dict` carried,
## normalizes it against the current catalog, re-projects every lineage it names, and
## registers the provider. Idempotent, and safe to call on an actor that carries nothing.
##
## No default lineage is invented: an actor with no bloodline is an ordinary actor, and
## minting one here would make every actor in the game quietly blooded.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	# Registering the provider twice is harmless: a provider's contribution replaces
	# its own stat rather than accumulating (ADR 0026), and both copies read the same
	# component. Reusing the slot keeps a re-attach from leaking instances.
	var provider := actor.component(_PROVIDER_COMPONENT) as BloodlineProvider
	if provider == null:
		provider = BloodlineProvider.new()
		actor.set_component(_PROVIDER_COMPONENT, provider)
		actor.stats.add_provider(provider)
	var ledger := BloodlineState.normalize(actor.get_module_data(MODULE_KEY), _known_bloodlines())
	actor.set_module_data(MODULE_KEY, ledger)
	BloodlineProjection.apply(actor, ledger)


## The concentration `actor` carries for `lineage_id`, in `[0, 1]`. 0.0 for an actor
## that carries none — absence is zero concentration, not a missing key, so a consumer
## never has to test for absence first.
static func purity_of(actor: Actor, lineage_id: StringName) -> float:
	return BloodlineGate.purity_of(actor, lineage_id)


## Every lineage `actor` currently carries awakened, canonically ordered. The awake set
## is what gated content reads, and it is read from the ledger rather than from a stat
## because a stat can be item-granted and a lineage power must not be.
static func awake(actor: Actor) -> Array[StringName]:
	return BloodlineGate.awake(actor)


## Whether `lineage_id` has crossed its authored awaken threshold for `actor`.
## False for a lineage this build does not ship: content nothing defines must not gate
## content.
static func is_awake(actor: Actor, lineage_id: StringName) -> bool:
	return BloodlineGate.is_awake(actor, lineage_id)


## The purity tier `purity` falls in: `founding`, `rare`, `common`, or `dormant` below
## the common bar. The read a lineage screen shows, and the function that keeps the
## thresholds in exactly one place.
static func rank_tier(purity: float) -> StringName:
	if purity >= TIER_FOUNDING:
		return &"founding"
	if purity >= TIER_RARE:
		return &"rare"
	if purity >= TIER_COMMON:
		return &"common"
	return &"dormant"


## Set `lineage_id`'s concentration for `actor` and re-project. Returns false —
## changing nothing — for an actor or a lineage the catalog does not ship, because a
## lineage nothing defines grants nothing and gates nothing.
##
## **Authoring and conception only. Gameplay must never raise purity** (ADR 0063):
## purity decays within a life and is raised only by being born to purer parents.
static func set_purity(actor: Actor, lineage_id: StringName, value: float) -> bool:
	if actor == null:
		return false
	var def := BloodlineCatalog.instance().bloodline_definition(lineage_id)
	if def == null:
		return false
	var ledger := BloodlineState.with_purity(
		BloodlineState.normalize(actor.get_module_data(MODULE_KEY), _known_bloodlines()),
		lineage_id,
		value
	)
	actor.set_module_data(MODULE_KEY, ledger)
	BloodlineProjection.apply(actor, ledger)
	return true


## The concentration a child of `parent_a` and `parent_b` carries for one lineage. The
## single-lineage form of `resolve_inherited`, for a caller that already knows which
## lineage it is asking about.
static func inherit_from(parent_a: Actor, parent_b: Actor, lineage_id: StringName) -> float:
	return BloodlineState.inherit(
		BloodlineGate.purity_of(parent_a, lineage_id), BloodlineGate.purity_of(parent_b, lineage_id)
	)


## The full `{lineage_id: purity}` map a child of `parent_a` and `parent_b` is born
## with. **This is what the birth system calls.**
##
## The union of both parents' lineages is blended in one pass, so a lineage only one
## parent carries still counts — as a dilution, which is the entire point. A lineage
## neither parent carries is absent rather than present as 0.0, because a child has no
## such ancestry. Pure: it mutates nothing and draws no roll, so the same two parents
## always produce the same child, which is what makes conception headless-testable.
static func resolve_inherited(parent_a: Actor, parent_b: Actor) -> Dictionary:
	return BloodlineResolver.resolve(parent_a, parent_b)


## Whether gated content may open for `actor`.
##
## `requirement` is authored data, never code. It is either an empty dictionary —
## ungated, always open — or a `{verb: ..., ...}` map naming exactly one of the six
## gate verbs (`is_awake`, `purity_at_least`, `has_trait`, `all_of`, `any_of`,
## `none_of`).
##
## Returns `{ok: bool, reason: String, unmet: Array[Dictionary]}` where each unmet entry
## is `{kind, id, required, actual, label}` — the same shape `ItemRequirement.unmet()`
## produces, so a panel can render a reason it did not have to invent. `ok` is the whole
## answer; the rest is for display. An unknown verb refuses closed and names itself.
static func unmet(actor: Actor, requirement: Dictionary) -> Dictionary:
	return BloodlineGate.evaluate(actor, requirement)


## A read-only, primitive-only snapshot built for a character or lineage screen: what
## this actor carries, how concentrated each lineage is, which are awake, and what the
## whole tree offers.
##
## One call answers the whole screen, so the facade needs no separate catalog accessor
## for the UI. `has_actor` is false and the lineage block is empty when there is no
## actor, which is the contract a panel tests instead of pixels.
static func summary(actor: Actor) -> Dictionary:
	var catalog := BloodlineCatalog.instance()
	var out := {
		"has_actor": actor != null,
		"actor_id": "" if actor == null else String(actor.id),
		"lineages": {},
		"lineage_count": 0,
		"awakened": [],
		"awakened_count": 0,
		"peak_purity": 0.0,
		"mean_purity": 0.0,
		"bloodline_power": 0.0,
		"tier": "",
		"bloodlines": {},
	}
	var ledger := BloodlineState.normalize(
		BloodlineState.empty() if actor == null else actor.get_module_data(MODULE_KEY)
	)
	for lineage_id in BloodlineState.lineage_ids(ledger):
		var purity := BloodlineState.purity(ledger, lineage_id)
		var def := catalog.bloodline_definition(lineage_id)
		out["lineages"][String(lineage_id)] = {
			"id": String(lineage_id),
			"purity": purity,
			"tier": String(rank_tier(purity)),
			"awake": def != null and def.is_awake(purity),
			"known": def != null,
			"display_name": "" if def == null else def.display_name,
		}
	out["awakened"] = _strings(BloodlineState.awake_ids(ledger))
	out["lineage_count"] = out["lineages"].size()
	out["awakened_count"] = (out["awakened"] as Array).size()
	out["peak_purity"] = BloodlineState.peak(ledger)
	out["mean_purity"] = BloodlineState.mean(ledger)
	out["tier"] = String(rank_tier(BloodlineState.peak(ledger)))
	if actor != null:
		var resolved := actor.component(BloodlineProjection.SUMMARY_COMPONENT) as BloodlineSummary
		if resolved != null:
			out["bloodline_power"] = clampf(
				resolved.bloodline_power, 0.0, BloodlineProvider.MAX_BLOODLINE_POWER
			)
	# Every authored lineage is listed whatever the actor is, so a screen can show what
	# is available without a second call; `held` is the only thing that differs.
	var held := BloodlineState.lineage_ids(ledger)
	for lineage_id in catalog.bloodline_ids():
		var authored := catalog.bloodline_definition(lineage_id)
		if authored == null:
			continue
		out["bloodlines"][String(lineage_id)] = {
			"id": String(lineage_id),
			"held": held.has(lineage_id),
			"display_name": authored.display_name,
			"description": authored.description,
			"awaken_threshold": authored.awaken_threshold,
			"tier": String(rank_tier(authored.awaken_threshold)),
			"crosses_races": authored.race_id == &"",
			"race_id": String(authored.race_id),
			"traits": _strings(authored.traits),
			"tags": _strings(authored.tags),
		}
	return out


## The actor's versioned ledger exactly as core persists it. This is the payload a save
## carries, so a caller never reaches into `actor.module_data`.
static func state(actor: Actor) -> Dictionary:
	if actor == null:
		return BloodlineState.empty()
	return BloodlineState.normalize(actor.get_module_data(MODULE_KEY), _known_bloodlines())


## Every authored lineage id, canonically ordered.
static func bloodline_ids() -> Array[StringName]:
	return BloodlineCatalog.instance().bloodline_ids()


# --- Internals ---------------------------------------------------------------


static func _known_bloodlines() -> Dictionary:
	var out := {}
	for lineage_id in BloodlineCatalog.instance().bloodline_ids():
		out[String(lineage_id)] = true
	return out


static func _strings(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
