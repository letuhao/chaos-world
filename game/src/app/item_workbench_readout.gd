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

## The names a press may carry to mean "show me the quest board", mapped to the quest
## id each one offers. Both are CONTENT names, so a new board is one `.tres` and one
## row here rather than a new branch in the handler — and a name absent from this
## dictionary is refused by name rather than silently doing nothing.
##
## **`quest_board` is an authored inhabited type**, which is what makes it a real press
## target rather than an invented one; `quest` is the same idea spelled as a route. An
## UNKNOWN author may publish no quest at all, so an empty board is a correct answer and
## not a gap. This is a HAND-OVER of what the module offers, never a second offer rule.
##
## ## Why it is declared HERE and not in the shell
##
## [method _interact_in_the_world] below is its ONLY reader in the tree, and a base class
## cannot name a member its subclass declares — so a vocabulary sitting in
## `item_workbench_app.gd` is a vocabulary this file cannot see. It rides with the reader
## for the same reason `READOUT_MAGNITUDE` and `READOUT_SHARE` sit on
## [ItemWorkbenchBody] rather than in the shell: the constants move WITH their bodies,
## and nothing outside this chain reads either spelling.
const _QUEST_BOARD_ALIASES: Dictionary = {
	&"quest_board": &"the_terms_you_drafted",
	&"quest": &"the_terms_you_drafted",
}

## The quest program a press is answered out of. Held here, and RE-POINTED by the shell:
## `item_workbench_app.gd` assigns it in `_ready` and again in `adopt_actor` on a rebirth,
## which is the whole life of the field — nothing else constructs one.
##
## ## Why the declaration is HERE and not in the shell, and why the shell must drop its own
##
## [method _interact_in_the_world] below is this field's only reader, and a BASE class
## cannot name a member its SUBCLASS declares. While the declaration sat only in
## `item_workbench_app.gd`, this reference did not resolve, `ItemWorkbenchReadout` failed
## to compile, and `item_workbench_app.gd:2`'s `extends ItemWorkbenchReadout` then reported
## the far less actionable `Could not resolve class "ItemWorkbenchReadout"` with the real
## error swallowed as a dependency-load failure. **The BASE half is the one that keeps
## `_quests`, and that was measured both ways:** declaring it in the SHELL as well is a
## hard `already exists in parent class` parse error, and removing it here while the
## shell's copy remained gives `Identifier "_quests" not declared in the current scope`
## at both use sites, because a BASE class cannot see a member its SUBCLASS declares.
## The two failures are mirror images and only one direction compiles. It is declared once
## below, with the rest of this file's fields.

## The path the readout's swing currently fires, or `&""` for
## [constant READOUT_DEFAULT_PATH]. Set through [method set_readout_path]; never persisted,
## because a bare swing leaves no record — the same reason `_readout_technique` is rebuilt
## per blow. Empty is the shipped default rather than a third state: "nobody chose" and
## "chose body" resolve to the same swing, and collapsing them means a selector can be
## driven to any position without a fourth case.
var _readout_selected_path: StringName = &""

## The drill's OWN status clock, and the body it is bound to (ADR 0195).
##
## ## Why the pair sits beside the drill rather than on the shell that has the frame
##
## [method ItemWorkbenchBody.clear_cast_target] already drops the drill on a rebirth, and
## a clock left pointed at a body that no longer exists is the half-swapped failure that
## method exists to prevent — so the aim and its clock are ONE fact, and only the half
## that caches the drill can drop it. The shell owns `_process` and calls
## [method tick_readout_drill]; nothing else may, which is what keeps ADR 0106's ONE tick
## caller true (`tests/app/test_status_clock.gd` pins the frame drivers, unchanged).
##
## ## Why a second INSTANCE rather than a second parameter
##
## `StatusLoop` is `RefCounted` with one `_actor` and one bounded accumulator. Rebuilding
## `_status_loop` per frame would reset the HERO's collapse window every frame, and a
## multi-actor loop would be a redesign of the wire ADR 0106 exists to keep singular. Two
## instances is the smallest change that leaves the hero's loop untouched.
##
## ## No arch cost here
##
## `tools/arch`'s `APP_STATE_MARKERS` reads `set_module_data` / `get_module_data` and a
## `func tick` DECLARATION. This file has the first and not the second — one signal, and
## the rule needs two (`APP_STATE_MIN_SIGNALS`) — so holding the loop here does not make
## `app/` a feature system. The alternative, declaring `tick` here, would have put a
## SECOND one beside the shell's own and tripped exactly that.
## `_drill_loop` and `_drill_body` are DECLARED in `item_workbench_body.gd`, the half that
## WRITES them (`body.gd:577-578`). A base cannot resolve a subclass member, so declaring
## them in this subclass made `body.gd` fail to parse, which made THIS class unresolvable,
## which made `item_workbench_app.gd` report nothing but `Could not resolve class
## "ItemWorkbenchReadout"` — one declaration, and every suite in the repo went red (INC-0020).
## The rule, stated once: **a declaration belongs in the LOWEST link of the chain that
## touches it.** `_quests` follows the same rule one screen down.
## The ONE caller of `QuestApi.accept` (BL-0663). The composition root MINTS and
## re-points this; this file is what READS it, so the declaration belongs here and
## the shell must not redeclare it — a member in both halves is a hard
## `already exists in parent class` parse error, and one parse error takes down
## every suite process-wide (INC-0020). A subclass ASSIGNING an inherited member
## is legal, so the field keeps its whole life across the split.
var _quests: QuestProgram = null


