extends TestCase

## ADR 0007's grade gate, asserted on the loot CONTENT: a starting hero's entry band
## pays wearable gear the hero can actually put on.
##
## ## What this is a guard against
##
## `ItemGrade.required_tier` reads GRADE, not realm — `TIER_BY_GRADE` puts `mortal` at
## ladder tier 1 and every other grade at 2 or more — so a hero built at R1 (`qi_refining`,
## tier 1) can wear grade-`mortal` gear and nothing else. `Equipment._meets_requirements`
## then refuses every higher grade outright. `tools data audit` measured the consequence:
## of 331 entry-band tables, 320 carried no grade-mortal wearable item at all, so on
## any of those fights a starting hero could kill a boss and receive nothing equippable.
## The corpus was never short of gear: 267 grade-mortal wearable items existed and 263 of
## them were already inside the band's transitive closure. The defect was PLACEMENT —
## the gear sat behind a 1-in-17 weighted draw into a pool — so the fix is authored
## placement into the band's own tables, never a new item.
##
## ## Why "the entry band" and not "every table"
##
## The entry band is the LOWEST tier of each authored encounter: the realm gate on
## `LootApi.enter_domain` refuses a band above the hero's own, so a higher tier is not a
## fight a new player can have. Sampling the whole table corpus instead measures a
## population the starting hero never rolls from.
##
## ## Why the walk, rather than the gate's own scan
##
## A `LootEntry` is either an ITEM or a nested TABLE, so a table "offers" gear its whole
## closure offers, at a depth the resolver itself bounds. The gate counts only an entry
## band's DIRECT item lines, which is the same figure it reports as a rate — and the
## consequence is visible in its own numbers: after the placement it reads "336 of 5832
## rolled entries", because the 5496-entry denominator includes every nested-TABLE entry,
## each of which can never itself be gear. This test asserts the property a player
## experiences instead: for every entry-band table, GEAR A TIER-1 HERO CAN WEAR is
## reachable inside the resolver's own nesting ceiling, and it is paid on EVERY resolve.
##
## ## Loop safety
##
## Every walk here carries a VISITED SET, a DEPTH CAP equal to
## `LootContent.MAX_NESTING_DEPTH` (so "reachable" means "the resolver reaches it"), and
## a hard ceiling on tables walked. The graph nests four deep and points back at its own
## parents, so an unguarded walk is a cycle; `MAX_WALK_FAILS` fails the test loudly if a
## walk ever hits a ceiling, because a truncated walk that still reports a pass is the
## silent half of that hazard.

## The resolver's own ceiling. Asserted equal to the constant rather than duplicated,
## so "reachable" cannot drift into "deeper than the resolver goes".
const DEPTH_CAP := 4
## Ceiling on tables walked in one closure. The band is 331 roots over a corpus of
## several thousand tables; this is three orders of magnitude of headroom, and hitting
## it is a failure, not a truncation.
const MAX_WALK_FAILS := 4000
## Sentinel for "this encounter declares no tier at all", kept out of the numbers a
## tier can legitimately take rather than being a magic int compared twice.
const NO_TIER := 1 << 30
## A real shipped grade-mortal wearable item, asserted present so the suite fails if
## the CORPUS loses it rather than if the PLACEMENT loses it.
const MORTAL_GEAR_PROBE := &"D4_mortal_fortune_charm"
## A real shipped entry-band table, and the boss its encounter binds it for. Reading the
## roots through the resolver's own `tier_at`/`table_for` is what makes this the entry
## band rather than a re-derivation of "tier 1" that could drift from the gate.
const PROBE_ENCOUNTER := &"loot_qi_qi_refining_domain"
const PROBE_TABLE := &"loot_qi_qi_refining_guardian"
const PROBE_BOSS := &"qi_qi_refining_guardian"
## Floors for the spread guard, not the measured counts: a content wave that ADDS gear
## must not fail a guard for growing the corpus. The corpus carries 267 grade-mortal
## wearables over 8 ruled slots and the placement exposes all of them, so these sit well
## under the measurement and still fail loudly if the band collapses onto one item.
const MIN_DISTINCT_GEAR := 100
const MIN_SLOTS_COVERED := 6


func _content() -> LootContent:
	return LootContent.instance()


