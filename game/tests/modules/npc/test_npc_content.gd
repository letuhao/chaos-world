extends TestCase

## The ledger, the record, the def and the catalog underneath the facade.
##
## `test_npc_tier.gd` and `test_npc_boot.gd` drive the feature end to end through
## `NpcApi`. This suite covers the four files neither of them reaches directly:
## `npc_state.gd` (the ledger and its caps), `npc_roster_entry.gd` (one tracked npc's
## remembered state and its tally table), `npc_def.gd` (stage lookup by id rather than
## by position) and `npc_catalog.gd` (what the catalog answers for an id it does not
## ship), plus the authored `.tres` cast those four read.
##
## ## Why this suite reaches for the internals
##
## `NpcApi.state()` hands back the PERSISTED dictionary, not the ledger, and there is no
## verb for `ensure_entry`, `remove` or `from_dict` at all — those are internal to the
## ledger by design, so the overflow and malformed-save behaviour is only reachable from
## here. Every other assertion the facade can answer goes through it.
##
## ## Nothing here leaks
##
## No `Node` is created, nothing is `instantiate()`d and nothing is `add_child()`ed, so
## there is no node to `free()`. `Actor` and `NpcState` are `RefCounted` and die with the
## test that built them. This suite deliberately never calls `NpcApi.attach`: that sets a
## static `_current_player` that nothing can clear, so every suite that attaches pins one
## player for the life of the process. The two process-wide singletons this suite does
## write to are reset in BOTH `setup()` and `teardown()`, because the runner shares one
## process across every suite.
##
## ## No `while` anywhere
##
## Every iteration below is a `for` over a range or a container that was snapshotted
## first, so `tests/arch_rules/test_no_unbounded_wait.gd` has nothing to rule on.

const CAST_DIR := "res://data/npc/cast/"

const ELDER := &"elder_wei"
const SMITH := &"smith_bearcutter"
const DRIFTER := &"drifter"
const GATE_KEEPER := &"gate_keeper_bo"

## The shipped individuals, in TEXT order. `npc_ids()` is not asserted to be in
## this order — see the ordering test for why that would be an assertion about the
## engine's string table rather than about this module.
##
## **This list is a census, and authoring an NPC means editing it.** That is the
## point: a new `.tres` under `cast/` that nobody declared here fails this test, so
## the cast cannot grow silently. `elder_qin` arrived with the brotherhood oath
## (BL-0745) as the WITNESS to another elder's pact, and `courting_elder_bo` with the
## pursuit seed as an authored suitor.
const SHIPPED_TEXT_ORDER := [
	"courting_elder_bo",
	"drifter",
	"elder_qin",
	"elder_wei",
	"gate_keeper_bo",
	"smith_bearcutter",
]


func setup() -> void:
	NpcCatalog.instance().reset()
	NpcRegistry.instance().reset()


func teardown() -> void:
	# Both singletons are process-wide. The runner calls `teardown` after EVERY test and
	# reuses this suite's catalog reference in the next `setup`, so leaving a fixture def
	# installed would hand it to whichever npc suite runs next.
	NpcCatalog.instance().reset()
	NpcRegistry.instance().reset()


# --- NpcState: the roster ledger ------------------------------------------------


## The cap REFUSES. `ensure_entry` returns null and the ledger keeps every entry it
## already had — a world that met too many npcs fails loudly at the bound instead of
## quietly dropping whichever face a dictionary happened to evict first, which would be
## a lost story npc diagnosed far from the cause.
func test_the_roster_refuses_at_its_cap_rather_than_trimming_the_oldest() -> void:
	var state := NpcState.new()
	for index in range(NpcState.MAX_ROSTER):
		state.ensure_entry(_key(index), _key(index))
	assert_eq(state.entry_count(), NpcState.MAX_ROSTER, "the ledger filled to its named cap")
	var overflow := state.ensure_entry(&"one_too_many", &"one_too_many")
	assert_eq(overflow, null, "past the cap it refuses rather than inventing a row")
	assert_eq(state.entry_count(), NpcState.MAX_ROSTER, "and nothing already tracked was trimmed")
	assert_eq(state.has_entry(&"npc_000"), true, "the oldest entry is still there")
	assert_eq(state.has_entry(&"npc_255"), true, "and so is the newest")


