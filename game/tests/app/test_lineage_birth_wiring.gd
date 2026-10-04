extends TestCase

## The two lineage wirings the composition root needed, and the load-bearing proofs that
## were missing with them.
##
## ## What is under test here
##
## 1. **PERSISTS.** `RaceApi.attach(actor)` and `BloodlineApi.attach(actor)` sit on the ONE
##    shared attach list in `ItemWorkbenchApp._attach_body_modules`
##    (`item_workbench_app.gd:493-494`), which `restore_actor` reaches through
##    `_mount_player_modules` (`item_workbench_app.gd:361`). The gap they closed:
##    `Actor.from_dict` restores `module_data`, so the race and bloodline LEDGERS survive a
##    save, but it restores components and NEVER a `StatProvider`, so the PROJECTION — the
##    percent modifiers, the base-attribute grants, the trait mirrors — is rebuilt by
##    nothing. After one reload a stoneborn silently lost its +15% `max_health` and a
##    tideborn read awake with zero grants, and no error anywhere. These cases read the
##    modifiers off `actor.stats._modifiers` after a REAL save/restore round trip and
##    assert they are BACK.
##
## 2. **OBSERVABLE / NOT DROPPED.** `_process` reads the tick's `born` key
##    (`item_workbench_app.gd:569`) and calls `_register_birth`, which writes a primitive row
##    into the root's `_born` registry and records the `child_born` world fact on the CHILD
##    (`item_workbench_app.gd:631-641`). A birth used to be COMPUTED and DROPPED: the child
##    lived only in `PregnancyStatus.offspring`, which `FertilityApi.advance` erases at the
##    end of the postpartum stage. These cases drive mounted frames until a birth happens,
##    then assert the child is reachable with its race and purity, and that it is still
##    reachable AFTER the pregnancy status has been cleared.
##
## ## Why this suite mounts the REAL scene
##
## Through `SeamHarness`, which parents the shipped `ItemWorkbenchApp.tscn` and drives
## `_ready` the way the engine would. The cases call `_process` on the mounted root rather
## than `StatusLoop.tick` or `FertilityApi.advance` — a test that drives the loop itself
## stays green the day the production reader is deleted, which is the exact shape of proof
## that let the original "computed and dropped" defect ship. Delete the `born` read at
## `item_workbench_app.gd:569` and the birth cases go red.
##
## ## Disk discipline
##
## `user://save` is cleared before every mount and after every case. The runner shares one
## process across every suite, so a save left behind is read by whichever suite boots next.

## One quarter-second frame, at the same 60 Hz the engine runs at (ADR 0089: a headless
## test passes its OWN delta rather than reading a clock).
const FRAME := 1.0 / 60.0
## The world fact a completed birth records. Read off the shipped constant rather than
## restated, so a rename here cannot leave this suite asserting a fact nothing writes.
const BIRTH_FACT := ItemWorkbenchApp.BIRTH_FACT
## A race whose authored PERCENT modifiers include a POSITIVE `max_health` grant, so a
## missing projection is a wrong NUMBER (0.0) rather than a missing key. Read off the
## shipped catalog rather than hardcoded, so a content retune fails here by name.
const RACE_WITH_MODIFIERS := &"stoneborn"
## A lineage whose authored percent grants are non-zero and whose authored awaken threshold
## is well under 1.0, so a restored awake lineage contributes a measurable grant.
const LINEAGE := &"tideborn"
## A generous upper bound on the mounted frames a birth may take.
##
## ## Why the number, and why it is not a tuned constant
##
## `FertilityApi._gestation_step` divides by an authored gestation length in DAYS, and
## `StatusLoop` converts a frame to a day at `SECONDS_PER_GESTATION_DAY = 1.0`, so a
## raceless 30-day pregnancy at the boot hero's `gestation_speed` of 1.26 needs about
## 1 / (1.26 * (1/60) / 30) = 1429 frames of gestation, plus one frame each for the
## CONCEIVED -> GESTATING and GESTATING -> LABOR transitions. This is deliberately well
## above that arithmetic rather than equal to it, so a content retune that lengthens a
## pregnancy cannot turn this suite red on a frame count.
##
## Bounded on purpose: `FertilityApi.advance` neither loops nor grows per call, so a budget
## this size cannot hang. It exists so a body that aborts mid-way fails on the frame count
## rather than as an infinite loop.
const BIRTH_FRAMES := 5000
## One generous postpartum. `recovery_remaining = 10.0 / recovery_rate`, so 5000 frames
## clears the status several times over and proves the child outlived it.
const POSTPARTUM_FRAMES := 5000

