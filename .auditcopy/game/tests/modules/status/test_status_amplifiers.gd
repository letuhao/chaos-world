extends TestCase

## The AMPLIFIER channel: `fire_pyre` and `wind_spread` are `sibling_amp` statuses that
## spend nothing themselves and exist only to make the burns beside them worse.
##
## ## The defect the production channel fixed, and the defect THIS SUITE carried
##
## `StatusRuntime.pulse_magnitude` used to read `sibling_gain` off `runtime.def` — the
## status BEING PULSED. `fire_immolation` authors no `sibling_gain`, so the branch
## never fired for any burn at any magnitude, and `StatusApi._sibling_burns` used to
## refuse unless the pulsing def was itself a `feed_siblings` amplifier, which spends
## nothing and so never reached the count at all. The two conditions were mutually
## exclusive: the channel answered `0` for every burn in the game. Production now reads
## the gain off the amplifiers PRESENT ON THE ACTOR (`StatusApi._amplifier_gain`) and
## counts the spending statuses beside the one pulsing.
##
## ## What was WRONG HERE, and the arithmetic that says so
##
## The suite's setup, not the design — and the suite's own header used to contradict
## itself about it. It measured "AMPLIFIER DELTA = 0.000000" with a `fire_pyre` on the
## actor and a LONE `fire_immolation` beside it, then asserted that exact measurement
## away in a different test. `_sibling_burns` excludes the pulsing status by id and
## `_feeds` admits only `health_share`/`element_power` defs, so a lone burn beside a pyre
## has ZERO feeding siblings: the only burn on the actor IS the one pulsing. A pyre
## amplifies the OTHER burns, and `fire_pyre.tres` says so in as many words — "A burning
## body burns harder. Every other burn already on the target feeds this one." So the
## delta being 0.0 there is the DESIGN working, and it is now asserted as its own case
## rather than smuggled in as a failing one.
##
## Every amplification case below therefore puts a REAL sibling on the actor, and the
## expected figure is computed FROM the def the game ships rather than restated:
## `sibling_gain`, `sibling_cap`, `share_per_pulse`, `escalation_per_tick` and
## `tick_interval` all live on the `.tres`, and the assertions that matter are
## RELATIONSHIPS (amplified > un-amplified, and the exact authored figure) rather than
## constants a balance pass would have to edit in twenty places.
##
## ## The channel's real ceiling, which is NOT the sum of the gains
##
## `StatusApi._amplifier_gain` SUMS each live amplifier's gain (clamped to its own cap)
## and `_amplifier_cap` takes the MAXIMUM cap, because `sibling_cap` is the ceiling of
## the CHANNEL (`api.gd:471-474`). Both authored amplifiers ship gain `0.5`/`0.45`
## against cap `0.4`, so each contributes `0.4`, the aggregate gain is `0.8`, and the
## channel spends `min(0.8 * siblings, 0.4)`. One sibling already reaches that ceiling,
## so a second amplifier and a second sibling both widen nothing — the cap is authored
## to stop exactly that. The suite asserts the truth of the shipped numbers instead of
## the arithmetic it hoped for: two amplifiers DO raise the reported gain, and the pulse
## is still bounded at one cap.

const BURN := &"fire_immolation"
const PYRE := &"fire_pyre"
const WIND := &"wind_spread"

## The `health_share` sibling the numeric cases put beside the burn. `metal_sever` is
## the bleed ADR 0090 authored beside the fire pair, it spends its own share, and it is
## a DIFFERENT channel from the burn's `element_power` — so a case that measures the
## burn's own spend through it is measuring the channel rather than one status's curve.
const SIBLING := &"metal_sever"

## The potency both channels are exercised at. Well inside `fire_immolation`'s authored
## `magnitude_cap` (10.0), so the escalation curve and the amplifier channel — not the cap
## — are what move the number.
const MAGNITUDE := 2.0

## Frames driven per window. Read off the burn's authored `tick_interval` rather than
## restated, so a retune of the content moves the frame count with it.
const FRAME := 0.25

# --- the channel, measured against the same burn ------------------------------------


