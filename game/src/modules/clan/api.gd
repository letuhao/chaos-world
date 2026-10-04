class_name ClanApi
extends RefCounted

## Public facade for the `clan` module (ADR 0064). Other modules may reference ONLY this
## file (`api.gd`). Concrete implementations live beside this file and are wired in
## `app/`.
##
## ## A clan is a standing with obligations, not a stat stick
##
## It answers *who are your people*, *what position do you hold there*, *what have you
## earned* and *what do you owe them* — never a delta a character sheet has to diff.
## Membership is a first-class actor fact and is NOT `Actor.faction` (ADR 0047):
## faction is the political alignment, clan is the family. An actor may belong to no
## clan, and that is the normal starting state.
##
## ## A clan grants recognition, never power
##
## Nothing here grants a `StatModifier`, a base attribute or a combat stat. The
## founding bloodline is read on a member as a **standing multiplier** by the social
## layer, never as a stat the clan hands out. So a member of a high-standing clan with
## a diluted bloodline is a legitimate and interesting character: the clan recognises
## them, the lineage does not empower them. **That gap is the point of the module.**
##
## ## Standing and rank are two numbers, and rank is not derived from standing
##
## `move_standing` can move earned standing UP **and DOWN** — it is the only standing
## writer, because the social layer that settles obligations is deliberately not built
## yet. Rank is authored and stored independently, so a member can hold `head` on
## nothing but standing. Any code that recomputes one from the other has deleted the
## politics ADR 0064 exists to leave room for.
##
## ## Clan is born from bloodline and never writes back to it
##
## Admission may require a purity threshold, but passing never raises purity
## (ADR 0063). A clan cannot manufacture a lineage it does not have.
##
## The facade is at its twelve-method cap, so anything a panel or a sibling module
## needs that is not a verb below lives on `ClanGate` or `ClanCatalog` behind a verb,
## never as a thirteenth method.

## The stat-provider component slot. Underscored because it is wiring, not a question.
const _PROVIDER_COMPONENT := &"clan_provider"
## `actor.module_data` key the versioned ledger is persisted under (ADR 0027).
const MODULE_KEY := ClanState.MODULE_KEY


## Attach the module to `actor`. Restores any ledger a prior `Actor.from_dict` carried,
## normalizes it against the current catalog, re-projects the membership it names, and
## registers the provider. Idempotent, and safe to call on an actor that belongs to no
## clan.
##
## No clan is invented: an actor with no clan is an ordinary actor, and minting one
## here would make every actor in the game quietly a member of a house.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	# Registering the provider twice is harmless: a provider's contribution replaces
	# its own stat rather than accumulating (ADR 0026), and both copies read the same
	# component. Reusing the slot keeps a re-attach from leaking instances.
	var provider := actor.component(_PROVIDER_COMPONENT) as ClanProvider
	if provider == null:
		provider = ClanProvider.new()
		actor.set_component(_PROVIDER_COMPONENT, provider)
		actor.stats.add_provider(provider)
	var ledger := ClanState.normalize(actor.get_module_data(MODULE_KEY), _known_clans())
	actor.set_module_data(MODULE_KEY, ledger)
	ClanProjection.apply(actor, ledger)


## Admit `actor` to `clan_id` and project the membership. Returns the gate verdict
## `{ok, reason, unmet}`.
##
## **Refuses when `admission_unmet` is non-empty, and changes nothing when it does** —
## an actor turned away leaves with exactly the ledger it arrived with. Refusing a
## typo'd clan id is the same path, so content nothing defines can never admit anyone.
##
## A new member starts at the clan's entry rank and at the standing passed in (0 by
## default): joining is not earning. Nothing about joining makes the actor stronger.
static func join(actor: Actor, clan_id: StringName, standing: int = 0) -> Dictionary:
	if actor == null:
		return ClanGate.evaluate(null, {"verb": &"is_clan", "id": String(clan_id)})
	var unmet := admission_unmet(actor, clan_id)
	if not unmet.is_empty():
		return {"ok": false, "reason": "unmet", "unmet": unmet}
	var def := ClanCatalog.instance().clan_definition(clan_id)
	var ledger := ClanState.with_membership(_ledger(actor), clan_id, standing)
	# The entry rank comes from the definition rather than a literal, so a clan that
	# publishes a different ladder still admits into its own bottom rung.
	if def != null:
		ledger["rank"] = String(def.entry_rank())
	actor.set_module_data(MODULE_KEY, ledger)
	ClanProjection.apply(actor, ledger)
	return {"ok": true, "reason": "", "unmet": []}