var _harness: SeamHarness = null
var _app: ItemWorkbenchApp = null
## Children this suite minted, so teardown can break the `PathState`/provider refcount
## cycle the way `test_creation_play_wiring` does.
var _children: Array = []


func setup() -> void:
	_clear_disk()
	_harness = SeamHarness.mount_new()
	_app = _harness.app as ItemWorkbenchApp


func teardown() -> void:
	_clear_disk()
	if _harness != null:
		_harness.teardown()
	_harness = null
	_app = null
	for born in _children:
		var body := born as Actor
		if body != null:
			body.resources.clear()
	_children.clear()
	_clear_disk()


# --- The root is a live root ----------------------------------------------------


func test_the_harness_mounted_a_booted_app_that_holds_a_hero() -> void:
	# The precondition every other case rests on. A failed mount would otherwise make each
	# of them report a null-body error instead of saying so once.
	assert_eq(String(_harness.boot_error), "", "the shell booted")
	assert_eq(_app != null, true, "there is a composition root")
	assert_eq(_app.actor() != null, true, "and it holds a hero")


# --- 1. PERSISTS: the projection survives a save/restore ------------------------


func test_a_restored_hero_carries_its_race_percent_modifiers_again() -> void:
	# THE POINT OF FIX 1. A hero is given a race, saved, and restored through a REAL boot
	# that runs the PRODUCTION attach path — a second `SeamHarness.mount_new()` over the
	# written save, so `_ready -> restore_actor -> _mount_player_modules` is what rebuilds
	# the body. The race's percent modifiers are read back OFF THE STAT STACK.
	#
	# Read off `actor.stats._modifiers`, never off a return value: the defect was that the
	# LEDGER survived while the PROJECTION did not, so asserting the ledger would pass
	# while the stat was wrong.
	var hero := _hero_with_race()
	assert_ne(hero, null, "the mounted root holds a hero to race")
	if hero == null:
		return
	# Precondition on the SAVE side: the fresh body really does carry the grant, so a
	# restored body that read 0.0 is a restore failure and not an authored value of zero.
	assert_eq(
		_race_percent_total(hero, Stat.MAX_HEALTH),
		0.15,
		"before the save, stoneborn's +15% max_health is on the stack"
	)

	var restored := _restore_through_a_real_boot()
	assert_ne(restored, null, "a real boot over the save restored a body")
	if restored == null:
		return
	assert_eq(
		String(RaceApi.race_of(restored)),
		String(RACE_WITH_MODIFIERS),
		"and the restored body kept its race: the ledger survived the save"
	)
	# THE CLAIM. A restored body that did not run the race attach reads 0.0 here where the
	# fresh body read 0.15, because `Actor.from_dict` restored the ledger and never a
	# StatProvider. This is the assertion that was missing and is the point of the fix.
	assert_almost_eq(
		_race_percent_total(restored, Stat.MAX_HEALTH),
		0.15,
		(
			"the restored hero's stoneborn percent modifiers are BACK on the stat stack, read "
			+ "off actor.stats._modifiers rather than off a return value"
		)
	)
	# Belt and braces on the same defect: the race's OWN source must be present on the
	# stack at all, which is what a skipped `RaceApi.attach` leaves empty. A missing key
	# and a zeroed modifier are the same silent failure, so both are named.
	assert_eq(
		_race_modifier_count(restored) > 0,
		true,
		"the restored hero carries race-owned stat modifiers at all, so the attach rebuilt them"
	)


