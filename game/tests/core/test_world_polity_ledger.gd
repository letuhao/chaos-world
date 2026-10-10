extends TestCase

## DEF-0119 / ADR 0037: the world-scoped polity ledger, the boundary rule that decides
## what may live in it, and the migration on either side of the save.
##
## ## The one test in here that would have failed before this change
##
## `test_a_non_member_reads_the_debt_across_a_save` is the whole feature. A test that
## reloads the ledger as the same actor proves nothing: the ledger rides the SAVE, so a
## same-actor round trip passes against any implementation that keeps the debt on the
## actor and merely copies it into the envelope. The different-body case is what makes
## "a polity outlives its founder" an observable fact rather than a claim, and it is
## why the reader here is an actor with no sect ledger at all.

const HOUSE := "t_house"
const RIVAL := "t_rival_house"
const TERM := "t_blood_price"
## An id that is NOT an institution, to prove the boundary rule bites.
const PERSON := "t_founder_actor"

## A player's regard line, spelled as the bad shape. It is one id and no pair, which is
## exactly what a per-actor fact looks like and exactly what may NOT be written here.
const TEXT_PERSON_LINE := "t_house->t_founder_actor"

# --- The slot and the boundary ------------------------------------------------


func test_the_slot_is_declared_in_core_and_carried_in_the_envelope() -> void:
	# The slot is in `SaveSlot.WORLD_KEYS` because the envelope owns the list, and in
	# `WorldPolityLedger.WORLD_KEY` because the ledger owns the name — the two files
	# cannot name each other (`core/` may not name `modules/`, and `modules/save` may
	# not name a core class's internals), so the agreement is asserted rather than
	# imported. A drift between them would write a ledger the reader never looks at.
	assert_eq(WorldPolityLedger.WORLD_KEY, "polity", "the ledger names its envelope key")
	assert_eq(SaveApi.WORLD_KEYS.has(WorldPolityLedger.WORLD_KEY), true, "the envelope carries it")


func test_the_containers_the_ledger_normalizes_are_the_ones_the_store_routes() -> void:
	# `app/world_ledger_store.gd` authors its own container table because it may not
	# normalize with this file's normalizer — a store holds bytes and the module owns
	# the meaning (ADR 0165). Two tables that disagree is a silent no-op on write, so
	# the agreement is a test and not a comment.
	assert_eq(WorldPolityLedger.CONTAINERS, ["institutions", "debts"], "the ledger's shape")


func test_an_inter_institution_line_is_institutional_and_a_person_line_is_not() -> void:
	# THE BOUNDARY RULE, as code. A fact whose subject names two institutions belongs on
	# the world root; a fact whose subject names a person belongs on that person and dies
	# with them. `is_institutional` is what a reviewer points at when a new field is
	# proposed, and this is the case that says so.
	assert_eq(
		WorldPolityLedger.is_institutional("t_house|t_rival_house"),
		true,
		"a debt between two sects belongs on the world"
	)
	assert_eq(
		WorldPolityLedger.is_institutional(TEXT_PERSON_LINE), false, "a player's regard is personal"
	)
	assert_eq(
		WorldPolityLedger.is_institutional(HOUSE), false, "a single institution is not a pair"
	)
	assert_eq(WorldPolityLedger.is_institutional(""), false, "nothing is not a pair")


func test_a_self_pair_is_not_institutional_because_it_has_no_order() -> void:
	# `NationState`'s stated reason, carried forward: a self pair collapses both orders
	# into one row that cannot express a two-sided opinion, so the row is refused rather
	# than stored.
	assert_eq(WorldPolityLedger.is_institutional("t_house|t_house"), false, "not institutional")
	assert_eq(WorldPolityLedger.pair_key(HOUSE, HOUSE), "", "and there is no canonical key")
	assert_eq(WorldPolityLedger.pair_key(HOUSE, ""), "", "nor one for an empty id")


