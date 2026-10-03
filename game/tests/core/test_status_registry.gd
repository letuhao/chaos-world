extends TestCase

## ADR 0086: one instance per `(actor, status_id)`, and the three merge modes.
##
## Every case here is a sentence the ADR states, asserted rather than described.
## The two that matter most are the two that would be tempting to get subtly
## wrong: REFRESH keeps the STRONGER magnitude (a weak re-application must never
## shorten a strong one), and STACK stops at `magnitude_cap` rather than growing
## forever.

var _merged: Array[StringName] = []
var _added: Array[StringName] = []
var _removed: Array[StringName] = []
var _ticked: Array[StringName] = []


func setup() -> void:
	_merged = []
	_added = []
	_removed = []
	_ticked = []


func _on_added(status_id: StringName) -> void:
	_added.append(status_id)


func _on_merged(status_id: StringName, _outcome: StringName, _stacks: int) -> void:
	_merged.append(status_id)


func _on_removed(status_id: StringName) -> void:
	_removed.append(status_id)


func _on_ticked(status_id: StringName, _magnitude: float) -> void:
	_ticked.append(status_id)


## An actor with every status signal recorded, so a merge is as observable as an
## expiry — the ADR requires a stacking change to be visible, not just an answer.
func _watched() -> Actor:
	var actor := Actor.new(&"hero")
	actor.status_added.connect(_on_added)
	actor.status_merged.connect(_on_merged)
	actor.status_removed.connect(_on_removed)
	actor.status_ticked.connect(_on_ticked)
	return actor


func _outcome(answer: Dictionary) -> StringName:
	return StringName(answer.get(&"outcome", &""))


## A status with an authored lever, so a test about duration or magnitude is not
## also quietly asserting a flat tax (ADR 0075).
func _levered(id: StringName, remaining: float, magnitude: float) -> StatusEffect:
	var status := StatusEffect.new(id, remaining)
	status.magnitude = magnitude
	status.mitigation_tags.append(&"gear")
	return status


# --- the three merge modes -----------------------------------------------------


func test_refresh_keeps_the_longer_duration_and_the_stronger_magnitude() -> void:
	# "a weak re-application never shortens a strong one" — the asymmetry is the
	# rule, so the weak re-application is the one asserted. The held instance is
	# read out of the array rather than assumed, because which object survives is
	# the registry's business and the test must not encode an accident.
	var actor := _watched()
	actor.add_status(_levered(&"immolation", 5.0, 10.0))
	var weak := _levered(&"immolation", 30.0, 2.0)
	weak.stacking = StatusEffect.Stacking.REFRESH
	var answer := actor.add_status(weak)
	var held := actor.statuses[0]
	assert_eq(_outcome(answer), StatusRegistry.REFRESHED, "reported as refreshed")
	assert_eq(bool(answer.get(&"ok", false)), true, "a merge is not a refusal")
	assert_almost_eq(held.remaining, 30.0, "took the longer duration")
	assert_almost_eq(held.magnitude, 10.0, "did NOT take the weaker magnitude")
	assert_eq(actor.statuses.size(), 1, "still one instance")


func test_refresh_takes_the_stronger_magnitude_from_the_incoming_side() -> void:
	# The other direction: a stronger re-application raises a weak held magnitude.
	var actor := _watched()
	actor.add_status(_levered(&"immolation", 30.0, 2.0))
	actor.add_status(_levered(&"immolation", 5.0, 10.0))
	var held := actor.statuses[0]
	assert_almost_eq(held.magnitude, 10.0, "took the stronger magnitude")
	assert_almost_eq(held.remaining, 30.0, "kept the longer duration")


func test_stack_adds_magnitudes_and_counts_the_stack() -> void:
	var actor := _watched()
	actor.add_status(_levered(&"pyre", 5.0, 3.0))
	var again := _levered(&"pyre", 5.0, 4.0)
	again.stacking = StatusEffect.Stacking.STACK
	var answer := actor.add_status(again)
	var held := actor.statuses[0]
	assert_eq(_outcome(answer), StatusRegistry.STACKED, "reported as stacked")
	assert_almost_eq(held.magnitude, 7.0, "magnitudes added")
	assert_eq(held.stacks, 2, "two applications")
	assert_eq(actor.statuses.size(), 1, "a stack is one instance, not two entries")


