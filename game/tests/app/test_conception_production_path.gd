extends TestCase

## ## THE ACCEPTANCE CASE, and it is an end-to-end proof rather than a unit test
##
## Everything under test here is reached the way a PLAYER reaches it:
##
## 1. A personal bond is raised above `Seduction.REQUIRED_STANDING` by **player actions
##    only** — `KinshipApp.fight_alongside`, twice, which is the two-press fight route
##    (`helped_in_combat` 3.0 then `spared_in_combat` 4.0 = 7.0). **This suite never calls
##    `apply_cause` to clear the floor.** That is the whole claim of BL-0717 / BL-0751:
##    before this change the only production writer of the row `can_meet` reads was
##    `apply_cause` on the SUCCESS PATH of the attempt the gate refuses, which is circular.
## 2. `Seduction.can_meet` flips FALSE -> TRUE. Read through `KinshipApp.read_conception`,
##    the app-level read model, not through the module — the panel and this suite read the
##    same numbers.
## 3. A conception is ATTEMPTED through `KinshipApp.attempt_conception`, which is the one
##    production caller of `Seduction.attempt` in the tree.
## 4. Gestation is advanced on the clock the composition root already owns — the mounted
##    root's OWN `_process`, never `StatusLoop.tick` and never `FertilityApi.advance`.
## 5. The child is retrieved from the composition root's OWN `_born` registry with a
##    resolved race and an inherited bloodline.
##
## ## Why the suite mounts the REAL scene rather than driving the app verbs directly
##
## Because a test that drives `KinshipApp` alone stays green the day the production install
## at `npc_boot.gd` is deleted — which is precisely the shape of proof that let the original
## "computed and dropped" birth defect ship. [method test_the_production_install_binds_the_seams]
## pins the install separately, and [method test_a_boot_with_nothing_installed_says_no_resolver]
## pins the unbound behaviour, so the two halves cannot both pass while the wiring is absent.
##
## ## Disk discipline
##
## `user://save` is cleared before every mount and after every case: the runner shares ONE
## process across every suite, so a save left behind is read by whichever suite boots next.

## One quarter-second frame, at the same 60 Hz the engine runs at (ADR 0089: a headless test
## passes its OWN delta rather than reading a clock).
const FRAME := 1.0 / 60.0
## The npc this hero forms the bond with. An authored cast member, never a literal def, so a
## reader can open the file and see the person (ADR 0074).
const ELDER := &"elder_wei"
## A lineage the mother's own ledger carries, so the birth has a purity to inherit and the
## assertion is on a NUMBER rather than on a present/absent key.
const LINEAGE := &"tideborn"
## A roll of 0.0 against any positive conception chance always conceives, so the attempt is
## a deterministic function of the ledger rather than of a draw.
const WINNING_ROLL := 0.0
## A generous upper bound on the mounted frames a birth may take.
##
## `FertilityApi._gestation_step` divides by an authored gestation length in DAYS and
## `StatusLoop` converts a frame to a day at `SECONDS_PER_GESTATION_DAY_TURN = 1.0`, so a
## raceless 30-day pregnancy at the boot hero's `gestation_speed` of 1.26 needs about
## 1429 frames of gestation, plus one frame each for the CONCEIVED -> GESTATING and
## GESTATING -> LABOR transitions. Deliberately well above that arithmetic rather than equal
## to it, so a content retune that lengthens a pregnancy cannot turn this suite red on a frame
## count. Bounded on purpose: `FertilityApi.advance` neither loops nor grows per call, so a
## budget this size cannot hang.
const BIRTH_FRAMES := 5000

var _harness: SeamHarness = null
var _app: ItemWorkbenchApp = null
## Children this suite minted, so teardown can break the provider refcount cycle the way
## `test_lineage_birth_wiring` does (INC-0021: anything instantiated in a test is freed).
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
	# The seams are process-wide statics on the module, so leaving them bound would leak
	# into whichever suite boots next. `KinshipApp.uninstall` restores the unbound state
	# exactly, which is what a teardown asserting the unbound case depends on.
	KinshipApp.uninstall()
	_clear_disk()


# --- 0. The production install ------------------------------------------------------


