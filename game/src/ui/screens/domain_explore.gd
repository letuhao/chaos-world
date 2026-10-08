class_name DomainExploreScreen
extends UiScreen

## The domain explore screen: where you are standing, what the domain promises, and the
## verbs you can take on the place you are standing in.
##
## ## The seam this screen is built around
##
## A pure consumer, like every screen in this program, but the `domain` module is not
## reachable the way `loot` or `world` are: it is not in `rules.UI_MODULES` and `app/` is
## a private unit, so this screen names no domain type at all — not `DomainApi`, not
## `DomainMinimap`, not `DomainMap`. Everything arrives through [DomainBridge], the
## `Callable` seam `DomainBoot.bridge()` fills, the same shape ADR 0143 settled for loot
## and the world clock. [method bind_bridge] is the only way the gameplay side arrives,
## and an unbound screen reports `{}` rather than rendering a facade nobody installed.
##
## ## What it shows, and what it deliberately does not draw a second time
##
## The floor plan is [DomainMinimap]'s payload, handed over WHOLE: the same dictionary
## the headless driver renders, so the screen and the probe cannot disagree about where a
## room is or what it promises. Fog is `DomainApi.discovered` and is the module's to decide.
## No shape is re-derived — room count, tier, zone severity and population all come out of
## the module's own read. The tier in particular is the MINIMAP's, because ADR 0073 forbids
## deriving a promise from a room's depth or size, and re-deriving it here would put exactly
## that forbidden heuristic back.
##
## ## Why it generates rather than only exploring
##
## A screen that could only look at a run somebody else started would be reachable and
## useless: nothing in the shipped program ever entered a domain. So `Enter` calls the one
## production entry point the module publishes, through the bridge, and that is what makes
## the chain template -> map -> contract -> active run startable from a button.
##
## ## The tone rules, stated once
##
## Every refusal repaints from the untouched actor and reports the reason the MODULE gave,
## never one this file invented. Each is named by the module's own reason id and worded by
## [member DomainBridge.REASON_TEXT]. Nothing is swallowed, and nothing silently truncates:
## a row that vanishes reads to a player as "the actor does not have this", which is a
## different and wrong statement.
##
## ## What is in [DomainExploreModel] and what is here
##
## This file is the screen: the node tree, the six verbs, the gates that say why a verb is
## refused, the outcomes, and `summary()`. What the place IS is [DomainExploreModel]'s —
## reading the world and painting it are two reasons to change, the split
## `world_pulse_reader.gd` already makes. The gates deliberately stayed here: a gate names
## its refusal in the PLAYER's terms and reads [constant FIXTURE_VERB], so a gate is a
## decision about what this screen OFFERS rather than a read of the world.
##
## Contract: `summary()` is the testable surface, primitives only, and `{}` with no actor.

## The seed `Enter` generates from, and the first of [DomainSeedWalk]'s bounded walk. A
## SEED and not a roll: two presses of one button should be the same domain, or "what is
## in there" is unreadable between two visits.
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
## [DomainSeedWalk] for the bound and why the refusal is never swallowed.
const DEFAULT_SEED := 20261003

## The six actions this screen offers, in the order a player meets them. Declared as data
## so the button row, the summary and the enabled map cannot disagree about the set.
const ACTION_IDS: Array[StringName] = [
	&"enter",
	&"visit",
	&"inspect",
	&"attempt",
	&"claim",
	&"leave",
]

const ACTION_LABELS := {
	&"enter": "LOC_UI_SCREENS_9EFF7ED921",
	&"visit": "LOC_UI_SCREENS_2AA4D3E32A",
	&"inspect": "LOC_UI_SCREENS_1508A954EE",
	&"attempt": "LOC_UI_SCREENS_682924E339",
	&"claim": "LOC_UI_SCREENS_B6DA8450F0",
	&"leave": "LOC_UI_SCREENS_7E3520A973",
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
	&"inspect": "act_inspect",
	&"attempt": "act_attempt",
	&"claim": "act_claim",
}