## Point the drill's clock at the drill [method ItemWorkbenchBody._readout_target]
## currently holds, building it if there is none.
##
## ## Why the shell calls THIS rather than constructing the loop itself
##
## The shell is at its thousand-line ceiling and names `StatusLoop` for the hero only;
## splitting the drill's half of the feature across two files would have split one
## invariant — "the drill and its clock are dropped together" — across the boundary that
## invariant exists to cross.
##
## **Idempotent per body, and cheap when nothing changed:** a reader who walks back to
## the readout must find the SAME loop holding the SAME collapse window rather than a
## fresh one that restarted the demotion clock under them. Called at the route mount so
## the clock is armed before the first frame that can strike, and from
## [method tick_readout_drill] when the drill has been reminted under it.
func bind_readout_drill() -> StatusLoop:
	var drill := _readout_target()
	if drill == null:
		return null
	if _drill_loop != null and _drill_body == drill:
		return _drill_loop
	# A NEW loop, not an `attach` onto the old one: the collapse window belongs to the
	# sea that earned it, so carrying one body's held seconds onto another's is exactly
	# the credit `StatusLoop.attach` resets the accumulator to prevent.
	_drill_loop = StatusLoop.new(drill)
	_drill_body = drill
	return _drill_loop


## Age the drill by `delta` seconds. The ONLY caller is
## [method ItemWorkbenchApp._process], which hands this the engine's own frame delta
## (ADR 0089) — so the drill ages on the same clock as the hero and never reads a wall
## time of its own.
##
## ## What this makes observable that was not
##
## `StatusLoop.tick` runs the three COMBAT ticks, and nothing was running them on the
## drill — so ADR 0070's wound DECAY and ADR 0071's rupture bleed and sea COLLAPSE
## could not happen on the one body a player can actually strike. Severity therefore only
## ever rose, and `MindDamage.tick_collapse`'s three-second demotion window could never
## advance on anything reachable: the wound arc and the mind collapse were theory while
## every suite driving the tick functions directly stayed green — the defect class
## `tests/app/test_status_loop_combat_ticks.gd` exists to catch.
##
## ## The growth guards, and why this may run FOREVER
##
## Nothing had to be invented for it: the guards were already written for "every frame,
## forever" and this is that frame. `decay` moves severity DOWN only and the ledger holds
## one row per meridian. `tick_rupture` spends `minf(loss, maximum)` out of a pool
## clamped to `[0, maximum]`, so it cannot drive a body negative however long it runs —
## which matters HERE specifically, because the drill is the body that bleeds and an
## unbounded tick would show as a drill walking to zero on its own. `tick_collapse`
## resets `held` on every outcome that fires and `StatusLoop.MAX_COLLAPSE_HELD` clamps the
## accumulator. None of the three CREATES state, and a body nobody struck pays a few
## dictionary reads a frame and gains nothing — which is the point: these ticks exist for
## a fight, not to manufacture one.
##
## The report is deliberately DISCARDED. The hero's tick is read for `born`
## (`_register_birth`), but the readout renders the LEDGER, not a tick dictionary, and a
## collapse is not a number that panel has a place for; the sea's tier and the channel's
## severity are both already on the page.
func tick_readout_drill(delta: float) -> void:
	# A null on either half is the drill being GONE rather than half-swapped, because
	# `clear_cast_target` drops the pair together — and reading the body off the same
	# cache means a reminted drill is never left un-aged.
	var drill := _readout_target()
	if _drill_loop == null or _drill_body == null or _drill_body != drill:
		bind_readout_drill()
		if _drill_loop == null:
			return
	_drill_loop.tick(delta)


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


