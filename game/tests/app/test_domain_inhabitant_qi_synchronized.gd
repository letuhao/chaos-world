extends TestCase

## BL-0753, the sibling of BL-0696: a domain inhabitant whose def declares `cultivates`
## was given a `PathState` and NOTHING behind it.
##
## `DomainSpawner._enrol_cultivator` was one line — `actor.set_path(...)` — and
## `ActorFactory.spawn_inhabitant` (the minter `DomainBoot.install()` wires) called
## `build()` + `SocialApi.attach` + `_refresh_element_realm` and never `_attach_qi`. So
## `QiCultivationApi.attach` was unreachable from this construction path, and a domain
## rival got no dantian, no `QiProvider`, no `QiTraining.synchronize` and no meridian
## unlock: `QiTraining.cultivate` refused, `QiBreakthroughCondition.can_breakthrough`
## refused, and `QiBreakthroughTransaction.preview` answered `no_dantian`
## (`breakthrough_transaction.gd:43`). Six of the nine shipped species declare
## `cultivates = true`, and `RealmScaling.apply` scaled them by realm anyway
## (`domain_spawner.gd:100`) — a realm-scaled boss labelled a cultivator that could not
## cultivate.
##
## Everything here goes through the REAL production wiring (`DomainBoot.install()`), not
## a hand-built fixture. That is deliberate: half the defect was a missing call in
## `DomainBoot.install`, and a fixture that set the enroller up by hand would have stayed
## green through it.
##
## `spirit_transformation` (the Flame Dragon, the highest realm any shipped cultivator
## names) is the realm every assertion is made at, because it disagrees with the
## defaults a bare `attach` leaves: `dantian_capacity = 200.0` against the reservoir's
## flat `100.0`, and a full tier of meridian unlocks against an empty network. Its
## `dantian_tier` is `lower`, which the component default also is, so tier cannot
## discriminate here — capacity, pool ceiling, meridian count and the preview can.

const INHABITANT_DIR := "res://src/data/domains/inhabitants"
const REALM := &"spirit_transformation"
const DRAGON := "flame_dragon"


## ## Why `setup` names the two seams instead of calling `DomainBoot.install()`
## Because `DomainBoot` is a single script and a peer editing any line of it can leave the
## WHOLE file unparseable, which would make this suite report red for a reason that has
## nothing to do with the claim under test. The wiring itself is pinned separately, by
## [method test_the_boot_installs_the_enrolment_contact], which reads the source TEXT and
## so cannot be broken by a parse error anywhere else.
func setup() -> void:
	DomainSpawner.set_minter(ActorFactory.spawn_inhabitant, ActorFactory.enrol_inhabitant_qi)


func teardown() -> void:
	# The runner calls this after EVERY test and both seams are process-wide static
	# state: left installed they leak into whatever suite runs next.
	DomainSpawner.set_minter(Callable())
	DomainFixtures.set_minter(Callable(), Callable())


## The shipped Flame Dragon, minted exactly as a room places one. Nothing below attaches,
## synchronizes or seeds anything by hand, so a failure cannot be blamed on an
## under-provisioned actor.
func _dragon() -> Actor:
	return DomainSpawner.spawn(
		load("%s/%s.tres" % [INHABITANT_DIR, DRAGON]) as InhabitantDef, &"boss"
	)


func _qi_providers(actor: Actor) -> int:
	var count := 0
	for entry in actor.stats._providers:
		if entry is QiProvider:
			count += 1
	return count