## Two properties of the cap that a `>=` / `>` slip or a "seen N ids" watermark would
## both break: an id already on the roster is still served at the cap, and a slot freed
## by `remove` is usable again.
func test_the_roster_cap_is_a_live_count_rather_than_a_high_water_mark() -> void:
	var state := NpcState.new()
	for index in range(NpcState.MAX_ROSTER):
		state.ensure_entry(_key(index), _key(index))
	assert_ne(state.ensure_entry(&"npc_000", &"other_def"), null, "a known id is served at the cap")
	assert_eq(state.entry_count(), NpcState.MAX_ROSTER, "and re-serving it minted no second row")
	assert_eq(state.remove(&"npc_000"), true, "a tracked npc leaves the roster")
	assert_ne(
		state.ensure_entry(&"late_arrival", &"late_arrival"),
		null,
		"the freed slot is usable, so the bound counts rows and not ids ever seen"
	)
	assert_eq(state.entry_count(), NpcState.MAX_ROSTER, "and the roster is back at the cap")


## `npc_ids` is what the ledger holds; `tracked_ids` is what a "who have I met" screen
## lists. They are not the same list, and an entry that defaults to an untracked tier
## must not leak into the second one.
func test_tracked_ids_lists_only_the_remembered_while_npc_ids_lists_everyone() -> void:
	var state := NpcState.new()
	var drifter_entry := state.ensure_entry(DRIFTER, DRIFTER)
	var smith_entry := state.ensure_entry(SMITH, SMITH)
	assert_eq(state.npc_ids(), [DRIFTER, SMITH], "the ledger holds both")
	assert_eq(
		state.tracked_ids(),
		[],
		"a fresh entry defaults to an untracked tier, so nothing is remembered yet"
	)
	smith_entry.tier = NpcTier.MAJOR
	drifter_entry.tier = NpcTier.MAJOR
	assert_eq(
		state.tracked_ids(), [DRIFTER, SMITH], "a tier change is what puts an npc on the list"
	)
	drifter_entry.tier = NpcTier.TRANSIENT
	assert_eq(state.tracked_ids(), [SMITH], "and untracking one takes them off it again")
	assert_eq(state.npc_ids(), [DRIFTER, SMITH], "without erasing the row: they were still met")


## `remove` reports what it did, so a caller can tell "forgotten" from "never met" — the
## difference the three-state vocabulary in ADR 0083 depends on.
func test_remove_reports_whether_it_removed_anything() -> void:
	var state := NpcState.new()
	state.ensure_entry(SMITH, SMITH)
	assert_eq(state.remove(&"no_such_npc"), false, "an unknown id removes nothing")
	assert_eq(state.entry_count(), 1, "and leaves the roster alone")
	assert_eq(state.remove(SMITH), true, "a known id is removed")
	assert_eq(state.entry(SMITH), null, "so the entry is gone")
	assert_eq(state.remove(SMITH), false, "and removing it twice says so")
	assert_eq(state.entry_count(), 0, "without inventing or double-counting")


## The save shape has to survive a write/read/write unchanged, or every load would
## rewrite the roster and a save would drift from itself one round trip at a time. Every
## field is exercised: tier, stage, presence, location, the tally and the off-stage
## actor payload.
func test_the_roster_round_trips_through_its_save_payload() -> void:
	var state := NpcState.new()
	var entry := state.ensure_entry(ELDER, ELDER)
	entry.tier = NpcTier.STORY
	entry.stage_id = &"sworn_servant"
	entry.set_stage_index(1)
	entry.presence = NpcPresence.RETIRED
	entry.location_id = &"qi_dao"
	entry.bump_tally(&"favours", 3)
	entry.payload = {"id": "npc_elder_wei", "base": {"physique": 14.0}, "tags": ["elder"]}
	var saved := state.to_dict()
	assert_eq(saved["version"], NpcState.SCHEMA_VERSION, "the payload is versioned")
	var restored := NpcState.from_dict(saved)
	assert_eq(restored.to_dict(), saved, "a write, a read and a write agree exactly")
	var restored_entry := restored.entry(ELDER)
	assert_ne(restored_entry, null, "the entry came back")
	assert_eq(restored_entry.tier, NpcTier.STORY, "with their tier")
	assert_eq(restored_entry.stage_id, &"sworn_servant", "and the stage they were left at")
	assert_eq(
		restored_entry.presence, NpcPresence.RETIRED, "and a retirement that outranks the room"
	)
	assert_eq(restored_entry.location_id, &"qi_dao", "and where they were last met")
	assert_eq(restored_entry.stage_index(), 1, "and the ordinal that blocks a rewind")
	assert_eq(restored_entry.tally_of(&"favours"), 3, "and what they owe you")
	assert_eq(
		restored_entry.payload["base"],
		{"physique": 14.0},
		"and the off-stage actor payload, which is the whole off-stage mechanism"
	)