## ## The entry band's roots, as the RESOLVER sees them.
##
## Every encounter's lowest-numbered tier, and every table that tier binds. `tier_at` is
## the resolver's own lookup and `table_for` its own per-boss binding, so a table this
## misses is a table no defeat at the entry band can resolve.
func _entry_band_roots() -> Array[StringName]:
	var out: Array[StringName] = []
	for encounter_id in _content().encounter_ids():
		var encounter := _content().encounter_by_id(StringName(encounter_id))
		if encounter == null:
			continue
		var lowest := NO_TIER
		for tier in encounter.tiers:
			if tier != null:
				lowest = mini(lowest, tier.tier)
		if lowest == NO_TIER:
			continue
		# `tier_at` takes the tier's NUMBER, not its position in the array (it matches
		# `candidate.tier == tier_index`), so this is `lowest` and not `lowest - 1`.
		var entry_tier := encounter.tier_at(lowest)
		if entry_tier == null:
			continue
		for table_id in entry_tier.table_ids():
			if table_id != &"" and not out.has(table_id):
				out.append(table_id)
	if out.size() > MAX_WALK_FAILS:
		push_error("%d entry-band roots exceeds MAX_WALK_FAILS" % out.size())
		return []
	return out


## Every grade-mortal wearable item this table can pay, through the nesting the
## resolver itself performs. VISITED SET + DEPTH CAP + a ceiling, and a loud failure if
## the ceiling is reached: a partial walk that still answers is worse than no walk.
##
## The index is a parameter so the cycle test below can point this walk at a scratch
## corpus. Seeding the shared `LootContent.instance()` with a test table would make the
## shipped corpus look different to every other suite, and the only way to watch a walk
## meet a cycle is to own the graph it walks.
func _entry_band_gear(
	content: LootContent, root: StringName, only_guaranteed: bool
) -> Array[StringName]:
	var found: Array[StringName] = []
	var visited: Dictionary = {}
	var pending: Array = [[String(root), 0]]
	var walked := 0
	# The bound is the ceiling, so this terminates whatever the graph looks like.
	while not pending.is_empty():
		if walked >= MAX_WALK_FAILS:
			push_error("%s: closure hit MAX_WALK_FAILS tables" % String(root))
			return []
		var frame: Array = pending.pop_back()
		var table_id := String(frame[0])
		var depth := int(frame[1])
		if visited.has(table_id) or depth > DEPTH_CAP:
			continue
		visited[table_id] = true
		walked += 1
		var table := content.table(StringName(table_id))
		if table == null:
			continue
		for entry in table.entries:
			if entry == null:
				continue
			if entry.is_nested():
				# A nested table is only reachable through an entry the resolver would
				# actually take, so a guarantee-only walk does not descend into a
				# weighted nest: that is the distinction the invariant rests on.
				if not (only_guaranteed and not entry.guaranteed):
					pending.append([String(entry.table_id), depth + 1])
				continue
			if only_guaranteed and not entry.guaranteed:
				continue
			if _is_wearable_mortal(entry, content) and not found.has(entry.item_id):
				found.append(entry.item_id)

	if walked >= MAX_WALK_FAILS:
		return []
	return found


## Grade-mortal WEARABLE EQUIPMENT, read from the AUTHORED rulings rather than a second
## list: `ItemCategory` says the item is equipment, `ItemGrade` answers the tier gate, and
## `ItemSlots` answers the slot vocabulary. A second copy of any of them here would be the
## ADR 0066 failure mode.
##
## `is_ruled` is load-bearing and NOT decorative. `ItemSlots.is_wearable` is deliberately
## permissive: it returns false only for a subtype the table lists under `unwearable`, so
## an UNRULED subtype stays wearable. Without the `is_ruled` guard this predicate accepted
## `trinket_iron_charm` — `category = misc`, `subcategory = charm`, `grade = mortal` — as
## "wearable gear a starting hero can equip", which is exactly the BL-0346 shape the
## permissive default creates. The mutation that found it swapped one entry-band table's
## gear for that trinket and the suite stayed GREEN.
func _is_wearable_mortal(entry: LootEntry, content: LootContent) -> bool:
	if entry == null or entry.item_id == &"":
		return false
	var def := content.definition(entry.item_id)
	if def == null:
		return false
	if def.category != ItemCategory.EQUIPMENT or def.grade != ItemGrade.MORTAL:
		return false
	return ItemSlots.is_ruled(def.subcategory) and ItemSlots.is_wearable(def.subcategory)