## ## The ONE line that makes either half of this gap real
##
## `npc_boot.install` calls `KinshipApp.install`, and that call is what binds the four
## seams. Delete the line and every case below fails at its FIRST assertion — which is the
## point: the wiring is the thing under test, not a fixture.
func test_the_production_install_binds_the_seams() -> void:
	assert_eq(
		KinshipApp.installed(),
		true,
		"the mounted root's own boot install bound every personal-cause seam"
	)


## A build that installs nothing must say so BY NAME rather than degrading quietly.
##
## This is the half that makes the case above meaningful: an install that reported success
## while binding nothing would pass [method test_the_production_install_binds_the_seams] and
## fail every verb underneath. `SocialFavourApp.uninstall` exists precisely so a suite can
## state "nothing bound" explicitly rather than trusting a default.
## ## The unbound state is asserted on the SEAM REPORT, not on a verb
##
## The first draft drove `teach` and expected `no_resolver`, and it was wrong: `SocialFavour`
## asks "is the manual carried?" BEFORE it asks "is the teacher bound?", so a hero with no
## manual is refused `not_carried` while every seam is unbound. Both answers are CORRECT and
## they answer different questions — a player outcome and a wiring gap — so driving a verb
## here would have been asserting an ordering that is not the contract. The seam report is
## what actually distinguishes the two states, and `SocialFavour` names its own four.
func test_a_boot_with_nothing_installed_says_so_by_name() -> void:
	var hero := _hero()
	assert_ne(hero, null, "the mounted root holds a hero")
	if hero == null:
		return
	KinshipApp.uninstall()
	assert_eq(KinshipApp.installed(), false, "and with nothing bound the report answers false")
	# Every one of the four seams reports itself false BY NAME, so a probe can tell which
	# wire is missing rather than inferring it from a verb that refused for another reason.
	var seams := SocialFavour.seams_installed()
	for seam in ["key_resolver", "debt_reader", "mercy_probe", "teacher"]:
		assert_eq(
			bool(seams.get(seam, true)),
			false,
			"the '%s' seam reports itself unbound rather than degrading quietly" % seam
		)
	# The COMBAT seam is a DIFFERENT seam, installed by `CombatBoot` and not owned by
	# `SocialFavourApp.uninstall` — so it stays bound across this teardown, and asserting it
	# unbound would assert a seam no uninstall in this file is responsible for. What is
	# honestly claimable is the seam this module DOES degrade on: with `mercy_probe` gone the
	# mercy route reports the WIRING gap rather than pressing a mercy it cannot verify.
	# `fight_alongside` asks `CombatMercy.installed` first, so that guard is what a caller
	# sees — and it is `KinshipApp`'s own, which is why the name is asserted here.
	assert_eq(
		CombatMercy.installed(),
		true,
		"the combat seam belongs to CombatBoot and is deliberately untouched by our uninstall"
	)
	# The DEEPER claim: the component itself, with no probe bound, refuses `no_resolver`
	# rather than falling through to a cause it cannot verify. That is `SocialFavour`'s own
	# gate and is what keeps an unbound build from minting a mercy.
	var probed: Variant = SocialFavour.seams_installed().get("mercy_probe", true)
	assert_eq(bool(probed), false, "and the mercy PROBE this module owns is genuinely unbound")
	KinshipApp.install()
	assert_eq(KinshipApp.installed(), true, "and reinstalling restores every seam")


# --- 1. RAISE THE FLOOR FROM A PLAYER ACTION ---------------------------------------


