extends TestCase

## ADR 0259: the world clock. ONE authoritative count of whole periods, saved beside the
## ledgers it moves, and moved forward by nothing but the composition root.
##
## ## The one test in here that would have failed before this change
##
## `test_the_count_a_world_reached_survives_the_quit` is the whole feature. Everything else in
## this file — the forward-only refusal, the corrupt-key repair, the body-independence — is a
## property that makes the count TRUSTWORTHY, and a count nothing can trust is worse than the
## period-zero resume it replaces, because it looks like an answer.
##
## ## WHY EVERY TEST HERE RUNS AGAINST A DISK SAVE
##
## A clock tested only in memory proves the arithmetic and nothing about the persistence, and
## the persistence is the entire reason the class exists. So every case writes a real envelope
## through `SaveApi.persist` and reads it back through `SaveApi.publish_world` — the same two
## calls a boot makes, in that order.
##
## ## WHY THE SPAN IS DERIVED, NOT TYPED
##
## The round trip needs a count that crosses day and month but NOT year — a span inside one
## year catches a lost or clamped low digit, and a span past a year catches a lost ratio. Both
## halves are read off `TimeLadder` at run time rather than typed as a constant, because a
## retune of `time_ladder_table.tres` would otherwise leave the test asserting a claim about a
## table it no longer describes, and a test that asserts something untrue is worse than no test.

## What a hand-edited save would carry where the count belongs.
const CORRUPT_PERIODS := "not-a-number"
## The clock under test. An INSTANCE, never a static — the runner shares one process, and a
## process-wide clock would leak this suite's periods into every later suite.
var _clock: WorldClock
## The span the round trip uses, in periods. Set in `setup()` from the authored ratios.
var _span: int = 0
## A count with awkward low digits, for the JSON hop. Not derived: its only job is to be a
## number whose low digits a truncating or float-serialising restore would lose.
var _odd_span: int = 4377

var _born: Array = []


func setup() -> void:
	_clear_disk()
	SaveApi.reset_clock()
	_clock = WorldClock.new()
	## THE SPAN IS DERIVED FROM THE TABLE, IN THE ASSERTING DIRECTION.
	##
	## A hundred days crosses day many times and month at least once, and
	## `test_a_clock_stores_periods_and_never_a_converted_value` then requires it to cross
	## NEITHER year. If a retune made a year shorter than a hundred days that assertion goes
	## red rather than quietly passing on a span that no longer means what the test claims — a
	## guard that has stopped describing its own input is the INC-0016 shape this repo already
	## paid for once.
	var day_ratio := maxi(1, TimeLadder.ratio_for(&"day"))
	_span = day_ratio * 100


## ## EVERYTHING this suite sets is undone here, because the runner shares one process
##
## `SaveApi._stores` is a `static var`, so a clock left installed here would be the
## `world_time` store for EVERY later suite in the run — and a later suite that persists would
## write this suite's periods onto disk and read them back as its own world age. That is the
## cross-suite leak the clock's own "never a static" rule exists to prevent, and this teardown
## is the guard on it.
func teardown() -> void:
	_clear_disk()
	SaveApi.reset_clock()
	SaveApi.install_store(WorldClock.WORLD_KEY, null)
	_clock = null
	_span = 0
	for actor in _born:
		(actor as Actor).resources.clear()
	_born.clear()


# --- The slot and the shape ---------------------------------------------------


func test_the_slot_is_declared_in_core_and_carried_in_the_envelope() -> void:
	# The slot is in `SaveSlot.WORLD_KEYS` because the ENVELOPE owns the list, and in
	# `WorldClock.WORLD_KEY` because the CLOCK owns the name. The two files cannot name each
	# other (`core/` may not name `modules/save`, and `modules/save` may not name a core
	# class's internals), so the agreement is ASSERTED rather than imported — a drift would
	# write a count the reader never looks at, which is the silent-loss failure.
	assert_eq(WorldClock.WORLD_KEY, "world_time", "the clock names its envelope key")
	assert_eq(SaveApi.WORLD_KEYS.has(WorldClock.WORLD_KEY), true, "the envelope carries it")
	# A new world key is NOT an envelope change: `envelope_version` is pinned at 1 and a
	# build whose list has no `world_time` must still read every slot it does know.
	assert_eq(SaveSlot.ENVELOPE_VERSION, 1, "the envelope version did not move for a new key")