## The bare swing the readout fires, on the path `_readout_path` selects.
##
## ## Why BODY is the default, and why the old qi claim was false
##
## This used to hardcode `PathState.QI` and justify it with "a magnitude high enough
## that a wound is reachable". **That was false and the code could not make it true:**
## `QiDamage` emits NO `effects[]` at all (only `BodyDamage` calls `add_effect`), so a qi
## blow reaches no wound however large the magnitude, and the panel's `_wound_line` /
## `necrotic` wording was unreachable through the shipped app forever. A single hardcoded
## qi swing also cannot show the THIRD mechanism: with no sea on the drill,
## `CombatBoot._runs_for` gates `MindDamage` out (`combat_boot.gd:377` requires
## `MindCultivationApi.sea(attacker) != null`) and the erosion row was unreachable too.
##
## BODY is the default because it is the one path whose outputs are WRITTEN: it emits one
## `body.wound` effect per struck site (ADR 0070), so the wound row — the half of this
## surface that outlives the blow — actually renders. `aim_meridian` is set because
## ADR 0070 is explicit that a `named` aim at a meridian the target has not unlocked is
## NOT struck at all; `_build_readout_target` unlocks all twenty, so the aim resolves to
## a real channel. `element_share` is kept because `PathState.QI` still reaches the same
## function and the qi path is one verb away.
##
## It is rebuilt per blow and never persisted, for the same reason `CombatBoot._swing_def`
## is: a swing leaves no record.
func _readout_technique() -> TechniqueDef:
	var def := TechniqueDef.new()
	var asked := _readout_path()
	def.path = asked if asked != &"" else READOUT_DEFAULT_PATH
	def.magnitude = READOUT_MAGNITUDE
	def.element_share = READOUT_SHARE
	if def.path == PathState.BODY:
		def.aim_meridian = READOUT_MERIDIAN
	elif def.path == PathState.QI:
		def.element = READOUT_ELEMENT
	return def


## The path the readout fires, or `&""` for [constant READOUT_DEFAULT_PATH]. Set through
## [method set_readout_path] by the composition root when the screen's selector asks for a
## different mechanism; empty — the shipped default — is what a reader who never touches
## the selector gets.
func _readout_path() -> StringName:
	return _readout_selected_path


## The path the readout's swing fires RIGHT NOW, as the primitive the screen publishes.
## Always a concrete path id rather than the stored empty default, because a screen that
## published `""` for its own default would be reporting its internals; the resolution
## happens here, once, through the same `_readout_technique` the blow uses.
func readout_path() -> StringName:
	var asked := _readout_path()
	return asked if asked != &"" else READOUT_DEFAULT_PATH


## Every path the readout can fire, in the order the screen's cycle walks them.
## `PathState.ALL` rather than a second list, so a fourth path added there is answerable
## here without an edit — the same reason `CombatBoot._mechanisms_for_paths` does not
## restate the three.
func readout_paths() -> Array[StringName]:
	return PathState.ALL


## The screen's READ half of the selector seam: no argument answers [method readout_path],
## and the `&"paths"` argument answers [method readout_paths]. One callable rather than
## two because the armed path and the offered list must come from ONE owner — a screen
## that compared two could only discover they disagree by showing a path the root would
## never arm.
func _readout_armed(question: Variant = &"") -> Variant:
	if StringName(question) == &"paths":
		var out: Array[StringName] = readout_paths()
		return out
	return readout_path()


## ## The third seam, and why the screen owns the CHOICE
##
## The readout's job is to make all three mechanisms visible, and ONE hardcoded swing
## cannot: qi emits no effects, and mind is gated out without a sea. So the screen is
## handed a third callable, `func(path: StringName) -> bool`, and the root answers it by
## recording the path it was asked for. The screen holds NO technique and NO rule — it
## still cannot name `TechniqueDef` (ADR 0161's facade edge) — it only says which of the
## three it wants, and the SAME `_readout_technique()` that `_readout_blow` fires answers
## `mechanism_for_hit` in `_readout_context`, so the mechanism line and the blow cannot
## disagree.
func set_readout_path(path: Variant) -> bool:
	var wanted := StringName(path) if path is StringName or path is String else &""
	if wanted != &"" and not PathState.ALL.has(wanted):
		_readout_selected_path = &""
		return false
	_readout_selected_path = wanted
	return wanted != &""


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
## [constant _QUEST_BOARD_ALIASES].
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
