extends TestCase

## ADR 0190: "A soul arrival grants its authored fates, and the grant rides the carried ledger."
##
## `SoulDef.marks` was authored on all three shipped arrivals and read by NOTHING in
## `game/src`. An author wrote marks and got no behaviour. These cases assert the earn path
## that makes them mean something, in the shape that could actually fail: every leg is written
## adversarially against a specific wrong implementation, and the two pins are non-regression
## pins on things this change could plausibly have broken.
##
## ## The harness is `test_soul_fate_across_rebirth.gd`'s, verbatim
##
## Deliberate: that suite and this one are about the same three bodies walking the same
## ladder, and a second harness would let the two drift into measuring different things. The
## adopt callback in particular REPRODUCES the composition root's `_attach_body_modules`
## (`DestinyApi.attach` on every adopted body), because the whole design is about WHERE the
## grant sits relative to that call — a suite that stubbed it out would be measuring its own
## stub instead of the rule.
##
## ## Assertion style
##
## `assert_eq` / `assert_ne`, each with a label. Sets are compared through
## [method _missing_from] — an explicit SET DIFFERENCE — and the union is printed on failure,
## because a bare `assert_eq` on two arrays prints "expected: [...] actual: [...]" and leaves
## the reader to spot the one id that differs.

const DUELS := &"duels_won"
## The authored origin whose `grants_fates` carry stat modifiers, so the carried-ledger half of
## the ladder is measured on a NON-EMPTY parent ledger rather than on an empty one. Read from
## the shipped catalog in the body rather than restated, so a content rename fails this suite
## by name instead of silently emptying it.
const CARRYING_ORIGIN := &"the_one_who_returned"

var _actor: Actor
var _soul_store: SoulWorldLedger
var _death: SoulDeath
var _minted: Array = []
## The body that fell, kept so a leg can read what the ledger held BEFORE the swap rather than
## inferring it from what survived.
var _fallen: Actor
## How many `WorldFact` subscribers this suite found. A DELTA is observable here, a zero is
## not: a sibling suite may legitimately hold one of its own.
var _baseline_subscribers: int = 0


## ## Leg 0, and the one precondition that is not optional
##
## The setup must EARN SOMETHING BEFORE THE FIRST DEATH, and this is the single most important
## line in the suite. `_carry_destiny` early-returns on an empty parent ledger
## (`soul_death.gd:_carry_destiny`), so on a hero who has earned nothing the carry writes
## nothing and a grant placed BEFORE the carry would leave the mark held — the whole ladder
## would pass and a misplaced grant would ship. Leg 2 is what catches it; this is what makes
## that catch reachable.
func setup() -> void:
	_soul_store = SoulWorldLedger.new()
	SoulApi.set_store(_soul_store)
	_minted.clear()
	_fallen = null
	_baseline_subscribers = WorldFact.subscriber_count()
	# The real bridge, installed the way the composition root installs it and for the reason
	# `item_workbench_app.gd` installs it: a subscriber installed after the first `record` has
	# already missed that occurrence, and the ledger is monotone, so there is no going back.
	DestinyProjection.subscribe_to_fact_ledger()
	assert_eq(
		DestinyProjection.is_subscribed_to_fact_ledger(),
		true,
		(
			"the fact->counter bridge is LIVE: every counter below is read through it, so a false "
			+ "here names the wiring rather than a zero"
		)
	)
	var flow := CharacterCreationFlow.new()
	_actor = _arriving_hero(CARRYING_ORIGIN, flow)
	_death = SoulDeath.new(_mint, _adopt)
	# THE PRECONDITION. A hero who has earned nothing makes a MISPLACED GRANT LOOK CORRECT.
	assert_ne(
		DestinyApi.fates(_actor).is_empty(),
		true,
		(
			"the parent ledger is NOT empty before the first death: a grant placed before "
			+ "`_carry_destiny` would survive an empty ledger and the ladder would pass anyway"
		)
	)


## Leave the process exactly as this suite found it. Only the bridge THIS suite installed is
## removed, by identity against the baseline DELTA — never by asserting a count of zero, which
## a sibling suite's legitimate subscriber would break.
func teardown() -> void:
	DestinyProjection.unsubscribe_from_fact_ledger()
	assert_eq(
		WorldFact.subscriber_count(),
		_baseline_subscribers,
		"the bridge is REMOVED again and the subscriber slot is back to what this test found"
	)
	for born in _minted:
		(born as Actor).resources.clear()
	_minted.clear()
	_actor = null
	_fallen = null
	_soul_store = null
	SoulApi.set_store(null)


