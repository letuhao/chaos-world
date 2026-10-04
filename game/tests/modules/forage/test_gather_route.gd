extends TestCase

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

var _actor: Actor
var _held: Array[Actor] = []


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
const FILL_BATCH := 48

## The node the plain-good measurements are taken on. Six per period: a prime-adjacent number
## that divides neither 99 nor 256 neatly, so the period count has to be CEILING and the grant
## has to be asserted as `periods * 6` rather than as a round figure.
const PLAIN_NODE := &"t_plain"
## Units the [constant PLAIN_NODE] yields per period.
const PLAIN_YIELD := 6


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
## The id the written fixture is given. Spelled once, so the write, the path and the
## assertions cannot disagree about what the file is called. A `t_`-prefixed name in the
## suite's fixture vocabulary, under no authored naming convention.
const PLAIN_ID := "t_measured_good"
## Where the fixture is written, and where `teardown` takes it down. The `misc` folder is
## where `_category_of` falls back to, so `Crafting.resolve`'s fast path finds it directly.
const PLAIN_PATH := "res://data/items/misc/t_measured_good.tres"
## The measured good, read back off disk. Never a hand-built object — see
## [method _plain_stackable].
var _plain: Array[ItemDef] = []


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


# --- the realm gate ------------------------------------------------------------


## A deep node refuses a shallow actor BY NAME, and the refusal costs the shallow actor
## nothing — no yield, no upkeep, no condition spent.
##
## This is ADR 0097's gate: realm is a GATE and never a yield multiplier, and the reason
## `ResourceNodeDef.realm` exists at all. A gate that returned true for anyone, or that
## charged a shallow actor for asking, would not be a gate.
func test_a_deep_node_refuses_a_shallow_actor_with_the_named_reason() -> void:
	_claim(_actor, &"t_deep")
	var result := ForageAction.gather(_actor, &"t_deep", 3)
	assert_eq(bool(result["ok"]), false, "a shallow actor cannot work a deep node")
	assert_eq(
		String(result["reason"]),
		ForageApi.REALM_BELOW_GATE,
		"and the refusal names the rule, not free text"
	)
	assert_eq(int(result["yielded"]), 0, "and no yield was credited")
	assert_eq(
		ItemsApi.inventory(_actor).snapshot().stacks().is_empty(),
		true,
		"and the bag is untouched: a refused gate costs nothing"
	)


## The same actor, the same node, and one rung of standing: the gate is a comparison on the
## ladder, not a whitelist, so an actor AT the node's realm works it.
func test_an_actor_at_the_node_realm_is_permitted() -> void:
	var deep := _miner(&"t_deep_miner", DEEP_REALM)
	_claim(deep, &"t_deep")
	var result := ForageAction.gather(deep, &"t_deep", 2)
	assert_eq(
		bool(result["ok"]), true, "an actor at the node's realm works it: %s" % result["reason"]
	)
	assert_eq(int(result["yielded"]), 12, "yield_per_period 6 over 2 periods")


## The gate is "at or above", not "strictly above": an actor DEEPER than the node must still
## work it, or the ladder would forbid a veteran from a beginner's field.
func test_an_actor_above_the_node_realm_is_still_permitted() -> void:
	var old_hand := _miner(&"t_old_hand", &"nascent_soul")
	_claim(old_hand, &"t_shallow")
	var result := ForageAction.gather(old_hand, &"t_shallow", 1)
	assert_eq(
		bool(result["ok"]), true, "a deeper actor works a shallow node: %s" % result["reason"]
	)


# --- the delivery --------------------------------------------------------------