## Leave the clan. Returns false — changing nothing — for an actor who belongs to none.
##
## Standing does not survive the membership: it was earned INSIDE this house, and
## leaving is how a house loses its claim. A disgraced member is the case ADR 0064 is
## built around, and it is reached by losing standing first and leaving after, not by
## keeping a number with no clan attached to it.
static func leave(actor: Actor) -> bool:
	if actor == null:
		return false
	var ledger := _ledger(actor)
	if not ClanState.is_member(ledger):
		return false
	# Strip FIRST, then clear. `ClanProjection.apply` strips internally and recovers
	# which mirrors to remove from what is still on the actor, so overwriting
	# `module_data` before that strip would strand the `clan:<id>` and
	# `clan_rank:<rank>` traits with nothing left to take them back off.
	ClanProjection.strip(actor)
	actor.set_module_data(MODULE_KEY, ClanState.empty())
	ClanProjection.apply(actor, ClanState.empty())
	return true


## The actor's clan id, or `&""` when it belongs to none.
static func clan_of(actor: Actor) -> StringName:
	return ClanGate.clan_of(actor)


## The earned standing the actor holds inside their clan. 0 for a non-member: absence
## is zero standing, not a missing key, so a consumer never tests for absence first.
static func standing_of(actor: Actor) -> int:
	return ClanGate.standing_of(actor)


## The position the actor holds, or `&""`. Read from the ledger and never recomputed
## from standing — that gap is the politics.
static func rank_of(actor: Actor) -> StringName:
	return ClanGate.rank_of(actor)


## Move earned standing by `delta` and return the new total. Symmetric: it can go UP
## **and DOWN**, and it floors at zero.
##
## **This is the only standing writer in the module.** It deliberately does NOT settle
## `patronage` or `duty` — the clan publishes the terms, and the social layer that
## pays them lands later (ADR 0064). It returns 0, having changed nothing, for an
## actor who belongs to no clan: standing is earned inside a house, so there is nothing
## to move.
##
## **A null actor is safe, and the guard is this module's house rule rather than a
## special case.** `join`, `leave`, `attach`, `state` and `summary` all refuse a null
## actor by name, so this verb returning `0` without touching the ledger is the
## ordinary reading, not a gap. It was not: `_ledger(null)` already returns the empty
## ledger, so the missing `if` looked harmless — but the line below dereferences
## `actor`, and a caller asking "what would this cost them" about nobody gets a
## runtime error instead of a number. Every sibling verb above checks.
static func move_standing(actor: Actor, delta: int) -> int:
	if actor == null:
		return 0
	var ledger := ClanState.with_standing(_ledger(actor), delta)
	actor.set_module_data(MODULE_KEY, ledger)
	ClanProjection.apply(actor, ledger)
	return ClanState.standing(ledger)


## Whether gated content may open for `actor`.
##
## `requirement` is authored data, never code. It is either an empty dictionary —
## ungated, always open — or a `{verb: ..., ...}` map naming exactly one of the seven
## gate verbs (`is_clan`, `has_rank`, `standing_at_least`, `has_trait`, `all_of`,
## `any_of`, `none_of`).
##
## Returns `{ok: bool, reason: String, unmet: Array[Dictionary]}` where each unmet entry
## is `{kind, id, required, actual, label}` — the same shape `ItemRequirement.unmet()`
## produces, so a panel can render a reason it did not have to invent. `ok` is the whole
## answer; the rest is for display. An unknown verb refuses closed and names itself.
static func unmet(actor: Actor, requirement: Dictionary) -> Dictionary:
	return ClanGate.evaluate(actor, requirement)