func test_stack_stops_at_the_magnitude_cap() -> void:
	# Linear addition is deliberate (`_buckets()` sums FLAT and PERCENT linearly
	# per stat), so the cap is the ONLY thing bounding it. Without one a repeated
	# application is unbounded, which is the 1024x failure ADR 0086 names.
	var actor := _watched()
	for _i in 3:
		var pyre := _levered(&"pyre", 5.0, 6.0)
		pyre.magnitude_cap = 10.0
		pyre.stacking = StatusEffect.Stacking.STACK
		actor.add_status(pyre)
	var held := actor.statuses[0]
	assert_almost_eq(held.magnitude, 10.0, "capped, not 18.0")
	assert_eq(held.stacks, 3, "every application still counted")
	assert_eq(actor.statuses.size(), 1, "still one instance")


func test_a_cap_of_zero_means_uncapped() -> void:
	# A def that authors no cap compounds rather than resolving to nothing; the
	# silent clamp to zero is the worse failure.
	var actor := _watched()
	for _i in 2:
		var pyre := _levered(&"pyre", 5.0, 6.0)
		pyre.stacking = StatusEffect.Stacking.STACK
		actor.add_status(pyre)
	assert_almost_eq(actor.statuses[0].magnitude, 12.0, "no authored cap, no clamp")


func test_replace_overwrites_both_duration_and_magnitude() -> void:
	var actor := _watched()
	actor.add_status(_levered(&"curse", 60.0, 10.0))
	var weak := _levered(&"curse", 2.0, 1.0)
	weak.stacking = StatusEffect.Stacking.REPLACE
	var answer := actor.add_status(weak)
	assert_eq(_outcome(answer), StatusRegistry.REPLACED, "reported as replaced")
	assert_almost_eq(weak.magnitude, 1.0, "magnitude overwritten even downward")
	assert_almost_eq(weak.remaining, 2.0, "duration overwritten")
	assert_eq(actor.statuses.size(), 1, "still one instance")


func test_replace_hands_over_the_new_instance_rather_than_overwriting_the_old() -> void:
	# A REPLACE def has its own data, so overwriting a held `PregnancyStatus`
	# in place would leave a state machine wearing another status's numbers. The
	# array holds exactly what the caller applied.
	var actor := _watched()
	var machine := PregnancyStatus.new(&"pregnancy")
	actor.add_status(machine)
	var incoming := _levered(&"pregnancy", 5.0, 3.0)
	incoming.stacking = StatusEffect.Stacking.REPLACE
	actor.add_status(incoming)
	assert_eq(actor.statuses[0], incoming, "the array holds the incoming instance")
	assert_eq(actor.statuses.size(), 1, "still one instance")


func test_the_incoming_stacking_mode_is_the_one_that_applies() -> void:
	# A def declares how IT stacks onto what is already there, so applying a
	# STACK def twice stacks twice rather than refreshing on the second pass.
	var actor := _watched()
	var first := _levered(&"pyre", 5.0, 3.0)
	first.stacking = StatusEffect.Stacking.STACK
	actor.add_status(first)
	var second := _levered(&"pyre", 5.0, 3.0)
	second.stacking = StatusEffect.Stacking.STACK
	actor.add_status(second)
	assert_almost_eq(first.magnitude, 6.0, "the def's own mode decided, twice")


# --- one instance per (actor, status_id) ---------------------------------------


func test_re_application_never_grows_the_array() -> void:
	# The invariant the whole registry exists for: `Actor.statuses` is read
	# directly by four modules, so an array that grew on re-application would make
	# every one of them count the same status twice.
	var actor := _watched()
	for _i in 5:
		actor.add_status(_levered(&"immolation", 5.0, 1.0))
	assert_eq(actor.statuses.size(), 1, "five applications, one entry")
	assert_eq(actor.has_status(&"immolation"), true, "held")


func test_distinct_ids_are_distinct_instances() -> void:
	var actor := _watched()
	actor.add_status(_levered(&"immolation", 5.0, 1.0))
	actor.add_status(_levered(&"sunder", 5.0, 1.0))
	assert_eq(actor.statuses.size(), 2, "two ids, two entries")


