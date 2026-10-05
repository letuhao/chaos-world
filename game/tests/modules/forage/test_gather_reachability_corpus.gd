extends TestCase

## ## DEF-0169 / DEF-0180: **every `gather`-declaring item a player can actually be given,
## is a `gather`-declaring item some node really yields.**
##
## ## What this suite is FOR, and why the mechanism suites are not enough
##
## `test_gather_route.gd` proves the MECHANISM works: hold a node, work it, items arrive.
## `test_gather_route_wear_and_wiring.gd` proves the yield table and the authored node tree
## agree in both directions, and that a granter is installed at the composition root.
## Neither can fail because a **content** item declared a `gather` source that no node in
## `ForageApi.NODE_YIELDS` produces.
##
## That is not a hypothetical. Measured on this tree (ADR 0253): **2428 items declare a
## `gather` source and 15 of them are named by some node's yield.** 2413 items claim a
## forager that does not exist. So the reachable set is a strict, *tiny* subset of the
## declared set, and it is 15 ids wide — which is small enough that a content wave could
## halve it, repoint it, or drop a node, and every mechanism assertion above would stay
## green while the acquisition graph quietly lost an edge.
##
## ## So what exactly is pinned
##
## The invariant is NOT "every gather item is gatherable" — that is **false today**, by
## 2413 items, and DEF-0180 is a HUMAN design ruling about what those 2413 are for
## (forage-as-supply, forage-as-loot, quest absorbs them, or retire the claim). This suite
## refuses to answer that question and asserts nothing about it.
##
## What IS pinned is the direction that can only ever lose items and never gain fiction:
##
## > For every item id the shipped `gather` route can deliver, that item declares `gather`,
## > and some authored node yields it, and that node is authored on disk.
##
## Three ways that can break, each of which is a real defect:
## 1. **A yield table entry names an item that no longer exists / was renamed.** The route
##    would grant nothing for that node — `no_yield_content` at play, forever.
## 2. **An item is renamed or removed while a node still names it.** Same failure, and the
##    node keeps authoring a yield for an id no item has.
## 3. **A new item is authored declaring `gather` and a node is pointed at it, but the
##    item's `sources` is wrong** (or a `set_yields` seam ships a table naming a
##    non-gather item) — the route would then deliver an item that never claimed to be
##    gatherable, so the declared set and the deliverable set disagree about what
##    `gather` MEANS. That is the fiction failure in the other direction.
##
## (3) is why this reads the `ItemDef` files rather than the Python loaders: the claim and
## the yield must be checked against each other in ONE place, and the corpus the player
## ships is the `.tres` tree.
##
## ## Why it reads the yield table statically, not through [method ForageApi.yields]
##
## `ForageApi._yields` is a `static var` this process shares with every suite that installs
## fixtures (`gather_route_fixture.gd` installs `FIXTURE_YIELDS`). Reading it here would
## make this suite's verdict depend on which suite ran last, which is the failure mode the
## fixture file's own header describes. [constant ForageApi.NODE_YIELDS] is the AUTHORED
## table and is immutable, so this suite measures shipped content and is order-independent.

## The authored item tree. Read directly rather than through any catalog singleton, for the
## reason above: a shared singleton would make the verdict depend on suite order.
const ITEM_ROOT := "res://data/items"
## The node tree `ForageApi.validate` audits, repeated here so this file's verdict does not
## depend on that method staying where it is.
const NODE_ROOT := "res://data/holdings/nodes"

## A cap on how many item files one test will load, so a malformed tree cannot make this
## suite unbounded. The corpus is ~8060 files today; this is headroom, not a promise.
const SCAN_BUDGET := 12000

## The measured floor, from ADR 0253. See the docstring above for why this is a floor and
## not an exact count.
const MEASURED_GATHERABLE_FLOOR := 15