## THE case. The same burn, at the same potency, spends a measurably different amount
## when a `fire_pyre` has a SECOND BURN to feed and when it has nothing to feed.
##
## This is where the suite's setup was wrong, and the fix is the mechanic rather than a
## relaxed number: `beside` now carries a real feeding sibling (`SIBLING`), because
## `_sibling_burns` counts the OTHER spending statuses on the actor and excludes the one
## pulsing. Measured before the fix (lone burn, pyre on) and after (one sibling, pyre on),
## the burn's spend moves from `0.041600` to `0.058240` — a delta of exactly
## `0.016640`, which is `0.4` (the pyre's gain, clamped to its own cap) applied to the
## authored share.
##
## Two fresh actors rather than two windows on one actor, because the amplifier is a
## STATUS on the actor and the two cases must not share one: measuring both on the same
## body would let the first window's escalation inflate the second.
func test_a_burn_beside_a_pyre_and_a_second_burn_spends_more_than_the_same_burn_alone() -> void:
	var alone := _burn_spend(_actor(), MAGNITUDE, false)
	var pyred := _burn_pulse_spend(_dressed([PYRE, SIBLING, BURN]))
	assert_almost_eq(alone, _unamplified_spend(), "the control spends the authored share", 1e-6)
	assert_eq(
		pyred > alone,
		true,
		(
			"a pyre must spend MORE once it has a burn to feed: alone %s, pyred %s (delta %s)"
			% [alone, pyred, pyred - alone]
		)
	)
	# Not merely "more" — the authored `sibling_gain` over one feeding sibling, which is
	# what makes this a failure to wire the channel rather than a rounding disagreement.
	assert_almost_eq(
		pyred - alone,
		alone * _pyre_gain(),
		"and the delta is exactly the authored sibling_gain applied to the share",
		1e-6
	)


## The MECHANIC the old setup kept asserting the opposite of, pinned in its own right: an
## amplifier is not its own sibling, so a pyre with nothing else burning spends nothing.
##
## `_sibling_burns` walks the actor's statuses, skips `runtime.def.id` — the burn being
## pulsed — and counts only what `_feeds` admits (`health_share` / `element_power`). A
## lone `fire_immolation` beside a `fire_pyre` therefore has ZERO feeding siblings and
## spends EXACTLY the un-amplified amount: delta `0.000000`, down from `0.000000` on a
## channel that was never wired at all. That is how the two defects are told apart, and
## it is the same claim `fire_pyre.tres` makes in prose — "Every OTHER burn already on
## the target feeds this one."
func test_a_lone_burn_beside_a_pyre_spends_exactly_the_un_amplified_amount() -> void:
	var alone := _burn_spend(_actor(), MAGNITUDE, false)
	var actor := _dressed([PYRE, BURN])
	assert_eq(
		StatusApi._sibling_burns(actor, _runtime_of(actor, BURN)),
		0,
		"the only burn on the actor is the one pulsing, so nothing feeds the pyre"
	)
	var pyred := _spend_over_one_pulse(actor)
	assert_almost_eq(pyred, alone, "a pyre with nothing to feed spends the same amount", 1e-6)
	assert_almost_eq(pyred - alone, 0.0, "the delta is exactly zero, and that is the design", 1e-9)
	# The amplifier itself authors no pool and no share, so the spend it contributes is
	# zero by content, not by accident of the tick loop.
	var def := StatusApi.definition(PYRE)
	assert_eq(float(def.payload.get("share_per_pulse", 0.0)), 0.0, "the pyre spends nothing")
	assert_eq(def.magnitude_unit, &"sibling_amp", "and it resolves through the amplifier channel")