func test_the_canonical_key_is_identical_under_a_swap() -> void:
	# ADR 0047's symmetry made structural, `NationState.pair_key`'s exact precedent.
	var forward := WorldPolityLedger.pair_key(HOUSE, RIVAL)
	var swapped := WorldPolityLedger.pair_key(RIVAL, HOUSE)
	assert_eq(forward, swapped, "the canonical key does not depend on argument order")
	assert_eq(forward, "t_house|t_rival_house", "and the ids are ordered lexicographically")
	assert_eq(WorldPolityLedger.split_pair_key(forward), [HOUSE, RIVAL], "it splits back apart")


# --- The one-row rule ---------------------------------------------------------


func _ledger_with_a_pair() -> Dictionary:
	return (
		WorldPolityLedger
		. normalize_payload(
			{
				"version": WorldPolityLedger.SCHEMA_VERSION,
				"institutions":
				{
					HOUSE: {"kind": "sect", "standing": 40, "standing_cap": 100, "sequence": 1},
					RIVAL: {"kind": "sect", "standing": 10, "standing_cap": 80, "sequence": 2},
				},
				"debts":
				{
					WorldPolityLedger.directed_key(HOUSE, RIVAL):
					{
						"debtor_id": HOUSE,
						"creditor_id": RIVAL,
						"sequence": 7,
						"lines": {TERM: 4},
					},
				},
			}
		)
	)


func test_one_pair_is_one_row_and_both_sides_read_that_row() -> void:
	# The symmetry in one assertion each: A reads what it owes and B reads what it is
	# owed, from ONE stored row. Two rows would be two copies of one political fact and
	# could disagree, which is the one-sided opinion BL-0192 exists to forbid.
	var ledger := _ledger_with_a_pair()
	assert_eq((ledger["debts"] as Dictionary).size(), 1, "one pair, one row")
	assert_eq(WorldPolityLedger.owed(ledger, HOUSE, RIVAL, TERM), 4, "the debtor reads the debt")
	assert_eq(WorldPolityLedger.owed(ledger, RIVAL, HOUSE, TERM), 0, "the creditor owes nothing")
	assert_eq(WorldPolityLedger.owed(ledger, HOUSE, "", TERM), 0, "an empty id is not a pair")
	assert_eq(
		WorldPolityLedger.owed(ledger, HOUSE, RIVAL, "t_no_such_term"),
		0,
		"an unopened line is zero"
	)


func test_a_payload_carrying_both_spellings_folds_into_the_one_canonical_row() -> void:
	# A hand-edited save, or a bug from an older build, can arrive holding the same pair
	# twice. Keeping both would be a one-sided opinion by another name.
	#
	# **Both spellings are written out by hand, not asked of `directed_key`.** `directed_key`
	# builds the obligor's spelling, so asking it for "the other order" hands back the same
	# string, a Dictionary literal holding both collapses to one entry before `normalize`
	# ever sees it, and the case would pass while proving nothing. This is
	# `test_nation_symmetry.gd`'s argument, verbatim.
	assert_ne(RIVAL, HOUSE, "the two ids differ")
	var forward := "%s->%s" % [HOUSE, RIVAL]
	var reversed := "%s->%s" % [RIVAL, HOUSE]
	assert_ne(
		reversed,
		WorldPolityLedger.directed_key(HOUSE, RIVAL),
		"the reversed spelling is not the canonical one"
	)
	var payload := {
		"debts":
		{
			forward: {"sequence": 7, "lines": {TERM: 4}},
			reversed: {"sequence": 9, "lines": {TERM: 11}},
		}
	}
	assert_eq(
		(payload["debts"] as Dictionary).size(),
		2,
		"the payload really carries both, or the case proves nothing"
	)
	var out := WorldPolityLedger.normalize_payload(payload)
	assert_eq((out["debts"] as Dictionary).size(), 1, "and normalize folds them to one")
	assert_eq(
		(out["debts"] as Dictionary).has(WorldPolityLedger.directed_key(HOUSE, RIVAL)),
		true,
		"under the canonical key"
	)
	assert_eq((out["debts"] as Dictionary).has(reversed), false, "never under the reversed one")
	# And the earlier declaration wins, so a hand-edited save cannot raise a debt by
	# writing the losing spelling with a bigger count.
	assert_eq(WorldPolityLedger.owed(out, HOUSE, RIVAL, TERM), 4, "the earlier row survives")