## ## The load-bearing test: the deliverable set is a subset of the declared set.
##
## This is the assertion that fails if any `gather`-declaring item becomes unreachable in
## the way that matters — the route granting goods for an item that never asked for them,
## or a yield table drifting away from the items it claims to produce. Delete a line from
## `NODE_YIELDS`, point a yield at a renamed item, or ship a table naming an item whose
## `sources` no longer says `gather`, and this is red.
func test_every_gatherable_item_declares_gather_and_is_authored_as_an_item() -> void:
	var yields := _authored_yields()
	assert_ne(
		yields.is_empty(),
		true,
		"ForageApi.NODE_YIELDS is non-empty, so this suite measured something"
	)

	var declared := _items_declaring_gather()
	assert_ne(
		declared.is_empty(),
		true,
		"some items declare a gather source, so the subset claim is falsifiable"
	)

	# The subset direction: every item the route can DELIVER declares the route.
	var undeclared: Array[String] = []
	for item_id in yields:
		if not declared.has(item_id):
			undeclared.append(item_id)
	assert_eq(
		undeclared,
		[],
		(
			"every item ForageApi.NODE_YIELDS yields must declare a `gather` source, or the"
			+ " route delivers an item that never claimed to be gatherable and the declared"
			+ " set and the deliverable set disagree about what gather means. Offenders: %s"
			+ str(undeclared)
		)
	)


## ## The other direction, over the NODE rather than the item.
##
## Every authored node yields something, and everything it yields is an item that exists.
## `test_gather_route_wear_and_wiring.gd` already asserts the first half through
## `ForageApi.validate`; it is re-asserted here because this suite's claim is about the
## SHIPPED table specifically, and a `set_yields` install by another suite must not be
## able to make a broken authored table look fine.
func test_every_authored_node_yields_an_item_that_exists_and_asks_to_be_gathered() -> void:
	var yields := _authored_yields()
	var node_ids := _authored_node_ids()
	assert_ne(node_ids.is_empty(), true, "the authored node tree is non-empty")

	var ghost: Array[String] = []
	var silent: Array[String] = []
	for node_id in node_ids:
		var row: Array = yields.get(node_id, []) as Array
		if row.is_empty():
			silent.append(node_id)
			continue
		for candidate in row:
			var item_id := String(candidate)
			if not _item_file_exists(item_id):
				ghost.append("%s -> %s" % [node_id, item_id])
			elif not _items_declaring_gather().has(item_id):
				ghost.append("%s -> %s (item does not declare gather)" % [node_id, item_id])
	assert_eq(
		silent,
		[],
		(
			"every authored node must yield something, or a player holds a node that can"
			+ " never be worked. Offenders: %s" % str(silent)
		)
	)
	assert_eq(
		ghost,
		[],
		(
			"a node must not yield an item that does not exist or does not declare `gather`,"
			+ " or harvest refuses no_yield_content forever on a node that looks workable."
			+ " Offenders: %s" % str(ghost)
		)
	)


## ## The count is pinned, because a count that silently changes is a count nobody read.
##
## DEF-0169's title says "806 items declare gather alone and 0 of 7982 items can reach a
## player by gathering". Measured 2026-10-05 on this tree (ADR 0253), that is 2428
## gather-declaring items and 15 of them named by a node — so the title is STALE on both
## halves and this is the number that replaced it.
##
## **Why the floor is a range rather than an exact figure.** The authored corpus grows by
## design (three other agents are shipping item waves concurrently). A hard ceiling would
## turn every content wave into a red suite and train the next agent to delete the test. A
## hard FLOOR is different: it can only fire when the route has LOST reachability, which is
## the defect this suite exists to catch. So: the deliverable set must not shrink below the
## measured floor, and must never be empty.
func test_the_gatherable_set_has_not_shrunk_below_the_measured_floor() -> void:
	var yields := _authored_yields()
	var distinct: Array[String] = []
	for node_id in yields.keys():
		for candidate in yields[node_id] as Array:
			var item_id := String(candidate)
			if not distinct.has(item_id):
				distinct.append(item_id)
	assert_eq(
		distinct.size() >= MEASURED_GATHERABLE_FLOOR,
		true,
		(
			"the gather route currently delivers %d distinct authored items; ADR 0253 measured"
			+ " %d on 2026-10-05. Falling below the floor means a yield table lost an entry,"
			+ (
				" a node was removed, or an item was renamed out from under a node."
				% [distinct.size(), MEASURED_GATHERABLE_FLOOR]
			)
		)
	)


