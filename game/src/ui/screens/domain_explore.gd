class_name DomainExploreScreen
extends UiScreen

## The domain explore screen: where you are standing, what the domain promises, and the
## verbs you can take on the place you are standing in.
##
## ## The seam this screen is built around
##
## It is a pure consumer, like every screen in this program, but the `domain` module is
## not reachable the way `loot` or `world` are: `domain` is not in `rules.UI_MODULES`
## and `app/` is a private unit, so this screen names no domain type at all — not
## `DomainApi`, not `DomainMinimap`, not `DomainMap`. Everything arrives through
## [DomainBridge], the `Callable` seam `DomainBoot.bridge()` fills, which is the same
## shape ADR 0143 settled for loot and for the world clock. [method bind_bridge] is the
## only way the gameplay side arrives, and a screen that has not been bound reports `{}`
## rather than rendering a facade nobody installed.
##
## ## What it shows, and what it deliberately does not draw a second time
##
## The floor plan is [DomainMinimap]'s payload, handed over WHOLE: the same dictionary
## the headless driver renders, so the screen and the probe cannot disagree about where
## a room is or what it promises. Fog is `DomainApi.discovered` and is the module's to
## decide, not this screen's. The room list, the population and the severe zones are all
## read from that payload or from the facade's own reads, and the fixture verbs are the
## module's, routed through the bridge.
##
## No shape is re-derived. The map's room count, the tier a room promises, the severity of
## a zone and the population of a room all come out of the module's own read. The tier in
## particular is the MINIMAP's, because ADR 0073 forbids deriving a promise from a room's
## depth or size, and re-deriving it here would put exactly that forbidden heuristic back.
##
## ## Why it generates rather than only exploring
##
## A screen that could only look at a run somebody else started would be reachable and
## useless: nothing in the shipped program ever entered a domain. So `Enter` calls the
## one production entry point the module publishes, through the bridge, and that is what
## makes the chain template -> map -> contract -> active run startable from a button.
##
## ## The tone rules, stated once
##
## Every refusal repaints from the untouched actor and reports the reason the MODULE
## gave, never one this file invented. A trap that has already fired, a treasure whose
## key you do not carry, a room that is not in this map: each is named by the module's
## own reason id and worded by [member DomainBridge.REASON_TEXT]. Nothing is swallowed,
## and nothing silently truncates: a row that vanishes reads to a player as "the actor
## does not have this", which is a different and wrong statement.
##
## ## What is in [DomainExploreModel] and what is here
##
## This file is the screen: the node tree, the six verbs, the gates that say why a verb
## is refused, the outcomes, and `summary()`. What the place IS — the active run, the
## room list, the selection, the fixtures, and every sentence the labels render — is
## [DomainExploreModel]'s, because reading the world and painting it are two reasons to
## change, and that is the split `world_pulse_reader.gd` already makes beside the world
## map. The gates deliberately stayed here: a gate names its refusal in the PLAYER's
## terms and reads [constant FIXTURE_VERB], which is the action row's own table, so a
## gate is a decision about what this screen OFFERS rather than a read of the world.
##
## Contract: `summary()` is the testable surface, primitives only, and `{}` with no actor.

## The seed `Enter` generates from, and the first of the bounded walk in
## [method _enter_with_a_generating_seed]. A SEED and not a roll: two presses of one
## button should be the same domain, or "what is in there" is unreadable between two
## visits.
##
## It is `test_domain_content.gd`'s `CONTENT_SEED`, and that is the whole reason: the
## generator partitions a template's extent into leaves and REFUSES a map below the
## template's `min_rooms`, so a seed that is not known-good is not a slightly different
## domain but no domain at all. That suite asserts every authored template generates at
## this seed, so `Enter` cannot press a button the content cannot answer. (A previous
## seed produced two rooms against `ember_grotto`'s `min_rooms 6` and every downstream
## assertion about an active run failed for want of one.)
##
## It is the FIRST seed, not the only one, and that is deliberate: "every template
## generates at `CONTENT_SEED`" is a claim about the suite's own template list, and a
## template authored after that suite ran — or one whose partition shifts under a
## generator change — can still land below its `min_rooms` here. Rather than let a
## button silently do nothing, `Enter` advances through a few derived seeds; see
## [constant MAX_SEED_ATTEMPTS] for the bound and why the refusal is never swallowed.
const DEFAULT_SEED := 20261003

