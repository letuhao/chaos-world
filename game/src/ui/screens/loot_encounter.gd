class_name LootEncounterScreen
extends UiScreen

## The loot surface: pick a domain and an authored tier, enter it, fight the
## spawned boss, then take what it dropped. Unclaimed rewards and the bounded world
## drop container are always listed, so nothing that exists in the world is hidden
## from the player.
##
## It is a pure consumer. The `loot` side arrives as a [LootBridge] of plain callables
## built by the composition root, so this screen names no loot type and no item type, and
## it owns no rule: every enabled state and every wording comes from what a facade
## returned. The `combat` side is reached by name — `combat` is declared in
## `rules.UI_MODULES`, so `CombatApi` is this program's declared door to it, and a fight
## is `CombatApi.exchange` rather than a damage number a caller chose (ADR 0076). Each
## rejected action leaves the actor untouched and says why.
##
## The encounter readout, including every figure in it, belongs to [LootBossPanel]. This
## screen hands over two primitive views and formats nothing.
##
## ## The status readout is here too (ADR 0106)
##
## `status` is declared in `rules.UI_MODULES`, so [StatusApi] is this program's declared
## door to it, exactly as `combat` is. `StatusApi.summary` is already primitives-only
## (AGENTS.md's testable contract), so the active ids and their timers are read here
## and the *wording* goes to the panel — a screen that printed `fire_immolation 4s`
## itself would own a number format the panel is supposed to own, and the readout would
## then have two places to change.
##
## Widgets live in `loot_encounter.tscn`; the four `ScreenStack` hooks are inherited
## from [UiScreen] and are safe to call at any time.
##
## Contract: `summary()` is the testable surface, and it REPUBLISHES first. Reading this
## screen brings its panels up to date with the world before it answers, because the loot
## state is reachable from outside this screen -- a probe, a boot sweep, a loaded save --
## and a report assembled from a stale panel beside a live facade number is a screen
## describing two different worlds at once. See [method summary].

const STRIKE_SEED := 20260902

var _bridge: LootBridge = null
var _domains: Array = []
var _domain_index: int = -1
var _tier_index: int = 0
var _selected_encounter: String = ""
var _focus_initialized: bool = false
var _header_label: Label = null
var _domain_option: OptionButton = null
var _tier_option: OptionButton = null
var _gate_label: Label = null
var _enter_button: Button = null
var _strike_button: Button = null
var _leave_button: Button = null
var _bonus_label: Label = null
var _boss_panel: LootBossPanel = null
var _reward_list: LootRewardList = null
var _stash_list: LootRewardList = null
## The last action's own verdict, published as primitives by `summary()`.
var _last_ok: bool = false
var _last_reason: String = ""


## Inject the gameplay side. Safe to call again; the domains are re-read.
##
## Repaints, and that is the point rather than a convenience. `bind_bridge` used to
## fill the selectors and stop, so a screen bound to an actor that already had a
## reward showed an EMPTY reward list: the drops were in the world and nothing on
## screen said so until the player pressed an unrelated control and the refresh
## happened as a side effect. A defeated boss's payload was invisible until you
## touched something else.
func bind_bridge(bridge: LootBridge) -> void:
	_bind_nodes()
	_bridge = bridge
	_domains = _read_domains()
	_refresh_domains()
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