## The four things `QiTraining.synchronize` owns (`training.gd:10-28`) plus the rig
## `attach` mounts. Every value is read off the realm's OWN seed rather than pasted, so a
## retuned realm is a named failure and not a silently-passing constant.
func test_a_shipped_cultivating_species_carries_a_qi_rig() -> void:
	var actor := _dragon()
	assert_ne(actor, null, "the authored def spawns")
	if actor == null:
		return
	var state := actor.path(QiPath.PATH_ID)
	assert_ne(state, null, "and it is on the qi path")
	if state == null:
		return
	assert_eq(String(state.rank_id), String(REALM), "at the realm its def authors")

	var seed := QiRealmSeed.for_realm(REALM)
	assert_ne(seed, null, "and that realm publishes a qi seed to synchronize against")
	var dantian := QiAccess.dantian(actor)
	assert_ne(dantian, null, "a dantian: the vessel every qi verb refuses without")
	if seed == null or dantian == null:
		return

	# Capacity comes from the seed scaled by the meridian network's own bonus, so the two
	# halves move together and an UNSYNCHRONIZED actor has the wrong one by construction:
	# it reports the base stat the component was minted with.
	var expected_capacity: float = (
		seed.dantian_capacity * (1.0 + actor.meridians.get_capacity_bonus())
	)
	assert_almost_eq(
		dantian.structural_capacity,
		expected_capacity,
		"the dantian is sized by synchronize from the realm seed, not from the base stat"
	)
	assert_eq(dantian.tier, seed.dantian_tier, "and carries the realm's dantian tier")
	# `training.gd:27` caps the reservoir at the dantian's effective capacity, so a
	# dantian sized right with a pool left at `attach`'s flat 100.0 is still a path that
	# cannot hold what its vessel can.
	assert_almost_eq(
		actor.resource(QiStats.QI).maximum,
		dantian.effective_capacity(),
		"the qi reservoir is capped to the dantian synchronize sized"
	)
	assert_eq(_qi_providers(actor), 1, "and exactly one qi provider, not an appended pair")
	assert_ne(QiAccess.provider(actor), null, "which is the provider the qi stats are read through")


## The unlocks, counted from `unlock_for_realm`'s OWN rule (`tier <= realm index`) rather
## than pasted, so a retuned meridian ladder is a named failure. `for` over the fixed 20
## `MeridianDefaults` appending into a counter the body does not grow — no `while` on a
## container this loop enlarges.
func test_a_shipped_cultivating_species_unlocks_its_realm_channels() -> void:
	var actor := _dragon()
	if actor == null:
		return
	var realm_index := RealmDefaults.ladder().index_of(REALM)
	var expected := 0
	for def in MeridianDefaults.all():
		if def.tier <= realm_index:
			expected += 1
	assert_eq(
		actor.meridians.get_all_meridians().size(),
		expected,
		"every meridian the realm unlocks is on the network"
	)
	var seed := QiRealmSeed.for_realm(REALM)
	if seed == null:
		return
	for meridian_id in seed.required_meridians:
		assert_ne(
			actor.meridians.get_meridian(meridian_id),
			null,
			"the channel %s the realm's gate names exists" % meridian_id
		)


## The player-visible consequence, and the assertion that would have been `no_dantian`
## before the fix. A preview that answers `no_dantian` is the whole bug in one string.
func test_a_shipped_cultivating_species_previews_past_the_dantian() -> void:
	var actor := _dragon()
	if actor == null:
		return
	var unmet: Array = QiBreakthroughTransaction.preview(actor).get("unmet_conditions", [])
	assert_eq(unmet.has("no_dantian"), false, "the preview no longer answers no_dantian")
	assert_eq(unmet.has("no_qi_path"), false, "and no longer answers no_qi_path")
	# It is still not ready — a fresh dragon owes progress, comprehension, a pill and a
	# full dantian. What changed is that the gate now answers with TRAINING owed rather
	# than with a vessel that does not exist.
	assert_eq(
		unmet.has("insufficient_progress"),
		true,
		"and owes the realm's progress, as a beginner must"
	)
	assert_eq(
		QiCultivationApi.cultivate(actor, QiCultivationApi.CULTIVATE_STEP), true, "so it can train"
	)


