extends TestCase

## The three wirings the death/rebirth program needed and did not originally have.
##
## ## Why these cases exist as a separate suite
##
## Every module suite passed while `difficulty` and `anchor` were reachable ONLY from a headless
## test. Nothing in `app/` opened a difficulty or raised a hearth, so a player could select no
## preset and stand in no building — the features were complete and unwired, which is the shape
## DEF-0109, DEF-0151 and BL-0121 all record in this repo.
##
## These cases assert the PRODUCTION DOOR: the verbs a shipped screen calls, on the app root,
## going through the same period boundary the "wait a season" button uses.
##
## ## Why this suite mounts the REAL scene
##
## Through `SeamHarness`, which parents the shipped `ItemWorkbenchApp.tscn` and drives `_ready`
## the way the engine would. An app built with `ItemWorkbenchApp.new()` alone leaves `_actor`
## null — `_ready` is where the actor is born — so every case would fail on a null body rather
## than on the wiring being wrong. Asserting against a mounted root is also the harness's own
## rule: a test that instantiates its own copy proves the file parses and nothing about the game.

const HEARTH := &"hearth_of_the_returning"

var _harness: SeamHarness
var _app: ItemWorkbenchApp
var _soul_store: SoulWorldLedger
var _anchor_store: AnchorWorldLedger


func setup() -> void:
	_clear_disk()
	_harness = SeamHarness.mount_new()
	_app = _harness.app as ItemWorkbenchApp
	# The stores are installed AFTER the mount, because `_ready` installs its own and would
	# discard anything set beforehand. Re-pointing them afterwards is what makes this suite's
	# ledger the one the root reads — and it is the same order a real boot uses, so the cases
	# below drive the production path rather than a private arrangement.
	_soul_store = SoulWorldLedger.new()
	_anchor_store = AnchorWorldLedger.new()
	SoulApi.set_store(_soul_store)
	AnchorApi.set_store(_anchor_store)
	SaveApi.install_store("soul", _soul_store)
	SaveApi.install_store("anchor", _anchor_store)
	if _app.actor() != null:
		SoulApi.attach(_app.actor())
		AnchorApi.attach(_app.actor())


func teardown() -> void:
	_clear_disk()
	if _harness != null:
		_harness.teardown()
	_harness = null
	_app = null
	SoulApi.set_store(null)
	AnchorApi.set_store(null)
	SaveApi.install_store("soul", null)
	SaveApi.install_store("anchor", null)


# --- The root is a live root -------------------------------------------------


func test_the_harness_mounted_a_booted_app_that_holds_a_hero() -> void:
	# The precondition every other case rests on. Asserted first because a mount that failed
	# would otherwise make each of them report a null-body error rather than saying so once.
	assert_eq(String(_harness.boot_error), "", "the shell booted")
	assert_eq(_app != null, true, "there is a composition root")
	assert_eq(_app.actor() != null, true, "and it holds a hero")


# --- Difficulty reaches play -------------------------------------------------


func test_the_app_publishes_a_difficulty_selector_a_settings_screen_can_call() -> void:
	# The door exists and answers with the scalars the run now plays under.
	var out := _app.select_difficulty(&"hard")
	assert_eq(bool(out["ok"]), true, "hard was selected: %s" % out.get("reason", ""))
	assert_eq(String(out["difficulty_id"]), "hard", "and named")
	assert_eq(
		float((out["scalars"] as Dictionary)["soul_damage_share"]),
		1.5,
		"with the scalars that preset carries"
	)


func test_selecting_difficulty_persists_so_a_save_records_what_it_was_playing_under() -> void:
	_app.select_difficulty(&"hard")
	assert_eq(
		String(_app.soul_summary()["difficulty"]),
		"hard",
		"the root reports the preset the run is under"
	)


func test_an_unauthored_preset_is_refused_by_name_rather_than_silently_accepted() -> void:
	var out := _app.select_difficulty(&"nightmare")
	assert_eq(bool(out["ok"]), false, "an unauthored preset is refused")
	assert_eq(String(out["reason"]), "unknown_difficulty", "and named")
	assert_eq(
		String(_app.soul_summary()["difficulty"]),
		"standard",
		"so the run is still on the neutral preset"
	)


# --- The building feature reaches play ----------------------------------------


func test_the_app_publishes_an_anchor_raise_a_construction_screen_can_call() -> void:
	_give_hearth_materials()
	var out := _app.raise_anchor(&"hearth_of_the_returning")
	assert_eq(bool(out["ok"]), true, "the hearth was raised: %s" % out.get("reason", ""))
	assert_eq(
		bool(AnchorApi.is_raised(_soul_actor(), &"hearth_of_the_returning")), true, "and it stands"
	)


