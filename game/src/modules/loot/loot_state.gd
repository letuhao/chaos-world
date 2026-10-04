class_name LootState
extends RefCounted

## The persisted loot lifecycle: enter, spawn, defeat, claim, clear, re-enter.
##
## State lives in `actor.module_data["loot_state"]` as a plain versioned
## dictionary, applied through `Actor.set_module_data`, so core never references a
## loot type and `Actor.to_dict()` already carries the whole thing (ADR 0027).
##
## ## Declared encounter rules
##
##   E1  One reward per encounter. An encounter is `(domain, boss, tier, run)` and
##       owns at most one payload, keyed by its deterministic encounter id. A
##       repeated death event, a re-entry and a save/load all resolve the same id,
##       so none of them can mint a second payload.
##   E2  A cleared band grants no new run. Re-entering a band that has been cleared is
##       refused (`domain_cleared`) and mints nothing. A band that has not been cleared
##       grants the next run — or resumes the one still in flight there.
##   E3  The next boss spawns as soon as the previous one is defeated, whether or
##       not its reward has been picked up. A full inventory therefore never
##       blocks progress and never loses a drop.
##   E4  Abandoning a domain discards the in-progress boss, never a reward.
##       Re-entering the same tier resumes the same run at the first boss that has
##       no reward yet.
##   E5  A pickup is all-or-nothing per drop. A refused pickup never spends the
##       claim and never discards the drop.
##   E6  An empty outcome is a decided outcome. A table that legitimately drops
##       nothing records the encounter as spent immediately, so it cannot be
##       re-rolled by a repeated death event.

const SCHEMA_VERSION := 2
const MODULE_KEY := &"loot_state"
## Bounded world drop container. A pickup that cannot fit the inventory overflows
## here while there is room; once it is full a pickup is refused outright.
const WORLD_DROP_CAPACITY := 6

# --- Reasons. Every refusal and every outcome has a stable id a reader can show.
const OK_ENTERED := "entered"
const OK_ALIVE := "alive"
const OK_DEFEATED := "defeated"
const OK_DUPLICATE := "already_defeated"
const OK_NO_DROP := "no_drop"
const OK_ABANDONED := "abandoned"
const OK_CLAIMED := "claimed"
const OK_OVERFLOW := "overflow"
const ERR_NOT_IN_DOMAIN := "not_in_domain"
const ERR_ALREADY_IN_DOMAIN := "already_in_domain"
const ERR_UNKNOWN_DOMAIN := "unknown_domain"
const ERR_UNKNOWN_TIER := "unknown_tier"
const ERR_DOMAIN_CLEARED := "domain_cleared"
const ERR_KEY_REACH := "key_reach_too_low"
const ERR_NO_DAMAGE := "no_damage"
const ERR_UNKNOWN_REWARD := "unknown_reward"
const ERR_CLAIM_SPENT := "claim_already_spent"
const ERR_UNKNOWN_DROP := "unknown_drop"
const ERR_DROP_CLAIMED := "drop_already_claimed"
const ERR_DROP_STASHED := "drop_stashed_in_world"
const ERR_NO_INVENTORY := "no_inventory"
const ERR_INVENTORY_FULL := "inventory_full"
const ERR_WORLD_FULL := "world_drops_full"
const ERR_UNKNOWN_DEFINITION := "unknown_definition"
const ERR_UNKNOWN_STASH := "unknown_stash"


static func blank() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"runs": {},
		"active": {},
		"rewards": {},
		"claimed": {},
		"world_drops": [],
	}


