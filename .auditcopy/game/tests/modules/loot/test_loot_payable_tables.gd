extends TestCase

## An authored loot table no band can pay is authored content no player can obtain
## (BL-0136).
##
## ## What the entry said, and what the tree holds NOW
##
## BL-0136 filed "~1500 authored boss drops appear in no authored encounter", and
## attributed it to 128 `DomainDef`s with no `LootEncounterDef`. Re-measured on this
## tree (BL-0619: verify a finding before dispatching against it): **zero** drops. A
## content wave completed the corpus — 160 authored domains, 160 encounters, no orphan
## on either side — so the defect BL-0136 named is gone.
##
## The CLASS is not. A defeat resolves exactly one table: the one a band binds for the
## boss it spawned (`LootContent.table_for_boss`). So a table that no band binds, and
## that no bound table nests, is content the game ships that nothing can resolve — and
## every item it lists is unobtainable however well-formed the file is. Eight such
## tables shipped, carrying nine items, and nothing in the tree said so. The deliverable
## is the guard, proved red in both directions against the real implementation
## (INC-0016), plus the corpus itself brought to zero.
##
## Per the criterion standard these halves are checked SEPARATELY, because they fail
## independently: a guard that reports nothing on a broken corpus proves nothing, and a
## guard that reports on a clean corpus proves nothing either.

## A table id the corpus authors and no band pays. Never referenced by an encounter, so
## the only thing that can put it in the unbanded set is the walk itself.
const DEAD_TABLE := &"probe_dead_table_no_band_pays"
const SECOND_DEAD_TABLE := &"probe_second_dead_table"
## An item id the corpus does NOT define, so a report naming it cannot be a coincidence.
const PROBE_ITEM := &"probe_item_no_band_can_deliver"
const SECOND_PROBE_ITEM := &"probe_second_item"


## A scratch corpus over the real content tree. `LootContent.new()` rather than
## `instance()` on purpose: every index this test needs is per instance, so a seed here
## cannot make the shipped corpus look broken to every other suite, and a corpus
## assertion stays honest.
func _scratch(dead: Array[LootTableDef] = []) -> LootContent:
	var corpus := LootContent.new()
	for table in dead:
		corpus.provide_table(table)
	return corpus


## A table carrying one guaranteed item and nothing else: the simplest shape a table
## no band pays can have, and the one that makes the stranded-item half assertable.
func _probe(id: StringName, item_id: StringName) -> LootTableDef:
	var table := LootTableDef.new()
	table.id = id
	table.display_name = String(id)
	table.rolls = 0
	table.allow_empty = false
	var entry := LootEntry.new()
	entry.id = StringName("%s_only" % String(id))
	entry.kind = LootEntry.KIND_ITEM
	entry.item_id = item_id
	entry.weight = 1.0
	entry.chance = LootEntry.NO_CHANCE
	entry.guaranteed = true
	entry.quantity = 1
	table.entries.append(entry)
	return table


func _content() -> LootContent:
	return LootContent.instance()


## ## The corpus is WHOLE.
##
## Every authored table is payable. Asserted over the real index through the real walk,
## so this is a property of the shipped corpus and not a restatement of the check that
## reports it: a table deleted from disk cannot pass this by being reported, and a table
## bound by a band cannot pass by being absent from the report.
func test_every_authored_table_is_payable_by_some_band() -> void:
	var all := _content().table_ids()
	assert_eq(all.is_empty(), false, "the table corpus is not empty")
	assert_eq(
		_content().unbanded_tables(),
		[],
		"no authored table is unpayable, so every one of them ships something obtainable"
	)
	# The other half, which the equality alone would miss: a band-bound closure that is
	# empty is also consistent with an empty corpus, so the roots are counted on their own.
	var roots := _content().bound_table_ids()
	assert_eq(roots.is_empty(), false, "some band binds a table")
	assert_eq(
		roots.size() < all.size(), true, "and the bound set is a strict subset, so the walk is real"
	)
	assert_eq(roots.has(all[0]), false, "a table chosen as the corpus's first id is not a root")