## ## THE INVARIANT. Every entry-band table PAYS gear a tier-1 hero can wear.
##
## This is the whole slice, and it is the assertion that is RED on the pre-change
## corpus. Reported as a LIST and compared empty, so a regression names the table rather
## than a count.
##
## MEASURED, so the claim is not larger than the work: this one was ALREADY true before
## the placement — 0 of 331 roots were closure-starved, because 263 of the 267
## grade-mortal wearables were already inside the band's transitive closure, sitting
## behind a 1-in-17 weighted draw. What was broken was that a hero could not SEE them.
## So this half is kept as a regression guard on the pools (strip the pools' gear and the
## band silently loses its reachable set) and is NOT the fix. The fix is the guarantee
## half below, which went from 321 tables with no guaranteed gear to 0.
func test_every_entry_band_table_pays_gear_a_starting_hero_can_wear() -> void:
	var content := _content()
	var roots := _entry_band_roots()
	assert_eq(roots.is_empty(), false, "the entry band names tables to fight")
	var starving: Array[String] = []
	var resolved := 0
	# `roots` is a snapshot taken above; the body only reads through LootContent, which
	# never appends to it, so the bound is fixed before the loop.
	for root in roots:
		resolved += 1
		if _entry_band_gear(content, root, false).is_empty():
			starving.append(String(root))
	assert_eq(starving, [], "every entry-band table pays grade-mortal wearable gear")
	assert_eq(resolved, roots.size(), "every root was walked, none was skipped")


## ## THE INVARIANT THAT FAILS PRE-CHANGE. It is PAID, not merely offered on a draw.
##
## `LootResolver._resolve` resolves guaranteed entries FIRST and UNCONDITIONALLY
## (loot_resolver.gd:83-86), so a guaranteed entry is the only kind of entry a table
## pays on EVERY resolve. A weighted entry behind a 1-in-17 draw into a pool is gear a
## hero may never see, which is the defect this slice fixed: 321 of 331 entry-band
## tables had no guaranteed grade-mortal wearable at all, so on those fights a starting
## hero could kill a boss and receive nothing equippable. A guard that accepted the
## weighted form would go green while the loop stayed broken.
func test_every_entry_band_table_guarantees_gear_a_starting_hero_can_wear() -> void:
	var content := _content()
	var roots := _entry_band_roots()
	assert_eq(roots.is_empty(), false, "the entry band names tables to fight")
	var optional: Array[String] = []
	for root in roots:
		if _entry_band_gear(content, root, true).is_empty():
			optional.append(String(root))
	assert_eq(optional, [], "every entry-band table guarantees grade-mortal wearable gear")


## ## The guarantee is not a formality: the resolver pays it.
##
## The two tests above read CONTENT. This one runs `LootResolver.resolve` over a real
## entry-band table with a seeded RNG and asserts the gear comes back in the plans —
## because an entry can be authored, guaranteed, and still never mint: `_expand` drops
## an item whose definition does not resolve, and a band that pays nothing is the shape
## BL-0634 reports.
func test_resolving_an_entry_band_table_pays_the_guaranteed_mortal_gear() -> void:
	var content := _content()
	var table := content.table(PROBE_TABLE)
	assert_ne(table, null, "the probe band has a table")

	# Seeded, so a failure is reproducible rather than a property of the draw.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261005
	var context := LootResolver.make_context(
		&"qi_refining", &"common", PROBE_BOSS, {"chance": 0.0, "count": 0, "quality_steps": 0}
	)
	var resolved := LootResolver.resolve(table, context, rng)
	var plans: Array = resolved["plans"]
	var warnings: Array = resolved["warnings"]
	assert_eq(warnings, [], "the entry band resolves without a warning")

	var paid := 0
	for plan in plans:
		var paid_entry := LootEntry.new()
		paid_entry.item_id = StringName(String(plan.get("def_id", "")))
		if _is_wearable_mortal(paid_entry, content):
			paid += 1
	assert_eq(paid > 0, true, "the resolve pays gear a starting hero can wear")


