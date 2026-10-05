class_name DestinyStarterPacks
extends RefCounted

## The registry of starter packs: the authored DEFAULT every body begins with,
## and whatever a destiny path has registered in its place.
##
## ## The rule this type exists to enforce: a registered pack REPLACES the default
##
## A pack is a complete answer to "what does this body begin holding", so two
## answers to that question is a bug. [method register] overwrites the pack filed
## under a destiny id rather than merging into it, and [method resolve] returns
## ONE pack — the registered one when the body holds a destiny that has one, the
## default otherwise. There is no code path here that can hand back the union,
## which is what makes "the default is gone" a property of the type rather than a
## promise in a comment.
##
## Appending would be the obvious alternative and it is wrong twice over. A player
## who holds a registered destiny would open a bag carrying both kits, so the
## registered pack's identity — the whole reason a destiny has one — would be
## invisible; and a second registration for the same destiny would double the kit
## rather than correct it, so a fix shipped twice is a balance change nobody
## authored.
##
## ## Registration is idempotent-by-overwrite, never additive
##
## Re-registering the same destiny id is how a pack is CORRECTED. That makes the
## verb safe to run on every boot, which a merge would not be.
##
## ## Process-wide, and reset the way every other singleton here is
##
## The registry is content, not player state: it is identical before and after a
## save and needs no serialization. It is reached through [method instance] and
## reset by nulling `shared`, the same seam `FateCatalog` and every fixture
## catalog in this repo use — so a suite installs its own and restores the real
## one without a bespoke verb.
##
## ## No loops that can fail to terminate
##
## Every loop here is a `for` over [constant ROLES], over `destiny_ids` (which
## [method resolve] snapshots from a sorted key list), or over the rows a caller
## passed. `tests/arch_rules/test_no_unbounded_wait.gd` is the guard that fails
## the build if a `while` appears that it cannot show terminating.

const DEFAULT_PACK_ID := &"mortal_starter"
const DEFAULT_SOURCE := &"default"

## Refusal reasons, named so a caller reports WHICH rule it broke.
const REASON_NO_DESTINY := "no_destiny_id"
const REASON_UNKNOWN_DESTINY := "unknown_destiny_id"
const REASON_BAD_PACK := "bad_pack"

## The authored default kit: one of each role, every id a real authored
## `ItemDef`, and **every one of them grade `mortal`**.
##
## The grade is not a preference. `ItemGrade.TIER_BY_GRADE` puts `mortal` at
## tier 1 and every other grade at tier 2 or higher, a starting hero's ladder
## tier is 1, and `Equipment._meets_requirements` refuses anything above it — so
## a starter item one grade up is an item the player is handed and can never wear.
## `tests/modules/destiny/test_destiny_starter_pack.gd` resolves all four ids
## against the real catalog and asserts the grade, so a retune that raises one
## goes red here rather than at a boot probe.
##
## The two wearables (`weapon`, `armor`) are the authored non-stackable defs, so
## `ItemsApi.generate` mints them as `ItemInstance`s — which is what the
## workbench's row builder can list and what `ItemActionRules.equip_shape_reason`
## can match, both of which are instance lookups that cannot see a stack.
const DEFAULT_ROWS: Array[Dictionary] = [
	{"role": DestinyStarterPack.ROLE_WEAPON, "item_id": &"weapon_iron_sword", "count": 1},
	{"role": DestinyStarterPack.ROLE_ARMOR, "item_id": &"armor_iron_helm", "count": 1},
	{"role": DestinyStarterPack.ROLE_CONSUMABLE, "item_id": &"alchemy_clarity_pill", "count": 3},
	{"role": DestinyStarterPack.ROLE_TOKEN, "item_id": &"curr_spirit_coin", "count": 25},
]

## The one registry, or null for "not built yet" — which is how a test resets.
static var shared: DestinyStarterPacks = null

## destiny id -> `DestinyStarterPack`. A plain assignment replaces, so the
## replacement rule is the Dictionary's own semantics rather than a branch
## somebody has to remember to write.
var _registered: Dictionary = {}


