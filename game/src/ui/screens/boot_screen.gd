class_name BootScreen
extends UiScreen

## The main menu: Continue when a save exists, New Game always.
##
## ## Why a screen and not a branch in the root
##
## Boot used to be a decision the composition root made silently: a restored
## body went to the workbench, a fresh boot went to arrival, and a player who
## wanted the other door had no door. A menu is that door. It is a screen
## rather than a second root because the root already owns the stack, the bar
## and the actor — a second scene would be a second program that agrees with
## the first about all three.
##
## ## Where each answer comes from
##
## `ui/` may not name the `save` module (ADR 0128), so whether a save exists
## arrives as an injected Callable, exactly as ADR 0143 prescribes — the same
## seam `SoulHearthScreen.bind_soul` takes its save read through. The two
## movements also arrive as Callables the root owns: continuing is the home
## route, a new game is the arrival route, and a screen that named either
## would be navigating behind the root's back.
##
## ## Unwired, every control refuses by name
##
## A menu whose seam was never filled must not offer a journey it cannot
## start: Continue is hidden without the save seam, New Game without the
## movement seam, and both verbs answer a named refusal instead of calling
## into a void Callable.
##
## Contract: `summary()` is the testable surface, primitives only, and `{}`

const NO_SAVE_SEAM := "no_save_seam"
const NO_CONTINUE_SEAM := "no_continue_seam"
const NO_NEW_GAME_SEAM := "no_new_game_seam"

var _status: Label = null
var _continue_button: Button = null
var _new_game_button: Button = null
## Whether a readable save exists, as the root answers it. Never a module this
## screen may name, so this is the only shape the question can arrive in.
var _has_save: Callable = Callable()
## The two movements, owned by the root: home for Continue, arrival for New Game.
var _on_continue: Callable = Callable()
var _on_new_game: Callable = Callable()
var _last_continue: bool = false
var _last_new_game: Dictionary = {}


## Inject the menu's three seams. `has_save` is called as `has_save() -> bool`;
## the movements are called as `continue() -> bool` and `new_game() ->
## Dictionary`, each answering its own verdict verbatim.
func bind_menu(has_save: Callable, on_continue: Callable, on_new_game: Callable) -> void:
	_has_save = has_save
	_on_continue = on_continue
	_on_new_game = on_new_game
	_bind_nodes()
	refresh()


## Whether the save half is wired at all. Separate from the movements because
## the three seams are filled by one arm and a partial bind is a real state.
func can_read_save() -> bool:
	return _has_save.is_valid()


## Whether Continue is offered right now: the seam is filled, a save exists,
## and this screen is bound to a body to continue WITH.
func can_continue() -> bool:
	if _actor == null or not _has_save.is_valid():
		return false
	return bool(_has_save.call())


## Whether New Game is offered right now: the movement seam is filled and a
## body is bound to leave from.
func can_new_game() -> bool:
	return _actor != null and _on_new_game.is_valid()


## Continue the saved journey: return to the home route. A headless probe
## drives this rather than pressing the button, so the two stay one verb.
func act_continue() -> bool:
	_bind_nodes()
	if not can_continue():
		set_message(NO_SAVE_SEAM if not _has_save.is_valid() else NO_CONTINUE_SEAM, TONE_ERROR)
		refresh()
		return false
	_last_continue = bool(_on_continue.call())
	if not _last_continue:
		set_message(NO_CONTINUE_SEAM, TONE_ERROR)
	else:
		set_message("", TONE_OK)
	refresh()
	return _last_continue


## Begin anew: open the arrival route and hand the verdict back verbatim, so
## what the player sees afterwards is the creation screen and not this
## screen's memory of having asked for it.
func act_new_game() -> Dictionary:
	_bind_nodes()
	if _actor == null or not _on_new_game.is_valid():
		set_message(NO_NEW_GAME_SEAM, TONE_ERROR)
		refresh()
		return {"ok": false, "reason": NO_NEW_GAME_SEAM}
	_last_new_game = (_on_new_game.call() as Dictionary).duplicate(true)
	if not bool(_last_new_game.get("ok", true)):
		set_message(String(_last_new_game.get("reason", NO_NEW_GAME_SEAM)), TONE_ERROR)
	else:
		set_message("", TONE_OK)
	refresh()
	return _last_new_game.duplicate(true)


func focus_initial() -> void:
	_bind_nodes()
	var target: Control = null
	if can_continue() and _continue_button != null:
		target = _continue_button
	elif _new_game_button != null:
		target = _new_game_button
	if target == null:
		return
	_focus_target = String(target.name)
	if target.is_inside_tree():
		target.grab_focus()


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	return {
		"has_save": can_read_save() and bool(_has_save.call()),
		"can_continue": can_continue(),
		"can_new_game": can_new_game(),
	}


func _refresh_view() -> void:
	pass


func _render() -> void:
	if _status != null:
		if _actor == null:
			_status.text = "No hero bound."
		elif can_continue():
			_status.text = "A saved journey exists. Continue it, or begin anew."
		else:
			_status.text = "No saved journey. Begin anew."
	if _continue_button != null:
		_continue_button.disabled = not can_continue()
	if _new_game_button != null:
		_new_game_button.disabled = not can_new_game()


func _bind_nodes() -> void:
	super()
	_status = get_node_or_null("%StatusLabel") as Label
	_continue_button = get_node_or_null("%ContinueButton") as Button
	_new_game_button = get_node_or_null("%NewGameButton") as Button
	if _continue_button != null and not _continue_button.pressed.is_connected(_on_continue_pressed):
		_continue_button.pressed.connect(_on_continue_pressed)
	if _new_game_button != null and not _new_game_button.pressed.is_connected(_on_new_game_pressed):
		_new_game_button.pressed.connect(_on_new_game_pressed)


func _on_continue_pressed() -> void:
	act_continue()


func _on_new_game_pressed() -> void:
	act_new_game()