## Everything this screen shows, republished first.
##
## `summary()` used to describe a view that could be OLDER than the world, because it
## assembled one dictionary out of two sources with two ages. The live figures --
## `pending_drops`, `claimed_encounters`, `world_drop_count`, the `active` block -- were
## read from the facade on every call, while `reward`, `stashed`, the boss readout and
## every label came from whatever the panels rendered LAST. Nothing reconciled them, so
## they disagreed whenever the world changed by a path this screen did not take: a
## pickup called straight on the loot facade by a probe, a boot sweep or a test, or a
## save loaded over the top. No press, so no republish, so the screen reported its own
## before-picture.
##
## That is not cosmetic. A full bag overflows a drop into the world, which sets the
## drop's own `stashed` flag, and a screen still showing the pre-overflow panel read
## `world_drop_count: 1` beside a reward list whose `stashed_count` was 0 -- the drop
## presented as both in the world and still waiting to be taken, with the row's control
## live and a press that could only be refused.
##
## Republishing on the read makes the reported view current by construction, for every
## observer rather than only the ones who happen to press a control. It repaints the
## widgets through the same call, so the picture and the report cannot diverge, and the
## panels keep sole ownership of how a row is presented (AGENTS.md).
##
## This is deliberately not `summary()` computing the rows itself: a report that reads
## the facade directly would tell the truth while the widgets kept lying, which fixes the
## observer and not the screen.
func summary() -> Dictionary:
	refresh()
	return super()


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


## Exchange one blow with the live boss.
func act_strike() -> bool:
	_bind_nodes()
	if _actor == null:
		return _reject("no_actor")
	if not _in_domain():
		return _reject("not_in_domain")
	var result := CombatApi.exchange(_actor, STRIKE_SEED)
	_settle(result)
	var outcome := String(result.get("outcome", ""))
	if outcome == CombatApi.OUTCOME_PLAYER_LOST:
		return _lost()
	if outcome == CombatApi.OUTCOME_BOSS_DEFEATED:
		set_message("The boss falls.", TONE_OK)
		refresh()
		return true
	return _accepted(result)


## A lost run is not a refusal: the player did everything right and the boss was better.
## The panel shows their restored health and the loss they just took, so these words only
## have to name what happened.
func _lost() -> bool:
	set_message("You fall. The run is lost.", TONE_ERROR)
	refresh()
	return true


## Leave the domain. Unclaimed rewards are kept, so this never loses anything.
func act_leave() -> bool:
	_bind_nodes()
	if _bridge == null or not _bridge.has(&"leave"):
		return _reject("no_loot_module")
	var result := _bridge.call_action(&"leave", [_actor])
	_settle(result)
	return _accepted(result)


## Pick up one drop. A full inventory is reported, not swallowed.
##
## ## Why the row has to belong to the listed reward
##
## `act_take_all` refuses a `stale_reward`, and this used not to: it read the encounter
## off the list and handed the press straight to the facade, so a press naming a drop the
## list was not showing reached the state layer and came back `unknown_drop` -- a refusal
## with no owner, four calls deep from the control that caused it.
##
## The rows are POOLED, so a press can name a drop from a payload that has already been
## retired: `_build` re-renders the rows in use and hides the surplus, and a hidden row
## keeps the `drop_id` it was last given. A reader that resolves a control by name rather
## than by what is on screen -- a probe, a scripted walk -- finds those first. Refusing
## here is the same decision `act_take_all` already makes, in the layer that owns the
## routing: the screen listed one reward, so a drop outside it is not this screen's to
## take. `row_keys` is the list's own answer to "what am I showing", so the guard asks the
## panel rather than re-deriving row membership from the facade.
func act_pickup(drop_id: String) -> bool:
	_bind_nodes()
	if _bridge == null or not _bridge.has(&"pickup"):
		return _reject("no_loot_module")
	var encounter_id := _reward_list.encounter_id()
	if encounter_id.is_empty():
		return _reject("no_reward_selected")
	if not _shown_drops().has(drop_id):
		return _reject("stale_reward")
	var result := _bridge.call_action(&"pickup", [_actor, encounter_id, drop_id])
	_reward_list.report_outcome(drop_id, _reason_of(result), _tone_of(result))
	_settle(result)
	return _accepted(result)