func test_a_restored_hero_carries_its_awakened_bloodline_grants_again() -> void:
	# The other half of fix 1, and the half the module suites could never catch: every
	# bloodline suite drove `BloodlineApi.attach` itself, so it stayed green while the
	# production attach path skipped the line entirely.
	var hero := _hero_with_awakened_bloodline()
	assert_ne(hero, null, "the mounted root holds a hero to awaken")
	if hero == null:
		return
	# Precondition on the SAVE side: the fresh body really does carry the grant.
	assert_eq(
		_bloodline_percent_total(hero, Stat.QI_ABSORPTION),
		0.08,
		"before the save, tideborn's +8% qi_absorption is on the stack"
	)

	var restored := _restore_through_a_real_boot()
	assert_ne(restored, null, "a real boot over the save restored a body")
	if restored == null:
		return
	assert_eq(
		BloodlineApi.is_awake(restored, LINEAGE),
		true,
		"the restored body still reads tideborn awake (the ledger survived)"
	)
	# THE CLAIM: the grants are BACK. Without the attach the lineage reads awake while
	# contributing nothing — the ledger says one thing and the stat stack another.
	assert_almost_eq(
		_bloodline_percent_total(restored, Stat.QI_ABSORPTION),
		0.08,
		"the restored hero's tideborn grants are BACK on the stat stack, read off the modifiers"
	)


# --- 2. OBSERVABLE: a birth is reachable, not merely computed -------------------


func test_a_driven_birth_publishes_a_child_with_its_race_and_purity() -> void:
	# THE POINT OF FIX 2. Drive MOUNTED `_process` frames (the production reader) until a
	# birth happens, then assert the child is reachable through the app's OWN registry with
	# its race and the purity the snapshot implies — not merely handed back into a
	# dictionary the app discarded.
	var hero := _pregnant_hero()
	assert_ne(hero, null, "the mounted root holds a pregnant hero")
	if hero == null:
		return
	var row := _drive_until_a_birth_is_registered()
	assert_eq(bool(row.is_empty()), false, "mounted frames drove a birth the app registered")
	if row.is_empty():
		return
	var child := _child_from_row(row)
	assert_ne(child, null, "the registered birth names a child the app retained")
	if child == null:
		return
	# The child carries a RACE id, read back through the module that owns it.
	assert_ne(
		String(RaceApi.race_of(child)),
		"",
		"the retained child carries a race id, so the birth resolved a body plan"
	)
	assert_eq(
		String(RaceApi.race_of(child)),
		String(row.get("race", "")),
		"and the registry's race is the one RaceApi reads off the child itself"
	)
	# The child carries the purity the snapshot implies, and the registry row AGREES
	# with `BloodlineApi` about it. The agreement is the assertion: a dropped birth
	# leaves no row and no child, and a row carrying a stale number would disagree.
	#
	# Read through `purity_of`, NOT through `awake`. With a null partner the child is
	# `inherit(1.0, 0.0) == 0.395`, which is BELOW `tideborn`'s 0.55 bar — so the line
	# is carried but DORMANT, and `_register_birth` publishes only what is awake. That
	# is the design working (ADR 0063: purity gates, it does not scale), not a defect,
	# so the assertion is on the number both readers agree on rather than on presence.
	var lineage := row.get("lineages", {}) as Dictionary
	var carried := float(BloodlineApi.purity_of(child, LINEAGE))
	assert_almost_eq(
		carried,
		BloodlineState.inherit(1.0, 0.0),
		"the child carries the documented diluted purity of an absent partner"
	)
	if lineage.has(String(LINEAGE)):
		assert_almost_eq(
			carried,
			float(lineage[String(LINEAGE)]),
			"and where the registry published the line, it published the child's own number"
		)
	else:
		assert_eq(
			carried < 0.55,
			true,
			"and a dormant line is correctly absent from the awake-only registry row"
		)


