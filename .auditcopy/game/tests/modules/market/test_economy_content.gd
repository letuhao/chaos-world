extends TestCase

## The two authored economy content trees, read off disk: the resource nodes under
## `res://data/holdings/nodes` and the shops under `res://data/market/shops`.
##
## ## Why this suite loads the files itself rather than trusting the catalogs
##
## `ResourceNodeCatalog` and `ShopDef` both answer from a directory scan, so a test
## that only read through them would pass on a catalog that silently dropped half the
## tree — `_ensure_loaded` skips a def it cannot load, and a skip is invisible to
## every assertion that asks the catalog what it has. So this suite walks the same
## directories with `ContentScan` and reads every `.tres` directly, and only then hands
## the nodes to the catalog to check the catalog's own gate.
##
## ## Why the field-level assertions exist at all
##
## `ResourceNodeCatalog.validate()` is deliberately narrow: it fails a zero yield and
## a kind outside the closed set, and nothing else. It cannot know whether an upkeep
## column is all zeros — which would make `upkeep_per_period` decoration — or whether a
## node names a realm the ladder does not have, which would make `permits()` refuse
## every actor forever. Those are content bugs the audit has to catch, so they are
## asserted here, over the shipped set, rather than once in a comment.
##
## ## Nothing here leaks
##
## `ResourceNodeCatalog` is a process-wide singleton, so it is reset in BOTH `setup()`
## and `teardown()`: the runner shares one process across every suite and calls
## `teardown` after each test, and a catalog left installed would hand this suite's
## fixtures to whichever holdings suite runs next.

const NODES_ROOT := ResourceNodeCatalog.NODES_ROOT
const SHOPS_ROOT := "res://data/market/shops"

## At least this many authored nodes and shops must ship. Written as a floor rather
## than an exact count so that adding a mine is content, not a test edit — but a floor
## is still a floor, because "the directory happens to be empty" is the failure this
## file exists to prevent.
const MIN_NODES := 14
const MIN_SHOPS := 5


func setup() -> void:
	ResourceNodeCatalog.instance().reset()


func teardown() -> void:
	ResourceNodeCatalog.instance().reset()


# --- The authored resource nodes ------------------------------------------------


## Every authored node file loads as a `ResourceNodeDef` and is filed under the id the
## game names it by. A renamed file whose `node_id` was not updated ships a node nothing
## can look up, and a duplicate id would let the second one silently win in the catalog.
func test_every_authored_node_file_loads_and_its_id_matches_its_file_name() -> void:
	var paths := ContentScan.files_under(NODES_ROOT)
	assert_ne(paths.is_empty(), true, "the node directory is not empty")
	assert_eq(paths.size() >= MIN_NODES, true, "at least %d nodes are authored" % MIN_NODES)
	var seen: Dictionary = {}
	for path in paths:
		var def := load(path) as ResourceNodeDef
		assert_ne(def, null, "%s loads as a ResourceNodeDef" % path)
		if def == null:
			continue
		var node_id := String(def.node_id)
		assert_eq(node_id, path.get_file().get_basename(), "'%s' is filed under its own id" % path)
		assert_eq(
			seen.has(node_id),
			false,
			"'%s' names '%s', and no other file already did" % [path, node_id]
		)
		seen[node_id] = true
		assert_ne(def.display_name, "", "'%s' is named" % node_id)


