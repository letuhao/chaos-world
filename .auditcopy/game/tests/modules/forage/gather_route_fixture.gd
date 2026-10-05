extends TestCase

## Shared fixture for the two halves of the `gather` route suite. NOT a suite itself:
## the runner discovers `test_*.gd` only (`run_tests.gd::_find_tests`), so this file is
## never executed on its own.
##
## Split out of the original single-file suite purely for size -- gdlint's
## `max-file-lines` is 1000. Nothing was rewritten, no assertion changed and no method
## renamed: every constant, `setup()`/`teardown()` and private helper the cases use now
## lives here, which both halves `extends`. No state is duplicated between them.
##
## `setup()` / `teardown()` MUST live here rather than in one half. `HoldingsApi._store`,
## `HoldingsApi._resolver`, `ForageApi._granter` and the `ResourceNodeCatalog` singleton
## are all PROCESS-WIDE, and the runner shares one process across every suite and calls
## `teardown()` after EVERY test on whichever instance ran it -- so a store installed by
## one half and cleared by the other outlives the suite and is inherited by everything
## that runs later. The measured good on disk is the same shape, for the same reason.
##
## The delivery half is `test_gather_route.gd`. The upkeep/depletion, structural-guard
## and screen-binding half is `test_gather_route_wear_and_wiring.gd`.

## The `gather` acquisition route, end to end: a player holds a node, works it, and ends up
## holding real items.
##
## ## What this suite is FOR
##
## `test_holdings_yields_units_not_items.gd` proved that no forager existed. Its own
## docstring said when one did: *"these assertions go red ON PURPOSE ... the route goes live
## only once an item demonstrably arrives, never before."* This suite is the evidence that
## an item now arrives — so that suite's `is_shipped` assertion could be flipped honestly
## rather than optimistically.
##
## ## The three facts it took as read are still read here
##
## `holdings` still names no `ItemsApi`/`ItemDef`/`Inventory`/`ItemStack` (asserted below,
## because a later change could quietly break it), `accrue` still deals in integers, and
## `ResourceNodeDef` still carries no item id. What changed is that a MODULE BESIDE holdings
## now owns the conversion, and `app/` supplies the item half.
##
## ## Every refusal is a named constant
##
## A test that asserted only `ok == false` would pass for a forager that refused
## everything. Each refusal below is asserted BY NAME, because the name is the contract a
## panel switches on.
##
## ## Nothing leaks
##
## `HoldingsApi._store`, `HoldingsApi._resolver`, `ForageApi._granter` and the
## `ResourceNodeCatalog` singleton are all process-wide. The runner shares one process
## across every suite and calls `teardown` after EVERY test, so each of these is released
## per-test rather than per-suite: a catalog left installed would hand this suite's fixtures
## to whichever suite runs next.
##
## [constant PLAIN_PATH] is process-wide too, in the only sense that matters: it is a FILE on
## disk under `res://data`, and it is taken back down in the same `teardown`. See
## [_plain_stackable] for why it has to be a file at all.

## A node at the shallowest authored band, worked by an actor at that band.
const SHALLOW_REALM := &"foundation"
## A node two rungs deeper, so `permits` has something to refuse.
const DEEP_REALM := &"core_formation"
## The item every fixture node yields. An AUTHORED id, deliberately: the granter resolves
## item ids against the real content tree, so a fixture "item" would not resolve and every
## verb assertion would land on `no_yield_content` instead of on the rule under test.
const FIXTURE_ITEM := &"trinket_iron_charm"

## The yield table the fixtures use. [constant NODE_YIELDS] is keyed by authored node ids,
## so a suite that installs its own nodes installs its own yields through the seam
## [method ForageApi.set_yields] exists for. This is the same shape
## `ResourceNodeCatalog.instance().install` is: explicit and immediate, so no assertion here
## depends on what content the build happens to ship.
const FIXTURE_YIELDS: Dictionary = {
	"t_shallow": [FIXTURE_ITEM],
	"t_deep": [FIXTURE_ITEM],
	"t_costly": [FIXTURE_ITEM],
	"t_vein": [FIXTURE_ITEM],
}

