class_name ItemWorkbenchReadout
extends ItemWorkbenchBody

## The composition root's READOUT half: the drill body a reader strikes, the one
## blow it resolves, the bare swing that blow fires, and the companion context row.
##
## ## Why this is a base script and not a set of `ItemWorkbenchApp` methods
##
## Extracted from `item_workbench_app.gd` because that file passed the thousand-line
## ceiling again once the interaction seam and travel wires were added. This is the
## third reason to change and so the third file in the chain (`AGENTS.md`, "one module
## = one reason to change"). The four callables here are one concern: everything the
## combat-readout screen is handed, resolved through the PRODUCTION engine entry
## points rather than a second opinion about them.
##
## ## Why inheritance and not delegation
##
## The shell binds these as `Callable(self, "_readout_blow")` / `Callable(self,
## "_readout_context")` from its `ROUTE_COMBAT_READOUT` arm, and
## `ItemWorkbenchBody._readout_target` caches the drill this class builds. As a base
## class the root still answers every one of them by name and
## `get_script_method_list()` on it reports the inherited declarations, so
## `tests/app/test_screen_reachability.gd` still sees the whole door surface. **No
## method was renamed and no signature changed**: the split is invisible to every
## caller, including the runtime suites that mount the real `ItemWorkbenchApp.tscn`
## and navigate the shipped route (`tests/app/test_readout_wound_ledger_wiring.gd`,
## `tests/ui/test_combat_readout_*.gd`).
##
## ## What stayed behind, and why
##
##   - `_ready`, `_process`, `restore_actor` and `restored_from_save` stayed in the
##     shell. `tests/app/test_status_clock.gd` requires `StatusLoop.new(` and a
##     `func _process(` to appear in `item_workbench_app.gd` and NOWHERE ELSE under
##     `res://src`, and `tests/modules/save/test_cultivation_boot_round_trip.gd`
##     slices that file between the `restore_actor` and `restored_from_save`
##     declarations. Moving them one layer down would have broken both.
##   - The `ROUTE_COMBAT_READOUT` arm stayed in the shell, because a route is a
##     screen mount and the screen stack is the shell's own wiring.
##   - `READOUT_MAGNITUDE` and `READOUT_SHARE` stayed declared on `ItemWorkbenchBody`
##     (they moved there with the attach list); a base class cannot name a subclass's
##     constant, and a subclass cannot back-reference its own base's constant by the
##     `ItemWorkbenchBody.<NAME>` spelling — so the bodies that use them stayed where
##     the constants live. Nothing outside the chain reads either spelling.
##
## Nothing in this file calls the engine through a route the shipped app does not:
## the whole claim of the readout is that what the engine computes is what a player
## sees.


## One drill body, with the three mechanism inputs the shipped player already has. It
## is a body-cultivation actor because that is the one carrying an `acupoints` set, so a
## body technique resolves at a meridian against it rather than reporting "no location
## axis" — the readout's whole claim is that what the engine computes is what a player
## sees, and an input-less target would show less than production does.
##
## ## Why `CombatBoot.install` is here and not one layer up
##
## The enrolment above is only the HALF of what the body needs to be struck. `install` is
## what calls `CombatEngineApi.attach_wounds`, and that call is the ONLY production writer
## of the `body_wounds` component — so without it `CombatEngineApi.wounds_of` answers
## null, `CombatReadoutScreen._wounds_payload` returns `{}`, and
## `CombatReadoutPanel.wounds_text` printed `No meridian carries a wound.` FOREVER, on a
## body that took every hit the reader ever threw at it. `effects[]` is not the wound:
## the row on the panel comes from the LEDGER, and nothing settles the ledger but the
## applier reading a bound one.
##
## The cache in `item_workbench_body.gd:_readout_target` exists precisely so a wound can
## ACCUMULATE — "a reader who re-enters the route strikes the same body twice and can
## watch a wound accumulate". It cannot accumulate without the ledger bound here, so this
## call is what makes that comment true rather than aspirational.
##
## Order matters and is the one `ui_driver.gd:197-201` documents: enrol the paths, THEN
## install — `bind_mechanisms` reads `acupoints` / `sea_of_consciousness` to choose a
## mechanism, and installing first measures every path's inputs as absent. `install` is
## idempotent, so a route re-entry cannot erase a wound earned on the previous visit.
func _build_readout_target() -> Actor:
	var drill := ActorFactory.spawn_inhabitant(&"readout_drills")
	ActorFactory.with_body_cultivation(drill)
	CombatBoot.install(drill)
	return drill


## Resolve one blow for the readout and hand back `CombatOutcome.to_dict()` VERBATIM.
##
## ## Why it is the production entry point and not a private one
##
## `CombatBoot.resolve_hit` is what `_resolve_technique_hit` already calls, so this is
## the same decision the shipped app makes about which mechanism runs and what `ctx.data`
## carries (ADR 0161). A readout that resolved through a different route would be a
## second opinion about the engine rather than a view of it.
##
## The technique is a BARE SWING built by `CombatBoot` for exactly this purpose — there
## is no authored "readout strike", and inventing one in `game/data/techniques/` would
## be authoring content the design does not have. It follows the hero's realm, so the
## numbers on the readout move when the hero's realm moves.
##
## `rng` is null on purpose: a null generator means nothing random happens and every
## attack lands, which is what a readout wants. A screen that reported "0 damage" for a
## miss would teach the reader that a whiff and a gut-punch are the same event.
func _readout_blow(attacker: Actor, defender: Actor) -> Dictionary:
	if attacker == null or defender == null:
		return {}
	var outcome := CombatBoot.resolve_hit(
		attacker, defender, _readout_technique(), CombatEngineApi.tuning(), null
	)
	return outcome.to_dict()