## The three fixture kinds, as the MODULE publishes them, paired with the BRIDGE VERB
## that acts on each. A trap is INSPECTED, a puzzle is struck, a treasure is opened: a
## button that offered the wrong verb for a fixture would push the player into a
## refusal to learn something the authored content already said.
##
## ## Why a trap reads rather than acts (ADR 0211)
##
## The trap's verb is `inspect_fixture`, which is FREE and mutates nothing. Presence inside
## the authored bounds is the only trigger, so there is no button left to fire one: a
## button that armed a trap made the player pay for having INSPECTED it rather than for
## having ENTERED it, and closed the telegraph window inside a single press. Reading a
## trap tells a player its footprint, its harm and its window; it costs nothing, so the
## floor is worth reading before it is worth crossing.
##
## The table itself moved to [DomainFixtureGates] when this file hit its thousand-line
## ceiling, and this screen holds no copy of it: two tables of "which verb acts on which
## kind" would be two answers to one question. See that class for why the values are the
## SEAM's action ids rather than the shorter button ids the action row publishes.
const FIXTURE_VERB := DomainFixtureGates.FIXTURE_VERB

## The `RoomDef.kind` a settlement room carries. One string, in one place, for one kind —
## the same discipline `domain_settlement.gd` follows, and `ui/` may not name a domain
## type, so the kind is carried as a plain word rather than read off a class.
const SETTLEMENT_KIND := "settlement"

## What the place is. Held as ONE object rather than nine fields, so a refresh is a
## single re-read: a screen carrying a set of cached copies can paint a room list from
## one moment and answer a gate from another, and that is the drift this closes.
##
## Built LAZILY by [method _read_model], never in this initializer. An initializer runs
## during instantiation and names a global class, so it resolved on load order rather than
## on this screen: an uncompiled script answers as a bare `GDScript` with no `new`, the
## initializer left `_model` null, and every refresh raised `in base 'Nil'`. Every reader
## goes through a null-tolerant accessor, so a model that could not be built reads as
## "nothing to show" — the shape an unbound bridge already has — rather than raising.
var _model: DomainExploreModel = null
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
var _inspect_button: Button = null
var _attempt_button: Button = null
var _claim_button: Button = null
var _fixture_label: Label = null
var _message_label: Label = null
var _actions: ActionSet = null
## Who is standing in the room the player is actually in (DEF-0261). Fed through a
## [NpcRosterBridge] because `npc` and `world_spawn` are both outside
## `rules.UI_MODULES` and `app/` is a private unit — the same door `DomainBridge` and
## `WorldPulseBridge` are.
##
## ## Null until the composition root fills it, and that is the honest default
##
## An unbound panel reports "the roster of this place is not wired to anything" rather
## than an empty room, because "nobody is here" and "this screen cannot ask" are
## different facts and a player must be able to tell them apart.
var _roster: NpcRosterBridge = null
var _roster_panel: NpcRosterPanel = null
## The floor plan, DRAWN (ADR 0206). Fed the module's payload WHOLE; it reads the
## geometry and draws it, so the only shape a player sees is the module's own.
var _map_view: DomainMapView = null
## A settlement, shown as the SELECTED room (ADR 0209). Keyed on the room the player is
## looking at, exactly as `_roster_panel` is keyed on where they stand.
var _settlement: SettlementPanel = null
## The settlement seam. Null until the composition root fills it, and the honest default
## is a panel that says so rather than one that claims this room holds no settlement.
var _settlement_bridge: SettlementBridge = null
## What the SELECTED fixture WOULD cost, shown before anything lands (ADR 0211).
##
## Fed the module's `telegraph` payload WHOLE and owns every word, decimal and width on
## this surface — the screen hands it primitives and formats nothing (AGENTS.md, UI
## standard). It lives here rather than as another line in this file because the screen is
## already past its line budget, and because a telegraph that the same screen could also
## mute is a telegraph nobody has to be able to rely on.
var _telegraph: DomainTelegraphPanel = null


## Inject the settlement seam. Safe to call again; the screen re-reads and repaints.
## Kept beside [method bind_roster] rather than folded into [method bind_bridge] because
## it is a different seam: `DomainSettlement` is a settlement-class read, not a domain
## verb, and ADR 0209 installs it behind its own `Callable` pair.
func bind_settlement(bridge: SettlementBridge) -> void:
	_bind_nodes()
	_settlement_bridge = bridge
	refresh()


## The settlement seam this screen holds, adopting the shared one when nobody handed it
## over. The same `NpcApi.set_minter` idiom `_adopt_roster_bridge` uses: a screen bound
## by a route and a screen bound by a test both get the seam, and neither can end up
## half-wired. Guarded rather than fatal because a program that never installed the
## settlement seam must still show the room — it just says the settlement is unwired.
func _adopt_settlement_bridge() -> void:
	if _settlement_bridge != null and _settlement_bridge.has(&"read_settlement"):
		return
	_settlement_bridge = SettlementBridge.shared()


