class_name SocialFavourApp
extends RefCounted

## The player-facing VERBS, and the only place `npc`, `techniques` and `combat` are
## allowed to meet `social`'s personal-cause component (ADR 0091's mirror defect).
##
## ## Why this is in `app/` and not on a facade
##
## `SocialApi` is at twelve public methods and `rules.MAX_FACADE_PUBLIC_METHODS` caps it at
## twelve, so **it may not grow a thirteenth** — `tools arch` fails the build on it. Worse,
## every verb here needs collaborators `social` may not name: an npc id has to become an
## `Actor` through `NpcApi.resident`, a manual has to become a `TechniqueDef` through
## `techniques`' own catalog, and a mercy has to be checked through `CombatMercy`. `social`
## declares `["contracts", "core"]` and may reach no sibling by name at all. So the only
## legal home is the layer exempt from the graph — `LAYER_DEPS["app"] == "*"`.
##
## This is the `BrotherhoodOathApp` shape exactly, and for the same reasons: a plain
## `RefCounted` in `app/` that reaches its collaborators through facades, holds no state of
## its own, and is drivable by a headless test with no scene tree.
##
## ## What it adds over the component, and why
##
## Only two things, both translation a player-facing caller needs:
## 1. **An npc id instead of an `Actor`.** A panel holds `&"elder_wei"`, not a body.
##    Resolution goes through `NpcApi.resident`, the off-stage mechanism ADR 0074 provides,
##    and refuses `unknown_npc` when this process holds none.
## 2. **The seam bindings.** `install` binds what `social` may not name, so a build that
##    never calls it answers `no_resolver` by name instead of silently degrading.

## Nobody to act towards, or to act as.
const R_NO_ACTOR := "no_actor"
## The id names nobody this process has met — the off-stage lookup found no body.
const R_UNKNOWN_NPC := "unknown_npc"


## Bind every seam `SocialFavour` may not resolve for itself, and report what bound.
##
## ## Every seam has a DEFAULT body, so `install()` needs no arguments at all
##
## That is deliberate and it is the whole reason "reachable in production" is a true claim
## rather than an aspiration. A verb behind four `Callable`s that a caller must construct is
## a verb nobody wires — the exact shape of the defect this change closes, one layer up.
## Each default below is a thin adapter over a facade `app/` may name; a caller that wants
## to substitute a double passes one, and a caller that passes none gets the real thing.
##
## **Idempotent, and a null Callable CLEARS a seam rather than half-binding it** — the
## `CombatMercy.install` discipline, so a teardown can uninstall deterministically instead
## of only overwriting. A build that never calls this at all still gets the key resolver
## and the mercy probe degraded to their unbound states by `SocialFavour` itself, and the
## verbs that need them refuse `no_resolver` **by name**.
static func install(
	key_resolver: Callable = Callable(),
	debt_reader: Callable = Callable(),
	mercy_probe: Callable = Callable(),
	teacher: Callable = Callable(),
) -> Dictionary:
	SocialFavour.install_key_resolver(
		key_resolver if _bound(key_resolver) else Callable(BrotherhoodOath, "bond_key")
	)
	SocialFavour.install_debt_reader(
		debt_reader if _bound(debt_reader) else Callable(SocialFavourApp, "owed_by")
	)
	SocialFavour.install_mercy_probe(
		mercy_probe if _bound(mercy_probe) else Callable(CombatMercy, "available")
	)
	SocialFavour.install_teacher(
		teacher if _bound(teacher) else Callable(SocialFavourApp, "teach_technique")
	)
	return SocialFavour.seams_installed()


## Uninstall every seam. Separate from `install(Callable())` for the same reason
## `TechniqueDelivery.clear` is: a suite that asserts the unbound behaviour needs to state
## "nothing bound" explicitly rather than passing a bare default and trusting it.
static func uninstall() -> void:
	SocialFavour.install_key_resolver(Callable())
	SocialFavour.install_debt_reader(Callable())
	SocialFavour.install_mercy_probe(Callable())
	SocialFavour.install_teacher(Callable())


static func _bound(candidate: Callable) -> bool:
	return not candidate.is_null() and candidate.is_valid()


