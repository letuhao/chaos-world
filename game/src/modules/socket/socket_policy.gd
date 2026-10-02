class_name SocketPolicy
extends RefCounted

## Socket rules both gameplay and the UI ask: what may carry a socket, how many
## sockets an item may carry, which slot kind a gem fits, and which options a
## socket treatment is forbidden to touch.
##
## Every answer here is derived from an owned policy — `ItemRarity`'s socket cap,
## `ItemGrade`'s tier table, the realm ladder and the definition's own tags — so
## no module restates a cap and a content change moves all of them at once.

## Tag every socket item (gem/rune) carries. Its presence is what makes an
## item a socket payload rather than a socket host.
const SOCKET_ITEM_TAG := &"socket_item"
## Slot kinds. A slot takes its kind from the reagent that created it; a gem
## declares which kinds it accepts through `socket_kind:<kind>` tags.
const KIND_ANY := &"any"
const KIND_OFFENSE := &"offense"
const KIND_DEFENSE := &"defense"
const KIND_UTILITY := &"utility"
const KIND_TAG_PREFIX := "socket_kind:"
const KINDS: Array[StringName] = [KIND_OFFENSE, KIND_DEFENSE, KIND_UTILITY]
## Effect channels this module authors. An option reached through any other
## channel belongs to another feature (item-authored fixed, rolled, and later
## set/unique) and is therefore locked against socket treatments.
const AUTHORED_CHANNELS: Array[String] = ["socket_slot", "socket_item", "enchantment"]
## Imputed effects a single slot may carry. A slot's own contribution is
## deliberately small: the gem is what scales. The cap is per slot, so an item
## with two sockets gets two independent slots instead of one budget split
## between them.
const IMPRINT_CAP := 2


## Socket slots an item of this rarity may carry: rare one, legendary two.
static func slot_cap(rarity: StringName) -> int:
	return ItemRarity.socket_cap(ItemRarity.sanitize(rarity))


## How many enchantments one target may ever receive, whatever replaces them.
## A common item is finished after one attempt; a legendary takes three.
static func enchant_cap(rarity: StringName) -> int:
	return clampi(ItemRarity.tier(ItemRarity.sanitize(rarity)) + 1, 1, 3)


## Whether this definition is a socket payload rather than a socket host. A
## socket item can never hold a socket, which is what makes a recursive socket
## structurally impossible rather than merely rejected.
static func is_socket_item(def: ItemDef) -> bool:
	return def != null and def.tags.has(SOCKET_ITEM_TAG)


## Whether this definition may host sockets at all.
static func carries_sockets(def: ItemDef) -> bool:
	return def != null and def.is_equipment() and not is_socket_item(def)


## The slot kind a definition declares, or `any` when it declares none.
static func kind_of(def: ItemDef) -> StringName:
	if def == null:
		return &""
	for tag in def.tags:
		if String(tag).begins_with(KIND_TAG_PREFIX):
			return StringName(String(tag).substr(KIND_TAG_PREFIX.length()))
	return KIND_ANY


## Whether a gem may sit in a slot of `kind`. An `any` slot or an `any` gem
## matches everything; anything else has to agree.
static func accepts_kind(def: ItemDef, kind: StringName) -> bool:
	var own := kind_of(def)
	return own == KIND_ANY or kind == &"" or kind == KIND_ANY or own == kind


## Realm tier a definition sits in. 0 means ungated content.
static func tier_of(realm_id: StringName) -> int:
	return RealmDefaults.ladder().tier_of(realm_id)


## Whether an actor at `actor_tier` may use content authored for `def_tier`.
static func meets_tier(actor_tier: int, def_tier: int) -> bool:
	return def_tier <= 0 or actor_tier <= 0 or actor_tier >= def_tier


## Whether `option_id` is locked on `instance`: reached through a channel this
## module does not author, or explicitly flagged `locked` by its owner. An
## enchantment refuses every locked option, so a set or unique survives any
## treatment this subsystem performs.
static func is_locked_option(instance: ItemInstance, option_id: StringName) -> bool:
	if instance == null or option_id == &"":
		return true
	for effect in effects_of(instance):
		if StringName(effect.get("option_id", &"")) != option_id:
			continue
		if bool(effect.get("locked", false)):
			return true
		if not AUTHORED_CHANNELS.has(String(effect.get("channel", ""))):
			return true
	return false


## Every effect an instance carries through a channel this module does not
## author. Used to keep an authored treatment from colliding with one.
static func foreign_option_ids(instance: ItemInstance) -> Array[StringName]:
	var out: Array[StringName] = []
	if instance == null:
		return out
	for effect in effects_of(instance):
		if AUTHORED_CHANNELS.has(String(effect.get("channel", ""))):
			continue
		var option_id := StringName(effect.get("option_id", &""))
		if option_id != &"" and not out.has(option_id):
			out.append(option_id)
	return out


## Every effect an instance resolves to: its definition's fixed channel plus
## its realized rolls, read through the items module's single aggregation path.
static func effects_of(instance: ItemInstance) -> Array[Dictionary]:
	if instance == null:
		return []
	if instance.def_ref == null:
		return instance.rolled.duplicate()
	return ItemEffects.resolve(instance.def_ref, instance)
