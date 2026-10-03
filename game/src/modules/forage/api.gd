class_name ForageApi
extends RefCounted

## Public facade for the `forage` module. Owns the ONE verb that turns a held resource
## node into goods, and the node->item table that makes it possible.
##
## ## Why a module and not a fifth line in `holdings`
##
## The gather route is the first code in the game that crosses the custody/item line, and
## that boundary is already written down from both sides. `holdings` declares
## `["contracts", "core"]`, and `test_the_holdings_facade_names_no_inventory_verb` reads its
## facade source and fails on the four item-holding type names — so the conversion cannot
## live there and that test must keep passing. `items` owns the bag and cannot grow a
## `holdings` edge without the item authority deciding what a world object is. `economy`
## owns the numeraire and one exchange primitive (ADR 0094) and says in its own docstring
## that it was built so it never has to reach past the items facade again.
##
## So the rule sits BESIDE both and declares exactly one edge: `holdings`, reached only
## through `holdings/api.gd`. It owns the one fact neither module has — **which item a node
## yields**. `ResourceNodeDef` carries no item id and cannot be given one
## (`test_a_node_definition_names_no_item` pins that field list), which is precisely why
## `gather` had no route: nothing in `game/src` knew the answer, so no amount of wiring
## could have invented it.
##
## ## The yield table is CONTENT, and it is `gather`'s ref vocabulary
##
## [constant NODE_YIELDS] maps a node id to the item ids it produces. It is authored HERE,
## beside the only reader of the `sources` field, because `gather` is declared
## `REF_FORBIDDEN` in `ItemSources.KINDS` — an authored `gather` source names the KIND and
## no target, so a node's target cannot be read off the item. The table is a table rather
## than a rule so a node's yield is a content decision (BL-0204 applied to gathering), and a
## node nobody harvests from is a content gap rather than a crash.
##
## ## The grant is INJECTED, and this module names no item type
##
## This module declares no `items` edge. It cannot: the items facade is at its twelve-method
## cap and def resolution is `items` internals that only `app/` may name, so a
## `forage -> items` edge could only be honoured by reaching past a facade — the exact thing
## `tools arch` fails on. So the item authority arrives as the injected `Callable`
## [method set_granter], the `HoldingsApi.set_resolver` / `NpcApi.set_minter` /
## `CustodyApi.set_minter` seam this repo already uses four times, and `app/` installs it.
##
## `test_the_forage_facade_names_no_inventory_verb` reads THIS file's source text and fails
## on the same five names `holdings` is held to, which is why the paragraph above describes
## the cap and the internals rather than spelling them: the discipline this module
## documents is the discipline it is tested for.
##
## ## No clock, and none invented
##
## [method harvest] takes an explicit `periods` from the caller that owns time (DEF-0111)
## and forwards it to `HoldingsApi.accrue`, which is where depletion, upkeep and the resting
## state are decided. This module never ticks and never restates a rule holdings owns.
##
## ## The order is the atomicity
##
## 1. [method ResourceNodeDef.permits] gates the actor — a shallow actor cannot work a deep
##    node, the reason `realm` exists (ADR 0097);
## 2. `periods <= 0` refuses before anything is read, so a caller bug never costs upkeep;
## 3. a granter must be installed, or the verb refuses loudly rather than accruing yield it
##    cannot deliver (ADR 0002's null-injection rule);
## 4. custody is confirmed — the actor must actually HOLD this node — before the bag is
##    consulted, so a trespasser is told `holder_mismatch` rather than `bag_full` and is
##    never told anything about their own bag by a node that is not theirs;
## 5. the granter PROBES (`probe = true`) — it reports how many units fit without moving
##    anything — so a full bag accrues nothing;
## 6. `accrue` then `settle` move the units, and only then is the goods actually granted.
##
## A refusal names a constant and writes nothing anywhere.

# --- refusals -----------------------------------------------------------------
# `no_periods`, `realm_below_gate` and every holdings-owned id are REUSED rather than
# restated, so one `holder_mismatch` covers the whole path whatever module raised it.

