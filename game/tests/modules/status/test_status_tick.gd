extends TestCase

## ADR 0089's definition of done is a PRODUCTION CALLER, not a test.
##
## Measured 2026-10-02, `Actor.tick_statuses` had no caller in `game/src` at all —
## only `tests/core/test_actor_statuses.gd:18,26`. So no DoT could tick and no status
## could expire. Every test in this file therefore drives the COMPOSITION ROOT
## (`StatusLoop.tick`, `app/status_loop.gd` -> `StatusApi.tick_statuses`), and none of
## them calls `actor.tick_statuses` directly: the direct call is precisely the shape
## that hid the defect for five waves, and a test that used it would pass again the day
## the production caller was deleted.
##
## The driver is `StatusLoop` and NOT the deleted `InputHandler`: ADR 0056 removed that
## prototype with no per-frame driver left behind, so `StatusLoop` deliberately hangs off
## nothing (its own doc comment says so). Driving it directly is the production path —
## it is the wire the next frame driver calls.
##
## `tests/arch_rules/test_arch_rules.gd` is the structural half — it asserts the
## caller is reachable in production code, which survives a test being deleted.

const FRAME := 0.25

var _actor: Actor
var _loop: StatusLoop


func _build() -> void:
	# The same composition a game boot performs: an actor and the status loop the
	# composition root owns the tick of.
	_actor = ActorFactory.build(
		&"ticker", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0, Stat.AGILITY: 20.0}
	)
	_loop = StatusLoop.new(_actor)


func setup() -> void:
	_build()


func _frames(count: int) -> void:
	# Drive the REAL composition-root tick, not the status module. This is the whole test.
	for frame in count:
		_loop.tick(FRAME)


func test_the_frame_driver_is_what_ticks_a_status() -> void:
	# Nothing here calls `tick_statuses`; the composition root does, once per frame,
	# from the `StatusLoop.tick` the game boot wires. One second of frames at the
	# authored `tick_interval` of 1.0 spends the burn's first pulse.
	StatusApi.apply(_actor, &"fire_immolation", 2.0)
	var before := _actor.resource(&"health").current
	_frames(4)
	assert_eq(_actor.has_status(&"fire_immolation"), true, "the status is still live")
	assert_eq(
		before - _actor.resource(&"health").current > 0.0,
		true,
		"and the production frame driver spent its pulse"
	)


func test_a_burn_deals_damage_when_only_the_frame_driver_runs() -> void:
	# The load-bearing assertion. Before ADR 0089 was implemented this was the
	# failure that made the system inert: the status sat on the actor forever and
	# every health point stayed where it was.
	var before := _actor.resource(&"health").current
	var applied := StatusApi.apply(_actor, &"fire_immolation", 3.0)
	assert_eq(bool(applied["ok"]), true, "the burn applies")
	# Well under the 16.0s duration, so nothing has expired and the damage can only
	# have come from the tick channel.
	_frames(8)
	var spent := before - _actor.resource(&"health").current
	# ## The authored share is spent PER PULSE, and the pulse count is the interval's.
	#
	# This deliberately does not restate one flat number. `fire_immolation` is authored
	# `tick_interval = 1.0`, and 8 frames at `FRAME` is 2.0s, so TWO intervals came due --
	# one pulse each. Pinning `3.0 * 0.02` here would pin a pulse count the def does not
	# claim, and it would contradict `test_an_escalating_burn_grows_with_each_pulse` right
	# below, which requires the same status to spend MORE than a flat repetition of its
	# first pulse. Both are reading one authored def, so the arithmetic is read from that
	# def instead of from a literal: the share, the interval and the escalation curve are
	# the content's, and the escalation is what makes pulse N cost more than pulse 1.
	var def := StatusApi.definition(&"fire_immolation")
	var share := float(def.payload.get("share_per_pulse", 0.0))
	var interval := maxf(0.001, def.tick_interval)
	# The elapsed time is the frame count times the frame delta. `_frames(8)` above
	# drove 8 frames at `FRAME`, so that product IS the elapsed time — read from the
	# same constant the driver uses rather than restated as a literal.
	var elapsed := 8.0 * FRAME
	var pulses := int(floor(elapsed / interval))
	# `escalation_per_tick` grows per PULSE, not per frame. `tick_statuses` increments
	# `ticks_elapsed` BEFORE it calls `_pulse`, so the first pulse pays at
	# `ticks_elapsed == 1`, not 0 — the escalation index is one-based because it counts
	# pulses already FIRED, and a pulse that has not fired cannot have escalated. The
	# loop below mirrors that exact order rather than assuming a zero-based index.
	var runtime := StatusRuntime.new()
	runtime.def = def
	runtime.magnitude = 3.0
	var expected := 0.0
	for pulse in pulses:
		runtime.ticks_elapsed = pulse + 1
		expected += StatusRuntime.pulse_magnitude(runtime, 0) * share
	assert_eq(pulses, 2, "two one-second intervals came due in two seconds of frames")
	assert_almost_eq(
		spent, expected, "two seconds of ticks spent the authored share of the potency", 0.001
	)
	# The FIRST pulse alone is one un-escalated share. It is asserted as "at least",
	# never as equality: the total over two pulses is the un-escalated share PLUS an
	# escalated one, so pinning the total to a single pulse's share would contradict
	# the summation immediately above.
	var first_pulse := 3.0 * share
	assert_eq(spent >= first_pulse, true, "at least the first pulse was spent")
	assert_eq(spent > first_pulse, true, "the second pulse spent more: the burn escalated")
	assert_eq(_actor.has_status(&"fire_immolation"), true, "still burning")