## ## THE CLAIM: two presses of ONE verb clear the floor, and `apply_cause` is never called
##
## `helped_in_combat` (3.0) then `spared_in_combat` (4.0) is 7.0 against a 6.0 floor. The
## mercy is VERIFIED rather than trusted — `SocialFavour` refuses `no_fight` unless the bond
## already carries the fight — so the route is two honest acts rather than one flag.
func test_a_player_action_pair_raises_a_personal_bond_above_the_floor() -> void:
	var hero := _hero()
	assert_ne(hero, null, "the mounted root holds a hero")
	if hero == null:
		return
	var elder := _elder()
	assert_ne(elder, null, "and the roster holds an individual to act towards")
	if elder == null:
		return
	# The floor is genuinely shut to begin with. Asserted rather than assumed, because a
	# suite that began with the gate already open would prove nothing.
	assert_eq(
		Seduction.can_meet(hero, elder),
		false,
		"a stranger does not clear the social floor — the gate starts shut"
	)
	assert_eq(
		float(SocialApi.bond_entry(hero, elder.id).get("standing", 0.0)),
		0.0,
		"and no personal bond row exists yet, so nothing has been authored standing"
	)

	# ## BEAT ONE: the player fought beside them. `helped_in_combat`, +3.0.
	var helped := KinshipApp.fight_alongside(hero, ELDER, false)
	assert_eq(bool(helped.get("ok", false)), true, "the fight settled as a player action")
	assert_eq(
		String(helped.get("cause", "")), "helped_in_combat", "and it recorded the authored cause"
	)
	# The MIRROR is the module's own contract (ADR 0091): one act writes both ledgers. This
	# is asserted because a one-sided write would leave the partner's regard disagreeing with
	# the player's, which is the exact defect `apply_cause`'s docstring warns about.
	assert_eq(
		_actor_key_standing(hero, elder),
		3.0,
		"the player's row carries the authored 3.0 under the ENGINE id can_meet reads"
	)
	assert_eq(
		Seduction.can_meet(hero, elder),
		false,
		"3.0 is still short of the 6.0 floor, so the gate has NOT opened yet"
	)

	# ## BEAT TWO: the player let them walk. `spared_in_combat`, +4.0. Total 7.0.
	var spared := KinshipApp.fight_alongside(hero, ELDER, true)
	assert_eq(
		bool(spared.get("ok", false)),
		true,
		"the mercy settled as a player action — the bound probe found a live opponent"
	)
	assert_eq(
		String(spared.get("cause", "")), "spared_in_combat", "and it recorded the authored cause"
	)
	assert_eq(
		_actor_key_standing(hero, elder),
		7.0,
		"the player's row is now the authored sum 3.0 + 4.0 = 7.0, ABOVE the 6.0 floor"
	)
	# ## THE GATE OPENS. This is the assertion the whole task turns on.
	assert_eq(
		Seduction.can_meet(hero, elder),
		true,
		"can_meet is TRUE — the social floor a player action can clear is no longer a wall"
	)
	# And the app-level read model agrees with the module, because a panel greys its control
	# out against THAT row rather than against the module's verdict.
	var read := KinshipApp.read_conception(hero, ELDER)
	assert_eq(bool(read.get("ok", false)), true, "the app read model agrees the gate is open")
	assert_eq(float(read.get("standing", 0.0)), 7.0, "and it publishes the same standing")
	# BOTH keys are on file and both agree, because they are two keys onto ONE bond. The
	# def-keyed row is what the rest of the game reads; the actor-keyed row is what the
	# lineage producer gates on. A pair filed under only one is sworn, mirrored, saved and
	# printed, and still cannot open the thing it was written to open.
	assert_eq(
		_actor_key_standing(hero, elder),
		float(SocialApi.bond_entry(hero, BrotherhoodOath.bond_key(elder)).get("standing", 0.0)),
		"the engine-id row and the roster-def-id row agree, so one act is one act"
	)


## The mercy is VERIFIED, not trusted: a caller cannot mint the larger cause by setting a
## flag, because the component reads its OWN cause ledger first.
##
## This is the anti-farm rule the route above rests on, and asserting it here is what makes
## the 7.0 route an honest one rather than a flag a player sets.
func test_a_mercy_cannot_be_minted_for_a_partner_the_player_never_fought() -> void:
	var hero := _hero()
	assert_ne(hero, null, "the mounted root holds a hero")
	if hero == null:
		return
	var elder := _elder()
	assert_ne(elder, null, "and the roster holds an individual to act towards")
	if elder == null:
		return
	var answered := KinshipApp.fight_alongside(hero, ELDER, true)
	assert_eq(bool(answered.get("ok", false)), false, "a mercy with no fight behind it is refused")
	assert_eq(
		String(answered.get("reason", "")),
		KinshipApp.R_MISSING_HISTORY,
		"and it names the missing history rather than reporting a wiring gap as an outcome"
	)
	assert_eq(
		_actor_key_standing(hero, elder),
		0.0,
		"so nothing was written — a refused verb moves no ledger (ADR 0044)"
	)


# --- 2. THE WHOLE PATH: FLOOR -> GATE -> PREGNANCY -> GESTATION -> CHILD -------------