## The caller passed `periods <= 0`. Holdings owns the rule; surfaced unchanged so a single
## id covers the whole accrue path.
const NO_PERIODS := HoldingsState.NO_PERIODS
## The node's `realm` band is deeper than the actor's rung on the shared ladder. ADR 0097's
## gate: realm is a gate, never a yield multiplier, and a gate that answers anything but
## `false` is not a gate.
const REALM_BELOW_GATE := HoldingsState.REALM_BELOW_GATE
## No granter is installed, so the yield could be accrued and never delivered. Refused
## loudly: a forager that silently produces nothing is the failure this module exists to end.
const NO_GRANTER := "no_granter"
## The caller passed a null actor, so there is nobody to deliver goods to or to charge.
## Distinct from every gate below: no gate is reached, because the thing that would be gated
## does not exist. Owned here rather than borrowed from `loot`'s identically-named
## `no_inventory` because the two answer different questions — that one asks whether a BAG
## is missing, this one asks whether a FORAGER is — and one id per question is the whole
## point of a refusal vocabulary a panel switches on.
const NO_ACTOR := "no_actor"
## The node yields nothing this module can name — it is absent from [constant NODE_YIELDS].
## Named, never silent, because "no item id on the node" is exactly the gap that made
## `gather` unshipped and it must never be quiet again.
const NO_YIELD_CONTENT := "no_yield_content"
## The granter refused to take the goods, and named why. The granter's own id is passed
## through verbatim rather than flattened, because only it knows what "the bag is full" is.
const GRANT_REFUSED := "grant_refused"
## The granter reported success but the unit count it moved is not what was asked for, so
## the line has been settled against a partial delivery. Refused rather than returned as a
## success: a half-harvest must read as a failure to whoever is driving it.
const GRANT_SHORT := "grant_short"

## How a node yields, keyed by node id: `{node_id: [item_id, ...]}`.
##
## Every one of the sixteen authored nodes has an entry, so an authored node nobody can
## forage is impossible by construction rather than by a test noticing later.
const NODE_YIELDS: Dictionary = {
	"foundation_yew_stand": [&"trinket_iron_charm"],
	"core_formation_mist_herb_plot": [&"T3_earth_ragwort_snips"],
	"core_formation_burrow": [&"trinket_hunt_trophy"],
	"nascent_soul_iron_adit": [&"currency_seal_token"],
	"nascent_soul_sunwood_grove": [&"currency_tribute_scroll"],
	"qi_refining_copper_seam": [&"R4_earth_loam_gizmo"],
	"qi_refining_ash_herb_bed": [&"T3_mortal_ragwort_epigram"],
	"spirit_domain_titan_ore_bed": [&"trinket_silk_charm"],
	"spirit_transformation_silver_lode": [&"trinket_jade_curio"],
	"spirit_condensation_lunar_veil_field": [&"trinket_moon_curio"],
	"spirit_sea_quiet_vein": [&"trinket_star_curio"],
	"body_integration_boar_ranch": [&"trinket_bone_charm"],
	"foundation_harvest_pen": [&"trinket_war_trophy"],
	"heaven_immortal_primordial_timber": [&"trinket_divine_trophy"],
	"primordial_origin_origin_vein": [&"trinket_luck_token"],
	"void_refinement_moonwell_spring": [&"trinket_silk_charm"],
}

static var _granter: Callable = Callable()
static var _yields: Dictionary = NODE_YIELDS


## Install the node->item table, or restore the authored one with an empty `yields`.
##
## The fourth seam of this shape in this repo (`HoldingsApi.set_resolver` /
## `set_store`, `NpcApi.set_minter`, `CustodyApi.set_minter`) and it exists for the same
## reason: [constant NODE_YIELDS] is keyed by AUTHORED node ids, so a suite that installs
## its own fixture nodes has no way to say what those fixtures yield and every verb
## assertion lands on `no_yield_content` instead of on the rule under test. That is a
## harness gap, not a content gap — and it was worth a seam rather than four fake ids in
## shipped content, which would have put `validate()`'s own audit against test fixtures.
##
## `app/` does NOT call this: production reads [constant NODE_YIELDS] as authored. An empty
## dictionary restores it, so a teardown is `set_yields({})` and there is no second way to
## leave the process on a table nobody shipped.
static func set_yields(yields: Dictionary) -> void:
	_yields = NODE_YIELDS if yields.is_empty() else yields.duplicate(true)


## The yield table in force: what was installed, or the authored one. Never empty by
## construction — an empty install restores rather than blanks, because a blank table would
## silently make every authored node un-gatherable.
static func yields() -> Dictionary:
	return _yields


## Install the item-granting half of the route. `app/` passes a callable taking
## `(actor, item_id, quantity, probe)` and answering `{ok, reason, granted}`.
##
## `probe` is the atomicity contract, and it is why this is a `Callable` rather than the
## verb granting directly. Called with `probe = true` it must report how many units COULD be
## delivered without moving anything, so a bag with no room refuses `forage` before the node
## is accrued and before upkeep is charged. Called with `probe = false` it must move exactly
## what it reported.
static func set_granter(granter: Callable) -> void:
	_granter = granter