## A save is untrusted input. A payload with nothing in it, or with an entry whose
## fields are all missing, must restore as the module's own empty shape rather than
## crashing a load or inventing a stranger the player is supposed to remember.
func test_an_absent_or_malformed_payload_restores_as_an_empty_roster() -> void:
	assert_eq(NpcState.new().to_dict(), NpcState.empty(), "a fresh ledger is the empty save shape")
	assert_eq(
		NpcState.from_dict({}).to_dict(), NpcState.empty(), "and so is a payload with no entries"
	)
	assert_eq(
		NpcState.from_dict({"version": 9}).to_dict(),
		NpcState.empty(),
		"and one with no entries key"
	)
	var restored := NpcState.from_dict({"entries": {"nobody": {}}})
	assert_eq(restored.entry_count(), 1, "an entry with no fields is still one row")
	var entry := restored.entry(&"nobody")
	assert_eq(entry.npc_id, &"", "with no identity of its own")
	assert_eq(entry.tracked(), false, "and an untracked tier, so it cannot become a remembered npc")
	assert_eq(entry.presence, NpcPresence.UNKNOWN, "and unknown presence, not a guessed one")
	assert_eq(entry.tally_of(&"anything"), 0, "and no tally")


## A corrupt enum must normalize to the safe end of the vocabulary: an unreadable tier
## makes the npc a stranger, and an unreadable presence makes them unknown. Neither may
## fall through to a value that changes what the player is told.
func test_a_corrupt_tier_or_presence_falls_back_rather_than_being_believed() -> void:
	var entry := NpcRosterEntry.from_dict(
		{"npc_id": "smith_bearcutter", "tier": "legendary", "presence": "somewhere_else"}
	)
	assert_eq(entry.tier, NpcTier.DEFAULT, "an unreadable tier reads as the untracked default")
	assert_eq(entry.tracked(), false, "so a stranger cannot be smuggled into the roster")
	assert_eq(
		entry.presence,
		NpcPresence.UNKNOWN,
		"an unreadable presence reads as unknown rather than as present or retired"
	)


## The tally is written with String keys on purpose, because a JSON round trip stringifies
## a StringName and a save written by another tool would otherwise stop finding its own
## verbs. This pins the reason the shape exists.
func test_a_tally_survives_a_string_keyed_save_payload() -> void:
	var entry := NpcRosterEntry.new(SMITH, SMITH)
	entry.bump_tally(&"favours", 2)
	var saved := entry.to_dict()
	assert_eq(saved["tally"].keys(), ["favours"], "the payload is keyed by text")
	var restored := NpcRosterEntry.from_dict(saved)
	assert_eq(restored.tally_of(&"favours"), 2, "so a verb written as text reads back as its id")
	assert_eq(restored.tally.has(&"favours"), true, "and it is stored under the id again")


# --- NpcRosterEntry: one tracked npc's record -----------------------------------


## `MAX_TALLY_KEYS` refuses the seventeenth verb and keeps counting the sixteen it has:
## a runaway verb cannot grow a save without limit, and a full table cannot freeze the
## counters the story is already reading.
func test_the_tally_refuses_a_seventeenth_verb_and_keeps_counting_the_ones_it_has() -> void:
	var entry := NpcRosterEntry.new(ELDER, ELDER)
	for index in range(NpcRosterEntry.MAX_TALLY_KEYS):
		assert_eq(entry.bump_tally(_key(index)), true, "verb %d fits" % index)
	assert_eq(entry.tally.size(), NpcRosterEntry.MAX_TALLY_KEYS, "the table is full")
	assert_eq(entry.bump_tally(&"one_too_many"), false, "a seventeenth verb is refused")
	assert_eq(entry.tally.size(), NpcRosterEntry.MAX_TALLY_KEYS, "so the save did not grow")
	assert_eq(entry.tally_of(&"one_too_many"), 0, "and the refused verb was never recorded")
	assert_eq(
		entry.bump_tally(&"npc_000", 5), true, "a verb already counted still counts at the cap"
	)
	assert_eq(entry.tally_of(&"npc_000"), 6, "so a full table cannot freeze the ladder")