static func instance() -> DestinyStarterPacks:
	if shared == null:
		shared = DestinyStarterPacks.new()
	return shared


## The authored default. Rebuilt per call rather than cached, so a suite that
## nulled `shared` cannot be handed a pack built from a table it has since
## changed, and so the returned object is never shared mutable state.
func default_pack() -> DestinyStarterPack:
	var built := DestinyStarterPack.make(DEFAULT_PACK_ID, DEFAULT_SOURCE, DEFAULT_ROWS)
	if bool(built["ok"]):
		return built["pack"] as DestinyStarterPack
	# The table above is a module constant, so a refusal here is a CONTENT bug in
	# this file and not something a caller can provoke. Answered with an empty
	# pack rather than a null every caller would have to null-check: a pack with
	# no rows is the honest shape of "nothing to hand out", and `to_dict()` still
	# describes it.
	return DestinyStarterPack.new()


## File `rows` under `destiny_id`, REPLACING whatever was there.
##
## Refuses an unknown `destiny_id` for the reason `DestinyApi.earn_fate` refuses
## an unknown fate id: a pack filed under a destiny the catalog does not ship can
## never be resolved by any body, because no body can ever hold that destiny. It
## is a content bug, and storing it would leave a dead registration that reads as
## a working one.
##
## `known_destiny` is the caller's catalog answer rather than a catalog read, so
## this type keeps no dependency on the content tree and stays testable against
## a fixture catalog.
func register(destiny_id: StringName, rows: Array, known_destiny: bool) -> Dictionary:
	if destiny_id == &"":
		return {"ok": false, "reason": REASON_NO_DESTINY}
	if not known_destiny:
		return {"ok": false, "reason": REASON_UNKNOWN_DESTINY, "destiny_id": String(destiny_id)}
	var built := DestinyStarterPack.make(destiny_id, destiny_id, rows)
	if not bool(built["ok"]):
		return {"ok": false, "reason": REASON_BAD_PACK, "detail": String(built["reason"])}
	_registered[String(destiny_id)] = built["pack"]
	return {"ok": true, "pack_id": String(destiny_id)}


## The pack filed under `destiny_id`, or null when none is.
func registered(destiny_id: StringName) -> DestinyStarterPack:
	return _registered.get(String(destiny_id)) as DestinyStarterPack


## Every registered destiny id, canonically ordered — the same ordering rule the
## ledger uses, so a caller that lists registrations and a caller that resolves
## them read in the same order.
func registered_ids() -> Array[String]:
	var out: Array[String] = []
	for key in _registered.keys():
		out.append(String(key))
	out.sort()
	return out


## THE answer to "what does a body holding `destiny_ids` begin with".
##
## Returns `{pack: DestinyStarterPack, replaced: bool, destiny_id: String}`.
## `replaced` is true exactly when a registered pack answered, which is what lets
## a caller — and a test — state that the default was displaced rather than
## added to.
##
## ## Order is canonical, not ledger order
##
## A body may hold several destinies from different exclusivity groups, and more
## than one of them may have registered a pack. The winner is the first in
## [method DestinyState.destiny_ids]' canonical order, so two reads of the same
## ledger cannot disagree and a save cannot change which kit a body gets by
## earning a destiny in a different order.
##
## The loop is a `for` over that snapshot: bounded by the number of destinies the
## ledger holds, terminating on every path, and it never grows the list it walks.
func resolve(destiny_ids: Array[StringName]) -> Dictionary:
	# Snapshot to a local array before iterating: the registry must not be able to
	# observe a list that is still being built, and a caller handing us its own
	# mutable array must not be able to change the answer mid-walk.
	var ordered := destiny_ids.duplicate()
	for destiny_id in ordered:
		var pack := registered(destiny_id)
		if pack != null:
			return {"pack": pack, "replaced": true, "destiny_id": String(destiny_id)}
	return {"pack": default_pack(), "replaced": false, "destiny_id": ""}
