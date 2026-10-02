class_name Main
extends Control

## Composition root for the playable slice (ADR 0002, ADR 0028). The only place
## that knows concrete module types and the attach order. It builds one actor,
## hands it to the UI program, and pushes the screen declared in Main.tscn onto
## the stack, which owns focus and input.
##
## The slice is stocked for exactly one breakthrough: realm two needs sixteen
## channel elixirs (four channels x four state steps). Anything beyond that is
## blocked by DEF-0022, because every body consumable is crafted from a
## boss-only guardian core and no boss runtime exists.

const CULTIVATION_PANEL := "res://src/ui/screens/body_cultivation_panel.tscn"
const WORLD_MAP_SCREEN := "res://src/ui/screens/world_map_screen.tscn"
## Realm two needs four channels at four state steps each.
const CHANNEL_ELIXIRS := 16
const RECOVERY_ELIXIRS := 4

var _actor: Actor
var _panel: BodyCultivationPanel
var _stack: ScreenStack


func _ready() -> void:
	_stack = get_node_or_null("Layout/Column/ScreenStack") as ScreenStack
	if _stack == null:
		push_error("Main: Main.tscn must carry a ScreenStack under Layout/Column")
		return
	# The screen is pushed rather than authored into the stack, so the stack stays
	# the only thing that decides which screen is live, and `push()` routes focus
	# through the screen's `focus_initial()` hook.
	var screen := load(CULTIVATION_PANEL) as PackedScene
	if screen == null:
		push_error("Main: cannot load %s" % CULTIVATION_PANEL)
		return
	var instance := screen.instantiate()
	# Duck-typed, not cast: the scene root is a plain Control at this point and the
	# class is registered later than this script's own parse, so a hard cast can
	# yield nil for a perfectly valid scene.
	if not instance.has_method(&"setup"):
		push_error("Main: %s is not a cultivation screen" % CULTIVATION_PANEL)
		instance.free()
		return
	_actor = _build_actor()
	_initialize_world(_actor)
	instance.call("setup", _actor)
	_panel = instance as BodyCultivationPanel
	if _panel != null and _panel.has_signal(&"world_map_requested"):
		_panel.world_map_requested.connect(_on_world_map_requested)
	_stack.push(instance)


## A body cultivator at the first realm, stocked with what realm two asks for.
func _build_actor() -> Actor:
	var actor := ActorFactory.with_body_cultivation(
		Actor.new(&"player", {Stat.PHYSIQUE: 20.0, Stat.COMPREHENSION: 6.0})
	)
	ItemsApi.attach(actor)
	BodyTraining.synchronize(actor)
	var target := BodyRealmSeed.for_realm(&"foundation")
	var home := BodyRealmSeed.for_realm(&"qi_refining")
	if target == null or home == null:
		return actor
	_stock(actor, home.strengthening_item, CHANNEL_ELIXIRS)
	_stock(actor, home.recovery_item, RECOVERY_ELIXIRS)
	_stock(actor, target.breakthrough_item, 1)
	return actor


func _stock(actor: Actor, def_id: StringName, quantity: int) -> void:
	if def_id == &"" or quantity <= 0:
		return
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 99
	ItemsApi.inventory(actor).add(def, quantity)


## Initialize the world module with a mortal-tier world.
func _initialize_world(actor: Actor) -> void:
	if actor == null:
		return
	WorldApi.create_world(actor, &"micro", 10.0)


## Push the world map screen onto the stack.
func _on_world_map_requested() -> void:
	if _stack == null or _actor == null:
		return
	var screen := load(WORLD_MAP_SCREEN) as PackedScene
	if screen == null:
		push_error("Main: cannot load %s" % WORLD_MAP_SCREEN)
		return
	var instance := screen.instantiate()
	if not instance.has_method(&"setup"):
		push_error("Main: %s is not a world map screen" % WORLD_MAP_SCREEN)
		instance.free()
		return
	instance.call("setup", _actor)
	_stack.push(instance)