## Inject the settlement roster. Safe to call again; the screen re-reads and repaints,
## which is the point rather than a convenience — a surface bound after its first paint
## would otherwise show the state it had BEFORE the binding.
##
## The panel is re-read on EVERY refresh, never cached: the roster is a function of where
## the player is standing, and the player moves. A panel that read once at bind time would
## show the room they left, which is the stale-settlement defect DEF-0261 exists to end —
## reproduced one layer up.
func bind_roster(roster: NpcRosterBridge) -> void:
	_bind_nodes()
	_roster = roster
	refresh()


## Adopt the roster reader the composition root installed, if any. Called from
## [method _bind_nodes] so a screen mounted through ANY door — the route table, the
## stack, or a test — carries a live roster without the binder having to know the roster
## exists.
##
## This one resolves its own bridge rather than waiting to be handed one. Every other
## seam in this program is handed over in `_bind_route_screen`; that arm lives in
## `item_workbench_app.gd`, which is mid-refactor by another agent and read-only here. The
## bridge's own `static var` (the `NpcApi.set_minter` idiom) makes the seam available to
## whoever mounts the screen, which is strictly more robust: a screen bound by a route AND
## a screen bound by a test both get the roster, and neither can end up half-wired.
func _adopt_roster_bridge() -> void:
	if _roster != null and _roster.wired():
		return
	_roster = NpcRosterBridge.shared()


## Ask the bridge where the player is and hand the whole answer to the panel.
##
## The panel keys on the location the bridge reports — never on a cast read of its own
## and never on the boot-time settlement [code]ItemWorkbenchPlay.npc_presence()[/code]
## publishes. That payload is minted once into [code]mortal_plains[/code] and never
## restocked, so a roster keyed on it shows a stale cast as though it were the room the
## player is standing in, with nothing on screen to tell the reader so.
func _refresh_roster() -> void:
	if _roster_panel == null:
		return
	_adopt_roster_bridge()
	if _actor == null:
		_roster_panel.show_room({})
		return
	_roster_panel.show_room(_roster.read_room_roster(_actor) if _roster != null else {})


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
	var model := _read_model()
	if model == null:
		return
	model.bind(bridge)
	refresh()


## The keyboard and pad land on the first live action, so a screen with nothing to do
## offers nothing to focus and one with something to do never lands on a dead control.
func focus_initial() -> void:
	_bind_nodes()
	if _actions != null and not _enabled().is_empty():
		_actions.focus_initial()
		return
	for control in [_enter_button, _visit_button, _inspect_button]:
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
	var model := _read_model()
	var seam := _bridge()
	if _actor == null or seam == null or model == null:
		return {}
	var place := model.summary()
	place["has_actor"] = _actor != null
	place["actor_id"] = String(_actor.id)
	# The bridge's own view of itself, so a test can assert the WIRING rather than
	# infer it from a verb that quietly did nothing.
	place["bridge"] = seam.summary()
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
	# The roster, nested under the panel's own key rather than merged key by key: it
	# already reports its own count, its own rows and the two sentences it painted, so
	# listing them here would be the second copy of one fact.
	place["roster"] = _roster_panel.summary() if _roster_panel != null else {}
	# The floor plan, nested under its own key: it publishes its own counts, its own
	# scale and its own fog partition, so listing them here would be the second copy of
	# one fact. `layout_digest` in particular is the VIEW's to answer and the only honest
	# way a test can check a second layout never appeared.
	place["minimap_view"] = _map_view.summary() if _map_view != null else {}
	# The settlement of the SELECTED room. Nested for the same reason, and its `reason`
	# carries the module's refusal id verbatim when it refuses — never a blank.
	place["settlement"] = _settlement.summary() if _settlement != null else {}
	# The telegraph of the SELECTED fixture. Nested for the same reason: it publishes its
	# own boundary, its own window and its own ledger booleans, so listing them here would
	# be the second copy of one fact — and the one that could disagree with the panel.
	place["telegraph"] = _telegraph.summary() if _telegraph != null else {}
	return place