# --- 1. THE INVARIANT: the ladder grants what each arrival authored ------------------


func test_the_three_life_ladder_holds_every_mark_of_every_arrival_it_earned() -> void:
	# The whole decision in one case. Walk the REAL `SoulDeath.resolve` down all three rungs and
	# assert, after EACH rung, that the new body holds every mark of arrivals 1..n AND that its
	# fates are exactly the union of what it held before and those marks.
	var catalog := SoulCatalog.instance()
	var arrivals := catalog.arrival_ids()
	assert_eq(arrivals.size(), 3, "the shipped ladder is three arrivals long")
	var owed: Array[StringName] = []
	for arrival_id in arrivals:
		var marks := SoulArrivalMarks.marks_for(arrival_id)
		assert_ne(
			marks.is_empty(),
			true,
			"arrival %s authors at least one mark, or the grant has nothing to do" % arrival_id
		)
		owed.append_array(marks)
	assert_eq(
		owed.size(),
		4,
		(
			(
				"the shipped ladder names four marks across three arrivals: %s. A count that drifts "
				+ "means an arrival was added or emptied, and the union below would then be asserting "
				+ "against content nobody can see"
			)
			% ", ".join(_as_strings(owed))
		)
	)
	var expected: Array[StringName] = DestinyApi.fates(_actor)
	for step in range(arrivals.size()):
		var fates_before := DestinyApi.fates(_actor)
		var arrival: StringName = arrivals[step]
		_kill_and_resolve()
		for mark_id in SoulArrivalMarks.marks_for(arrival):
			assert_eq(
				DestinyApi.has_fate(_actor, mark_id),
				true,
				(
					(
						"rung %d: the body re-embodied into %s holds the mark it earned by dying there"
						+ " — %s"
					)
					% [step + 1, arrival, mark_id]
				)
			)
		expected.append_array(SoulArrivalMarks.marks_for(arrival))
		var held := DestinyApi.fates(_actor)
		var missing := _missing_from(held, expected)
		assert_eq(
			missing.size(),
			0,
			(
				(
					"rung %d: fates == union(pre-death fates, marks of arrivals 1..n). Missing from "
					+ "the union: %s. Held: %s. Union: %s"
				)
				% [
					step + 1,
					", ".join(_as_strings(missing)),
					_as_strings(held),
					_as_strings(expected)
				]
			)
		)
		var extra := _missing_from(expected, held)
		assert_eq(
			extra.size(),
			0,
			(
				(
					"rung %d: and the new body holds NOTHING the union does not name — the grant adds "
					+ "exactly the authored marks. Unaccounted for: %s"
				)
				% [step + 1, ", ".join(_as_strings(extra))]
			)
		)
	assert_eq(
		DestinyApi.fates(_actor).size(),
		expected.size(),
		"three deaths and every mark is held exactly once, so the held count is the union's size"
	)


# --- 2. THE ORDERING GUARD ------------------------------------------------------


func test_a_grant_placed_before_the_carry_would_be_erased_and_this_catches_it() -> void:
	# THE ADVERSARIAL LEG. `_carry_destiny` is a WHOLESALE OVERWRITE
	# (`to.set_module_data(DestinyState.MODULE_KEY, ledger.duplicate(true))`), so a grant
	# placed BEFORE it is silently erased by the copy. That bug PASSES leg 1 on a hero whose
	# ledger is empty at the moment of the carry — which is exactly why leg 0 earns something
	# first, and why this leg runs against a body holding a real fate and a real counter.
	WorldFact.record(_actor, DUELS, 2)
	DestinyApi.earn_fate(_actor, &"first_blood_duel", "combat")
	var counter_before := _counter(_actor, DUELS)
	var fates_before := DestinyApi.fates(_actor)
	assert_ne(fates_before.is_empty(), true, "the falling body holds a fate to lose")
	assert_ne(counter_before, 0, "and a counter the carry has to move")
	var arrival := SoulCatalog.instance().arrival_ids()[0]
	var outcome := _kill_and_resolve()
	assert_eq(
		(outcome["marks"] as Array).size(),
		1,
		"the verdict NAMES the mark it granted, so a silent no-op is not possible here"
	)
	for mark_id in SoulArrivalMarks.marks_for(arrival):
		assert_eq(
			DestinyApi.has_fate(_actor, mark_id),
			true,
			(
				"THE MARK SURVIVED THE CARRY. A grant before `_carry_destiny` reads as correct "
				+ "here only because the parent ledger was NON-EMPTY; on a fresh hero the same "
				+ "bug leaves the mark held and every ladder rung green"
			)
		)
	for fate_id in fates_before:
		assert_eq(
			DestinyApi.has_fate(_actor, fate_id),
			true,
			(
				"and the parent's own fate %s survived — the copy did not clobber the grant either"
				% fate_id
			)
		)
	assert_eq(
		_counter(_actor, DUELS),
		counter_before,
		"the carried counter is unmoved, so the parent ledger really did ride the body swap"
	)