## The closed set, the positive yield, and a realm the ladder actually has. A node whose
## `realm` is not on `RealmDefaults.ladder()` answers `permits()` with `false` for every
## actor including one standing on the top rung, so it is claimable by nobody.
func test_every_authored_node_names_a_kind_a_yield_and_a_real_realm() -> void:
	var ladder := RealmDefaults.ladder()
	var nodes := _shipped_nodes()
	assert_ne(nodes.is_empty(), true, "the node directory holds loadable defs")
	for def in nodes:
		var node_id := String(def.node_id)
		assert_eq(
			ResourceNodeDef.KINDS.has(def.kind),
			true,
			"'%s' authors kind '%s', inside the closed set" % [node_id, def.kind]
		)
		assert_eq(def.yield_per_period > 0, true, "'%s' yields something every period" % node_id)
		assert_ne(def.realm, &"", "'%s' names a realm band" % node_id)
		assert_eq(
			ladder.index_of(def.realm) >= 0,
			true,
			"'%s' realm '%s' is a canonical ladder id" % [node_id, def.realm]
		)
		assert_eq(def.claim_floor >= 0, true, "'%s' floors a claim at zero or above" % node_id)
		assert_eq(def.depletion >= 0, true, "'%s' depletes by zero or more periods" % node_id)


## The `realm` field is a GATE, so the shipped set has to exercise more than one rung
## of it. A set authored entirely at the shallow end would make `permits()` trivially
## true for anyone and the gate untested by content; a set at one rung would make the
## field a label.
func test_the_authored_realms_span_the_ladder_rather_than_sitting_on_one_rung() -> void:
	var ladder := RealmDefaults.ladder()
	var bands: Dictionary = {}
	for def in _shipped_nodes():
		bands[String(def.realm)] = true
	assert_eq(bands.size() >= 4, true, "at least four distinct realm bands are authored")
	var deepest := 0
	for realm_id in bands.keys():
		deepest = maxi(deepest, ladder.index_of(StringName(realm_id)))
	assert_eq(
		deepest >= ladder.index_of(&"heaven_immortal"),
		true,
		"the authored set reaches at least the heaven_immortal band"
	)


## A shallower band than the deepest one authored, or every node would be workable by a
## beginner and the gate would never refuse anyone in shipped content.
func test_a_shallow_band_exists_beside_the_deep_one() -> void:
	var bands: Array[String] = []
	for def in _shipped_nodes():
		if not bands.has(String(def.realm)):
			bands.append(String(def.realm))
	assert_ne(bands.is_empty(), true, "bands were collected")
	assert_eq(
		bands.has("qi_refining"),
		true,
		"a shallow band is authored, so the gate refuses a beginner something"
	)


## Upkeep is what makes a claim a decision. The field being uniformly zero would leave
## `upkeep_per_period` decoration, and the field being uniformly positive would leave
## free income unrepresentable — so BOTH halves have to be in the shipped set.
func test_upkeep_is_authored_on_some_nodes_and_absent_on_others() -> void:
	var charged := 0
	var free := 0
	for def in _shipped_nodes():
		if def.upkeep_per_period > 0:
			charged += 1
		else:
			free += 1
	assert_eq(charged >= 1, true, "at least one node charges upkeep per period")
	assert_eq(free >= 1, true, "and at least one node is free, so the contrast is authored")


## The same argument for `depletion` and `claim_cost`: a field that is always one value
## is not a decision point, it is a constant with an extra load step.
func test_depletion_and_claim_cost_are_both_authored_in_both_states() -> void:
	var resting := 0
	var finite := 0
	var costed := 0
	var free_claim := 0
	for def in _shipped_nodes():
		if def.depletion > 0:
			finite += 1
		else:
			resting += 1
		if def.claim_cost.is_empty():
			free_claim += 1
		else:
			costed += 1
	assert_eq(resting >= 1, true, "at least one node is inexhaustible")
	assert_eq(finite >= 1, true, "and at least one depletes after a finite run")
	assert_eq(costed >= 1, true, "at least one first claim costs obligation terms")
	assert_eq(free_claim >= 1, true, "and at least one is claimed for nothing")


