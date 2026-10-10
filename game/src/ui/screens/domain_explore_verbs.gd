class_name DomainExploreVerbs
extends RefCounted

## The verb layer of [DomainExploreScreen]: the action table, the six gates, the refusal
## each states, and the three one-line helpers that wire a control.
##
## Extracted when the screen outgrew gdlint's `max-file-lines` ceiling. It holds NO
## screen, NO node and NO bridge: every read arrives through one `facts` dictionary the
## screen builds ([method DomainExploreScreen._facts]), which is what keeps the property
## the gates were designed around — a gate cannot reach past its caller's own
## `_bind_nodes`, so a button's offered state and the verb that answers it stay the same
## fact. A refusal names the MODULE's reason id; the wording is [DomainBridge]'s table,
## never this file's.

## The six actions [DomainExploreScreen] offers, in the order a player meets them.
## Declared as data so the button row, the summary and the enabled map cannot disagree
## about the set.
const IDS: Array[StringName] = [&"enter", &"visit", &"inspect", &"attempt", &"claim", &"leave"]

## The label each action's row carries. The KEYS are the labels' own keys, resolved at
## display time (ADR 0916).
const LABELS := {
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
## A TABLE rather than a chain of `match` arms, because a dispatch is the least
## interesting thing in this layer. An id the screen does not offer is refused BY NAME
## rather than ignored, so a driver learns it asked wrongly instead of seeing a silent
## no-op.
const HANDLERS := {
	&"enter": "act_enter",
	&"leave": "act_leave",
	&"visit": "act_visit",
	&"inspect": "act_inspect",
	&"attempt": "act_attempt",
	&"claim": "act_claim",
}


## Whether a run is active and the bridge can reach the verb at all.
static func live(facts: Dictionary) -> bool:
	return (
		bool(facts.get("has_actor", false))
		and facts.get("seam", null) != null
		and not bool(facts.get("view_empty", true))
	)


## Whether the ENTER verb may run: an actor, a seam that reaches it, no run standing,
## and a template the model holds.
static func can_enter(facts: Dictionary) -> bool:
	var seam := facts.get("seam", null) as DomainBridge
	return (
		bool(facts.get("has_actor", false))
		and seam != null
		and seam.has(&"enter")
		and bool(facts.get("view_empty", false))
		and String(facts.get("template_id", "")) != ""
	)


static func can_leave(facts: Dictionary) -> bool:
	var seam := facts.get("seam", null) as DomainBridge
	return live(facts) and seam != null and seam.has(&"leave")


## `Visit` needs a run, the verb, and a room the MODULE actually holds.
##
## The pending-room check is what turns a refused [method DomainExploreScreen.select_room]
## into a refusal of the verb rather than a silent walk into the previous room: a pending
## id means the caller named a room this run does not have, so the verb must say so by
## name.
static func can_visit(facts: Dictionary) -> bool:
	if String(facts.get("pending", "")) != "":
		return false
	var seam := facts.get("seam", null) as DomainBridge
	return (
		live(facts)
		and seam != null
		and seam.has(&"visit")
		and String(facts.get("room_id", "")) != ""
	)


static func can_inspect(facts: Dictionary) -> bool:
	return gates(facts).can_act(&"inspect_fixture")


static func can_attempt(facts: Dictionary) -> bool:
	return gates(facts).can_attempt()


static func can_claim(facts: Dictionary) -> bool:
	return gates(facts).can_act(&"claim_fixture")


## The gate set, pointed at the CURRENT state of its caller.
##
## Built fresh on each read and never cached, for the same reason the telegraph is
## re-read every refresh: a cached gate answers about the moment it was minted, so a
## selection that moved would leave a button enabled against a fixture that is no longer
## selected. The object holds no widget and no bridge — only the four facts a decision
## needs.
static func gates(facts: Dictionary) -> DomainFixtureGates:
	var seam := facts.get("seam", null) as DomainBridge
	var gates := DomainFixtureGates.new()
	gates.evaluate(
		live(facts),
		(func(action: StringName) -> bool: return seam != null and seam.has(action)) as Callable,
		String(facts.get("fixture_kind", "")),
		StringName(facts.get("fixture_id", "")),
		facts.get("nodes", []) as Array[StringName]
	)
	return gates


static func enter_reason(facts: Dictionary) -> String:
	var seam := facts.get("seam", null) as DomainBridge
	if not bool(facts.get("has_actor", false)) or seam == null:
		return "no_actor"
	if not seam.has(&"enter"):
		return "no_inventory_bridge"
	if String(facts.get("template_id", "")) == "":
		return "no_such_template"
	return "no_map"


static func visit_reason(facts: Dictionary) -> String:
	if not live(facts):
		return "no_map"
	var seam := facts.get("seam", null) as DomainBridge
	if seam == null or not seam.has(&"visit"):
		return "no_inventory_bridge"
	return "unknown_room"


## A refusal of the READ rather than of an action. `unknown_fixture` is the honest
## fallback: `inspect` touches nothing and refuses nothing an actor could have caused,
## so the only reasons it can carry are "this seam is not wired" and "this fixture is
## not the one the verb reads".
static func inspect_reason(facts: Dictionary) -> String:
	return gates(facts).reason_for(&"inspect_fixture")


## `authors_nothing_to_grant` is checked BEFORE the gate: it is not a bridge fact but a
## fact about the AUTHORED nodes, which is why it reads the node list directly.
## Everything after it is the gate's own answer.
static func attempt_reason(facts: Dictionary) -> String:
	if (facts.get("nodes", []) as Array[StringName]).is_empty():
		return "authors_nothing_to_grant"
	return gates(facts).reason_for(&"attempt_fixture")


static func claim_reason(facts: Dictionary) -> String:
	return gates(facts).reason_for(&"claim_fixture")


## What each of the six verbs is right now. The panel's own halves are added by the
## screen, which owns the `ActionSet`.
static func flags(facts: Dictionary) -> Dictionary:
	return {
		"enter": can_enter(facts),
		"leave": can_leave(facts),
		"visit": can_visit(facts),
		"inspect": can_inspect(facts),
		"attempt": can_attempt(facts),
		"claim": can_claim(facts),
	}


## A guarded connect. Every one of them, so a re-bound screen has one handler per press.
static func connect_pressed(button: Button, handler: Callable) -> void:
	if button != null and not button.pressed.is_connected(handler):
		button.pressed.connect(handler)


## The four selectors are wired to ONE handler each; this is the guarded half of that,
## shared so the rule cannot drift between them.
static func connect_select(option: OptionButton, handler: Callable) -> void:
	if option != null and not option.item_selected.is_connected(handler):
		option.item_selected.connect(handler)


## Repaint a selector against the list it was filled from, without re-emitting
## `item_selected` — so a programmatic `select()` cannot be mistaken for a click and
## re-enter the handler that set it.
static func select_index(option: OptionButton, index: int) -> void:
	if option != null and index >= 0 and index < option.item_count:
		option.select(index)


static func text_of(label: Label) -> String:
	return "" if label == null else label.text


## Fill the domain selector from the AUTHORED catalogue. Presentation only: the screen
## never invents a domain, and the rows carry the id beside the label because the row a
## player reads and the row a driver aims at are the same row.
static func fill_templates(option: OptionButton, model: DomainExploreModel) -> void:
	if option == null:
		return
	if model == null:
		fill(option, [])
		return
	fill(option, model.template_options())
	model.keep_template(model.template_id())


## Fill the room selector from the AUTHORED room list, so every room in the run is
## reachable and not only the ones the floor plan has already drawn.
static func fill_rooms(option: OptionButton, model: DomainExploreModel) -> void:
	if option == null:
		return
	fill(option, model.room_options() if model != null else [])


## Fill the fixture and node selectors from the SELECTED room. A room is the only place a
## fixture exists — `DomainFixtures._resolve` refuses by name outside one — so the list
## empties rather than offering buttons aimed at another room. No nodes is honest: a trap
## and a treasure have none to strike, so the node row says so by being disabled.
static func fill_fixtures(
	fixture: OptionButton, node: OptionButton, model: DomainExploreModel, nodes: Array
) -> void:
	if fixture == null or node == null:
		return
	fill(fixture, model.fixture_options() if model != null else [])
	var labels: Array = []
	for entry in nodes:
		labels.append(String(entry))
	fill(node, labels)
	node.disabled = nodes.is_empty()


## Replace an option list's rows. Every refill goes through here because the rule is the
## same each time, and one place to keep it is one place for the four to agree.
static func fill(option: OptionButton, labels: Array) -> void:
	option.clear()
	for label in labels:
		option.add_item(String(label))


## Push the action row's own state: the ids in table order, the labels, and which of them
## are live. Only ids and booleans go down; the panel owns the wording and the figures.
static func publish(actions: ActionSet, flags: Dictionary) -> void:
	if actions == null:
		return
	var enabled := {}
	for action in IDS:
		enabled[String(action)] = bool(flags.get(String(action), false))
	var state := {
		"actions": IDS,
		"labels": LABELS,
		"enabled": enabled,
		"primary": &"enter" if bool(enabled["enter"]) else &"visit",
	}
	actions.set_state(state)


## The outcome line in both places a reader can see it. `WarnLabel` on a refusal and
## `OkLabel` on an acceptance are THEME VARIATIONS rather than per-node colours, so the
## palette stays in the one theme (the UI standard; BL-0084).
static func publish_message(
	actions: ActionSet, label: Label, message: String, tone: StringName
) -> void:
	if actions != null:
		actions.set_message(message, tone)
	if label != null:
		label.text = L.t(message)
		label.theme_type_variation = tone_variation(tone)


static func tone_variation(tone: StringName) -> StringName:
	match tone:
		UiScreen.TONE_ERROR:
			return &"WarnLabel"
		UiScreen.TONE_OK:
			return &"OkLabel"
		_:
			return &"MetaLabel"


## Repaint the four selectors against the lists they were just filled from, without
## re-emitting `item_selected` — so a programmatic `select()` cannot be mistaken for a
## click and re-enter the handler that set it.
static func sync_selections(
	template: OptionButton, room: OptionButton, fixture: OptionButton, node: OptionButton, at: Array
) -> void:
	select_index(template, int(at[0]))
	select_index(room, int(at[1]))
	select_index(fixture, int(at[2]))
	select_index(node, int(at[3]))