## The live `Actor` `npc_id` names, or null when this process holds none.
##
## Published rather than left private so the verbs below and any sibling app verb resolve
## a partner through the SAME two-step resolution — `NpcApi.resident` for a roster id, then
## a scan of the ids this process minted for an ENGINE id. Both steps are load-bearing and
## the second one is why `KinshipApp` may not answer this question for itself: a second
## resolution would be a second thing to drift from the row the write path files.
static func partner_of(npc_id: StringName) -> Actor:
	return _partner(npc_id)


## Give `rows` — `{def_id, quantity}` primitives — to `npc_id`.
##
## `{ok, reason, cause, partner, standing_before, standing_after, partner_standing}`. A
## refusal names itself and **moves no goods** — the component checks every refusal before
## the transfer, which is ADR 0044's "a refused verb writes nothing".
static func give(player: Actor, npc_id: StringName, rows: Array) -> Dictionary:
	var partner := _partner(npc_id)
	if partner == null:
		return _refuse(player, R_UNKNOWN_NPC)
	return SocialFavour.give(player, partner, rows)


## Record that the player fought beside `npc_id`, or let them walk.
##
## `spared` is **verified, not trusted**: the component asks the bound mercy probe and
## refuses if there is no live opponent to spare. A caller cannot mint the larger cause by
## setting a flag.
static func fight_alongside(player: Actor, npc_id: StringName, spared: bool = false) -> Dictionary:
	var partner := _partner(npc_id)
	if partner == null:
		return _refuse(player, R_UNKNOWN_NPC)
	return SocialFavour.fight_alongside(player, partner, spared)


## Settle the debt `npc_id` is owed under `debt_id`.
##
## The debt is read from the partner's own roster tally, so the caller cannot assert one
## into existence — a refusal here is `no_debt`, and it is the partner's answer rather than
## the caller's claim.
static func settle_debt(
	player: Actor, npc_id: StringName, debt_id: StringName = &"debt"
) -> Dictionary:
	var partner := _partner(npc_id)
	if partner == null:
		return _refuse(player, R_UNKNOWN_NPC)
	return SocialFavour.settle_debt(player, partner, debt_id)


## Teach `npc_id` the technique the player carries the manual for.
##
## `rng` is threaded to the learner's own `TechniquesApi.learn`, where it is a SEED SOURCE;
## `null` takes the engine's entropy, exactly as production does. **No `randf()` appears in
## any path here**, so a headless suite reproduces an outcome by seeding.
static func teach(
	player: Actor,
	npc_id: StringName,
	manual_id: StringName,
	rng: RandomNumberGenerator = null,
) -> Dictionary:
	var partner := _partner(npc_id)
	if partner == null:
		return _refuse(player, R_UNKNOWN_NPC)
	return SocialFavour.teach(player, partner, manual_id, rng)


## The read model a screen polls before it offers the affordance: `{ok, reason, partner,
## standing, class, label, causes}`. A refusal names itself rather than returning an empty
## row, so a panel greys the button out and prints why instead of letting the verb refuse
## at the press.
static func read(player: Actor, npc_id: StringName) -> Dictionary:
	var partner := _partner(npc_id)
	if partner == null:
		return {
			"ok": false,
			"reason": R_UNKNOWN_NPC,
			"partner": String(npc_id),
			"standing": 0.0,
			"class": "",
			"label": "",
			"causes": [],
		}
	return SocialFavour.read(player, partner)


## Every cause id these verbs can apply, sorted. Republished from the component so a content
## audit reads the wired vocabulary from ONE place, and `tests/modules/social/
## test_social_personal_causes.gd` pins every entry against the shipped catalog — a bridge
## built on an unauthored id fails at test time rather than refusing silently at play time.
static func cause_ids() -> Array[StringName]:
	return SocialFavour.cause_ids()


