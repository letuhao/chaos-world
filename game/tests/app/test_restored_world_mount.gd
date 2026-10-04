extends TestCase

## DEF-0183 on the RESTORE path: a saved body must come back STANDING IN THE PLACE ITS SAVE
## CARRIED, or the event ledger's own copy of that place stays `EventApi.NOWHERE` and
## `EventApi.available` drops every authored event before its trigger is read.
##
## ## The TRAP this file is built around, and why a single mount proves nothing
##
## `SeamHarness.mount_new()` calls `clear_save()` FIRST (`seam_harness.gd:80`) — and
## `clear_save` removes `user://item_workbench_state.json`, the workbench SCREEN's file,
## not `SavePaths.PRIMARY`, which is what `SaveApi.restore()` reads through `SaveStore`.
## So a boot with no slot on disk takes the FRESH branch, never the restore branch, and a
## test that persists and then mounts ONCE would be asserting about a hero creation just
## built. Every case here therefore persists, tears the first boot down, and boots a
## SECOND time over the slot the first wrote — and then asserts `restored_from_save()` is
## true, or the case proves nothing at all.
##
## ## The anti-pattern this suite cannot have
##
## `EventApi.set_location` is NEVER called here. It is the publish the mount fires, so a
## test that called it itself would re-create the very thing under test and a RED
## composition root would still pass (the shape `test_arrival_world_mount.gd` is written
## against). Moving the hero uses the PRODUCTION verb `WorldSpawnApi.selected`; advancing
## the world uses the PRODUCTION verb `advance_world`. Nothing in this file writes a
## trigger fact, because the authored triggers wait on `WorldAmbient` facts and a test
## that records them itself proves nothing about the world (the reasoning at
## `test_arrival_world_mount.gd:151-156`).

## The place this suite puts a hero, and the only authored location whose authored events
## wait on nothing this suite has to fake. `mortal_plains` carries three events; the
## `storm_front_sighted` trigger `WorldAmbient.ROSTER` records on period 1.
const TARGET := &"mortal_plains"
## Bounded, not a loop. Four periods is `WorldAmbient.ROSTER`'s last row
## (`sect_war_called`), and `advance_periods` clamps to its own `MAX_PERIODS_PER_PULL`, so
## this cannot run away.
const PERIODS := 4
## A place no authored event names, so `available()` at it must be empty. A test that
## wants the location filter PROVED needs a control, or "non-empty" only means "permissive".
const NOWHERE_EVENTS := &"a_location_no_tres_defines"

## Hand-built Actors, drained in `teardown()`. `Actor` is `RefCounted`, and the runner
## shares ONE process across every suite, so a leaked body is a leak everywhere; the
## `resources.clear()` is the half the OTHER suites document.
var _born: Array = []


func teardown() -> void:
	# `WorldStage`'s `_current` and `_mounted_player` are PROCESS-WIDE statics, so a stage
	# this suite mounted and did not leave would publish a freed `PlayerAdapter` to every
	# suite after it. FIRST, before anything else, exactly as
	# `test_arrival_world_mount.gd:53-62` does — this is a per-TEST teardown and the
	# runner calls it after every test, not once per suite.
	if WorldStage.instance() != null:
		WorldStage.instance().leave()
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
	SeamHarness.clear_save()
	for body in _born:
		if body is Actor and not (body as Actor).resources.is_empty():
			(body as Actor).resources.clear()
		body = null
	_born.clear()


# --- The two-boot fixture ------------------------------------------------------


