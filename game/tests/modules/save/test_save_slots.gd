extends TestCase

## NAMED SAVE SLOTS AS PARALLEL JOURNEYS (ADR 0903).
##
## The roster is fixed — primary plus first/second/third — the autosave keeps
## writing whoever is live, and each slot rotates through its own files. Every
## case below writes the real `user://save` directory and removes it first, so
## a previous run's generation cannot make an assertion pass for the wrong
## reason. The live slot is reset to primary on both sides of every case: it
## is process-wide static, so a slot set here is read by whichever suite
## boots next.
##
## What is NOT covered here: the menu that lists these slots (its own suite
## drives the screen), and loading a slot into a live root (the composition
## root owns that adoption).

var _born: Array = []


func setup() -> void:
	_clear_disk()
	SaveApi.set_live_slot(&"primary")


func teardown() -> void:
	_clear_disk()
	SaveApi.set_live_slot(&"primary")
	for born in _born:
		(born as Actor).resources.clear()
	_born.clear()


func _hero_named(actor_id: StringName) -> Actor:
	var actor := Actor.new(actor_id)
	actor.display_name = "Slot Hero"
	_born.append(actor)
	return actor


func _clear_disk() -> void:
	for slot in SaveApi.slots():
		var paths := SavePaths.for_slot(StringName(slot))
		for key in ["primary", "backup", "temp"]:
			var path := String(paths[key])
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


# --- The roster -----------------------------------------------------------------


func test_the_roster_is_fixed_and_primary_stays_first() -> void:
	var slots := SaveApi.slots()
	assert_eq(slots, ["primary", "first", "second", "third"], "four slots, no more")
	assert_eq(SaveApi.live_slot(), &"primary", "and the live one starts on primary")


func test_an_unknown_slot_is_refused_by_name() -> void:
	assert_eq(SavePaths.is_slot(&"nowhere"), false, "nowhere is not a slot")
	var erased := SaveApi.erase(&"nowhere")
	assert_eq(bool(erased["ok"]), false, "so erasing it goes nowhere")
	assert_eq(String(erased["reason"]), "unknown_slot", "and says so by name")
	var summary := SaveApi.slot_summary(&"nowhere")
	assert_eq(bool(summary["exists"]), false, "and it is reported empty")
	assert_eq(String(summary["reason"]), "unknown_slot", "for the same named reason")


# --- Isolation ------------------------------------------------------------------


func test_a_named_slot_writes_beside_primary_not_over_it() -> void:
	var hero := _hero_named(&"slot_hero")
	assert_eq(bool(SaveApi.persist(hero, "standard", &"first")["ok"]), true, "the slot save landed")
	assert_eq(SaveApi.exists(&"first"), true, "and the slot reads back")
	assert_eq(SaveApi.exists(), false, "while primary was never written")
	var summary := SaveApi.slot_summary(&"first")
	assert_eq(bool(summary["exists"]), true, "so the menu lists it")
	assert_eq(String(summary["actor_id"]), "slot_hero", "under the hero who wrote it")
	assert_eq(String(summary["display_name"]), "Slot Hero", "by the name they carry")


func test_each_slot_rotates_through_its_own_backup() -> void:
	var hero := _hero_named(&"rotating_hero")
	assert_eq(
		bool(SaveApi.persist(hero, "standard", &"second")["ok"]), true, "generation one landed"
	)
	assert_eq(
		bool(SaveApi.persist(hero, "standard", &"second")["ok"]), true, "generation two landed"
	)
	var paths := SavePaths.for_slot(&"second")
	assert_eq(FileAccess.file_exists(String(paths["backup"])), true, "the slot kept its own backup")
	assert_eq(SaveApi.exists(), false, "and primary still holds nothing")


func test_generations_do_not_leak_across_slots() -> void:
	var hero := _hero_named(&"counting_hero")
	SaveApi.persist(hero, "standard", &"first")
	SaveApi.persist(hero, "standard", &"first")
	SaveApi.persist(hero, "standard", &"third")
	assert_eq(int(SaveApi.slot_summary(&"first")["generation"]), 2, "first is on two")
	assert_eq(int(SaveApi.slot_summary(&"third")["generation"]), 1, "third is on one")


# --- The live slot ----------------------------------------------------------------


func test_the_autosave_follows_whoever_is_live() -> void:
	var hero := _hero_named(&"live_hero")
	assert_eq(bool(SaveApi.set_live_slot(&"second")["ok"]), true, "the root moves live")
	SaveApi.persist(hero, "standard")
	assert_eq(SaveApi.exists(&"second"), true, "so the default write lands on second")
	assert_eq(SaveApi.exists(&"primary"), false, "and primary stays empty")
	assert_eq(SaveApi.exists(), true, "because exists() without a slot means the live one")


func test_setting_an_unknown_slot_live_is_refused() -> void:
	var verdict := SaveApi.set_live_slot(&"nowhere")
	assert_eq(bool(verdict["ok"]), false, "nowhere cannot go live")
	assert_eq(String(verdict["reason"]), "unknown_slot", "by name")
	assert_eq(SaveApi.live_slot(), &"primary", "so live never moved")


# --- Forgetting ---------------------------------------------------------------------


func test_erasing_a_slot_empties_it_and_leaves_the_others() -> void:
	var hero := _hero_named(&"forgotten_hero")
	SaveApi.persist(hero, "standard", &"first")
	SaveApi.persist(hero, "standard", &"second")
	var erased := SaveApi.erase(&"first")
	assert_eq(bool(erased["ok"]), true, "the erase ran")
	assert_eq(bool(erased["erased"]), true, "and removed files")
	assert_eq(SaveApi.exists(&"first"), false, "so first reads empty")
	assert_eq(SaveApi.exists(&"second"), true, "while second is untouched")


func test_erasing_an_empty_slot_is_a_no_op_not_a_failure() -> void:
	var erased := SaveApi.erase(&"third")
	assert_eq(bool(erased["ok"]), true, "nothing to remove is still ok")
	assert_eq(bool(erased["erased"]), false, "and says so")


func test_the_live_journey_cannot_be_erased_from_under_itself() -> void:
	var hero := _hero_named(&"living_hero")
	SaveApi.persist(hero, "standard", &"second")
	SaveApi.set_live_slot(&"second")
	var erased := SaveApi.erase(&"second")
	assert_eq(bool(erased["ok"]), false, "the live slot refuses")
	assert_eq(String(erased["reason"]), "live_erase_refused", "by name")
	assert_eq(SaveApi.exists(&"second"), true, "and the journey survives")