## An empty verb would consume one of the sixteen slots forever while counting nothing,
## so it is not recorded at all.
func test_an_empty_verb_is_never_counted() -> void:
	var entry := NpcRosterEntry.new(ELDER, ELDER)
	assert_eq(entry.bump_tally(&""), false, "there is no such verb")
	assert_eq(entry.tally.size(), 0, "so nothing was written")


## The ordinal is stored separately from `stage_id` so advancement can refuse a rewind
## without consulting the catalog. It lives in the tally table, so it is worth pinning
## that it round-trips and that it is accounted for in the cap.
func test_the_stage_ordinal_round_trips_and_costs_a_tally_slot() -> void:
	var entry := NpcRosterEntry.new(ELDER, ELDER)
	assert_eq(entry.stage_index(), 0, "nobody has moved yet")
	entry.set_stage_index(2)
	assert_eq(entry.stage_index(), 2, "the ordinal is set")
	var restored := NpcRosterEntry.from_dict(entry.to_dict())
	assert_eq(restored.stage_index(), 2, "and survives a save")
	assert_eq(entry.tally.size(), 1, "the ordinal is itself a tally row")
	for index in range(NpcRosterEntry.MAX_TALLY_KEYS - 1):
		entry.bump_tally(_key(index))
	assert_eq(entry.bump_tally(&"one_too_many"), false, "so an advanced npc has one verb fewer")
	assert_eq(entry.stage_index(), 2, "and the ordinal is untouched by the refusal")


## A save must not share a reference with the live ledger or with the object it was read
## from, or an edit on either side rewrites the other behind the save's back.
func test_a_save_payload_is_a_copy_rather_than_a_shared_reference() -> void:
	var entry := NpcRosterEntry.new(SMITH, SMITH)
	entry.payload = {"health": 12}
	var saved := entry.to_dict()
	saved["payload"]["health"] = 99
	assert_eq(entry.payload["health"], 12, "editing the save cannot rewrite the ledger")
	var restored := NpcRosterEntry.from_dict(saved)
	entry.payload["health"] = 7
	assert_eq(restored.payload["health"], 99, "and editing the ledger cannot rewrite the save")


# --- NpcDef: a stage is addressed by id, never by position ----------------------


## A gate names the stage it requires, so lookup has to be exact and a miss has to be
## null. Falling through to the first stage would let a half-authored def open
## everything.
func test_a_stage_is_found_by_id_and_an_unknown_one_is_never_guessed() -> void:
	var def := _def(SMITH, NpcTier.MAJOR, [_stage(&"stranger", 0), _stage(&"trusted_smith", 1)])
	assert_ne(def.stage(&"trusted_smith"), null, "a declared stage is found")
	assert_eq(def.stage(&"trusted_smith").stage_id, &"trusted_smith", "and it is that one")
	assert_eq(def.stage(&"no_such_stage"), null, "an undeclared stage is null, not the first")
	assert_eq(def.stage(&""), null, "and so is an empty id")
	assert_eq(def.stage_index_of(&"trusted_smith"), 1, "the ordinal comes back with it")
	assert_eq(
		def.stage_index_of(&"no_such_stage"), -1, "and an unknown one is reported, not guessed"
	)


## The ordinal is the AUTHORED number, not the position in the array. An author who
## inserts a rung mid-ladder must not renumber every save below it, so the two are
## different things and this keeps them different.
func test_a_stage_ordinal_is_the_authored_index_and_not_the_array_position() -> void:
	var def := _def(SMITH, NpcTier.MAJOR, [_stage(&"third", 20), _stage(&"first", 10)])
	assert_eq(def.stage_index_of(&"third"), 20, "the authored index, not its slot in the array")
	assert_eq(def.stage_index_of(&"first"), 10, "for every stage, however the array is ordered")


