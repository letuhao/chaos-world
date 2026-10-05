extends TestCase

## The run ledger and the encounter ids must be able to name the same run (BL-0252).
##
## ## What used to disagree
##
## `active`, `rewards` and `claimed` are all keyed by [method LootState.encounter_id],
## which embeds the authored **band** and the **run**: `"<domain>/<boss>@<tier>#<run>"`.
## The run ledger was keyed by `domain_id` alone and held one `run` / `run_tier` /
## `cleared_tier` triple per domain. So the two structures disagreed the moment one
## domain had two bands in flight: entering the second band overwrote the first's
## ledger entry, and the first band's remaining bosses became **unreachable** — walking
## back in computed a run number its encounter ids no longer used, so the rest of that
## run could never be fought or paid.
##
## The fix keys the ledger per (domain, band), the same structure the ids embed, so the
## disagreement is no longer expressible. These suites prove it cannot come back.

const EMBER_DOMAIN := &"loot_ember_vault_domain"
const EMBER_LOW := 1
const EMBER_HIGH := 2
const SEED := 20260902


func _hero() -> Actor:
	var actor := Actor.new(&"delver", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor, 24)
	LootApi.attach(actor)
	return actor


func _ledger(actor: Actor) -> Dictionary:
	return LootApi.summary(actor)["runs"] as Dictionary


func _band_record(actor: Actor, tier: int) -> Dictionary:
	return _ledger(actor).get(LootState.run_key(String(EMBER_DOMAIN), tier), {}) as Dictionary


func _active(actor: Actor) -> Dictionary:
	return LootApi.summary(actor).get("active", {}) as Dictionary


## The whole world a run's existence is recorded in: the ledger and the ids that were
## actually minted against it.
func _truth(actor: Actor) -> Dictionary:
	var state := LootState.normalize(actor.get_module_data(LootState.MODULE_KEY))
	return {"runs": state["runs"], "rewards": (state["rewards"] as Dictionary).keys()}


func _enter(actor: Actor, tier: int) -> Dictionary:
	return LootApi.enter_domain(actor, EMBER_DOMAIN, tier, SEED)


## The defect, stated as the concrete sequence that produced it. Two bands of one domain,
## the second entered while the first is abandoned mid-run.
func test_two_bands_of_one_domain_keep_independent_runs() -> void:
	var actor := _hero()

	var low := _enter(actor, EMBER_LOW)
	assert_eq(bool(low["ok"]), true, "the low band opens")
	var low_run := int(low["run"])
	assert_eq(low_run, 1, "as run one")
	assert_eq(int(_active(actor).get("tier", -1)), EMBER_LOW, "with that band's boss live")
	assert_eq(
		bool(
			LootApi.strike(actor, float(_active(actor).get("vitality_max", 1.0)) * 10.0, SEED)["ok"]
		),
		true,
		"and its first boss is defeated, so that band is part-way through"
	)

	assert_eq(bool(LootApi.abandon(actor)["ok"]), true, "and it is abandoned")
	var high := _enter(actor, EMBER_HIGH)
	assert_eq(bool(high["ok"]), true, "the high band opens in the same domain")
	assert_eq(int(_active(actor).get("tier", -1)), EMBER_HIGH, "with its own boss live")
	var high_run := int(high["run"])
	assert_eq(high_run, 1, "as its own first run, not a continuation of the low band's")

	# The two bands now hold separate ledger entries. Under the old one-entry-per-domain
	# ledger the low band's record was gone at this point, and this assertion is what
	# says so.
	var ledger := _ledger(actor)
	assert_eq(ledger.size(), 2, "each band has its own ledger entry")
	assert_eq(
		ledger.has(LootState.run_key(String(EMBER_DOMAIN), EMBER_LOW)),
		true,
		"the abandoned low band is still recorded"
	)
	assert_eq(
		ledger.has(LootState.run_key(String(EMBER_DOMAIN), EMBER_HIGH)),
		true,
		"alongside the high band"
	)
	assert_eq(
		int(_band_record(actor, EMBER_LOW)["run"]),
		low_run,
		"and the low band's run number is untouched by the high band's entry"
	)

	# Walking back into the abandoned band RESUMES it (rule E4) rather than starting a new
	# run. THIS is the step that destroyed the low band's progress under the old ledger:
	# the resume check read one shared `run_tier`, which the high band's entry had already
	# overwritten, so the low band was judged not-in-flight and restarted under a fresh run
	# number — leaving the boss it had already paid for unreachable ever again.
	assert_eq(bool(LootApi.abandon(actor)["ok"]), true, "the high band is abandoned too")
	var resumed := _enter(actor, EMBER_LOW)
	assert_eq(bool(resumed["ok"]), true, "the low band is entered again")
	assert_eq(int(resumed["run"]), low_run, "resuming the same run, not minting a new one")
	assert_eq(
		int(_active(actor).get("boss_index", -1)),
		1,
		"at the next undefeated boss rather than restarting the band"
	)
	assert_eq(
		String(_active(actor).get("encounter_id", "")).ends_with("@%d#%d" % [EMBER_LOW, low_run]),
		true,
		"under ids carrying the band AND the run its defeated boss was paid under"
	)
	assert_eq(
		int(_band_record(actor, EMBER_HIGH)["run"]),
		high_run,
		"and the high band's own run number is still its own"
	)