## The id the written fixture is given. Spelled once, so the write, the path and the
## assertions cannot disagree about what the file is called. A `t_`-prefixed name in the
## suite's fixture vocabulary, under no authored naming convention.
const PLAIN_ID := "t_measured_good"
## Where the fixture is written, and where `teardown` takes it down. The `misc` folder is
## where `_category_of` falls back to, so `Crafting.resolve`'s fast path finds it directly.
const PLAIN_PATH := "res://data/items/misc/t_measured_good.tres"

## The stack ceiling every probe measurement below is taken against.
##
## ## Why the measured good cannot be [constant FIXTURE_ITEM]
##
## `trinket_iron_charm` carries `roll_spec = {count = 1, contexts = [...]}` and every authored
## `fixed_modifier` rolls an option, so its realized rolls are ALMOST NEVER equal and its
## stacks never merge. It is the right good for "does an item demonstrably reach the bag" and
## the wrong good for every room measurement here. Measured on this tree: 20 000 realizations
## produced no signature collision, so "almost never" is "never" as far as a test is concerned.
const MEASURED_MAX_STACK := 64

## The node the plain-good measurements are taken on. Six per period: a prime-adjacent number
## that divides neither 99 nor 256 neatly, so the period count has to be CEILING and the grant
## has to be asserted as `periods * 6` rather than as a round figure.
const PLAIN_NODE := &"t_plain"
## Units the [constant PLAIN_NODE] yields per period.
const PLAIN_YIELD := 6
## How many distinct stacks [_fill_bag] will try to place. A CEILING on the walk, not a
## promise that the content tree has this many: if it does not, the calling case's own
## `is_full()` assertion fails loudly rather than leaving a bag that is not full, because a bag
## that is not full makes the refusal it is testing unfalsifiable.
const FILL_BATCH := 64

var _actor: Actor
var _held: Array[Actor] = []
## The measured good, read back off disk. Never a hand-built object — see
## [method _plain_stackable].
var _plain: Array[ItemDef] = []


func setup() -> void:
	ResourceNodeCatalog.instance().reset()
	(
		ResourceNodeCatalog
		. instance()
		. install(
			[
				_node(&"t_shallow", SHALLOW_REALM, 5, 0, 0),
				_node(&"t_deep", DEEP_REALM, 6, 0, 0),
				_node(&"t_costly", SHALLOW_REALM, 4, 3, 0),
				_node(&"t_vein", SHALLOW_REALM, 2, 0, 2),
			]
		)
	)
	HoldingsApi.set_resolver(func(_kind: String, _id: String) -> Dictionary: return {"ok": true})
	HoldingsApi.set_store(WorldLedger.new())
	ForageApi.set_granter(ForageGranary.deliver)
	# BEFORE `_yields()`, which resolves the measured good's id: the granter only answers
	# `known` for an id `Crafting.resolve` can find ON DISK, so the file has to be there
	# before the yield table that names it is built.
	_ensure_plain_good()
	ForageApi.set_yields(_yields())
	_actor = _miner(&"t_miner", SHALLOW_REALM)


## The yield table, extended with one entry per PLAIN fixture node so the probe measurements
## can be taken against a good whose stacks merge. See [method _plain_stackable] for why the
## authored charm cannot serve there.
##
## The extra entry is rebuilt per `setup` rather than cached, so a plain good found on the
## last run cannot survive into this one. The GOOD it names is resolved from disk, so this
## runs AFTER the file is in place — see [method _ensure_plain_good].
func _yields() -> Dictionary:
	var out: Dictionary = FIXTURE_YIELDS.duplicate(true)
	var good := _plain_stackable()
	if good != null:
		out[String(PLAIN_NODE)] = [String(good.id)]
	return out


func teardown() -> void:
	for actor in _held:
		if actor != null:
			actor = null
	_held.clear()
	ForageApi.set_granter(Callable())
	# Restores the AUTHORED table, not an empty one — see `set_yields`, where an empty
	# dictionary means "put it back" precisely so no suite can leave the process on a
	# table of fixture ids that no content ships.
	ForageApi.set_yields({})
	HoldingsApi.set_resolver(Callable())
	HoldingsApi.set_store(null)
	ResourceNodeCatalog.instance().reset()
	# The measured good is the ONE fixture here that lives on disk, so it is the one that
	# can outlive the process. Taken down before the runner hands the engine to the next
	# suite, so no later run — and no `tools data` audit between runs — ever sees it.
	_remove_plain_good()


