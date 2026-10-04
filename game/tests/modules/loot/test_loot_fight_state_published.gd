extends TestCase

## BL-0878. The loot screen publishes the fight's own state and NOTHING reads it:
## `boss_id`, `vitality`, `vitality_max` and `health_ratio` have zero consumers and zero
## test coverage anywhere in `game/src` or `game/tests`. That is why eight attempts to stop
## the boot probe's strike loop on "the fight ended" all behaved identically - no code in
## the repo had ever READ those fields to find out whether they carry anything at all.
##
## This suite reads them. It drives the screen the way a player does - choose a domain,
## press Enter, press Strike - and never calls an `act_*` method, because the claim being
## tested is that a player can fight and see the fight's own numbers, not that a harness
## holding the screen object can.
##
## These are also the only assertions in the repo that can express the objective's first
## binding product rule: damage lands on an AUTHORED vitality pool belonging to a NAMED
## boss. Everything else about the loot pipeline can be asserted from a bag; the pool
## cannot.

var _rig: LootScreenRig = null


func setup() -> void:
	_rig = LootScreenRig.new()


## `release()` is idempotent, so this is safe even after a test aborted mid-way - which
## is exactly when a hand-freed screen would be leaked instead.
func teardown() -> void:
	if _rig != null:
		_rig.release()
		_rig = null


## Mid-fight, the screen must NAME what is being fought and publish the pool it is being
## fought out of. An empty `boss_id` here is not cosmetic: it is the field the boot probe
## infers "the run cleared" from, so a blank one makes that inference unreadable.
func test_the_screen_names_the_live_boss_and_publishes_its_authored_pool() -> void:
	var view := _rig.screen(_rig.hero())
	assert_eq(
		_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER),
		true,
		"the Enter control starts a run"
	)
	var live := view.summary() as Dictionary
	assert_eq(bool(live.get("in_domain", false)), true, "a boss is live")
	assert_ne(
		String(live.get("encounter_id", "")),
		"",
		"and the fight names its encounter, which is what ends one and starts the next"
	)
	assert_ne(
		String(live.get("boss_id", "")),
		"",
		"and the boss being fought, which the boot probe's verdict is derived from"
	)
	assert_eq(
		float(live.get("vitality_max", 0.0)) > 0.0,
		true,
		"the boss carries an AUTHORED vitality pool, not a number scaled to the hero's gear"
	)
	assert_eq(float(live.get("vitality", 0.0)) > 0.0, true, "and that pool is not yet spent")


## The load-bearing one. A published pool that no published damage moves is a label, not a
## fight: this is the assertion that damage lands on the AUTHORED vitality, which is the
## whole first clause of the objective's primary loop.
func test_a_strike_spends_the_published_pool_rather_than_a_private_number() -> void:
	var view := _rig.screen(_rig.hero())
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	var before := float((view.summary() as Dictionary).get("vitality", 0.0))
	assert_eq(_rig.press(view, "%StrikeButton"), true, "the Strike control exists")
	var after := float((view.summary() as Dictionary).get("vitality", 0.0))
	assert_eq(
		after < before,
		true,
		"one strike spends the pool the screen publishes: %s -> %s" % [before, after]
	)
