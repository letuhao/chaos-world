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
## ## Membership moves REGARD, the same way `sect` and `nation` do
##
## Joining and leaving apply an AUTHORED institutional cause to the bond between the
## actor and the house's id, through `social` (ADR 0091, BL-0200). That is the whole of
## the advantage a house confers: an opinion the world holds about you there, with a
## cause ledger behind it so a save can explain it. It is a recognition, and it is the
## third leg of one mechanism `sect` and `nation` already had two legs of.
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
## The facade is held to its fan-in budget (`rules.MAX_FACADE_FAN_IN`), so anything
## a panel or a sibling module needs that is not a verb below lives on `ClanGate` or
## `ClanCatalog` behind a verb, never as another published method.

## The stat-provider component slot. Underscored because it is wiring, not a question.
const _PROVIDER_COMPONENT := &"clan_provider"
## `actor.module_data` key the versioned ledger is persisted under (ADR 0027).
const MODULE_KEY := ClanState.MODULE_KEY

## ## `social`, reached as exactly one `res://` edge
##
## Membership moves the world's opinion of the actor at a house (ADR 0091), and `clan`
## owns no regard number of its own — a float written here would be a SECOND copy of
## one fact, which `AGENTS.md` calls out by name as the ADR 0066 failure mode. So it
## asks `social` to apply an authored cause and `social` owns the arithmetic, the cause
## ledger and the projection into `SocialState.regard`.
##
## ## Why `SOCIAL_FACADE` and never a bare `SocialApi`
##
## `BARE_REF_UNITS` is `{ui, app, contracts}` — `modules/*` is excluded, so a bare
## class reference out of `modules/clan/` would report ZERO violations and a
## `clan -> social` cycle would be invisible to `_find_cycle` (ADR 0083). The `preload`
## below is the single `res://` edge the resolver DOES read, and
## `test_clan_social_edge.gd` greps the whole module for a bare `Social[A-Z]` class
## name outside it, so the invisible cycle cannot be written quietly.
const SOCIAL_FACADE := preload("res://src/modules/social/api.gd")

## ## The authored causes membership moves regard BY
##
## Ids in `social`'s catalog, reached as plain strings through the preload above — the
## same shape `SectApi.CAUSE_SWORN` and `NationApi.CAUSE_LIVED` use. Naming them here
## rather than spelling literals at the call sites is what lets a test assert the
## shipped catalog really does carry them, which is what turns `_regard`'s silence into
## a red test rather than an invisible one.
##
## There is deliberately no `expelled_from_clan`: `ClanApi` publishes no expulsion verb,
## so authoring a cause no call site can apply is the inert-vocabulary defect ADR 0076's
## catalog exists to prevent. The catalog says so at `social_cause_catalog.gd:329`.
const CAUSE_SWORN := &"sworn_to_a_clan"
const CAUSE_LEFT := &"left_a_clan"


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
	# ## The kind row is registered HERE, on attach, and not on some rarer verb
	#
	# `sect` registers lazily from `SectFounding.registry()`, which only `SectApi.found`
	# reaches — so **a plain `join` there reads an unregistered kind** until somebody
	# founds a sect. That is inherited, not designed: it works only because nothing in `sect`
	# asks the registry outside founding yet, and it is one call site away from refusing a
	# join `unknown_kind`. A clan has NO founding verb to hang it on, so the same trick would
	# never register the row at all; `attach` is the seam instead, because it is the one
	# verb EVERY actor reaches and a membership question asked before any `attach` is a
	# question about an actor this module has never seen.
	ClanFounding.registry()
	var ledger := ClanState.normalize(actor.get_module_data(MODULE_KEY), _known_clans())
	actor.set_module_data(MODULE_KEY, ledger)
	ClanProjection.apply(actor, ledger)


## May a clan be brought into being by an actor? **Always no, and that is a fact about the
## kind rather than a missing feature.**
##
## `{ok: true, can_found: false, reason: ""}` for a registered `clan` and
## `{ok: false, reason: "unknown_kind", can_found: false}` for one this boot never
## registered — the honest difference between "this kind cannot be founded" (ADR 0083's
## third state, here a settled `false`) and "there is no such kind" (its first). A bare
## `false` would collapse two opposite actions into one, and a registry that defaulted a
## missing kind to "yes" would let a profile invent an institution of a type nothing defines.
##
## Published because the capability READ is the only reason the registry row exists, and a
## row nothing reads is the inert-vocabulary defect ADR 0076's catalog exists to prevent.
static func can_found() -> Dictionary:
	var found := ClanFounding.registry().has_capability(
		ClanFounding.KIND, ClanFounding.CAP_IS_BORN_TO
	)
	if not bool(found["ok"]):
		return {"ok": false, "reason": String(found["reason"]), "can_found": false}
	return {"ok": true, "reason": "", "can_found": not bool(found["has"])}


## Admit `actor` to `clan_id` and project the membership. Returns the gate verdict
## `{ok, reason, unmet}`.
##
## **Refuses when `admission_unmet` is non-empty, and changes nothing when it does** —
## an actor turned away leaves with exactly the ledger it arrived with. Refusing a
## typo'd clan id is the same path, so content nothing defines can never admit anyone.
##
## A new member starts at the clan's entry rank and at the standing passed in (0 by
## default): joining is not earning. Nothing about joining makes the actor stronger.
##
## ## And it moves REGARD, and nothing else
##
## The admission is an authored institutional cause applied to the bond between this
## actor and this house's id, so the world now holds a named opinion about the actor
## there and a save can explain it. It does **not** touch `standing` — a new member is
## recognised, not respected, which is the two-part split ADR 0064 is built on — and
## the cause is applied at `scale` = the member's recognition factor, which is ADR
## 0064's hinge: a carrier of the founder's line is known to their house as what they
## are, and an admitted diluted member is recognised without being weightier for it.
##
## ## THE ORDER IS THE WHOLE BRIDGE, and it is load-bearing
##
## `_regard` is called AFTER `set_module_data` and `ClanProjection.apply` have landed,
## because `ClanGate.recognition_scale` reads the membership back off the ledger: its
## no-house branch answers 1.0. Read one line earlier the scale would be the
## UNWEIGHTED default and every member of every house would be admitted at full
## strength, silently deleting the hinge — and, because the two differ by only a
## factor, every magnitude assertion would still pass. `test_clan_recognition_hinge.gd`
## holds both ends of the curve for exactly that reason.
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
	_regard(actor, clan_id, CAUSE_SWORN, ClanGate.recognition_scale(actor))
	return {"ok": true, "reason": "", "unmet": []}