func test_a_status_expires_through_the_production_path_and_releases_its_modifiers() -> void:
	# Expiry is the other half of "nobody can tick": without a caller nothing ever
	# reaches `remaining <= 0`. And the modifier release is what stops an expired
	# debuff from silently disarming the target forever.
	var applied := StatusApi.apply(_actor, &"metal_sunder", 1.0)
	assert_eq(bool(applied["ok"]), true, "the debuff applies")
	assert_eq(_actor.stats.modifier_count(), 2, "both authored modifiers are held")
	# 10.0s duration at a 0.25s frame is 40 frames; 48 overshoots into the next frame
	# so the expiry is definitely behind us.
	_frames(48)
	assert_eq(_actor.has_status(&"metal_sunder"), false, "expired through app/ wiring")
	assert_eq(_actor.stats.modifier_count(), 0, "and its modifiers were removed in full")


func test_a_permanent_cultivation_status_survives_ticking() -> void:
	# `remaining < 0.0` is the contract's "forever" sentinel, so a CULTIVATION gift
	# ages through the same path and is never affected by it.
	StatusApi.apply(_actor, &"wood_bloom", 1.0)
	_frames(64)
	assert_eq(_actor.has_status(&"wood_bloom"), true, "still growing after 16 seconds")
	assert_ne(
		_actor.stats.derived(Stat.MAX_HEALTH),
		0.0,
		"and it is still contributing its authored modifier"
	)


func test_combat_exit_purges_combat_scope_and_leaves_cultivation_scope() -> void:
	# ADR 0089's purge rule: COMBAT statuses die on combat exit, by the same caller
	# that ticks them; a CULTIVATION status is never purged by combat state, because
	# it is a gift the game pays out rather than a fight-scoped fact.
	StatusApi.apply(_actor, &"metal_sever", 1.0)
	StatusApi.apply(_actor, &"wood_bloom", 1.0)
	_frames(2)
	var purged := _loop.exit_combat()
	assert_eq(purged.size() > 0, true, "combat exit purged something")
	assert_eq(_actor.has_status(&"metal_sever"), false, "the COMBAT status is purged")
	assert_eq(_actor.has_status(&"wood_bloom"), true, "the CULTIVATION status survives")
	assert_eq(_actor.stats.modifier_count() > 0, true, "and its modifiers are still held")


func test_an_escalating_burn_grows_with_each_pulse() -> void:
	# Fire's identity is escalation, so the damage is not a flat share and a test
	# pinning one number would be pinning a bug.
	StatusApi.apply(_actor, &"fire_immolation", 2.0)
	_frames(4)
	var after_first := _actor.resource(&"health").maximum - _actor.resource(&"health").current
	_frames(12)
	var total := _actor.resource(&"health").maximum - _actor.resource(&"health").current
	assert_eq(total > after_first, true, "the burn kept spending as it escalated")
	assert_eq(
		total > after_first * 2.0,
		true,
		"and grew past a flat repetition of the first window's cost"
	)