## Whether an item-granting callable is installed. A read a caller can ask BEFORE calling,
## so a screen can disable a forage button rather than discovering the gap by clicking it.
static func has_granter() -> bool:
	return _granter.is_valid()


## Work `node_id` for `periods` periods and put the yield in `actor`'s bag.
##
## `owner` is the `OwnerRef` dictionary the holder is recorded under —
## `{"kind":"actor","id":"<actor id>"}` — exactly what `HoldingsApi.claim` was given, because
## that is the thing `accrue` compares against the ledger's holder. `periods` is REQUIRED
## and never defaulted: there is no clock here (DEF-0111) and a defaulted period is an
## invented tick.
##
## Returns `{ok, reason, node_id, item_id, periods, yielded, granted, accrued, condition}`.
## Every refusal carries a named constant and leaves the ledger, the bag and the node exactly
## as they were — except [constant GRANT_SHORT], which names itself in its own docstring
## because it is the one branch that reports a partial outcome rather than none.
static func harvest(
	actor: Actor, node_id: StringName, owner: Dictionary, periods: int
) -> Dictionary:
	var node := ResourceNodeCatalog.instance().definition(node_id)
	if node == null:
		# `unknown_node` is holdings' vocabulary; surfaced unchanged so one id means one fact
		# rather than letting this module invent a near-synonym no caller can switch on.
		return _refuse(node_id, HoldingsState.UNKNOWN_NODE)
	if actor == null or not node.permits(actor.realm()):
		return _refuse(node_id, REALM_BELOW_GATE)
	if periods <= 0:
		return _refuse(node_id, NO_PERIODS)
	if not _granter.is_valid():
		return _refuse(node_id, NO_GRANTER)
	var item_id := _yield_item(node_id)
	if item_id == &"":
		return _refuse(node_id, NO_YIELD_CONTENT)
	# Custody FIRST, before the bag is consulted at all. `accrue` would decide the same
	# thing a few lines down, but by then the granter has already been asked what fits in
	# this actor's bag for a node that is not theirs — which both leaks a fact about a
	# stranger's inventory and would report a trespass as `bag_full`, an error the caller
	# cannot act on. Decided from the same ledger `accrue` reads, so the two cannot disagree.
	var custody := _holds(actor, node_id, owner)
	if custody != "":
		return _refuse(node_id, custody)
	# Probe before ANY mutation. `node_resting` and `depleted` are decided by accrue, which
	# runs next; asking the bag first keeps a full bag from being reported as a custody
	# failure the caller cannot act on.
	var room := _call_granter(actor, item_id, maxi(1, node.yield_per_period), true)
	if not bool(room["ok"]):
		return _refuse(node_id, String(room["reason"]))
	if int(room["granted"]) <= 0:
		return _refuse(node_id, GRANT_REFUSED)
	var accrued := HoldingsApi.accrue(actor, node_id, owner, periods)
	if not bool(accrued["ok"]):
		return _refuse(node_id, String(accrued["reason"]))
	var units := int(accrued["yielded"])
	if units <= 0:
		return _refuse(node_id, GRANT_REFUSED)
	# Settle the line the units came from BEFORE granting them, so the ledger and the bag
	# can never both claim the same units. `settle` is all-or-nothing by construction.
	var settled := HoldingsApi.settle(actor, node_id, units)
	if not bool(settled["ok"]):
		return _refuse(node_id, String(settled["reason"]))
	var granted := _call_granter(actor, item_id, units, false)
	if not bool(granted["ok"]) or int(granted["granted"]) != units:
		var out := _refuse(node_id, GRANT_REFUSED if not bool(granted["ok"]) else GRANT_SHORT)
		out["granted"] = maxi(0, int(granted["granted"]))
		return out
	return {
		"ok": true,
		"reason": "",
		"node_id": String(node_id),
		"item_id": String(item_id),
		"periods": periods,
		"yielded": units,
		"granted": units,
		"accrued": int(accrued["accrued"]),
		"condition": int(accrued["condition"]),
	}


## Whether `actor` holds `node_id` under `owner`, as the ids `accrue` itself uses.
##
## Returns `""` when the custody is good, and holdings' OWN refusal id when it is not —
## `no_holder` for a vein nobody holds, `holder_mismatch` for someone else's. Restated
## rather than invented so one id means one fact whichever module surfaced it, and read
## through `HoldingsApi.summary` rather than the raw ledger so this module never reaches
## into a state shape `holdings` owns.
static func _holds(actor: Actor, node_id: StringName, owner: Dictionary) -> String:
	var summary := HoldingsApi.summary(actor)
	var nodes: Dictionary = summary.get("nodes", {}) as Dictionary
	if not nodes.has(String(node_id)):
		return HoldingsState.NO_HOLDER
	var entry: Dictionary = nodes[String(node_id)] as Dictionary
	var held: Dictionary = entry.get("owner", {}) as Dictionary
	if OwnerRef.is_vacant(held) or held.is_empty():
		return HoldingsState.NO_HOLDER
	if String(held.get("id", "")) != String(owner.get("id", "")):
		return HoldingsState.HOLDER_MISMATCH
	return ""