## A miner: an inventory for the goods, holdings for the custody, and a body path so
## `actor.realm()` has a rung to stand on.
##
## `capacity` is passed to `ItemsApi.attach` rather than defaulted, because the probe's
## behaviour is a function of ROOM and a 24-slot bag cannot be shown to be short without
## stacking 2 376 units. A bag of 1 or 2 slots makes the shortfall the size of the harvest,
## which is the thing under test.
func _miner(id: StringName, realm: StringName, capacity: int = ItemsApi.DEFAULT_CAPACITY) -> Actor:
	var actor := Actor.new(id, {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor, capacity)
	HoldingsApi.attach(actor)
	actor.set_path(PathState.new(PathState.BODY, realm))
	_held.append(actor)
	return actor


## Fill `actor`'s bag with `inventory.capacity` DISTINCT authored STACKS, and return how many
## units landed.
##
## ## Why stacks, and why distinct ones
##
## `Inventory._add_batch` refuses a new stack on `if _stacks.size() >= capacity` -- it counts
## `_stacks` ALONE. Distinct definitions are therefore what fills a bag for this purpose: one
## stack each, so a bag of `capacity` distinct defs has `capacity` stacks. Re-adding the SAME
## def merges into the open stack instead (up to `max_stack`), which is exactly the behaviour
## that made an earlier version of this fixture leave the bag short.
##
## ## Why the bound is snapshotted before the walk
##
## `capacity` is read ONCE, before the walk, and never re-read: a bound taken before a loop
## cannot change under it, so this can never be the unbounded walk the repo forbids. The walk
## also stops early at `is_full()`, and [constant FILL_BATCH] caps it as well, so a content
## tree with fewer distinct defs than a large capacity produces a LOUD failure at the calling
## case's own `is_full()` assertion rather than a quietly under-filled bag -- a bag that is not
## full makes the refusal it is testing unfalsifiable.


func _fill_bag(actor: Actor) -> int:
	var inventory := ItemsApi.inventory(actor)
	var bound := maxi(1, mini(inventory.capacity, FILL_BATCH))
	var defs := _distinct_stackables(bound)
	var placed := 0
	for index in defs.size():
		if inventory.add(defs[index], 1) == 0:
			placed += 1
		if inventory.is_full():
			break
	return placed


## Up to `limit` authored, DISTINCT `ItemDef`s, in a stable order, optionally narrowed to the
## PLAIN ones.
##
## ## Why `roll_spec` is filtered when `plain` is asked for
##
## This is the deepest of the three fixture mistakes this section went through, and the reason
## is worth recording because it is invisible from the outside. `Inventory._add_batch` merges
## a batch only when `batch.signature() == prototype.signature()`, and for a def carrying a
## `roll_spec` the prototype is a FRESHLY REALIZED roll. So:
##
##   * a bag holding such a good has NO growable stack at all -- every add opens a new one; and
##   * a request of `2 * max_stack` gets NOTHING into such a bag that is already full of stacks,
##     because a second stack cannot be opened.
##
## The sharp edge is the one that matters for a probe: a roll-bearing good's room is measured
## in WHOLE STACKS, so the only answers reachable are "all of it" and "none of it", and the
## interesting middle -- a partial grant -- needs a PLAIN, roll-free, high-`max_stack` good.
## `plain = true` is what supplies one, and the flags it selects on are asserted by
## [method _assert_plain], so a content change that rolls one of them fails loudly.
##
## Read from `Crafting.ITEM_ROOTS` -- the one list every item resolver in the repo reads -- and
## de-duplicated by `id`, because `ContentScan.files_under` walks three roots and one id can be
## authored under more than one. `limit` is the caller's bound and is passed in rather than
## defaulted, so no loop below needs a bound of its own.
func _distinct_stackables(limit: int, plain: bool = false) -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	var seen: Dictionary = {}
	for root in Crafting.ITEM_ROOTS:
		for path in ContentScan.files_under(root):
			if out.size() >= limit:
				return out
			var def := load(path) as ItemDef
			if def == null or def.id == &"" or not def.stackable or seen.has(String(def.id)):
				continue
			if plain and not def.roll_spec.is_empty():
				continue
			seen[String(def.id)] = true
			out.append(def)
	return out


## A def with exactly the shape the probe measurements need: stackable, no roll spec (so two
## adds merge and open room is reachable at all), and a KNOWN, MODEST stack ceiling.
##
## ## Why this has to be a FILE, and why it is not authored content
##
## The granter resolves an item id through `Crafting.resolve`, which finds defs by PATH:
## `ResourceLoader.exists(root/category/id.tres)`, then a `ContentScan` sweep of
## [constant Crafting.ITEM_ROOTS] matching the filename. It reads the tree — there is no
## in-memory registry to insert into, no `install` seam on any item catalog, and
## `ItemsApi` is at its twelve-method cap so one could not be added. A def that exists only
## as a variable is therefore invisible to it, and both routes through `ForageGranary`
## answer `unknown_item` and `no_yield_content` before a single unit is measured — which is
## exactly the five failures this fixture had to be fixed to remove.
##
## So the good is written to disk for the duration of ONE test and taken down again in
## `teardown`. It is emphatically not content:
##
##   * its id is `t_measured_good`, in this suite's `t_` fixture vocabulary and under NO
##     category, `grade`, `realm` or naming convention any authored item follows;
##   * it declares NO `sources`, so it is not obtainable from anything and no content gate
##     can claim it as a delivery target;
##   * it is removed after every test, so a full-suite run never ends with it present.
##
## ## Why `misc`, the one folder it sits in
##
## `_category_of` guesses a category from the id's first letter and falls back to
## [constant ItemCategory.MISC], so `res://data/items/misc` is the folder
## `Crafting.resolve`'s fast path would have looked in anyway. Putting it in a new folder
## would have made it an UNDECLARED content family, which `tools data` reports by name.
##
## ## Why it is written out in full rather than duplicated from an authored def
##
## The three fields that matter — `max_stack = 64`, `roll_spec = {}`, an empty
## `fixed_modifiers` — are the three the whole measurement turns on, so writing them out
## makes the fixture's shape readable in one place and impossible to lose to a content
## change. [_assert_plain] then pins exactly those three on the def that came BACK off
## disk, so a file that failed to parse into the intended shape fails the test loudly.


## The measured good, as `ForageGranary` will resolve it, or null when it is not there.
##
## Re-read from disk rather than handed back as a local object, and that is the load-bearing
## detail: the granter resolves its OWN `ItemDef` by id, so a measurement taken against one
## instance while the code under test was handed a different one would be measuring the
## fixture rather than the granter. Reading it back means the object under test and the
## object measured are the one `Crafting.resolve` would hand a player.
func _plain_stackable() -> ItemDef:
	if not _plain.is_empty():
		return _plain[0]
	_ensure_plain_good()
	return _plain[0] if not _plain.is_empty() else null


## Put the measured good on disk and cache the def read back out of it.
##
## Returns nothing and reports nothing on purpose: every caller that needs the value reads
## it through [method _plain_stackable], so a write that failed surfaces as a null there
## and the calling case's own `assert_ne(good, null, ...)` names it with the case that
## needed it.
##
## An already-present file is removed first rather than overwritten, so the path never
## points at a resource `Crafting.resolve`'s fast path has already cached under the same
## name from an earlier run.
func _ensure_plain_good() -> void:
	if not _plain.is_empty():
		return
	if FileAccess.file_exists(PLAIN_PATH):
		DirAccess.remove_absolute(PLAIN_PATH)
	var file := FileAccess.open(PLAIN_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(_plain_text())
	file.close()
	_plain.clear()
	_plain.append(load(PLAIN_PATH) as ItemDef)


## The fixture's body, written by hand rather than `ResourceSaver.save`d.
##
## Hand-written so it is byte-comparable to an authored `.tres` and so every field marking
## it as a fixture is visible — nothing is hidden that `ResourceSaver` would have added.
## `roll_spec = {}` and the empty `fixed_modifiers` are the load-bearing omissions: they are
## what let two adds of this good MERGE, which is the only way a partial grant is reachable.
## An EMPTY `sources` is what makes it a fixture rather than content — the good is obtainable
## from nothing, so no gate can count it as reachable or flag it as a dangling target.
func _plain_text() -> String:
	return (
		'[gd_resource type="Resource" script_class="ItemDef" load_steps=2 format=3]\n'
		+ "\n"
		+ '[ext_resource type="Script" path="res://src/modules/items/item_def.gd" id="1_item"]\n'
		+ "\n"
		+ "[resource]\n"
		+ 'script = ExtResource("1_item")\n'
		+ 'id = &"%s"\n' % PLAIN_ID
		+ 'display_name = "Measured Good"\n'
		+ 'category = &"misc"\n'
		+ 'rarity = &"common"\n'
		+ 'realm = &""\n'
		+ "stackable = true\n"
		+ "max_stack = %d\n" % MEASURED_MAX_STACK
		+ "roll_spec = {}\n"
		+ "fixed_modifiers = Array[Dictionary]([])\n"
		+ 'subcategory = &""\n'
		+ 'grade = &"mortal"\n'
		+ "sources = Array[StringName]([])\n"
	)


## Take the fixture down. Idempotent, and a missing file is not a failure: `teardown` runs
## after EVERY test whether or not the test under it needed the good, so the file is usually
## already gone.
##
## The in-memory cache is cleared with it, deliberately. `Crafting.resolve` hands back a
## `load`ed resource, so a cached def would outlive its file and answer the NEXT test's "is
## this item known" question about an item nothing on disk agrees exists. Dropping the cache
## sends every lookup back through `resolve`, which is the behaviour under test.
func _remove_plain_good() -> void:
	_plain.clear()
	if FileAccess.file_exists(PLAIN_PATH):
		DirAccess.remove_absolute(PLAIN_PATH)


## The two properties every probe measurement below depends on, asserted once so a content
## change cannot quietly turn a measurement into something else.
##
## `max_stack` is asserted EQUAL to [constant MEASURED_MAX_STACK], and equality is the point
## here rather than a hostage to content: the fixture AUTHORED this value, so nothing in the
## content tree can move it. It was previously asserted as a floor, which was right when the
## good was FOUND in the tree — `curr_spirit_coin` carries `max_stack = 9999` (ADR 0094
## requires it), stacks, and has no roll spec, so a content change would silently have
## re-pointed every "the shortfall fits INSIDE one stack" measurement at a 9999-unit stack,
## where no shortfall of the size these tests build is reachable at all. The fixture owns its
## shape now, so the floor became the exact value it always needed to be.
func _assert_plain(def: ItemDef) -> void:
	assert_eq(def.stackable, true, "setup: the measured good stacks")
	assert_eq(
		def.roll_spec.is_empty(),
		true,
		"setup: and carries no roll spec, so two adds of it CAN merge and room is reachable"
	)
	assert_eq(
		def.max_stack,
		MEASURED_MAX_STACK,
		(
			"setup: and holds exactly %d units, so a shortfall is measured against a KNOWN stack"
			% MEASURED_MAX_STACK
		)
	)


## A node def with a real yield and a real upkeep, so the verbs below exercise a def rather
## than a null a refusal path would answer.
func _node(
	node_id: StringName, realm: StringName, yield_units: int, upkeep: int, depletion: int
) -> ResourceNodeDef:
	return (
		ResourceNodeDef
		. from_dict(
			{
				"node_id": String(node_id),
				"display_name": "Test Node",
				"kind": "ore",
				"realm": String(realm),
				"yield_per_period": yield_units,
				"upkeep_per_period": upkeep,
				"depletion": depletion,
				"claim_floor": 0,
			}
		)
	)


## Install an arbitrary node. A test that measures the granter's probe needs a node yielding
## a SPECIFIC good, and the fixture table points at the charm, so the node cannot be one of
## the four `setup` installs. Same singleton seam, so `setup` re-installing the whole catalog
## before every test keeps it from leaking into the next one.
func _install_node(
	node_id: StringName, realm: StringName, yield_units: int, upkeep: int, depletion: int
) -> void:
	ResourceNodeCatalog.instance().install([_node(node_id, realm, yield_units, upkeep, depletion)])


func _owner(actor: Actor) -> Dictionary:
	return ForageAction.owner_ref(actor)


## Take `node_id` for `actor`, asserting the claim landed so a later refusal is about the
## verb under test and not about a setup that silently failed.
func _claim(actor: Actor, node_id: StringName) -> void:
	var claimed := HoldingsApi.claim(actor, node_id, _owner(actor))
	assert_eq(bool(claimed["ok"]), true, "setup: '%s' is claimed" % node_id)