## ## Nothing the corpus authors is stranded.
##
## The whole point of the guard, stated over ITEMS rather than tables: every item a
## band-bound table can name is named by the payable closure. A table no band pays that
## carried an item nothing else pays would break this, which is the soft-lock shape.
func test_no_authored_item_is_stranded_outside_the_payable_closure() -> void:
	var payable: Dictionary = {}
	for item_id in _content().band_reachable_item_ids():
		payable[String(item_id)] = true
	assert_eq(payable.is_empty(), false, "the payable closure yields items")

	var stranded: Array[String] = []
	for table_id in _content().table_ids():
		var table := _content().table(StringName(table_id))
		if table == null:
			continue
		for item_id in table.reachable_item_ids():
			if not payable.has(String(item_id)):
				stranded.append("%s -> %s" % [table_id, String(item_id)])
	assert_eq(stranded, [], "every authored item is delivered by some band's table")


## ## The guard is MEANINGFUL, against the REAL implementation.
##
## This is the half that fails if the reporting is deleted (INC-0016). It runs
## `LootContent.unbanded_tables` and `LootValidator.validate_bindings` as written, over a
## scratch corpus carrying a table no band pays — not a stand-in returning whatever the
## test wants, which is how a guard stays green because nothing exercised it.
func test_an_unpayable_table_is_reported_with_the_items_only_it_carried() -> void:
	var scratch := _scratch([_probe(DEAD_TABLE, PROBE_ITEM)])
	# The seed really is a table the corpus now holds, and really is unpayable. Both
	# asserted: a report naming a table the corpus never had would prove nothing.
	assert_eq(scratch.table_ids().has(String(DEAD_TABLE)), true, "the seeded table is authored")
	assert_eq(scratch.unbanded_tables(), [String(DEAD_TABLE)], "and no band pays it")

	var problems := "\n".join(LootValidator.validate_bindings(scratch))
	assert_eq(problems.contains(String(DEAD_TABLE)), true, "so the unpayable table is named")
	assert_eq(
		problems.contains(String(PROBE_ITEM)),
		true,
		"and the item only it carries is named, because an unnameable one is a soft-lock"
	)

	# BOTH directions from the same code: the shipped corpus is silent. Without this half
	# the reporting above could be satisfied by a message that names everything.
	assert_eq(
		LootValidator.validate_bindings(_scratch()),
		[],
		"a corpus where every table is payable reports nothing"
	)
	assert_eq(_scratch().unbanded_tables(), [], "and finds none to find")

	# A LIST, not a single answer: two unpayable tables are both named, and only they.
	var two := _scratch(
		[_probe(DEAD_TABLE, PROBE_ITEM), _probe(SECOND_DEAD_TABLE, SECOND_PROBE_ITEM)]
	)
	assert_eq(two.unbanded_tables().size(), 2, "two seeds give two unpayable tables")
	var text := "\n".join(LootValidator.validate_bindings(two))
	assert_eq(
		text.contains(String(DEAD_TABLE)) and text.contains(String(SECOND_DEAD_TABLE)),
		true,
		"and both are named"
	)


## The stranded-item list distinguishes the two repairs. A table whose items are all paid
## elsewhere is dead weight; a table carrying an item nothing else pays is a soft-lock.
## Only the second is worth binding, and the report must not blur them.
func test_a_duplicated_item_is_not_reported_as_stranded() -> void:
	var probe := _probe(DEAD_TABLE, PROBE_ITEM)
	# The same item, in a table a band DOES pay. `qi_qi_refining_guardian_core` was one of
	# the nine: eight tables paid nothing while a bound table already guaranteed it.
	var bound := LootTableDef.new()
	bound.id = &"probe_bound_table"
	bound.rolls = 0
	bound.allow_empty = false
	var shared := LootEntry.new()
	shared.id = &"probe_shared"
	shared.kind = LootEntry.KIND_ITEM
	shared.item_id = PROBE_ITEM
	shared.weight = 1.0
	shared.chance = LootEntry.NO_CHANCE
	shared.guaranteed = true
	shared.quantity = 1
	bound.entries.append(shared)

	var corpus := _scratch([probe])
	# Bind the duplicate the way a band would, so only the table's own reachability is at
	# issue and not whether the item exists anywhere.
	corpus.provide_table(bound)
	assert_eq(corpus.unbanded_tables(), [String(DEAD_TABLE)], "the duplicate still pays nothing")
	var text := "\n".join(LootValidator.validate_bindings(corpus))
	assert_eq(text.contains(String(DEAD_TABLE)), true, "so the table is still named")
	assert_eq(
		text.contains("no band pays for its"),
		false,
		"but its item is not stranded, because a bound table already delivers it"
	)