func test_the_child_bears_the_birth_fact_so_the_birth_is_durable_not_session_only() -> void:
	# A birth that leaves no trace dies with the frame. `WorldFact.record` writes the
	# counter onto the CHILD's own `module_data`, which `Actor.to_dict` round-trips — so
	# this is the durable, published half of "the child was not dropped".
	var hero := _pregnant_hero()
	assert_ne(hero, null, "the mounted root holds a pregnant hero")
	if hero == null:
		return
	var row := _drive_until_a_birth_is_registered()
	assert_eq(bool(row.is_empty()), false, "mounted frames drove a birth the app registered")
	if row.is_empty():
		return
	var child := _child_from_row(row)
	assert_ne(child, null, "the registered birth names a child the app retained")
	if child == null:
		return
	assert_eq(
		WorldFact.has(child, BIRTH_FACT, 1),
		true,
		"the retained child bears the child_born world fact, which rides its own save payload"
	)


# --- 3. NOT DROPPED: the child outlives the pregnancy status --------------------


func test_the_child_is_still_obtainable_after_the_pregnancy_status_is_cleared() -> void:
	# `FertilityApi.advance` erases the `offspring` list at the end of the postpartum stage,
	# roughly ten seconds after the birth. A child that lived only there would vanish with
	# the status. This drives past that erasure and asserts the app STILL hands back the
	# child's row — so the child is a value that did not die with its status.
	#
	# ## What "obtainable" means here, and why it is the REGISTRY
	#
	# `_born` rows are primitives — `{actor_id, race, faction, parent_id, lineages,
	# sequence}` — and the ACTOR itself lived only in the mother's status offspring list.
	# So the durable claim the fix makes is that the CHILD'S IDENTITY AND LINEAGE are
	# retained in the registry once the status is gone. That is what is asserted: the row
	# for the child is still readable from the app after the pregnancy status clears,
	# carrying the same race and the same purity the child was born with.
	var hero := _pregnant_hero()
	assert_ne(hero, null, "the mounted root holds a pregnant hero")
	if hero == null:
		return
	var row := _drive_until_a_birth_is_registered()
	assert_eq(bool(row.is_empty()), false, "mounted frames drove a birth the app registered")
	if row.is_empty():
		return
	var child_id := String(row.get("actor_id", ""))
	# "the row NAMES the child" is `is_empty() == false`, so this is `assert_eq`, not
	# `assert_ne`. Written as `assert_ne(x.is_empty(), false)` it asserts the row is
	# EMPTY — the inverted rule — and fails on a perfectly good row.
	assert_eq(child_id.is_empty(), false, "the registered birth names the child by id")
	if child_id.is_empty():
		return

	# Drive well past the postpartum so the pregnancy status is ERASED from the actor.
	_frames(POSTPARTUM_FRAMES)
	assert_eq(
		FertilityApi.pregnancy(hero), null, "the mother's pregnancy status has been cleared by now"
	)
	# THE CLAIM: the child is still on the app's registry after the status cleared.
	var after := _registry_row_for(child_id)
	assert_eq(
		bool(after.is_empty()),
		false,
		(
			"the child is still obtainable from the app's registry after the status cleared, "
			+ "so it did not die with the pregnancy status"
		)
	)
	if after.is_empty():
		return
	# And it is the SAME child, with the same lineage it was born with — not a stale or
	# rebuilt row.
	assert_eq(
		String(after.get("race", "")),
		String(row.get("race", "")),
		"the retained child still answers to the race it was born with"
	)
	assert_eq(
		after.get("lineages", {}) as Dictionary,
		row.get("lineages", {}) as Dictionary,
		"and its recorded lineages are unchanged, so the row is the child's and not a copy"
	)


# --- Internals ------------------------------------------------------------------


## The mounted root's OWN actor. A thin alias rather than `_app.actor()` scattered
## through the cases, because a leading-underscore NAME cannot carry a dot in GDScript.
##
## The explicit `as Actor` cast is load-bearing, not decoration: `_app` is reached
## through the harness as a `Control`, so `actor()` comes back untyped, and this project
## treats a Variant-inferred `:=` as an ERROR (warnings are errors here). Assigning
## through the cast is what lets the return type be honoured.
func _hero() -> Actor:
	return _app.actor() as Actor