## THE probe, and the one hole in this suite until now.
##
## ## What was missing, and why every case above missed it
##
## Every case in this section forages into an EMPTY bag, where the probe's answer and "yes,
## all of it fits" are the same number. Nothing here ever made `ForageGranary._fits` report
## LESS than what was asked, so the function could be rewritten to `return maxi(0, quantity)`
## -- a probe that ALWAYS promises delivery -- and all 99 cases across the two gather suites
## stayed green. The claim in the docblock ("so a full bag accrues nothing") was asserted by
## nothing; this section is what asserts it.
##
## ## Why these fixtures block the bag with STACKS
##
## ## A bag is only "full" to `_add_batch` when its STACKS are full, and that is not the same
## ## question `used_slots()` answers. `Inventory._add_batch` refuses a new stack on
## ## `if _stacks.size() >= capacity`, counting `_stacks` ALONE -- while `_add_instances`
## ## refuses on `used_slots() < capacity`, which also counts instances. So a bag whose slots
## ## are all taken by non-stackable `ItemInstance`s still accepts stack after stack.
## ##
## ## Two earlier attempts at this fixture were wrong in exactly that way: both filled the bag
## ## with non-stackable goods, the bag reported `is_full() == true`, and the probe then
## ## cheerfully appended a fresh stack past capacity. So the blockers here are all
## ## `ItemStack`s, which is what `_add_batch` actually counts.
##
## ## And the yielded good is a 99-max STACKABLE, which is the only shape that makes the
## ## probe's answer exact. A stack already at `max_stack` cannot be grown by a merge, so the
## ## only room left in a bag holding one is a free SLOT -- and how much of the request fits
## ## then depends on how many slots are left, which is a number this section measures rather
## ## than assumes.
func test_a_full_bag_refuses_the_harvest_and_accrues_nothing() -> void:
	var packed := _miner(&"t_packer", SHALLOW_REALM, 1)
	_fill_bag(packed)
	assert_eq(
		ItemsApi.inventory(packed).is_full(),
		true,
		(
			"setup: the bag is full (%d of %d slots)"
			% [ItemsApi.inventory(packed).used_slots(), ItemsApi.inventory(packed).capacity]
		)
	)

	_claim(packed, &"t_vein")
	var result := ForageAction.gather(packed, &"t_vein", 1)
	# ## The refusal, and WHICH constant it is
	#
	# `ForageApi.GRANT_REFUSED`, reached by the `int(room["granted"]) <= 0` guard -- and that is
	# the correct answer, not a quirk of my reading. `ForageGranary.deliver` wraps its
	# `BAG_FULL` probe answer in `_answer(ok = true, ...)`, so the granter reports "nothing
	# fits" as a SUCCESSFUL read of a full bag, and `harvest` is the module that turns "zero
	# would fit" into a refusal. `ForageGranary.BAG_FULL` is therefore NOT reachable through
	# this path; asserting it would have asserted a branch that cannot execute. What is asserted
	# is the id the route really produces, and asserting it by name rather than only
	# `ok == false` means a forager that refused EVERYTHING could not pass.
	assert_eq(bool(result["ok"]), false, "a bag with no room is not foraged: %s" % result["reason"])
	assert_eq(
		String(result["reason"]),
		ForageApi.GRANT_REFUSED,
		"named `grant_refused`: the probe answered zero and the route refused on it"
	)
	assert_eq(
		int(result["granted"]),
		0,
		"and the caller is told the harvest delivered NOTHING rather than a short count"
	)
	# ## The atomicity itself: the bag is consulted BEFORE `accrue`, so nothing was charged
	#
	# This is the sentence the docblock makes. Without it a bag-full harvest could still credit
	# the node and bill its upkeep, and the player would pay for a delivery that could not
	# happen -- which is the entire reason `harvest` probes before it mutates anything.
	var line: Dictionary = HoldingsApi.state(packed)["line"] as Dictionary
	assert_eq(int(line.get("t_vein", 0)), 0, "no yield is accrued onto the node's line")
	assert_eq(
		int(line.get("actor:upkeep:%s" % String(packed.id), 0)),
		0,
		"and no upkeep is charged, so a refused harvest costs the holder nothing"
	)