## The ladder is walked by the AUTHORED index rather than by the array's slot order, so a
## ladder whose stages were not authored in order still resolves each step forward and
## never back. Pinned as a SET comparison because `next_stage_id` returns the first
## qualifying stage it meets in array order, not the lowest index above the current one —
## every rung is reachable, which is the property `advance_stage` depends on.
func test_the_next_stage_is_read_off_the_authored_index_not_the_array_position() -> void:
	var shuffled: Array[NpcStageDef] = [
		_stage(&"retired", 2), _stage(&"gatekeeper", 0), _stage(&"sworn", 1)
	]
	var def := _def(ELDER, NpcTier.STORY, shuffled)
	def.initial_stage = &"gatekeeper"
	var second := def.next_stage_id(&"gatekeeper")
	assert_ne(second, &"", "there is a next stage")
	assert_eq(
		def.stage_index_of(second) > 0, true, "and it is a later rung, not the one left behind"
	)
	assert_eq(def.next_stage_id(&"retired"), &"", "and the last rung ends the ladder")


## In the ordinary authored case — the array in index order — one step is the immediate
## successor, and the last stage resolves to nothing rather than wrapping around. This is
## the contract `tally` walks: `advance_after` counts up to it and the ladder must not
## restart.
func test_one_step_forward_is_the_immediate_successor_and_the_ladder_ends() -> void:
	var def := _def(
		ELDER, NpcTier.STORY, [_stage(&"gatekeeper", 0), _stage(&"sworn", 1), _stage(&"retired", 2)]
	)
	def.initial_stage = &"gatekeeper"
	assert_eq(def.next_stage_id(&"gatekeeper"), &"sworn", "one step forward")
	assert_eq(def.next_stage_id(&"sworn"), &"retired", "and on to the last")
	assert_eq(def.next_stage_id(&"retired"), &"", "the ladder ends rather than wrapping around")
	assert_eq(def.next_stage_id(&"gatekeeper"), &"sworn", "and answering twice does not move it")


## An id that is not on the ladder resolves to where this individual starts — the answer
## a caller asking "where is this npc now?" needs — rather than to nothing.
func test_an_unknown_stage_id_resolves_to_where_the_individual_starts() -> void:
	var def := _def(ELDER, NpcTier.STORY, [_stage(&"gatekeeper", 0), _stage(&"sworn", 1)])
	assert_eq(
		def.next_stage_id(&"no_such_stage"),
		def.starting_stage_id(),
		"not off the end of the ladder"
	)
	assert_eq(def.next_stage_id(""), def.starting_stage_id(), "nor an empty id")


## `initial_stage` is a convenience, so every way of getting it wrong still resolves:
## unset, naming a stage this def does not declare, and a def with no ladder at all.
func test_starting_stage_falls_back_to_the_first_stage_when_the_author_names_another() -> void:
	var first := _stage(&"gatekeeper", 0)
	var second := _stage(&"sworn", 1)
	var ladder: Array[NpcStageDef] = [first, second]

	var unset := _def(ELDER, NpcTier.STORY, ladder)
	assert_eq(unset.starting_stage_id(), &"gatekeeper", "an unset initial_stage is the first rung")

	var misplaced := _def(ELDER, NpcTier.STORY, ladder)
	misplaced.initial_stage = &"sworn_servant"
	assert_eq(
		misplaced.starting_stage_id(),
		&"gatekeeper",
		"an initial_stage the def does not declare is ignored, not honoured"
	)
	assert_eq(misplaced.stage_index_of(&"sworn_servant"), -1, "and it really is not on the ladder")

	var authored := _def(ELDER, NpcTier.STORY, ladder)
	authored.initial_stage = &"sworn"
	assert_eq(authored.starting_stage_id(), &"sworn", "a declared initial_stage is honoured")

	var no_ladder := _def(DRIFTER, NpcTier.TRANSIENT, [])
	no_ladder.initial_stage = &"gatekeeper"
	assert_eq(no_ladder.starting_stage_id(), &"", "and a def with no ladder has nowhere to start")


# --- NpcCatalog: what it answers, and what it refuses ----------------------------