## Every shipped species, not one cherry-picked. A `for` over a directory listing bounded
## by the shipped files; nothing here grows the list it walks.
func test_every_shipped_cultivating_species_answers_with_a_rig() -> void:
	var checked := 0
	for file_name in _tres_files(INHABITANT_DIR):
		var def := load("%s/%s" % [INHABITANT_DIR, file_name]) as InhabitantDef
		if def == null or not def.cultivates:
			continue
		checked += 1
		var actor := DomainSpawner.spawn(def, &"miniboss")
		assert_ne(actor, null, "'%s' spawns" % file_name)
		if actor == null:
			continue
		assert_ne(
			QiAccess.dantian(actor),
			null,
			"'%s' declares it cultivates, so it HAS a dantian" % file_name
		)
		assert_ne(actor.resource(QiStats.QI), null, "'%s' carries a qi reservoir" % file_name)
		assert_ne(
			actor.meridians.get_all_meridians().size(), 0, "'%s' has unlocked channels" % file_name
		)
	assert_eq(checked, 6, "all six shipped species that declare cultivates were checked")


## The authored decision still gates, and nothing leaked into the mobs. `cinder_hound`
## declares `cultivates = false`, so the 3-argument enrolment shape must never be reached
## for it — an unconditional `_attach_qi` in `spawn_inhabitant` would give a rat a dantian,
## which is the reason the enrolment is a separate call at all.
func test_a_mob_that_does_not_cultivate_still_gets_nothing() -> void:
	var def := load("%s/cinder_hound.tres" % INHABITANT_DIR) as InhabitantDef
	assert_ne(def, null, "the authored mob def loads")
	if def == null:
		return
	assert_eq(def.cultivates, false, "and it declares it does not cultivate")
	var actor := DomainSpawner.spawn(def, &"mob")
	assert_ne(actor, null, "so it still spawns")
	if actor == null:
		return
	assert_eq(actor.path(QiPath.PATH_ID), null, "with no qi path")
	assert_eq(QiAccess.dantian(actor), null, "and no dantian")
	assert_eq(actor.resource(QiStats.QI), null, "and no reservoir to spend")
	assert_eq(_qi_providers(actor), 0, "and no qi provider")


## Two instances of the SAME def, because the double-apply risk is real and unguarded:
## `QiCultivationApi.attach` appends a `QiProvider` with no `is_connected`-style guard
## (`api.gd:32`), unlike `QiTraining.synchronize` (overwrites) and `attach_dantian`
## (returns the existing one). The 2-argument constructor call and the 3-argument
## enrolment call are both made per instance, and this asserts the rig is mounted once.
func test_each_instance_is_enrolled_exactly_once() -> void:
	var first := _dragon()
	var second := _dragon()
	assert_ne(first, null, "the first instance spawns")
	assert_ne(second, null, "the second instance spawns")
	if first == null or second == null:
		return
	assert_eq(_qi_providers(first), 1, "the first carries one qi provider")
	assert_eq(_qi_providers(second), 1, "and so does the second, minted from the same def")
	assert_ne(
		QiAccess.dantian(first),
		QiAccess.dantian(second),
		"each carries its OWN dantian, not a component shared through the loaded .tres"
	)


## The wiring, asserted as SOURCE rather than by calling it. Half of BL-0753 was a missing
## argument at the install site, and a suite that installed the seam itself would have
## stayed green through exactly that. Reading the text also means a parse error anywhere
## in `domain_boot.gd` — a peer's in-flight edit, say — cannot be charged to this claim.
func test_the_boot_installs_the_enrolment_contact() -> void:
	var source := FileAccess.get_file_as_string("res://src/app/domain_boot.gd")
	assert_eq(source.is_empty(), false, "the boot file is readable")
	if source.is_empty():
		return
	assert_eq(
		source.contains("DomainSpawner.set_minter("), true, "the boot installs the spawner seam"
	)
	assert_eq(
		source.contains("ActorFactory.enrol_inhabitant_qi"),
		true,
		"and installs the cultivation enroller with it — the call that closes BL-0753"
	)


## Directory listing of the shipped defs. `while entry != ""` is the `DirAccess`
## terminator, drained to exhaustion — the bound is the iterator's own empty entry, not a
## count this loop grows.
func _tres_files(dir_path: String) -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return names
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and not dir.current_is_dir() and entry.ends_with(".tres"):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names