## The probe's NUMBER, which is the half `harvest` short-circuits past on a full bag.
##
## ## Why this is a separate case from the refusal above
##
## Because `harvest` returns at `granted <= 0` before it ever reads a positive count, so the
## case above proves the probe's "refuse" half and nothing else. The answer asserted here is
## non-zero AND strictly less than the request, so it is an assertion on the VALUE: a probe
## that refused everything and a probe that promised everything both fail it, and the mutation
## under test (`return maxi(0, quantity)`) fails it by answering the whole request.
func test_the_probe_reports_how_many_units_actually_fit_rather_than_how_many_were_asked_for(
) -> void:
	var good := _plain_stackable()
	assert_ne(good, null, "setup: the measured good is on disk, where Crafting.resolve can find it")
	_assert_plain(good)
	var stack_size := good.max_stack
	var request := stack_size + 1

	# ## The fixture: a ONE-STACK bag already holding one of the measured good
	#
	# Capacity 1, so no second stack can ever be opened. One unit is in the bag, so the open
	# stack has `stack_size - 1` of room, and asking for `stack_size + 1` merges `stack_size - 1`
	# into it and leaves 2 with nowhere to go. The measured answer is `stack_size - 1`: large,
	# exact, and strictly less than the request, which is the only shape that tests the VALUE.
	var tight := _miner(&"t_tight", SHALLOW_REALM, 1)
	var inventory := ItemsApi.inventory(tight)
	assert_eq(inventory.add(good, 1), 0, "setup: one unit landed")
	assert_eq(inventory.used_slots(), 1, "setup: one stack")
	assert_eq(inventory.is_full(), true, "setup: and the bag is full of STACKS")

	var measured := ForageGranary.deliver(tight, good.id, request, true)
	assert_eq(
		bool(measured["ok"]),
		true,
		"the probe answers rather than refusing: %s" % measured.get("reason", "")
	)
	assert_eq(
		int(measured["granted"]),
		stack_size - 1,
		"and it MEASURED %d of the %d asked for" % [stack_size - 1, request]
	)
	assert_eq(
		int(measured["granted"]) < request,
		true,
		"the shortfall is a number strictly less than the request, which is the claim"
	)
	# The probe is a pure read, which is the other half of the atomicity and the reason
	# `snapshot()` exists at all.
	assert_eq(
		inventory.used_slots(),
		1,
		"and it moved nothing: a snapshot the probe adds onto cannot reach the live bag"
	)
	assert_eq(inventory.count(good.id), 1, "including the stack it measured against")
	# And the ZERO answer on a bag with no room at all, which no partial fixture can give.
	var blocked := _miner(&"t_blocked", SHALLOW_REALM, 1)
	_fill_bag(blocked)
	var none := ForageGranary.deliver(blocked, StringName(FIXTURE_ITEM), 2, true)
	assert_eq(bool(none["ok"]), true, "a bag with no room is still a question the probe answers")
	assert_eq(
		int(none["granted"]),
		0,
		"and it answers ZERO: a probe that always promises delivery is not a probe"
	)