func test_an_unaffordable_anchor_records_its_debt_instead_of_pretending() -> void:
	var out := _app.raise_anchor(&"hearth_of_the_returning")
	assert_eq(bool(out["ok"]), false, "nothing was paid, so nothing was raised")
	assert_eq(String(out["reason"]), "cannot_afford", "and it says so")
	assert_eq(int(out["owed"]) > 0, true, "with the outstanding debt recorded")


# --- The anchor actually repairs on a period ----------------------------------


func test_waiting_a_period_at_a_hearth_repairs_the_soul_in_play() -> void:
	# The whole point of this wiring. Before it, the hearth existed and healed nobody: the
	# repair verb was reachable only from a headless test.
	var actor := _soul_actor()
	SoulApi.damage(actor, 40, "test")
	var damaged := int(SoulApi.soul(actor)["integrity"])
	_give_hearth_materials()
	assert_eq(bool(_app.raise_anchor(&"hearth_of_the_returning")["ok"]), true, "the hearth stands")
	var outcome := _app.advance_one_period()
	assert_eq(outcome.has("anchor_repair"), true, "the period reports what the anchor did")
	var repair: Dictionary = outcome["anchor_repair"]
	assert_eq(
		bool(repair["ok"]),
		true,
		(
			"and the hearth healed (%s, anchor %s)"
			% [repair.get("reason", ""), repair.get("anchor_id", "")]
		)
	)
	assert_eq(int(repair["restored"]) > 0, true, "by a real amount")
	assert_eq(
		int(SoulApi.soul(actor)["integrity"]) > damaged,
		true,
		"so the soul is measurably less damaged"
	)


func test_waiting_a_period_with_no_anchor_repairs_nothing_and_says_why() -> void:
	var outcome := _app.advance_one_period()
	var repair: Dictionary = outcome["anchor_repair"]
	assert_eq(bool(repair["ok"]), false, "nothing to repair from")
	assert_eq(String(repair["reason"]), "not_raised", "and it is named rather than silent")


# --- The world keeps going across a death ---------------------------------------


func test_the_root_reports_the_whole_rebirth_surface_a_screen_needs() -> void:
	# One read for a screen: the soul, the preset, the anchors, the last death and the save's
	# condition. Assembled here rather than in each screen so they cannot disagree.
	var summary := _app.soul_summary()
	for key in ["soul", "difficulty", "anchors", "last_death", "save"]:
		assert_eq(summary.has(key), true, "%s is published" % key)


func test_a_reborn_body_is_the_one_every_later_read_answers_from() -> void:
	# The swap is not local: after a rebirth the anchors and the save follow the NEW body, so a
	# screen reading the root cannot be looking at the body that fell.
	var first := _soul_actor()
	SoulApi.damage(first, 10, "test")
	# The two seams the composition root injects, written out rather than inlined into a
	# lambda pair: a multi-line lambda list ending in a comma does not parse in GDScript, and
	# the error reads as a corrupt file rather than as a syntax slip.
	var mint := func(arrival_id: String, incarnation: int) -> Dictionary:
		return CharacterCreationFlow.build_forced(StringName(arrival_id), incarnation)
	var adopt := func(body: Actor) -> void: _app.adopt_actor(body)
	var resolver := SoulDeath.new(mint, adopt)
	var pool := first.resource(&"health")
	pool.change(-pool.maximum)
	resolver.resolve(first)
	var second := _soul_actor()
	assert_ne(second.id, first.id, "the body changed")
	assert_eq(
		int(SoulApi.soul(second)["integrity"]),
		int(SoulApi.soul(first)["integrity"]),
		"and the soul crossed with it"
	)


# --- Internals -----------------------------------------------------------------


## The actor the root is currently holding. A thin alias rather than `_app.actor()`
## scattered through the cases, because a leading-underscore NAME cannot carry a dot in
## GDScript — `_app.actor()` parses `_app` as a type name and fails with "Unexpected token
## DOT", which reads as a corrupt file rather than as a naming slip.
func _soul_actor() -> Actor:
	return _app.actor()


## Give the actor what the hearth's authored cost asks for, so a raise is affordable.
func _give_hearth_materials() -> void:
	var actor := _app.actor()
	if ItemsApi.inventory(actor) == null:
		ItemsApi.attach(actor)
	var bag := ItemsApi.inventory(actor)
	var def := Crafting.resolve(&"vial_mending_elixir")
	if def != null and not bag.has(&"vial_mending_elixir", 2):
		bag.add(def, 2)


func _clear_disk() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SavePaths.DIR):
		DirAccess.remove_absolute(SavePaths.DIR)