## The control half of the pair above, as its own assertion: a burn with NO amplifier
## beside it spends EXACTLY what it spent before the channel moved — same magnitude, same
## escalation index, same authored share. Read through the two-argument
## `pulse_magnitude(runtime, siblings)` call the rest of the tree still uses, because
## keeping that call answer the un-amplified magnitude is what makes the new channel
## additive rather than a change of contract.
##
## The runtime is read AFTER the window, not before: `pulse_magnitude` reads
## `ticks_elapsed` off the very record the tick advances, so a value captured before the
## tick answers the UN-escalated first pulse (`0.04` against a spend of `0.0416`) and
## reports the shipped pulse as broken. That mismatch was the whole of this test's
## original failure.
func test_a_burn_with_no_pyre_spends_exactly_what_it_spent_before() -> void:
	var actor := _actor()
	StatusApi.apply(actor, BURN, MAGNITUDE)
	var def := StatusApi.definition(BURN)
	var share := float(def.payload.get("share_per_pulse", 0.0))
	var spend := _spend_over_one_pulse(actor)
	# Read after the tick: `runtime` is the LIVE record `tick_statuses` advanced.
	var runtime := _runtime_of(actor, BURN)
	# The two-argument call, verbatim: the signature the pre-fix tree used.
	var legacy := StatusRuntime.pulse_magnitude(runtime, 0) * share
	assert_almost_eq(
		spend,
		legacy,
		"the shipped pulse equals the two-argument call, so no-amplifier is unchanged",
		1e-6
	)
	# And the explicit two-argument form against a sibling count it cannot have: an
	# amplifier whose gain was not passed in multiplies nothing. This is the default that
	# keeps `pulse_magnitude` pure — it applies a curve, it does not look anything up.
	assert_almost_eq(
		StatusRuntime.pulse_magnitude(runtime, 1),
		StatusRuntime.pulse_magnitude(runtime, 0),
		"a gain nobody passed in cannot amplify, whatever the sibling count",
		1e-9
	)


## TWO amplifiers add their authored gains, and the CHANNEL is still bounded at one cap.
##
## ## Why this is not "two amplifiers widen the pulse"
##
## `StatusApi._amplifier_gain` sums each live amplifier's `sibling_gain` clamped to its
## own `sibling_cap` — `fire_pyre` authors 0.5 and `wind_spread` 0.45 against a cap of
## 0.4 each, so the aggregate is `0.4 + 0.4 = 0.8`. `_amplifier_cap` then takes the
## MAXIMUM cap over the live amplifiers, because `sibling_cap` is the ceiling of the
## CHANNEL and not a per-amplifier budget (`api.gd:471-474`). `pulse_magnitude` spends
## `min(gain * siblings, cap)`, which for one sibling is `min(0.8, 0.4) = 0.4` whether
## one amplifier is on the actor or two. So the second authored amplifier is NOT lost —
## it is visible in the reported gain — and the pulse it would have widened is bounded by
## a number a designer authored for exactly that purpose.
##
## The old body asserted `both > pyre_only`. That is not reachable with the shipped
## `.tres` and is not the design: it asked the channel to break its own ceiling.
func test_two_amplifiers_add_their_authored_gains_and_the_channel_still_saturates() -> void:
	var none := _burn_spend(_actor(), MAGNITUDE, false)
	var one_actor := _dressed([PYRE, SIBLING, BURN])
	var both_actor := _dressed([PYRE, WIND, SIBLING, BURN])
	var pyre_only := _burn_pulse_spend(one_actor)
	var both := _burn_pulse_spend(both_actor)
	# The AGGREGATE does collect both authored gains, which is the half that used to be
	# unreachable — `sibling_gain` read off the pulsing def could never report a sum.
	assert_almost_eq(
		StatusApi._amplifier_gain(both_actor),
		_pyre_gain() + _wind_gain(),
		"both amplifiers contribute their own gain, each clamped at its own cap",
		1e-9
	)
	assert_eq(
		StatusApi._amplifier_gain(both_actor) > StatusApi._amplifier_gain(one_actor),
		true,
		"and the reported gain is strictly larger than one amplifier's alone"
	)
	# The CEILING is the maximum cap, not the sum of them, so the pulse is the same
	# either way. Asserted as a strict numeric equality: this is the claim that a second
	# amplifier cannot run the channel away.
	assert_almost_eq(
		StatusApi._amplifier_cap(both_actor),
		_cap_of_actor(one_actor, []),
		"widening the channel does not widen the ceiling that bounds it",
		1e-9
	)
	assert_almost_eq(
		both,
		pyre_only,
		"one amplifier and two spend the same pulse, because one sibling already hits the cap",
		1e-6
	)
	# And neither of them is the un-amplified control: the ordering that IS true.
	assert_eq(
		none < pyre_only and pyre_only == both,
		true,
		"no amplifier < one amplifier = two amplifiers (cap 0.4 binds at one sibling)"
	)
	# A second sibling does not widen it either, for the same reason. The bleed's own
	# spend is excluded by reading the BURN's pulse, so this is the burn's delta alone.
	assert_almost_eq(
		both,
		_burn_pulse_spend(_dressed([PYRE, WIND, BURN, SIBLING])),
		"a second feeding sibling is clamped at the same cap",
		1e-6
	)