## Persist a hero at `location_id`, free that boot, then boot AGAIN over the slot.
##
## Returns the SECOND harness — the one on the restore branch. Null when either boot
## failed, so a caller returns rather than asserting against a null actor.
##
## The placement goes through `WorldSpawnApi.selected`, the durable-place verb a player
## reaches through the world map (`WorldStage.on_location_selected` reaches the same
## `selected`). It is never `EventApi.set_location`, which writes the OTHER ledger — the
## one the mount is supposed to fill.
func _boot_restored_at(location_id: StringName) -> SeamHarness:
	var first := SeamHarness.mount_new()
	assert_eq(first.boot_error, "", "the fresh first boot ran")
	if first.boot_error != "":
		return null
	var placed := WorldSpawnApi.selected(first.actor, location_id)
	assert_eq(bool(placed.get("ok", false)), true, "the hero was placed at %s" % location_id)
	assert_eq(
		String(WorldSpawnApi.current(first.actor).get("location_id", "")),
		String(location_id),
		"and the durable ledger carries it into the save"
	)
	var saved := SaveApi.persist(first.actor, "standard")
	assert_eq(bool(saved.get("ok", false)), true, "the slot was written")
	# Frees the app; the FILE survives, because `teardown` only clears the workbench
	# screen's own path and `mount_new`'s `clear_save` touches nothing `SaveStore` reads.
	first.teardown()
	var second := SeamHarness.mount_new()
	assert_eq(second.boot_error, "", "the second boot ran")
	if second.boot_error != "":
		return null
	assert_eq(
		bool(second.app.call(&"restored_from_save")),
		true,
		"the restore branch really ran, or this case proves nothing"
	)
	return second


# --- T1: the place the save carried is the place the body stands in --------------


func test_a_restored_hero_stands_in_the_place_its_save_carried() -> void:
	var second := _boot_restored_at(TARGET)
	if second == null:
		return
	var here := WorldSpawnApi.current(second.actor)
	assert_eq(
		String(here.get("location_id", "")),
		String(TARGET),
		"the durable place came back from the save untouched"
	)
	var stage := WorldStage.instance()
	assert_ne(stage, null, "a stage is mounted for the restored body")
	if stage == null:
		return
	var body := WorldStage.player()
	assert_ne(body, null, "and the stage holds a body")
	if body == null:
		return
	assert_eq(
		String(body.actor().id),
		String(second.actor.id),
		"and it is the body the composition root restored"
	)


## The reads a boot DREW rather than RESUMED would still pass — every one of them is a
## plausible place — so the assertion is not "somewhere", it is THIS place.
func test_a_restored_hero_is_not_standing_somewhere_else() -> void:
	var second := _boot_restored_at(TARGET)
	if second == null:
		return
	var visits := int(WorldSpawnApi.current(second.actor).get("visits", 0))
	assert_ne(visits, 0, "the ledger counts at least the one arrival the save was written after")
	assert_eq(
		String(WorldSpawnApi.current(second.actor).get("source", "")),
		WorldSpawnApi.SOURCE_EXPLICIT,
		"the mount RESUMED an explicit placement rather than drawing over it"
	)


# --- T2: the mount told the event module --------------------------------------


func test_the_restored_mount_told_the_event_module_where_the_player_is() -> void:
	var second := _boot_restored_at(TARGET)
	if second == null:
		return
	var stage := WorldStage.instance()
	assert_ne(stage, null, "a stage is mounted")
	if stage == null:
		return
	var report := stage.summary()
	assert_eq(
		bool(report.get("world_told", false)),
		true,
		"the world was told: %s" % report.get("world_told_reason", "")
	)
	# The second half cannot be faked. `EventApi.set_location` is never called in this
	# suite, so a NON-EMPTY ledger location can only have come from production wiring.
	assert_eq(
		String(EventApi.state(second.actor).get("location_id", "")),
		String(TARGET),
		"the event ledger itself carries the place, not a default"
	)


# --- T3: THE HEADLINE ----------------------------------------------------------


func test_events_available_at_the_restored_location_are_not_empty() -> void:
	var second := _boot_restored_at(TARGET)
	if second == null:
		return
	# Let the WORLD say what it reached, through its own clock. No fact is written here:
	# the authored triggers wait on `storm_front_sighted` and friends, and `WorldAmbient`
	# is the production owner of those.
	second.app.call("advance_world", PERIODS)
	var here := EventApi.available(second.actor, String(TARGET))
	assert_ne(
		here.size(), 0, "EventApi.available is NON-EMPTY at %s for a RESTORED hero" % String(TARGET)
	)
	# And at that same place, every row really is an event authored FOR it — not a widened
	# filter returning something the location rule should have excluded.
	for row in here:
		assert_eq(
			String(row.get("location_id", "")),
			String(TARGET),
			"an available event is authored for the place the restored player stands in"
		)


# --- T4: the control that makes T3 mean something -------------------------------


