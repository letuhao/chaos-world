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
## The one effect channel a reforge may replace: an instance's OWN realized
## affix. Everything else an item carries — item-authored fixed options, a set
## threshold, a unique's locked signature — belongs to another subsystem and is
## authored content, so it is never a reforge target.
const ROLL_CHANNEL := &"rolled"


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


## How many reforges one instance may ever receive: one per affix it carries
## beyond the first.
##
## The first affix is the item's character and is never replaced, so a common
## item — the one rarity that cannot carry a socket either — is not investable
## at all. That is a deliberate answer rather than an oversight: the forge
## invests in the pieces it can already build on, and refusing the rest is what
## keeps "reforge" from being a universal upgrade button.
static func reforge_cap(rarity: StringName) -> int:
	return maxi(0, ItemRarity.affix_count(ItemRarity.sanitize(rarity)) - 1)


## Units of reagent the `attempts`-th reforge of one instance costs: 1, 2, 3, …
##
## Escalating, and that is the whole answer to "a re-roll lottery". The first
## attempt is cheap enough to try on a lucky drop; the next two are not, so the
## bill for chasing one better affix is a decision rather than a habit.
static func reforge_cost_units(attempts: int) -> int:
	return 1 + maxi(0, attempts)


## Whether a gem may sit in a slot of `kind`. An `any` slot or an `any` gem
## matches everything; anything else has to agree.
static func accepts_kind(def: ItemDef, kind: StringName) -> bool:
	var own := kind_of(def)
	return own == KIND_ANY or kind == &"" or kind == KIND_ANY or own == kind


## Whether `option_id` is one this instance's owner may replace: its OWN rolled
## affix, unlocked. Anything an item reaches through another channel — a
## definition's fixed option, a set threshold, a unique's locked signature — is
## authored by someone else and is refused.
static func is_reforgable(instance: ItemInstance, option_id: StringName) -> bool:
	if instance == null or option_id == &"":
		return false
	var carried := false
	for effect in effects_of(instance):
		if StringName(effect.get("option_id", &"")) != option_id:
			continue
		carried = true
		if StringName(effect.get("channel", &"")) != ROLL_CHANNEL:
			return false
		if bool(effect.get("locked", false)):
			return false
	return carried


## Every affix on `instance` a reforge may NOT replace, as ids. A screen reads
## this to mark an option unselectable rather than letting a press be refused.
static func locked_reforge_ids(instance: ItemInstance) -> Array[StringName]:
	var out: Array[StringName] = []
	if instance == null:
		return out
	for effect in effects_of(instance):
		var option_id := StringName(effect.get("option_id", &""))
		if option_id == &"" or out.has(option_id):
			continue
		if not is_reforgable(instance, option_id):
			out.append(option_id)
	return out


## The index in `instance.rolled` of `option_id`, or -1. A reforge replaces one
## realized entry in place, so this is what makes "this one affix, keep the
## rest" a single-array edit rather than a rebuild of the item.
static func rolled_index(instance: ItemInstance, option_id: StringName) -> int:
	if instance == null or option_id == &"":
		return -1
	for index in instance.rolled.size():
		if StringName(instance.rolled[index].get("option_id", &"")) == option_id:
			return index
	return -1


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