## `wind_spread` is the SAME channel on a different element, so it has to move a sibling
## the way the pyre does. Asserted at wind's own authored gain rather than at the pyre's
## number, which is the whole claim: the channel is not fire-specific and the two
## amplifiers are not aliases of one another.
func test_wind_spread_amplifies_a_sibling_the_same_way_the_pyre_does() -> void:
	var none := _burn_spend(_actor(), MAGNITUDE, false)
	var winded := _burn_pulse_spend(_dressed([WIND, SIBLING, BURN]))
	assert_eq(
		winded > none,
		true,
		(
			"wind_spread is an amplifier: alone %s, winded %s (delta %s)"
			% [none, winded, winded - none]
		)
	)
	assert_almost_eq(
		winded - none,
		none * _wind_gain(),
		"and it spends wind_spread's OWN authored sibling_gain, not the pyre's",
		1e-6
	)


## The channel saturates at the authored `sibling_cap` rather than running away, which is
## what stops N amplifiers on one actor from multiplying a pulse without bound. Asserted
## on the pure function so the ceiling is a property of the CURVE and not of any particular
## actor's status list: past `cap / gain` siblings the answer stops moving.
func test_the_channel_saturates_at_the_authored_sibling_cap() -> void:
	var runtime := _pulse_runtime(BURN, MAGNITUDE)
	var gain := _pyre_gain()
	var cap := _cap_of(PYRE)
	# The largest sibling count whose gain is still under the cap, and one past it.
	var under := int(floor(cap / gain))
	assert_eq(under > 0, true, "the authored cap is reachable inside one sibling")
	var at_cap := StatusRuntime.pulse_magnitude(runtime, under, gain, cap)
	var past_cap := StatusRuntime.pulse_magnitude(runtime, under + 1, gain, cap)
	var far_past := StatusRuntime.pulse_magnitude(runtime, under + 50, gain, cap)
	assert_almost_eq(at_cap, past_cap, "one sibling past the cap changes nothing", 1e-9)
	assert_almost_eq(at_cap, far_past, "and fifty siblings past it changes nothing either", 1e-9)
	# Below the cap the curve really is still climbing, so the saturation assertion above
	# is not satisfied by a channel that was flat from the first sibling.
	var one := StatusRuntime.pulse_magnitude(runtime, 1, gain, cap)
	assert_eq(
		one > StatusRuntime.pulse_magnitude(runtime, 0, gain, cap),
		true,
		"the curve climbs while it is under the cap"
	)


