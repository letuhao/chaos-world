extends TestCase

## BL-0854, measured. The entry - and the boot probe's own comment - claim that walking the
## whole BAND destroys the first kill's reward: "by the time the band clears, the reward
## minted on the first kill is settled". That is a claim about the reward lifecycle, and it
## is FALSE on the current tree. Measured here, in a suite, in seconds instead of a boot:
##
##   walking the band to its end leaves pending_drops > 0 and reward_count = 1
##
## So the band-walk costs the probe nothing. A kill's payload outlives the fight that minted
## it, and a probe that fights the whole band still has something to collect. That matters
## because the standing explanation for the probe's red hunt has been the band-walk for seven
## turns, and this removes it: the hunt's failure is NOT the reward being settled, and no fix
## to `LootState._advance` would make the probe greener.
##
## The invariant worth keeping is the one this measurement leaves standing, stated in the
## direction that is actually true: whatever a fight does to the run, a reward the player has
## earned stays owed until they claim it. That is the objective's claim-token rule - "a reward
## payload is minted ONCE (claim token)" - expressed on the one path that could have broken it.

const MAX_BOSSES := 12

var _rig: LootScreenRig = null


func setup() -> void:
	_rig = LootScreenRig.new()


## Idempotent, so this is safe after a test that aborted mid-walk.
func teardown() -> void:
	if _rig != null:
		_rig.release()
		_rig = null


## Walk the whole band deliberately - which is exactly what the boot probe's strike loop does,
## because `LootState._advance` spawns the next boss on a defeat and Strike stays offered -
## and then ask the question the entry got wrong: is the first kill still owed?
func test_walking_the_whole_band_still_leaves_the_earned_rewards_owed() -> void:
	var view := _rig.screen(_rig.hero())
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	assert_ne(
		String((view.summary() as Dictionary).get("encounter_id", "")),
		"",
		"a boss is live to begin with"
	)
	var kills := 0
	# `defeat_boss` stops at ONE kill on its own (it returns when `encounter_id` changes), so
	# calling it again is how a whole band gets walked here. Bounded by MAX_BOSSES, and it
	# ends as soon as the rig reports the band cleared, so a rig that stopped spawning
	# bosses cannot spin.
	while kills < MAX_BOSSES:
		if _rig.defeat_boss(view, 200).is_empty():
			break
		kills += 1
	assert_ne(kills, 0, "at least one boss was killed")
	var after := view.summary() as Dictionary
	var owed := int(after.get("pending_drops", 0))
	var rewards := int(after.get("reward_count", 0))
	# The measurement that corrects the entry, stated in the direction that is true.
	assert_eq(
		owed > 0,
		true,
		(
			(
				"after walking all %d bosses the player is still owed drops, so the band-walk does "
				+ "NOT settle an earlier kill's reward (owed=%d, rewards=%d). BL-0854 claimed the "
				+ "opposite and was wrong: the probe's red hunt is not caused by the reward being "
				+ "settled, and no change to LootState._advance would make it green."
			)
			% [kills, owed, rewards]
		)
	)
	assert_eq(
		rewards > 0,
		true,
		"and the reward list still shows what the fight paid (rewards=%d)" % rewards
	)


## The claim-token rule on the ordinary path: one fight, one reward, still owed. Kept separate
## because a suite where both halves pass is not evidence that either would fail alone.
func test_a_single_kill_leaves_its_own_reward_owed_to_the_player() -> void:
	var view := _rig.screen(_rig.hero())
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	assert_ne(_rig.defeat_boss(view, 200), "", "one boss was killed and named")
	var after := view.summary() as Dictionary
	assert_eq(
		int(after.get("pending_drops", 0)) > 0,
		true,
		"and the reward it minted is still owed - a kill never spends its own payload"
	)
	assert_eq(int(after.get("reward_count", 0)) > 0, true, "and the reward list still shows it")