## The live `Actor` for `npc_id`, or null when this process holds none.
##
## **Off-stage bodies are subjects too.** `NpcApi.resident` is ADR 0074's whole mechanism:
## an individual the player has met but who is not in the room costs one dictionary rather
## than a live actor, so a panel can offer "give" against somebody who has walked away
## instead of refusing `unknown_npc` for someone plainly known.
##
## ## ## An id this process MINTED resolves too, and this is load-bearing
##
## `NpcApi.resident` scans `NpcRegistry`'s INSTANCE keys — `elder_wei#1` — by prefix, so
## it answers for `elder_wei` and refuses `npc_elder_wei`. That refusal was correct for
## every id a panel holds, and wrong for one caller: `Seduction.can_meet` asks its gate
## for `String(partner.id)`, the ENGINE id, so `Seduction` is a reader of the actor-keyed
## row `_settle` writes beside the def-keyed one. With only the roster lookup, that row
## existed, was correct, and could not be read by the one producer whose gate it was
## written to open — the same invisible-row defect the alias was added to fix, reopened on
## the read side.
##
## **So an id that is not a roster id is tried against the ids this process minted**,
## and an exact match on a live body wins. The scan is over `NpcLedger`-free territory:
## it reads `NpcRegistry`, which `app/` may name, and the predicate is the same one
## `BrotherhoodOath.bond_key` walks in the other direction — the two agree on which
## `Actor` an id names, so a caller can write through one id and read through the other
## and land on the same body rather than on `unknown_npc`.
static func _partner(npc_id: StringName) -> Actor:
	if npc_id == &"":
		return null
	var resident := NpcApi.resident(npc_id)
	if resident != null:
		return resident
	return _minted(npc_id)


## The live body whose ENGINE id is exactly `actor_id`, or null. Bounded by the live
## registry, which is bounded by the room, so this cannot grow with a session.
static func _minted(actor_id: StringName) -> Actor:
	var registry := NpcRegistry.instance()
	for key in registry.present_ids():
		var live := registry.present(key)
		if live != null and live.id == actor_id:
			return live
	return null


static func _refuse(player: Actor, reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"cause": "",
		"partner": String(""),
		"standing_before": 0.0,
		"standing_after": 0.0,
		"partner_standing": 0.0,
		"detail": {},
		"player_id": "" if player == null else String(player.id),
	}


## The default seam bodies, so `install` needs no caller wiring at all.
##
## A player-driven verb with four `Callable`s to hand-build is a verb nobody wires, and
## "wired in production" is the entire claim this change makes. Each body is a thin
## adapter over a facade `app/` may name, and each is DEFAULTED rather than required — so a
## suite that installs nothing still gets the real resolution, and the seams stay seams for
## the one collaborator (`techniques`) that needs a def object rather than an id.


## What `npc_id` is owed under `debt_id`: `NpcApi.summary(npc_id)["tally"]`, the partner's
## own record of what they have been given, which is what "owed" means. `0` for an id the
## roster does not carry — and `0` is the refusal, so an unknown id settles nothing.
static func owed_by(npc_id: StringName, debt_id: StringName) -> int:
	var summary := NpcApi.summary(npc_id)
	var tally: Dictionary = summary.get("tally", {}) as Dictionary
	return int(tally.get(String(debt_id), 0))


## `BrotherhoodOath.bond_key`: the def id an npc's ledger is keyed under, resolved through
## `NpcRegistry`'s prefix scan. `social` may not name `npc`, so the resolution is bound.
static func default_key_resolver() -> Callable:
	return Callable(BrotherhoodOath, "bond_key")


## `CombatMercy.available`: is there somebody a mercy could honestly be shown to right now.
static func default_mercy_probe() -> Callable:
	return Callable(CombatMercy, "available")


## The learn a teaching verb calls: resolve the manual through `techniques`' own catalog and
## hand the def to `TechniquesApi.learn`.
##
## **The manual → technique link is the AUTHORED `delivered_by` field**, not an id rule:
## `TechniqueDelivery.study` documents at length that an identity between two independently
## authored vocabularies is not a contract anyone reviewed, and an id no def claims still
## resolves to nothing and is still refused `unknown_technique` by name.
static func teach_technique(
	learner: Actor, manual_id: StringName, _rng: RandomNumberGenerator = null
) -> Dictionary:
	var def := TechniqueCatalog.instance().delivers(manual_id)
	if def == null:
		return {"ok": false, "reason": "unknown_technique", "id": String(manual_id)}
	return TechniqueDelivery.bind_learner(learner, def.id, 0)
