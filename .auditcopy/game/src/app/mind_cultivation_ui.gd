class_name MindCultivationUi
extends Control

## Minimal cultivation UI for the mind_cultivation module (ADR 0013/0016).
## Displays active realm, sea state, channel states, and breakthrough conditions.

var _actor: Actor
var _realm_label: Label
var _sea_label: Label
var _channel_label: Label
var _condition_label: Label
var _cultivate_button: Button
var _meditate_button: Button
var _breakthrough_button: Button
var _sea_catalyst_button: Button
var _train_button: Button


func _ready() -> void:
	_build_ui()


func setup(actor: Actor) -> void:
	_actor = actor
	_refresh()


func _build_ui() -> void:
	# Idempotent. The headless harness drives `_ready()` by hand after
	# `add_child`, so a node with a live parent can get the engine's own `_ready()`
	# as well — and an unguarded build then parents a second VBox and duplicates
	# every handler, leaving the first one orphaned under nothing. The early return
	# is the same guard every screen in `src/ui/` uses.
	if _cultivate_button != null:
		return
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	_realm_label = Label.new()
	_realm_label.text = "Realm: "
	vbox.add_child(_realm_label)

	_sea_label = Label.new()
	_sea_label.text = "Sea: "
	vbox.add_child(_sea_label)

	_channel_label = Label.new()
	_channel_label.text = "Channels: "
	vbox.add_child(_channel_label)

	_condition_label = Label.new()
	_condition_label.text = "Conditions: "
	vbox.add_child(_condition_label)

	_cultivate_button = Button.new()
	_cultivate_button.text = "Cultivate"
	_cultivate_button.pressed.connect(_on_cultivate)
	vbox.add_child(_cultivate_button)

	_meditate_button = Button.new()
	_meditate_button.text = "Meditate"
	_meditate_button.pressed.connect(_on_meditate)
	vbox.add_child(_meditate_button)

	_sea_catalyst_button = Button.new()
	_sea_catalyst_button.text = "Use Sea Catalyst"
	_sea_catalyst_button.pressed.connect(_on_sea_catalyst)
	vbox.add_child(_sea_catalyst_button)

	_train_button = Button.new()
	_train_button.text = "Train Channel"
	_train_button.pressed.connect(_on_train)
	vbox.add_child(_train_button)

	_breakthrough_button = Button.new()
	_breakthrough_button.text = "Breakthrough"
	_breakthrough_button.pressed.connect(_on_breakthrough)
	vbox.add_child(_breakthrough_button)


func _refresh() -> void:
	if _actor == null:
		return
	var state := _actor.path(MindPath.PATH_ID)
	if state == null:
		_realm_label.text = "Realm: No mind path"
		return
	var realm := RealmDefaults.ladder().realm(state.rank_id)
	_realm_label.text = "Realm: %s (%s)" % [realm.display_name, realm.id]

	var sea := MindCultivationApi.sea(_actor)
	if sea != null:
		_sea_label.text = (
			"Sea: %s | Clarity: %.2f | Turbulence: %.2f | Purity: %.2f | Power: %d/%d"
			% [
				sea.tier,
				sea.clarity,
				sea.turbulence,
				sea.purity,
				int(sea.current(_actor)),
				int(sea.maximum(_actor)),
			]
		)

	var channels := []
	for def in MeridianDefaults.all():
		var channel := _actor.meridians.get_meridian(def.id)
		if channel != null:
			channels.append("%s:%s" % [def.id, channel.state])
	_channel_label.text = "Channels: %s" % ", ".join(channels)

	var preview := MindAdvancement.preview(_actor)
	if preview.get("ready", false):
		_condition_label.text = "Conditions: READY (chance: %.2f)" % preview.get("chance", 0.0)
	else:
		_condition_label.text = "Conditions: %s" % ", ".join(preview.get("conditions", []))


func _on_cultivate() -> void:
	if _actor == null:
		return
	MindTraining.cultivate(_actor, 10.0)
	_refresh()


func _on_meditate() -> void:
	if _actor == null:
		return
	MindTraining.meditate(_actor, 0.1)
	_refresh()


func _on_sea_catalyst() -> void:
	if _actor == null:
		return
	MindTraining.strengthen_sea(_actor)
	_refresh()


func _on_train() -> void:
	if _actor == null:
		return
	var state := _actor.path(MindPath.PATH_ID)
	if state == null:
		return
	var seed := MindRealmSeed.for_realm(state.rank_id)
	if seed == null:
		return
	for id in seed.required_meridians:
		if MindTraining.train_channel(_actor, id):
			break
	_refresh()


func _on_breakthrough() -> void:
	if _actor == null:
		return
	MindAdvancement.try_breakthrough(_actor)
	_refresh()