func test_the_inverse_a_minted_body_with_an_empty_ledger_still_holds_the_mark_after_attach(
) -> void:
	# The other direction, and the one that catches a grant placed AFTER `_rebind`: `DestinyApi
	# .attach` calls `DestinyState.normalize`, which DROPS any fate id not in
	# `_known_fates()` (destiny/api.gd:321-327, destiny_state.gd:72). Grant, then adopt
	# again, and the mark must still be there. A grant placed after the rebind would be
	# re-normalized away by the very next `attach` the composition root runs.
	var arrival := SoulCatalog.instance().arrival_ids()[0]
	var minted := CharacterCreationFlow.build_forced(arrival, 99)
	assert_eq(bool(minted.get("ok", false)), true, "the arrival mints a real body")
	var body: Actor = minted["actor"] as Actor
	_minted.append(body)
	assert_eq(
		(DestinyApi.state(body)["fates"] as Dictionary).size(),
		0,
		"a freshly minted body holds nothing — this is the ledger the carry and the grant fill"
	)
	var verdict := SoulArrivalMarks.grant(body, arrival)
	assert_eq(bool(verdict["ok"]), true, "so the grant has something to do: %s" % verdict)
	DestinyApi.attach(body)
	for mark_id in SoulArrivalMarks.marks_for(arrival):
		assert_eq(
			DestinyApi.has_fate(body, mark_id),
			true,
			(
				"the mark SURVIVES a SECOND `attach`. `normalize` drops anything not in "
				+ "`_known_fates()`, so a mark whose FateDef the catalog cannot resolve passes "
				+ "`has_fate` at grant time and vanishes at the next adopt"
			)
		)


# --- 3. ATTACH DOES NOT DROP THE MARK -------------------------------------------


func test_a_second_attach_after_the_rebirth_does_not_drop_the_mark() -> void:
	# The explicit form of leg 2's inverse, run through the REAL death rather than a hand-built
	# body: the composition root's `attach` is idempotent and normalizing, and a second call on
	# the adopted body must leave every mark exactly where the rebind left it.
	var arrival := SoulCatalog.instance().arrival_ids()[0]
	_kill_and_resolve()
	var marks := SoulArrivalMarks.marks_for(arrival)
	for mark_id in marks:
		assert_eq(DestinyApi.has_fate(_actor, mark_id), true, "the rebind granted %s" % mark_id)
	DestinyApi.attach(_actor)
	DestinyApi.attach(_actor)
	var rows: Dictionary = DestinyApi.state(_actor)["fates"] as Dictionary
	for mark_id in marks:
		assert_eq(
			rows.has(String(mark_id)),
			true,
			(
				'after two further `attach` calls the mark is STILL in `state(body)["fates"]`. '
				+ "Read off the ledger rather than through `has_fate`, because the read is what "
				+ "a codex renders and the verb is what a gate asks"
			)
		)


# --- 4. EXACTLY-ONCE, MEASURED ON history ---------------------------------------