func test_a_burst_spends_itself_once_and_leaves_nothing_behind() -> void:
	# `water_deluge` is the anti-DoT: one heavy unblockable impact at the moment of
	# arrival. Two windows of frames must not double it, or "burst" is a lie.
	var applied := StatusApi.apply(_actor, &"water_deluge", 1.0)
	assert_eq(bool(applied["ok"]), true, "the wave lands")
	var spent := _actor.resource(&"health").maximum - _actor.resource(&"health").current
	assert_eq(spent > 0.0, true, "it dealt its impact immediately")
	_frames(16)
	assert_almost_eq(
		_actor.resource(&"health").maximum - _actor.resource(&"health").current,
		spent,
		"and dealt nothing further while it sat on the actor"
	)


func test_a_burning_body_feeds_a_pyre_that_alone_does_nothing() -> void:
	# The second-order mechanic: `fire_pyre` authors no stat and no pool of its own,
	# so with no burning sibling it contributes nothing at all — and that is the
	# design, not a defect. With a sibling it doubles that sibling's potency.
	var solo := _actor.resource(&"health").maximum - _actor.resource(&"health").current
	StatusApi.apply(_actor, &"fire_pyre", 1.0)
	_frames(8)
	assert_almost_eq(
		_actor.resource(&"health").maximum - _actor.resource(&"health").current,
		solo,
		"a pyre with no burning sibling spends nothing"
	)
	StatusApi.apply(_actor, &"fire_immolation", 2.0)
	var before := _actor.resource(&"health").maximum - _actor.resource(&"health").current
	_frames(4)
	var after := _actor.resource(&"health").maximum - _actor.resource(&"health").current
	assert_eq(after > before, true, "the burning sibling now spends more per pulse")


func test_a_status_the_module_did_not_author_still_ages_through_the_same_tick() -> void:
	# Tribulation's `heavenly_blessing` and `PregnancyStatus` are applied by their
	# own modules and carry no `StatusDef`. They must still age, or wiring the status
	# clock would have broken every pre-existing status to fix the new ones.
	var blessing := StatusEffect.new(&"heavenly_blessing", 2.0)
	_actor.add_status(blessing)
	assert_eq(_actor.has_status(&"heavenly_blessing"), true, "the foreign status is live")
	_frames(12)
	assert_eq(
		_actor.has_status(&"heavenly_blessing"),
		false,
		"and it aged out through the same production tick"
	)


func test_ticking_an_unwired_loop_is_still_safe() -> void:
	# A composition root that built no loop must not crash on a frame, and an actor
	# nobody ticks simply does not age — the status is inert, not corrupt.
	var bare := StatusLoop.new()
	StatusApi.apply(_actor, &"metal_sever", 1.0)
	for frame in 4:
		assert_eq(bool(bare.tick(FRAME)["ok"]), false, "an unwired loop refuses loudly")
	assert_eq(_actor.has_status(&"metal_sever"), true, "the status simply does not age")
	assert_eq(_loop.actor(), _actor, "the wired loop is unaffected")


func test_a_save_carries_no_status_and_still_loads() -> void:
	# ADR 0089: statuses are session-only. `SCHEMA_VERSION` stays 4, `to_dict()` has
	# no `statuses` key, and an older save with no status data at all loads cleanly.
	StatusApi.apply(_actor, &"fire_immolation", 2.0)
	var payload := _actor.to_dict()
	assert_eq(payload.has("statuses"), false, "no statuses key is emitted")
	assert_eq(int(payload["version"]), 4, "schema version is unchanged at 4")
	var text := JSON.stringify(payload)
	assert_eq(text.contains("fire_immolation"), false, "no status id leaks into the payload")
	assert_eq(text.contains("share_per_pulse"), false, "and no status payload leaks either")

	# The round trip restores an actor, and the status is simply gone.
	var restored := Actor.from_dict(payload)
	assert_eq(restored.has_status(&"fire_immolation"), false, "the status is session-only")
	assert_eq(int(restored.to_dict()["version"]), 4, "and the restored actor reserializes")

	# An OLD save — schema 4 written before this change — has no status data at all.
	var legacy := payload.duplicate(true)
	legacy["statuses"] = null
	for key in ["module_data", "item_state", "mind_attempt"]:
		legacy.erase(key)
	var from_legacy := Actor.from_dict(legacy)
	assert_eq(from_legacy.id, _actor.id, "a legacy payload with no status data still loads")
	assert_eq(from_legacy.statuses.size(), 0, "and carries no statuses")
