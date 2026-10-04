extends TestCase

## ADR 0186 + ADR 0089: what an actor's statuses do across a save.
##
## ## Why this file asserts the OPPOSITE of what it used to
##
## An earlier `test_status_round_trip.gd` asserted that statuses PERSIST through an actor
## round trip, citing "a save that lies". That claim contradicts ADR 0089 (statuses are
## session-only, no `statuses` key in `Actor.to_dict`) and ADR 0186 (the tribulation
## blessing's once-guard is session-only, so a saved actor is re-payable). Both cannot
## hold, which is DEF-0150. ADR 0186 rules: statuses stay session-only, and the CORRECT
## save contract is that nothing a player earned is silently deleted — the tribulation's
## permanent blessing is RE-EARNABLE after a load because its once-guard does not ride the
## save. So this file asserts that contract, not persistence.
##
## ## The rule this file pins
##
## - An actor's STATUSES do not ride the save (ADR 0089). A restored actor carries none.
## - A save written before a `statuses` key existed still loads, and an untrusted payload
##   carrying one is IGNORED rather than refused or half-applied.
## - The tribulation blessing — a PERMANENT reward — is not silently lost: its once-guard
##   is session-only, so a survived tribulation is re-payable after a load (ADR 0186,
##   DEF-0235). The full producer-side proof is in `test_status_blessing_save.gd`; the
##   claim here is that the PERSISTENCE layer does not reintroduce a guard that blocks it.


func setup() -> void:
	expect_assertions(2)


func _status(id: StringName, remaining: float) -> StatusEffect:
	var status := StatusEffect.new(id, remaining)
	status.magnitude = 12.5
	status.kind = StatusEffect.Kind.CONTROL
	status.scope = StatusEffect.Scope.CULTIVATION
	status.mitigation_tags.append(&"purge")
	status.source = &"test"
	status.stacks = 2
	status.tick_elapsed = 1.5
	status.payload = {"note": "kept"}
	return status


# --- statuses are session-only (ADR 0089) -----------------------------------------


func test_a_status_does_not_survive_an_actor_round_trip() -> void:
	# The contract ADR 0089 sets and ADR 0186 leaves in place: a status is a session fact.
	# The restored actor carries NONE of it, because the payload emits no `statuses` key.
	var actor := Actor.new(&"carrier", {})
	actor.add_status(_status(&"bound_mark", 30.0))
	var payload := actor.to_dict()
	assert_eq(payload.has("statuses"), false, "the actor payload emits NO statuses key (ADR 0089)")
	var restored := Actor.from_dict(payload)
	assert_eq(restored != null, true, "the actor round-trips")
	assert_eq(restored.statuses.size(), 0, "and carries no status — a status is session-only")
	assert_eq(restored.has_status(&"bound_mark"), false, "the session status is gone after a load")


func test_an_actor_with_no_statuses_still_round_trips() -> void:
	var actor := Actor.new(&"plain", {})
	var restored := Actor.from_dict(actor.to_dict())
	assert_eq(restored != null, true, "a plain actor loads")
	assert_eq(restored.statuses.size(), 0, "with no statuses, as expected")


# --- compatibility: a legacy or untrusted payload never fails the load ------------


func test_a_save_written_before_a_statuses_key_still_loads() -> void:
	# Absence must mean "no statuses", never a failure — this is the day-one compatibility
	# case and it still holds.
	var restored := Actor.from_dict({"id": "legacy", "base": {}})
	assert_eq(restored != null, true, "a legacy payload loads")
	assert_eq(restored.statuses.size(), 0, "and carries no statuses")


func test_a_malformed_statuses_slot_is_ignored_not_fatal() -> void:
	# An older or foreign payload that DOES carry a `statuses` key must be IGNORED, not
	# half-applied and not a load failure: this schema does not read that key (ADR 0089),
	# and `Actor.from_dict` explicitly ignores it rather than refusing.
	var restored := (
		Actor
		. from_dict(
			{
				"id": "wounded",
				"base": {},
				"statuses": [{"no_id_here": true}, "not a dictionary", {"id": "real_one"}],
			}
		)
	)
	assert_eq(restored != null, true, "the actor still loads")
	assert_eq(
		restored.statuses.size(),
		0,
		"and the untrusted slot is ignored entirely — a load never fails on a field it does not read"
	)


# --- the tribulation blessing is not silently lost (ADR 0186, DEF-0235) -------------


func test_a_saved_actor_does_not_carry_the_blessing_once_guard() -> void:
	# The persistence-layer half of ADR 0186. The full producer proof lives in
	# `test_status_blessing_save.gd`; this asserts the layer that would have caused the
	# bug: a `TribulationBlessing.REWARDED_KEY` in `module_data` WOULD be serialized, and
	# that is exactly why the guard moved off `module_data`. Here there is no blessing paid,
	# so the guard must simply be absent from the payload.
	var actor := Actor.new(&"unguarded", {})
	actor.add_status(_status(&"earth_bulwark", -1.0))
	var payload: Variant = JSON.parse_string(JSON.stringify(actor.to_dict()))
	var module_data: Variant = (payload as Dictionary).get("module_data", {})
	assert_eq(
		(
			(typeof(module_data) == TYPE_DICTIONARY)
			and not (module_data as Dictionary).has(String(TribulationBlessing.REWARDED_KEY))
		),
		true,
		"no once-guard rides the saved module_data (ADR 0186), so a load cannot refuse what it lacks"
	)
	var restored := Actor.from_dict(payload as Dictionary)
	assert_eq(restored != null, true, "the actor reloads")
	assert_eq(
		restored.has_status(&"earth_bulwark"),
		false,
		"a permanent blessing is session-only (ADR 0089), and re-earnable, not lost, because its guard is"
	)
