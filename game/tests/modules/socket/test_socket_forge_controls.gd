extends TestCase

## The SOCKET FORGE surface, driven through the buttons and selectors a player
## presses.
##
## `test_socket_forge.gd` calls `act_create_slot()`, `act_impute_slot()`,
## `act_insert_socket()` and `act_extract_socket()` directly. That proves the
## screen's handlers work; it proves nothing about whether the RENDERED controls
## reach them. `ActionSet` builds its buttons at runtime, so a `set_state()` that
## stopped declaring the actions would leave every case in that suite green while
## the forge showed no buttons at all — and a connect that was never made leaves
## buttons that render, sit lit, and do nothing.
##
## So every case here presses the screen's own `ActionSet` buttons by the names
## that panel gives them (`CreateSlotButton`, `ImputeSlotButton`, …) and the three
## `OptionButton` selectors, and asserts an OBSERVABLE OUTCOME in the socket
## ledger: a slot exists, carries its own imputed modifiers, holds the chosen gem,
## and empties again on extract.
##
## The screen is a pure view — it hands an intent to whoever owns the gameplay
## program and the program pushes the next read model back. So this harness plays
## the composition root: it runs the facade on the screen's signal and rebinds the
## view. That IS the shipped path; the only thing this suite changes is that the
## intent arrives from a button press rather than a direct call.

const HOST := &"socket_host_rare_blade"
const SLOT_REAGENT := &"socket_reagent_mortal_slot_offense"
const INK := &"socket_reagent_mortal_imputation"
const WASH := &"socket_reagent_mortal_enchantment"
const GEM := &"socket_rune_mortal_offense"

var _rig: ItemSurfaceRig = null
var _screen: SocketForgeScreen = null
var _actor: Actor = null
## Intents the screen handed over, newest last. Read so a case can assert the
## press produced the intent the player asked for, not merely that something ran.
var _requests: Array = []


func setup() -> void:
	expect_assertions(2)
	_rig = ItemSurfaceRig.new()


func teardown() -> void:
	# `release()` frees the screen, and freeing a node disconnects its signals, so
	# the handler this suite connected dies with it. Idempotent, so a test that
	# aborted mid-way still leaves nothing mounted.
	_rig.release()
	_screen = null
	_actor = null
	_requests.clear()


## A forge hero carrying one host, plus whatever reagents the case asks for, with
## the screen mounted and bound to the facade's own read model.
func _forge(content: Array[StringName] = []) -> SocketForgeScreen:
	_actor = _rig.forge_hero()
	assert_ne(_rig.acquire(_actor, HOST, 5150), null, "the socket host is acquired")
	for def_id in content:
		assert_eq(_rig.stock_authored(_actor, def_id, 2), true, "'%s' is stocked" % String(def_id))
	_screen = _rig.screen(ItemSurfaceRig.FORGE_SCENE) as SocketForgeScreen
	if _screen == null:
		return null
	_screen.setup(_actor)
	_screen.socket_action_requested.connect(_on_request)
	_push()
	return _screen


func _on_request(action: StringName, args: Dictionary) -> void:
	_requests.append({"action": String(action), "args": args})


## Republish the socket program's read model, which is what the composition root
## does after running a transaction.
func _push() -> void:
	_screen.bind_view(SocketApi.panel_state(_actor))


## Play the intent the screen just handed over against the facade, and republish.
## Returns whether the program committed it.
func _play_last() -> bool:
	if _requests.is_empty():
		return false
	var request := _requests.pop_back() as Dictionary
	var action := StringName(String(request["action"]))
	var args: Dictionary = request["args"]
	var host := String(SocketApi.panel_state(_actor).get("parent", {}).get("instance_id", ""))
	var committed := false
	match action:
		&"create_slot":
			committed = bool(
				(
					SocketApi
					. create_slot(_actor, StringName(host), StringName(String(args["reagent_id"])))["ok"]
				)
			)
		&"impute_slot":
			committed = bool(
				(
					SocketApi
					. impute_slot(
						_actor,
						StringName(host),
						int(args["index"]),
						StringName(String(args["reagent_id"]))
					)["ok"]
				)
			)
		&"insert_socket":
			committed = bool(
				(
					SocketApi
					. insert_socket(
						_actor,
						StringName(host),
						int(args["index"]),
						StringName(String(args["gem_instance_id"]))
					)["ok"]
				)
			)
		&"extract_socket":
			committed = bool(
				SocketApi.extract_socket(_actor, StringName(host), int(args["index"]))["ok"]
			)
	_push()
	return committed