## ## THE ACCEPTANCE TRACE, end to end, from a player action
##
## Floor raised -> gate opens -> conception attempted -> gestation advanced on the mounted
## clock -> child registered with a race and an inherited bloodline. No `apply_cause`, no
## direct `FertilityApi.try_conceive`, and no direct `Seduction.attempt`.
func test_a_player_action_carries_a_bond_past_the_floor_to_a_born_child() -> void:
	var hero := _hero()
	assert_ne(hero, null, "the mounted root holds a hero")
	if hero == null:
		return
	var elder := _elder()
	assert_ne(elder, null, "and the roster holds an individual to act towards")
	if elder == null:
		return
	# A lineage on the mother's OWN ledger, so the child's inherited purity is a number this
	# suite can assert rather than a presence it can only observe.
	BloodlineApi.set_purity(hero, LINEAGE, 1.0)
	var mother_carried := float(BloodlineApi.purity_of(hero, LINEAGE))
	assert_almost_eq(
		mother_carried, 1.0, "the mother's ledger carries the lineage at full concentration"
	)

	# ## STEP 1 — BEFORE. The whole downstream is shut, and each refusal names itself.
	assert_eq(Seduction.can_meet(hero, elder), false, "STEP 1 before: the floor is shut")
	var before := KinshipApp.read_conception(hero, ELDER)
	assert_eq(bool(before.get("ok", false)), false, "and the read model says so")
	assert_eq(
		float(before.get("standing", 0.0)),
		0.0,
		"at zero standing, because no personal cause has been applied to this pair"
	)
	assert_eq(
		float(before.get("chance", -1.0)),
		0.0,
		"and chance reads 0.0 — the producer will not roll a roll it has already refused"
	)
	var refused := KinshipApp.attempt_conception(hero, ELDER, WINNING_ROLL)
	assert_eq(bool(refused.get("ok", false)), false, "so an attempt before the floor is refused")
	assert_eq(
		String(refused.get("reason", "")), Seduction.R_NO_BOND, "naming the social floor by name"
	)
	assert_eq(
		FertilityApi.pregnancy(hero), null, "and a refused attempt writes no pregnancy (ADR 0044)"
	)

	# ## STEP 2 — THE PLAYER ACTIONS. Two presses of ONE verb, and nothing else.
	assert_eq(
		bool(KinshipApp.fight_alongside(hero, ELDER, false).get("ok", false)),
		true,
		"STEP 2: the fight settled"
	)
	assert_eq(
		bool(KinshipApp.fight_alongside(hero, ELDER, true).get("ok", false)),
		true,
		"STEP 2: the mercy settled"
	)

	# ## STEP 3 — AFTER. The gate opened, and the odds became answerable.
	assert_eq(Seduction.can_meet(hero, elder), true, "STEP 3 after: can_meet is TRUE")
	var after := KinshipApp.read_conception(hero, ELDER)
	assert_eq(bool(after.get("ok", false)), true, "and the app read model agrees")
	assert_eq(float(after.get("standing", 0.0)), 7.0, "at the authored 7.0")
	assert_eq(
		float(after.get("chance", 0.0)) > 0.0,
		true,
		"and chance is now a positive number, which is what a panel's odds line reads"
	)

	# ## STEP 4 — THE ATTEMPT. Through the app verb, which is the one caller of `Seduction.attempt`.
	var conceived := KinshipApp.attempt_conception(hero, ELDER, WINNING_ROLL)
	assert_eq(bool(conceived.get("ok", false)), true, "STEP 4: the conception attempt succeeded")
	assert_eq(String(conceived.get("reason", "")), "", "with no refusal to report")
	assert_eq(
		bool(conceived.get("pregnant", false)), true, "and the hero now carries the pregnancy"
	)
	var pregnancy := FertilityApi.pregnancy(hero)
	assert_ne(pregnancy, null, "the status machine holds a PregnancyStatus")
	if pregnancy == null:
		return
	# ## ADR 0108: the lineage inputs are SNAPSHOT AT CONCEPTION. Asserted here because the
	# whole point of the snapshot is that it cannot be rewritten later — and the assertion that
	## would catch a regression is that the status carries the PARTNER's own capture.
	assert_eq(
		String(pregnancy.partner_id),
		String(elder.id),
		"the status captured the partner's ENGINE id at conception, which is the snapshot"
	)
	assert_eq(
		String(pregnancy.species_id),
		String(RaceApi.race_of(hero)),
		"and the mother's own race, captured rather than re-read at birth"
	)

	# ## STEP 5 — GESTATION. The MOUNTED root's own frame callback, never StatusLoop.tick.
	var row := _drive_until_a_birth_is_registered()
	assert_eq(
		bool(row.is_empty()), false, "STEP 5: mounted frames drove a birth the app registered"
	)
	if row.is_empty():
		return
	var child := _child_from_row(row)
	assert_ne(child, null, "the registered birth names a child the app retained")
	if child == null:
		return

	# ## STEP 6 — THE CHILD, with a resolved race and an INHERITED bloodline.
	assert_ne(
		String(RaceApi.race_of(child)),
		"",
		"STEP 6: the child carries a race id, so the birth resolved a body plan"
	)
	assert_eq(
		String(RaceApi.race_of(child)),
		String(row.get("race", "")),
		"and the registry's race is the one RaceApi reads off the child itself"
	)
	# The purity is INHERITED, so it is the blend of both parents rather than either one —
	# and it is read back off the child through the module that owns it, not copied out of
	# the status the registry was written from.
	var inherited := float(BloodlineApi.purity_of(child, LINEAGE))
	assert_eq(
		inherited > 0.0,
		true,
		"the child INHERITED the lineage the mother carried — it is not absent, and not a copy"
	)
	assert_eq(
		inherited < mother_carried,
		true,
		"and it is DILUTED below the mother's concentration, which is ADR 0063's blend"
	)
	var lineage_row := row.get("lineages", {}) as Dictionary
	if lineage_row.has(String(LINEAGE)):
		assert_almost_eq(
			inherited,
			float(lineage_row[String(LINEAGE)]),
			"and where the registry published the line, it published the child's own number"
		)
	# ## ADR 0108, second half: a newborn is born into NO house. Admission is a gate with its
	# own rules (ADR 0064), and a birth is not one.
	assert_eq(
		String(ClanApi.state(child).get("clan", "")),
		"",
		"and the child is born into no clan — admission stays an explicit gate"
	)