func _refresh_view() -> void:
	_bind_nodes()
	var model := _read_model()
	if model == null:
		return
	model.refresh(_actor)
	_fill_templates()
	_fill_rooms()
	_fill_fixtures()
	# The floor plan and the settlement are both functions of WHERE THE PLAYER IS LOOKING
	# and WHAT THE MODULE PUBLISHED, so both are re-read on every refresh rather than
	# cached at bind time — a panel that read once would show the room the player left,
	# which is the stale-settlement defect DEF-0261 exists to end, reproduced one layer up.
	_refresh_map()
	_refresh_settlement()
	# The roster is a function of WHERE THE PLAYER IS, so it is re-read on every refresh
	# rather than cached at bind time. Everything above is the domain's own run; this is
	# the settlement outside it, and the player can walk between them at any time.
	_refresh_roster()
	# The telegraph is re-read on every refresh for the same reason and one more: a trap
	# is telegraphed by PRESENCE, which the composition root calls on its own tick, so the
	# screen did nothing to cause the state it is about to paint. A panel that only
	# refreshed on a press would show a quiet floor while the trap under the player's feet
	# was already counting down — which is the untelegraphed hazard ADR 0075 refuses.
	_refresh_telegraph()


## Re-read the SELECTED fixture's telegraph and hand it to the panel WHOLE. A re-read,
## not a cache of the last press: `inspect` is free and mutates nothing, so it is safe to
## call on every refresh and its answer is the truth right now. That is the whole reason
## this panel can show a telegraph a press did not produce — the player walked onto the
## trap, the composition root's tick armed it, and the next refresh picks that up.
##
## `{}` clears the panel whenever there is nothing to read, rather than leaving the last
## fixture's footprint standing next to a different selection.
func _refresh_telegraph() -> void:
	if _telegraph == null:
		return
	if _actor == null or _selected_room_id().is_empty() or _selected_fixture_id().is_empty():
		_telegraph.show_telegraph({})
		return
	_telegraph.show_telegraph(_read_telegraph())


## The module's own telegraph for the selected fixture, or `{}` when it will not answer.
##
## Routed through the bridge's `inspect_fixture` rather than a separate read verb, because
## ADR 0211 made `inspect` and `telegraph` the same call by construction — two ids for one
## read would be two things that could drift. No `delta` is passed and none can be: there
## is no argument here that would advance a window, which is what makes calling this from a
## repaint safe rather than a second button in disguise.
func _read_telegraph() -> Dictionary:
	var seam := _bridge()
	if seam == null or not seam.has(&"inspect_fixture"):
		return {}
	var ids := [_actor, _selected_room_id(), _selected_fixture_id()]
	return seam.call_action(&"inspect_fixture", ids)


## Hand the module's floor-plan payload to the view, WHOLE, plus the room the player is
## standing in.
##
## The player room is the SELECTION, and that is honest: the module publishes no tracked
## current room and no intra-room position (ADR 0206 says so outright), and the facade is at
## its cap, so there is nothing to read that would be more true. After a `Visit` the
## selection IS the room the actor walked into; before one it is the room they are LOOKING
## at, which is the same room surface every other verb here acts through. It is named in
## `summary()` as `player_room`, so a reader can see which room the mark follows.
func _refresh_map() -> void:
	if _map_view == null:
		return
	var model := _read_model()
	var payload: Dictionary = model.minimap() if model != null else {}
	_map_view.show_map(payload, _selected_room_id_for_map())
	# AFTER `show_map`, because the seam is computed against the authored list: the
	# payload's own `rooms[]` is the DISCOVERED subset, so the frontier needs the second
	# read to have anything to reach.
	_refresh_authored_rooms()


## The room the player's mark follows, as a plain string for the view's one door. The
## SELECTION is the honest stand-in — see [method _refresh_map] — and it is named
## `player_room` in the view's `summary()` so a reader sees which room the mark follows.
func _selected_room_id_for_map() -> String:
	return String(_selection().get("room", ""))


## Ask the view for the room list the run AUTHORED. The payload's `rooms[]` is the
## DISCOVERED subset, and the frontier seam is computed against the rooms fog hid
## (ADR 0207) — a seam asked of a fogged list is permanently empty, which is the whole
## failure ADR 0207 exists to end.
func _refresh_authored_rooms() -> void:
	if _map_view == null:
		return
	var model := _read_model()
	_map_view.set_authored_rooms(model.authored_rooms() if model != null else [])