func test_the_containers_the_clock_normalizes_are_the_ones_the_store_routes() -> void:
	# `app/world_ledger_store.gd` authors its own container table because it may not reach
	# this file's normalizer — a store holds bytes and this class owns the shape. Two authored
	# copies of a routing table is the ADR 0116 four-curves shape, so the agreement is
	# asserted by test rather than left to a comment. Read the table as SOURCE, because a
	# value comparison against `normalize` would pass against a store that routed every key
	# the same way.
	var source := FileAccess.get_file_as_string("res://src/app/world_ledger_store.gd")
	var line := ""
	for candidate in source.split("\n"):
		if candidate.contains('"world_time":'):
			line = candidate
			break
	assert_ne(line.is_empty(), true, "the store routes a world_time container")
	assert_eq(line.contains('"periods"'), true, "and it routes the one container this clock owns")
	# ONE container. A `years` or a `seconds` container would be an authored ratio living in
	# the save format, which is exactly what ADR 0259 clause 4 refuses.
	assert_eq(WorldClock.CONTAINERS.size(), 1, "the clock owns one container, not a calendar")
	assert_eq(WorldClock.CONTAINERS[0], "periods", "and it is the count, not a conversion")


func test_a_clock_stores_periods_and_never_a_converted_value() -> void:
	# Clause 4, asserted as a SHAPE rather than as a value: whatever the ladder says, the
	# payload is a count under one key. If a `years` field ever appears beside it, a retune
	# of `time_ladder_table.tres` would reinterpret every existing save silently, because
	# nothing anywhere would say which table authored the number.
	_clock.advance(_span)
	var ledger := _clock.read_ledger()
	assert_eq(ledger.has("periods"), true, "the count is stored")
	assert_eq(ledger.keys().size(), 2, "and nothing beside it (version, periods)")
	assert_eq(
		ledger.has("years") or ledger.has("days") or ledger.has("seconds"),
		false,
		"no converted value is stored, so a ladder retune cannot disagree with a save"
	)
	# The conversion is the READER's, and `TimeLadder` is the only converter in the repo.
	var crossed := TimeLadder.magnitudes_crossed(_clock.periods())
	assert_eq(int(crossed.get(&"day", 0)) >= 1, true, "the span crosses days once converted")
	assert_eq(int(crossed.get(&"month", 0)) >= 1, true, "and months")
	assert_eq(
		int(crossed.get(&"year", 0)) >= 1,
		false,
		"and does not reach a year — the span is derived, so this stays true after a retune"
	)


# --- The round trip -----------------------------------------------------------


## THE FEATURE. A world ages, the game saves, the process ends, a NEW session restores — and
## the count the next session reads is the count the last one reached.
##
## **The restore goes through a DIFFERENT clock object**, which is the half a same-object test
## cannot reach: an implementation that kept the count in a static or a singleton would pass a
## same-object round trip and fail this one.
func test_the_count_a_world_reached_survives_the_quit() -> void:
	SaveApi.install_store(WorldClock.WORLD_KEY, _clock)
	_clock.advance(_span)
	assert_eq(_clock.periods(), _span, "the world aged")
	assert_eq(bool(SaveApi.persist(_hero(), "standard")["ok"]), true, "and the save landed")

	# What the file ACTUALLY carries, asserted before the restore. A round trip whose two
	# halves are both wrong proves nothing, and this is the half that could silently write an
	# empty world over a full ledger.
	var envelope := SaveStore.restore()["envelope"] as Dictionary
	var carried = (envelope["world"] as Dictionary).get(WorldClock.WORLD_KEY)
	assert_eq(carried is Dictionary, true, "world_time rode out in the envelope")
	assert_eq(
		int((carried as Dictionary).get("periods", 0)),
		_span,
		"with the count the world actually reached"
	)

	# A NEW session: a different clock, published from that file by the same call a boot
	# makes. `publish_world` skips and NAMES an unwired key rather than inventing it, so the
	# clock is reachable at all only because it was installed.
	var next_session := WorldClock.new()
	SaveApi.install_store(WorldClock.WORLD_KEY, next_session)
	var published := SaveApi.publish_world()
	assert_eq(bool(published["ok"]), true, "the world published")
	assert_eq(
		(published["restored"] as Array).has(WorldClock.WORLD_KEY),
		true,
		"and it names the clock among the keys it restored"
	)
	assert_eq(
		next_session.periods(), _span, "so the next session resumes where the last one left off"
	)


