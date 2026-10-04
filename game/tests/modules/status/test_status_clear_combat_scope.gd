extends TestCase

## `StatusApi.clear_combat_scope` is called by PRODUCTION (`app/status_loop.gd`
## `exit_combat`, the combat-exit purge) and by NO test. This suite drives the
## facade verb itself, so the scope split the docstring claims is a measured
## fact rather than prose.
##
## ## Why this is not already covered
##
## `modules/status/test_status_cultivation_reach.gd` proves a cultivation
## blessing SURVIVES a combat exit -- but it reaches the purge through its own
## helper, so a mutation that emptied the returned list, or purged cultivation
## ids too, could still leave every one of those assertions green. The verb is
## the thing the caller reads: `exit_combat()` returns it verbatim, so "what
## was cleared" is the return value's contract, and nothing asserted it.

## One COMBAT-scope id and one CULTIVATION-scope id, both authored, so the
## assertion is about the SCOPE and not about which ids happen to exist.
## `dark_corrosion` is `scope = combat` with `on_landed_blow = true`, which is
## what ADR 0105 says a landed blow may apply.
const COMBAT_ID := &"dark_corrosion"
const CULTIVATION_ID := &"earth_bulwark"

var _actor: Actor


func setup() -> void:
	# `ActorFactory.build`, not `Actor.new`: the combat scope read walks
	# `actor.statuses` and the status runtime map, and a bare actor carries neither
	# the pools nor the stat providers these statuses modify.
	_actor = ActorFactory.build(&"scoper", {Stat.COMPREHENSION: 30.0})


## A COMBAT status the module owns, so it has a runtime this verb can find.
func _apply_combat() -> String:
	var def := StatusApi.definition(COMBAT_ID)
	assert_ne(def, null, "the probe combat id is authored")
	var applied := StatusApi.apply(_actor, COMBAT_ID, 10.0)
	assert_eq(bool(applied["ok"]), true, "the combat status applied")
	return String(applied.get("id", COMBAT_ID))


func _live() -> Array[String]:
	var out: Array[String] = []
	for status in _actor.statuses:
		out.append(String(status.id))
	return out


## The whole claim: combat scope goes, cultivation scope stays, and the verb
## NAMES what it removed so a screen can report it.
func test_combat_scope_is_cleared_and_cultivation_scope_survives() -> void:
	_apply_combat()
	var cultivation := StatusApi.apply_cultivation(_actor, CULTIVATION_ID)
	assert_eq(bool(cultivation["ok"]), true, "the cultivation blessing applied")
	assert_eq(_live().has(String(COMBAT_ID)), true, "both are live before the purge")
	assert_eq(_live().has(CULTIVATION_ID), true, "the blessing is live before the purge")

	var cleared := StatusApi.clear_combat_scope(_actor)

	assert_eq(_live().has(String(COMBAT_ID)), false, "the combat status is gone")
	assert_eq(_live().has(CULTIVATION_ID), true, "ADR 0089: cultivation scope is never purged")
	assert_eq(
		cleared.has(String(COMBAT_ID)),
		true,
		"and the verb NAMES what it cleared, because exit_combat returns this list verbatim"
	)


## A purge that reported nothing while removing something would leave the
## combat-exit screen silent about a status it just lost.
func test_the_returned_list_is_exactly_what_left_the_actor() -> void:
	var id := _apply_combat()
	var cleared := StatusApi.clear_combat_scope(_actor)
	assert_eq(cleared, [id], "the returned ids are the ones that were removed, and no others")


## The second purge is a no-op and says so. `exit_combat` is called on every
## combat end, so a verb that re-reported the same ids forever would make a
## screen claim a status was cleared twice.
func test_a_second_purge_reports_nothing_because_nothing_is_left() -> void:
	_apply_combat()
	StatusApi.clear_combat_scope(_actor)
	var again := StatusApi.clear_combat_scope(_actor)
	assert_eq(again, [], "a purge with nothing in scope reports nothing")


## The null guard, because `exit_combat` reads a `_actor` a screen may not have set.
func test_a_null_actor_clears_nothing_rather_than_raising() -> void:
	assert_eq(StatusApi.clear_combat_scope(null), [], "no actor, nothing cleared")