## Take every claimable drop of the listed reward.
##
## ## Why this takes the encounter id the signal sends
##
## `LootRewardList.take_all_requested` declares one argument, and this used to take
## none, so Godot refused the connection with "Method expected 0 argument(s), but
## called with 1". The button rendered, was enabled, and did nothing but log -- the
## exact shape of a control that looks alive and is dead.
##
## The alternative was `.unbind(1)`, which makes the arity match by throwing the
## payload away. That is worse: the signal would keep declaring an id it does not
## use, and the one piece of information that says *which* reward the button belongs
## to would be discarded in transit. So the parameter is taken, with a default so
## the zero-argument callers keep working -- `tools ui drive` invokes `act_take_all()`
## with no arguments and so does the headless suite.
##
## The id is then checked rather than trusted. This screen lists exactly one reward
## (`rewards[0]`), so a signal naming a *different* one means the button belongs to
## a reward that is no longer the one on screen, and taking everything from a reward
## the player cannot see is worse than refusing. That refusal is named
## `stale_reward` so it reads as a refusal.
func act_take_all(encounter_id: String = "") -> bool:
	_bind_nodes()
	if _bridge == null or not _bridge.has(&"pickup_all"):
		return _reject("no_loot_module")
	var shown := _reward_list.encounter_id()
	if shown.is_empty():
		return _reject("no_reward_selected")
	if not encounter_id.is_empty() and encounter_id != shown:
		return _reject("stale_reward")
	var result := _bridge.call_action(&"pickup_all", [_actor, shown])
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
	var boss: Dictionary = _boss_panel.summary()
	var active := state.get("active", {}) as Dictionary
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
		"boss_id": String(active.get("boss_id", "")),
		"encounter_id": String(active.get("encounter_id", "")),
		"vitality": float(active.get("vitality", 0.0)),
		"vitality_max": float(active.get("vitality_max", 0.0)),
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
		"vitality_label": _boss_panel.vitality_text(),
		"boss_label": _boss_panel.boss_text(),
		"player_label": _boss_panel.player_text(),
		"defeat_label": _boss_panel.defeat_text(),
		# The status line is the panel's sentence; the ids behind it stay structured
		# under `boss` rather than being mirrored here as a flat list. A flat copy is a
		# second thing that can be wrong — and the obvious one to get wrong is the
		# catalogue's `ids`, which names every status the game has authored rather than
		# the ones the player is carrying.
		"status_label": _boss_panel.status_text(),
		"health": float(boss.get("health", 0.0)),
		"health_max": float(boss.get("health_max", 0.0)),
		"defeats": int(boss.get("defeats", 0)),
		"bonus": _bonus_label.text,
		"boss": boss,
		"reward": shown,
		"stashed": stashed,
		# The last action's verdict as primitives, not as a sentence. `message` is the
		# screen's own wording and the panels word their own lines separately, so a reader
		# asking WHY a pickup did nothing had three strings to correlate and no way to
		# branch on the answer. These two are the facade's reason id and its `ok`, so one
		# run can tell a full bag from a full world container from a drop that is not
		# there any more -- the refusals that all read as "nothing was collected".
		"last_reason": _last_reason,
		"last_ok": _last_ok,
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
	_boss_panel = get_node_or_null("%BossPanel") as LootBossPanel
	_strike_button = get_node_or_null("%StrikeButton") as Button
	_leave_button = get_node_or_null("%LeaveButton") as Button
	_bonus_label = get_node_or_null("%BonusLabel") as Label
	_reward_list = get_node_or_null("%RewardList") as LootRewardList
	_stash_list = get_node_or_null("%StashList") as LootRewardList
	# Guarded like every connect below. `_bind_nodes` returning early keeps these
	# to one per instance, but a guarded connect is what makes that a fact rather
	# than an accident of the early return: an unguarded one duplicates silently
	# the moment anything calls this again.
	if not _reward_list.row_action_requested.is_connected(act_pickup):
		_reward_list.row_action_requested.connect(act_pickup)
	if not _reward_list.take_all_requested.is_connected(act_take_all):
		_reward_list.take_all_requested.connect(act_take_all)
	# One signal, two meanings: the list says "this row's action was pressed" and the
	# screen decides what that means for the list it belongs to. The stash list's
	# action is a reclaim, and routing it here is what makes the world-drop-container
	# overflow branch reachable at all.
	if not _stash_list.row_action_requested.is_connected(act_reclaim):
		_stash_list.row_action_requested.connect(act_reclaim)
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