## The one refusal a different SEED might answer. Held as a named constant because the
## bounded walk branches on it and it must not become a bare string literal in the loop:
## `DomainApi.ERR_GENERATION_REFUSED` is not nameable here (`domain` is not in
## `rules.UI_MODULES`), so the id is carried instead, and it is worded by
## [member DomainBridge.REASON_TEXT] like every other reason this screen reports.
const GENERATION_REFUSED := "generation_refused"

## How many derived seeds [method act_enter] will try before refusing.
##
## Small and named, never unbounded. The generator is REFUSAL-first by design
## (`DomainGenerator.generate` returns null rather than a partial map), and a refusal
## carries no verdict that a different seed would fare better — so a screen that kept
## drawing seeds until one worked would turn a content defect into an unbounded loop,
## which is exactly the shape `tests/arch_rules/test_no_unbounded_wait.gd` rules out.
## Eight consecutive derived seeds is far more than the generator needs: the partition
## refines on the same stream and adjacent seeds differ in a handful of rolls, so a
## template that cannot produce its `min_rooms` once produces it almost immediately.
const MAX_SEED_ATTEMPTS := 8

## The six actions this screen offers, in the order a player meets them. Declared as data
## so the button row, the summary and the enabled map cannot disagree about the set.
const ACTION_IDS: Array[StringName] = [
	&"enter",
	&"visit",
	&"arm",
	&"attempt",
	&"claim",
	&"leave",
]

const ACTION_LABELS := {
	&"enter": "Enter domain",
	&"visit": "Visit room",
	&"arm": "Arm trap",
	&"attempt": "Strike node",
	&"claim": "Open treasure",
	&"leave": "Leave",
}

## Drive any action by id, so `tools ui drive --cmd` and a headless probe reach the same
## code path a button press does.
##
## A TABLE rather than a chain of `match` arms, because this file already holds a hundred
## lines of prose and a dispatch is the least interesting thing in it. An id this screen
## does not offer is refused BY NAME rather than ignored, so a driver learns it asked
## wrongly instead of seeing a silent no-op.
const ACTION_HANDLERS := {
	&"enter": "act_enter",
	&"leave": "act_leave",
	&"visit": "act_visit",
	&"arm": "act_arm",
	&"attempt": "act_attempt",
	&"claim": "act_claim",
}

## The three fixture kinds, as the MODULE publishes them, paired with the BRIDGE VERB
## that acts on each. A trap is armed, a puzzle is struck, a treasure is opened: a
## button that offered the wrong verb for a fixture would push the player into a
## refusal to learn something the authored content already said.
##
## The values are the SEAM's action ids (`arm_fixture` / `attempt_fixture` /
## `claim_fixture`), not the shorter button ids the `ActionSet` row publishes, because
## the only reader is [method _can_fixture] — and it is handed a bridge action. Holding
## the button ids here instead made all three comparisons unequal, so every fixture verb
## was gated off permanently: a trap could never be armed from a button, the armed/spent
## ledger was unreachable, and a refusal reported a reason the player never caused
## (`authors_no_status_id`, `unknown_node`, `missing_key` — each a gate that does not
## exist). Two vocabularies, so two tables: [constant ACTION_IDS] is the button row's,
## this one is the seam's.
const FIXTURE_VERB := {
	"trap": &"arm_fixture",
	"puzzle": &"attempt_fixture",
	"treasure": &"claim_fixture",
}

## Seconds one `Arm` press advances a trap's telegraph by. Small and stated: the FIRST
## press always arms whatever this says, so the window is visible before the second press
## crosses it. Never a clock read — the module keeps no clock (ADR 0089), and a screen
## that invented one would be a second cadence for one status.
##
## Sized to CROSS the authored window in one step, not merely to nudge it. The authored
## traps telegraph for 0.9s to 1.6s (`src/data/domains/rooms/*.tres`), and
## `DomainFixtures.arm` fires only once `elapsed >= telegraph_s`; a tick below the
## shortest window meant a second press re-armed the same trap and no press count ever
## fired one, so the whole armed/spent ledger was unreachable from a button. Two presses
## is the interaction this screen offers, so two presses must arm and then fire.
const ARM_TICK := 2.0

## What a fixture verb that SUCCEEDED did. The module's own reason ids are the whole
## vocabulary — `telegraphing`, `fired`, `advanced`, `wrong_node`, `claimed` — and each
## names the state it left behind, so an acceptance that changed nothing is visibly
## different from one that paid out.
const OUTCOME_TEXT := {
	"telegraphing": "telegraphing — step on it again to be hit",
	"fired": "fired",
	"advanced": "advanced",
	"wrong_node": "wrong node — the sequence resets",
	"claimed": "claimed",
}