## A usable state from anything `module_data` may hold. A payload written before
## a field existed loads with that field empty rather than failing, and the
## schema version is stamped on the way out.
##
## ## One ledger key, and why the version moved
##
## The run ledger used to be keyed by `domain_id` alone and to carry a single
## `run` / `run_tier` / `cleared_tier` triple per domain. Everything else in this file —
## `active`, `rewards`, `claimed` — is keyed by [method encounter_id], which embeds
## **both** the authored band and the run. So the two disagreed the moment one domain
## had two bands in flight: the second band's entry overwrote the first's, and the
## first band's remaining bosses became unreachable, because re-entering it computed a
## run number its encounter ids no longer used (BL-0252).
##
## Keyed per (domain, band) — [method run_key] — the ledger names the same triple
## structure as the ids it has to keep straight, so the disagreement is no longer
## expressible. A v1 payload migrates through [method _migrate_runs], which preserves
## the rules it was written under rather than improving on them.
static func normalize(raw: Dictionary) -> Dictionary:
	var state := blank()
	if raw.is_empty():
		return state
	for key in ["runs", "active", "rewards", "claimed"]:
		if raw.get(key) is Dictionary:
			state[key] = (raw[key] as Dictionary).duplicate(true)
	if raw.get("world_drops") is Array:
		state["world_drops"] = (raw["world_drops"] as Array).duplicate(true)
	var runs := state["runs"] as Dictionary
	if int(raw.get("version", 1)) < SCHEMA_VERSION:
		runs = _migrate_runs(runs)
	state["runs"] = _normalized_runs(runs)
	state["version"] = SCHEMA_VERSION
	return state


## The run ledger's key: one entry per (domain, authored band), never one per domain.
## It carries the same two facts [method encounter_id] embeds, so the ledger and the ids
## it has to keep straight are keyed identically.
static func run_key(domain_id: String, tier_index: int) -> String:
	return "%s@%d" % [domain_id, tier_index]