## Unknown means nothing. A catalog that returned a fallback def would let a typo in a
## room's spawn list stand up somebody nobody authored.
func test_the_catalog_answers_an_unknown_id_with_nothing() -> void:
	NpcCatalog.instance().install([_def(SMITH, NpcTier.MAJOR, [])])
	assert_eq(
		NpcCatalog.instance().definition(&"no_such_npc"), null, "an id it does not ship is null"
	)
	assert_eq(NpcCatalog.instance().definition(&""), null, "and so is the empty id")
	assert_eq(
		NpcCatalog.instance().has_definition(&"no_such_npc"), false, "which is also how it says no"
	)
	assert_ne(NpcCatalog.instance().definition(SMITH), null, "while a shipped id resolves")
	assert_eq(NpcCatalog.instance().has_definition(SMITH), true, "and reports as shipped")


## Complete, duplicate-free and stable between reads. Deliberately NOT asserted to be in
## text order: `Array[StringName].sort()` orders by the interned pointer rather than by
## the string, which is why `DestinyState._sorted_keys` and `WorldFact.ids` sort a
## `String` copy first. Asserting text order here would be asserting a property of the
## engine's string table, not of this module. What a panel actually needs is that a list
## it cycles does not reshuffle between two reads.
func test_ids_are_complete_and_do_not_reorder_between_reads() -> void:
	_install_shipped_cast()
	var catalog := NpcCatalog.instance()
	var first := catalog.npc_ids()
	var second := catalog.npc_ids()
	assert_eq(first, second, "two reads of an unchanged catalog agree")
	assert_eq(first.size(), SHIPPED_TEXT_ORDER.size(), "every shipped cast member is listed once")
	var as_text: Array[String] = []
	for npc_id in first:
		as_text.append(String(npc_id))
	var sorted_text := as_text.duplicate()
	sorted_text.sort()
	assert_eq(sorted_text, SHIPPED_TEXT_ORDER, "and the set is exactly the shipped cast")


## An unnamed def would otherwise take the `""` slot and be answerable by every caller
## that forgot to check, and a reinstall has to replace rather than accumulate.
func test_install_rejects_a_def_that_names_nobody_and_the_last_write_wins() -> void:
	var named := _def(SMITH, NpcTier.MAJOR, [])
	var unnamed := _def(&"", NpcTier.MAJOR, [])
	var replacement := _def(SMITH, NpcTier.STORY, [])
	var batch: Array[NpcDef] = [named, null, unnamed]
	NpcCatalog.instance().install(batch)
	assert_eq(
		NpcCatalog.instance().npc_ids(), [SMITH], "a null and an unnamed def are both skipped"
	)
	assert_eq(
		NpcCatalog.instance().has_definition(&""), false, "so nothing answers to the empty id"
	)
	assert_eq(NpcCatalog.instance().definition(SMITH).tier, NpcTier.MAJOR, "the real def installed")
	NpcCatalog.instance().install([replacement])
	assert_eq(
		NpcCatalog.instance().definition(SMITH).tier,
		NpcTier.STORY,
		"reinstalling the same id replaces the def rather than shadowing it"
	)
	assert_eq(NpcCatalog.instance().npc_ids().size(), 1, "and does not accumulate a second row")


# --- The authored cast ----------------------------------------------------------


## Every `.tres` under the cast directory loads as an `NpcDef`, and its id matches the
## file it lives in — a renamed file whose `npc_id` was not updated ships a cast member
## nothing in the game can name.
func test_every_shipped_cast_file_loads_and_its_id_matches_its_file_name() -> void:
	var paths := ContentScan.files_under(CAST_DIR)
	assert_ne(paths.is_empty(), true, "the cast directory is not empty")
	for path in paths:
		var def := load(path) as NpcDef
		assert_ne(def, null, "%s loads as an NpcDef" % path)
		if def == null:
			continue
		assert_eq(
			String(def.npc_id),
			path.get_file().get_basename(),
			"'%s' is filed under the id the game names it by" % path
		)
		assert_ne(def.display_name, "", "'%s' is named" % String(def.npc_id))
		assert_ne(def.realm_id, &"", "'%s' cultivates" % String(def.npc_id))
		assert_ne(
			def.inhabitant_id, &"", "'%s' names the species it was built from" % String(def.npc_id)
		)
		# The AUTHORED tier, not the normalized one: a typo normalizes to the untracked
		# default and would quietly turn a remembered cast member into a stranger.
		assert_eq(
			NpcTier.is_known(def.tier),
			true,
			"'%s' authors a tier the module recognises" % String(def.npc_id)
		)