# --- readers ---------------------------------------------------------------------


## `ForageApi.NODE_YIELDS` as a plain `Dictionary`, read by TEXT so this file never
## depends on a fixture-installed `_yields` (see the class docstring).
func _authored_yields() -> Dictionary:
	var path := "res://src/modules/forage/api.gd"
	var text := FileAccess.get_file_as_string(path)
	assert_eq(text.is_empty(), false, "the forage facade source is readable")
	var open := text.find("const NODE_YIELDS")
	assert_ne(open, -1, "the facade declares the authored yield table")
	var tail := text.substr(open)
	var brace := tail.find("{")
	assert_ne(brace, -1, "the yield table is a dictionary literal")
	# Walk braces rather than regex: the literal's entries are one per line and the value
	# strings contain no braces, so a balanced scan is exact and cannot over-read into the
	# next constant.
	var depth := 0
	var close := -1
	for index in range(brace, tail.length()):
		var ch := tail[index]
		if ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth == 0:
				close = index
				break
	assert_ne(close, -1, "the yield table literal is balanced")
	var out: Dictionary = {}
	for line in tail.substr(brace, close - brace + 1).split("\n"):
		var colon := line.find(":")
		if colon < 0:
			continue
		var node_id := line.substr(0, colon).strip_edges().trim_prefix('"').trim_suffix('"')
		if node_id.is_empty():
			continue
		var items: Array[String] = []
		for quoted in _quoted(line.substr(colon + 1)):
			items.append(quoted)
		out[node_id] = items
	return out


## Every `&"..."` literal in `text`, as strings. The yield table's wire form, read the way
## `tools/data.py::_gatherable_ids` reads it — one reader of one shape.
func _quoted(text: String) -> Array[String]:
	var out: Array[String] = []
	var rest := text
	while true:
		var at := rest.find('&"')
		if at < 0:
			return out
		var tail := rest.substr(at + 2)
		var end := tail.find('"')
		if end < 0:
			return out
		out.append(tail.substr(0, end))
		rest = tail.substr(end + 1)


## Every authored `ItemDef` id that declares a `gather` source, from the item tree on disk.
## Read as TEXT, not loaded: 8000+ `load()` calls in one test is a cost this suite should
## not pay, and `sources` is a flat literal in the file.
func _items_declaring_gather() -> Dictionary:
	var out: Dictionary = {}
	var scanned := 0
	for path in ContentScan.files_under(ITEM_ROOT):
		scanned += 1
		if scanned > SCAN_BUDGET:
			break
		var text := FileAccess.get_file_as_string(path)
		if not text.contains('&"gather"'):
			continue
		var id := _field(text, 'id = &"')
		if id.is_empty():
			continue
		out[id] = true
	return out


## Every authored node id on disk, from the `node_id` field of each node `.tres`.
func _authored_node_ids() -> Array[String]:
	var out: Array[String] = []
	for path in ContentScan.files_under(NODE_ROOT):
		var text := FileAccess.get_file_as_string(path)
		if not text.contains('script_class="ResourceNodeDef"'):
			continue
		var id := _field(text, 'node_id = &"')
		if not id.is_empty():
			out.append(id)
	return out


## Whether an item `.tres` with this id exists anywhere under the item tree.
func _item_file_exists(item_id: String) -> bool:
	var marker := 'id = &"%s"' % item_id
	for path in ContentScan.files_under(ITEM_ROOT):
		if FileAccess.get_file_as_string(path).contains(marker):
			return true
	return false


## The value of `prefix`-delimited field in a `.tres`, or `""`.
func _field(text: String, prefix: String) -> String:
	var at := text.find(prefix)
	if at < 0:
		return ""
	var tail := text.substr(at + prefix.length())
	var end := tail.find('"')
	if end < 0:
		return ""
	return tail.substr(0, end)