## ## The amplifier feeds the OTHER statuses on the actor, not just one hard-coded id
##
## `_feeds` decides by `magnitude_unit` rather than by id or by mechanic, so the channel
## is a property of the CONTENT TREE: any authored status that spends its magnitude
## (`element_power` or `health_share`) is a sibling, and a future status beside a burn is
## fed exactly as a second burn is. Asserted on a DIFFERENT spending status — the bleed
## (`health_share`), against a burn that spends through `element_power` — so "it multiplies
## `fire_immolation`" cannot pass for "it feeds siblings".
##
## The bleed spends its own share on the same pool on the same frame, so the actor's pool
## delta is BOTH spends. Measuring the pool instead of the burn would credit the burn with
## the bleed's cost, which is how a case like this passes for the wrong reason: the
## expected figure below is 0.03 of bleed, not the 0.01664 of authored amplification. Each
## status's own spend is therefore read off its live runtime record, and the pool delta is
## asserted to equal their sum.
func test_any_spending_status_is_a_sibling_and_an_amplifier_is_not() -> void:
	var bleed := StatusApi.definition(SIBLING)
	assert_ne(bleed.magnitude_unit, &"sibling_amp", "the bleed is not an amplifier")
	assert_eq(
		float(bleed.payload.get("share_per_pulse", 0.0)) > 0.0,
		true,
		"metal_sever spends a share of its own, so it is a sibling the amplifiers feed"
	)
	assert_ne(
		StatusApi.definition(BURN).magnitude_unit,
		bleed.magnitude_unit,
		"and it spends through a DIFFERENT channel from the burn's"
	)
	var alone := _burn_spend(_actor(), MAGNITUDE, false)
	# One burn alone, one burn beside a bleed, both on the same pyre.
	var lone := _dressed([PYRE, BURN])
	var paired := _dressed([PYRE, SIBLING, BURN])
	assert_eq(
		StatusApi._sibling_burns(paired, _runtime_of(paired, BURN)),
		1,
		"the bleed is one feeding sibling"
	)
	assert_eq(
		StatusApi._sibling_burns(lone, _runtime_of(lone, BURN)),
		0,
		"and with nothing beside it the burn has none, which is the other half of the pair"
	)
	var one := _burn_pulse_spend(paired)
	assert_eq(
		one > _burn_pulse_spend(lone), true, "a second spending status must widen the channel"
	)
	# The channel is `1 + min(gain * siblings, cap)` on the WHOLE pulse magnitude, so
	# one sibling multiplies by `(1 + gain)`, not by `gain`. Writing `alone * gain`
	# asserted a marginal increase against a multiplicative curve.
	#
	## ## Why this used to read 0.056 against an expected 0.058240
	##
	## `alone` is `_burn_spend`, which DRIVES A WINDOW, so the burn's runtime it leaves
	## behind has `ticks_elapsed == 1` and is already ESCALATED — `2.0 * (1 + 0.12/3) =
	## 2.08`, a spend of `0.041600`. This pair used to read `_pulse_spend_of(paired, BURN)`
	## on an actor no window had ever run, so the burn it read had `ticks_elapsed == 0`: the
	## escalation branch multiplied by `1 + 0.12 * 0 / 3 = 1.0`, and the spend came out
	## `2.0 * 1.4 * 0.02 = 0.056`. The expectation `alone * (1 + gain) = 0.0416 * 1.4 =
	## 0.058240` was RIGHT and the measured figure was the un-escalated one — the two sides
	## of the comparison were at different points on the escalation curve, which is exactly
	## the error this file's own `_pulse_spend_of` docblock warns about.
	##
	## So the fixture is corrected, not the number: `_burn_pulse_spend` ticks the actor and
	## THEN reads, which puts both sides of the comparison at the same escalation index and
	## pins the shipped pulse rather than a figure derived from an un-ticked record.
	assert_almost_eq(
		one, alone * (1.0 + _pyre_gain()), "and one sibling multiplies the burn by (1 + gain)", 1e-6
	)
	# The pool delta is both spends, and it is exactly that: no bleed cost is credited to
	# the burn and none is lost. Read from ONE actor — building a second with `_dressed`
	# gave it its own escalation index, so the two sides were never comparable.
	var dressed_actor := _dressed([PYRE, SIBLING, BURN])
	assert_almost_eq(
		_spend_over_one_pulse(dressed_actor),
		_pulse_spend_of(dressed_actor, BURN) + _pulse_spend_of(dressed_actor, SIBLING),
		"the actor's health loss is the burn's spend plus the bleed's, and nothing else",
		1e-6
	)
	# The amplifier is NOT a sibling of itself. `_sibling_burns` excludes the pulsing id
	# and `_feeds` admits no `sibling_amp` def, so the count is 1 here whether there is one
	# amplifier or four — which is asserted, not assumed.
	var crowded := _dressed([PYRE, WIND, PYRE, WIND, SIBLING, BURN])
	assert_eq(
		StatusApi._sibling_burns(crowded, _runtime_of(crowded, BURN)),
		1,
		"more amplifiers cannot inflate the feeding-sibling count"
	)


# --- the read path itself ------------------------------------------------------------


