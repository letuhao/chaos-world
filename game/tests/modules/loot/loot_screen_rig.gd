class_name LootScreenRig
extends RefCounted

## Shared rig for the loot screen suites: one hero, one bridge wired exactly as the
## composition root wires it, and helpers that drive the screen the way a player
## does — by emitting the real control signals rather than by calling the actions.
##
## Nothing here owns a rule. The bridge names [LootApi] so these suites can prove
## the pipeline a player walks; the screen itself never sees a module type.

const SCREEN_SCENE := "res://src/ui/screens/loot_encounter.tscn"
const EMBER_DOMAIN := &"loot_ember_vault_domain"
const STORM_DOMAIN := &"loot_storm_crypt_domain"
## The lowest authored band of each encounter's first tier entry.
const EMBER_TIER := 1
const STORM_TIER := 3
## How many bosses the ember run at the lowest band holds, and its first boss.
const EMBER_BOSS_COUNT := 3
const EMBER_FIRST_BOSS := "loot_ember_vault_warden"


## A delver with the core pools, an inventory of `capacity` slots and the loot
## lifecycle attached — the same attach order the composition root uses.
##
## Gear is applied as source-tagged FLAT modifiers on the ids the loot content itself
## grants. It is not decoration: a domain boss now answers every blow (ADR 0076), so a
## bare delver loses the ember run before its third boss and these suites could no longer
## walk a complete pipeline. Applied this way rather than through a bag so the fixture does
## not depend on how items are filled or rolled.
func hero(capacity: int = 24, fortune: float = 0.0, gear: float = 60.0) -> Actor:
	var actor := Actor.new(&"delver", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.stats.set_base(Stat.FORTUNE, fortune)
	actor.attach_core_resources()
	ItemsApi.attach(actor, capacity)
	LootApi.attach(actor)
	for id in [
		Stat.ATTACK_PHYSICAL,
		Stat.ATTACK_SPIRITUAL,
		Stat.DEFENSE_PHYSICAL,
		Stat.DEFENSE_SPIRITUAL,
		Stat.PENETRATION,
	]:
		actor.stats.add_modifier(StatModifier.new(id, Stat.Op.FLAT, gear, &"loot_test_gear"))
	return actor


## The loot program as the plain callables the screen consumes. There is no strike slot:
## a domain fight is `CombatApi.exchange`, which the screen calls by name (ADR 0076), so
## the bridge cannot be mis-wired back into a flat-damage path.
func bridge() -> LootBridge:
	var wired := LootBridge.new()
	wired.list_domains = Callable(LootApi, "domains")
	wired.enter_domain = Callable(LootApi, "enter_domain")
	wired.leave_domain = Callable(LootApi, "abandon")
	wired.pickup = Callable(LootApi, "pickup")
	wired.pickup_all = Callable(LootApi, "pickup_all")
	wired.reclaim = Callable(LootApi, "reclaim")
	wired.read_state = Callable(LootApi, "summary")
	return wired


## The same bridge with nothing to enter: the domain list reads empty, which is the
## one input state that leaves `Enter` with nothing to act on.
func bridge_without_domains() -> LootBridge:
	var wired := bridge()
	wired.list_domains = _no_domains
	return wired


func _no_domains() -> Array:
	return []


## The loot screen scene, bound to `actor` and to the real facade. Instantiated
## directly and driven off-tree, which is how the headless suite exercises UI.
func screen(actor: Actor) -> LootEncounterScreen:
	var scene: PackedScene = load(SCREEN_SCENE)
	if scene == null:
		return null
	var view := scene.instantiate() as LootEncounterScreen
	view.call("_ready")
	view.call("setup", actor)
	view.call("bind_bridge", bridge())
	return view


# --- Control drivers. Each one presses the control a player presses.


## Press a button by the unique name the screen scene gave it.
func press(view: LootEncounterScreen, node_name: String) -> bool:
	var button := view.get_node_or_null(node_name) as Button
	if button == null:
		return false
	button.pressed.emit()
	return true


## Move a screen-level selector the way a click does: select, then announce.
func choose(view: LootEncounterScreen, node_name: String, index: int) -> bool:
	return _choose(view.get_node_or_null(node_name), index)


func _choose(option_node: Node, index: int) -> bool:
	var option := option_node as OptionButton
	if option == null:
		return false
	option.select(index)
	option.item_selected.emit(index)
	return true


## Select the entry at `domain_index`/`tier_index` in the screen's own selectors.
## `tier_index` is a *row* in the band selector, not an authored band number.
func select_domain(view: LootEncounterScreen, domain_index: int, tier_index: int = 0) -> bool:
	if not choose(view, "%DomainOption", domain_index):
		return false
	return choose(view, "%TierOption", tier_index)


## The row of the screen's domain selector that names `domain_id`, or -1 when the
## content does not offer it.
##
## Every suite enters a domain through this rather than through a hardcoded row,
## because the row order is a property of the content, not an address: the selector
## is filled from the facade's list sorted by domain id, so a generated encounter
## sorting ahead of the vault silently moves every ordinal the suites were using.
func domain_row(domain_id: StringName) -> int:
	var domains := LootApi.domains()
	for index in domains.size():
		if StringName((domains[index] as Dictionary).get("domain_id", "")) == domain_id:
			return index
	return -1


## The row of the band selector that carries authored band `tier` of `domain_id`,
## or -1 when that band is not authored.
func tier_row(domain_id: StringName, tier: int) -> int:
	for domain in LootApi.domains():
		var descriptor := domain as Dictionary
		if StringName(descriptor.get("domain_id", "")) != domain_id:
			continue
		var bands := descriptor.get("tiers", []) as Array
		for index in bands.size():
			if int((bands[index] as Dictionary).get("tier", -1)) == tier:
				return index
	return -1


## Enter `domain_id` at authored band `tier` through the screen's own three
## controls, in the order a player uses them. False when the content offers no such
## domain or band — which is itself worth failing on, never a reason to enter a
## different one.
func enter_domain(view: LootEncounterScreen, domain_id: StringName, tier: int = 1) -> bool:
	var domain_index := domain_row(domain_id)
	if domain_index < 0:
		return false
	if not choose(view, "%DomainOption", domain_index):
		return false
	if not choose(view, "%TierOption", maxi(0, tier_row(domain_id, tier))):
		return false
	return press(view, "%EnterButton")


func _reward_list(view: LootEncounterScreen) -> LootRewardList:
	return view.get_node_or_null("%RewardList") as LootRewardList


func _stash_list(view: LootEncounterScreen) -> LootRewardList:
	return view.get_node_or_null("%StashList") as LootRewardList


func _rows(list: LootRewardList) -> VBoxContainer:
	return null if list == null else list.get_node_or_null("%RewardRows") as VBoxContainer


## The action button of drop `index` in `list`, i.e. the row's `Pick up` /
## `Reclaim` control. Pressing it is what a player does to take one drop.
func row_action(list: LootRewardList, index: int) -> Button:
	var rows := _rows(list)
	if rows == null or index < 0 or index >= rows.get_child_count():
		return null
	return rows.get_child(index).get_node_or_null("%DropAction") as Button


## Press the row action of drop `index` in the listed reward.
func pick_up_row(view: LootEncounterScreen, index: int) -> bool:
	var action := row_action(_reward_list(view), index)
	if action == null:
		return false
	action.pressed.emit()
	return true


## Press the row action of `index` in the world drop list, i.e. `Reclaim`.
func reclaim_row(view: LootEncounterScreen, index: int) -> bool:
	var action := row_action(_stash_list(view), index)
	if action == null:
		return false
	action.pressed.emit()
	return true


## Press `Take all` on the listed reward.
##
## Returns whether the press *moved anything*. A control that exists but is wired to
## nothing returns false, so a suite learns the action is dead at the control rather
## than three assertions later from a state that never changed. A refusal also returns
## false — it moved nothing — and leaves its own reason on the message line for the
## caller to read. The button is pressed even when it is disabled, because what several
## suites prove is that the *action* refuses and says why; `take_all_offered` is the
## separate question of whether a player is shown the control at all.
func take_all(view: LootEncounterScreen) -> bool:
	var list := _reward_list(view)
	if list == null:
		return false
	var button := list.get_node_or_null("%TakeAllButton") as Button
	if button == null:
		return false
	var before := view.summary()
	button.pressed.emit()
	return _progressed(view.summary(), before)


## Whether `after` shows the world moving: a different owed count, a different claim
## count, or a drop newly parked in the world container.
func _progressed(after: Dictionary, before: Dictionary) -> bool:
	return (
		int(after.get("pending_drops", 0)) != int(before.get("pending_drops", 0))
		or int(after.get("reward_count", 0)) != int(before.get("reward_count", 0))
		or int(after.get("claimed_encounters", 0)) != int(before.get("claimed_encounters", 0))
		or int(after.get("world_drop_count", 0)) != int(before.get("world_drop_count", 0))
	)


## Whether `Take all` is even offered right now. A screen that hides it is better than
## one that refuses it, and a suite has to be able to tell the two apart.
func take_all_offered(view: LootEncounterScreen) -> bool:
	var list := _reward_list(view)
	if list == null:
		return false
	var button := list.get_node_or_null("%TakeAllButton") as Button
	return button != null and not button.disabled


## Kill the live boss and return the encounter id it died under, or "" when the
## screen is not in a domain. Watches the encounter id rather than the vitality, so
## it stops on the same boss instead of killing the rest of the run too. Bounded, so
## a screen that never resolves a kill fails the test instead of hanging it.
##
## Losing the fight also ends the run (ADR 0076), so `in_domain` going false is NOT a
## kill: a loss returns "" exactly like a stall does. Otherwise a hero who simply lost
## would read as having cleared the boss.
func defeat_boss(view: LootEncounterScreen, limit: int = 200) -> String:
	var start := String(view.summary().get("encounter_id", ""))
	if start.is_empty():
		return ""
	var hits := 0
	while hits < limit:
		press(view, "%StrikeButton")
		hits += 1
		var state := view.summary()
		if String(state.get("encounter_id", "")) != start:
			return start
		if not bool(state.get("in_domain", false)):
			return ""
	return ""


## The reward view the screen currently has on display, or `{}`.
func listed_reward(view: LootEncounterScreen) -> Dictionary:
	return view.summary().get("reward", {}) as Dictionary


## Take everything outstanding, one listed payload at a time.
##
## The screen lists a single payload and settles it before the next reaches the list,
## so the drain is: take all of what is listed, then whatever the screen puts up next,
## until nothing is waiting anywhere. Bounded, and it ends the moment a pass moves
## nothing, so a screen whose controls do nothing ends the drain instead of spinning.
func take_everything(view: LootEncounterScreen, limit: int = 20) -> int:
	var rounds := 0
	while rounds < limit:
		rounds += 1
		if int(view.summary().get("pending_drops", 0)) == 0:
			return rounds
		if not take_all(view):
			return rounds
	return rounds


## The realized instance the payload stored for `drop_id`, read the way the save file
## holds it. Read this *before* a pickup, because settling the last drop of a payload
## moves it to the claim ledger and it stops being addressable.
func realized_for(actor: Actor, encounter_id: String, drop_id: String) -> Dictionary:
	var state := LootState.normalize(actor.get_module_data(LootState.MODULE_KEY))
	var payload := (state["rewards"] as Dictionary).get(encounter_id, {}) as Dictionary
	for drop in payload.get("drops", []):
		if String((drop as Dictionary).get("drop_id", "")) == drop_id:
			return (drop as Dictionary).get("instance", {}) as Dictionary
	return {}


## What the inventory now holds for the drop `row` describes, or `{}`. A stackable
## drop is delivered as a batch, which carries no instance id, so the non-stackable
## case matches on the drop id its delivery mints from and the stackable case on the
## realization itself.
func carried_drop(actor: Actor, row: Dictionary) -> Dictionary:
	var inventory := ItemsApi.inventory(actor)
	if inventory == null or row.is_empty():
		return {}
	var stem := String(row.get("instance_id", "")).trim_suffix("#i0")
	for instance in inventory.instances():
		if String(instance.instance_id).begins_with(stem):
			return instance.to_dict()
	for batch in inventory.stacks():
		if (
			String(batch.def_id) == String(row.get("def_id", ""))
			and batch.rolled.size() == int(row.get("rolled_count", 0))
		):
			return batch.to_dict()
	return {}
