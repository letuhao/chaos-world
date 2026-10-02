class_name LootEncounterScreen
extends UiScreen

## The loot surface: pick a domain and an authored tier, enter it, fight the
## spawned boss, then take what it dropped. Unclaimed rewards and the bounded world
## drop container are always listed, so nothing that exists in the world is hidden
## from the player.
##
## It is a pure consumer. The gameplay side arrives as a [LootBridge] of plain
## callables built by the composition root, so this screen names no module type and
## no item type, and it owns no rule: every enabled state and every wording comes
## from what the facade returned. Each rejected action leaves the actor untouched
## and says why.
##
## Widgets live in `loot_encounter.tscn`; the four `ScreenStack` hooks are inherited
## from [UiScreen] and are safe to call at any time.
##
## Contract: `summary()` is the testable surface.

const STRIKE_SEED := 20260902

var _bridge: LootBridge = null
var _domains: Array = []
var _domain_index: int = -1
var _tier_index: int = 0
var _strike_damage: float = 25.0
var _selected_encounter: String = ""
var _focus_initialized: bool = false
var _header_label: Label = null
var _domain_option: OptionButton = null
var _tier_option: OptionButton = null
var _gate_label: Label = null
var _enter_button: Button = null
var _boss_label: Label = null
var _vitality_bar: ProgressBar = null
var _vitality_label: Label = null
var _strike_button: Button = null
var _leave_button: Button = null
var _bonus_label: Label = null
var _reward_list: LootRewardList = null
var _stash_list: LootRewardList = null


## Inject the gameplay side. Safe to call again; the domains are re-read.
func bind_bridge(bridge: LootBridge) -> void:
	_bind_nodes()
	_bridge = bridge
	_strike_damage = 25.0 if bridge == null else bridge.strike_damage
	_domains = _read_domains()
	_refresh_domains()


## How much damage one strike deals. Authored per caller, never derived from the
## actor's gear here: boss vitality is content, and the fight is the caller's.
func set_strike_damage(damage: float) -> void:
	_strike_damage = maxf(0.0, damage)
	refresh()


func _ready() -> void:
	_bind_nodes()
	refresh()


func on_screen_shown() -> void:
	refresh()


func on_screen_hidden() -> void:
	_focus_initialized = false


## The keyboard and pad land on the entry selector while the player is outside a
## domain, and on the strike button while a boss is live.
func focus_initial() -> void:
	_bind_nodes()
	_focus_initialized = true
	var target: Control = _strike_button if _in_domain() else _enter_button
	if target == null:
		return
	_focus_target = String(target.name)
	if target.is_inside_tree():
		target.grab_focus()


func on_stack_input(_event: InputEvent) -> bool:
	return false


# --- Actions. Each calls the facade through the bridge and reports what came back


## Enter the selected domain at the selected tier.
func act_enter() -> bool:
	_bind_nodes()
	if _bridge == null or not _bridge.has(&"enter"):
		return _reject("no_loot_module")
	var domain_id := _selected_domain_id()
	if domain_id.is_empty():
		return _reject("no_domain_selected")
	var result := _bridge.call_action(&"enter", [_actor, domain_id, _selected_tier(), STRIKE_SEED])
	_settle(result)
	return _accepted(result)


## Deal one strike's worth of damage to the live boss.
func act_strike() -> bool:
	_bind_nodes()
	if _bridge == null or not _bridge.has(&"strike"):
		return _reject("no_loot_module")
	if not _in_domain():
		return _reject("not_in_domain")
	var result := _bridge.call_action(&"strike", [_actor, _strike_damage, STRIKE_SEED])
	_settle(result)
	return _accepted(result)


## Leave the domain. Unclaimed rewards are kept, so this never loses anything.
func act_leave() -> bool:
	_bind_nodes()
	if _bridge == null or not _bridge.has(&"leave"):
		return _reject("no_loot_module")
	var result := _bridge.call_action(&"leave", [_actor])
	_settle(result)
	return _accepted(result)