## ## Every cause the kinship path can apply is AUTHORED
##
## `SocialApi.apply_cause` answers `unknown_cause` for an id the catalog does not ship, and a
## bridge built on unauthored vocabulary refuses at PLAY time — the inert-vocabulary defect in
## its worst form: the code reads correct and the feature never fires. Pinning the ids here
## makes such a bridge fail at TEST time.
func test_every_cause_the_kinship_verbs_apply_is_authored() -> void:
	var catalog := SocialCauseCatalog.instance()
	for cause_id in KinshipApp.cause_ids():
		assert_ne(
			catalog.cause_definition(cause_id),
			null,
			"'%s' is applied by a KinshipApp verb and must exist in the catalog" % String(cause_id)
		)
	for cause_id in KinshipApp.conception_cause_ids():
		assert_ne(
			catalog.cause_definition(cause_id),
			null,
			(
				"'%s' is recorded on success by the lineage producer and must be authored"
				% String(cause_id)
			)
		)
	# ## And the floor is cleared by an AUTHORED sum, not by one invented cause.
	#
	# Read off the catalog rather than restated, so a content retune that moves a magnitude
	# turns this red and the task's "6.0 must stay reachable" claim stays MEASURED rather than
	# asserted. This is the assertion that would fail if the only route to 6.0 were rescaled.
	var fight_route := float(
		(
			catalog.cause_definition(&"helped_in_combat").standing
			+ catalog.cause_definition(&"spared_in_combat").standing
		)
	)
	assert_eq(
		fight_route > Seduction.REQUIRED_STANDING,
		true,
		(
			(
				"the two-press fight route (%s) is above the floor (%s), so 6.0 is reachable with "
				+ "authored magnitudes and the threshold was never lowered to fake it"
			)
			% [str(fight_route), str(Seduction.REQUIRED_STANDING)]
		)
	)


## ## `Seduction.attempt` has a production caller NOW, and exactly one
##
## The measurement the task turns on, as a fact about the TREE rather than about one test: a
## scan of `res://src/` for `Seduction.attempt` must find the app verb and nothing else. A
## second caller would mean two places deciding who may conceive, which is a second
## authority over the one gate the module owns.
func test_seduction_attempt_has_exactly_one_production_caller() -> void:
	var callers: Array[String] = []
	for path in ContentScan.files_under("res://src/", ".gd"):
		var text := FileAccess.get_file_as_string(path)
		if text.contains("Seduction.attempt("):
			callers.append(path)
	assert_eq(
		callers.size(),
		1,
		"exactly one production site calls the lineage producer. Found: %s" % str(callers)
	)
	assert_eq(
		callers[0],
		"res://src/app/kinship_app.gd",
		"which is the app verb — not a facade nobody reaches, and not a test"
	)