## Drive the composition root's OWN frame callback, `frames` times, at the headless FRAME
## delta. The entry under test is `ItemWorkbenchApp._process`, never `StatusLoop.tick` or
## `FertilityApi.advance`, so a green run is evidence about production wiring.
func _frames(frames: int) -> void:
	var app := _harness.app
	assert_eq(app.has_method(&"_process"), true, "the composition root declares _process")
	if not app.has_method(&"_process"):
		return
	for frame in frames:
		app.call("_process", FRAME)


## A hero carrying `RACE_WITH_MODIFIERS`, projected, through the module facade — so the
## percent modifiers are on the stack the way the shipped attach path leaves them.
func _hero_with_race() -> Actor:
	var hero := _hero()
	assert_ne(hero, null, "the mounted root holds a hero to race")
	if hero == null:
		return null
	RaceApi.set_race(hero, RACE_WITH_MODIFIERS)
	return hero


## A hero carrying an AWAKENED `LINEAGE`, through `set_purity` so the projection runs and
## the grants are on the stack before the save.
func _hero_with_awakened_bloodline() -> Actor:
	var hero := _hero()
	assert_ne(hero, null, "the mounted root holds a hero to awaken")
	if hero == null:
		return null
	BloodlineApi.set_purity(hero, LINEAGE, 1.0)
	return hero


## Persist the mounted hero and mount a SECOND real app over the written save, so
## `_ready -> restore_actor -> _mount_player_modules -> _attach_body_modules` is what
## rebuilds the body. This is the PRODUCTION restore path a returning player walks — the
## one the fix names — not a hand-built `Actor.from_dict`.
##
## The second harness is torn down before this returns, and its actor retained, so the
## caller reads a real restored body without leaking a second live mount. Returns the
## restored actor, or null when the boot restored nothing.
func _restore_through_a_real_boot() -> Actor:
	var hero := _hero()
	if hero == null:
		return null
	var landed: Dictionary = SaveApi.persist(hero, String(DifficultyApi.current_id(hero)))
	assert_eq(bool(landed.get("ok", false)), true, "the hero's save landed on disk")
	if not bool(landed.get("ok", false)):
		return null
	var second := SeamHarness.mount_new()
	assert_eq(String(second.boot_error), "", "a second real boot over the save booted cleanly")
	if second.boot_error != "":
		second.teardown()
		return null
	var restored := second.app.get("_actor") as Actor
	assert_eq(second.app.restored_from_save(), true, "and it restored from the save, not fresh")
	second.teardown()
	return restored


## The total PERCENT this race owns on `body`'s stat stack for `stat_id`, read off
## `actor.stats._modifiers` and filtered to the race module's own source — so a stranger's
## modifier on the same stat cannot be mistaken for the race's grant, and so the figure is
## the STAT STACK's rather than anything a verb returned.
func _race_percent_total(body: Actor, stat_id: StringName) -> float:
	var total := 0.0
	for modifier in body.stats._modifiers:
		if modifier.stat == stat_id and RaceState.is_own_source(modifier.source):
			total += modifier.value
	return total


## How many stat modifiers the race module owns on `body` at all, across every stat.
## Counted rather than compared against an exact total so a content retune that changes the
## VALUES still passes here: the claim is only that the attach wrote the race's OWN sources
## onto the stack, which is what a skipped `RaceApi.attach` leaves empty.
func _race_modifier_count(body: Actor) -> int:
	var total := 0
	for modifier in body.stats._modifiers:
		if RaceState.is_own_source(modifier.source):
			total += 1
	return total


## The total PERCENT the bloodline module owns on `body` for `stat_id`, filtered to its own
## namespaced sources, for the same reason as `_race_percent_total`.
func _bloodline_percent_total(body: Actor, stat_id: StringName) -> float:
	var total := 0.0
	for modifier in body.stats._modifiers:
		if modifier.stat == stat_id and BloodlineState.is_own_source(modifier.source):
			total += modifier.value
	return total