## All five kinds are the closed set, so a set that skips one ships a mine nobody could
## author and a hunting ground with no content behind it.
func test_every_node_kind_is_authored_at_least_twice() -> void:
	var counts: Dictionary = {}
	for def in _shipped_nodes():
		counts[String(def.kind)] = int(counts.get(String(def.kind), 0)) + 1
	for kind in ResourceNodeDef.KINDS:
		assert_eq(
			int(counts.get(String(kind), 0)) >= 2,
			true,
			(
				"kind '%s' is authored at least twice (saw %d)"
				% [String(kind), int(counts.get(String(kind), 0))]
			)
		)


## The load-bearing assertion: the catalog's OWN gate, over the authored set. `install`
## is the test seam and does not scan, so the defs are handed over explicitly — which is
## also what makes a duplicate id here impossible, because the catalog shouts and skips.
func test_the_catalog_validates_the_authored_nodes_with_zero_problems() -> void:
	var nodes := _shipped_nodes()
	assert_ne(nodes.is_empty(), true, "there are authored nodes to install")
	ResourceNodeCatalog.instance().install(nodes)
	assert_eq(
		ResourceNodeCatalog.instance().node_ids().size(), nodes.size(), "every node installed"
	)
	assert_eq(str(ResourceNodeCatalog.validate()), "[]", "the catalog reports no content problems")


## `reset()` clears the loaded flag as well as the map, so a production read re-scans.
## Asserted because it is what makes `install` a seam rather than a one-way door: if a
## reset forgot the flag, this suite's fixtures would be the only nodes the process ever
## saw and the assertion above would prove nothing about the shipped tree.
func test_a_reset_catalog_re_reads_the_authored_tree() -> void:
	ResourceNodeCatalog.instance().reset()
	var shipped := ResourceNodeCatalog.instance().node_ids()
	assert_eq(shipped.size() >= MIN_NODES, true, "the shipped tree is what a production read sees")
	assert_eq(
		ResourceNodeCatalog.instance().has_definition(&"no_such_node"),
		false,
		"an unknown id is absent"
	)


# --- The authored shops ---------------------------------------------------------


## Every authored shop file loads as a `ShopDef` and is filed under the id the game
## names it by, with a unique id. Same reason as the nodes: a duplicate id would let the
## second definition answer for the first.
func test_every_authored_shop_file_loads_and_its_id_matches_its_file_name() -> void:
	var paths := ContentScan.files_under(SHOPS_ROOT)
	assert_ne(paths.is_empty(), true, "the shop directory is not empty")
	assert_eq(paths.size() >= MIN_SHOPS, true, "at least %d shops are authored" % MIN_SHOPS)
	var seen: Dictionary = {}
	for path in paths:
		var def := load(path) as ShopDef
		assert_ne(def, null, "%s loads as a ShopDef" % path)
		if def == null:
			continue
		var shop_id := String(def.shop_id)
		assert_eq(shop_id, path.get_file().get_basename(), "'%s' is filed under its own id" % path)
		assert_eq(
			seen.has(shop_id),
			false,
			"'%s' names '%s', and no other file already did" % [path, shop_id]
		)
		seen[shop_id] = true
		assert_ne(def.display_name, "", "'%s' is named" % shop_id)
		assert_ne(def.location_id, &"", "'%s' trades somewhere" % shop_id)
		assert_eq(def.capacity >= 0, true, "'%s' bounds its own stock" % shop_id)


## An unresolvable `def_id` is a runtime content bug: `Crafting.resolve` returns null
## for it, and every transfer that touches the row then refuses or prices nothing.
## Resolved through `Crafting` itself rather than a file listing, because that is the
## exact call the market makes.
func test_every_authored_stock_row_resolves_to_a_real_item_def() -> void:
	for def in _shipped_shops():
		var shop_id := String(def.shop_id)
		assert_eq(def.stock.is_empty(), false, "'%s' stocks something" % shop_id)
		for row in def.stock:
			var def_id := StringName(row.get("def_id", ""))
			assert_ne(def_id, &"", "%s names what it stocks" % shop_id)
			assert_ne(
				Crafting.resolve(def_id),
				null,
				"%s stocks '%s', which resolves to an ItemDef" % [shop_id, def_id]
			)
			assert_eq(
				int(row.get("quantity", 0)) > 0,
				true,
				"%s stocks a positive count of '%s'" % [shop_id, def_id]
			)


