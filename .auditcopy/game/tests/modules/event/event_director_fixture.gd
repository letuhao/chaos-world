extends TestCase

## Shared fixture for the two halves of the world event director suite. NOT a suite
## itself: the runner discovers `test_*.gd` only (`run_tests.gd::_find_tests`), so this
## file is never executed on its own.
##
## Split out of the original single-file suite purely for size -- gdlint's
## `max-file-lines` is 1000. Nothing was rewritten, no assertion changed and no method
## renamed: every constant and private helper the cases use now lives here, which both
## halves `extends`. No state is duplicated between them.
##
## There is no `setup()` / `teardown()` to move: the original file declared neither,
## because every case builds its own actor and lets it go at the end of the body. The
## split therefore neither installs nor releases anything the suite did not already.
##
## The delivery half -- the clock, the trigger gate, stages and the once-paid prize -- is
## `test_event.gd`. The delegation, ledger, persistence and bus half is
## `test_event_ledger.gd`.## BL-0054 / ADR 0113 / ADR 0114 / ADR 0085: **the world event director.**

##

## ## This file drives the WORLD; `test_event_content.gd` audits the TREE

##

## Everything below builds an actor and moves the world through it. The authored

## content under `res://data/event/events/` has its own suite, so the two concerns

## stay separate and this file fits inside the 1000-line lint cap.

##

## ## The properties, not the buttons

##

## Every test here asserts something that must be true of the DESIGN rather than of

## one authored event, because ADR 0077's standing warning is that an ADR can describe

## a spine with not one of its named symbols present. The load-bearing ones are:

##

##   1. **The director has no clock.** Advancing requires an explicit `periods`, the

##      source contains no clock spelling at all, and two identical pulls with no

##      elapsed time between them resolve nothing extra.

##   2. An event with an unmet trigger never appears in `available`.

##   3. Stage progression respects `duration_periods` — one period is not enough.

##   4. `pay` fires EXACTLY ONCE per event, across many `advance` calls (ADR 0061).

##   5. **The director owns no conflict arithmetic**: a conflict event DELEGATES to

##      `NationApi.resolve_conflict`, the standoff closes in `nation`, and no

##      `CombatApi`, no `rng` and no damage constant exists anywhere in `event/`.

##   6. A fate grant carries the exact source string `"event:" + event_id` (DEF-0108).

##

## The structural cases read the SOURCE, the same technique

## `test_nation_conflict.gd` uses: `tools arch` cannot see a method that does not

## exist, so a formula written into this module would fork the shared spine invisibly.

## Comments are stripped first — a module that DOCUMENTS the rule it obeys is not

## reported for obeying it in prose.

const MODULE_ROOT := "res://src/modules/event"

const EVENTS_ROOT := "res://data/event/events"

## The words a second damage model would be written with (ADR 0085's whole subject).

const DAMAGE_WORDS := ["resolve_attack", "damage", "crit", "mitigate", "army_strength", "hit_point"]

## The rng and the clock. `CombatApi` is here because an event director that calls

## combat is a second place verdicts are produced — ADR 0085 routes them to the

## caller, and the caller runs the exchange.

const FORBIDDEN_WORDS := [
	"CombatApi",
	"CombatEngineApi",
	"RandomNumberGenerator",
	"randf",
	"randi",
	"seed(",
	"shuffle",
	"Time.get_ticks",
	"get_tree()",
	"_process(",
	"_physics_process(",
	"_notification(",
]

const WAR := &"war_of_the_nine_fords"

const TOURNAMENT := &"tournament_of_the_spirit_peaks"

const TIDE := &"beast_tide_of_the_mortal_plains"

const AUCTION := &"auction_at_the_immortal_court"

const DISASTER := &"the_riven_peak_disaster"

const TREASURE := &"the_stone_that_answering"

const MARCH := &"march_of_the_nine_provinces"

# --- Fixtures ---------------------------------------------------------------


func _actor(at: String = &"spirit_peaks", founded: bool = false) -> Actor:
	var actor := Actor.new(&"event_actor", {Stat.PHYSIQUE: 10.0})

	DestinyApi.attach(actor)

	NationApi.attach(actor)

	EventApi.attach(actor)

	if founded:
		NationApi.found(actor, MARCH, String(actor.id))

	EventApi.set_location(actor, at)

	return actor


## Record a fact the way a beat does — through the ONE writer that owns the ledger.

## Not through the event module's own hand-rolled write, which is exactly what the

## ADR 0066 tests below forbid.


func _remember(actor: Actor, fact_id: StringName, amount: int = 1) -> void:
	WorldFact.record(actor, fact_id, amount)


func _stage_id(actor: Actor, event_id: StringName) -> String:
	var rows := EventApi.active(actor)

	for row in rows:
		if StringName(row["event_id"]) == event_id:
			return String(row["stage_id"])

	return ""


func _available_ids(actor: Actor, at: String = "") -> Array[String]:
	var out: Array[String] = []

	for row in EventApi.available(actor, at):
		out.append(String(row["event_id"]))

	return out


# --- Plumbing ---------------------------------------------------------------

## Every `.gd` under `root`, found iteratively and sorted. The same reason

## `test_nation_conflict.gd` walks that way: a recursive `DirAccess` returned an empty

## list under this runner once, and an empty scan makes every assertion pass vacuously.


func _module_files(root: String) -> Array[String]:
	var out: Array[String] = []

	var pending: Array[String] = [root]

	while not pending.is_empty():
		var current: String = pending.pop_back()

		var dir := DirAccess.open(current)

		if dir == null:
			continue

		dir.list_dir_begin()

		var entry := dir.get_next()

		while entry != "":
			var path: String = current.path_join(entry)

			if dir.current_is_dir():
				if not entry.begins_with("."):
					pending.append(path)

			elif entry.ends_with(".gd"):
				out.append(path)

			entry = dir.get_next()

		dir.list_dir_end()

	out.sort()

	return out


## Code with every comment removed, so a module that DOCUMENTS the rule it obeys is

## not reported for obeying it in prose.


func _strip_comments(text: String) -> String:
	var out: Array[String] = []

	for line in text.split("\n"):
		var trimmed := line.strip_edges()

		if trimmed.begins_with("#"):
			continue

		var hash := line.find("#")

		out.append(line.substr(0, hash) if hash >= 0 else line)

	return "\n".join(out)