## What the place is. Held as ONE object rather than nine fields, so a refresh is a
## single re-read: a screen carrying a set of cached copies can paint a room list from
## one moment and answer a gate from another, and that is the drift this closes.
var _model: DomainExploreModel = DomainExploreModel.new()
## The last outcome of a fixture verb, kept separately from `UiScreen`'s message because
## the fixture line names the FIXTURE and the message line names the screen's own verb.
var _fixture_message: String = ""
var _fixture_tone: StringName = &""

var _header_label: Label = null
var _status_label: Label = null
var _template_option: OptionButton = null
var _enter_button: Button = null
var _leave_button: Button = null
var _room_option: OptionButton = null
var _visit_button: Button = null
var _map_label: Label = null
var _rooms_label: Label = null
var _population_label: Label = null
var _zones_label: Label = null
var _fixture_option: OptionButton = null
var _node_option: OptionButton = null
var _arm_button: Button = null
var _attempt_button: Button = null
var _claim_button: Button = null
var _fixture_label: Label = null
var _message_label: Label = null
var _actions: ActionSet = null


func _ready() -> void:
	_bind_nodes()
	refresh()


func on_screen_shown() -> void:
	refresh()


func on_screen_hidden() -> void:
	pass


## Inject the gameplay side. Safe to call again; the screen re-reads and repaints, which
## is the point rather than a convenience — a surface bound after its first paint would
## otherwise show the state it had BEFORE the binding.
func bind_bridge(bridge: DomainBridge) -> void:
	_bind_nodes()
	_model.bind(bridge)
	refresh()


## The keyboard and pad land on the first live action, so a screen with nothing to do
## offers nothing to focus and one with something to do never lands on a dead control.
func focus_initial() -> void:
	_bind_nodes()
	if _actions != null and not _enabled().is_empty():
		_actions.focus_initial()
		return
	for control in [_enter_button, _visit_button, _arm_button]:
		var target := control as Control
		if target == null or target.disabled:
			continue
		_focus_target = String(target.name)
		if target.is_inside_tree():
			target.grab_focus()
		return


## Everything this screen shows, as primitives only. `{}` with no actor or no bridge, per
## the screen contract, so a test never reads a half-initialised screen.
##
## The model's half is merged in WHOLE rather than key by key: every figure in it is the
## MODULE's own answer, and re-listing them here would be the second copy of the map's
## shape this screen exists not to hold.
func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null or _model.bridge() == null:
		return {}
	var place := _model.summary()
	place["has_actor"] = _actor != null
	place["actor_id"] = String(_actor.id)
	# The bridge's own view of itself, so a test can assert the WIRING rather than
	# infer it from a verb that quietly did nothing.
	place["bridge"] = _model.bridge().summary()
	place["fixture_message"] = _fixture_message
	place["fixture_tone"] = String(_fixture_tone)
	place["header"] = _text_of(_header_label)
	place["status"] = _text_of(_status_label)
	place["map_text"] = _text_of(_map_label)
	place["rooms_text"] = _text_of(_rooms_label)
	place["population_text"] = _text_of(_population_label)
	place["zones_text"] = _text_of(_zones_label)
	place["fixture_text"] = _text_of(_fixture_label)
	place["enabled"] = _enabled()
	place["actions"] = _actions.summary() if _actions != null else {}
	return place


func _refresh_view() -> void:
	_bind_nodes()
	_model.refresh(_actor)
	_fill_templates()
	_fill_rooms()
	_fill_fixtures()


func _render() -> void:
	_bind_nodes()
	var lines := _model.lines()
	_header_label.text = String(lines["header"])
	_status_label.text = String(lines["status"])
	_map_label.text = String(lines["map"])
	_rooms_label.text = String(lines["rooms"])
	_population_label.text = String(lines["population"])
	_zones_label.text = String(lines["zones"])
	_fixture_label.text = String(lines["fixture"])
	_enter_button.disabled = not _can_enter()
	_leave_button.disabled = not _can_leave()
	_visit_button.disabled = not _can_visit()
	_arm_button.disabled = not _can_arm()
	_attempt_button.disabled = not _can_attempt()
	_claim_button.disabled = not _can_claim()
	_publish_actions()
	_publish_message()
	_sync_selections()