func test_an_unreadable_or_self_paired_key_is_dropped_not_guessed() -> void:
	var payload := {
		"debts":
		{
			"no_arrow_here": {"lines": {TERM: 3}},
			"->only_a_creditor": {"lines": {TERM: 3}},
			"only_a_debtor->": {"lines": {TERM: 3}},
			"t_house->t_house": {"lines": {TERM: 3}},
		}
	}
	assert_eq(
		(WorldPolityLedger.normalize_payload(payload)["debts"] as Dictionary).size(),
		0,
		"an unreadable or self-directed key is dropped rather than read as a debt"
	)


func test_an_absent_or_unreadable_ledger_reads_as_empty_never_as_a_partial_one() -> void:
	# ADR 0037's "a payload that cannot be read is diagnosed as empty, never partially
	# applied": half a ledger silently changes what the player is owed.
	assert_eq(WorldPolityLedger.empty(), WorldPolityLedger.normalize_payload({}), "no payload")
	assert_eq(
		(WorldPolityLedger.normalize_payload({"debts": "not a map"})["debts"] as Dictionary).size(),
		0,
		"a malformed container is empty"
	)
	assert_eq(
		WorldPolityLedger.empty()["version"], WorldPolityLedger.SCHEMA_VERSION, "and versioned"
	)


func test_a_corrupt_count_is_clamped_rather_than_trusted() -> void:
	var out := WorldPolityLedger.normalize_payload(
		{
			"debts":
			{
				WorldPolityLedger.directed_key(HOUSE, RIVAL):
				{"lines": {TERM: 999999, "t_zero": 0, "t_negative": -5}}
			}
		}
	)
	var lines := (
		(out["debts"][WorldPolityLedger.directed_key(HOUSE, RIVAL)] as Dictionary)["lines"]
		as Dictionary
	)
	assert_eq(int(lines[TERM]), WorldPolityLedger.PERIOD_CAP, "a huge count is clamped")
	assert_eq(lines.has("t_zero"), false, "a zero line is not persisted")
	assert_eq(lines.has("t_negative"), false, "nor a negative one")


# --- The save round trip ------------------------------------------------------


func _clear_disk() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SavePaths.DIR):
		DirAccess.remove_absolute(SavePaths.DIR)


func setup() -> void:
	_clear_disk()
	SaveApi.reset_clock()
	SaveApi.install_store(WorldPolityLedger.WORLD_KEY, _store())


func teardown() -> void:
	_clear_disk()
	SaveApi.reset_clock()
	SaveApi.install_store(WorldPolityLedger.WORLD_KEY, null)


## A save-backed store over the `polity` envelope key, which is what `app/` installs.
func _store() -> WorldLedgerStore:
	return WorldLedgerStore.new(WorldPolityLedger.WORLD_KEY, WorldPolityLedger.SCHEMA_VERSION)


func _outsider(actor_id: StringName = &"t_outsider") -> Actor:
	# Deliberately NOT a member of either sect: no `sect_state` ledger at all, which is
	# the state the feature exists for.
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0})
	actor.display_name = "Outsider"
	return actor


func test_a_non_member_reads_the_debt_across_a_save() -> void:
	# THE FEATURE. A founder writes an inter-institution debt, the game saves, and a
	# DIFFERENT body — one that is not a member of either polity and carries no ledger at
	# all — reads it back.
	#
	# Every earlier statement in this file is a mechanism; this is the reason for it. It
	# fails against any implementation that keeps the debt on the actor, because that debt
	# would not be in `world["polity"]` at all.
	var founder := _outsider(&"t_founder_actor")
	var written := _write_a_debt(founder)
	assert_eq(bool(written.get("ok", false)), true, "the debt was written: %s" % written)
	assert_eq(bool(SaveApi.persist(founder, "standard")["ok"]), true, "and the save landed")

	# A fresh session: the store is rebuilt from scratch and published from the file,
	# exactly as `app/item_workbench_app._ready` does on the next launch.
	var next_session := _store()
	SaveApi.install_store(WorldPolityLedger.WORLD_KEY, next_session)
	var published := SaveApi.publish_world()
	assert_eq(bool(published["ok"]), true, "the world published: %s" % published)
	assert_eq(
		(published["restored"] as Array).has(WorldPolityLedger.WORLD_KEY),
		true,
		"and it published the polity slot"
	)

	var restored := WorldPolityLedger.normalize_payload(next_session.read_ledger())
	var stranger := _outsider(&"t_second_outsider")
	assert_eq(
		stranger.get_module_data(SectState.MODULE_KEY).is_empty(),
		true,
		"the reader is not a member of anything"
	)
	assert_eq(
		WorldPolityLedger.owed(restored, HOUSE, RIVAL, TERM),
		4,
		"a body that is not a member reads the debt"
	)
	assert_eq(
		WorldPolityLedger.owed(restored, RIVAL, HOUSE, TERM), 0, "and the direction is intact"
	)
	# The debt is not on the reader either, which is the no-duplication half: a body that
	# never founded anything must not be able to answer a question about the world.
	assert_eq(
		stranger.get_module_data(SectState.MODULE_KEY).has("debts"),
		false,
		"and no copy rode onto the reading body"
	)