## The route refuses a SHORT harvest, names it, and reports the short count.
##
## ## Why the shortfall has to live INSIDE one stack
##
## `harvest` PROBES with `yield_per_period` and GRANTS `yield_per_period * periods`. For the
## grant to come up short it must exceed the room the probe found, and with the measured good
## in a one-stack bag that room is exactly one stack. So the grant asked for is one unit beyond
## it, the probe answers the stack, and the grant delivers the stack and leaves the rest behind.
## The node yields 6 per period, so eleven periods is 66 units against a 63-unit room: three
## over. Eleven is not a trick -- it is the same verb with a bigger count, and the exact counts
## are derived from `stack_size` below rather than written in.
##
## ## Why `grant_short` and not `grant_refused`
##
## `ok == false` in both branches, and only the NAME separates "the granter took nothing" from
## "the granter took part of it". A caller rendering "your bag was full" against a harvest
## that delivered 63 of 66 is showing a false fact, so the constant is asserted by value.
func test_a_harvest_the_bag_cannot_hold_whole_is_named_grant_short_with_the_real_count() -> void:
	var good := _plain_stackable()
	assert_ne(good, null, "setup: the measured good is on disk, where Crafting.resolve can find it")
	_assert_plain(good)
	var stack_size := good.max_stack
	# A node whose yield does not divide the stack size evenly leaves an awkward remainder, so
	# the period count is CEILING and the grant is `6 * that` -- assertably more than the room,
	# and checked rather than assumed.
	var periods := (stack_size + 5) / 6
	var asked := periods * 6
	assert_eq(
		asked > stack_size,
		true,
		(
			"setup: the grant asked for %d exceeds the %d a one-stack bag can take"
			% [asked, stack_size]
		)
	)

	var half := _miner(&"t_half", SHALLOW_REALM, 1)
	# One unit in the bag, so the open stack has `stack_size - 1` of room: the probe answers
	# `stack_size - 1` and the grant of `asked` delivers `stack_size - 1` and leaves the rest.
	assert_eq(ItemsApi.inventory(half).add(good, 1), 0, "setup: one unit landed")

	# The node has to yield `good`, so it is installed here rather than reusing a fixture whose
	# yield table points at the charm. Installing a node is the same seam `setup` uses.
	#
	# The realm is SHALLOW, matching the miner above: a `DEEP_REALM` node is correctly
	# refused `realm_below_gate` before the bag is ever consulted, so measuring a shortfall
	# against it measures the gate instead of the granter.
	_install_node(PLAIN_NODE, SHALLOW_REALM, 6, 0, 0)
	_claim(half, PLAIN_NODE)
	var result := ForageAction.gather(half, PLAIN_NODE, periods)
	assert_eq(
		bool(result["ok"]),
		false,
		(
			"a harvest the bag cannot hold whole is a refusal, not a partial success: %s"
			% result["reason"]
		)
	)
	assert_eq(
		String(result["reason"]),
		ForageApi.GRANT_SHORT,
		(
			"named `grant_short` rather than `grant_refused`: part of it DID arrive (granted=%d of %d, item=%s)"
			% [int(result["granted"]), asked, String(result["item_id"])]
		)
	)
	# The granter moved a real number of units and `granted` reports it, so a caller can render
	# "98 of 102 delivered" rather than a bare refusal. Asserted because the mutation this suite
	# was written against makes exactly this number WRONG.
	assert_eq(
		int(result["granted"]),
		stack_size - 1,
		(
			"and the short count is the measured one: %d of the %d really did land"
			% [stack_size - 1, asked]
		)
	)
	# The line is settled BEFORE the grant, so the ledger must not still be holding the units
	# nobody received -- the reason a short delivery has to be named rather than banked.
	# Keyed on PLAIN_NODE: this used to read "t_plain", a literal that happened to match the
	# node the fixture installed, so it stayed correct by coincidence while the node id moved.
	var line: Dictionary = HoldingsApi.state(half)["line"] as Dictionary
	assert_eq(
		int(line.get(String(PLAIN_NODE), 0)),
		0,
		"and the accrued line was settled, so the ledger and the bag cannot both claim them"
	)
	assert_eq(
		ItemsApi.has_item(half, good.id, stack_size - 1),
		true,
		"while the bag really did receive the units that fit"
	)


## THE end-to-end claim of this suite: foraging a held node credits
## `yield_per_period * periods` units AND the actor ends up holding real items.
##
## Both halves are asserted, because either alone is satisfiable by a lie. A forager that
## credited units and granted nothing would pass a ledger assertion; one that conjured
## items without accruing would pass a bag assertion. The yield is read from the LEDGER and
## the goods from the BAG, so the two sides cannot be satisfied by the same fiction.
func test_foraging_a_held_node_accrues_the_authored_yield_and_grants_items() -> void:
	_claim(_actor, &"t_shallow")
	var result := ForageAction.gather(_actor, &"t_shallow", 3)
	assert_eq(bool(result["ok"]), true, "the harvest is accepted: %s" % result.get("reason", ""))
	assert_eq(int(result["periods"]), 3, "the caller's periods are honoured verbatim")
	assert_eq(
		int(result["yielded"]), 15, "yield_per_period 5 over 3 periods is credited to the line"
	)
	assert_eq(int(result["granted"]), 15, "and the same units reach the bag")
	var item_id := String(result["item_id"])
	assert_ne(item_id, "", "the node names an item, which is the fact a node cannot carry")
	assert_eq(
		ItemsApi.has_item(_actor, StringName(item_id), 15),
		true,
		"and the actor really holds them: %d of '%s'" % [15, item_id]
	)
	# The line was settled, so the ledger and the bag never both claim the same units.
	assert_eq(
		int(HoldingsApi.state(_actor)["line"].get("t_shallow", 0)),
		0,
		"the accrued line is settled, not double-counted"
	)


## The yield really is `yield_per_period * periods` and not a constant: two different
## period counts on the same node must produce two different totals.
func test_the_granted_quantity_scales_with_periods() -> void:
	_claim(_actor, &"t_shallow")
	ForageAction.gather(_actor, &"t_shallow", 1)
	var two := ForageAction.gather(_actor, &"t_shallow", 2)
	assert_eq(int(two["yielded"]), 10, "2 periods of a 5-unit node is 10")
	assert_eq(int(two["granted"]), 10, "and all ten are granted")