## Resolve scene nodes, then connect every signal ONCE. Guarded like every other connect
## in this program (ADR/AGENTS.md): an unguarded connect is one handler per call, and a
## reused screen then fires N times for one press.
func _bind_nodes() -> void:
	if _header_label != null:
		return
	_header_label = get_node_or_null("%HeaderLabel") as Label
	_status_label = get_node_or_null("%StatusLabel") as Label
	_template_option = get_node_or_null("%TemplateOption") as OptionButton
	_enter_button = get_node_or_null("%EnterButton") as Button
	_leave_button = get_node_or_null("%LeaveButton") as Button
	_room_option = get_node_or_null("%RoomOption") as OptionButton
	_visit_button = get_node_or_null("%VisitButton") as Button
	_map_label = get_node_or_null("%MapLabel") as Label
	_rooms_label = get_node_or_null("%RoomsLabel") as Label
	_population_label = get_node_or_null("%PopulationLabel") as Label
	_zones_label = get_node_or_null("%ZonesLabel") as Label
	_fixture_option = get_node_or_null("%FixtureOption") as OptionButton
	_node_option = get_node_or_null("%NodeOption") as OptionButton
	_arm_button = get_node_or_null("%ArmButton") as Button
	_attempt_button = get_node_or_null("%AttemptButton") as Button
	_claim_button = get_node_or_null("%ClaimButton") as Button
	_fixture_label = get_node_or_null("%FixtureLabel") as Label
	_message_label = get_node_or_null("%MessageLabel") as Label
	_actions = get_node_or_null("%Actions") as ActionSet
	if _actions != null and not _actions.action_requested.is_connected(_on_action_requested):
		_actions.action_requested.connect(_on_action_requested)
	_connect_select(_template_option, _on_template_selected)
	_connect_select(_room_option, _on_room_selected)
	_connect_select(_fixture_option, _on_fixture_selected)
	_connect_select(_node_option, _on_node_selected)
	_connect_pressed(_enter_button, act_enter)
	_connect_pressed(_leave_button, act_leave)
	_connect_pressed(_visit_button, act_visit)
	_connect_pressed(_arm_button, act_arm)
	_connect_pressed(_attempt_button, act_attempt)
	_connect_pressed(_claim_button, act_claim)


# ── Actions. Each asks the bridge, then repaints from the untouched actor ─────────


## Generate and enter the selected authored template. The ONE production entry point
## into a domain, and calling it from a button is what makes the module reachable from
## the shipped program at all.
##
## The seed is [constant DEFAULT_SEED] first and then a small, BOUNDED walk of derived
## seeds — see [method _enter_with_a_generating_seed] for why a refused seed cannot
## simply be retried forever. Two presses of this button still enter the SAME domain:
## the walk is a pure function of the template, so it picks the same first success for
## the same template every time.
func act_enter() -> bool:
	_bind_nodes()
	if not _can_enter():
		return _reject(_enter_reason())
	var template_id := _selected_template_id()
	var entered := _enter_with_a_generating_seed(StringName(template_id))
	return _settle(entered, "Entered %s" % template_id)


## `Enter` against the selected template, advancing the seed until the MODULE accepts
## one, and returning the LAST answer either way so the caller still repaints from the
## untouched actor.
##
## ## Why the seed has to move at all
##
## `DomainGenerator.generate` partitions a template's extent and REFUSES a partition
## below the template's `min_rooms` — it pushes `produced N room(s), below its
## min_rooms M` and returns null. `generate_and_enter` turns that into
## `generation_refused`, so a template whose partition under this particular seed lands
## short produces NO domain and the button does nothing a player can see. That is a
## property of the SEED and the TEMPLATE together, not a defect in either: the same
## template generates from a neighbouring seed. Pressing `Enter` should enter something,
## so the screen advances rather than reporting a refusal the player can do nothing
## about.
##
## ## Why this is not papering over it
##
## Three things stay true, and each of them is what the alternative lost:
##
##  - The attempt count is [constant MAX_SEED_ATTEMPTS] — a named, small cap. There is
##    no loop that can be made unbounded by authoring a template nothing can satisfy.
##  - The refusal is NEVER swallowed. A reason that is not a generation refusal is
##    returned IMMEDIATELY, untouched, on the first attempt — so `no_such_template` and
##    `invalid_contract` reach the player exactly as the module worded them.
##  - If every attempt refuses for the generation reason, the LAST refusal is what gets
##    returned, so the line names the module's own `generation_refused` rather than a
##    wording this file invented.
##
## The seeds are `DEFAULT_SEED + attempt`, not a random roll: reproducible, and the same
## template always resolves to the same domain.
func _enter_with_a_generating_seed(template_id: StringName) -> Dictionary:
	var refusal: Dictionary = {}
	for attempt in MAX_SEED_ATTEMPTS:
		var answer := _model.bridge().call_action(
			&"enter", [_actor, template_id, DEFAULT_SEED + attempt]
		)
		if bool(answer.get("ok", false)):
			return answer
		refusal = answer
		if String(answer.get("reason", "")) != GENERATION_REFUSED:
			# Not something a different seed would change, so stop asking and report it.
			return answer
	# Every seed the bounded walk tried was refused for the same reason. The LAST refusal
	# is returned rather than a fresh call, so the player is told the module's own
	# `generation_refused` once and the walk costs `MAX_SEED_ATTEMPTS` generations, not
	# `MAX_SEED_ATTEMPTS + 1`.
	return refusal