## A count with awkward low digits survives the JSON hop. `_span` is a round number, so a
## float-serialising or truncating restore would pass on it; this one has digits that only
## survive an exact integer hop.
func test_a_count_with_low_digits_survives_the_json_hop() -> void:
	SaveApi.install_store(WorldClock.WORLD_KEY, _clock)
	_clock.advance(_odd_span)
	assert_eq(_clock.periods(), _odd_span, "the world aged by an odd count")
	assert_eq(bool(SaveApi.persist(_hero(), "standard")["ok"]), true, "and the save landed")
	var next_session := WorldClock.new()
	SaveApi.install_store(WorldClock.WORLD_KEY, next_session)
	SaveApi.publish_world()
	assert_eq(next_session.periods(), _odd_span, "every digit of it came back, not a rounded copy")


# --- A restore never authors a count -------------------------------------------


func test_a_clock_with_no_persisted_key_reads_zero_rather_than_guessing() -> void:
	# A save written before ADR 0259 carries no `world_time` on disk, so the restore hands
	# this clock `{}`. It must land on period zero — the honest answer for a world whose age
	# was never written — and must NOT invent a count to paper over the gap.
	var envelope := SaveSlot.build({"version": Actor.SCHEMA_VERSION}, {}, "standard", 1)
	assert_eq(
		(envelope["world"] as Dictionary).has(WorldClock.WORLD_KEY),
		true,
		"the envelope carries the key as empty rather than omitting it"
	)
	_clock.write_ledger({})
	assert_eq(_clock.periods(), 0, "so an empty persisted key restores as period zero")
	assert_eq(_clock.is_empty(), true, "which is the new-game answer, not an error")


func test_a_corrupt_key_is_repaired_rather_than_silently_believed() -> void:
	# A hand-edited save carrying a string where the count belongs. Two properties, and both
	# matter: it must not crash the boot (`int()` on a String raises at runtime, which is the
	# one thing a corrupt save is allowed to do — `WorldPolityLedger._text`'s argument), and
	# it must not be BELIEVED. Zero is the answer, and zero is a REPAIR, not a read.
	_clock.write_ledger({"periods": CORRUPT_PERIODS})
	assert_eq(_clock.periods(), 0, "a string where a count belongs reads as zero")
	# A negative count in a file is a corrupt save, NOT a rewind request. It is repaired to
	# zero rather than believed, so a hand-edited file cannot make the world run backwards.
	_clock.write_ledger({"periods": -500})
	assert_eq(_clock.periods(), 0, "and a negative persisted count is repaired to zero")
	# A missing field is the same repair, not a default a caller could read as a count.
	_clock.write_ledger({"version": WorldClock.SCHEMA_VERSION})
	assert_eq(_clock.periods(), 0, "and a payload with no count at all is period zero")
	# **The repair goes through ONE normalizer**, or the three cases above could disagree:
	# whatever `read_ledger` hands a caller is what `periods_of` reads, so a snapshot cannot
	# carry a count `periods()` refuses to report.
	assert_eq(
		WorldClock.periods_of(_clock.read_ledger()),
		_clock.periods(),
		"the normalized payload and the integer read are one value"
	)