## Foraging a node you do NOT hold refuses — with the holder mismatch named by the module
## that owns the ledger, rather than a restatement here.
func test_foraging_a_node_you_do_not_hold_refuses() -> void:
	var rival := _miner(&"t_rival", SHALLOW_REALM)
	_claim(rival, &"t_shallow")
	var result := ForageAction.gather(_actor, &"t_shallow", 1)
	assert_eq(bool(result["ok"]), false, "a non-holder cannot forage a held node")
	assert_eq(
		String(result["reason"]),
		HoldingsState.HOLDER_MISMATCH,
		"and the refusal is holdings' own id, passed through by name"
	)
	assert_eq(
		ItemsApi.inventory(_actor).snapshot().stacks().is_empty(),
		true,
		"and the trespasser's bag is empty"
	)


## An unclaimed node is not a node the caller may work: `no_holder`, not `holder_mismatch`.
## The two are different facts and a caller that saw only "refused" could not tell a vacant
## vein from someone else's.
func test_foraging_an_unclaimed_node_refuses_no_holder() -> void:
	var result := ForageAction.gather(_actor, &"t_shallow", 1)
	assert_eq(bool(result["ok"]), false, "a node nobody holds cannot be foraged")
	assert_eq(String(result["reason"]), HoldingsState.NO_HOLDER, "and names the vacant state")


## A node that is not in the catalog at all refuses `unknown_node`, so a stale node id is a
## named refusal rather than a null dereference somewhere downstream.
func test_foraging_an_unknown_node_refuses() -> void:
	var result := ForageAction.gather(_actor, &"no_such_node", 1)
	assert_eq(bool(result["ok"]), false, "an unknown node refuses")
	assert_eq(String(result["reason"]), HoldingsState.UNKNOWN_NODE, "and names the rule")


# --- upkeep, depletion, resting ------------------------------------------------


## Upkeep is charged on a node that declares it, and is charged AGAINST THE HOLDER'S LINE
## keyed by the holder — never out of the yield. That is what makes a claim a decision
## rather than a free grab (ADR 0097), and it is why a node with upkeep can net cost the
## player money while still paying out.
func test_a_node_with_upkeep_charges_it_and_a_node_without_does_not() -> void:
	_claim(_actor, &"t_costly")
	ForageAction.gather(_actor, &"t_costly", 4)
	var line: Dictionary = HoldingsApi.state(_actor)["line"] as Dictionary
	# `_charge_upkeep` keys the line `"<kind>:upkeep:<holder id>"` and NOTHING else, so this
	# is the holder's single upkeep line across every node they hold — the node id is
	# deliberately absent, because an institution's upkeep is one visible obligation rather
	# than a second pile of goods per node (BL-0191).
	var upkeep_key := "actor:upkeep:%s" % String(_actor.id)
	assert_eq(
		int(line.get(upkeep_key, 0)),
		12,
		"upkeep_per_period 3 over 4 periods is charged against the holder's own line"
	)

	# Working a node that declares no upkeep must leave that line byte-identical. The
	# previous form of this assertion read a `...:upkeep:<node id>` key, which holdings can
	# never write — so it answered 0 whatever the code did, and a harvest that charged
	# upkeep for a free node would have passed. Comparing across the call is the only
	# version of this that can actually fail.
	var before := int(line.get(upkeep_key, 0))
	_claim(_actor, &"t_shallow")
	ForageAction.gather(_actor, &"t_shallow", 4)
	var after: Dictionary = HoldingsApi.state(_actor)["line"] as Dictionary
	assert_eq(
		int(after.get(upkeep_key, 0)), before, "and a node that declares no upkeep is charged none"
	)


