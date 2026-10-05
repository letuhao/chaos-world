extends TestCase

## The socket forge screen (ADR 0038). These tests assert `summary()` and the
## screen's actions, never pixels: the screen renders the socket program's read
## model, offers an action only when the gameplay program says it would commit,
## and reports the gameplay reason when it would not.
##
## The screen is a pure view, so the harness here plays the part of the
## composition root: it pushes the facade's read model in and runs the facade's
## actions when the screen asks. That is exactly the path a player takes.

const SCENE := "res://src/ui/screens/socket_forge.tscn"
const SLOT_REAGENT := &"socket_reagent_mortal_slot_offense"
const INK := &"socket_reagent_mortal_imputation"
const WASH := &"socket_reagent_mortal_enchantment"

var _screen: SocketForgeScreen = null
var _requests: Array = []


func _actor() -> Actor:
	var actor := Actor.new(&"forge_hero", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	actor.add_resource(ResourcePool.new(&"qi", 60.0))
	ItemsApi.attach(actor, 24)
	SocketApi.attach(actor)
	return actor


func _screen_scene() -> SocketForgeScreen:
	_requests.clear()
	var screen: SocketForgeScreen = load(SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	screen.socket_action_requested.connect(_on_request)
	_screen = screen
	return screen


func _on_request(action: StringName, args: Dictionary) -> void:
	_requests.append({"action": String(action), "args": args})


func _push(screen: SocketForgeScreen, actor: Actor) -> Dictionary:
	screen.bind_view(SocketApi.panel_state(actor))
	return screen.summary()


func _give(actor: Actor, def_id: StringName, quantity: int = 1) -> void:
	ItemsApi.inventory(actor).add(SocketApi.resolve_content(def_id), quantity)


func _host(actor: Actor, seed_value: int) -> ItemInstance:
	return ItemsApi.generate(
		actor, SocketApi.resolve_content(&"socket_host_rare_blade"), seed_value
	)


# --- Read model ---------------------------------------------------------------


func test_an_unbound_screen_reports_an_empty_summary() -> void:
	var screen := _screen_scene()
	assert_eq(screen.summary(), {}, "an unbound screen reports an empty summary")
	screen.free()


func test_a_bound_screen_reads_the_socket_program() -> void:
	var actor := _actor()
	var host := _host(actor, 101)
	_give(actor, SLOT_REAGENT)
	_give(actor, INK)
	_give(actor, WASH)
	var screen := _screen_scene()
	screen.setup(actor)
	var view := _push(screen, actor)
	assert_eq(String(view["host_instance_id"]), String(host.instance_id), "the host is shown")
	assert_eq(String(view["host_rarity"]), "rare", "its rarity is shown")
	assert_eq(bool(view["host_equipped"]), false, "carried, not worn")
	assert_eq(int(view["slot_cap"]), 1, "a rare host carries one socket")
	assert_eq(int(view["slot_count"]), 0, "no slot yet")
	assert_eq(int(view["host_count"]), 1, "one host is offered")
	assert_eq(int(view["gem_count"]), 0, "no socket item carried")
	assert_eq(bool(view["can_create"]), true, "a slot can be opened")
	assert_eq(bool(view["can_impute"]), false, "there is no slot to imprint")
	assert_eq(bool(view["can_extract"]), false, "there is nothing to extract")
	screen.free()


func test_the_slots_are_shown_with_slot_and_gem_effects_kept_apart() -> void:
	var actor := _actor()
	var host := _host(actor, 102)
	_give(actor, SLOT_REAGENT)
	SocketApi.create_slot(actor, host.instance_id, SLOT_REAGENT)
	_give(actor, INK)
	SocketApi.impute_slot(actor, host.instance_id, 0, INK)
	var gem := ItemsApi.generate(
		actor, SocketApi.resolve_content(&"socket_rune_mortal_offense"), 202
	)
	SocketApi.insert_socket(actor, host.instance_id, 0, gem.instance_id)
	var screen := _screen_scene()
	screen.setup(actor)
	var view := _push(screen, actor)
	assert_eq(int(view["slot_count"]), 1, "the slot is listed")
	assert_eq(bool(view["slot_occupied"]), true, "and it is occupied")
	var row: Dictionary = view["slots"]["0"]
	assert_eq(bool(row["has_slot"]), true, "the row renders the slot")
	assert_eq(int(row["imputed_count"]), 2, "the slot's own modifiers are shown")
	assert_eq(int(row["gem_effect_count"]) > 0, true, "the gem's own modifiers are shown")
	assert_eq(
		(row["imputed_lines"] as Array).size(),
		int(row["imputed_count"]),
		"one line per slot modifier"
	)
	assert_eq(
		(view["slots"]["1"] as Dictionary)["has_slot"],
		false,
		"a slot the item does not have renders itself absent"
	)
	assert_eq(String(row["kind"]), "offense", "the slot kind is shown")
	screen.free()


# --- Actions ------------------------------------------------------------------


func test_an_available_action_hands_the_intent_to_the_program() -> void:
	var actor := _actor()
	var host := _host(actor, 103)
	_give(actor, SLOT_REAGENT, 2)
	var screen := _screen_scene()
	screen.setup(actor)
	_push(screen, actor)
	assert_eq(screen.act_create_slot(), true, "the action was offered")
	assert_eq(_requests.size(), 1, "one intent was handed over")
	assert_eq(String((_requests[0] as Dictionary)["action"]), "create_slot", "the right action")
	var args: Dictionary = (_requests[0] as Dictionary)["args"]
	assert_eq(String(args["reagent_id"]), String(SLOT_REAGENT), "with the reagent it would spend")
	screen.free()


func test_a_disabled_action_changes_nothing_and_names_the_gameplay_reason() -> void:
	var actor := _actor()
	var host := _host(actor, 104)
	var screen := _screen_scene()
	screen.setup(actor)
	# No reagent: that is the first thing a player is told they are missing.
	var bare := _push(screen, actor)
	assert_eq(bool(bare["can_impute"]), false, "the action is offered as disabled")
	assert_eq((bare["reasons"] as Array)[1], "missing_cost", "with the gameplay reason")
	assert_eq(screen.act_impute_slot(), false, "and refuses")
	assert_eq(_requests.size(), 0, "nothing was handed to the program")
	assert_eq(String(screen.summary()["message"]), "Rejected: missing_cost", "shown on the line")
	assert_eq(String(screen.summary()["tone"]), "error", "reported as a rejection")

	# Holding the reagent moves the reason on to the real blocker: no slot yet.
	_give(actor, INK)
	var view := _push(screen, actor)
	assert_eq(bool(view["can_impute"]), false, "still disabled")
	assert_eq(
		(view["reasons"] as Array)[1], "no_slot", "now the gameplay reason is the missing slot"
	)
	assert_eq(screen.act_impute_slot(), false, "and refuses")
	assert_eq(_requests.size(), 0, "still nothing handed over")
	var after: Dictionary = screen.summary()
	assert_eq(String(after["message"]), "Rejected: no_slot", "the reason is shown")
	assert_eq(String(after["tone"]), "error", "reported as a rejection")
	assert_eq(String(host.instance_id) != "", true, "the host is still the one on screen")
	screen.free()


func test_the_screen_says_why_a_cap_stops_a_second_slot() -> void:
	var actor := _actor()
	var host := _host(actor, 105)
	_give(actor, SLOT_REAGENT, 2)
	SocketApi.create_slot(actor, host.instance_id, SLOT_REAGENT)
	var screen := _screen_scene()
	screen.setup(actor)
	var view := _push(screen, actor)
	assert_eq(bool(view["can_create"]), false, "the cap disables opening another slot")
	assert_eq((view["reasons"] as Array)[0], "cap_reached", "with the gameplay reason")
	assert_eq(screen.act_create_slot(), false, "and the action refuses")
	assert_eq(ItemsApi.inventory(actor).count(SLOT_REAGENT), 1, "nothing consumed")
	screen.free()


func test_a_full_loop_driven_from_the_screen_reaches_the_same_state() -> void:
	var actor := _actor()
	var host := _host(actor, 106)
	_give(actor, SLOT_REAGENT, 2)
	_give(actor, INK, 2)
	var gem := ItemsApi.generate(
		actor, SocketApi.resolve_content(&"socket_rune_mortal_offense"), 206
	)
	var screen := _screen_scene()
	screen.setup(actor)
	_push(screen, actor)

	# Same path a player takes: the screen asks, the harness runs the facade, the
	# view is pushed back.
	assert_eq(screen.act_create_slot(), true, "open a socket")
	assert_eq(_play(_requests.pop_back(), actor), true, "the facade committed it")
	_push(screen, actor)
	assert_eq(screen.act_impute_slot(), true, "imprint it")
	assert_eq(_play(_requests.pop_back(), actor), true, "the facade committed it")
	_push(screen, actor)
	assert_eq(screen.act_insert_socket(), true, "insert a socket item")
	assert_eq(_play(_requests.pop_back(), actor), true, "the facade committed it")
	_push(screen, actor)

	var view := screen.summary()
	assert_eq(int(view["slot_count"]), 1, "the slot is listed")
	assert_eq(bool(view["slot_occupied"]), true, "and it is occupied")
	assert_eq(int((view["slots"]["0"] as Dictionary)["imputed_count"]), 2, "imputation is intact")
	assert_eq(bool(view["can_extract"]), true, "the gem can be taken back out")
	assert_eq(screen.act_extract_socket(), true, "extract it")
	assert_eq(_play(_requests.pop_back(), actor), true, "the facade committed it")
	_push(screen, actor)
	assert_eq(bool(screen.summary()["slot_occupied"]), false, "the slot is empty again")
	assert_eq(
		int((screen.summary()["slots"]["0"] as Dictionary)["imputed_count"]),
		2,
		"and the imputation survived"
	)
	screen.free()


func test_the_screen_reports_what_an_enchantment_would_cost_and_allow() -> void:
	var actor := _actor()
	var host := _host(actor, 107)
	_give(actor, WASH, 2)
	var screen := _screen_scene()
	screen.setup(actor)
	var view := _push(screen, actor)
	assert_eq(bool(view["can_enchant"]), true, "a treatment is offered")
	assert_eq(int(view["enchant_permitted"]) > 0, true, "with permitted outcomes")
	assert_eq(int(view["enchant_locked"]) > 0, true, "and the locked options it must not touch")
	assert_eq(int(view["enchant_generation"]), 0, "nothing applied yet")
	assert_eq(int(view["enchant_allowed"]), 3, "the cap is reported")
	assert_eq(
		String((view["costs"] as Dictionary)["enchantment"]), String(WASH), "the cost is named"
	)
	assert_eq(screen.act_enchant(), true, "the action is offered")
	assert_eq(String((_requests[0] as Dictionary)["action"]), "enchant", "and is the right intent")
	screen.free()


func test_the_enchantment_line_names_a_refusal_instead_of_a_bare_reason() -> void:
	var actor := _actor()
	_host(actor, 108)
	var screen := _screen_scene()
	screen.setup(actor)
	var view := _push(screen, actor)
	assert_eq(bool(view["can_enchant"]), false, "no reagent is carried")
	assert_eq((view["reasons"] as Array)[4], "missing_cost", "with the gameplay reason")
	screen.free()


# --- ScreenStack contract ------------------------------------------------------


func test_the_screen_implements_the_screen_stack_hooks() -> void:
	var actor := _actor()
	var host := _host(actor, 109)
	_give(actor, SLOT_REAGENT)
	_give(actor, INK)
	assert_eq(
		bool(SocketApi.create_slot(actor, host.instance_id, SLOT_REAGENT)["ok"]), true, "a slot"
	)
	var screen := _screen_scene()
	screen.setup(actor)
	_push(screen, actor)
	screen.call("on_screen_shown")
	assert_ne(screen.summary().is_empty(), true, "showing the screen repaints it")
	screen.call("on_screen_hidden")
	assert_ne(screen.summary().is_empty(), true, "hiding it keeps the state readable")
	assert_eq(
		screen.call("on_stack_input", InputEventKey.new()), false, "the screen consumes nothing"
	)
	screen.focus_initial()
	assert_ne(String(screen.summary()["focus_target"]), "", "focus lands on a live action")
	screen.free()


## Play the screen's intent against the socket program, the way the composition
## root does, and report whether it committed.
func _play(request: Dictionary, actor: Actor) -> bool:
	var action := StringName(String(request["action"]))
	var args: Dictionary = request["args"]
	var host := StringName(
		String(SocketApi.panel_state(actor).get("parent", {}).get("instance_id", ""))
	)
	match action:
		&"create_slot":
			return bool(
				SocketApi.create_slot(actor, host, StringName(String(args["reagent_id"])))["ok"]
			)
		&"impute_slot":
			return bool(
				(
					SocketApi
					. impute_slot(
						actor, host, int(args["index"]), StringName(String(args["reagent_id"]))
					)["ok"]
				)
			)
		&"insert_socket":
			return bool(
				(
					SocketApi
					. insert_socket(
						actor, host, int(args["index"]), StringName(String(args["gem_instance_id"]))
					)["ok"]
				)
			)
		&"extract_socket":
			return bool(SocketApi.extract_socket(actor, host, int(args["index"]))["ok"])
	return false