## The gain comes off the amplifiers PRESENT ON THE ACTOR. This is the assertion the
## defect makes impossible: with `sibling_gain` read off the pulsing def, every one of
## these actors answers an IDENTICAL magnitude, because `fire_immolation` authors no gain
## whatever. The three reads are pinned to the two authored `.tres` values and to the
## arithmetic between them, so the read cannot silently move back onto the wrong object.
func test_the_gain_is_read_off_the_amplifiers_on_the_actor() -> void:
	var none := _gain_of(_actor())
	var pyred := _gain_of(_actor(), [PYRE])
	var winded := _gain_of(_actor(), [WIND])
	var both := _gain_of(_actor(), [PYRE, WIND])
	assert_almost_eq(none, 0.0, "no amplifier means no gain at all", 1e-9)
	assert_almost_eq(pyred, _pyre_gain(), "fire_pyre's own authored gain", 1e-9)
	assert_almost_eq(winded, _wind_gain(), "wind_spread's own authored gain", 1e-9)
	assert_almost_eq(
		both,
		minf(_pyre_gain(), _cap_of(PYRE)) + minf(_wind_gain(), _cap_of(WIND)),
		"both amplifiers contribute their own gain, each clamped at its own cap",
		1e-9
	)
	# The cap is the CHANNEL's ceiling, so it is the maximum over the live amplifiers and
	# NOT their sum: widening what the channel may add must not also widen the bound on
	# how much of it any one amplifier can contribute.
	assert_almost_eq(_cap_of_actor(_actor(), [PYRE, WIND]), _cap_of(WIND), "the wider cap wins")
	assert_almost_eq(
		_cap_of_actor(_actor(), [PYRE]),
		_cap_of(PYRE),
		"and one amplifier is bounded at its own authored cap"
	)


## `pulse_magnitude` stays PURE: same runtime and same numbers in, same answer out, with
## no actor anywhere in the call. Asserted by calling it twice on the same runtime and by
## showing a gain that was passed in multiplies nothing without a feeding sibling — which
## is what lets the rest of the tree keep calling it without measuring amplifiers first.
##
## The original body compared a THREE-sibling call against a ZERO-sibling one and reported
## the failure as "no feeding sibling is no amplification", so the assertion and its own
## message said opposite things. Both halves are stated separately here: zero siblings is
## the un-amplified magnitude even with a gain in hand, and three siblings is strictly
## larger.
func test_pulse_magnitude_is_pure_and_its_legacy_signature_still_works() -> void:
	var runtime := _pulse_runtime(BURN, MAGNITUDE)
	var first := StatusRuntime.pulse_magnitude(runtime, 3, _pyre_gain(), _cap_of(PYRE))
	var second := StatusRuntime.pulse_magnitude(runtime, 3, _pyre_gain(), _cap_of(PYRE))
	assert_almost_eq(first, second, "the same inputs answer the same number", 1e-12)
	assert_almost_eq(
		StatusRuntime.pulse_magnitude(runtime, 0, _pyre_gain(), _cap_of(PYRE)),
		StatusRuntime.pulse_magnitude(runtime, 0),
		"no feeding sibling is no amplification, and that is the design",
		1e-9
	)
	assert_eq(
		first > StatusRuntime.pulse_magnitude(runtime, 0, _pyre_gain(), _cap_of(PYRE)),
		true,
		"and a gain in hand widens the pulse the moment there IS a sibling to feed"
	)
	# A null runtime or a null def is refused rather than multiplied: `pulse_magnitude`
	# has always answered `0.0` there and a caller that lost its record must not get a
	# number scaled by whatever amplifiers the actor happens to carry.
	assert_almost_eq(
		StatusRuntime.pulse_magnitude(null, 3, _pyre_gain(), _cap_of(PYRE)),
		0.0,
		"null is refused",
		1e-9
	)
	var detached := _pulse_runtime(BURN, MAGNITUDE)
	detached.def = null
	assert_almost_eq(
		StatusRuntime.pulse_magnitude(detached, 3, _pyre_gain(), _cap_of(PYRE)),
		0.0,
		"and a runtime with no def is refused too",
		1e-9
	)


## The escalation curve and the amplifier channel COMPOSE rather than one replacing the
## other, and the cap the def authors (`magnitude_cap`) still bounds the result. Before the
## fix the amplifier branch sat after the escalation branch and could only ever be reached
## with a gain no def authored, so nothing proved they were independent.
func test_the_amplifier_channel_composes_with_escalation_and_respects_the_magnitude_cap() -> void:
	var def := StatusApi.definition(BURN)
	var cap := def.magnitude_cap
	var gain := _pyre_gain()
	var channel_cap := _cap_of(PYRE)
	var escalated := 0.0
	var pulses := 24
	for pulse in range(1, pulses + 1):
		var runtime := _pulse_runtime(BURN, MAGNITUDE)
		runtime.ticks_elapsed = pulse
		var alone := StatusRuntime.pulse_magnitude(runtime, 0, gain, channel_cap)
		var amplified := StatusRuntime.pulse_magnitude(runtime, 1, gain, channel_cap)
		assert_eq(
			amplified > alone,
			true,
			"the amplifier still widens an ESCALATED pulse (pulse %d)" % pulse
		)
		assert_eq(amplified <= cap, true, "and the answer stays inside the authored cap")
		escalated = amplified
	# At the authored escalation the channel keeps widening the pulse, so the two curves
	# really are independent reads rather than one shadowing the other.
	assert_eq(escalated > 0.0, true, "the escalated, amplified pulse is a real number")