## Re-file a v1 ledger, keyed by domain, onto (domain, band). A v1 record always wrote
## `run_tier` beside `run`, so the band it belongs to is named in the record itself; a
## record without one names no band and cannot be placed, so it is dropped rather than
## guessed at. A band counts as cleared exactly when it sat at or below v1's
## `cleared_tier`, because that is what v1 refused — a save resumes under the rules it
## was written under, not under stricter ones.
static func _migrate_runs(legacy: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for domain_id in legacy.keys():
		var raw = legacy[domain_id]
		if not raw is Dictionary:
			continue
		var record := raw as Dictionary
		var tier := int(record.get("run_tier", -1))
		if tier < 0:
			continue
		out[run_key(String(domain_id), tier)] = {
			"run": int(record.get("run", 0)),
			"cleared": int(record.get("cleared_tier", -1)) >= tier,
		}
	return out


## A ledger of well-formed band entries: every key names a band, every record is a
## `{run, cleared}` pair of the right types. An unusable entry is dropped rather than
## repaired, so a hand-edited save cannot inject a run number nothing agrees with.
static func _normalized_runs(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for band in raw.keys():
		if not String(band).contains("@"):
			continue
		var value = raw[band]
		if not value is Dictionary:
			continue
		var record := value as Dictionary
		out[String(band)] = {
			"run": maxi(0, int(record.get("run", 0))),
			"cleared": bool(record.get("cleared", false)),
		}
	return out


## Deterministic encounter id. It is the claim token and the payload key, so it
## must depend on nothing that a reload can change.
static func encounter_id(domain_id: String, boss_id: String, tier: int, run: int) -> String:
	return "%s/%s@%d#%d" % [domain_id, boss_id, tier, run]


static func has_reward(state: Dictionary, encounter_id: String) -> bool:
	return state.get("rewards", {}).has(encounter_id)


static func is_spent(state: Dictionary, encounter_id: String) -> bool:
	return state.get("claimed", {}).has(encounter_id)


# --- Entry ------------------------------------------------------------------


## Rule E2/E4: grant or resume a run in `domain_id` at `tier_index`.
##
## The ledger is written **once the outcome is known**, never before. It used to be
## written first, which meant the entry's refusal paths were describing a ledger that
## had already moved. The branch that refused a fully-claimed run turned out to be
## unreachable — `resumes` implies `_run_in_flight`, which implies
## `_first_undefeated >= 0`, so that lookup could never come back empty — so the
## reachable defect was the keying alone. The ordering is kept because the two shapes
## disagreeing is the thing worth making unrepresentable, not just the one case that
## happened to be reachable.
static func enter(
	state: Dictionary, encounter: LootEncounterDef, tier_index: int, seed_value: int
) -> Dictionary:
	if encounter == null:
		return {"ok": false, "reason": ERR_UNKNOWN_DOMAIN}
	if not (state.get("active", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": ERR_ALREADY_IN_DOMAIN}
	var tier := encounter.tier_at(tier_index)
	if tier == null:
		return {"ok": false, "reason": ERR_UNKNOWN_TIER, "tier": tier_index}
	var domain_id := String(encounter.domain_id)
	var band := run_key(domain_id, tier_index)
	var runs: Dictionary = state["runs"]
	var record: Dictionary = runs.get(band, {})
	if bool(record.get("cleared", false)):
		# E2: a band that has been fought through grants no new run, so walking back in
		# cannot farm it and cannot re-award the encounter that cleared it. Refusing the
		# BAND rather than the domain is the honest report: another band of the same
		# domain may well be unfinished, and v1's single `cleared_tier` maximum could
		# not say so.
		return _cleared(domain_id, band, tier_index, int(record.get("run", 0)))
	var existing_run := int(record.get("run", 0))
	# Rule E4 resumes the same run only when it is still in flight **at this band**. The
	# band is part of the ledger key, so this can no longer be answering for a band that
	# is not the one being entered.
	var resumes := existing_run > 0 and _run_in_flight(state, encounter, tier_index, existing_run)
	var run := existing_run if resumes else existing_run + 1
	record["run"] = run
	runs[band] = record
	state["runs"] = runs
	var boss_index := _first_undefeated(state, encounter, tier_index, run)
	if boss_index < 0:
		# The run this band resumed is already fought through — every boss of it holds a
		# reward or a spent claim. That is a cleared band, and saying so is the only
		# honest answer; recording it here rather than on the way in is what keeps a
		# refusal from having moved the counter.
		record["cleared"] = true
		runs[band] = record
		state["runs"] = runs
		return _cleared(domain_id, band, tier_index, run)
	state["active"] = _spawn(encounter, tier, tier_index, run, boss_index)
	var result := {
		"ok": true,
		"reason": OK_ENTERED,
		"domain_id": domain_id,
		"band": band,
		"tier": tier_index,
		"tier_label": String(tier.label),
		"run": run,
		"seed": seed_value,
	}
	result["active"] = LootRewards.active_view(state["active"])
	return result


## Rule E2's refusal, naming the band rather than a per-domain maximum.
static func _cleared(domain_id: String, band: String, tier_index: int, run: int) -> Dictionary:
	return {
		"ok": false,
		"reason": ERR_DOMAIN_CLEARED,
		"domain_id": domain_id,
		"band": band,
		"tier": tier_index,
		"run": run,
		"cleared": true,
	}


# --- Combat -----------------------------------------------------------------


## Apply `damage` to the active boss, and defeat it when its authored vitality is
## spent. Rule E1 lives here: a boss that is already defeated — or whose reward
## already exists — returns the same payload instead of minting another.
##
## ## Why the boss's own AFFLICTION rides here
##
## This is the primitive every landed blow goes through, and it is the only `loot` verb
## `CombatExchange.exchange` calls on a press (`exchange.gd:88`), so it is the one place a
## boss can reach the player with something other than a share of health. The infliction
## is read off the boss **that was struck** — captured before the pool is spent, because a
## defeating blow advances the band and the next boss must not inherit the answer meant
## for the one that fell.
##
## `afflict_chance` and `afflict_magnitude` are the CALLER's ADR 0087/0088 numbers and
## default to an open gate at `1.0` so `LootApi.strike` — which every existing caller
## uses with three arguments — inflicts with the status module's own default potency. A
## defeated boss inflicts nothing: the fight is over and ADR 0089's purge clears COMBAT
## scope on the exit.
static func strike(
	state: Dictionary,
	actor: Actor,
	damage: float,
	seed_value: int,
	afflict_chance: float = 1.0,
	afflict_magnitude: float = 1.0
) -> Dictionary:
	var active: Dictionary = state.get("active", {})
	if active.is_empty():
		return {"ok": false, "reason": ERR_NOT_IN_DOMAIN}
	var encounter := String(active.get("encounter_id", ""))
	if (
		bool(active.get("defeated", false))
		or has_reward(state, encounter)
		or is_spent(state, encounter)
	):
		return _duplicate(state, encounter)
	if not is_finite(damage) or damage <= 0.0:
		return {
			"ok": false,
			"reason": ERR_NO_DAMAGE,
			"encounter_id": encounter,
			"vitality": float(active.get("vitality", 0.0)),
			"vitality_max": float(active.get("vitality_max", 0.0)),
		}
	# BEFORE the pool is spent: the band advances on a defeat (rule E3) and a new boss
	# carries its own affliction, which is not what this blow met.
	var affliction := LootAffliction.inflict(actor, active, afflict_chance, afflict_magnitude)
	active["vitality"] = maxf(0.0, float(active["vitality"]) - damage)
	state["active"] = active
	if float(active["vitality"]) > 0.0:
		return {
			"ok": true,
			"reason": OK_ALIVE,
			"encounter_id": encounter,
			"vitality": float(active["vitality"]),
			"vitality_max": float(active["vitality_max"]),
			"affliction": affliction,
		}
	return _defeat(state, actor, seed_value, affliction)


static func _duplicate(state: Dictionary, encounter: String) -> Dictionary:
	var rewards: Dictionary = state["rewards"]
	if rewards.has(encounter):
		return {
			"ok": true,
			"reason": OK_DUPLICATE,
			"duplicate": true,
			"encounter_id": encounter,
			"drop_count": (rewards[encounter] as Dictionary).get("drops", []).size(),
			"reward": LootRewards.view(rewards[encounter]),
		}
	return {
		"ok": true,
		"reason": OK_DUPLICATE,
		"duplicate": true,
		"encounter_id": encounter,
		"drop_count": 0,
		"reward": {},
	}


static func _defeat(
	state: Dictionary, actor: Actor, seed_value: int, affliction: Dictionary
) -> Dictionary:
	var active: Dictionary = state["active"]
	var encounter := String(active.get("encounter_id", ""))
	active["defeated"] = true
	state["active"] = active
	if has_reward(state, encounter) or is_spent(state, encounter):
		return _duplicate(state, encounter)
	var boss_id := StringName(active.get("boss_id", ""))
	var tier_index := int(active.get("tier", 0))
	var encounter_def := LootContent.instance().encounter_by_id(
		StringName(active.get("encounter_def", ""))
	)
	var tier := encounter_def.tier_at(tier_index) if encounter_def != null else null
	var table := LootContent.instance().table_for_boss(boss_id, tier_index)
	var axes := LootBonus.axes_for(actor)
	var context := LootResolver.make_context(
		StringName(active.get("tier_realm", "")),
		StringName(active.get("tier_rarity", "")),
		boss_id,
		axes
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = _encounter_seed(seed_value, encounter)
	var resolved := LootResolver.resolve(table, context, rng)
	var payload := LootRewards.build(
		encounter,
		boss_id,
		StringName(active.get("domain_id", "")),
		tier,
		table,
		resolved["plans"],
		rng.seed,
		resolved["warnings"]
	)
	var drops: Array = payload["drops"]
	var rewards: Dictionary = state["rewards"]
	if drops.is_empty():
		# E6: an empty outcome is decided, not pending. Recording it as spent is
		# what stops a repeated death event from re-rolling the same no-drop.
		var claims: Dictionary = state["claimed"]
		claims[encounter] = {
			"drops": 0, "tier": tier_index, "reason": OK_NO_DROP, "seed": seed_value
		}
		state["claimed"] = claims
	else:
		rewards[encounter] = payload
	state["rewards"] = rewards
	_advance(state)
	return {
		"ok": true,
		"reason": OK_DEFEATED if not drops.is_empty() else OK_NO_DROP,
		"duplicate": false,
		"encounter_id": encounter,
		"drop_count": drops.size(),
		"warnings": resolved["warnings"],
		"reward": LootRewards.view(payload),
		# What the boss that FELL inflicted, carried through `_advance` because the
		# `active` key now describes the NEXT boss. A caller showing "what that fight
		# did to you" must not have to have read the state before this call.
		"affliction": affliction,
		"active": LootRewards.active_view(state["active"]),
	}


## Rule E4: leave the domain. The in-progress boss is discarded, nothing else.
static func abandon(state: Dictionary) -> Dictionary:
	var active: Dictionary = state.get("active", {})
	if active.is_empty():
		return {"ok": false, "reason": ERR_NOT_IN_DOMAIN}
	var boss_id := String(active.get("boss_id", ""))
	var encounter := String(active.get("encounter_id", ""))
	state["active"] = {}
	return {
		"ok": true,
		"reason": OK_ABANDONED,
		"boss_id": boss_id,
		"encounter_id": encounter,
		"reward_kept": has_reward(state, encounter),
		"active": LootRewards.active_view(state["active"]),
	}


# --- Claims -----------------------------------------------------------------


## Rule E5: hand one drop to the inventory. Returns `status` of `claimed`
## (delivered), `overflow` (moved to the bounded world drop container) or
## `refused` (nothing changed, the claim is untouched).
static func pickup(
	state: Dictionary, encounter: String, drop_id: String, inventory: Inventory
) -> Dictionary:
	if is_spent(state, encounter):
		return {
			"ok": false, "status": "refused", "reason": ERR_CLAIM_SPENT, "encounter_id": encounter
		}
	var rewards: Dictionary = state["rewards"]
	if not rewards.has(encounter):
		return {
			"ok": false,
			"status": "refused",
			"reason": ERR_UNKNOWN_REWARD,
			"encounter_id": encounter
		}
	if inventory == null:
		return {
			"ok": false, "status": "refused", "reason": ERR_NO_INVENTORY, "encounter_id": encounter
		}
	var payload: Dictionary = rewards[encounter]
	var drops: Array = payload["drops"]
	var index := _drop_index(drops, drop_id)
	if index < 0:
		return {
			"ok": false,
			"status": "refused",
			"reason": ERR_UNKNOWN_DROP,
			"encounter_id": encounter,
			"drop_id": drop_id
		}
	var drop: Dictionary = drops[index]
	if bool(drop.get("claimed", false)):
		return {
			"ok": false,
			"status": "refused",
			"reason": ERR_DROP_CLAIMED,
			"encounter_id": encounter,
			"drop_id": drop_id
		}
	if bool(drop.get("stashed", false)):
		return {
			"ok": false,
			"status": "refused",
			"reason": ERR_DROP_STASHED,
			"encounter_id": encounter,
			"drop_id": drop_id
		}
	var realized := LootRewards.instance_from(drop, "")
	if not LootRewards.fits(drop, inventory, realized):
		return _overflow(state, encounter, drop, index)
	if LootRewards.deliver(drop, inventory) > 0:
		return {
			"ok": false,
			"status": "refused",
			"reason": ERR_INVENTORY_FULL,
			"world_drops_full": state["world_drops"].size() >= WORLD_DROP_CAPACITY,
			"encounter_id": encounter,
			"drop_id": drop_id,
		}
	drop["claimed"] = true
	drops[index] = drop
	payload["drops"] = drops
	rewards[encounter] = payload
	state["rewards"] = rewards
	_settle(state, encounter, payload)
	return {
		"ok": true,
		"status": OK_CLAIMED,
		"reason": "",
		"encounter_id": encounter,
		"drop_id": drop_id
	}


## Deliver every claimable drop in `encounter`. Each drop keeps its own outcome,
## so one full-inventory drop cannot hold back the rest.
static func pickup_all(state: Dictionary, encounter: String, inventory: Inventory) -> Dictionary:
	var outcomes: Array = []
	if is_spent(state, encounter):
		return {
			"ok": false,
			"status": "refused",
			"reason": ERR_CLAIM_SPENT,
			"encounter_id": encounter,
			"results": outcomes
		}
	var rewards: Dictionary = state["rewards"]
	if not rewards.has(encounter):
		return {
			"ok": false,
			"status": "refused",
			"reason": ERR_UNKNOWN_REWARD,
			"encounter_id": encounter,
			"results": outcomes
		}
	for drop in (rewards[encounter] as Dictionary)["drops"].duplicate():
		outcomes.append(pickup(state, encounter, String(drop.get("drop_id", "")), inventory))
	var claimed := 0
	var overflowed := 0
	for outcome in outcomes:
		if String(outcome.get("status", "")) == OK_CLAIMED:
			claimed += 1
		elif String(outcome.get("status", "")) == OK_OVERFLOW:
			overflowed += 1
	return {
		"ok": claimed > 0,
		"status": OK_CLAIMED if claimed > 0 else "refused",
		"encounter_id": encounter,
		"claimed": claimed,
		"overflowed": overflowed,
		"refused": outcomes.size() - claimed - overflowed,
		"results": outcomes,
	}


## Rule E5: take one drop back out of the bounded world drop container.
static func reclaim(state: Dictionary, stash_id: String, inventory: Inventory) -> Dictionary:
	var stashes: Array = state["world_drops"]
	var stash_index := _stash_index(stashes, stash_id)
	if stash_index < 0:
		return {"ok": false, "status": "refused", "reason": ERR_UNKNOWN_STASH, "stash_id": stash_id}
	if inventory == null:
		return {"ok": false, "status": "refused", "reason": ERR_NO_INVENTORY, "stash_id": stash_id}
	var stash: Dictionary = stashes[stash_index]
	var encounter := String(stash.get("encounter_id", ""))
	var rewards: Dictionary = state["rewards"]
	if not rewards.has(encounter):
		stashes.remove_at(stash_index)
		state["world_drops"] = stashes
		return {
			"ok": false, "status": "refused", "reason": ERR_UNKNOWN_REWARD, "stash_id": stash_id
		}
	var payload: Dictionary = rewards[encounter]
	var drops: Array = payload["drops"]
	var index := _drop_index(drops, String(stash.get("drop_id", "")))
	if index < 0:
		stashes.remove_at(stash_index)
		state["world_drops"] = stashes
		return {"ok": false, "status": "refused", "reason": ERR_UNKNOWN_DROP, "stash_id": stash_id}
	var drop: Dictionary = drops[index]
	var realized := LootRewards.instance_from(drop, "")
	if not LootRewards.fits(drop, inventory, realized) or LootRewards.deliver(drop, inventory) > 0:
		# Stays in the world container, claim untouched: a full inventory never
		# destroys a drop that already exists.
		return {
			"ok": false,
			"status": "refused",
			"reason": ERR_INVENTORY_FULL,
			"stash_id": stash_id,
			"encounter_id": encounter,
		}
	drop["claimed"] = true
	drop["stashed"] = false
	drops[index] = drop
	payload["drops"] = drops
	rewards[encounter] = payload
	state["rewards"] = rewards
	stashes.remove_at(stash_index)
	state["world_drops"] = stashes
	_settle(state, encounter, payload)
	return {
		"ok": true,
		"status": OK_CLAIMED,
		"reason": "",
		"stash_id": stash_id,
		"encounter_id": encounter
	}


static func _overflow(
	state: Dictionary, encounter: String, drop: Dictionary, index: int
) -> Dictionary:
	var drop_id := String(drop.get("drop_id", ""))
	var stashes: Array = state["world_drops"]
	if stashes.size() >= WORLD_DROP_CAPACITY:
		# Bounded container is full: the pickup is refused outright. Nothing is
		# discarded, no claim is spent, and the drop stays pickable in the reward.
		#
		# `ERR_WORLD_FULL`, not `ERR_INVENTORY_FULL`: nothing was parked, so the
		# overflow sentence -- "the drop is in the world and can be reclaimed" -- is
		# false here, and `ERR_WORLD_FULL` already has wording of its own that a
		# reader can act on. Two refusals that name the same reason are one refusal
		# with a wrong label on one of them.
		return {
			"ok": false,
			"status": "refused",
			"reason": ERR_WORLD_FULL,
			"world_drops_full": true,
			"encounter_id": encounter,
			"drop_id": drop_id,
		}
	drop["stashed"] = true
	var rewards: Dictionary = state["rewards"]
	var payload: Dictionary = rewards[encounter]
	var drops: Array = payload["drops"]
	drops[index] = drop
	payload["drops"] = drops
	rewards[encounter] = payload
	state["rewards"] = rewards
	stashes.append({"stash_id": drop_id, "encounter_id": encounter, "drop_id": drop_id})
	state["world_drops"] = stashes
	return {
		"ok": true,
		"status": OK_OVERFLOW,
		"reason": ERR_INVENTORY_FULL,
		"encounter_id": encounter,
		"drop_id": drop_id,
		"stash_id": drop_id,
		"world_drops_full": false,
	}


# --- Internals --------------------------------------------------------------


static func _spawn(
	encounter: LootEncounterDef, tier: LootTier, tier_index: int, run: int, boss_index: int
) -> Dictionary:
	var boss_id := encounter.boss_ids[boss_index]
	var vitality := tier.vitality_for(boss_id)
	var profile := boss_profile(boss_id)
	return {
		"encounter_def": String(encounter.id),
		"domain_id": String(encounter.domain_id),
		"tier": tier_index,
		"tier_label": String(tier.label),
		"tier_realm": String(tier.realm),
		"tier_rarity": String(tier.rarity),
		"run": run,
		"boss_index": boss_index,
		"boss_id": String(boss_id),
		"encounter_id": encounter_id(String(encounter.domain_id), String(boss_id), tier_index, run),
		"vitality": vitality,
		"vitality_max": vitality,
		# The fight's own numbers are frozen with the boss (ADR 0076), not re-derived on
		# every exchange: a resumed fight is the fight the band priced, and a retuned
		# content file cannot change the terms of a run already in flight.
		"attack": tier.attack_for(boss_id),
		"defense": tier.defense_for(boss_id),
		# ...and so is the boss's own striking profile, for the same reason. Without it the
		# boss answered every blow through one hardcoded zero-profile that no content could
		# move (BL-0224): it never critted, never pierced, never slipped a blow and never
		# softened one, so no boss could ACT differently from any other.
		"crit_chance": profile["crit_chance"],
		"crit_damage": profile["crit_damage"],
		"penetration": profile["penetration"],
		"evasion": profile["evasion"],
		"damage_reduction": profile["damage_reduction"],
		# ...and so is the status it afflicts on the player, for the same reason. A boss
		# whose creature is fire-blown changes nothing about the terms of a run already in
		# flight, and a resumed fight must not be re-priced by a content edit either. Frozen
		# with everything else it goes through `active_view`, so the combat module reads it
		# through this module's facade like every other number about the boss.
		"affliction": boss_affliction(boss_id),
		"defeated": false,
	}


## The `StatusDef.id` a spawned boss afflicts on the player, or `""` when it names none.
##
## Read off the boss's authored record and no further: a boss nobody authored an
## affliction for inflicts nothing, which is the behaviour every boss had before the field
## existed. Whether the id names a real, COMBAT-scope def is NOT decided here — that is
## `LootAffliction`'s refusal to report, so this module keeps holding an authored string
## and `status` keeps owning whether it means anything.
static func boss_affliction(boss_id: StringName) -> String:
	return String(LootContent.instance().boss_record(boss_id).get("affliction", ""))


## The striking profile a spawned boss fights with: the authored numbers off its
## `BossDef`, defaulted to the inert profile for a boss nobody authored one for.
##
## `crit_damage` is a **multiplier**, not a probability, so it is only held non-negative;
## the other four are bounded fractions. `CombatDamage` clamps all five again at the point
## of use, so this is about the profile a reader is *shown* being honest rather than about
## the arithmetic being safe.
static func boss_profile(boss_id: StringName) -> Dictionary:
	var authored := LootContent.instance().boss_record(boss_id).get("profile", {}) as Dictionary
	return {
		"crit_chance": clampf(float(authored.get("crit_chance", 0.0)), 0.0, 1.0),
		"crit_damage": maxf(0.0, float(authored.get("crit_damage", 1.0))),
		"penetration": maxf(0.0, float(authored.get("penetration", 0.0))),
		"evasion": clampf(float(authored.get("evasion", 0.0)), 0.0, 1.0),
		"damage_reduction": clampf(float(authored.get("damage_reduction", 0.0)), 0.0, 1.0),
	}


## Rule E3: the next boss spawns on defeat. When the run is done it clears and
## records the cleared band, which is what rule E2 then refuses to re-grant.
static func _advance(state: Dictionary) -> void:
	var active: Dictionary = state.get("active", {})
	if active.is_empty():
		return
	var domain_id := String(active.get("domain_id", ""))
	var tier_index := int(active.get("tier", 0))
	var run := int(active.get("run", 0))
	var encounter := LootContent.instance().encounter_by_id(
		StringName(active.get("encounter_def", ""))
	)
	if encounter == null:
		state["active"] = {}
		return
	var next := _first_undefeated_from(
		state, encounter, tier_index, run, int(active.get("boss_index", 0)) + 1
	)
	if next < 0:
		_clear(state, domain_id, tier_index)
		return
	state["active"] = _spawn(encounter, encounter.tier_at(tier_index), tier_index, run, next)


## Mark one band cleared. The run number is left exactly as `enter` wrote it: this is
## the outcome of that run, not a new one.
static func _clear(state: Dictionary, domain_id: String, tier_index: int) -> void:
	var runs: Dictionary = state["runs"]
	var band := run_key(domain_id, tier_index)
	var record: Dictionary = runs.get(band, {})
	record["cleared"] = true
	runs[band] = record
	state["runs"] = runs
	state["active"] = {}


## First boss index at or after `from_index` with no reward and no spent claim.
static func _first_undefeated_from(
	state: Dictionary, encounter: LootEncounterDef, tier_index: int, run: int, from_index: int
) -> int:
	for index in range(maxi(0, from_index), encounter.boss_ids.size()):
		var id := encounter_id(
			String(encounter.domain_id), String(encounter.boss_ids[index]), tier_index, run
		)
		if not has_reward(state, id) and not is_spent(state, id):
			return index
	return -1


static func _first_undefeated(
	state: Dictionary, encounter: LootEncounterDef, tier_index: int, run: int
) -> int:
	return _first_undefeated_from(state, encounter, tier_index, run, 0)


## Whether a run at this tier is already in flight, i.e. it was entered and left
## again before clearing. Rule E4 resumes it instead of granting a new one.
static func _run_in_flight(
	state: Dictionary, encounter: LootEncounterDef, tier_index: int, run: int
) -> bool:
	return _first_undefeated(state, encounter, tier_index, run) >= 0


## A per-encounter stream seeded from the caller's seed and the encounter id, so
## one boss defeat is reproducible from (seed, encounter) alone.
static func _encounter_seed(seed_value: int, encounter: String) -> int:
	var mixed := absi(hash(encounter))
	return (seed_value * 2654435761 + mixed) & 0x7FFFFFFF


static func _drop_index(drops: Array, drop_id: String) -> int:
	for index in drops.size():
		if String((drops[index] as Dictionary).get("drop_id", "")) == drop_id:
			return index
	return -1


static func _stash_index(stashes: Array, stash_id: String) -> int:
	for index in stashes.size():
		if String((stashes[index] as Dictionary).get("stash_id", "")) == stash_id:
			return index
	return -1


## When every drop is claimed and none is stashed the encounter's claim is spent:
## the payload moves to the claim ledger so nothing can ever address it again.
static func _settle(state: Dictionary, encounter: String, payload: Dictionary) -> void:
	var drops: Array = payload.get("drops", [])
	for drop in drops:
		if not bool((drop as Dictionary).get("claimed", false)):
			return
	var rewards: Dictionary = state["rewards"]
	rewards.erase(encounter)
	state["rewards"] = rewards
	var claims: Dictionary = state["claimed"]
	claims[encounter] = {
		"drops": drops.size(),
		"tier": int(payload.get("tier", 0)),
		"table_id": String(payload.get("table_id", "")),
	}
	state["claimed"] = claims
	var stashes: Array = state["world_drops"]
	state["world_drops"] = stashes.filter(
		func(entry: Dictionary) -> bool: return String(entry.get("encounter_id", "")) != encounter
	)
