class_name SocketApi
extends RefCounted

## Public facade for the `socket` module (ADR 0025/0026/0027).
## Other modules may reference ONLY this file (`api.gd`).
##
## Three transactions live here: opening a socket slot on an item, imputing an
## empty slot's own effects, and moving a socket item into or out of a slot. The
## fourth is the enchantment channel — one replaceable channel per target.
##
## Every transaction validates completely before it mutates anything, spends its
## cost through the items module's own crafting path, and returns a result
## dictionary whose `reason` is the gameplay cause of a refusal. State lives in
## `actor.module_data["socket_state"]`, so `Actor` never learns a socket type.

const LEDGER_COMPONENT := &"socket_ledger"
const TAGS_SLOT_REAGENT := &"socket_reagent"
const TAGS_IMPUTATION := &"imputation_reagent"
const TAGS_ENCHANTMENT := &"enchantment_reagent"
const TAGS_SLOT_CREATION := &"slot_creation"
## A reforge spends the same reagent the enchantment channel does. That is a
## deliberate overlap and not a missing content tag: one pool of material means
## improving a worn affix competes for the same units as enchanting a new one,
## which is what makes the choice between them a decision.
const REFORGE_REAGENT_TAG := TAGS_ENCHANTMENT


## Give `actor` a socket ledger and start tracking its equipment, so a worn item
## keeps contributing its sockets. Idempotent, and safe after a load: state
## restored by `Actor.from_dict` is adopted rather than replaced.
static func attach(actor: Actor) -> SocketLedger:
	if actor == null:
		return SocketLedger.new()
	var existing := actor.component(LEDGER_COMPONENT) as SocketLedger
	if existing != null:
		return existing
	var ledger := SocketLedger.new(actor.get_module_data(SocketLedger.STATE_KEY))
	actor.set_component(LEDGER_COMPONENT, ledger)
	SocketOwnership.rehydrate(actor)
	var equipment := ItemsApi.equipment(actor)
	if equipment != null and not equipment.changed.is_connected(_on_equipment_changed):
		equipment.changed.connect(_on_equipment_changed.bind(actor))
	ledger.commit(actor)
	SocketEffects.sync(actor, ledger)
	return ledger


## The definition for `item_id`: the items module's resolver first, then this
## module's own content namespace.
static func resolve_content(item_id: StringName) -> ItemDef:
	return SocketContent.resolve(item_id)


## Everything a screen needs to render the socket program for `actor`:
## primitives only, so it can be a `summary()` payload unchanged. The parent is
## the requested instance, or the first item the actor owns that can carry a
## socket.
static func panel_state(actor: Actor, parent_instance_id: StringName = &"") -> Dictionary:
	var ledger := _ledger(actor)
	if ledger == null:
		return {}
	return SocketReadModel.project(actor, ledger, parent_instance_id)


## Open a socket slot on `parent_instance_id`, spending one `reagent_def_id`.
static func create_slot(
	actor: Actor, parent_instance_id: StringName, reagent_def_id: StringName
) -> Dictionary:
	return _run(
		actor,
		SlotService.ACTION_CREATE,
		func(ledger: SocketLedger) -> Dictionary:
			return SlotService.create_slot(actor, ledger, parent_instance_id, reagent_def_id)
	)


## Impute the slot at `index` on `parent_instance_id`, spending one reagent.
static func impute_slot(
	actor: Actor, parent_instance_id: StringName, index: int, reagent_def_id: StringName
) -> Dictionary:
	return _run(
		actor,
		SlotService.ACTION_IMPUTE,
		func(ledger: SocketLedger) -> Dictionary:
			return SlotService.impute_slot(actor, ledger, parent_instance_id, index, reagent_def_id)
	)


## Move the owned socket item `gem_instance_id` into slot `index`.
static func insert_socket(
	actor: Actor, parent_instance_id: StringName, index: int, gem_instance_id: StringName
) -> Dictionary:
	return _run(
		actor,
		SlotService.ACTION_INSERT,
		func(ledger: SocketLedger) -> Dictionary:
			return SlotService.insert_socket(
				actor, ledger, parent_instance_id, index, gem_instance_id
			)
	)


## Move slot `index`'s socket item back into the inventory. Non-destructive: the
## same instance returns, unrerolled, with the slot's imputation intact.
static func extract_socket(actor: Actor, parent_instance_id: StringName, index: int) -> Dictionary:
	return _run(
		actor,
		SlotService.ACTION_EXTRACT,
		func(ledger: SocketLedger) -> Dictionary:
			return SlotService.extract_socket(actor, ledger, parent_instance_id, index)
	)