func test_the_history_trail_records_each_mark_exactly_once_in_increasing_order() -> void:
	# `has_fate` CANNOT fail this leg: `earn_fate`'s exactly-once no-op makes a double grant
	# invisible to it, because the second grant finds the fate already held and returns the
	# ledger unchanged. Only the TRAIL shows it — a second grant appends a second `fate` row
	# with a fresh `sequence`, and that is the only observable difference between "granted once"
	# and "granted twice".
	for _step in range(3):
		_kill_and_resolve()
	var trails := DestinyApi.state(_actor)["history"] as Array
	var mark_sequences: Array[int] = []
	var per_mark := {}
	for row in trails:
		var entry := row as Dictionary
		if String(entry.get("kind", "")) != "fate":
			continue
		var mark_id := StringName(entry.get("id", ""))
		per_mark[mark_id] = int(per_mark.get(mark_id, 0)) + 1
		var source := String(entry.get("detail", ""))
		if not source.begins_with(SoulArrivalMarks.SOURCE_PREFIX):
			# An origin-granted fate is a `fate` row too, and it is not a mark — the
			# sequence monotonicity below is about the MARKS, measured on the rows this
			# ADR adds rather than on every fate the hero ever earned.
			continue
		mark_sequences.append(int(entry.get("sequence", 0)))
		var arrival_id := StringName(source.substr(SoulArrivalMarks.SOURCE_PREFIX.length()))
		assert_ne(
			SoulCatalog.instance().arrival_definition(arrival_id),
			null,
			(
				(
					"the `source` names the SYSTEM, not the fate id: `%s<arrival_id>` resolves to a "
					+ "real arrival (%s), so a consumer asking how a mark was earned reads the "
					+ "arrival and cannot mistake one grant for another's"
				)
				% [SoulArrivalMarks.SOURCE_PREFIX, arrival_id]
			)
		)
		assert_ne(
			arrival_id,
			mark_id,
			"and never the mark itself: a source naming the fate id cannot distinguish two grants"
		)
	var marks := _all_authored_marks()
	for mark_id in marks:
		assert_eq(
			int(per_mark.get(mark_id, 0)),
			1,
			(
				(
					"mark %s appears EXACTLY ONCE in the fate trail: %d rows. A double grant is "
					+ "invisible to `has_fate` and is only visible here"
				)
				% [mark_id, int(per_mark.get(mark_id, 0))]
			)
		)
	assert_eq(
		mark_sequences.size(),
		marks.size(),
		"and exactly one arrival-sourced fate row per authored mark — no more, no fewer"
	)
	var previous := -1
	var strictly_rising := true
	for sequence in mark_sequences:
		if sequence <= previous:
			strictly_rising = false
		previous = sequence
	assert_eq(
		strictly_rising,
		true,
		(
			(
				"every mark's `sequence` is DISTINCT and STRICTLY INCREASING (%s). Two rows sharing "
				+ "a sequence are one earn recorded twice under `_record`"
			)
			% ", ".join(_as_ints(mark_sequences))
		)
	)


# --- 5. EARN-ONLY AS A MONOTONE SUPERSET ---------------------------------------


func test_a_rebirth_is_a_monotone_superset_and_never_an_equality() -> void:
	# ADR 0065, restated for a ledger that now grows on a death. Asserted BY DIFFERENCE and
	# never by equality: byte-equality encodes "the carry is a pure copy", which stops being
	# true the moment an arrival grants anything, and asserting equality here would fail on the
	# very gain this ADR adds.
	WorldFact.record(_actor, DUELS, 3)
	DestinyApi.earn_fate(_actor, &"first_blood_duel", "combat")
	var before := DestinyApi.state(_actor)
	_kill_and_resolve()
	var after := DestinyApi.state(_actor)
	for key in ["fates", "destinies"]:
		var missing := _missing_from(
			_after_keys(after, key) as Array[StringName],
			_before_keys(before, key) as Array[StringName]
		)
		assert_eq(
			missing.size(),
			0,
			(
				(
					"every %s key present BEFORE the death is present AFTER: %s. A ledger that loses "
					+ "a row across a swap breaks the earn-only invariant, whatever it gains"
				)
				% [key, ", ".join(_as_strings(missing))]
			)
		)
	var counters_after: Dictionary = after["counters"] as Dictionary
	for counter_id in (before["counters"] as Dictionary).keys():
		assert_eq(
			(
				int(counters_after.get(counter_id, 0))
				>= int((before["counters"] as Dictionary)[counter_id])
			),
			true,
			(
				(
					"counter %s never lowers across the swap: %d -> %d. Counters are monotone with "
					+ "no refund (ADR 0065, ADR 0113)"
				)
				% [
					counter_id,
					int((before["counters"] as Dictionary)[counter_id]),
					int(counters_after.get(counter_id, 0))
				]
			)
		)
	var history_before := before["history"] as Array
	var history_after := after["history"] as Array
	assert_eq(
		history_before.size() <= history_after.size(),
		true,
		(
			"the trail never shrinks: %d rows before, %d after"
			% [history_before.size(), history_after.size()]
		)
	)
	for index in range(history_before.size()):
		assert_eq(
			history_after[index],
			history_before[index],
			(
				(
					"row %d of the trail is UNCHANGED. The new ledger's history must be a PREFIX "
					+ "extension of the old one, never a rewrite: an earn-only ledger that reorders "
					+ "or edits its own record has a removal path nobody named"
				)
				% index
			)
		)
	# The direction was wrong here once, and the fix is named because it is the easy mistake:
	# a strict-superset test asks which keys the NEW ledger ADDED, so it is
	# `_missing_from(BEFORE, AFTER)` — "in after, not in before" — and never the reverse.
	var added := _missing_from(
		_before_keys(before, "fates") as Array[StringName],
		_after_keys(after, "fates") as Array[StringName]
	)
	assert_eq(
		added.size() > 0,
		true,
		(
			(
				"and the superset is STRICT, which is the point of this leg: the new body holds a fate "
				+ "the falling body did not — the mark the arrival earned by dying into it. Added: %s. "
				+ "A ledger that grew by nothing passes every line above, so THIS assertion is what "
				+ "proves the grant landed; an equality assertion would pass a silent no-op"
			)
			% ", ".join(added)
		)
	)