func test_the_registry_holds_the_actors_own_array() -> void:
	# `FertilityApi.advance` erases `actor.statuses` directly and
	# `EnvironmentField._status` reads it directly, so the registry must not own a
	# shadow copy that goes stale the moment either runs.
	var actor := _watched()
	actor.statuses.append(_levered(&"placed_by_hand", 5.0, 1.0))
	assert_eq(actor.has_status(&"placed_by_hand"), true, "the registry sees a direct append")


# --- what the answer says ------------------------------------------------------


func test_add_status_reports_what_it_did() -> void:
	# The three live callers all read the outcome, and `StatusApply` reads `ok`
	# and `reason` — so the answer is that shape, not a bare bool.
	var actor := _watched()
	var first := actor.add_status(_levered(&"immolation", 5.0, 1.0))
	assert_eq(_outcome(first), StatusRegistry.APPLIED, "a first application is applied")
	assert_eq(String(first.get(&"status_id", "")), "immolation", "names the status")
	assert_eq(int(first.get(&"stacks", 0)), 1, "one stack")
	assert_eq(String(first.get(&"reason", "")), "", "no reason on a commit")
	var second := _levered(&"immolation", 5.0, 1.0)
	second.stacking = StatusEffect.Stacking.STACK
	var answer := actor.add_status(second)
	assert_eq(_outcome(answer), StatusRegistry.STACKED, "a merge is named, not blank")
	assert_eq(bool(answer.get(&"ok", false)), true, "a merge reports ok")


func test_add_status_refuses_a_null_or_an_id_less_status() -> void:
	var actor := _watched()
	var nothing := actor.add_status(null)
	assert_eq(_outcome(nothing), StatusRegistry.REFUSED, "a null status is refused")
	assert_eq(bool(nothing.get(&"ok", true)), false, "a refusal reports not-ok")
	assert_ne(String(nothing.get(&"reason", "")), "", "a refusal names a reason")
	var nameless := actor.add_status(StatusEffect.new(&"", 5.0))
	assert_eq(_outcome(nameless), StatusRegistry.REFUSED, "an id-less status is refused")
	assert_eq(actor.statuses.size(), 0, "nothing was held")


func test_a_merge_is_observable_and_still_emits_added() -> void:
	# A stacking change must be as visible as an expiry, and `status_added` must
	# keep firing the way it did before ADR 0086 or every existing listener breaks.
	var actor := _watched()
	actor.add_status(_levered(&"immolation", 5.0, 1.0))
	var again := _levered(&"immolation", 5.0, 1.0)
	again.stacking = StatusEffect.Stacking.STACK
	actor.add_status(again)
	assert_eq(_added.size(), 2, "added fires for the application and the merge")
	assert_eq(_merged.size(), 1, "merged fires only for the merge")
	assert_eq(_merged[0], &"immolation", "and names the status")


# --- expiry and interval -------------------------------------------------------


func test_expiry_removes_the_status_and_emits() -> void:
	var actor := _watched()
	actor.add_status(_levered(&"burn", 0.5, 1.0))
	actor.tick_statuses(0.6)
	assert_eq(actor.has_status(&"burn"), false, "expired")
	assert_eq(actor.statuses.size(), 0, "pruned")
	assert_eq(_removed.size(), 1, "removed emitted")
	assert_eq(_removed[0], &"burn", "and names the status")


func test_a_permanent_status_never_expires_or_ticks() -> void:
	# The blessing and the pregnancy are timers, not clocks: with no interval
	# authored there is nothing to pay out, however long the world runs.
	var actor := _watched()
	actor.add_status(_levered(&"heavenly_blessing", -1.0, 1.0))
	actor.tick_statuses(100000.0)
	assert_eq(actor.has_status(&"heavenly_blessing"), true, "permanent survives")
	assert_eq(_ticked.size(), 0, "and never ticked")