## The settlement of the SELECTED room, or `{}` for any room that is not one. Keyed on
## the room the player is looking at rather than on a run of its own: a settlement is a
## `RoomDef.kind`, so it needs no route and no nav action (ADR 0209).
func _refresh_settlement() -> void:
	if _settlement == null:
		return
	_adopt_settlement_bridge()
	var room_id := _selected_room_id()
	if _actor == null or room_id.is_empty() or _settlement_bridge == null:
		_settlement.show_settlement({})
		return
	# `kind` is checked FIRST and by the payload's own word: a settlement is a room KIND,
	# and asking the settlement class about an ordinary room would only ever produce a
	# refusal the player has no action for. The institution itself never comes from this
	# payload — it comes from `DomainSettlement`, which resolves the fixture ref and
	# refuses it by name (ADR 0209).
	if _map_view == null or _map_view.kind_of({"room_id": String(room_id)}) != SETTLEMENT_KIND:
		_settlement.show_settlement({})
		return
	var about := _settlement_bridge.read_room(_actor, room_id)
	(
		_settlement
		. show_settlement(
			about,
			{
				"residents": about.get("residents", []),
				"truncated": bool(about.get("residents_truncated", false)),
			}
		)
	)


func _render() -> void:
	_bind_nodes()
	var model := _read_model()
	var lines := model.lines() if model != null else {}
	_header_label.text = L.t(String(lines.get("header", "Domains — no hero")))
	_status_label.text = L.t(String(lines.get("status", "Not inside a domain")))
	_map_label.text = L.t(String(lines.get("map", "No floor plan — no domain is active")))
	_rooms_label.text = L.t(String(lines.get("rooms", "No rooms known")))
	_population_label.text = L.t(String(lines.get("population", "Nobody is placed here yet")))
	_zones_label.text = L.t(String(lines.get("zones", "No severe environment authored here")))
	_fixture_label.text = L.t(String(lines.get("fixture", "No fixture in this room")))
	_enter_button.disabled = not _can_enter()
	_leave_button.disabled = not _can_leave()
	_visit_button.disabled = not _can_visit()
	_inspect_button.disabled = not _can_inspect()
	_attempt_button.disabled = not _can_attempt()
	_claim_button.disabled = not _can_claim()
	_publish_actions()
	_publish_message()
	_sync_selections()


## The model, built on first read and held after that. The `null` test is the guard, so
## the mint happens exactly once per screen and never on a repaint.
func _read_model() -> DomainExploreModel:
	if _model == null:
		_model = DomainExploreModel.new()
	return _model


## Every READ of the model goes through one of the helpers below, and each answers the
## empty vocabulary for a null model rather than raising — the shape the repo already
## uses for an absent bridge, where "nothing to show" is not a crash. The check belongs
## here, once per read, rather than in every caller; `_read_model()` itself is the one
## call that can still answer null.
func _bridge() -> DomainBridge:
	var model := _read_model()
	return model.bridge() if model != null else null


func _view() -> Dictionary:
	var model := _read_model()
	return model.active() if model != null else {}


func _selection() -> Dictionary:
	var model := _read_model()
	return model.selection() if model != null else {}


func _template_id() -> String:
	var model := _read_model()
	return model.template_id() if model != null else ""


func _fixture_kind() -> String:
	var model := _read_model()
	return model.fixture_kind() if model != null else ""


func _node_options() -> Array[StringName]:
	var model := _read_model()
	if model == null:
		var none: Array[StringName] = []
		return none
	return model.node_options()


## Hand a selector's index to the model, which holds the list that index names. A
## selection with no model to record it in is dropped, and the handler repaints anyway.
func _choose(selector: StringName, index: int) -> void:
	var model := _read_model()
	if model != null:
		model.choose(selector, index)


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
	_inspect_button = get_node_or_null("%InspectButton") as Button
	_attempt_button = get_node_or_null("%AttemptButton") as Button
	_claim_button = get_node_or_null("%ClaimButton") as Button
	_fixture_label = get_node_or_null("%FixtureLabel") as Label
	_message_label = get_node_or_null("%MessageLabel") as Label
	_actions = get_node_or_null("%Actions") as ActionSet
	_roster_panel = get_node_or_null("%Roster") as NpcRosterPanel
	_map_view = get_node_or_null("%MapView") as DomainMapView
	_settlement = get_node_or_null("%Settlement") as SettlementPanel
	_telegraph = get_node_or_null("%Telegraph") as DomainTelegraphPanel
	if _actions != null and not _actions.action_requested.is_connected(_on_action_requested):
		_actions.action_requested.connect(_on_action_requested)
	_connect_select(_template_option, _on_template_selected)
	_connect_select(_room_option, _on_room_selected)
	_connect_select(_fixture_option, _on_fixture_selected)
	_connect_select(_node_option, _on_node_selected)
	_connect_pressed(_enter_button, act_enter)
	_connect_pressed(_leave_button, act_leave)
	_connect_pressed(_visit_button, act_visit)
	_connect_pressed(_inspect_button, act_inspect)
	_connect_pressed(_attempt_button, act_attempt)
	_connect_pressed(_claim_button, act_claim)