# --- 6. THE BOUNDARY ------------------------------------------------------------


func test_the_grant_lives_in_app_and_creates_no_soul_to_destiny_edge() -> void:
	# `BARE_REF_UNITS` excludes `modules/*`, so `tools arch` cannot see a bare reference out of
	# `soul/`. THE SOURCE TEXT IS THE GUARD, not the registry — and the registry alone is not
	# enough either, because a declared-but-dead edge is exactly the seam ADR 0065 warns about.
	var declared := _declared_deps(&"soul")
	assert_eq(
		declared,
		_names(["contracts", "core", "items"]),
		"soul declares contracts, core and items — no destiny, and no edge invented by this change"
	)
	assert_eq(
		_declared_deps(&"destiny").has("soul"),
		false,
		"and destiny declares no back edge to the module that may not know it exists"
	)
	# The WHOLE soul tree, walked rather than listed: a new file under `soul/` that reached for
	# destiny would not be in a hand-written list of five.
	var paths := _files_under("res://src/modules/soul")
	assert_eq(
		paths.is_empty(),
		false,
		(
			(
				"the soul tree was walked, so an empty scan cannot pass this. This read "
				+ "assert_ne(paths.is_empty(), false), and `assert_ne` FAILS when actual EQUALS "
				+ "unexpected — so it asserted the scan WAS empty: it failed on every healthy walk "
				+ "and would have PASSED on the empty scan it exists to catch. Found %d path(s)."
			)
			% paths.size()
		)
	)
	# STRONGER than non-empty, because both are ways the no-destiny scan below passes
	# vacuously: a walk that returned one lucky file, and a walk whose entries are all
	# UNREADABLE — the offender loop skips empty text, so an unreadable path is invisible
	# to it. `assert_ne(x.is_empty(), true)` is the repo's readable idiom; the `false`
	# above was its mirror image, which is exactly the shape that cannot fail.
	assert_eq(
		paths.has("res://src/modules/soul/api.gd"),
		true,
		"and the walk reached the facade, so this is not a one-file scan that proves nothing"
	)
	for path in paths:
		assert_ne(
			FileAccess.get_file_as_string(path).is_empty(),
			true,
			(
				"%s is readable: the offender scan below skips empty text, so an unreadable " % path
				+ "path would let this boundary pass on a file it never read"
			)
		)
	var offenders: Array[String] = []
	for path in paths:
		var text := _code_only(FileAccess.get_file_as_string(path))
		if text.is_empty():
			continue
		if text.contains("DestinyApi") or text.contains("DestinyState"):
			offenders.append(path)
	assert_eq(
		offenders,
		[] as Array[String],
		(
			(
				"no CODE under soul/ names destiny at all: %s. Comments are stripped FIRST — the "
				+ "soul ledger's own prose cites `DestinyState.normalize` and `DestinyApi.record` as "
				+ "precedent, which is a cross-reference a reader follows, never an edge the "
				+ "compiler resolves"
			)
			% ", ".join(offenders)
		)
	)
	var death := _code_only(FileAccess.get_file_as_string("res://src/app/soul_death.gd"))
	var grant := _code_only(FileAccess.get_file_as_string("res://src/app/soul_arrival_marks.gd"))
	assert_eq(
		death.contains("SoulArrivalMarks.grant("),
		true,
		"the grant is CALLED from soul_death.gd, between the carry and the rebind"
	)
	assert_eq(
		grant.contains("DestinyApi.earn_fate("),
		true,
		(
			"and `earn_fate` is called from the app-layer helper that owns it. Both files are in "
			+ "`app/`, the one layer that may depend on anything; the facade rule means the earn "
			+ "reaches `destiny` through `DestinyApi` and nowhere else"
		)
	)
	assert_eq(
		grant.contains("SoulArrivalMarks.SOURCE_PREFIX") or grant.contains("SOURCE_PREFIX"),
		true,
		"and the source string is composed from the shared `soul_arrival:` prefix, in one place"
	)
	assert_eq(
		grant.contains('SOURCE_PREFIX := "soul_arrival:"'),
		true,
		"spelled exactly `soul_arrival:` — the SYSTEM name, never a fate id (ADR 0065)"
	)
	assert_eq(
		death.contains("SoulApi.grant_marks"),
		false,
		(
			"no `SoulApi.grant_marks` verb: the facade is at 12/12 and the cap is the design, "
			+ "and the verb would create exactly the forbidden soul->destiny edge ADR 0181 "
			+ "guard 5 exists to prevent"
		)
	)