## Pick up one drop. A full inventory is reported, not swallowed.
func act_pickup(drop_id: String) -> bool:
	_bind_nodes()
	if _bridge == null or not _bridge.has(&"pickup"):
		return _reject("no_loot_module")
	var encounter_id := _reward_list.encounter_id()
	if encounter_id.is_empty():
		return _reject("no_reward_selected")
	var result := _bridge.call_action(&"pickup", [_actor, encounter_id, drop_id])
	_reward_list.report_outcome(drop_id, _reason_of(result), _tone_of(result))
	_settle(result)
	return _accepted(result)


## Take every claimable drop of the listed reward.
func act_take_all() -> bool:
	_bind_nodes()
	if _bridge == null or not _bridge.has(&"pickup_all"):
		return _reject("no_loot_module")
	var encounter_id := _reward_list.encounter_id()
	if encounter_id.is_empty():
		return _reject("no_reward_selected")
	var result := _bridge.call_action(&"pickup_all", [_actor, encounter_id])
	_settle(result)
	return _accepted(result)


## Take one drop back out of the world drop container.
func act_reclaim(drop_id: String) -> bool:
	_bind_nodes()
	if _bridge == null or not _bridge.has(&"reclaim"):
		return _reject("no_loot_module")
	var result := _bridge.call_action(&"reclaim", [_actor, drop_id])
	_stash_list.report_outcome(drop_id, _reason_of(result), _tone_of(result))
	_settle(result)
	return _accepted(result)


func _summary() -> Dictionary:
	if _actor == null or _bridge == null:
		return {}
	var state := _state()
	if state.is_empty():
		return {}
	var rewards: Array = state.get("rewards", [])
	var shown: Dictionary = _reward_list.summary()
	var stashed: Dictionary = _stash_list.summary()
	return {
		"has_actor": _actor != null,
		"actor_id": String(_actor.id),
		"domain_count": _domains.size(),
		"domain_id": _selected_domain_id(),
		"domain_label": _header_label.text,
		"tier": _selected_tier(),
		"tier_label":
		_tier_option.get_item_text(_tier_option.selected) if _tier_count() > 0 else "",
		"in_domain": _in_domain(),
		"boss_id": String((state.get("active", {}) as Dictionary).get("boss_id", "")),
		"encounter_id": String((state.get("active", {}) as Dictionary).get("encounter_id", "")),
		"vitality": float((state.get("active", {}) as Dictionary).get("vitality", 0.0)),
		"vitality_max": float((state.get("active", {}) as Dictionary).get("vitality_max", 0.0)),
		"reward_count": rewards.size(),
		"reward_encounter_id": String(shown.get("encounter_id", "")),
		"pending_drops": int(state.get("pending_drops", 0)),
		"claimed_encounters": int(state.get("claimed_encounters", 0)),
		"world_drop_count": int(state.get("world_drop_count", 0)),
		"world_drop_capacity": int(state.get("world_drop_capacity", 0)),
		"world_drops_full": bool(state.get("world_drops_full", false)),
		"key_reach": float(state.get("key_reach", 0.0)),
		"loot_bonus": float(state.get("loot_bonus", 0.0)),
		"enabled": _enabled(),
		"gate": _gate_label.text,
		"vitality_label": _vitality_label.text,
		"bonus": _bonus_label.text,
		"reward": shown,
		"stashed": stashed,
	}


func _refresh_view() -> void:
	_bind_nodes()
	_header_label.text = _header_text()
	_refresh_domains()
	_render_encounter()
	_render_lists()


func _render() -> void:
	pass


