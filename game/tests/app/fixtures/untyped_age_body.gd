class_name TestAgeUntypedBody
extends Actor

## ## A TEST FIXTURE, not a shipped body: the ONLY way to reach `SoulAge`'s type guard
##
## ADR 0258 §2's field is `var age_years: float`, and `Object.set` coerces to the DECLARED type
## — a `String` becomes `0.0`, a negative becomes `0.0` — so neither is reachable through a real
## `Actor`, and `SoulAge.age_years` could never be observed refusing one. This declares the same
## name as a `Variant`, so the stored value IS the value written and the guard is reachable.
##
## It is a diamond rather than an overlay because a diamond cannot REMOVE the inherited member:
## `AGE_FIELD in actor` is true either way, and it is `actor.get(AGE_FIELD)`'s TYPE that
## `soul_age.gd:95-98` checks. That is also why the fixture cannot carry a body plan — one field,
## one slot — so the lifespan refusal is asserted separately by
## `test_a_body_with_no_body_plan_reads_a_zero_lifespan_and_expires_nobody`.
##
## Nothing in `res://src` may reference this: it lives under `res://tests` and is loaded through
## `res://tests/app/fixtures/`, so it is part of the suite rather than a second way to build a
## body in the game.

## The value this body was handed, kept alongside so a case can assert the guard fired rather
## than only that its own output happened to be a refusal.
var stored_age: Variant = null


func _init(actor_id: StringName, value: Variant) -> void:
	super(actor_id)
	age_years = value
	stored_age = value
