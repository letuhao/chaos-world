class_name SocketForgeProgram
extends RefCounted

## The gameplay half of the socket forge, owned by the composition root.
##
## `SocketForgeScreen` is a pure view: it names no socket type, renders a read model
## pushed in with `bind_view()`, and answers an action by emitting
## `socket_action_requested`. This object is the other half — it holds the read
## model, runs each intent against the socket facade, and pushes the next view back.
## Split out of the composition root so the root wires and this owns the one forge's
## round trip; the two halves still meet at exactly one place, and neither reaches
## into the other's types.

var _actor: Actor = null
var _screen: Control = null
var _requests: int = 0


func _init(actor: Actor) -> void:
	_actor = actor


## Adopt `screen` as the forge this program drives, connect its intent signal and
## paint the first view. Safe to call again: the previous screen is simply forgotten.
func bind(screen: Control) -> void:
	if screen == null:
		return
	_screen = screen
	if not screen.is_connected(&"socket_action_requested", Callable(self, "handle")):
		screen.connect(&"socket_action_requested", Callable(self, "handle"))
	refresh()


## The forge still mounted, or null once the stack has popped and freed it. Every
## entry point checks this, because the stack frees a screen the moment a route
## closes and a stale reference is a crash waiting for the next navigation.
func is_live() -> bool:
	return is_instance_valid(_screen)


## Re-read the socket program's read model for the host the screen is looking at,
## and hand it in. The host id rides the view, so one read serves every widget.
func refresh() -> void:
	if not is_live() or _actor == null:
		return
	_screen.call(&"bind_view", SocketApi.panel_state(_actor, host_id()))


## Run one screen intent against the socket program, then repaint from the result.
## A refusal is reported through the message line, never swallowed.
func handle(action: StringName, args: Dictionary) -> void:
	var result := _run(action, args)
	if not is_live():
		return
	_screen.call(&"set_message", _outcome(action, result), _tone(result))
	refresh()


## The host the screen is looking at, or the facade's own default host when nothing is
## mounted to ask.
func host_id() -> String:
	if is_live():
		return String(_screen.call(&"selected_host"))
	var parent: Dictionary = SocketApi.panel_state(_actor).get("parent", {})
	return String(parent.get("instance_id", ""))


func _run(action: StringName, args: Dictionary) -> Dictionary:
	var host := StringName(String(args.get("host_id", host_id())))
	var reagent := StringName(String(args.get("reagent_id", "")))
	var index := int(args.get("index", 0))
	match action:
		&"create_slot":
			return SocketApi.create_slot(_actor, host, reagent)
		&"impute_slot":
			return SocketApi.impute_slot(_actor, host, index, reagent)
		&"insert_socket":
			return SocketApi.insert_socket(
				_actor, host, index, StringName(String(args.get("gem_instance_id", "")))
			)
		&"extract_socket":
			return SocketApi.extract_socket(_actor, host, index)
		_:
			return SocketApi.commit_enchantment(
				_actor, host, reagent, _next_request_id(), Time.get_ticks_usec()
			)


## Each enchantment carries a request id so two of them in the same tick are two
## requests rather than one; the forge's own replay protection reads it.
func _next_request_id() -> StringName:
	_requests += 1
	return StringName("socket_request_%d" % _requests)


func _outcome(action: StringName, result: Dictionary) -> String:
	if bool(result.get("ok", false)):
		return "%s committed" % action
	return "Rejected: %s" % result.get("reason", "")


func _tone(result: Dictionary) -> StringName:
	return &"ok" if bool(result.get("ok", false)) else &"error"