func _bind_nodes() -> void:
	if _header_label != null:
		return
	_header_label = get_node_or_null("%HeaderLabel") as Label
	_domain_option = get_node_or_null("%DomainOption") as OptionButton
	_tier_option = get_node_or_null("%TierOption") as OptionButton
	_gate_label = get_node_or_null("%GateLabel") as Label
	_enter_button = get_node_or_null("%EnterButton") as Button
	_boss_label = get_node_or_null("%BossLabel") as Label
	_vitality_bar = get_node_or_null("%VitalityBar") as ProgressBar
	_vitality_label = get_node_or_null("%VitalityLabel") as Label
	_strike_button = get_node_or_null("%StrikeButton") as Button
	_leave_button = get_node_or_null("%LeaveButton") as Button
	_bonus_label = get_node_or_null("%BonusLabel") as Label
	_reward_list = get_node_or_null("%RewardList") as LootRewardList
	_stash_list = get_node_or_null("%StashList") as LootRewardList
	_reward_list.pickup_requested.connect(act_pickup)
	_reward_list.take_all_requested.connect(act_take_all)
	_stash_list.pickup_requested.connect(act_reclaim)
	if (
		_domain_option != null
		and not _domain_option.item_selected.is_connected(_on_domain_selected)
	):
		_domain_option.item_selected.connect(_on_domain_selected)
	if _enter_button != null and not _enter_button.pressed.is_connected(act_enter):
		_enter_button.pressed.connect(act_enter)
	if _strike_button != null and not _strike_button.pressed.is_connected(act_strike):
		_strike_button.pressed.connect(act_strike)
	if _leave_button != null and not _leave_button.pressed.is_connected(act_leave):
		_leave_button.pressed.connect(act_leave)


# --- Plumbing ---------------------------------------------------------------


func _state() -> Dictionary:
	if _bridge == null or not _bridge.has(&"state") or _actor == null:
		return {}
	return _bridge.call_action(&"state", [_actor])


func _read_domains() -> Array:
	if _bridge == null or not _bridge.has(&"domains"):
		return []
	var result = _bridge.list_domains.call()
	return result as Array if result is Array else []


## Fill the two selectors from the facade's domain list. Presentation only: the
## screen never invents a domain or a tier.
func _refresh_domains() -> void:
	if _domain_option == null or _tier_option == null:
		return
	var keep_domain := _selected_domain_id()
	_domain_option.clear()
	var labels: Array = []
	var ids: Array = []
	for index in _domains.size():
		var descriptor := _domains[index] as Dictionary
		var domain_id := String(descriptor.get("domain_id", ""))
		ids.append(domain_id)
		labels.append(String(descriptor.get("display_name", domain_id)))
		_domain_option.add_item(String(labels[index]))
	# Match on the stable domain id, never on the label: the label is presentation.
	_domain_index = maxi(0, ids.find(keep_domain))
	if not labels.is_empty():
		_domain_option.select(_domain_index)
	_fill_tiers()


func _fill_tiers() -> void:
	_tier_option.clear()
	for tier in _selected_descriptor().get("tiers", []):
		var row := tier as Dictionary
		_tier_option.add_item(String(row.get("label", row.get("tier", ""))))
	if _tier_option.item_count > 0:
		_tier_option.select(clampi(_tier_index, 0, _tier_option.item_count - 1))


func _selected_descriptor() -> Dictionary:
	var index := _selected_index()
	if index < 0:
		return {}
	return _domains[index] as Dictionary


## The widget's selection is the truth once it exists; the field only carries it
## across a refill, so a programmatic `select()` is honoured like a click.
func _selected_index() -> int:
	var index := _domain_option.selected if _domain_option != null else _domain_index
	if index < 0 or index >= _domains.size():
		return -1
	return index


func _selected_domain_id() -> String:
	return String(_selected_descriptor().get("domain_id", ""))


func _selected_tier() -> int:
	var tiers: Array = _selected_descriptor().get("tiers", [])
	if tiers.is_empty():
		return 0
	var index := _tier_option.selected if _tier_option != null else 0
	if index < 0 or index >= tiers.size():
		index = 0
	return int((tiers[index] as Dictionary).get("tier", 0))


func _tier_count() -> int:
	return (_selected_descriptor().get("tiers", []) as Array).size()