# --- Internals ----------------------------------------------------------------------


## The mounted root's OWN actor.
##
## The explicit `as Actor` cast is load-bearing, not decoration: `_app` is reached through the
## harness as a `Control`, so `actor()` comes back untyped, and this project treats a
## Variant-inferred `:=` as an ERROR (warnings are errors here).
func _hero() -> Actor:
	return _app.actor() as Actor


## A live cast member the hero can act towards, spawned through the shipped minter.
##
## `NpcApi.spawn` refuses an id the catalog does not ship, so this reaching `elder_wei` is
## itself a content fact rather than a fixture — and the spawned body carries the same
## provider spine every other actor gets.
func _elder() -> Actor:
	var hero := _hero()
	if hero == null:
		return null
	NpcBoot.install(hero)
	var elder := NpcApi.spawn(ELDER)
	if elder == null:
		return null
	SocialApi.attach(elder)
	ItemsApi.attach(elder)
	CombatMercy.install()
	return elder


## The personal standing the player holds under the ENGINE id — the row `Seduction.can_meet`
## gates on, which is why this is read through `partner.id` and not through `bond_key`.
func _actor_key_standing(hero: Actor, elder: Actor) -> float:
	return float(SocialApi.bond_entry(hero, elder.id).get("standing", 0.0))


## Drive the composition root's OWN frame callback, `frames` times, at the headless FRAME delta.
## The entry under test is `ItemWorkbenchApp._process`, never `StatusLoop.tick` or
## `FertilityApi.advance`, so a green run is evidence about production wiring.
func _frames(frames: int) -> void:
	var app := _harness.app
	assert_eq(app.has_method(&"_process"), true, "the composition root declares _process")
	if not app.has_method(&"_process"):
		return
	for frame in frames:
		app.call("_process", FRAME)


## Drive MOUNTED frames until the app's registry holds a birth, and return that first row.
##
## The registry is read through the app's own `_born` field. Stepping frame by frame and
## stopping at the first registered row rather than driving a fixed high count and hoping: a
## birth is a one-shot event and the frame it lands on depends on the authored gestation,
## which content may retune. Returns an EMPTY dictionary when no birth registered within the
## frame budget, so a caller can assert on `row.is_empty()` and bail rather than dereference
## nothing.
func _drive_until_a_birth_is_registered() -> Dictionary:
	var app := _harness.app
	assert_eq(app.has_method(&"_process"), true, "the composition root declares _process")
	if not app.has_method(&"_process"):
		return {}
	var guard := 0
	# Snapshot the bound BEFORE the loop: `test_no_unbounded_wait` requires a real terminating
	# guard, and the budget is the authored constant BIRTH_FRAMES rather than anything that
	# grows with the loop.
	while guard < BIRTH_FRAMES:
		app.call("_process", FRAME)
		guard += 1
		_capture_live_children()
		var born: Dictionary = app.get("_born") as Dictionary
		if not born.is_empty():
			var first: Dictionary = born.values()[0] as Dictionary
			return first
	return {}


## Take a reference to every child the mounted hero's pregnancy is currently holding.
## Idempotent, and the only place `_children` is written — so `teardown` frees exactly what
## this suite minted.
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
## The app's row is PRIMITIVES and deliberately does not carry the actor: `app/` records what
## a birth WAS, not a second reference to a body another module owns. The live `Actor` is
## therefore captured at the birth frame and matched here by the id the registry recorded.
##
## It deliberately does NOT walk the mother's `PregnancyStatus.offspring` list. That list is
## erased roughly ten seconds after the birth, so a lookup through it would pass while testing
## nothing. If no child was captured, the child really was dropped and this returns null.
func _child_from_row(row: Dictionary) -> Actor:
	var child_id := StringName(String(row.get("actor_id", "")))
	if child_id == &"":
		return null
	for body in _children:
		var actor := body as Actor
		if actor != null and actor.id == child_id:
			return actor
	return null


func _clear_disk() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SavePaths.DIR):
		DirAccess.remove_absolute(SavePaths.DIR)