# --- Opening a socket, through the button ------------------------------------


## The first observable step: pressing `Open socket` spends the reagent and leaves
## a slot on the host. Read from the socket program's own state, not from the
## screen's rendering, so a screen that painted a slot nobody owns cannot pass.
func test_pressing_open_socket_creates_a_slot_on_the_host() -> void:
	var forge := _forge([SLOT_REAGENT])
	assert_ne(forge, null, "the forge scene mounts")
	assert_eq(int(SocketApi.panel_state(_actor).get("slot_count", 0)), 0, "no slot yet")
	assert_eq(bool(forge.summary()["can_create"]), true, "the action is offered")
	assert_eq(_rig.press_action(forge, &"create_slot"), true, "the Open socket button is pressable")
	assert_eq(_play_last(), true, "the program committed the intent the press handed over")
	assert_eq(
		int(SocketApi.panel_state(_actor).get("slot_count", 0)),
		1,
		"the observable outcome: the host now carries a slot"
	)
	assert_eq(
		ItemsApi.inventory(_actor).count(SLOT_REAGENT), 1, "and one reagent was spent to open it"
	)


## And the screen republishes it, so the slot the player just opened is on the
## surface rather than only in the ledger.
func test_the_opened_slot_is_on_the_screen_after_the_press() -> void:
	var forge := _forge([SLOT_REAGENT, INK])
	_rig.press_action(forge, &"create_slot")
	_play_last()
	var view := forge.summary()
	assert_eq(int(view["slot_count"]), 1, "the screen lists the slot")
	assert_eq(bool(view["slots"]["0"]["has_slot"]), true, "and the slot row renders itself")
	assert_eq(bool(view["can_impute"]), true, "so the next action is offered too")


# --- Imputing and filling it, through the buttons ----------------------------


## The whole transaction from the host's three buttons, asserted against the
## ledger at each step. `ActionSet` names its buttons after the action ids, so
## `impute_slot` is `ImputeSlotButton`; a screen that declared its actions under
## different ids would show different buttons and fail here rather than silently
## offering nothing.
func test_the_three_buttons_open_impute_and_fill_a_socket() -> void:
	var forge := _forge([SLOT_REAGENT, INK])
	assert_ne(_rig.acquire(_actor, GEM, 5252), null, "a socket item is carried")
	_push()
	assert_eq(_rig.press_action(forge, &"create_slot"), true, "Open socket is pressable")
	assert_eq(_play_last(), true, "the slot opened")
	assert_eq(_rig.press_action(forge, &"impute_slot"), true, "Imprint socket is pressable")
	assert_eq(_play_last(), true, "the slot was imputed")
	assert_eq(_rig.press_action(forge, &"insert_socket"), true, "Insert socket item is pressable")
	assert_eq(_play_last(), true, "the socket item was seated")

	var view := forge.summary()
	assert_eq(int(view["slot_count"]), 1, "the slot is listed")
	assert_eq(bool(view["slot_occupied"]), true, "and it is occupied")
	assert_eq(
		int((view["slots"]["0"] as Dictionary)["imputed_count"]) > 0,
		true,
		"the slot carries its OWN imputed modifiers, kept apart from the gem's"
	)
	assert_eq(
		int((view["slots"]["0"] as Dictionary)["gem_effect_count"]) > 0,
		true,
		"and the seated gem's own modifiers are shown too"
	)


## The gem that lands is the one the SELECTOR chose. Two socket items are carried
## so index 0 is not the only answer, and the press must take the second.
func test_the_gem_selector_chooses_which_socket_item_is_seated() -> void:
	var forge := _forge([SLOT_REAGENT])
	var first := _rig.acquire(_actor, GEM, 5353)
	var second := _rig.acquire(_actor, GEM, 5354)
	_push()
	_rig.press_action(forge, &"create_slot")
	_play_last()
	assert_eq(int(forge.summary()["gem_count"]), 2, "two socket items are offered")
	assert_eq(_rig.choose(forge, "%GemOption", 1), true, "the second gem is chosen")
	assert_eq(_rig.press_action(forge, &"insert_socket"), true, "Insert socket item is pressable")
	assert_eq(_play_last(), true, "the socket item was seated")
	var slot: Dictionary = forge.summary()["slots"]["0"]
	assert_eq(
		String(slot["gem_instance_id"]),
		String(second.instance_id),
		"the observable outcome: the gem the SELECTOR chose is the one seated"
	)
	assert_ne(String(first.instance_id), String(second.instance_id), "the two gems are distinct")


