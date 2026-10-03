extends TestCase

## `AcupointSet.busy` — the re-entrancy guard on the acupoint-consuming verbs.
##
## It is VACUOUS in the strict sense and deliberately kept. No caller can observe
## it true: every window that sets it is synchronous (no `await` anywhere in
## `BodyTraining`/`BodyAdvancement`), and every signal that fires *inside* a
## window resolves to `StatsInvalidator.on_changed`, a UI refresh, or a stat
## recompute — none of which re-enters a verb. `Actor.path_advanced` is emitted
## inside the breakthrough window and has zero connections, so it is the vector
## that would make the guard observable if a handler were ever attached.
##
## What it is NOT is a write-only field: the guards read it, and the clear is
## load-bearing. A verb with more than one exit (strengthen has two, the
## breakthrough has three) that forgot one `busy = false` would leave an actor
## permanently unable to cultivate or break through, with no error and a
## save that keeps growing. The tripwire below is the test that would catch it.


func _actor() -> Actor:
	var actor := Actor.new(&"busy_hero", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor)
	BodyTraining.synchronize(actor)
	return actor


func _stock(actor: Actor, def_id: StringName) -> void:
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 99
	ItemsApi.inventory(actor).add(def, 1)


## Every exit that opens or passes through a `busy` window. The refused exits
## are the ones that matter: they return from *inside* the window, so they carry
## the responsibility of clearing it.
func test_busy_is_cleared_on_every_return_path() -> void:
	var actor := _actor()
	var points: AcupointSet = actor.component(&"acupoints")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# Refused before any window opens: nothing to clear, but a leaked flag from a
	# previous verb would still be visible here.
	BodyTraining.recover(actor, &"lung")
	assert_eq(points.busy, false, "a no-op recover leaves the set clear")
	BodyAdvancement.try_breakthrough(actor, rng)
	assert_eq(points.busy, false, "a refused breakthrough leaves the set clear")

	# Strengthen opens its window and then refuses on the missing elixir.
	BodyTraining.strengthen(actor, &"lung")
	assert_eq(points.busy, false, "strengthen without an elixir leaves the set clear")

	# The accepted path: the window runs to completion and must still clear.
	_stock(actor, &"body_qi_refining_channel_elixir")
	assert_eq(BodyTraining.strengthen(actor, &"lung"), true, "the elixir was spent")
	assert_eq(points.busy, false, "an accepted strengthen leaves the set clear")

	# Recover's window, refused at the item and then accepted.
	_stock(actor, &"body_qi_refining_recovery_elixir")
	BodyCultivationApi.acupoints(actor)[0].block()
	assert_eq(BodyTraining.recover(actor, &"lung"), true, "the recovery was spent")
	assert_eq(points.busy, false, "an accepted recover leaves the set clear")


## A set left busy refuses every guarded verb. Written by hand on purpose: no
## production path can produce this state today, so this asserts the guard is
## wired to the field, not that the guard is reachable.
func test_a_busy_set_refuses_every_guarded_verb() -> void:
	var actor := _actor()
	var points: AcupointSet = actor.component(&"acupoints")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	_stock(actor, &"body_qi_refining_channel_elixir")
	_stock(actor, &"body_qi_refining_recovery_elixir")
	points.busy = true
	assert_eq(BodyTraining.cultivate(actor, 10.0), false, "cultivate refused")
	assert_eq(BodyTraining.strengthen(actor, &"lung"), false, "strengthen refused")
	assert_eq(BodyTraining.recover(actor, &"lung"), false, "recover refused")
	assert_eq(BodyAdvancement.try_breakthrough(actor, rng), false, "breakthrough refused")
	# Refused before consuming anything, so the stocked items must survive.
	assert_eq(
		ItemsApi.has_item(actor, &"body_qi_refining_channel_elixir"), true, "elixir not spent"
	)
	assert_eq(
		ItemsApi.has_item(actor, &"body_qi_refining_recovery_elixir"), true, "recovery not spent"
	)