## The rule that makes the resume sound: a resumed run keeps the encounter ids its
## already-defeated bosses were paid under. If the ids changed, the reward already minted
## would become orphaned and the rest of the run would restart.
func test_a_resumed_band_keeps_the_encounter_ids_its_defeated_bosses_were_paid_under() -> void:
	var actor := _hero()
	var opened := _enter(actor, EMBER_LOW)
	assert_eq(bool(opened["ok"]), true, "the low band opens")
	var first := String(_active(actor).get("encounter_id", ""))
	assert_eq(first.is_empty(), false, "the first boss has an id")
	assert_eq(
		bool(
			LootApi.strike(actor, float(_active(actor).get("vitality_max", 1.0)) * 10.0, SEED)["ok"]
		),
		true,
		"and is defeated"
	)
	var minted := String(LootApi.summary(actor)["rewards"][0]["encounter_id"])
	assert_eq(minted, first, "the payload is keyed by that id")

	LootApi.abandon(actor)
	_enter(actor, EMBER_HIGH)
	LootApi.abandon(actor)
	var again := _enter(actor, EMBER_LOW)
	assert_eq(bool(again["ok"]), true, "the low band is entered again")
	assert_eq(
		int(_active(actor).get("boss_index", -1)),
		1,
		"it resumes at the next undefeated boss rather than restarting the band"
	)
	assert_eq(int(LootApi.summary(actor)["reward_count"]), 1, "the earlier payload is still owed")

	# And the surviving id is still addressable, which is the property a changed run
	# number would have destroyed.
	assert_eq(
		bool(LootApi.reward(actor, first)["ok"]),
		true,
		"the earlier payload is still retrievable under its original id"
	)


## A refused entry writes nothing. `enter` used to write the ledger before it knew the
## entry would succeed, so its refusal paths described a counter that had already moved —
## a second structure disagreeing with the world. Both refusal branches that are reachable
## (`unknown_tier` and `already_in_domain`, which both return before any write) are
## asserted here. The third branch, a fully-claimed run, is **unreachable** —
## `resumes` implies `_run_in_flight` implies `_first_undefeated >= 0` — so it is left
## documented rather than asserted, because a test for it would pass for the wrong reason.
func test_a_refused_entry_does_not_move_the_run_counter() -> void:
	var actor := _hero()
	_enter(actor, EMBER_LOW)
	var run_before := int(_band_record(actor, EMBER_LOW)["run"])
	assert_eq(bool(LootApi.abandon(actor)["ok"]), true, "the band is abandoned")

	# An empty run name is refused before anything is written.
	var unknown := _enter(actor, 99)
	assert_eq(bool(unknown["ok"]), false, "an unauthored band is refused")
	assert_eq(String(unknown["reason"]), LootState.ERR_UNKNOWN_TIER, "naming the band")
	assert_eq(
		int(_band_record(actor, EMBER_LOW)["run"]),
		run_before,
		"and the band it refused left the run counter alone"
	)

	# A band that is already in flight is refused too, and moves nothing. Entered again
	# first, so there really is a live run for that guard to find.
	assert_eq(bool(_enter(actor, EMBER_LOW)["ok"]), true, "the band is entered again")
	var already := _enter(actor, EMBER_LOW)
	assert_eq(bool(already["ok"]), false, "a second entry while one is live is refused")
	assert_eq(String(already["reason"]), LootState.ERR_ALREADY_IN_DOMAIN, "naming why")
	assert_eq(
		int(_band_record(actor, EMBER_LOW)["run"]),
		run_before,
		"the resumed run keeps its number, so the refusal moved nothing"
	)


## A band cleared out of order does not mark its neighbours cleared. Under the old single
## `cleared_tier` maximum, clearing the HIGH band set the maximum to 2 and then refused
## the LOW band too — reporting a band the player had never entered as fought through.
func test_clearing_one_band_does_not_mark_another_band_cleared() -> void:
	var actor := _hero()
	_enter(actor, EMBER_HIGH)
	for _boss in 3:
		LootApi.strike(actor, float(_active(actor).get("vitality_max", 1.0)) * 10.0, SEED)
	assert_eq(bool(_band_record(actor, EMBER_HIGH)["cleared"]), true, "the high band is cleared")
	assert_eq(
		bool(_band_record(actor, EMBER_LOW).get("cleared", false)),
		false,
		"and the low band, never entered, is not"
	)

	var low := _enter(actor, EMBER_LOW)
	assert_eq(bool(low["ok"]), true, "so the low band still opens for a player who wants it")
	assert_eq(int(low["run"]), 1, "as its own first run")