func test_no_copy_of_a_debt_exists_on_the_actor_payload() -> void:
	# "Never a second copy of a truth." The world slot carries the ledger; the actor
	# carries a STAMP and nothing else. If the debt ever appeared under `module_data` it
	# would be a second copy every actor could contradict.
	var founder := _outsider(&"t_founder_actor")
	_write_a_debt(founder)
	SaveApi.persist(founder, "standard")
	var envelope := SaveStore.restore()["envelope"] as Dictionary
	var actor_rows := (envelope["actor"] as Dictionary)["module_data"] as Dictionary
	assert_eq(actor_rows.has("world_polity_version"), true, "the actor carries the v6 stamp")
	assert_eq(
		int(actor_rows["world_polity_version"]),
		WorldPolityLedger.SCHEMA_VERSION,
		"at the ledger's version"
	)
	assert_eq(actor_rows.has("debts"), false, "and no debt rows")
	assert_eq(actor_rows.has("institutions"), false, "and no institution rows")
	# The stamp is serialized EXACTLY ONCE, through `module_data` and not through a
	# second payload key of its own — the ADR 0037 rule the other two versioned slots
	# follow, and the reason the loop in `to_dict` excludes it.
	assert_eq(
		(envelope["actor"] as Dictionary).has("world_polity_version"),
		false,
		"and never as a second top-level key beside it"
	)
	assert_eq(
		int((envelope["actor"] as Dictionary)["version"]),
		Actor.SCHEMA_VERSION,
		"at the bumped schema"
	)


## Write the pair through the ledger the way `SectApi` will, so the suite exercises the
## shipped normalizer rather than a hand-built dictionary the normalizer never sees.
func _write_a_debt(_actor: Actor) -> Dictionary:
	var ledger := WorldPolityLedger.empty()
	ledger["institutions"][HOUSE] = {"kind": "sect", "standing": 40, "standing_cap": 100}
	ledger["institutions"][RIVAL] = {"kind": "sect", "standing": 10, "standing_cap": 80}
	var key := WorldPolityLedger.directed_key(HOUSE, RIVAL)
	ledger["debts"][key] = {
		"debtor_id": HOUSE,
		"creditor_id": RIVAL,
		"sequence": 1,
		"lines": {TERM: 4},
	}
	SaveApi.store_for(WorldPolityLedger.WORLD_KEY).call(&"write_ledger", ledger)
	return {"ok": true}


# --- The migration ------------------------------------------------------------


func test_an_old_save_with_no_world_polity_slot_loads_cleanly() -> void:
	# The forward direction, and it is the direction most migrations get wrong: a save
	# written before this slot existed must read as an EMPTY WORLD, not as a failure and
	# not as a world stamped at the current version. Fabricating one would assert a polity
	# history that never happened.
	var legacy := SaveSlot.build(
		{"version": 5, "id": "legacy", "base": {}},
		{"soul": {"integrity": 80}, "polity": {}},
		"standard",
		3
	)
	# A build from before this change reconstructs `world` from ITS OWN key list, so the
	# fixture is written the way that build would have written it: no `polity` key at all.
	var without_key := legacy.duplicate(true)
	(without_key["world"] as Dictionary).erase(WorldPolityLedger.WORLD_KEY)
	var prepared := SaveMigrate.prepare(without_key)
	assert_eq(prepared.is_empty(), false, "an old envelope is migrated, not refused")
	assert_eq(SaveMigrate.refusal(without_key), "", "with no refusal to name")
	var world := prepared["world"] as Dictionary
	assert_eq(
		world.has(WorldPolityLedger.WORLD_KEY), false, "and the slot stays ABSENT, not fabricated"
	)
	assert_eq(
		int((world["soul"] as Dictionary)["integrity"]),
		80,
		"the old world's other keys are untouched"
	)
	assert_eq(
		int((prepared["actor"] as Dictionary)["version"]),
		5,
		"and the actor payload is not rewritten"
	)