## Depletion spends CONDITION and refuses once it is gone. A node that silently yielded
## nothing would leave a player pressing a button that does nothing forever, so the refusal
## is the point: `depleted` is named, not an empty result.
func test_a_depleted_node_refuses_rather_than_yielding_nothing_silently() -> void:
	_claim(_actor, &"t_vein")
	# `depletion = 2`, so two periods of accrual spend the condition and the third refuses.
	var first := ForageAction.gather(_actor, &"t_vein", 1)
	assert_eq(bool(first["ok"]), true, "the first period works")
	assert_eq(int(first["condition"]), 1, "and spends one period of condition")
	var second := ForageAction.gather(_actor, &"t_vein", 1)
	assert_eq(bool(second["ok"]), true, "the second period works")
	assert_eq(int(second["condition"]), 0, "and spends the last of it")
	var third := ForageAction.gather(_actor, &"t_vein", 1)
	assert_eq(bool(third["ok"]), false, "the next one refuses rather than yielding nothing")
	assert_eq(String(third["reason"]), HoldingsState.DEPLETED, "and names the rule")
	assert_eq(
		ItemsApi.has_item(_actor, StringName(String(second["item_id"])), 4),
		true,
		"the units already paid out are still in the bag: depletion is not a retroactive loss"
	)


## A refused depletion must not charge upkeep, or an exhausted holding would keep billing
## the player for a node that produces nothing. Asserted because `accrue` refuses BEFORE it
## charges, and that ordering is the only thing protecting the player.
func test_a_refused_depleted_node_charges_no_upkeep() -> void:
	_claim(_actor, &"t_vein")
	ForageAction.gather(_actor, &"t_vein", 1)
	ForageAction.gather(_actor, &"t_vein", 1)
	# `t_vein` declares upkeep 0, so the holder's upkeep line is 0 before the refusal and
	# must still be 0 after it. Read across the refusal rather than at a key holdings never
	# writes: the original `...:upkeep:t_vein` lookup answered 0 for a code that charged
	# upkeep anyway, so the assertion could not fail.
	var upkeep_key := "actor:upkeep:%s" % String(_actor.id)
	var before: Dictionary = HoldingsApi.state(_actor)["line"] as Dictionary
	var refused := ForageAction.gather(_actor, &"t_vein", 1)
	assert_eq(String(refused["reason"]), HoldingsState.DEPLETED, "the node is spent")
	var line: Dictionary = HoldingsApi.state(_actor)["line"] as Dictionary
	assert_eq(
		int(line.get(upkeep_key, 0)),
		int(before.get(upkeep_key, 0)),
		"and a refusal charges no upkeep, so an exhausted holding is not a bill"
	)


## `periods <= 0` refuses with `no_periods`, and the id is HELDINGS' — this module surfaces
## the constant rather than inventing a synonym, so one `no_periods` covers the whole accrue
## path whichever module a caller reached it through.
func test_a_non_positive_period_count_refuses() -> void:
	_claim(_actor, &"t_shallow")
	for bad in [0, -1, -100]:
		var result := ForageAction.gather(_actor, &"t_shallow", bad)
		assert_eq(bool(result["ok"]), false, "periods %d refuses" % bad)
		assert_eq(String(result["reason"]), ForageApi.NO_PERIODS, "periods %d names the rule" % bad)
	assert_eq(
		ItemsApi.inventory(_actor).snapshot().stacks().is_empty(),
		true,
		"and a refused period count moved nothing at all"
	)


# --- the structural guard -------------------------------------------------------


## The boundary this whole design exists to keep. `holdings` may not name an inventory, so
## the conversion has to live somewhere else — and this asserts from the facade's own SOURCE
## rather than by reflection, because a `has_method` probe on a class of static verbs
## answers for the instance side and would pass for reasons unrelated to the claim.
func test_holdings_still_names_no_inventory_verb() -> void:
	var source := FileAccess.get_file_as_string("res://src/modules/holdings/api.gd")
	assert_eq(source.is_empty(), false, "the facade source is readable")
	for verb in ["ItemsApi", "ItemDef", "Inventory", "ItemStack"]:
		assert_eq(
			source.contains(verb),
			false,
			"holdings/api.gd never names %s, so the conversion had to live elsewhere" % verb
		)


## And the `forage` module is just as bounded: it declares no `items` edge, so it must not
## name an inventory either. The granter is the seam that keeps that true.
func test_the_forage_facade_names_no_inventory_verb() -> void:
	var source := FileAccess.get_file_as_string("res://src/modules/forage/api.gd")
	assert_eq(source.is_empty(), false, "the forage facade source is readable")
	for verb in ["ItemsApi", "ItemDef", "Inventory", "ItemStack", "Crafting"]:
		assert_eq(
			source.contains(verb),
			false,
			"forage/api.gd never names %s, so the item half is genuinely injected" % verb
		)