## Persistence: a v1 ledger migrates onto (domain, band) keys, and it migrates onto the
## CLEARED answers v1 would have given, not onto stricter ones — a save written before
## this change must not hand the player a different world.
func test_a_v1_ledger_migrates_onto_band_keys() -> void:
	var legacy := {
		"version": 1,
		"runs":
		{
			# Abandoned mid-run at band 2, never cleared.
			"ember": {"run": 3, "run_tier": 2, "cleared_tier": -1},
			# Fought through at band 1.
			"storm": {"run": 1, "run_tier": 1, "cleared_tier": 1},
			# v1 could leave a record naming no band at all; it cannot be placed.
			"nameless": {"run": 2, "cleared_tier": -1},
		},
	}
	var migrated := LootState.normalize(legacy)
	assert_eq(int(migrated["version"]), LootState.SCHEMA_VERSION, "the schema version is stamped")
	var runs := migrated["runs"] as Dictionary
	assert_eq(runs.size(), 2, "the two placeable records survive and the nameless one is dropped")
	assert_eq(
		int(runs[LootState.run_key("ember", 2)]["run"]),
		3,
		"the ember record lands on the band it named"
	)
	assert_eq(
		bool(runs[LootState.run_key("ember", 2)]["cleared"]),
		false,
		"and is not cleared, because v1's maximum was below it"
	)
	assert_eq(
		bool(runs[LootState.run_key("storm", 1)]["cleared"]),
		true,
		"the storm record is cleared, because v1's maximum reached it"
	)


## v1 refused every band at or below `cleared_tier`, so a record whose band sat BELOW that
## maximum was already unreachable there. Migration preserves that rather than quietly
## re-opening a band the save had closed.
func test_migration_preserves_v1s_clearing_of_a_band_below_its_maximum() -> void:
	var legacy := {
		"version": 1,
		"runs": {"ember": {"run": 1, "run_tier": 1, "cleared_tier": 2}},
	}
	var runs := LootState.normalize(legacy)["runs"] as Dictionary
	assert_eq(bool(runs[LootState.run_key("ember", 1)]["cleared"]), true, "band 1 stays closed")
	assert_eq(
		runs.has(LootState.run_key("ember", 2)),
		false,
		"and no record is invented for a band v1 never named a run for"
	)


## A v1 save loads and keeps fighting: the payload and claim ledgers were never keyed by
## band, so they migrate untouched and the ids inside them still resolve.
func test_a_v1_save_loads_with_its_rewards_intact() -> void:
	var encounter := "loot_ember_vault_domain/loot_ember_vault_warden@1#1"
	var legacy := {
		"version": 1,
		"runs": {"loot_ember_vault_domain": {"run": 1, "run_tier": 1, "cleared_tier": -1}},
		"active": {},
		"rewards":
		{
			encounter:
			{
				"version": 1,
				"encounter_id": encounter,
				"claim_token": encounter,
				"drops": [],
				"warnings": [],
			}
		},
		"claimed": {},
		"world_drops": [],
	}
	var migrated := LootState.normalize(legacy)
	assert_eq((migrated["rewards"] as Dictionary).has(encounter), true, "the payload survives")
	assert_eq(
		(migrated["claimed"] as Dictionary).size(), 0, "and migration invented no claim against it"
	)
	assert_eq((migrated["active"] as Dictionary).size(), 0, "nor a live run")

	var actor := _hero()
	actor.set_module_data(LootState.MODULE_KEY, legacy)
	LootApi.attach(actor)
	assert_eq(int(LootApi.summary(actor)["reward_count"]), 1, "the facade still reports it")
	assert_eq(
		bool(LootApi.reward(actor, encounter)["ok"]),
		true,
		"and the payload is still addressable under its original id"
	)


## And a migrated save survives a second round trip unchanged: normalization is
## idempotent, so a load/save/load cannot drift the ledger.
func test_normalizing_a_migrated_state_twice_changes_nothing() -> void:
	var legacy := {
		"version": 1,
		"runs": {"ember": {"run": 3, "run_tier": 2, "cleared_tier": -1}},
	}
	var once := LootState.normalize(legacy)
	var twice := LootState.normalize(once)
	assert_eq(twice["runs"], once["runs"], "the ledger is stable across a second pass")
	assert_eq(int(twice["version"]), int(once["version"]), "and so is the version")


## The ledger is serialized exactly once, inside `loot_state`, and there is no second key
## beside it that could hold a competing copy of a run — which is the whole shape BL-0252
## was about.
func test_the_run_ledger_is_stored_once_inside_the_loot_state() -> void:
	var actor := _hero()
	_enter(actor, EMBER_LOW)
	var restored = JSON.parse_string(JSON.stringify(actor.to_dict()))
	var stored := (restored as Dictionary).get("module_data", {}) as Dictionary
	# Every top-level key whose payload looks like a run ledger. `loot_state` is the only
	# one there may be: a second copy beside it is exactly the shape BL-0252 described,
	# because two structures each claiming to know a run is a structure that can disagree.
	var owners: Array = []
	for key in stored.keys():
		var value = stored[key]
		if value is Dictionary and (value as Dictionary).has("runs"):
			owners.append(String(key))
	assert_eq(owners, [String(LootState.MODULE_KEY)], "only the loot state owns a run ledger")
	assert_eq(
		(stored[String(LootState.MODULE_KEY)] as Dictionary)["runs"].size(),
		1,
		"and it holds one entry, for the one band that was entered"
	)