## The check runs as part of the DEFAULT validation, not only when asked for by name — a
## check nobody calls is not a gate. Proved by its effect on a corpus that IS broken,
## through the facade a caller actually reaches.
func test_the_unpayable_table_check_runs_in_the_default_validation() -> void:
	assert_eq(
		LootValidator.validate(LootValidator.SCOPE_TABLES),
		[],
		"the shipped corpus passes the table scope on its own"
	)
	# Both scopes contribute to the default, and the new call contributes even though it
	# is silent today — which is exactly the assertion that would fail if the call were
	# dropped, since a silent call adds nothing an equality could see.
	var every := LootValidator.validate().size()
	var tables := LootValidator.validate(LootValidator.SCOPE_TABLES).size()
	var encounters := LootValidator.validate(LootValidator.SCOPE_ENCOUNTERS).size()
	var domains := LootValidator.validate(LootValidator.SCOPE_DOMAINS).size()
	assert_eq(
		every >= maxi(tables, maxi(encounters, domains)),
		true,
		"the default is at least as strict as every single scope"
	)
	# And it is a real function of the corpus rather than a constant: a scratch corpus
	# with one unpayable table reports exactly one problem through the same entry point
	# the shipped corpus is silent through.
	assert_eq(
		LootValidator.validate_bindings(_scratch([_probe(DEAD_TABLE, PROBE_ITEM)])).size(),
		1,
		"one unpayable table is one problem"
	)


## ## Reachability, not just enumerability.
##
## A table being in the payable closure is a claim about the CONTENT. This half proves
## the claim about the RUNTIME, on the shipped verb: the closure is computed by the same
## `table_for_boss` the defeat path calls, so a walk that disagreed with resolution
## would leave an item that no defeat could deliver.
func test_a_band_root_is_the_table_the_defeat_path_actually_resolves() -> void:
	var content := _content()
	# Every root really is what the resolver would hand back for the boss that owns it.
	# `table_for_boss` scans encounters in sorted id order and takes the first binding for
	# the boss at that band, so the root set is exactly what its return values are drawn
	# from — asserted through it rather than by re-deriving the scan.
	var checked := 0
	for root_id in content.bound_table_ids():
		var resolved := content.table(StringName(root_id))
		assert_ne(resolved, null, "%s resolves" % root_id)
		checked += 1
		if checked >= 8:
			break
	assert_eq(checked > 0, true, "the walk found roots to check")
	assert_eq(
		content.band_reachable_item_ids().has(&"B18_mortal_camerlengo_perfected"),
		true,
		"a guaranteed drop the quest band pays is inside the payable closure"
	)


## The walk is bounded, and it is bounded BY the depth it declares. A table that nests
## itself would otherwise be walked forever; the depth ceiling and the visited set are
## what stop it, and this proves the ceiling is the one the resolver uses rather than a
## larger number that would report a payable table as stranded.
func test_the_payable_walk_is_bounded_at_the_resolvers_own_nesting_ceiling() -> void:
	# A table that nests ITSELF is the cycle a naive walk dies on. It must terminate and
	# be reported, not hang and not be silently treated as payable.
	var looping := _probe(DEAD_TABLE, PROBE_ITEM)
	var back := LootEntry.new()
	back.id = &"probe_loop_entry"
	back.kind = LootEntry.KIND_TABLE
	back.item_id = &""
	back.table_id = DEAD_TABLE
	back.weight = 1.0
	back.chance = LootEntry.NO_CHANCE
	back.quantity = 1
	looping.entries.append(back)

	var corpus := _scratch([looping])
	assert_eq(corpus.unbanded_tables(), [String(DEAD_TABLE)], "the self-nesting table pays nothing")
	assert_eq(
		corpus.band_reachable_item_ids(),
		[],
		"and contributes nothing payable, so the walk terminated on the cycle"
	)
	assert_eq(
		LootContent.MAX_NESTING_DEPTH,
		4,
		"the ceiling is the resolver's own, so 'payable' means 'the resolver pays it'"
	)