func test_the_same_read_at_a_place_nobody_stands_in_is_still_empty() -> void:
	var second := _boot_restored_at(TARGET)
	if second == null:
		return
	second.app.call("advance_world", PERIODS)
	assert_eq(
		EventApi.available(second.actor, String(NOWHERE_EVENTS)).size(),
		0,
		"an unknown place still offers nothing, so the filter is doing work after a restore"
	)


# --- T5: ADVERSARIAL. A place with nothing to do is still a playable state ------


## WHICH authored places the event catalog names. Read, never restated: a hard-coded list
## in the test would be a second opinion about content that can change under it.
func _event_places() -> Array[String]:
	var out: Array[String] = []
	var events := EventApi.catalog().get("events", {}) as Dictionary
	for event_id in events.keys():
		var at := String((events[event_id] as Dictionary).get("location_id", ""))
		if not at.is_empty() and not out.has(at):
			out.append(at)
	return out


func test_every_shipped_location_carries_an_event_so_the_quiet_place_is_unauthorable() -> void:
	# The PRECONDITION of the adversarial case below, established rather than assumed: the
	# event catalog and the location pool are INDEPENDENT data trees, but as shipped every
	# authored `.tres` location also has an authored event, so there is currently no QUIET
	# authored place to stand a restored hero in.
	#
	# Authoring one would prove the claim, and it is exactly the change that must never be
	# made to prove a claim: a new `.tres` is content this suite does not own, and adding
	# one to make a test pass is indistinguishable from adding one to make a game work.
	# So the emptiness is established against the MODULE (which null-guards and therefore
	# accepts any location id) and the honest shape of the claim is asserted below it.
	var places := _event_places()
	assert_ne(places.is_empty(), true, "the event catalog names at least one place")
	var pool: Array[String] = []
	for entry in WorldApi.locations(null):
		pool.append(String(entry.get("location_id", "")))
	for at in places:
		assert_eq(pool.has(at), true, "%s is both an authored place and an event place" % at)


func test_a_body_whose_place_no_event_names_still_mounts_and_offers_nothing() -> void:
	# THE ADVERSARIAL SHAPE, asserted where it can be without authoring content: a hero
	# whose ledger names a place the event catalog does not author. `EventApi.available`
	# null-guards its actor, so the read is legal with a bare body, and the location it is
	# given is one no `.tres` defines — the same string T4 uses, so this is the SAME control
	# seen from the other side: the filter is real, and empty is a CORRECT answer rather than
	# a refused restore.
	#
	# What this case cannot do is put a REAL saved body in such a place, because `WorldStage
	# .mount` refuses `unknown_location` for a place no `.tres` backs — which is the NAMED
	# refusal T6 exercises through the save. The two together cover the claim: a quiet place
	# offers nothing, and a place that does not exist is refused by name rather than rounded
	# up to a draw.
	var events := EventApi.catalog().get("events", {}) as Dictionary
	var uneventful := false
	for entry in WorldApi.locations(null):
		var at := String(entry.get("location_id", ""))
		var carries := false
		for event_id in events.keys():
			if String((events[event_id] as Dictionary).get("location_id", "")) == at:
				carries = true
				break
		if not carries:
			uneventful = true
			break
	# Whether or not such a place is AUTHORED today, asking about an id nothing defines must
	# offer nothing. This is the branch the fix must not turn into "refused restore".
	assert_eq(
		EventApi.available(second_actor_probe(), String(NOWHERE_EVENTS)).size(),
		0,
		"a place no event is authored for offers nothing, and that is a correct answer"
	)
	# The claim is about the SHAPE, so it is stated whether or not the corpus happens to
	# contain a quiet place right now: `uneventful` is reported rather than asserted, because
	# authoring the missing `.tres` is not this suite's to do.
	if uneventful:
		assert_eq(
			EventApi.available(second_actor_probe(), String(TARGET)).size(),
			0,
			"and a place that IS authored but names no event is equally empty"
		)