## Leave the domain. The discovered set survives, so nothing the player found is lost.
func act_leave() -> bool:
	_bind_nodes()
	if not _can_leave():
		return _reject("no_map")
	return _settle(_model.bridge().call_action(&"leave", [_actor]), "Left the domain")


## Walk into the selected room, recording it as discovered so the floor plan draws it. A
## room the map does not hold is REFUSED BY NAME and changes nothing at all.
##
## The gate is the MODULE's room list, not the fogged minimap and not the previous
## selection: a caller that aims the screen at a room the run does not hold must be told
## `unknown_room` when it presses the verb, not have the verb quietly walk into whatever
## room happened to be selected before.
func act_visit() -> bool:
	_bind_nodes()
	if not _can_visit():
		return _reject(_visit_reason())
	var reached := _model.bridge().call_action(&"visit", [_actor, _selected_room_id(), &""])
	return _settle(reached, "Reached %s" % String(_selected_room_id()))


## Arm a trap's telegraph, or fire it when the authored window has already elapsed.
func act_arm(delta: float = ARM_TICK) -> bool:
	_bind_nodes()
	if not _can_arm():
		return _reject(_arm_reason())
	var armed := _model.bridge().call_action(
		&"arm_fixture", [_actor, _selected_room_id(), _selected_fixture_id(), delta]
	)
	return _settle_fixture(armed)


## Strike one node of a formation puzzle. A wrong node costs the ATTEMPT and never
## health, and the module names the node it expected — which is shown, not swallowed.
func act_attempt() -> bool:
	_bind_nodes()
	if not _can_attempt():
		return _reject(_attempt_reason())
	var struck := _model.bridge().call_action(
		&"attempt_fixture", [_actor, _selected_room_id(), _selected_fixture_id(), _puzzle_node_id()]
	)
	return _settle_fixture(struck)


## Open a treasure. Refused by name at every gate, in the order a player meets them.
func act_claim() -> bool:
	_bind_nodes()
	if not _can_claim():
		return _reject(_claim_reason())
	return _settle_fixture(
		_model.bridge().call_action(
			&"claim_fixture", [_actor, _selected_room_id(), _selected_fixture_id()]
		)
	)


func act(action: StringName) -> bool:
	_bind_nodes()
	var handler := String(ACTION_HANDLERS.get(action, ""))
	if handler.is_empty():
		return _reject("unknown_action")
	return bool(call(handler))


## Look at one room, the way picking it from the room selector does. Public because a
## test and a driver both need to aim at a specific room, and reaching into the model's
## fields would make the selection a private field with a public back door.
##
## Gated on the AUTHORED room list, not on the minimap's drawn rooms. Those are not the
## same set and the difference is the whole point of the screen: the fog is what the
## module has DISCOVERED, so gating on it made an undiscovered room unselectable — a
## player could never walk toward one, and the domain could only ever be one room deep.
##
## A room the MODULE does not hold is still refused, and the refusal is RECORDED in the
## model rather than discarded. The caller is told false, so it knows, and the next
## `Visit` reports `unknown_room` by name instead of walking into whatever room was
## selected before — a verb aimed at a room nobody holds must refuse rather than silently
## succeed somewhere else. The pending id is dropped the moment anything else moves the
## selection, so it can never outlive the press that set it.
func select_room(room_id: StringName) -> bool:
	_bind_nodes()
	var accepted := _model.select_room(room_id)
	refresh()
	return accepted