func _in_domain() -> bool:
	return bool((_state().get("active", {}) as Dictionary).get("in_domain", false))


func _render_encounter() -> void:
	var state := _state()
	var active := state.get("active", {}) as Dictionary
	var descriptor := _selected_descriptor()
	_gate_label.text = _gate_text(descriptor, state)
	# The player's own `loot_bonus` is shown whether or not a boss is live, so the
	# number that shapes every drop is never hidden.
	_bonus_label.text = "Loot bonus %.2f" % float(state.get("loot_bonus", 0.0))
	if not bool(active.get("in_domain", false)):
		_boss_label.text = "Outside a domain"
		_vitality_bar.value = 0.0
		_vitality_label.text = ""
		return
	_boss_label.text = String(active.get("boss_id", ""))
	_vitality_bar.max_value = maxf(1.0, float(active.get("vitality_max", 1.0)))
	_vitality_bar.value = clampf(float(active.get("vitality", 0.0)), 0.0, _vitality_bar.max_value)
	_vitality_label.text = (
		"%d / %d vitality"
		% [
			int(active.get("vitality", 0.0)),
			int(active.get("vitality_max", 0.0)),
		]
	)


func _render_lists() -> void:
	var state := _state()
	var rewards: Array = state.get("rewards", [])
	var listed: Dictionary = rewards[0] as Dictionary if not rewards.is_empty() else {}
	_reward_list.show_reward(listed, _can_pick_up())
	_stash_list.show_stashes(state.get("world_drops", []), _can_reclaim())


## Picking a drop up needs a free slot; the facade still decides, so this only
## controls whether the button is live.
func _can_pick_up() -> bool:
	var state := _state()
	return _actor != null and int(state.get("world_drop_capacity", 0)) > 0


func _can_reclaim() -> bool:
	return _can_pick_up()


func _enabled() -> Dictionary:
	var state := _state()
	return {
		"enter":
		(
			_bridge != null
			and _bridge.has(&"enter")
			and not _in_domain()
			and _selected_domain_id() != ""
		),
		"strike": _bridge != null and _bridge.has(&"strike") and _in_domain(),
		"leave": _bridge != null and _bridge.has(&"leave") and _in_domain(),
		"pickup": _bridge != null and _bridge.has(&"pickup") and _can_pick_up(),
		"take_all": _bridge != null and _bridge.has(&"pickup_all") and _can_pick_up(),
		"reclaim": _bridge != null and _bridge.has(&"reclaim") and _can_reclaim(),
	}


func _gate_text(descriptor: Dictionary, state: Dictionary) -> String:
	var required := int(descriptor.get("key_reach", 0))
	if required <= 0:
		return "Open domain"
	return "Needs key reach %d, carrying %d" % [required, int(state.get("key_reach", 0.0))]


func _header_text() -> String:
	if _actor == null:
		return "Loot — no actor"
	var domain_id := _selected_domain_id()
	return "Loot — %s" % ("no domain authored" if domain_id.is_empty() else domain_id)


## A refusal repaints from the untouched actor, so nothing on screen can drift away
## from the world state.
func _reject(reason: String) -> bool:
	set_message("Rejected: %s" % reason, TONE_ERROR)
	refresh()
	return false


func _accepted(result: Dictionary) -> bool:
	if bool(result.get("ok", false)):
		_tone = TONE_OK
		refresh()
		return true
	return _reject(String(result.get("reason", "rejected")))


## Every action ends by re-reading the world and repainting; the outcome wording is
## owned by the panels.
func _settle(_result: Dictionary) -> void:
	refresh()


func _reason_of(result: Dictionary) -> String:
	return String(result.get("reason", ""))


func _tone_of(result: Dictionary) -> StringName:
	if bool(result.get("ok", false)):
		return &"ok"
	return &"error"


func _on_domain_selected(index: int) -> void:
	_domain_index = maxi(0, index)
	_tier_index = 0
	_fill_tiers()
	refresh()