# --- 7. NO DESTINY, NO GROUP, NO PICKER -----------------------------------------


func test_an_arrival_grants_a_fate_and_never_a_destiny_a_group_or_a_picker() -> void:
	# Two halves, because either alone is weak. The TEXT half is the only thing that can see a
	# call that was never made on this code path; the BEHAVIOUR half is the only thing that can
	# see a grant that reached the ledger by some route the text scan missed.
	var death := _code_only(FileAccess.get_file_as_string("res://src/app/soul_death.gd"))
	var grant := _code_only(FileAccess.get_file_as_string("res://src/app/soul_arrival_marks.gd"))
	assert_eq(
		grant.contains("DestinyApi.earn_fate("),
		true,
		"the arrival earn goes through `DestinyApi.earn_fate`, and nothing else"
	)
	assert_eq(
		grant.contains("earn_destiny"),
		false,
		(
			"`earn_destiny` appears NOWHERE in the grant. An arrival is a RECEIPT recorded in "
			+ "`SoulState.origins`, not a claim: earning it would put a rebirth into the `origin` "
			+ "exclusivity set and hand the player the destination picker ADR 0065 forbids"
		)
	)
	assert_eq(
		death.contains("earn_destiny"),
		false,
		"nor in the death resolver that calls it, on either the guardian or the rebody branch"
	)
	assert_eq(
		grant.contains("earn_fate(body") or grant.contains("earn_fate(actor"),
		true,
		"and the earn is the plain `earn_fate` verb, with no gate, group or picker argument"
	)
	var flow := CharacterCreationFlow.new()
	var hero := _arriving_hero(CARRYING_ORIGIN, flow)
	var destinies_first := DestinyApi.destinies(hero)
	_actor = hero
	for _step in range(3):
		_kill_and_resolve()
	assert_eq(
		DestinyApi.destinies(_actor),
		destinies_first,
		(
			"after three deaths the held DESTINY set is byte-identical to the first body's. "
			+ "Byte equality is CORRECT here — nothing is ever supposed to grant a destiny, so "
			+ "the only change that could ever be legitimate is none"
		)
	)
	assert_eq(
		DestinyApi.destinies(_actor).size(),
		1,
		"and exactly one origin-group destiny is held, so the exclusivity set did not grow"
	)


# --- 8. THE CONTENT GATE MUST BE ABLE TO FAIL ------------------------------------