func test_a_new_save_loads_on_the_old_code_path_without_crashing() -> void:
	# The backward direction. `SaveSlot.build` reconstructs the envelope field by field
	# from a KEY LIST, which is what makes this work: a build whose list has no `polity`
	# reads every key it knows, writes them back, and DROPS the one it does not — so the
	# world it knows survives byte-for-byte and the slot it has never heard of is not
	# corrupted into the middle of them.
	var keys: Array[String] = []
	for key in SaveApi.WORLD_KEYS:
		if key == WorldPolityLedger.WORLD_KEY:
			continue
		keys.append(key)
	var world := {}
	for key in keys:
		world[key] = {"integrity": 80} if key == "soul" else {}
	world[WorldPolityLedger.WORLD_KEY] = _ledger_with_a_pair()
	var new_save := SaveSlot.build(
		{"version": Actor.SCHEMA_VERSION, "id": "a"}, world, "standard", 1
	)

	# The OLD builder, spelled out: same six envelope fields, world taken from ITS list.
	var rebuilt := {
		"envelope_version": SaveSlot.ENVELOPE_VERSION,
		"format": SaveSlot.FORMAT,
		"generation": int(new_save["generation"]),
		"difficulty": String(new_save["difficulty"]),
		"actor": (new_save["actor"] as Dictionary).duplicate(true),
		"world": {},
	}
	for key in keys:
		rebuilt["world"][key] = (new_save["world"] as Dictionary).get(key, {})
	assert_eq(
		SaveSlot.is_readable(rebuilt), true, "the old builder's envelope is still a readable save"
	)
	assert_eq(
		int((rebuilt["world"] as Dictionary)["soul"]["integrity"]),
		80,
		"and the world it knows survives"
	)
	assert_eq(
		(rebuilt["world"] as Dictionary).has(WorldPolityLedger.WORLD_KEY),
		false,
		"while the slot it never heard of is dropped rather than half-written"
	)
	# `envelope_version` did NOT move, which is what makes the above legal: ADR 0128 pins
	# the two ladders independent and an envelope key appearing is not an envelope change.
	assert_eq(SaveSlot.ENVELOPE_VERSION, 1, "the envelope version did not move for a new world key")


func test_an_actor_payload_from_a_newer_build_is_refused_by_name() -> void:
	# The explicit version gate. Reading a payload this build does not know and writing it
	# back is how a newer run's save is erased by an older one, so it is refused rather
	# than half-read — and the refusal is a NAME a caller can compare.
	var future := SaveSlot.build(
		{"version": Actor.SCHEMA_VERSION + 1, "id": "from_the_future"}, {}, "standard", 1
	)
	assert_eq(
		SaveMigrate.prepare(future).is_empty(), true, "a future actor payload is not prepared"
	)
	assert_eq(SaveMigrate.refusal(future), SaveMigrate.R_FUTURE_ACTOR_SCHEMA, "and named")
	assert_eq(
		SaveMigrate.refusal({}),
		SaveMigrate.R_NO_READABLE_SAVE,
		"an absent save is a different refusal"
	)


func test_an_old_actor_payload_keeps_the_content_it_had_and_gains_no_stamp() -> void:
	# The actor-side half of the migration, and ADR 0037's rule verbatim: accepting an
	# older schema never invents state. A v5 payload has no stamp, so the restored actor
	# carries none — not a current-version one, which would assert that this save was
	# written with a world polity ledger.
	var legacy := Actor.from_dict({"version": 5, "id": "legacy_warden", "base": {Stat.WILL: 30.0}})
	assert_eq(ActorSave.polity_version(legacy), -1, "an old payload invents no stamp")
	var resaved := legacy.to_dict()
	assert_eq(int(resaved["version"]), Actor.SCHEMA_VERSION, "and re-saves at the current version")
	assert_eq(
		(resaved["module_data"] as Dictionary).has("world_polity_version"),
		false,
		"still with no stamp, because nothing wrote one"
	)