func test_a_dot_ticks_on_its_interval() -> void:
	var actor := _watched()
	var dot := _levered(&"immolation", 10.0, 2.5)
	dot.kind = StatusEffect.Kind.DOT
	dot.tick_interval = 1.0
	actor.add_status(dot)
	actor.tick_statuses(0.4)
	assert_eq(_ticked.size(), 0, "no pulse before the interval")
	actor.tick_statuses(0.6)
	assert_eq(_ticked.size(), 1, "one pulse at the interval")
	actor.tick_statuses(4.0)
	assert_eq(_ticked.size(), 5, "four more pulses for four more intervals")
	assert_almost_eq(dot.tick_elapsed, 0.0, "the accumulator carries no leftover")


func test_a_dot_does_not_spend_a_pool_and_reads_no_clock() -> void:
	# ADR 0086: a status is DATA and the module that applies it turns magnitude
	# into an effect. So core writes no health, and the interval is driven purely
	# by the caller's delta — a DOT's pulse count is a function of the deltas, so
	# the same inputs replay identically.
	var actor := _watched()
	actor.attach_core_resources()
	var pool := actor.resource(&"health")
	var health := pool.current
	var dot := _levered(&"immolation", 10.0, 2.5)
	dot.kind = StatusEffect.Kind.DOT
	dot.tick_interval = 1.0
	actor.add_status(dot)
	actor.tick_statuses(6.0)
	assert_almost_eq(pool.current, health, "core never subtracts health")
	assert_eq(_ticked.size(), 6, "six intervals, six pulses")
	assert_almost_eq(dot.magnitude, 2.5, "the magnitude is unchanged by ticking")


func test_a_dot_with_no_interval_never_ticks() -> void:
	var actor := _watched()
	var dot := _levered(&"immolation", 10.0, 2.5)
	dot.kind = StatusEffect.Kind.DOT
	actor.add_status(dot)
	actor.tick_statuses(1000.0)
	assert_eq(_ticked.size(), 0, "an interval-less status pays nothing")


func test_ticking_without_a_delta_is_not_a_clock_read() -> void:
	# delta <= 0 does nothing at all, which is what proves no wall clock was read:
	# a clock-driven tick would have moved on its own between these two calls.
	var registry := StatusRegistry.new()
	var dot := _levered(&"immolation", 10.0, 1.0)
	dot.tick_interval = 1.0
	registry.apply(null, dot)
	assert_eq((registry.tick(null, 0.0).ticks as Array).size(), 0, "a zero delta ticks nothing")
	assert_eq((registry.tick(null, -5.0).ticks as Array).size(), 0, "nor a negative one")


# --- the subclass precedent ----------------------------------------------------


func test_the_pregnancy_state_machine_still_runs_its_four_stages() -> void:
	# The regression guard for ADR 0086's "a subclass stays legal for a machine".
	# `PregnancyStatus` overrides no constructor and adds no timer of its own, so
	# a merge rule that mutated or swapped it would show up here.
	var actor := _watched()
	var status := PregnancyStatus.new(&"pregnancy")
	status.partner_id = &"father"
	status.partner_base = {Stat.PHYSIQUE: 20.0}
	actor.add_status(status)
	var held := actor.statuses[0]
	# The instance the caller handed in is the one the actor holds, which is what
	# lets the fertility module keep mutating it in place through its own facade.
	assert_eq(held, status, "held by reference, not copied")
	assert_eq(actor.has_status(&"pregnancy"), true, "held")
	assert_eq(actor.statuses.size(), 1, "one instance")
	assert_eq(held.stage, PregnancyStatus.Stage.CONCEIVED, "conceived")
	held.stage = PregnancyStatus.Stage.GESTATING
	assert_eq(held.is_gestating(), true, "gestating")
	held.stage = PregnancyStatus.Stage.LABOR
	held.progress = 1.0
	assert_eq(held.stage, PregnancyStatus.Stage.LABOR, "labor")
	held.stage = PregnancyStatus.Stage.POSTPARTUM
	held.recovery_remaining = 10.0
	assert_eq(held.is_recovering(), true, "postpartum")
	# Its timer is never set, so `tick_statuses` must not prune it out from under
	# the state machine that owns it.
	actor.tick_statuses(1000.0)
	assert_eq(actor.has_status(&"pregnancy"), true, "the machine is not a timer")