## Look at one fixture of the selected room. Same reasoning as [method select_room].
func select_fixture(fixture_id: StringName) -> bool:
	_bind_nodes()
	var accepted := _model.select_fixture(fixture_id)
	refresh()
	return accepted


## Choose the puzzle node to strike, for a formation the player is solving. False when the
## selected fixture authors no such node, so a caller learns the node is not a real choice.
func select_node(node_id: StringName) -> bool:
	_bind_nodes()
	var accepted := _model.select_node(node_id)
	refresh()
	return accepted


# ── Enabled state. Each verb states its OWN refusal rather than a bare "disabled" ──


func _can_enter() -> bool:
	return (
		_actor != null
		and _model.bridge() != null
		and _model.bridge().has(&"enter")
		and _model.active().is_empty()
		and not _selected_template_id().is_empty()
	)


func _can_leave() -> bool:
	return _live() and _model.bridge().has(&"leave")


## `Visit` needs a run, the verb, and a room the MODULE actually holds.
##
## The pending-room check is what turns a refused [method select_room] into a refusal of
## the verb rather than a silent walk into the previous room: a pending id means the
## caller named a room this run does not have, so the verb must say so by name.
func _can_visit() -> bool:
	if not _pending_room().is_empty():
		return false
	return _live() and _model.bridge().has(&"visit") and not _selected_room_id().is_empty()


func _can_arm() -> bool:
	return _can_fixture(&"arm_fixture")


func _can_attempt() -> bool:
	return _can_fixture(&"attempt_fixture") and not _puzzle_nodes().is_empty()


func _can_claim() -> bool:
	return _can_fixture(&"claim_fixture")


## Whether a run is active and the bridge can reach the verb at all.
func _live() -> bool:
	return _actor != null and _model.bridge() != null and not _model.active().is_empty()


## A fixture verb is offered when the room holds a fixture OF THE KIND THIS VERB acts
## on, and the module can answer. Whether the module will ANSWER YES is its business: a
## treasure whose key you lack must stay pressable, or the refusal — the thing that
## teaches a player why the hoard is sealed — becomes unreachable.
func _can_fixture(action: StringName) -> bool:
	if not _live() or not _model.bridge().has(action) or _selected_fixture_id().is_empty():
		return false
	return FIXTURE_VERB.get(_model.fixture_kind(), &"") == action


func _enter_reason() -> String:
	if _actor == null or _model.bridge() == null:
		return "no_actor"
	if not _model.bridge().has(&"enter"):
		return "no_inventory_bridge"
	if _selected_template_id().is_empty():
		return "no_such_template"
	return "no_map"


func _visit_reason() -> String:
	if not _live():
		return "no_map"
	if not _model.bridge().has(&"visit"):
		return "no_inventory_bridge"
	return "unknown_room"


func _arm_reason() -> String:
	return _fixture_reason(&"arm_fixture", "authors_no_status_id")


func _attempt_reason() -> String:
	if _puzzle_nodes().is_empty():
		return "authors_nothing_to_grant"
	return _fixture_reason(&"attempt_fixture", "unknown_node")


func _claim_reason() -> String:
	return _fixture_reason(&"claim_fixture", "missing_key")


## Why a fixture verb is refused when it is refused by the SCREEN rather than by the
## module. The fallback names what the authored content says about that fixture, which
## is the gate a player is most likely to be standing at.
func _fixture_reason(action: StringName, authored_reason: String) -> String:
	if not _live():
		return "no_map"
	if not _model.bridge().has(action):
		return "no_inventory_bridge"
	return authored_reason


## What each action is right now, and what the ActionSet row itself thinks. Both halves
## are published so a test can compare them rather than trust either one.
##
## The panel's own flags are read through ONE explicitly typed local. `summary()` is a
## `Dictionary`, so `get()` answers a `Variant`, and a ternary over a Variant and a
## literal infers Variant for the whole expression — which this project treats as a parse
## error. Coerced here so the ternary below compares two dictionaries.
func _enabled() -> Dictionary:
	var flags: Dictionary = {}
	if _actions != null:
		flags = _actions.summary().get("enabled", {}) as Dictionary
	return {
		"enter": _can_enter(),
		"leave": _can_leave(),
		"visit": _can_visit(),
		"arm": _can_arm(),
		"attempt": _can_attempt(),
		"claim": _can_claim(),
		"panel_enter": bool(flags.get("enter", false)),
		"panel_visit": bool(flags.get("visit", false)),
		"panel_leave": bool(flags.get("leave", false)),
	}