# ── Actions. Each asks the bridge, then repaints from the untouched actor ─────────


## Generate and enter the selected authored template. The ONE production entry point
## into a domain, and calling it from a button is what makes the module reachable from
## the shipped program at all.
##
## The seed is [constant DEFAULT_SEED] first and then a small, BOUNDED walk of derived
## seeds — see [DomainSeedWalk] for why a refused seed cannot simply be retried forever
## and why the refusal is never swallowed. Two presses of this button still enter the
## SAME domain: the walk is a pure function of the template, so it picks the same first
## success for the same template every time.
func act_enter() -> bool:
	_bind_nodes()
	if not _can_enter():
		return _reject(_enter_reason())
	var template_id := _selected_template_id()
	var entered := _enter_with_a_generating_seed(StringName(template_id))
	return _settle(entered, "Entered %s" % template_id)


## The bounded seed walk, delegating to [DomainSeedWalk] and handing it this screen's own
## `enter` seam action — which is the only reason the walk needs no bridge reference, and
## the reason it can be driven by a test with one `Callable`.
func _enter_with_a_generating_seed(template_id: StringName) -> Dictionary:
	# Reached only through [method act_enter], which has already answered `_can_enter()`
	# — so the seam is non-null by construction. Read through the accessor anyway, so a
	# future caller reaching the walk without the gate gets a refusal, not a crash.
	var seam := _bridge()
	if seam == null:
		return {"ok": false, "reason": "no_inventory_bridge"}
	return DomainSeedWalk.walk(
		(
			(func(who: Actor, which: StringName, seed: int) -> Dictionary:
				return seam.call_action(&"enter", [who, which, seed]) as Dictionary)
			as Callable
		),
		_actor,
		template_id,
		DEFAULT_SEED
	)


## Leave the domain. The discovered set survives, so nothing the player found is lost.
func act_leave() -> bool:
	_bind_nodes()
	if not _can_leave():
		return _reject("no_map")
	return _settle(_bridge().call_action(&"leave", [_actor]), "Left the domain")


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
	var reached := _bridge().call_action(&"visit", [_actor, _selected_room_id(), &""])
	return _settle(reached, "Reached %s" % String(_selected_room_id()))


## Look at one fixture WITHOUT touching it. This is what the `Arm` button BECAME
## (ADR 0211): free, no `delta`, and mutating nothing.
##
## ## Why it must not be able to fire a trap
##
## Presence inside the authored footprint is the ONLY trigger, and the trap fires from
## `presence` on the composition root's tick. A button that reached `arm` made the player
## pay for having INSPECTED a trap rather than for having ENTERED one, and it opened and
## closed the telegraph window inside a single press — so the warning was unreachable and
## the unarmed player was the one who paid. So there is no `delta` parameter here at all:
## the verb has no way to express "fire it", which is the property that makes the rule
## structural rather than a matter of this screen's discipline.
##
## ## What the press DOES
##
## It asks the module what this fixture would cost and hands the answer WHOLE to
## [DomainTelegraphPanel], which owns every word and decimal on this surface. The answer
## is `telegraph`, so what the panel shows is the module's own payload rather than a
## second reading of the same fixture.
func act_inspect() -> bool:
	_bind_nodes()
	if not _can_inspect():
		return _reject(_inspect_reason())
	var read := _bridge().call_action(
		&"inspect_fixture", [_actor, _selected_room_id(), _selected_fixture_id()]
	)
	return _settle_inspect(read)


## Strike one node of a formation puzzle. A wrong node costs the ATTEMPT and never
## health, and the module names the node it expected — which is shown, not swallowed.
func act_attempt() -> bool:
	_bind_nodes()
	if not _can_attempt():
		return _reject(_attempt_reason())
	var struck := _bridge().call_action(
		&"attempt_fixture", [_actor, _selected_room_id(), _selected_fixture_id(), _puzzle_node_id()]
	)
	return _settle_fixture(struck)


