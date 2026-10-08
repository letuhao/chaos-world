class_name DialogueApi
extends RefCounted

## Public facade for the `dialogue` module (ADR 0862). Other modules may reference ONLY
## this file (`api.gd`); `ui/` reaches it too, so a panel renders a conversation
## without naming a `DialogueDef`.
##
## ## What a conversation is
##
## An authored graph keyed by the NPC it belongs to: a `DialogueDef` holds nodes, a node
## holds ordered `lines`, a `speaker`, and the choices the player may answer. A choice
## carries an optional [DialogueCondition] (a closed verb set over the actor's typed
## variable store) and an optional effect. `DialogueRunner` is the state machine;
## everything here is a thin verb over it that ANNOUNCES on `DialogueEvents` (ADR 0269).
##
## ## The state is the actor's, and it round-trips through the save
##
## Where a conversation is, and every variable it has written, live in
## `actor.module_data["dialogue_state"]` (ADR 0027), so `Actor.to_dict` carries them with
## no bespoke save path. There is no module-level state and no clock: a conversation
## advances only when a caller pulls it (ADR 0085, DEF-0111).
##
## ## Gating is DATA (ADR 0065/0066)
##
## A condition is a `.tres` naming a closed verb and a variable key, never GDScript. A
## locked choice is PUBLISHED with its refusal, not dropped, so "she will not tell you
## yet" and "she never offers it" are not the same silence.
##
## ## Ten verbs, and the budget is real
##
## Screens and other modules reach this facade, and it stays small on purpose: a
## conversation render, a choice, and the two reads a screen needs are one call each.

## The `actor.module_data` key the row persists under (ADR 0027).
const MODULE_KEY := DialogueState.MODULE_KEY


## Attach the module to `actor`: normalize any row a prior `Actor.from_dict` carried and
## drop a conversation the current catalog no longer defines. Idempotent, and safe before
## anything has ever been said — the normal starting state.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	actor.set_module_data(MODULE_KEY, _known_row(actor))


## Open `npc_id`'s conversation at its entry node. Refuses, by name, `unknown_dialog`
## (the npc has none, or the def is unplayable) and `unknown_node` (its entry names a
## node it does not author).
static func start(actor: Actor, npc_id: StringName) -> Dictionary:
	var out := DialogueRunner.start(actor, npc_id)
	if bool(out["ok"]):
		DialogueEvents.shared().dialogue_started.emit(
			_actor_id(actor),
			String(npc_id),
			String(out.get("dialog_id", "")),
			String(out.get("node_id", ""))
		)
	else:
		DialogueEvents.shared().dialogue_refused.emit(_actor_id(actor), String(out["reason"]), "")
	return out


## The current node as primitives, or a `not_talking` refusal. The one read a screen
## makes to render a conversation.
static func current(actor: Actor) -> Dictionary:
	return DialogueRunner.current(actor)


## Take `choice_id` on the current node: apply its effect, then move. A LOCKED choice is
## refused by its condition's own name and writes nothing. Fires `dialogue_choice_taken`
## when the row moves, or `dialogue_ended` when a choice ends the conversation.
static func choose(actor: Actor, choice_id: StringName) -> Dictionary:
	var out := DialogueRunner.choose(actor, choice_id)
	if not bool(out["ok"]):
		DialogueEvents.shared().dialogue_refused.emit(
			_actor_id(actor), String(out["reason"]), String(choice_id)
		)
		return out
	var node := String(out.get("node_id", ""))
	if bool(out.get("ended", false)):
		DialogueEvents.shared().dialogue_ended.emit(
			_actor_id(actor), String(out.get("dialog_id", ""))
		)
	else:
		DialogueEvents.shared().dialogue_choice_taken.emit(
			_actor_id(actor), String(choice_id), node
		)
	return out


## Close the open conversation, keeping the variable store. Idempotent.
static func stop(actor: Actor) -> Dictionary:
	var out := DialogueRunner.stop(actor)
	if bool(out["ok"]) and String(out.get("closed", "")) != "":
		DialogueEvents.shared().dialogue_ended.emit(_actor_id(actor), String(out["closed"]))
	return out


## The whole state as primitives for a screen that wants one read: whether a conversation
## is open, what node, and the variable store.
static func summary(actor: Actor) -> Dictionary:
	return DialogueRunner.summary(actor)


## The actor's variable store, live. Read a value with `has`/`get_value`; write it back
## through [method write_variable] so the row is persisted rather than a detached copy
## mutated in place.
static func variables(actor: Actor) -> DialogueVariables:
	return DialogueRunner.variables(actor)


## Write one variable into the actor's store and persist it. The verb a command in a
## scripted beat, or a quest effect, uses to set conversational state.
static func write_variable(actor: Actor, key: StringName, value: Variant) -> Dictionary:
	return DialogueRunner.write_variable(actor, key, value)


## Every authored conversation as primitives, keyed by dialog id: the ids plus the node
## and npc each belongs to. A direct view of content for a tool or a codex.
static func catalog() -> Dictionary:
	var out: Dictionary = {}
	for dialog_id in DialogueCatalog.instance().dialog_ids():
		var def := DialogueCatalog.instance().definition(dialog_id)
		if def != null:
			out[String(dialog_id)] = def.to_dict()
	return out


## The signal bus, so a consumer subscribes without this module reaching into it. The bus
## ANNOUNCES; nothing on it is a request (ADR 0093).
static func events() -> DialogueEvents:
	return DialogueEvents.shared()


# --- internals ---------------------------------------------------------------


static func _actor_id(actor: Actor) -> String:
	return "" if actor == null else String(actor.id)


static func _known_row(actor: Actor) -> Dictionary:
	var known: Dictionary = {}
	for dialog_id in DialogueCatalog.instance().dialog_ids():
		known[String(dialog_id)] = true
	return DialogueState.normalize(actor.get_module_data(MODULE_KEY), known)