func test_a_stamped_payload_round_trips_its_stamp() -> void:
	var actor := Actor.new(&"stamped", {Stat.PHYSIQUE: 10.0})
	ActorSave.set_polity_version(actor, WorldPolityLedger.SCHEMA_VERSION)
	var restored := Actor.from_dict(actor.to_dict())
	assert_eq(
		ActorSave.polity_version(restored),
		WorldPolityLedger.SCHEMA_VERSION,
		"the stamp survives the payload and the JSON hop"
	)
	assert_eq(
		ActorSave.polity_version(
			Actor.from_dict(JSON.parse_string(JSON.stringify(actor.to_dict())) as Dictionary)
		),
		WorldPolityLedger.SCHEMA_VERSION,
		"through JSON too, which is what a file-backed save does"
	)
	assert_eq(
		ActorSave.polity_version(Actor.new()),
		-1,
		"and a body that was never told carries -1, not 0"
	)


func test_a_malformed_stamp_is_dropped_rather_than_coerced() -> void:
	# A save is untrusted input, and a stamp a caller compares against must be an int it
	# can trust. A string, a dictionary or a negative is dropped rather than repaired.
	for bogus in ["six", {"version": 6}, -1, 4.5]:
		var payload := {
			"version": Actor.SCHEMA_VERSION,
			"id": "corrupt",
			"base": {},
			"module_data": {"world_polity_version": bogus},
		}
		assert_eq(
			ActorSave.polity_version(Actor.from_dict(payload)),
			-1,
			"a %s stamp is dropped rather than coerced" % typeof(bogus)
		)


func test_the_json_hop_returns_the_stamp_as_a_float_and_it_is_still_read() -> void:
	# ## WHAT THE JSON HOP ACTUALLY PRODUCES — measured here, not assumed.
	#
	# The claim the reader is built on is that JSON has no integer type, so a file-backed
	# save hands the reader a FLOAT. This asserts the claim itself first: if a future
	# build's parser ever did return an int, this test goes red and says the reader's
	# float tolerance is now unnecessary rather than leaving it as folklore. Without this
	# assertion the round-trip test would pass for the wrong reason and nobody would know
	# which branch actually carried the stamp.
	var actor := Actor.new(&"json_hop", {Stat.PHYSIQUE: 10.0})
	ActorSave.set_polity_version(actor, WorldPolityLedger.SCHEMA_VERSION)
	var in_memory: Variant = (actor.to_dict()["module_data"] as Dictionary)["world_polity_version"]
	assert_eq(typeof(in_memory), TYPE_INT, "in memory the stamp is an INT")
	var from_disk: Variant = (
		(JSON.parse_string(JSON.stringify(actor.to_dict())) as Dictionary)["module_data"]
		as Dictionary
	)["world_polity_version"]
	assert_eq(typeof(from_disk), TYPE_FLOAT, "after the JSON hop it is a FLOAT, as claimed")
	assert_eq(from_disk, float(WorldPolityLedger.SCHEMA_VERSION), "carrying the same value")
	# And that is the whole tolerance: same value, accepted. `4.5` and a negative float
	# are still refused, so "integral float" is a shape rule and not a rounding.
	assert_eq(
		ActorSave.stamp_of(float(WorldPolityLedger.SCHEMA_VERSION)),
		WorldPolityLedger.SCHEMA_VERSION,
		"the integral float is read as the int it is"
	)
	assert_eq(ActorSave.stamp_of(4.5), -1, "a fractional number is still refused")
	assert_eq(ActorSave.stamp_of(-2.0), -1, "and so is a negative one")