func test_every_authored_mark_resolves_to_a_real_fate_and_the_tres_names_the_field() -> void:
	# ADR 0147's lesson: a content gate that passes vacuously is worse than no gate, because it
	# reports the tree is good. So the scanned set is asserted to BE the shipped ladder, and each
	# arrival is asserted to carry at least one mark — otherwise an emptied `.tres` and a
	# deleted one both read as "nothing to check".
	var catalog := SoulCatalog.instance()
	var fates := FateCatalog.instance()
	var arrivals := catalog.arrival_ids()
	assert_eq(arrivals.size(), 3, "the shipped ladder is three arrivals long")
	var scanned := _all_authored_marks()
	assert_eq(
		scanned.size(),
		4,
		"the shipped ladder authors exactly four marks: %s" % ", ".join(_as_strings(scanned))
	)
	for arrival_id in arrivals:
		var marks := SoulArrivalMarks.marks_for(arrival_id)
		assert_ne(
			marks.is_empty(),
			true,
			"arrival %s carries at least one mark, or this whole file proves nothing" % arrival_id
		)
		for mark_id in marks:
			var def := fates.fate_definition(mark_id)
			assert_ne(
				def,
				null,
				(
					(
						"mark %s on arrival %s names NO FateDef. `earn_fate` refuses an id the "
						+ "catalog cannot resolve and returns the ledger UNCHANGED — the same empty "
						+ "answer it gives an already-held fate (ADR 0134 §1a) — so an unresolvable "
						+ "mark is authored, looks authored, and grants nothing"
					)
					% [mark_id, arrival_id]
				)
			)
			if def == null:
				continue
			assert_eq(
				def.build_modifiers().size(),
				0,
				(
					(
						"mark %s is PURE NARRATIVE and carries no modifier. `test_soul_fate_across_"
						+ "rebirth.gd` asserts `modifier_count` is unchanged across a death, so a "
						+ "modifier here turns that shipped guard red and reopens DEF-0241's balance "
						+ "scope"
					)
					% mark_id
				)
			)
			assert_eq(
				String(def.category),
				"rebirth",
				(
					"mark %s is filed under the `rebirth` category, which is where the codex reads it"
					% mark_id
				)
			)
	# THE FIELD-NAME PIN. Godot 4.7 silently IGNORES a property the class dropped, so a
	# resurrected field with no `@export` loads as `[]` and every read above passes on an empty
	# list — the loaded resource cannot see the difference. The `.tres` TEXT is what names
	# `marks =`, so the text is what is read.
	var unnamed: Array[String] = []
	for path in _files_under("res://data/soul/arrivals", ".tres"):
		var text := _code_only(FileAccess.get_file_as_string(path))
		if text.is_empty():
			continue
		if not text.contains("marks ="):
			unnamed.append(path)
	assert_eq(
		unnamed,
		[] as Array[String],
		(
			(
				"every shipped arrival `.tres` NAMES `marks =` in its own text: %s. A loaded-resource "
				+ "read cannot see a property the class dropped — Godot ignores it silently and the "
				+ "authored mark is gone with no error anywhere"
			)
			% ", ".join(unnamed)
		)
	)


# --- Pins: things this change could plausibly have broken ------------------------


func test_a_rebirth_moves_no_counter_and_changes_no_modifier_count() -> void:
	# Two one-line non-regression pins, in one case because neither needs its own walk.
	var modifiers_before := DestinyProjection.modifier_count(_actor)
	_kill_and_resolve()
	assert_eq(
		DestinyApi.state(_actor)["counters"],
		{} as Dictionary,
		"a mark moves no counter: it is a pure-narrative fate, so the counter ledger is untouched"
	)
	assert_eq(
		DestinyProjection.modifier_count(_actor),
		modifiers_before,
		(
			"and `modifier_count` is UNCHANGED across the death. `apply` strips before it "
			+ "rebuilds, so a carried fate is applied once per body — and a mark carrying a "
			+ "modifier would make this the place the growth showed"
		)
	)


# --- Internals -------------------------------------------------------------------


## Kill the body that stands and resolve it, exactly as the frame driver does, keeping a
## reference to the one that FELL so a leg can read both sides of the swap.
##
## Returns the verdict `SoulDeath.resolve` produced, because `marks` and `ungranted_marks` are
## only observable there.
func _kill_and_resolve() -> Dictionary:
	_fallen = _actor
	var pool := _actor.resource(&"health")
	if pool != null:
		pool.change(-pool.maximum)
	return _death.resolve(_actor)


## The composition root's mint callback, through the real arrival table.
func _mint(arrival_id: String, incarnation: int) -> Dictionary:
	var built := CharacterCreationFlow.build_forced(StringName(arrival_id), incarnation)
	if not bool(built.get("ok", false)):
		return {"ok": false, "reason": String(built.get("reason", ""))}
	_minted.append(built["actor"])
	return built


## The composition root's adopt callback, and the half of the production path this suite has to
## reproduce by hand: `_attach_body_modules` runs `DestinyApi.attach(actor)` on every body it
## adopts (fresh, restore and rebirth alike), and that call is what normalizes the carried
## ledger and re-projects from it. The design here is about WHERE the grant sits relative to
## THIS call, so it has to be the real one — an adopt that skipped it would leave a ledger whose
## numbers were never projected, and the suite would be measuring its own stub.
func _adopt(body: Actor) -> void:
	if body == null:
		return
	DestinyApi.attach(body)
	_actor = body


## A hero built through the REAL creation commit, so the ledger under test is the one a player
## earns. `CharacterCreationFlow` attaches `destiny` itself, and `build` earns the origin
## through the facade exactly as the creation screen does. The caller's own flow is passed in
## because `build` refuses `already_created` on a second call — a suite that minted one flow
## per hero could not say anything about which of them was the player's.
func _arriving_hero(choice_id: StringName, flow: CharacterCreationFlow) -> Actor:
	var built := flow.build(choice_id)
	assert_eq(
		bool(built.get("ok", false)),
		true,
		"the creation commit is open for %s: %s" % [choice_id, built.get("reason", "")]
	)
	var hero: Actor = built["actor"] as Actor
	_minted.append(hero)
	SoulApi.attach(hero)
	DifficultyApi.attach(hero)
	return hero