## The item id `node_id` yields, or `&""` when it yields nothing.
##
## The first entry of [constant NODE_YIELDS], resolved through the granter's own content
## view so this module never has to reach into an item tree it has no edge to. A node whose
## authored id is absent from the catalog falls through to the next entry, so one bad content
## id cannot silently empty a node's yield.
static func _yield_item(node_id: StringName) -> StringName:
	for candidate in _yields.get(String(node_id), []):
		var item_id := StringName(candidate)
		if _call_granter(null, item_id, 0, true).get("known", false):
			return item_id
	return &""


## Call the granter and normalize its answer, so a granter that returns a non-dictionary
## refuses LOUDLY rather than dereferencing nothing (ADR 0002).
static func _call_granter(
	actor: Actor, item_id: StringName, quantity: int, probe: bool
) -> Dictionary:
	if not _granter.is_valid():
		return {"ok": false, "reason": NO_GRANTER, "granted": 0, "known": false}
	var answered: Variant = _granter.call(actor, item_id, quantity, probe)
	if not answered is Dictionary:
		return {"ok": false, "reason": NO_GRANTER, "granted": 0, "known": false}
	var out := (answered as Dictionary).duplicate()
	out["granted"] = maxi(0, int(out.get("granted", 0)))
	out["known"] = bool(out.get("known", false))
	out["ok"] = bool(out.get("ok", false))
	if not out.has("reason"):
		out["reason"] = ""
	return out


## Every node id with an authored yield, as `StringName`s. The read model a panel builds its
## node list from, and the honest answer to "what is forageable here".
static func yieldable_node_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for node_id in _yields.keys():
		out.append(StringName(node_id))
	out.sort()
	return out


## Content audit: every authored yield names a node that exists, and every authored node
## has a yield. A yield table entry for a node nobody authored is a content gap that would
## otherwise sit here forever, silent.
##
## ## It audits the AUTHORED corpus, not whatever the catalog currently holds
##
## Two reasons, and both are about what this method is FOR. First, `validate` answers a
## question about SHIPPED CONTENT — "does every mine this build ships name something to
## gather?" — and a suite's `ResourceNodeCatalog.install` fixtures are not shipped content,
## so counting them would report four test node ids as missing yields on every run and
## train the next reader to ignore the output. Second, `NODE_YIELDS` is authored content for
## exactly the same reason, so the two halves of the comparison must both come from the
## content tree or the comparison is meaningless.
##
## So this walks the `.tres` files itself rather than reading the shared singleton, which
## also makes it independent of any suite that installed before it.
static func validate() -> Array[String]:
	var problems: Array[String] = []
	for node_id in NODE_YIELDS.keys():
		if not _is_authored_node(node_id):
			problems.append("forage: '%s' yields an item but no such node is authored" % node_id)
	for path in _authored_nodes():
		var def := load(path) as ResourceNodeDef
		if def == null or def.node_id == &"":
			continue
		if not NODE_YIELDS.has(String(def.node_id)):
			problems.append(
				"forage: node '%s' has no authored yield, so it cannot be foraged" % def.node_id
			)
	return problems


## Every authored node `.tres`, by path. The content tree read directly, so the audit never
## sees a fixture a suite installed.
static func _authored_nodes() -> Array[String]:
	var out: Array[String] = []
	for path in ContentScan.files_under(ResourceNodeCatalog.NODES_ROOT):
		if not path.ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains(
			'script_class="%s"' % ResourceNodeCatalog.NODE_SCRIPT_CLASS
		):
			continue
		out.append(path)
	return out


## Whether `node_id` names an authored node file, independent of the live catalog.
static func _is_authored_node(node_id: String) -> bool:
	for path in _authored_nodes():
		var def := load(path) as ResourceNodeDef
		if def != null and String(def.node_id) == node_id:
			return true
	return false


static func _refuse(node_id: StringName, reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"node_id": String(node_id),
		"item_id": "",
		"periods": 0,
		"yielded": 0,
		"granted": 0,
		"accrued": 0,
		"condition": 0,
	}