## Extract, from the button. A dark Extract that quietly did nothing would leave
## the occupied flag above set forever.
func test_pressing_extract_empties_the_slot_and_keeps_the_imputation() -> void:
	var forge := _forge([SLOT_REAGENT, INK])
	_rig.acquire(_actor, GEM, 5454)
	_push()
	for action in [&"create_slot", &"impute_slot", &"insert_socket"]:
		_rig.press_action(forge, action)
		_play_last()
	assert_eq(bool(forge.summary()["slot_occupied"]), true, "the slot is full to begin with")
	assert_eq(_rig.press_action(forge, &"extract_socket"), true, "Extract socket item is pressable")
	assert_eq(_play_last(), true, "the gem was taken back out")
	var view := forge.summary()
	assert_eq(bool(view["slot_occupied"]), false, "the observable outcome: the slot is empty again")
	assert_eq(
		int((view["slots"]["0"] as Dictionary)["imputed_count"]) > 0,
		true,
		"and the slot's own imputation survived the gem leaving"
	)


# --- The controls the program says are unavailable ---------------------------


## A screen that offers an action the program would refuse is the defect the
## `eligibility` map exists to prevent, so the negative case is stated at the
## control: with no reagent carried the button must be DARK, and a press on a dark
## button must move nothing.
func test_a_disabled_action_is_a_dark_button_and_pressing_it_moves_nothing() -> void:
	var forge := _forge()
	assert_ne(forge, null, "the forge scene mounts")
	var view := forge.summary()
	assert_eq(bool(view["can_impute"]), false, "the program says impute is unavailable")
	assert_eq(
		_rig.button(forge, "%Actions").find_child("ImputeSlotButton", true, false) != null,
		true,
		"the button is still on the screen"
	)
	assert_eq(
		_rig.press_action(forge, &"impute_slot"),
		false,
		"but a player cannot press a disabled control, so the press is refused"
	)
	assert_eq(_requests.size(), 0, "and nothing was handed to the program")
	assert_eq(
		int(SocketApi.panel_state(_actor).get("slot_count", 0)),
		0,
		"so the host still carries no slot"
	)


## Every action the forge offers is a live button once the actions are declared.
## Without this, a case above could fail for a reason that has nothing to do with
## sockets — an `ActionSet` that built no buttons at all.
func test_every_offered_action_is_a_button_on_the_screen() -> void:
	var forge := _forge([SLOT_REAGENT, INK, WASH])
	_push()
	var actions := forge.summary()["actions"] as Dictionary
	assert_eq((actions["actions"] as Array).size(), 5, "the forge declares five actions")
	var found := 0
	for action_id in actions["actions"]:
		var name := "%sButton" % String(action_id).to_pascal_case()
		if _rig.button(forge, "%Actions").find_child(name, true, false) != null:
			found += 1
	assert_eq(found, 5, "every declared action is a button the screen renders")


# --- The enchantment control -------------------------------------------------


## Enchant, through the button. The observable outcome is the treatment count on
## the host's own channel, which is what a player pays a reagent for.
func test_pressing_enchant_spends_a_treatment_on_the_host() -> void:
	var forge := _forge([WASH])
	assert_ne(forge, null, "the forge scene mounts")
	_push()
	var view := forge.summary()
	assert_eq(bool(view["can_enchant"]), true, "the action is offered")
	assert_eq(int(view["enchant_generation"]), 0, "no treatment applied yet")
	assert_eq(_rig.press_action(forge, &"enchant"), true, "the enchant button is pressable")
	assert_eq(_requests.size(), 1, "the press handed exactly one intent over")
	assert_eq(String((_requests[0] as Dictionary)["action"]), "enchant", "and it is the right one")
	assert_eq(
		String((_requests[0] as Dictionary)["args"]["reagent_id"]),
		String(WASH),
		"naming the reagent it would spend, so the player sees the cost"
	)