## A tracked def with no ladder spawns with an empty `stage_id`, which no gate can ever
## satisfy and no panel can name. Untracked defs may legitimately ship none.
func test_a_tracked_cast_member_ships_a_ladder_to_walk() -> void:
	_install_shipped_cast()
	for def in _shipped_defs():
		if not def.tracked():
			continue
		assert_eq(
			def.stage_count() > 0,
			true,
			"'%s' is remembered, so they need somewhere to start" % String(def.npc_id)
		)
		assert_ne(
			def.starting_stage_id(), &"", "'%s' resolves a starting stage" % String(def.npc_id)
		)


## Strictly increasing indices, unique stage ids, non-empty ids. The ladder is walked by
## index, so two stages sharing one makes the advance order undecidable, and a repeated
## index makes `next_stage_id` pick whichever the array happened to hold.
func test_every_authored_ladder_is_strictly_increasing_and_never_repeats_a_stage() -> void:
	_install_shipped_cast()
	for def in _shipped_defs():
		var previous := -1
		var seen := {}
		for stage_def in def.stages:
			assert_ne(stage_def.stage_id, &"", "'%s' has a stage with an id" % String(def.npc_id))
			assert_eq(
				seen.has(String(stage_def.stage_id)),
				false,
				"'%s' names '%s' once" % [def.npc_id, stage_def.stage_id]
			)
			seen[String(stage_def.stage_id)] = true
			assert_eq(
				stage_def.index > previous,
				true,
				(
					"'%s' stage '%s' is strictly after the one before it"
					% [def.npc_id, stage_def.stage_id]
				)
			)
			previous = stage_def.index


## At most one terminal stage, and it is the last rung: a terminal stage half way up a
## ladder retires the npc with every later rung unreachable.
func test_a_terminal_stage_ends_the_ladder_rather_than_sitting_half_way_up_it() -> void:
	_install_shipped_cast()
	for def in _shipped_defs():
		var terminals := 0
		var terminal_at := -1
		for position in def.stages.size():
			if def.stages[position].terminal:
				terminals += 1
				terminal_at = position
		assert_eq(terminals <= 1, true, "'%s' retires at most once" % String(def.npc_id))
		if terminals == 1:
			assert_eq(
				terminal_at,
				def.stages.size() - 1,
				(
					"'%s' ends at its retirement rather than leaving later rungs unreachable"
					% String(def.npc_id)
				)
			)


## `initial_stage` is authored by hand next to a ladder it has to agree with. A ladder
## reorder that drops the named stage would otherwise spawn everyone one rung down.
func test_an_initial_stage_is_a_stage_the_def_itself_declares() -> void:
	_install_shipped_cast()
	for def in _shipped_defs():
		if def.initial_stage == &"":
			continue
		assert_ne(
			def.stage(def.initial_stage),
			null,
			"'%s' starts at '%s', which its own ladder declares" % [def.npc_id, def.initial_stage]
		)
		assert_eq(
			def.starting_stage_id(),
			def.initial_stage,
			"'%s' therefore resolves the stage it was authored with" % String(def.npc_id)
		)


# --- Fixtures -------------------------------------------------------------------


## `load()` returns the engine's CACHED resource, so a shipped def is shared with every
## suite in the process. It is read here and never written; a test that mutated one would
## change content for the rest of the run.
func _install_shipped_cast() -> void:
	for def in _shipped_defs():
		NpcCatalog.instance().install([def])


func _shipped_defs() -> Array[NpcDef]:
	var out: Array[NpcDef] = []
	for path in ContentScan.files_under(CAST_DIR):
		var def := load(path) as NpcDef
		if def != null:
			out.append(def)
	return out


func _stage(stage_id: StringName, index: int) -> NpcStageDef:
	var stage := NpcStageDef.new()
	stage.stage_id = stage_id
	stage.display_name = String(stage_id)
	stage.index = index
	return stage


func _def(npc_id: StringName, tier: StringName, stages: Array) -> NpcDef:
	var def := NpcDef.new()
	def.npc_id = npc_id
	def.display_name = String(npc_id)
	def.tier = tier
	def.realm_id = &"qi_refining"
	for stage_def in stages:
		def.stages.append(stage_def)
	return def


## A zero-padded id, so lexical and numeric order agree and a sorted list reads in the
## order it was written.
func _key(index: int) -> StringName:
	return StringName("npc_%03d" % index)