func test_a_future_clock_is_refused_by_name_rather_than_overwriting_the_world() -> void:
	# A ledger stamped by a build whose `SCHEMA_VERSION` is higher than the reading one. The
	# store refuses it, and refusing it must mean the GOOD ledger on disk is still there —
	# reading a future version and writing it back is how an older build erases a newer
	# build's world, and this is the only guard between the two.
	SaveApi.install_store(WorldClock.WORLD_KEY, _clock)
	_clock.advance(_span)
	assert_eq(bool(SaveApi.persist(_hero(), "standard")["ok"]), true, "a good save landed")
	var store := WorldLedgerStore.new(WorldClock.WORLD_KEY, WorldClock.SCHEMA_VERSION)
	var written: Dictionary = store.call(
		&"write_ledger", {"version": WorldClock.SCHEMA_VERSION + 1, "periods": _span}
	)
	assert_eq(bool(written.get("ok", false)), false, "the future clock is refused")
	assert_eq(
		String(written.get("reason", "")), "future_schema", "and the refusal is NAMED, not silent"
	)
	# The refusal preserved what was there rather than replacing it with the refused payload.
	assert_eq(
		WorldClock.periods_of(store.call(&"read_ledger")),
		_span,
		"so the world this build can read is untouched on disk"
	)


# --- Forward only -------------------------------------------------------------


func test_a_negative_advance_is_refused_and_the_count_does_not_move() -> void:
	# ADR 0259 clause 5. A clock that can be wound back is the rewind ADR 0131 and ADR 0128
	# refuse, and the refusal has to be STRUCTURAL: there is no argument to pass that does it.
	_clock.advance(_span)
	var before := _clock.periods()
	var refused := _clock.advance(-1)
	assert_eq(bool(refused["ok"]), false, "a negative advance is refused")
	assert_eq(String(refused["reason"]), "negative_advance", "and it is NAMED")
	assert_eq(_clock.periods(), before, "and the count did not move")


func test_the_forward_only_refusal_is_structural_and_not_a_convention() -> void:
	# The half a caller cannot route around. Every assignment to the stored count goes through
	# `normalize_payload` (or the initialiser), so there is no expression anywhere in the class
	# that puts an arbitrary number into the clock — no setter, no rewind, no raw field write.
	#
	## Counted against the SOURCE rather than asserted as a missing name, because "there is no
	## `set_periods`" passes against a `set_time`, a `rewind_to` or a raw `_periods = n`.
	var code := _code_only(FileAccess.get_file_as_string("res://src/core/world_clock.gd"))
	assert_eq(_unsafe_writers(code), 0, "no assignment puts an unnormalized number into the clock")
	var writers := _writer_methods(code)
	writers.sort()
	assert_eq(
		writers,
		["_init", "advance", "write_ledger"],
		"exactly three writers, named — so a fourth is a failure and not a bigger number"
	)
	# `write_ledger` is the restore door and takes a whole PAYLOAD, not a number — so the one
	# verb that can replace the count cannot be handed a bare integer to wind it back with.
	var signature := ""
	for line in code.split("\n"):
		if line.contains("func write_ledger"):
			signature = line
			break
	assert_eq(
		signature.contains("Dictionary"),
		true,
		"the restore door takes a payload, so there is no integer-shaped way to wind it back"
	)


func test_a_zero_advance_is_a_frame_that_did_not_move_rather_than_an_error() -> void:
	# `WorldPulse.pull` hands down zero on a delta that elapsed nothing, and that must not be
	# reported as a refusal — the fold returns `ok` for it, so a clock that refused it would
	# make the fold's own caller see two different answers for the same world.
	_clock.advance(_span)
	var report := _clock.advance(0)
	assert_eq(bool(report["ok"]), true, "a zero span is not a refusal")
	assert_eq(String(report["reason"]), "", "and it names no reason")
	assert_eq(_clock.periods(), _span, "and the count stays where it was")


func test_an_advance_past_the_cap_is_refused_rather_than_clamped_down() -> void:
	# A clamp here would be a SILENT rewind: the world would be older than the clock says, and
	# every reader that trusts the count would be wrong by the surplus with nothing to see.
	# Refuse loudly instead — which is `AGENTS.md:56`'s rule, one magnitude up.
	var refused := _clock.advance(WorldClock.PERIOD_CAP + 1)
	assert_eq(bool(refused["ok"]), false, "an over-cap advance is refused")
	assert_eq(String(refused["reason"]), "over_cap", "and it is NAMED")
	assert_eq(_clock.periods(), 0, "and the count did not become a clamped lie")


# --- Body independence --------------------------------------------------------


