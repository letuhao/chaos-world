class_name ItemWorkbenchFight
extends ItemWorkbenchReadout

## The composition root's FIGHT half (ADR 0197): the `FightLoop` this root owns and the
## five verbs it hands the fight page.
##
## ## Why this is a base script and not a set of `ItemWorkbenchApp` methods
##
## `item_workbench_app.gd` is at 972 lines against a 1000-line ceiling, and ADR 0197's
## five injected verbs plus a purge arm would have put it over. This is the third reason to
## change, so the third file in the chain (`AGENTS.md`, "one module = one reason to
## change") — and the concern is separable: everything below is about a CONTEST, while the
## shell's job is mounting a screen and answering "where is the player".
##
## ## Why inheritance and not delegation
##
## **The public surface is the contract, and it does not move.** `FightLoop` is held here
## and reached through [method fight_summary], which every caller and every probe reads by
## name; a delegation would leave a caller naming a method that is not on the mounted
## root. As a base class the root still answers every verb, and
## `get_script_method_list()` reports the inherited declarations too, so
## `tests/app/test_screen_reachability.gd` still sees the whole door surface.
##
## ## Why the loop is REPLACED rather than re-pointed on a rebirth
##
## `adopt_actor` swaps the hero on a body that fell (ADR 0130). A `FightLoop` carried
## across that swap would hold the DEAD body's opponent, its blow tally and the seconds it
## had aged — and a reborn hero would open a fight already part-way through the last one's.
## [method adopt_actor_fight] therefore builds a fresh loop, the same rule `bind_readout_drill`
## follows for the drill's clock (ADR 0195): the accumulator belongs to the body that
## earned it.
##
## ## Why the fight's own clock rides the drill's, not a new one
##
## `StatusLoop` holds ONE actor, so a fight cannot be aged by the hero's loop (which would
## reset the hero's collapse window every frame) nor by a second frame driver
## (`tests/app/test_status_clock.gd` pins those). So the fight's age is passed DOWN by
## whoever ages it — the screen's own `act_age` verb, or a caller — and this file never
## ticks. That is ADR 0106's rule restated: the game has one clock and it is not this one.

## The loop this root is currently holding. Null before a hero is adopted.
##
## **A field and not a lazy getter**, because the loop's state is a CONTEST: a getter that
## minted one on first read would hand two readers two fights.
var _fight: FightLoop = null
## The opponent's status clock, and the body it ages (ADR 0197).
##
## ## Why this is a SECOND `StatusLoop` rather than the hero's
##
## `StatusLoop` is a `RefCounted` holding ONE actor, so a fight's opponent cannot ride
## the hero's loop without either rebuilding it every frame (resetting the hero's collapse
## window every frame) or redesigning the wire ADR 0106 exists to keep singular. So it is
## a second INSTANCE, aged by the root's own frame — which is NOT a new clock: one more
## call on the one frame, handed that frame's own delta, and skipped when no fight is
## live. The same allowance ADR 0195 granted the readout's drill.
##
## **The fight's own RATE is not here.** `FightLoop` has no `tick` by design: its cooldown
## is a countdown the CALLER ages through `fight_verbs`'s `age` verb, so nothing in this
## chain advances a fight behind the player's back. What this clock ages is the fight's
## CONSEQUENCES — ADR 0070's wound decay, ADR 0071's rupture bleed and sea collapse.
var _fight_loop: StatusLoop = null
var _fight_body: Actor = null


## Adopt `hero` as the fighter, building the loop that holds it. Called from the root's
## `adopt_actor` and from `_build_actor`, so a fresh boot and a rebirth take the same path
## and a reborn hero never inherits a dead body's opponent.
func adopt_fight(hero: Actor) -> void:
	_fight = FightLoop.new(hero)


## The loop this root is holding, or null before a hero exists. A probe and the route arm
## both ask through this rather than through the field, so there is one answer to "is
## there a fight program" and it cannot be a stale `has_method` guess.
func fight_loop() -> FightLoop:
	return _fight


## The fight as `FightLoop.summary()` publishes it, or `{}`. The one read the page and
## every probe share, so a report can never describe a different fight than the one the
## page is showing.
func fight_summary() -> Dictionary:
	if _fight == null:
		return {}
	return _fight.summary()