## The player's own fight state, as primitives. Read through the `combat` facade, which
## `ui/` may name because `combat` is declared in `rules.UI_MODULES`. Empty when there is
## no actor, so the panel reads "no health" rather than a fabricated pool.
func _player_view() -> Dictionary:
	return CombatApi.preview(_actor) if _actor != null else {}


## What is on the player right now, as primitives (ADR 0106).
##
## Read through the `status` facade, which `ui/` may name because `status` is declared
## in `rules.UI_MODULES`. `{}` with no actor, so a panel bound to nothing reads "no
## statuses" rather than a fabricated one. Nothing here is formatted: the raw dict is
## what the panel renders, and the screen formats no figure.
func _status_view() -> Dictionary:
	return StatusApi.summary(_actor) if _actor != null else {}


func _render_encounter() -> void:
	var state := _state()
	var active := state.get("active", {}) as Dictionary
	var descriptor := _selected_descriptor()
	var required := float(descriptor.get("key_reach", 0.0))
	var carrying := float(state.get("key_reach", 0.0))
	# Every figure on these two lines belongs to the panel; the screen routes the
	# panel's sentences to the labels and formats nothing itself (AGENTS.md).
	_gate_label.text = _boss_panel.gate_text(required, carrying)
	# The player's own `loot_bonus` is shown whether or not a boss is live, so the
	# number that shapes every drop is never hidden.
	_bonus_label.text = _boss_panel.bonus_text(float(state.get("loot_bonus", 0.0)))
	# Both sides of the fight, and both sides' wording, belong to the panel. The screen
	# passes the two primitive views through and formats nothing (ADR 0076).
	_boss_panel.show_fight(active, _player_view())
	# What is eating the player belongs on the same line (ADR 0106), and it is a
	# facade read like the other two: no status rule is re-derived here.
	_boss_panel.show_statuses(_status_view().get("active", []))


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
		# `strike` is deliberately not gated on the loot bridge: the exchange is the
		# `combat` module's own verb (ADR 0076), so it is offered whenever a boss is live.
		"strike": _in_domain(),
		"leave": _bridge != null and _bridge.has(&"leave") and _in_domain(),
		"pickup": _bridge != null and _bridge.has(&"pickup") and _can_pick_up(),
		"take_all": _bridge != null and _bridge.has(&"pickup_all") and _can_pick_up(),
		"reclaim": _bridge != null and _bridge.has(&"reclaim") and _can_reclaim(),
	}


func _header_text() -> String:
	if _actor == null:
		return "Loot — no actor"
	var domain_id := _selected_domain_id()
	return "Loot — %s" % ("no domain authored" if domain_id.is_empty() else domain_id)


## A refusal repaints from the untouched actor, so nothing on screen can drift away
## from the world state.
##
## The refusal records itself as the latest verdict, so a press that never reached the
## facade still leaves `last_reason` naming what stopped it rather than leaving the
## previous action's verdict standing as the answer.
func _reject(reason: String) -> bool:
	_last_ok = false
	_last_reason = reason
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
##
## The result is recorded on the way through, because this is the one place every action
## passes: a refusal raised before the facade was ever called -- a stale row, a control
## with nothing to act on -- records itself in `_reject` instead, so `last_reason` names
## the most recent decision whichever layer made it.
func _settle(result: Dictionary) -> void:
	_last_ok = bool(result.get("ok", false))
	_last_reason = String(result.get("reason", ""))
	refresh()


## The drop ids the reward list is showing right now, as its own row keys.
func _shown_drops() -> Array:
	return _reward_list.summary().get("row_keys", []) as Array


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