## Leave the clan. Returns false — changing nothing — for an actor who belongs to none.
##
## Standing does not survive the membership: it was earned INSIDE this house, and
## leaving is how a house loses its claim. A disgraced member is the case ADR 0064 is
## built around, and it is reached by losing standing first and leaving after, not by
## keeping a number with no clan attached to it.
##
## ## It moves REGARD down, by a DIFFERENT cause from `join`
##
## `CAUSE_LEFT` is a different act from being cast out and has to read as one, exactly
## as it does on `SectApi.leave` (ADR 0083: leaving is always permitted and always
## costs, and the cost is the standing). `ClanApi` publishes no expulsion verb, so
## there is no expelling counterpart here and no cause that a call site cannot reach.
##
## The house id is read off `ledger` BEFORE the strip for the reason `strip` is first
## below: once `module_data` is cleared there is no clan left to name a row against.
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
	_regard(actor, ClanState.clan_id(ledger), CAUSE_LEFT)
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
## ungated, always open — or a `{verb: ..., ...}` map naming exactly one of the eight
## gate verbs (`is_clan`, `has_rank`, `standing_at_least`, `recognised_at_least`,
## `has_trait`, `all_of`, `any_of`, `none_of`).
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
		"recognition": 0.0,
		"recognition_scale": 1.0,
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
	# ADR 0064's hinge, published beside the raw standing it re-reads, so a screen can
	# show a member "recognised at 30 of 40" and WHY the two differ — the factor is the
	# member's own concentration in this house's founding line, and it is the same number
	# `social` was handed when the admission was recorded. Outside the `def != null` block
	# on purpose: a member of content the catalog no longer ships still has the ledger,
	# and the reading is still the honest one.
	out["recognition"] = ClanGate.recognised_of(actor)
	out["recognition_scale"] = ClanGate.recognition_scale(actor)
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


## ## THE ONE place this module moves `regard`, and it moves nothing else
##
## `clan` holds no regard number, no regard ledger and no regard increment: it asks
## `social` to apply an AUTHORED cause to the bond between `actor` and `clan_id`
## (ADR 0091), and `social` owns the arithmetic, the cause ledger and the projection.
## That is what stops the three tiers growing a second copy of one fact — the ADR
## 0066 failure mode `AGENTS.md` calls out by name.
##
## ## Through `SOCIAL_FACADE`, never a bare social class name
##
## `BARE_REF_UNITS` excludes `modules/*`, so a bare class reference here would report
## zero violations and a `clan -> social` cycle would be invisible to `_find_cycle`
## (ADR 0083). The `preload` at the top of this file is the single `res://` edge the
## resolver does read, and `test_clan_social_edge.gd` greps the module for any bare
## `Social[A-Z]` name outside it.
##
## Underscore-prefixed, so it does **not** widen the facade's published surface —
## which is why ADR 0083's answer to a full facade, a component named beside it, applies
## here rather than a newly published method.
##
## ## The scale is ADR 0064's hinge, and it is a READ of purity
##
## `apply_cause`'s fourth argument attenuates a cause without authoring a second id,
## and this is what it is for: a house recognises its members in proportion to how much
## of the founder's line they actually carry. So a carrier is recorded at full weight, a
## diluted member at less, and a member of a house that claims no founding line at the
## `UNSCALED` floor — the act happened, so it is recorded at all.
##
## ## `leave` passes NO scale, and that is deliberate
##
## `join` is weighed by the hinge; leaving is not. The departure is an act in its own
## right, and its cost must not be a function of the lineage of a membership that is
## over — a diluted member walking out of a house is still walking out of it.
## `test_clan_regard_bridge.gd` asserts the weight this leaves behind, so a later change
## here is a red test.
##
## **This scales a recognition and never a stat.** `apply_cause` writes a `SocialBond`
## axis; the character sheet is not touched anywhere on this path, which is what keeps
## ADR 0064's rule — a clan grants recognition, never power — a property of the code
## rather than a promise in a docstring. `test_clan_grants_no_power.gd` reads the
## derived combat stats across a join to hold it.
##
## ## Silence is a refusal, not a swallowed error
##
## `apply_cause` refuses an unknown cause rather than moving nothing quietly, and it
## may legitimately refuse: an actor with no social state at all, or a `clan_id` that is
## empty. Neither is a state this module can fix and neither should abort a membership
## change — so the result is ignored here, and the property that makes it safe is that
## **every call site is past its own refusals**, so a refusal can only mean the cause
## catalog does not ship this id. `test_clan_regard_bridge.gd` asserts the shipped
## catalog does, which turns that silent path into a failed test rather than an
## invisible one.
static func _regard(actor: Actor, clan_id: StringName, cause_id: StringName, scale := 1.0) -> void:
	if actor == null or clan_id == &"":
		return
	SOCIAL_FACADE.apply_cause(actor, clan_id, cause_id, scale)


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