# ── Rendering ────────────────────────────────────────────────────────────────


## Fill the domain selector from the AUTHORED catalogue. Presentation only: the screen
## never invents a domain, and the rows carry the id beside the label because the row a
## player reads and the row a driver aims at are the same row.
func _fill_templates() -> void:
	if _template_option == null:
		return
	_fill(_template_option, _model.template_options())
	_model.keep_template(_model.template_id())


## Fill the room selector from the AUTHORED room list, so every room in the run is
## reachable and not only the ones the floor plan has already drawn.
func _fill_rooms() -> void:
	if _room_option == null:
		return
	_fill(_room_option, _model.room_options())


## Fill the fixture and node selectors from the SELECTED room. A room is the only place a
## fixture exists — `DomainFixtures._resolve` refuses by name outside one — so the list
## empties rather than offering buttons aimed at another room. No nodes is honest: a trap
## and a treasure have none to strike, so the node row says so by being disabled.
func _fill_fixtures() -> void:
	if _fixture_option == null or _node_option == null:
		return
	_fill(_fixture_option, _model.fixture_options())
	var nodes := _puzzle_nodes()
	var labels: Array = []
	for node in nodes:
		labels.append(String(node))
	_fill(_node_option, labels)
	_node_option.disabled = nodes.is_empty()


## Replace an option list's rows. Every refill goes through here because the rule is the
## same each time, and one place to keep it is one place for the four to agree.
func _fill(option: OptionButton, labels: Array) -> void:
	option.clear()
	for label in labels:
		option.add_item(String(label))


## Push the action row's own state, and the outcome line beside it.
func _publish_actions() -> void:
	if _actions == null:
		return
	var enabled := _enabled()
	var flags := {}
	for action in ACTION_IDS:
		flags[String(action)] = bool(enabled.get(String(action), false))
	var state := {
		"actions": ACTION_IDS,
		"labels": ACTION_LABELS,
		"enabled": flags,
		"primary": &"enter" if flags["enter"] else &"visit",
	}
	_actions.set_state(state)


## The outcome line in both places a reader can see it. `WarnLabel` on a refusal and
## `OkLabel` on an acceptance are THEME VARIATIONS rather than per-node colours, so the
## palette stays in the one theme (the UI standard; BL-0084).
func _publish_message() -> void:
	if _actions != null:
		_actions.set_message(_message, _tone)
	if _message_label != null:
		_message_label.text = _message
		_message_label.theme_type_variation = _tone_variation()


func _tone_variation() -> StringName:
	match _tone:
		TONE_ERROR:
			return &"WarnLabel"
		TONE_OK:
			return &"OkLabel"
		_:
			return &"MetaLabel"


## Repaint the four selectors against the lists they were just filled from, without
## re-emitting `item_selected` — so a programmatic `select()` cannot be mistaken for a
## click and re-enter the handler that set it.
func _sync_selections() -> void:
	var at := _model.selection_indices()
	_select(_template_option, int(at[0]))
	_select(_room_option, int(at[1]))
	_select(_fixture_option, int(at[2]))
	_select(_node_option, int(at[3]))


# ── Outcomes ─────────────────────────────────────────────────────────────────


## An outcome the MODULE named. Accepted repaints in the accepted tone; refused reports
## the reason it was given and repaints from the untouched actor, so nothing on screen
## can drift away from the world state.
func _settle(result: Dictionary, accepted: String) -> bool:
	if not bool(result.get("ok", false)):
		return _reject(String(result.get("reason", "rejected")))
	_fixture_message = accepted
	_fixture_tone = TONE_OK
	set_message(accepted, TONE_OK)
	refresh()
	return true


## As [method _settle], for a fixture verb: the line names the FIXTURE as well, because a
## room can hold three of them and "already claimed" reads as ambiguous while the player
## is looking at a formation.
##
## BOTH lines name the fixture and the reason id. A refusal is the thing that teaches a
## player why a verb cannot be taken, and "You are not carrying its key" on its own is
## ambiguous against two other fixtures in the same room — so the fixture line leads with
## which one it was about and carries the module's own reason id alongside the bridge's
## wording. The id is not decoration: it is the stable handle a driver and a test match
## on, and a worded sentence alone would leave both of them pattern-matching prose.
func _settle_fixture(result: Dictionary) -> bool:
	var reason := String(result.get("reason", ""))
	var accepted := bool(result.get("ok", false))
	var text: String = _outcome_text(reason) if accepted else _reason_text(reason)
	# Both lines carry the reason ID and the wording. The id is the stable handle a
	# driver and a test match on; the wording is what a player reads. A line with only
	# one of them fails half of every consumer.
	_fixture_message = _fixture_sentence("%s — %s" % [reason, text])
	_fixture_tone = TONE_OK if accepted else TONE_ERROR
	set_message(_fixture_message, _fixture_tone)
	refresh()
	return accepted