## Open a treasure. Refused by name at every gate, in the order a player meets them.
func act_claim() -> bool:
	_bind_nodes()
	if not _can_claim():
		return _reject(_claim_reason())
	return _settle_fixture(
		_bridge().call_action(
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
	var model := _read_model()
	var accepted := model != null and model.select_room(room_id)
	refresh()
	return accepted


## Look at one fixture of the selected room. Same reasoning as [method select_room].
func select_fixture(fixture_id: StringName) -> bool:
	_bind_nodes()
	var model := _read_model()
	var accepted := model != null and model.select_fixture(fixture_id)
	refresh()
	return accepted


## Choose the puzzle node to strike, for a formation the player is solving. False when the
## selected fixture authors no such node, so a caller learns the node is not a real choice.
func select_node(node_id: StringName) -> bool:
	_bind_nodes()
	var model := _read_model()
	var accepted := model != null and model.select_node(node_id)
	refresh()
	return accepted


# ── Enabled state. Each verb states its OWN refusal rather than a bare "disabled" ──


func _can_enter() -> bool:
	var seam := _bridge()
	return (
		_actor != null
		and seam != null
		and seam.has(&"enter")
		and _view().is_empty()
		and not _template_id().is_empty()
	)


func _can_leave() -> bool:
	var seam := _bridge()
	return _live() and seam != null and seam.has(&"leave")


## `Visit` needs a run, the verb, and a room the MODULE actually holds.
##
## The pending-room check is what turns a refused [method select_room] into a refusal of
## the verb rather than a silent walk into the previous room: a pending id means the
## caller named a room this run does not have, so the verb must say so by name.
func _can_visit() -> bool:
	if not _pending_room().is_empty():
		return false
	var seam := _bridge()
	return _live() and seam != null and seam.has(&"visit") and not _selected_room_id().is_empty()


func _can_inspect() -> bool:
	return _gates().can_act(&"inspect_fixture")


func _can_attempt() -> bool:
	return _gates().can_attempt()


func _can_claim() -> bool:
	return _gates().can_act(&"claim_fixture")


## Whether a run is active and the bridge can reach the verb at all.
func _live() -> bool:
	return _actor != null and _bridge() != null and not _view().is_empty()


## The gate set, pointed at the CURRENT state of this screen.
##
## Built fresh on each read and never cached, for the same reason the telegraph is re-read
## every refresh: a cached gate answers about the moment it was minted, so a selection that
## moved would leave a button enabled against a fixture that is no longer selected. The
## object holds no widget and no bridge — only the four facts a decision needs — which is
## what lets a screen ask a question without reaching past its own `_bind_nodes`.
func _gates() -> DomainFixtureGates:
	var gates := DomainFixtureGates.new()
	var seam := _bridge()
	gates.evaluate(
		_live(),
		(func(action: StringName) -> bool: return seam != null and seam.has(action)) as Callable,
		_fixture_kind(),
		_selected_fixture_id(),
		_puzzle_nodes()
	)
	return gates


func _enter_reason() -> String:
	var seam := _bridge()
	if _actor == null or seam == null:
		return "no_actor"
	if not seam.has(&"enter"):
		return "no_inventory_bridge"
	if _template_id().is_empty():
		return "no_such_template"
	return "no_map"


func _visit_reason() -> String:
	if not _live():
		return "no_map"
	var seam := _bridge()
	if seam == null or not seam.has(&"visit"):
		return "no_inventory_bridge"
	return "unknown_room"


## A refusal of the READ rather than of an action. `unknown_fixture` is the honest
## fallback: `inspect` touches nothing and refuses nothing an actor could have caused,
## so the only reasons it can carry are "this seam is not wired" and "this fixture is
## not the one the verb reads".
func _inspect_reason() -> String:
	return _gates().reason_for(&"inspect_fixture")


## `authors_nothing_to_grant` is checked BEFORE the gate, and stays here rather than moving
## with the rest: it is not a bridge fact but a fact about the AUTHORED nodes, so it reads
## the selection directly. Everything after it is the gate's own answer.
func _attempt_reason() -> String:
	if _puzzle_nodes().is_empty():
		return "authors_nothing_to_grant"
	return _gates().reason_for(&"attempt_fixture")


func _claim_reason() -> String:
	return _gates().reason_for(&"claim_fixture")


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
		"inspect": _can_inspect(),
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
	var model := _read_model()
	if model == null:
		_fill(_template_option, [])
		return
	_fill(_template_option, model.template_options())
	model.keep_template(model.template_id())


## Fill the room selector from the AUTHORED room list, so every room in the run is
## reachable and not only the ones the floor plan has already drawn.
func _fill_rooms() -> void:
	if _room_option == null:
		return
	var model := _read_model()
	_fill(_room_option, model.room_options() if model != null else [])


## Fill the fixture and node selectors from the SELECTED room. A room is the only place a
## fixture exists — `DomainFixtures._resolve` refuses by name outside one — so the list
## empties rather than offering buttons aimed at another room. No nodes is honest: a trap
## and a treasure have none to strike, so the node row says so by being disabled.
func _fill_fixtures() -> void:
	if _fixture_option == null or _node_option == null:
		return
	var model := _read_model()
	_fill(_fixture_option, model.fixture_options() if model != null else [])
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
		_message_label.text = L.t(_message)
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
	var model := _read_model()
	if model == null:
		return
	var at := model.selection_indices()
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
## on, and a worded sentence alone would leave both of them pattern-matching prose. The
## composition itself is [DomainOutcome]'s.
func _settle_fixture(result: Dictionary) -> bool:
	var reason := String(result.get("reason", ""))
	var accepted := bool(result.get("ok", false))
	_fixture_message = (
		DomainOutcome.accepted(_selected_fixture_id(), reason)
		if accepted
		else DomainOutcome.refused(_selected_fixture_id(), reason, _reason_text(reason))
	)
	_fixture_tone = TONE_OK if accepted else TONE_ERROR
	set_message(_fixture_message, _fixture_tone)
	refresh()
	return accepted


## The free read's outcome, which is NOT [method _settle_fixture] and deliberately so.
##
## `inspect` answers with an EMPTY reason on success (`domain_fixtures.gd:533`), because
## nothing happened: no state moved, no health was spent, nothing is owed. Routing it
## through the action path would print an empty id beside the fixture name and leave a
## driver pattern-matching for a token that cannot exist. So an acceptance says what it
## DID — read — and the payload itself goes to the panel, which is the only place the
## numbers are worded.
##
## ## Why the panel is fed BEFORE the repaint
##
## [method refresh] re-reads the telegraph from the bridge anyway
## ([method _refresh_telegraph]), so the panel cannot be showing a stale payload even if
## this press did not happen. The explicit feed is what makes the press IMMEDIATE rather
## than next-refresh.
func _settle_inspect(result: Dictionary) -> bool:
	if not bool(result.get("ok", false)):
		return _reject(String(result.get("reason", "unknown_fixture")))
	if _telegraph != null:
		_telegraph.show_telegraph(result)
	_fixture_message = DomainOutcome.read(_selected_fixture_id())
	_fixture_tone = TONE_OK
	set_message(_fixture_message, _fixture_tone)
	refresh()
	return true


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
	# Composed ONCE, by [DomainOutcome.refused]. Re-wrapping this here would prefix the
	# fixture id a second time, so a repeated refusal read "ash_x: ash_x: ...".
	var worded := _reason_text(reason)
	_fixture_message = DomainOutcome.refused(_selected_fixture_id(), reason, worded)
	_fixture_tone = TONE_ERROR
	set_message(_fixture_message, _fixture_tone)
	refresh()
	return false


## The player-facing sentence for a reason id, as `DomainBridge.REASON_TEXT` words it.
## Falls back to the id itself when no seam is bound — a reason this build has no wording
## for must still be REPORTED rather than dropped.
func _reason_text(reason: String) -> String:
	var seam := _bridge()
	return seam.reason_text(reason) if seam != null else reason


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
	_choose(&"template", index)
	refresh()


func _on_room_selected(index: int) -> void:
	_choose(&"room", index)
	refresh()


func _on_fixture_selected(index: int) -> void:
	_choose(&"fixture", index)
	refresh()


func _on_node_selected(index: int) -> void:
	_choose(&"node", index)
	refresh()


# ── The model's selection, read through the gates and the verbs ───────────────


func _selected_room_id() -> StringName:
	return StringName(_selection().get("room", ""))


func _selected_fixture_id() -> StringName:
	return StringName(_selection().get("fixture", ""))


func _puzzle_node_id() -> StringName:
	return StringName(_selection().get("node", ""))


func _pending_room() -> StringName:
	return StringName(_selection().get("pending", ""))


func _puzzle_nodes() -> Array[StringName]:
	return _node_options()


func _selected_template_id() -> String:
	return _template_id()