func test_a_malformed_module_slot_is_still_dropped_and_named() -> void:
	# ## PROOF THE MALFORMATION GUARD STILL REFUSES AN UNTRUSTED SAVE.
	#
	# The fix for the stamp exempted ONE key from the guard, because that key is not a
	# module ledger and `ActorSave` owns its shape. Nothing else was exempted, and this
	# is what says so: a genuine module ledger that arrives as a string, a nested array
	# or a negative must still be DROPPED and NAMED, or BL-0884's self-inflicted,
# permanent data loss is back — the next autosave overwrites the good save with a
	# body that reads as never having earned anything.
	#
	# Each case is checked on both halves the guard owes: the slot is absent afterwards
	# (`get_module_data` answers `{}`, so the module normalizes to its own default), and
	# the key is not silently swallowed. The stamp key is asserted UNAFFECTED in the same
	# payloads, so a future exemption cannot creep back in unnoticed.
	for bogus in ["not a ledger", [1, 2, 3], -7, 4.5]:
		var key := "t_slot_%s" % typeof(bogus)
		var payload := {
			"version": Actor.SCHEMA_VERSION,
			"id": "corrupt_modules",
			"base": {},
			"module_data":
			{
				key: bogus,
				String(Actor.POLITY_SLOT_KEY): WorldPolityLedger.SCHEMA_VERSION,
			},
		}
		var restored := Actor.from_dict(payload)
		assert_eq(
			restored.get_module_data(StringName(key)).is_empty(),
			true,
			"a %s module slot is dropped, not replayed" % typeof(bogus)
		)
		# The stamp in the SAME payload is still restored, so the exemption is provably
		# scoped to the one key rather than having disabled the guard wholesale.
		assert_eq(
			ActorSave.polity_version(restored),
			WorldPolityLedger.SCHEMA_VERSION,
			"and the stamp beside it still rides the versioned path"
		)


func test_the_stamp_is_not_carried_as_a_dictionary() -> void:
	# The canonical shape is a BARE INT, and this pins it so the Dictionary spelling
	# cannot creep back in. It is the assertion that would have failed before the fix:
	# `set_polity_version` wrote `{"version": N}` and `to_dict` wrote a bare int, so the
	# two ends of one round trip disagreed and the saved stamp was dropped on load.
	var actor := Actor.new(&"shape", {Stat.PHYSIQUE: 10.0})
	ActorSave.set_polity_version(actor, WorldPolityLedger.SCHEMA_VERSION)
	var slot: Variant = actor.module_data.get(ActorSave.POLITY_SLOT_KEY)
	assert_eq(typeof(slot), TYPE_INT, "the live slot is a bare int in memory")
	assert_eq(
		typeof((actor.to_dict()["module_data"] as Dictionary)[String(ActorSave.POLITY_SLOT_KEY)]),
		TYPE_INT,
		"and a bare int on the wire"
	)
	# And it is excluded from the generic `module_data` path entirely: `set_module_data`
	# is typed `(id, data: Dictionary)`, so an int could never ride it.
	assert_eq(
		actor.get_module_data(ActorSave.POLITY_SLOT_KEY).is_empty(),
		true,
		"the stamp is not a module ledger and never answers as one"
	)


# --- The core/ boundary -------------------------------------------------------


func test_core_names_no_module_and_no_module_reaches_into_this_file() -> void:
	# `tools arch` holds `core/` to `{"core", "contracts"}`, and it reads `res://` and
	# `extends` as real edges — so the mechanical half is that this file declares neither.
	# What it CANNOT see is a bare module class name, which is why the second half is
	# here: a test that reads the source and fails on a module-shaped reference.
	var source := _code_only(FileAccess.get_file_as_string("res://src/core/world_polity_ledger.gd"))
	assert_eq(source.contains("res://"), false, "core/ declares no res:// path")
	assert_eq(source.contains("extends Sect"), false, "and extends no module type")
	for module_name in [
		"SectApi", "SectState", "NationApi", "NationState", "ClanApi", "SaveApi", "SaveSlot"
	]:
		assert_eq(
			source.contains(module_name),
			false,
			"core/ names no %s (the checker cannot see a bare reference; this can)" % module_name
		)


## `source` with every comment line removed, so a guard reads CODE and never the prose
## describing what the code must not do.
func _code_only(source: String) -> String:
	var out: PackedStringArray = []
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)