## Every node this module can forage is a node the game actually authors, and every authored
## node has a yield. Without this, a yield table could drift from the content tree and a
## node could quietly become un-gatherable with nothing failing.
func test_every_authored_node_has_an_authored_yield() -> void:
	var problems := ForageApi.validate()
	assert_eq(
		problems,
		[],
		"the yield table and the authored node catalog agree: %s" % ", ".join(problems)
	)


## The route is shipped because there is a verb, and the verb is reachable from `game/src`.
## Both halves are asserted: a `shipped` flag without a production call site is the exact
## lie `tools/data.py`'s `call_sites` exists to prevent.
func test_the_route_is_backed_by_a_verb_and_an_installed_granter() -> void:
	assert_eq(
		ItemSources.is_shipped(ItemSources.KIND_GATHER),
		true,
		"gather ships because ForageApi.harvest exists, not because the flag moved"
	)
	assert_eq(bool(ForageApi.has_granter()), true, "and the granter is installed by this suite")


## Without a granter the verb refuses LOUDLY rather than accruing yield it can never
## deliver. A forager that produced accruals and no items is the exact bug that kept
## `gather` unshipped, so the unwired case is asserted rather than assumed away.
func test_an_unwired_granter_refuses_instead_of_accruing_unreachable_yield() -> void:
	_claim(_actor, &"t_shallow")
	ForageApi.set_granter(Callable())
	var result := ForageAction.gather(_actor, &"t_shallow", 2)
	assert_eq(bool(result["ok"]), false, "an unwired route refuses")
	assert_eq(
		String(result["reason"]),
		ForageApi.NO_GRANTER,
		"and names the missing seam rather than failing quietly"
	)
	var line: Dictionary = HoldingsApi.state(_actor)["line"] as Dictionary
	assert_eq(
		int(line.get("t_shallow", 0)),
		0,
		"and credits nothing, so nothing was accrued that could not be delivered"
	)


## A node with no authored yield refuses BY NAME. This is the gap that made `gather`
## unshipped — nothing in `game/src` knew what a node produced — and it must never come
## back as a silent empty bag.
func test_a_node_with_no_authored_yield_refuses_named() -> void:
	ResourceNodeCatalog.instance().install([_node(&"t_unmapped", SHALLOW_REALM, 5, 0, 0)])
	_claim(_actor, &"t_unmapped")
	var result := ForageAction.gather(_actor, &"t_unmapped", 1)
	assert_eq(bool(result["ok"]), false, "a node nothing names an item for cannot be foraged")
	assert_eq(
		String(result["reason"]),
		ForageApi.NO_YIELD_CONTENT,
		"and it says so, rather than yielding an empty bag"
	)


# --- the entry point a screen binds ---------------------------------------------


## `ForageAction.workable` is the question a button's enabled state binds to. It must agree
## with the verb: a button that is enabled where the verb refuses is a control that lies.
func test_workable_agrees_with_the_verb_on_every_gate() -> void:
	_claim(_actor, &"t_shallow")
	assert_eq(ForageAction.workable(_actor, &"t_shallow"), true, "a held, shallow node works")
	assert_eq(
		ForageAction.workable(_actor, &"t_deep"),
		false,
		"an unheld deep node is not workable, whatever else is true of it"
	)
	_claim(_actor, &"t_deep")
	assert_eq(
		ForageAction.workable(_actor, &"t_deep"),
		false,
		"and a HELD deep node is still not workable by a shallow actor"
	)
	var rival := _miner(&"t_rival_2", SHALLOW_REALM)
	_claim(rival, &"t_shallow")
	# ADR 0085: a claim on HELD ground opens a standoff and leaves `holder` byte-identical
	# (`test_holdings_claim` pins exactly this). So `rival`'s challenge did not take the
	# node — `_actor` is still its holder, and `workable` must say so for BOTH of them. This
	# assertion used to claim the rival's own ref made it workable, which is only true if a
	# challenge silently transfers ground, i.e. if `holdings` is broken.
	assert_eq(
		ForageAction.workable(rival, &"t_shallow"),
		false,
		"a challenger never holds the node, so it is not workable for them either"
	)
	assert_eq(
		ForageAction.workable(_actor, &"t_shallow"),
		true,
		"and the real holder still works it: the standoff moved nothing"
	)