## The bare swing the readout fires: the qi path, so the mechanism is the one the
## installed actor carries, and a magnitude high enough that a wound is reachable in a
## handful of strikes rather than in a session. It is rebuilt per blow and never
## persisted, for the same reason `CombatBoot._swing_def` is: a swing leaves no record.
func _readout_technique() -> TechniqueDef:
	var def := TechniqueDef.new()
	def.path = PathState.QI
	def.magnitude = READOUT_MAGNITUDE
	def.element_share = READOUT_SHARE
	return def


## The readout's companion read: `{band, actor, mechanism}`, all primitives.
##
## ## Why this is ONE callable and not three
##
## `CombatOutcome.to_dict()` decomposes ONE resolved blow. It deliberately carries
## nothing about the roll that was NOT taken, nothing about the attacker, and nothing
## about which mechanism produced the number — those are three different questions from
## three different owners. The prior shape of this wiring took a `strike` callable and a
## `context` callable separately, which put two seams on the same screen for two halves
## of one answer and left the screen unable to say which mechanism fired.
##
## `app/` is the only layer that can answer all three: it names `CombatEngineApi` for
## the band and the stat line, and `CombatBoot.mechanism_for_hit` for the third, because
## **the mechanism is the one fact the READOUT cannot derive** — it is chosen per hit by
## the technique's path, and re-asking it here through a second route would be a second
## opinion about the engine's own decision. It is deliberately the SAME named question
## `_readout_blow` answers internally, so the line a reader sees is the line the blow ran.
##
## ## The band is a SEPARATE roll, and that is the point
##
## `CombatEngineApi.band` rolls again with no generator, so this reports what WOULD be
## drawn rather than what WAS consumed by the blow above. Folding it into `to_dict()`
## would have made the readout claim the engine produced a number it did not — which is
## why it stays its own row and the panel labels it for what it is.
func _readout_context() -> Dictionary:
	return {
		"band": CombatEngineApi.band(_actor, _readout_target(), CombatEngineApi.tuning(), null),
		"actor": CombatEngineApi.summary(_actor),
		"mechanism": CombatBoot.mechanism_for_hit(_actor, _readout_technique()),
	}


# --- The world interaction seam -----------------------------------------------
#
# These live here rather than in the shell for the reason the rest of this file is
# here: they are a CONVERSATION with a screen, not the shell's own bookkeeping.
# `WorldStage.interact` hands every press to an injected callable and had **no
# production caller**, so every press in the shipped game answered
# `{"ok": false, "reason": "no_handler"}` — a body standing in a world with
# nothing to press and nothing to answer.


## THE BOOT WIRE. Why a press OFFERS rather than ACCEPTS, why nothing navigates,
## and why the program is read through the field rather than captured are stated at
## `WorldStage.has_interaction_handler`; the vocabulary a press may carry is
## `_QUEST_BOARD_ALIASES`.
func _install_interaction_handler() -> void:
	WorldStage.set_interaction_handler(Callable(self, "_interact_in_the_world"))


## Answer one press from the world stage. `func(actor, location_id, target_name)
## -> Dictionary`, which is the signature `WorldStage.interact` calls.
func _interact_in_the_world(
	actor: Actor, location_id: StringName, target_name: String
) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor", "target": target_name}
	if _quests == null:
		return {"ok": false, "reason": "no_quest_program", "target": target_name}
	var board := String(_QUEST_BOARD_ALIASES.get(target_name, ""))
	if board.is_empty():
		return {"ok": false, "reason": "not_a_quest_board", "target": target_name}
	# Read the CURRENT ledger rather than a figure remembered at boot: a press is a
	# question about the hero standing there, and a hero who has since taken a quest
	# on must not be offered it again.
	var offered: Array[Dictionary] = _quests.offered()
	var rows: Array[Dictionary] = []
	for view in offered:
		if String(view.get("id", "")) != board:
			continue
		var steps: Array[Dictionary] = []
		for step in QuestApi.steps(actor, StringName(board)):
			(
				steps
				. append(
					{
						"fact": String((step as Dictionary)["fact"]),
						"need": int((step as Dictionary)["need"]),
						"done": bool((step as Dictionary)["done"]),
					}
				)
			)
		(
			rows
			. append(
				{
					"quest_id": board,
					"display_name": String(view.get("display_name", "")),
					"tier": int(view.get("tier", 0)),
					"steps": steps,
				}
			)
		)
	if rows.is_empty():
		return {"ok": false, "reason": "quest_not_offered", "target": target_name}
	return {
		"ok": true,
		"reason": "",
		"target": target_name,
		"location_id": String(location_id),
		"quest_id": board,
		"offered": rows,
		"offered_count": offered.size(),
	}