## Every mark every authored arrival names, sorted and de-duplicated — the set leg 8 asserts
## the scanned gate found, so the gate cannot pass by scanning nothing.
func _all_authored_marks() -> Array[StringName]:
	var strings: Array[String] = []
	for arrival_id in SoulCatalog.instance().arrival_ids():
		for mark_id in SoulArrivalMarks.marks_for(arrival_id):
			var text := String(mark_id)
			if not strings.has(text):
				strings.append(text)
	strings.sort()
	var out: Array[StringName] = []
	for text in strings:
		out.append(StringName(text))
	return out


## `held` minus `wanted`, as plain strings, so a failure prints ids rather than StringNames.
func _missing_from(held: Array[StringName], wanted: Array[StringName]) -> Array[String]:
	var present: Array[String] = []
	for id in held:
		present.append(String(id))
	var out: Array[String] = []
	for id in wanted:
		if not present.has(String(id)):
			out.append(String(id))
	return out


func _as_strings(ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id in ids:
		out.append(String(id))
	return out


func _as_ints(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		out.append(str(value))
	return out


## One ledger section's keys as `Array[StringName]`, which is the type
## [method _missing_from] compares in.
func _before_keys(ledger: Dictionary, section: String) -> Array[StringName]:
	return _string_name_keys(ledger, section)


func _after_keys(ledger: Dictionary, section: String) -> Array[StringName]:
	return _string_name_keys(ledger, section)


func _string_name_keys(ledger: Dictionary, section: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for key in (ledger.get(section, {}) as Dictionary).keys():
		out.append(StringName(key))
	return out


## One counter, read off the ledger `DestinyApi.state` publishes rather than off a facade verb.
func _counter(actor: Actor, counter_id: StringName) -> int:
	var ledger := DestinyApi.state(actor)
	return int((ledger["counters"] as Dictionary).get(String(counter_id), 0))


## `values` as the `Array[StringName]` [method _declared_deps] answers in, so an expected side is
## never a differently-typed literal: a GDScript typed array does not compare equal to a
## differently-typed one even element for element.
func _names(values: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for value in values:
		out.append(StringName(value))
	return out


## Every file under `root` ending in `suffix`, through `core/ContentScan`.
##
## The shared scanner, never a hand-rolled `DirAccess` walk: AGENTS.md requires all content
## loading to go through `ContentScan`, because it caps depth at `MAX_DEPTH` and a locally grown
## `_scan` has no such cap — a directory junction pointing back at an ancestor would return
## nothing, forever. Sorted, so the scan order never depends on the filesystem.
func _files_under(root: String, suffix: String = ".gd") -> Array[String]:
	return ContentScan.files_under(root, suffix)


## A GDScript source with every comment line removed, so a cross-reference in prose cannot be
## mistaken for a reference the compiler resolves.
##
## `##` documents a declaration and `#` comments a line out; both are stripped whole-line, and a
## `#` inside a string literal is left alone because this only ever drops lines whose first
## non-whitespace character is a `#`. That is coarser than a real tokenizer and deliberately so.
func _code_only(text: String) -> String:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var trimmed := String(line).strip_edges()
		if trimmed.begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)


## `tools/arch/registry.json`'s declared deps for `module_name`, read from disk.
##
## That file is OUTSIDE `res://` and is reached by GLOBALIZING `res://..` — a `res://../tools/…`
## resource path resolves to nothing, and `FileAccess` answers an empty string for a missing file
## with no error, so a naive read asserts that its own failure. `res://..` must be simplified
## before it reaches any path comparison.
## Empty when the registry cannot be read, so a suite that cannot see it fails the edge assertion
## above rather than passing on an empty set.
func _declared_deps(module_name: StringName) -> Array:
	var root := ProjectSettings.globalize_path("res://..").replace("\\", "/")
	var path := root.simplify_path().path_join("tools/arch/registry.json")
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return []
	var modules: Variant = (parsed as Dictionary).get("modules", {})
	if not (modules is Dictionary):
		return []
	var entry: Variant = (modules as Dictionary).get(String(module_name), {})
	if not (entry is Dictionary):
		return []
	var out: Array = []
	for dep in (entry as Dictionary).get("deps", []) as Array:
		out.append(StringName(dep))
	return out