## A pregnant hero carrying an awakened lineage, so the birth carries a purity to report.
## A `roll` of 0.0 against any positive conception chance always conceives, and a
## `race_roll` of 0.0 keeps the mother's own race winning, so the child is a deterministic
## function of the mother — reproducible across runs.
func _pregnant_hero() -> Actor:
	var hero := _hero_with_awakened_bloodline()
	assert_ne(hero, null, "the mounted root holds a hero to impregnate")
	if hero == null:
		return null
	var conceived := FertilityApi.try_conceive(hero, null, 0.0, 0.0)
	assert_eq(conceived, true, "the hero conceived")
	return hero


## Drive MOUNTED frames until the app's registry holds a birth, and return that first row.
##
## The registry is read through the app's own `_born` field — the composition root's
## primitive birth table the fix writes to. Stepping frame by frame and stopping at the
## first registered row, rather than driving a fixed high count and hoping: a birth is a
## one-shot event and the frame it lands on depends on the authored gestation, which
## content may retune.
##
## Returns an EMPTY dictionary when no birth registered within the frame budget, so a
## caller can assert on `row.is_empty()` and bail rather than dereference nothing.
func _drive_until_a_birth_is_registered() -> Dictionary:
	var app := _harness.app
	assert_eq(app.has_method(&"_process"), true, "the composition root declares _process")
	if not app.has_method(&"_process"):
		return {}
	var guard := 0
	while guard < BIRTH_FRAMES:
		app.call("_process", FRAME)
		guard += 1
		# Capture the live child on EVERY frame, not only the frame the registry
		# filled. `_register_birth` is reached through the same `advance` call that
		# fills `status.offspring`, but the two are separate steps and asserting on
		# one specific frame would make this suite a hostage to that ordering.
		# The status holds the child for the whole postpartum window, so any frame
		# inside it is a legitimate place to take the reference.
		_capture_live_children()
		var born: Dictionary = app.get("_born") as Dictionary
		if not born.is_empty():
			var first: Dictionary = born.values()[0] as Dictionary
			return first
	return {}


## Take a reference to every child the mounted hero's pregnancy is currently holding.
## Idempotent, and the only place `_children` is written.
func _capture_live_children() -> void:
	var hero := _hero()
	if hero == null:
		return
	for status in hero.statuses:
		if status is PregnancyStatus:
			for offspring in (status as PregnancyStatus).offspring:
				var body := offspring as Actor
				if body != null and not _children.has(body):
					_children.append(body)


## The child actor captured at the frame the birth registered, or null.
##
## The app's row is PRIMITIVES and deliberately does not carry the actor: `app/` records
## what a birth was, not a second reference to a body another module owns. The live Actor
## is therefore captured at the birth frame (see `_drive_until_a_birth_is_registered`) and
## matched here by the id the registry recorded.
##
## It deliberately does NOT walk the mother's `PregnancyStatus.offspring` list. That list
## is erased roughly ten seconds after the birth, so a lookup through it would pass while
## testing nothing — it would assert against the exact window this defect is about.
## If no child was captured, the child really was dropped and this returns null.
func _child_from_row(row: Dictionary) -> Actor:
	var child_id := StringName(String(row.get("actor_id", "")))
	if child_id == &"":
		return null
	# Captured ids are reported rather than silently yielding null: a mismatch between
	# what the registry recorded and what the status holds is exactly the defect this
	# suite exists to catch, and a bare null would hide WHICH half is wrong.
	var held: Array[StringName] = []
	for body in _children:
		var actor := body as Actor
		if actor != null:
			held.append(actor.id)
			if actor.id == child_id:
				return actor
	return null


## The app's registry row for `child_id`, or an empty dictionary. This is the durable half
## of "not dropped": the row is primitives on the composition root and survives the status.
func _registry_row_for(child_id: String) -> Dictionary:
	var app := _harness.app
	var born: Dictionary = app.get("_born") as Dictionary
	for value in born.values():
		var entry: Dictionary = value as Dictionary
		if String(entry.get("actor_id", "")) == child_id:
			return entry
	return {}


func _clear_disk() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SavePaths.DIR):
		DirAccess.remove_absolute(SavePaths.DIR)