## A read-only, primitive-only snapshot built for a character or clan screen: who this
## actor's people are, what position they hold, how far that position sits from what
## their standing publishes, and the terms on both sides of the ledger.
##
## One call answers the whole screen, so the facade needs no separate catalog accessor
## for the UI. `has_actor` is false and the membership block is empty when there is no
## actor, which is the contract a panel tests instead of pixels. **`patronage` and
## `duty` are published in full** so a screen can render obligations without a second
## call — which is the whole point of the clan publishing terms rather than collecting
## them.
static func summary(actor: Actor) -> Dictionary:
	var catalog := ClanCatalog.instance()
	var out := {
		"has_actor": actor != null,
		"actor_id": "" if actor == null else String(actor.id),
		"clan": "",
		"known": false,
		"display_name": "",
		"rank": "",
		"rank_index": -1,
		"rank_count": 0,
		"standing": 0,
		"band_rank": "",
		"band_count": 0,
		"outranks_standing": false,
		"founding_bloodline": "",
		"founding_purity": 0.0,
		"min_purity": 0.0,
		"patronage": {},
		"duty": {},
		"patronage_tier": 0.0,
		"rivals": [],
		"clan_count": 0,
		"clans": {},
	}
	if actor == null:
		return out
	var resolved := actor.component(ClanProjection.SUMMARY_COMPONENT) as ClanSummary
	if resolved != null:
		out["clan"] = String(resolved.clan_id)
		out["known"] = resolved.known
		out["display_name"] = resolved.display_name
		out["rank"] = String(resolved.rank)
		out["rank_index"] = resolved.rank_index
		out["rank_count"] = resolved.rank_count
		out["standing"] = resolved.standing
		out["band_rank"] = String(resolved.band_rank)
		out["band_count"] = resolved.band_count
		out["outranks_standing"] = resolved.outranks_standing()
		out["patronage_tier"] = clampf(resolved.patronage_tier, 0.0, ClanSummary.MAX_PATRONAGE_TIER)
	var def := ClanCatalog.instance().clan_definition(ClanState.clan_id(_ledger(actor)))
	if def != null:
		out["founding_bloodline"] = String(def.founding_bloodline)
		out["min_purity"] = def.min_purity
		if def.founding_bloodline != &"":
			out["founding_purity"] = BloodlineApi.purity_of(actor, def.founding_bloodline)
		out["patronage"] = _terms(def.patronage)
		out["duty"] = _terms(def.duty)
		out["rivals"] = _strings(def.rival_clans)
	# Every authored clan is listed whatever the actor is, so a screen can compare houses
	# and read who is hostile to whom without a second call; `held` is the only thing
	# that differs. `admission_unmet` is deliberately NOT called here — it is a gate,
	# and a screen can ask it for the house a player is looking at, not for every house
	# in the world.
	var held := ClanState.clan_id(_ledger(actor))
	for clan_id in catalog.clan_ids():
		var authored := catalog.clan_definition(clan_id)
		if authored == null:
			continue
		var view := _view(authored)
		view["held"] = clan_id == held
		out["clans"][String(clan_id)] = view
	out["clan_count"] = (out["clans"] as Dictionary).size()
	return out


## The actor's versioned ledger exactly as core persists it. This is the payload a save
## carries, so a caller never reaches into `actor.module_data`.
static func state(actor: Actor) -> Dictionary:
	if actor == null:
		return ClanState.empty()
	return ClanState.normalize(actor.get_module_data(MODULE_KEY), _known_clans())


## Every authored clan id, canonically ordered.
static func clan_ids() -> Array[StringName]:
	return ClanCatalog.instance().clan_ids()


## "May this actor be admitted to `clan_id`", as `{kind, id, required, actual, label}`
## entries. Empty means the admission is open. The array is a list of complaints, so a
## caller asks "is this empty" and never has to know how many rules the clan authored.
static func admission_unmet(actor: Actor, clan_id: StringName) -> Array[Dictionary]:
	return ClanGate.admission_unmet(actor, clan_id)


# --- Internals ---------------------------------------------------------------


static func _known_clans() -> Dictionary:
	var out := {}
	for clan_id in ClanCatalog.instance().clan_ids():
		out[String(clan_id)] = true
	return out


static func _ledger(actor: Actor) -> Dictionary:
	if actor == null:
		return ClanState.empty()
	return ClanState.normalize(actor.get_module_data(MODULE_KEY))


static func _view(def: ClanDef) -> Dictionary:
	return {
		"id": String(def.id),
		"held": false,
		"display_name": def.display_name,
		"description": def.description,
		"founding_bloodline": String(def.founding_bloodline),
		"ranks": _strings(def.ranks),
		"standing_bands": _ints(def.standing_bands),
		"patronage": _terms(def.patronage),
		"duty": _terms(def.duty),
		"rivals": _strings(def.rival_clans),
		"tags": _strings(def.tags),
	}


## Published terms flattened to sorted `String` keys, so a screen renders a stable list
## and a test compares a plain array. The authored VALUES are deliberately dropped:
## they are prose the social layer will one day negotiate, and publishing them as a
## number here would turn an obligation into a dial.
static func _terms(source: Dictionary) -> Array:
	var keys: Array = source.keys()
	keys.sort()
	return _strings_of(keys)


static func _strings(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out


static func _strings_of(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out


static func _ints(values: Array[int]) -> Array:
	var out: Array = []
	for value in values:
		out.append(value)
	return out