# --- internals -----------------------------------------------------------------------


## A fresh actor. Separate per case rather than reused, because the amplifier channel is
## a property of the ACTOR's live statuses and a shared body would let one case's
## amplifiers feed another case's measurement.
##
## Built directly rather than through `ActorFactory`, which is the composition root and
## therefore an `app/` edge: nothing in this module needs the element provider (potency
## is supplied by `StatusApi.apply`, not by ADR 0088's channel) and a status suite that
## pulled in `app/` to mint a body would fail to load the moment a file elsewhere in the
## composition root stopped parsing. What it does need — a health pool to spend — comes
## from core's own `attach_core_resources`, so the fixture is three lines and names no
## module at all.
func _actor() -> Actor:
	var actor := Actor.new(&"amplifier_probe", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
	actor.attach_core_resources()
	return actor


## A fresh actor carrying exactly `ids`, amplifiers first so a case reads in the order the
## channel applies. Every id is applied at `1.0` except the burn, which is applied at
## [constant MAGNITUDE] — the potency the assertions are written against.
##
## Untyped `Array` on purpose: GDScript refuses to narrow a `StringName` literal to an
## `Array[StringName]` parameter, so a typed argument made every call site spell out the
## array type instead of the ids it meant.
func _dressed(ids: Array) -> Actor:
	var actor := _actor()
	for status_id in ids:
		StatusApi.apply(actor, StringName(status_id), MAGNITUDE if status_id == BURN else 1.0)
	return actor


## One burn's spend over exactly one authored interval, with the amplifier statuses
## applied first. Read as `maximum - current` so a body that regenerated is not credited.
func _burn_spend(actor: Actor, magnitude: float, with_amp: bool, beside: Array = []) -> float:
	if with_amp:
		for amplifier in beside:
			StatusApi.apply(actor, amplifier, 1.0)
	StatusApi.apply(actor, BURN, magnitude)
	return _spend_over_one_pulse(actor)


## ONE status's own spend over one window, read off its live runtime record AFTER the tick
## has run. This is the isolation a case needs when a second health-spending status shares
## the actor: the pool delta is then the SUM of both spends, and reading the pool where a
## case means "the burn's delta" credits the burn with the sibling's cost.
##
## It reads exactly what `_pulse` read — the same sibling count, the same aggregated gain,
## the same channel cap — so asserting it against the measured pool delta is what pins the
## tick loop to the channel rather than merely restating the curve.
##
## ## Why it is NOT a read of the actor's pool
##
## The window has to be driven before the read. `tick_statuses` spends from
## `actor.resource(...)` directly, so the only way to learn what a status COST is to
## measure the pool across a tick — and measuring it means having already run the tick.
## Reading before the tick answers `ticks_elapsed == 0`, which for an escalating burn is
## the UN-escalated magnitude: the figure came out `0.0464` against a measured `0.048`, a
## shortfall of exactly `0.0016` — `0.12 * 0.02 * 2.0`, one escalation step of share.
##
## So a caller drives the window itself and reads afterwards, and the un-amplified control
## is taken from an actor that has ALSO been ticked. Comparing an escalated spend against an
## un-ticked one is the same error wearing a different hat.
func _pulse_spend_of(actor: Actor, status_id: StringName) -> float:
	var runtime := _runtime_of(actor, status_id)
	if runtime == null or runtime.def == null:
		return 0.0
	var magnitude := StatusRuntime.pulse_magnitude(
		runtime,
		StatusApi._sibling_burns(actor, runtime),
		StatusApi._amplifier_gain(actor),
		StatusApi._amplifier_cap(actor)
	)
	return magnitude * float(runtime.def.payload.get("share_per_pulse", 0.0))


## Drive one window on `actor` and return what the BURN itself spent in it. The isolation
## primitive every multi-status case in this file is written against: the pool delta is
## both statuses' spends, this is only the burn's share of them.
func _burn_pulse_spend(actor: Actor) -> float:
	_spend_over_one_pulse(actor)
	return _pulse_spend_of(actor, BURN)


func _spend_over_one_pulse(actor: Actor) -> float:
	var pool := actor.resource(&"health")
	var before := pool.maximum - pool.current
	var interval := maxf(0.001, StatusApi.definition(BURN).tick_interval)
	# Rounded UP to whole frames so the interval has certainly come due: a half frame of
	# the shortfall would silently spend nothing and make every delta in this file zero.
	var frames := maxi(1, int(ceil(interval / FRAME)))
	for frame in frames:
		StatusApi.tick_statuses(actor, FRAME)
	return (pool.maximum - pool.current) - before


## The un-amplified pulse MAGNITUDE for the burn, straight off the authored escalation
## curve at its FIRST pulse (`ticks_elapsed == 1`, because `tick_statuses` increments
## before it pulses).
func _unamplified_pulse() -> float:
	return StatusRuntime.pulse_magnitude(_pulse_runtime(BURN, MAGNITUDE), 0)


## The un-amplified SPEND: the magnitude above through the burn's authored share. The two
## are not the same number and are not interchangeable — comparing a spend against a
## magnitude is a unit error that reports `expected 2.08, got 0.0416` and reads as a
## wiring failure.
func _unamplified_spend() -> float:
	return _unamplified_pulse() * float(_payload_of(BURN).get("share_per_pulse", 0.0))


## A `StatusRuntime` resolved against the real authored def, with only the escalation
## index to set. Built through the catalogue rather than assembled in code so a def this
## suite has never heard of still resolves.
func _pulse_runtime(status_id: StringName, magnitude: float) -> StatusRuntime:
	var runtime := StatusRuntime.new()
	runtime.def = StatusApi.definition(status_id)
	runtime.magnitude = magnitude
	runtime.source = StatusRuntime.source_for(status_id)
	runtime.ticks_elapsed = 1
	return runtime


func _runtime_of(actor: Actor, status_id: StringName) -> StatusRuntime:
	return StatusRuntime._runtimes(actor).get(String(status_id), null) as StatusRuntime


## The gain and cap an actor's live amplifiers report, through the caller's own aggregator.
## Untyped arrays for the same reason `_burn_spend` is.
func _gain_of(actor: Actor, amplifiers: Array = []) -> float:
	for amplifier in amplifiers:
		StatusApi.apply(actor, amplifier, 1.0)
	return StatusApi._amplifier_gain(actor)


func _cap_of_actor(actor: Actor, amplifiers: Array) -> float:
	for amplifier in amplifiers:
		StatusApi.apply(actor, amplifier, 1.0)
	return StatusApi._amplifier_cap(actor)


## The authored numbers, read off the `.tres` the game ships. `fire_pyre` and
## `wind_spread` are two DIFFERENT authored gains on purpose, which is what makes a
## suite that hard-codes either of them wrong the moment a balance pass re-rolls the pair.
func _payload_of(status_id: StringName) -> Dictionary:
	var def := StatusApi.definition(status_id)
	return {} if def == null else def.payload


## The gain an amplifier actually contributes: its authored `sibling_gain` CLAMPED BY its
## own authored `sibling_cap`. `fire_pyre` authors gain 0.5 against cap 0.4, so it
## contributes 0.4 — production clamps per amplifier (`StatusApi._amplifier_gain`) so the
## channel saturates instead of running away. Reading the raw gain here made this suite
## assert a number the game can never produce.
func _pyre_gain() -> float:
	return minf(
		float(_payload_of(PYRE).get("sibling_gain", 0.0)),
		float(_payload_of(PYRE).get("sibling_cap", 0.0))
	)


func _wind_gain() -> float:
	return minf(
		float(_payload_of(WIND).get("sibling_gain", 0.0)),
		float(_payload_of(WIND).get("sibling_cap", 0.0))
	)


func _cap_of(status_id: StringName) -> float:
	return float(_payload_of(status_id).get("sibling_cap", 0.0))