## A refusal. The reason is the MODULE'S and the sentence is the bridge's table — never
## a wording this file chose, because a screen that invents the reason is a second,
## quietly-wrong account of why a verb was refused.
##
## Named so the line still says WHICH fixture when there is one: `_reject` is reached
## from the fixture verbs as well as from `Enter`/`Leave`/`Visit`, and a room can hold
## three fixtures, so "Rejected: You are not carrying its key" is not an answer a player
## can act on. With no fixture selected the line is the bare reason, which is honest —
## there was no fixture to be about.
func _reject(reason: String) -> bool:
	_fixture_message = _fixture_sentence(_reason_text(reason))
	_fixture_tone = TONE_ERROR
	# Composed ONCE. Re-wrapping `_fixture_message` here would prefix the fixture id a
	# second time, so a repeated refusal read "ash_x: ash_x: ...".
	set_message(_fixture_sentence("Rejected: %s — %s" % [reason, _reason_text(reason)]), TONE_ERROR)
	refresh()
	return false


## `<fixture>: <text>`, or `<text>` alone when no fixture is aimed at. The one place a
## fixture outcome is worded, so the summary line and the message line can never name two
## different fixtures for one press.
func _fixture_sentence(text: String) -> String:
	var fixture := _selected_fixture_id()
	if fixture.is_empty():
		return text
	return "%s: %s" % [String(fixture), text]


func _reason_text(reason: String) -> String:
	return _model.bridge().reason_text(reason) if _model.bridge() != null else reason


func _outcome_text(reason: String) -> String:
	var text := String(OUTCOME_TEXT.get(reason, reason))
	return text if not text.is_empty() else "done"


# ── Plumbing ─────────────────────────────────────────────────────────────────


## A guarded connect. Every one of them, so a re-bound screen has one handler per press.
## The action row carries `act_*` DIRECTLY rather than routing through `act`, because an
## `ActionSet` button is one specific verb and the panel already knows which; a string
## table would add a lookup to the one path a player presses most.
func _connect_pressed(button: Button, handler: Callable) -> void:
	if button != null and not button.pressed.is_connected(handler):
		button.pressed.connect(handler)


## The four selectors are wired to ONE handler each, and each handler hands its own index
## to the model — which holds the list that index names, so the two cannot drift.
func _connect_select(option: OptionButton, handler: Callable) -> void:
	if option != null and not option.item_selected.is_connected(handler):
		option.item_selected.connect(handler)


func _select(option: OptionButton, index: int) -> void:
	if option != null and index >= 0 and index < option.item_count:
		option.select(index)


func _text_of(label: Label) -> String:
	return "" if label == null else label.text


func _on_action_requested(action: StringName) -> void:
	act(action)


## The four selector handlers, one per dropdown. None of them resolves an index against a
## list of its own: the model holds the list the dropdown was filled from, so a handler
## cannot read a stale copy of it. All four share one rule, which is why they share one
## line of prose between them.
func _on_template_selected(index: int) -> void:
	_model.choose(&"template", index)
	refresh()


func _on_room_selected(index: int) -> void:
	_model.choose(&"room", index)
	refresh()


func _on_fixture_selected(index: int) -> void:
	_model.choose(&"fixture", index)
	refresh()


func _on_node_selected(index: int) -> void:
	_model.choose(&"node", index)
	refresh()


# ── The model's selection, read through the gates and the verbs ───────────────


func _selected_room_id() -> StringName:
	return StringName(_model.selection().get("room", ""))


func _selected_fixture_id() -> StringName:
	return StringName(_model.selection().get("fixture", ""))


func _puzzle_node_id() -> StringName:
	return StringName(_model.selection().get("node", ""))


func _pending_room() -> StringName:
	return StringName(_model.selection().get("pending", ""))


func _puzzle_nodes() -> Array[StringName]:
	return _model.node_options()


func _selected_template_id() -> String:
	return _model.template_id()