## ADR 0127's argument applied to time, and **the property most likely to be broken by a
## well-meaning convenience**.
##
## The hero dies, a NEW body is minted, a fresh `WorldPulse` fold is built for it — and the
## world's age is the same number it was before. A per-actor clock would restart at zero and a
## per-fold clock would die with the first one; both would pass every single-actor test.
func test_the_world_does_not_get_younger_when_the_hero_does() -> void:
	_clock.advance(_span)
	assert_eq(_clock.periods(), _span, "the first hero aged the world")

	# The body swap: a different actor entirely, and a fresh fold for it. The fold is replaced
	# because `adopt_actor` builds a new one — which is exactly the mechanism that would kill
	# a clock held per fold.
	var reborn := _hero_named(&"reborn_hero")
	var fresh_fold := WorldPulse.new(reborn, BeatDirector.new())
	# The composition root hands the SAME clock to every fold — that is what `adopt_actor`
	# does, and this is the assertion that keeps a refactor from rebuilding it.
	fresh_fold.attach_clock(_clock)
	assert_eq(fresh_fold.world_periods(), _span, "the new fold counts on top of the world's age")

	# And the new body ages the SAME world rather than starting one.
	fresh_fold.advance_periods(3)
	assert_eq(_clock.periods(), _span + 3, "so the reborn hero advances the world it inherited")
	assert_eq(
		fresh_fold.world_periods(),
		_span + 3,
		"and the fold and the clock agree rather than being two answers"
	)
	# Nothing about the fallen body is consulted in any of that. A fact keyed on the body would
	# answer differently here, which is the whole property: there is no per-body copy to hold
	# a second number, so there is nothing that could disagree.
	assert_eq(_clock.periods(), _span + 3, "and no per-body copy exists to disagree with it")


func test_the_world_clock_survives_the_session_and_the_fold_is_only_its_caller() -> void:
	# A NEW boot, not a body swap: a fresh clock is published from the file and a fresh fold is
	# built against it. The session boundary is the harder case — a clock that lived on the
	# root would die with it and every launch would restart the world at zero, which is the
	# defect ADR 0259 was written about.
	SaveApi.install_store(WorldClock.WORLD_KEY, _clock)
	_clock.advance(_span)
	assert_eq(bool(SaveApi.persist(_hero(), "standard")["ok"]), true, "a save landed")

	var next_boot := WorldClock.new()
	SaveApi.install_store(WorldClock.WORLD_KEY, next_boot)
	SaveApi.publish_world()
	var next_fold := WorldPulse.new(_hero_named(&"second_session_hero"), BeatDirector.new())
	next_fold.attach_clock(next_boot)
	assert_eq(next_fold.world_periods(), _span, "the new session's fold starts at the world's age")


func test_only_the_fold_advances_the_clock_and_no_module_can() -> void:
	# DEF-0111 / ADR 0089: no module owns time. The clock holds no clock of its own — no
	# `Time.get_ticks*`, no frame callback, no `get_tree()` — so a span can only arrive from a
	# caller. Asserted on the source because `tools arch` cannot see it in `core/`
	# (`BARE_REF_UNITS` excludes `modules/*` and `core/`).
	var code := _code_only(FileAccess.get_file_as_string("res://src/core/world_clock.gd"))
	assert_eq(code.contains("Time.get_ticks"), false, "the clock never reads a wall clock")
	assert_eq(code.contains("get_tree()"), false, "and never reaches for the tree")
	assert_eq(code.contains("func _process"), false, "and declares no frame callback")
	# The composition root is the ONE caller of `advance`, and it does it at the EXISTING fold
	# boundary — a second driver is the class of change DEF-0111 exists to prevent.
	var pulse := _code_only(FileAccess.get_file_as_string("res://src/app/world_pulse.gd"))
	assert_eq(pulse.contains("_clock.advance(periods)"), true, "the fold records into the clock")
	assert_eq(
		pulse.contains("func _advance"),
		true,
		"at the one place a whole advance already happened — not a new driver"
	)
	# And it hands the SPAN, not the running total: a forward-only clock has no verb for a
	# total, and handing the total anyway would grow the count as a quadratic of itself.
	assert_eq(
		pulse.contains("_clock.advance(_periods)"),
		false,
		"and it hands the span, never the running total"
	)


# --- The unwired key is named, not invented -----------------------------------