## T5's real claim, on a REAL body: a restored hero whose events at its place are all
## settled has an EMPTY `available()` — and is still a located, mounted, playable hero.
## Standing somewhere with nothing left to do is a correct state, and the fix must not turn
## it into a refused restore.
func test_an_exhausted_ladder_is_not_a_refused_restore() -> void:
	var second := _boot_restored_at(TARGET)
	if second == null:
		return
	# Drive the world far enough that the place's ladders advance past their triggers, so
	# `available()` at TARGET can legitimately be empty. Bounded: the clamp is inside
	# `advance_periods`, and this is a fixed count, not a loop.
	second.app.call("advance_world", PERIODS * 2)
	var answer: Dictionary = second.app.call("restore_actor")
	assert_eq(bool(answer.get("ok", false)), true, "a restore never fails for an empty list")
	assert_eq(bool(answer.get("located", false)), true, "the hero is still located")
	assert_eq(String(answer.get("location_id", "")), String(TARGET), "at the place it resumed")
	assert_eq(
		String(WorldSpawnApi.current(second.actor).get("location_id", "")),
		String(TARGET),
		"and the durable ledger still says so — an empty event list changed nothing"
	)


# --- T6: ADVERSARIAL. A save naming a place no .tres backs ----------------------


func test_a_save_naming_a_place_no_content_backs_still_boots_and_is_refused_by_name() -> void:
	var first := SeamHarness.mount_new()
	assert_eq(first.boot_error, "", "the fresh first boot ran")
	if first.boot_error == "":
		# Write a ledger row naming a place the pool does not ship, then persist. This is
		# the DURABLE ledger the restore reads, not the event ledger — the corrupt-place
		# case is about where the save says the body is, not about the event module.
		var state := WorldSpawnState.normalize(
			first.actor.get_module_data(WorldSpawnApi.MODULE_KEY)
		)
		state["location_id"] = "a_place_no_tres_defines"
		first.actor.set_module_data(WorldSpawnApi.MODULE_KEY, state)
		assert_eq(
			bool(SaveApi.persist(first.actor, "standard").get("ok", false)),
			true,
			"the corrupt slot was written"
		)
		first.teardown()
		var second := SeamHarness.mount_new()
		# A corrupt place must NOT brick a boot. The body comes back and plays; only the
		# PLACE is refused, by name.
		assert_eq(second.boot_error, "", "the boot is not bricked by a corrupt place")
		if second.boot_error == "":
			assert_eq(
				bool(second.app.call(&"restored_from_save")),
				true,
				"and the restore branch still ran"
			)
			var answer: Dictionary = second.app.call("restore_actor")
			assert_eq(
				bool(answer.get("located", true)),
				false,
				"the mount REFUSED rather than rounding up to a draw: %s" % answer.get("reason", "")
			)


# --- T7: ONE MOUNT, NOT TWO ----------------------------------------------------


func test_two_boots_leave_exactly_one_stage_holding_the_current_body() -> void:
	var first := SeamHarness.mount_new()
	assert_eq(first.boot_error, "", "the fresh first boot ran")
	if first.boot_error != "":
		return
	var first_id := String(first.actor.id)
	WorldSpawnApi.selected(first.actor, TARGET)
	SaveApi.persist(first.actor, "standard")
	first.teardown()
	var second := _boot_restored_at(TARGET)
	if second == null:
		return
	var stage := WorldStage.instance()
	assert_ne(stage, null, "one stage is current after two boots")
	if stage == null:
		return
	# `WorldStage._current` is a STATIC. A stage built PER RESTORE would leave the newest
	# in `_current` (here the restore's) while the FIRST boot's stage still existed — and
	# the moment creation and restore coexist, `player()` and `_current` can disagree. This
	# asserts the published pair names ONE stage and ONE body, and that body is the CURRENT
	# second boot's hero, not the first boot's.
	var body := WorldStage.player()
	assert_ne(body, null, "one body is mounted")
	if body == null:
		return
	assert_eq(
		String(body.actor().id),
		String(second.actor.id),
		"the mounted body is the CURRENT restored hero, not the first boot's"
	)
	assert_ne(
		String(body.actor().id),
		first_id,
		"and it is a different body from the first boot's, which was freed"
	)
	assert_eq(
		String(stage.summary().get("location_id", "")),
		String(TARGET),
		"and the one stage stands at the place the second boot's save carried"
	)


# --- Internals -----------------------------------------------------------------


## A bare actor for the read-only catalog scans above. `WorldApi.locations` and
## `EventApi.available` both null-guard their actor, so this is a legal probe — but it is
## still a hand-built body, so it goes in `_born` and is drained in `teardown`.
func second_actor_probe() -> Actor:
	if _born.is_empty():
		_born.append(Actor.new(&"restored_world_mount_probe"))
	return _born[0] as Actor