## The five verbs the fight page is handed, as ADR 0143's bridge. `app/` is a
## `PRIVATE_UNIT`, so `ui/` may neither hold a `FightLoop` nor mint an opponent — this
## dictionary is the only door between them, and every slot is a plain `Callable` so the
## screen needs no type at all.
##
## **`read` is a verb rather than the summary's being handed over** so the page always
## asks for the CURRENT fight rather than holding a snapshot taken at mount time. A
## snapshot is how a readout ends up describing a fight that has already been decided.
func fight_verbs() -> Dictionary:
	if _fight == null:
		return {}
	return {
		"begin": Callable(self, "_fight_begin"),
		"exchange": Callable(self, "_fight_exchange"),
		"age": Callable(self, "_fight_age"),
		"disengage": Callable(self, "_fight_disengage"),
		"read": Callable(self, "fight_summary"),
	}


## The fight's own status clock, and the bodies it ages. `FightLoop` holds no clock by
## design (see the class docblock), so ageing a fight's CONSEQUENCES — the wound decay, the
## rupture bleed, the sea collapse — is the SAME `StatusLoop` a readout drill uses, pointed
## at whichever body is in the fight.
##
## Rebuilt rather than re-attached whenever the target changes, for `StatusLoop.attach`'s
## own stated reason: the collapse window belongs to the sea that earned it.
func tick_fight(delta: float) -> void:
	if _fight == null or delta <= 0.0:
		return
	var opponent := _fight.opponent()
	if opponent == null:
		return
	if _fight_loop == null or _fight_body != opponent:
		_fight_loop = StatusLoop.new(opponent)
		_fight_body = opponent
	_fight_loop.tick(delta)


## Mount the fight page's two seams. Called from the shell's one `ROUTE_FIGHT` arm, which
## is the only place a screen is bound to this root.
##
## ## Why this whole arm was MISSING, and what it cost
##
## `screen_routes.gd` DECLARED the `fight` route, so a player could navigate to the page,
## and `_bind_route_screen` had no arm for it. Every verb therefore stayed the empty
## `Callable` `bind_fight` defaults to, and `act_start` answered `no_fight_seam` on every
## press forever. The loop, the verbs, the panel and the route all existed; nothing had
## ever joined them. The page was reachable and inert — which is why "the fight loop is
## BUILT" and "it runs" were separate claims.
##
## ## Why `adopt_fight` runs here and not only from `_build_actor`
##
## A fresh boot adopts its hero in `_build_actor`, but a RESTORED root adopts through
## `restore_actor`. Arming the loop here as well means a restored root mounts a working
## page rather than one of dead buttons, and the call is safe to repeat: it REPLACES the
## loop (the ADR 0130 rule, restated in this file's docblock), and a mount is not a fight
## already in progress.
##
## ## And the purge is the SAME callable `ROUTE_LOOT` hands over
##
## ADR 0089's combat-exit purge is a fact about WHEN a fight is over, this root holds the
## one `StatusLoop` that ages the opponent, and a second callable over the same wire could
## only ever disagree with the first — so the fight page is handed the identical seam.
func bind_fight_screen(screen: Control) -> void:
	adopt_fight(_actor)
	screen.call("bind_fight", fight_verbs())
	screen.call("bind_combat_exit", Callable(self, "_purge_combat_scope"))


# --- The verbs the page is handed --------------------------------------------
#
# Private on purpose: the page and the root both reach them THROUGH the bundle above, so a
# screen cannot call one by a name it guessed and a probe reads one by reflecting the loop.


func _fight_begin() -> Dictionary:
	if _fight == null:
		return {"ok": false, "reason": "no_fight_loop"}
	return _fight.start_fight()


func _fight_exchange() -> Dictionary:
	if _fight == null:
		return {"ok": false, "reason": "no_fight_loop"}
	# **No seed.** A live page passes `null` to the spine, which reads it as "nothing
	# random happens and every strike lands" (ADR 0087's S12) — the same choice
	# `_readout_blow` documents: a whiff and a gut-punch are different events, and a
	# player's own fight must not depend on a generator nobody chose. A reproducible run
	# is a probe's decision, passed in as the seed a caller supplies.
	return _fight.exchange(0)


func _fight_age(seconds: float) -> Dictionary:
	if _fight == null:
		return {"ok": false, "reason": "no_fight_loop"}
	return _fight.age(seconds)


func _fight_disengage() -> Dictionary:
	if _fight == null:
		return {"ok": false, "reason": "no_fight_loop"}
	var result := _fight.disengage()
	# The fight is over, so the clock that was ageing its opponent stops with it. The
	# loop is KEPT so the page can still render the ended fight's two pools, but a
	# corpse that keeps decaying and bleeding is a foe no player is shown.
	_fight_loop = null
	_fight_body = null
	return result