## What an enchantment of `target_instance_id` could produce, and what would stop
## it. Changes nothing: no unit consumed, no state written, no roll advanced.
static func preview_enchantment(
	actor: Actor,
	target_instance_id: StringName,
	reagent_def_id: StringName,
	rng: RandomNumberGenerator = null
) -> Dictionary:
	var ledger := _ledger(actor)
	if ledger == null:
		return SocketResult.refused(
			EnchantmentService.ACTION_PREVIEW, target_instance_id, "no_actor"
		)
	# A preview is not a change, so it is not published: the change notification
	# stays exactly one event per committed or refused transaction.
	return EnchantmentService.preview(
		actor, ledger, target_instance_id, resolve_content(reagent_def_id), rng
	)


## What replacing `option_id` on `target_instance_id` could produce, and what
## would stop it. Changes nothing: no unit consumed, no state written, no roll
## advanced. `option_id` is one of the target's OWN rolled affixes; an authored
## fixed option, a set threshold and a unique's locked signature are refused.
static func preview_reforge(
	actor: Actor,
	target_instance_id: StringName,
	option_id: StringName,
	reagent_def_id: StringName,
	rng: RandomNumberGenerator = null
) -> Dictionary:
	var ledger := _ledger(actor)
	if ledger == null:
		return SocketResult.refused(ReforgeService.ACTION_PREVIEW, target_instance_id, "no_actor")
	# A preview is not a change, so it is not published: the change notification
	# stays exactly one event per committed or refused transaction.
	return ReforgeService.preview(
		actor, ledger, target_instance_id, option_id, resolve_content(reagent_def_id), rng
	)


## Replace `option_id` on `target_instance_id` with a newly realized affix,
## spending an escalating number of `reagent_def_id`. The cost grows with every
## reforge the same instance has received and the count is finite
## (`SocketPolicy.reforge_cap`), so this is an investment rather than a lottery.
## The replacement is recorded, never re-derived: a save/load round trip restores
## the instance carrying it, and it is not rerolled from its seed. Replaying the
## same `request_id` returns the recorded result without charging twice.
static func commit_reforge(
	actor: Actor,
	target_instance_id: StringName,
	option_id: StringName,
	reagent_def_id: StringName,
	request_id: StringName,
	seed: int
) -> Dictionary:
	return _run(
		actor,
		ReforgeService.ACTION_COMMIT,
		func(ledger: SocketLedger) -> Dictionary:
			return ReforgeService.commit(
				actor,
				ledger,
				target_instance_id,
				option_id,
				resolve_content(reagent_def_id),
				request_id,
				seed
			)
	)


## Apply or replace `target_instance_id`'s enchantment, spending one reagent.
## Replaying the same `request_id` returns the recorded result without charging
## or applying a second time.
static func commit_enchantment(
	actor: Actor,
	target_instance_id: StringName,
	reagent_def_id: StringName,
	request_id: StringName,
	seed: int
) -> Dictionary:
	return _run(
		actor,
		EnchantmentService.ACTION_COMMIT,
		func(ledger: SocketLedger) -> Dictionary:
			return EnchantmentService.commit(
				actor, ledger, target_instance_id, resolve_content(reagent_def_id), request_id, seed
			)
	)


## Whether `option_id` is locked on `instance`: reached through a channel this
## module does not author, or explicitly flagged by its owner. An enchantment
## refuses every locked option, so set and unique effects survive any treatment.
static func is_locked_option(instance: ItemInstance, option_id: StringName) -> bool:
	return SocketPolicy.is_locked_option(instance, option_id)


## The actor's versioned socket payload, exactly as it is persisted.
static func socket_state(actor: Actor) -> Dictionary:
	var ledger := _ledger(actor)
	return {} if ledger == null else ledger.to_dict()


static func _run(actor: Actor, action: StringName, body: Callable) -> Dictionary:
	var ledger := _ledger(actor)
	if ledger == null:
		return _published(SocketResult.refused(action, &"", "no_actor"))
	return _published(body.call(ledger))


static func _published(result: Dictionary) -> Dictionary:
	SocketBus.publish(result)
	return result


static func _ledger(actor: Actor) -> SocketLedger:
	if actor == null:
		return null
	var existing := actor.component(LEDGER_COMPONENT) as SocketLedger
	return existing if existing != null else attach(actor)


static func _on_equipment_changed(actor: Actor) -> void:
	var ledger := _ledger(actor)
	if ledger != null:
		SocketEffects.sync(actor, ledger)