func test_a_world_key_with_no_store_installed_is_skipped_and_named() -> void:
	# This behaviour already existed and ADR 0259 asks that it be CONFIRMED and kept rather
	# than replaced: `publish_world` must skip an unwired key and NAME the ones it did restore,
	# so a clock nobody wired is loud rather than silently absent.
	#
	## **The store is UNINSTALLED here, which is the state no public call can produce.**
	##
	## `SaveApi.install_store(key, null)` refuses a null store and leaves the previous entry in
	## place, so there is no public way to CLEAR a key — the only unwired state a caller can
	## reach is "never installed". This suite installs the clock in every other case, so this
	## one erases the entry the way `install_store` would have written it. Reaching into the
	## facade's own table is acceptable HERE precisely because it is the only way to build the
	## state under test, and the assertion that follows is about `publish_world` — not about
	## the private field, which nothing else may rely on.
	SaveApi._stores.erase(WorldClock.WORLD_KEY)
	assert_eq(SaveApi.store_for(WorldClock.WORLD_KEY), null, "the clock is genuinely unwired here")
	_clock.advance(_span)
	assert_eq(bool(SaveApi.persist(_hero(), "standard")["ok"]), true, "and a save still lands")

	var published := SaveApi.publish_world()
	assert_eq(bool(published["ok"]), true, "the world still published")
	assert_eq(
		(published["restored"] as Array).has(WorldClock.WORLD_KEY),
		false,
		"and the unwired clock is SKIPPED rather than invented"
	)
	# Not invented on the way IN either: `_snapshot_world` writes an empty payload for an
	# unwired key rather than leaving a stale one from the previous generation.
	var world := SaveStore.restore()["envelope"]["world"] as Dictionary
	assert_eq(world.has(WorldClock.WORLD_KEY), true, "the key is still present in the envelope")
	assert_eq(
		(world[WorldClock.WORLD_KEY] as Dictionary).is_empty(),
		true,
		"and it is empty rather than fabricated"
	)


# --- Internals ----------------------------------------------------------------


func _clear_disk() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SavePaths.DIR):
		DirAccess.remove_absolute(SavePaths.DIR)


func _hero() -> Actor:
	return _hero_named(&"hero")


## A body with what the save carries and nothing else.
##
## ## WHY THIS BUILDS THE ACTOR ITSELF AND NOT THROUGH `ActorFactory`
##
## The factory pulls `modules/elements`, `modules/race` and the body plan, and the clock has
## no use for any of them: `SaveApi.persist` needs an `actor.to_dict()`, which every `Actor`
## has. A world fact must not acquire a dependency on a body plan — that is ADR 0127's argument
## run backwards, and it is what would make this suite unable to prove anything at all while an
## unrelated module is mid-edit.
##
## Freed from `teardown()` through a `_born` list rather than at each call site, so an early
## return cannot leak one (the runner shares one process across every suite).
func _hero_named(actor_id: StringName) -> Actor:
	var body := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0})
	body.display_name = String(actor_id)
	body.attach_core_resources()
	DifficultyApi.attach(body)
	_born.append(body)
	return body


## How many places in `code` put an UNNORMALIZED value into the stored count. Zero is the
## answer that makes forward-only structural rather than conventional: there is no expression
## in the class that can install an arbitrary number, under any name.
func _unsafe_writers(code: String) -> int:
	var unsafe := 0
	for line in code.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("_ledger = "):
			continue
		if (
			trimmed.ends_with("_ledger = empty()")
			or trimmed.contains("_ledger = normalize_payload(")
		):
			continue
		unsafe += 1
	return unsafe


## The names of the functions that write the stored count, in source order. Asserted as an
## EXACT list rather than a count, so a fourth writer added under any name is a failure and
## not a silently larger number.
func _writer_methods(code: String) -> Array[String]:
	var found: Array[String] = []
	var current := ""
	for line in code.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("func "):
			current = trimmed.split("(")[0].replace("func ", "").strip_edges()
		if trimmed.begins_with("_ledger = ") and not found.has(current):
			found.append(current)
	return found


## `source` with every comment line removed, so a guard reads CODE and not the prose that
## describes what the code must not do.
func _code_only(source: String) -> String:
	var out := PackedStringArray()
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)