## ## The pool is real, so the placement had something to place.
##
## Without this, both invariants above could be green on a band that pays ONE item
## forever, while the rest of the grade-mortal corpus sits unreachable — a band that
## "pays gear" and a band that has real gear to give are different claims.
func test_the_entry_bands_guaranteed_gear_is_the_corpus_and_not_one_repeated_item() -> void:
	var content := _content()
	var probe := content.definition(MORTAL_GEAR_PROBE)
	assert_ne(probe, null, "the probe gear item is authored")
	assert_eq(
		probe.grade, ItemGrade.MORTAL, "and is grade-mortal, the only grade a tier-1 hero may equip"
	)

	var roots := _entry_band_roots()
	assert_eq(roots.is_empty(), false, "the entry band names tables to fight")
	var distinct: Dictionary = {}
	var slots: Dictionary = {}
	for root in roots:
		for item_id in _entry_band_gear(content, root, true):
			distinct[String(item_id)] = true
			var def := content.definition(item_id)
			if def != null:
				slots[String(def.subcategory)] = true
	assert_eq(
		distinct.size() >= MIN_DISTINCT_GEAR,
		true,
		(
			"the band guarantees %d distinct grade-mortal wearables, not one repeated item"
			% distinct.size()
		)
	)
	assert_eq(
		slots.size() >= MIN_SLOTS_COVERED,
		true,
		(
			(
				"and spreads across %d of the ruled wearable slots, so a hero is never handed "
				% slots.size()
			)
			+ "the same slot every fight"
		)
	)


## ## The walk is bounded BY the depth it declares, and terminates on a cycle.
##
## `DEPTH_CAP` is only meaningful if it equals the resolver's ceiling, and the visited
## set is only meaningful if it stops a graph that points at its own parent. Both are
## checked here rather than trusted: a cap that had drifted to a larger number would
## report gear as reachable that no resolve can pay, and an unbounded walk would hang
## the runner instead of failing it.
func test_the_walk_is_bounded_at_the_resolvers_own_nesting_ceiling() -> void:
	assert_eq(DEPTH_CAP, LootContent.MAX_NESTING_DEPTH, "the depth cap IS the resolver's ceiling")

	# A self-nesting table is the cycle a naive walk dies on. Seeded on a scratch index,
	# never the shared one: a test-only table must not make the shipped corpus look
	# different to every other suite.
	var looping := LootTableDef.new()
	looping.id = &"probe_self_nesting_table"
	# One draw, so the resolver actually PICKS the back edge and tries to expand it.
	# With rolls = 0 nothing is drawn, the nesting is never expanded, and every assertion
	# below passes without any guard being reached.
	looping.rolls = 1
	looping.allow_empty = false
	var back := LootEntry.new()
	back.id = &"probe_loop_back"
	back.kind = LootEntry.KIND_TABLE
	back.item_id = &""
	back.table_id = looping.id
	back.weight = 1.0
	back.chance = LootEntry.NO_CHANCE
	back.quantity = 1
	looping.entries.append(back)

	var scratch := LootContent.new()
	scratch.provide_table(looping)

	# THIS suite's walk, against a graph that points at its own parent. Reaching the
	# assert at all is half the proof; returning empty is the other half, because a walk
	# that answered "reachable" here would be answering from a cycle it never left.
	assert_eq(
		_entry_band_gear(scratch, looping.id, false),
		[],
		"this suite's walk terminates on a self-nesting table and finds no gear"
	)
	assert_eq(
		_entry_band_gear(scratch, looping.id, true),
		[],
		"and the guarantee-only walk does too, so neither half can spin on a cycle"
	)

	# And the production reachability walk, which carries its OWN chain guard rather than
	# this suite's visited set. It recurses, so a table naming its own ancestor would
	# never return without that guard.
	assert_eq(
		looping.reachable_item_ids(),
		[],
		"the production reachability walk also terminates on the cycle and finds nothing"
	)

	# What the RESOLVER does with the same table, asserted as far as it honestly can be,
	# with the limit stated rather than papered over: `_expand` looks a nested table up
	# through `LootContent.instance()`, so a cycle planted on a scratch index is
	# unreachable BY the resolver too, and the only way to make it walk one is to seed the
	# shared index every later suite reads. So the observable half is asserted instead --
	# it names the nesting it could not resolve rather than dropping it silently.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261005
	var context := LootResolver.make_context(
		&"qi_refining", &"common", &"probe_boss", {"chance": 0.0, "count": 0, "quality_steps": 0}
	)
	var cyclic := LootResolver.resolve(looping, context, rng)
	var cyclic_plans: Array = cyclic["plans"]
	assert_eq(
		cyclic_plans.size() <= LootResolver.MAX_PLANS_PER_RESOLVE,
		true,
		"the resolver stays inside its own plan ceiling on an unresolvable nesting"
	)
	var names_the_table := false
	for warning in cyclic["warnings"]:
		if String(warning).contains(LootResolver.WARN_UNKNOWN_NESTED):
			names_the_table = true
	assert_eq(
		names_the_table,
		true,
		"and names the nesting it could not resolve instead of dropping it silently"
	)