## Every `buys` id is authored as an item too. A `buys` list is a refusal policy, so an
## unresolvable id in it is a refusal that can never be reached — harmless today and a
## lie tomorrow, which is why it is asserted rather than tolerated.
func test_every_authored_buy_id_resolves_to_a_real_item_def() -> void:
	for def in _shipped_shops():
		for def_id in def.buys:
			assert_ne(
				Crafting.resolve(def_id),
				null,
				"%s buys '%s', which resolves to an ItemDef" % [String(def.shop_id), def_id]
			)


## ADR 0100: an empty `buys` is a shop that buys nothing at all, which is what makes a
## black market a content choice rather than a price modifier. At least one authored
## shop has to carry that, or the refusal path has no content behind it.
func test_at_least_one_authored_shop_buys_nothing_at_all() -> void:
	var silent := 0
	for def in _shipped_shops():
		if def.buys.is_empty():
			silent += 1
	assert_eq(silent >= 1, true, "at least one shop is authored with an empty buys list")
	assert_eq(
		ShopDef.stock_seed(&"qi_refining_ore_stall", &"alchemy_cinder_ore"),
		ShopDef.stock_seed(&"qi_refining_ore_stall", &"alchemy_cinder_ore"),
		"and the stock seed is still a pure function of (shop_id, def_id)"
	)


## All four shop kinds are the closed set, so each is authored at least once and the
## `location_id` that differentiates a travelling merchant is actually exercised.
func test_every_shop_kind_is_authored_and_each_shop_trades_somewhere_distinct() -> void:
	var kinds: Dictionary = {}
	var locations: Dictionary = {}
	for def in _shipped_shops():
		var shop_id := String(def.shop_id)
		assert_eq(
			ShopDef.KINDS.has(def.kind),
			true,
			"'%s' authors kind '%s', inside the closed set" % [shop_id, def.kind]
		)
		kinds[String(def.kind)] = int(kinds.get(String(def.kind), 0)) + 1
		var location := String(def.location_id)
		assert_eq(
			locations.has(location),
			false,
			"'%s' shares location '%s' with another shop" % [shop_id, location]
		)
		locations[location] = shop_id
	for kind in ShopDef.KINDS:
		assert_eq(
			int(kinds.get(String(kind), 0)) >= 1,
			true,
			"kind '%s' is authored at least once" % String(kind)
		)


## `buys` is where regional and black-market variation lives, so two shops sharing a
## buy list would mean the authored set had no variation to express.
func test_the_authored_buy_lists_differ_from_one_another() -> void:
	var shops := _shipped_shops()
	assert_eq(shops.size() >= MIN_SHOPS, true, "there are enough shops to differ")
	var first := shops[0]
	for other in shops.slice(1):
		assert_ne(
			other.buys,
			first.buys,
			"'%s' does not repeat '%s' verbatim" % [String(other.shop_id), String(first.shop_id)]
		)


## ## Fixtures -------------------------------------------------------------------


## Every `.tres` in the node tree, read directly. `load()` hands back the engine's
## CACHED resource, so these are the same objects the catalog sees — read here, never
## written, because a suite that mutated shipped content would change it for every
## suite that runs later in the process.
func _shipped_nodes() -> Array[ResourceNodeDef]:
	var out: Array[ResourceNodeDef] = []
	for path in ContentScan.files_under(NODES_ROOT):
		var def := load(path) as ResourceNodeDef
		if def != null:
			out.append(def)
	return out


func _shipped_shops() -> Array[ShopDef]:
	var out: Array[ShopDef] = []
	for path in ContentScan.files_under(SHOPS_ROOT):
		var def := load(path) as ShopDef
		if def != null:
			out.append(def)
	return out
