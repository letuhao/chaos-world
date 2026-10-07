extends TestCase

## The qi path must be able to satisfy its own breakthrough gate (ADR 0043 gap
## audit). `QiTraining.train_channel` existed but was not on the facade, so no
## screen could reach it and the qi R2 gate was unsatisfiable in play: the gate
## demands channels reach `required_channel_state`, and `cultivate` never touches
## meridians.

const SCREEN := "res://src/ui/screens/qi_cultivation_screen.tscn"


func _screen() -> QiCultivationScreen:
	return (load(SCREEN) as PackedScene).instantiate() as QiCultivationScreen


func _actor() -> Actor:
	var actor := Actor.new(&"qi_gate", {Stat.PHYSIQUE: 20.0, Stat.COMPREHENSION: 10.0})
	ItemsApi.attach(actor, 512)
	actor.set_path(PathState.new(QiPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	QiCultivationApi.attach(actor)
	QiTraining.synchronize(actor)
	return actor


func _stock(actor: Actor, def_id: StringName) -> void:
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 9999
	ItemsApi.inventory(actor).add(def, 999)


func test_the_facade_exposes_channel_training() -> void:
	## Without this method the qi breakthrough gate cannot be met at all.
	var script: GDScript = load("res://src/modules/qi_cultivation/api.gd")
	var names: Array[String] = []
	for method in script.get_script_method_list():
		names.append(String(method.name))
	assert_eq(names.has("train_channel"), true, "train_channel is on the facade")


func test_channel_training_moves_a_channel_toward_the_gate() -> void:
	var actor := _actor()
	var seed := QiRealmSeed.for_realm(&"qi_refining")
	_stock(actor, seed.training_item)
	var channel := actor.meridians.get_meridian(&"lung")
	assert_eq(channel.state, &"closed", "starts closed")
	assert_eq(QiCultivationApi.train_channel(actor, &"lung"), true, "one step trains it")
	assert_ne(actor.meridians.get_meridian(&"lung").state, &"closed", "the channel advanced")


func test_channel_training_is_refused_without_the_elixir() -> void:
	var actor := _actor()
	assert_eq(QiCultivationApi.train_channel(actor, &"lung"), false, "no elixir, no training")
	assert_eq(actor.meridians.get_meridian(&"lung").state, &"closed", "unchanged")


func test_every_required_channel_can_be_reached() -> void:
	var actor := _actor()
	var seed := QiRealmSeed.for_realm(&"qi_refining")
	_stock(actor, seed.training_item)
	for meridian_id in seed.required_meridians:
		var guard := 0
		while (
			guard < 16
			and not actor.meridians.get_meridian(meridian_id).meets(seed.required_channel_state)
		):
			guard += 1
			if not QiCultivationApi.train_channel(actor, meridian_id):
				break
		var channel := actor.meridians.get_meridian(meridian_id)
		assert_eq(
			channel.meets(seed.required_channel_state),
			true,
			"%s reaches %s" % [meridian_id, seed.required_channel_state]
		)


func test_the_screen_can_drive_channel_training() -> void:
	## The whole point: a player, not a test, must be able to satisfy the gate.
	var screen := _screen()
	var actor := _actor()
	screen.setup(actor)
	var seed := QiRealmSeed.for_realm(&"qi_refining")
	_stock(actor, seed.training_item)
	var before := actor.meridians.get_meridian(&"lung").state
	assert_eq(screen.act_train_next_channel(), true, "the screen trained a channel")
	assert_ne(actor.meridians.get_meridian(&"lung").state, before, "state advanced")
	screen.free()


func test_the_screen_reports_channel_training_as_unavailable_without_the_elixir() -> void:
	var screen := _screen()
	var actor := _actor()
	screen.setup(actor)
	assert_eq(screen.act_train_next_channel(), false, "nothing to spend, nothing trained")
	screen.free()


func test_a_pressed_channel_row_is_the_one_the_screen_trains() -> void:
	## The player action that reaches `train_channel` (ADR 0188): pressing a row in the
	## channel list selects it, and the train action spends on the SELECTION rather than
	## on the first owed channel.
	var actor := _actor()
	var seed := QiRealmSeed.for_realm(&"qi_refining")
	_stock(actor, seed.training_item)
	var screen := _screen()
	screen.setup(actor)
	screen.refresh()
	var list := screen.get_node_or_null("%Channels") as ChannelList
	assert_ne(list, null, "the channel list is mounted")
	if list == null:
		screen.free()
		return
	var visible := list.visible_ids()
	assert_eq(visible.is_empty(), false, "the gate's channels are listed")
	var chosen := StringName(visible[visible.size() - 1])
	var row: StatRow = (list.get("_rows") as Dictionary).get(chosen)
	assert_ne(row, null, "the chosen channel has a row")
	if row == null:
		screen.free()
		return
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	list.call("_on_row_gui_input", press, row)
	assert_eq(
		StringName(screen.get("_selected_channel")), chosen, "the press selected the row's channel"
	)
	var before := actor.meridians.get_meridian(chosen).state
	assert_eq(screen.act_train_next_channel(), true, "the screen trained the selected channel")
	assert_ne(
		actor.meridians.get_meridian(chosen).state,
		before,
		"the SELECTED channel advanced, not the first owed one"
	)
	screen.free()
