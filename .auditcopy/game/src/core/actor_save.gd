class_name ActorSave
extends RefCounted

## One actor's save payload, and the world-slot stamp that travels beside it.
##
## ## Why this is not code in `actor.gd`
##
## `core/` is the shared stat/actor foundation every module names, so its public surface is
## load-bearing and the twenty-method cap in `gdlintrc` is a real constraint rather than a
## taste. Two members of it were never about the ACTOR: what a save carries, and which
## world slot this body's save was written at. Neither is identity, stats, resources,
## statuses or paths — the foundation `core/` is named for — and both are pure data with
## one writer each. This is the same split [StatusRegistry] already makes for statuses and
## [StatsInvalidator] for the caches: the actor keeps the field, and the rule about the
## field lives beside it so there is exactly one place to change it.
##
## ## It is a DELEGATE, never a subclass, and the edge is ONE-WAY
##
## `Actor` has no subclass in this repo — `tests/modules/domain/test_domain_spawner.gd`
## asserts there is none — so nothing inherits a member this file moved. The helpers here
## read and write the actor's PUBLIC fields and never ask the actor for anything private,
## so `Actor` -> `ActorSave` is the only edge in the pair. Never the reverse: a mutual
## class reference is what breaks compilation.
##
## ## ## What this file deliberately does NOT own
##
## `to_dict` / `from_dict` stayed on `Actor`. Both are named in `docs/adr/0028`,
## `docs/adr/0027` and `docs/world/player-adapter-design.md` as the actor's own round trip,
## both are `static`, and both are read by name in more than a hundred suites — moving the
## implementation is a refactor worth doing on its own merits, not as a side effect of
## clearing a method cap. What moved here is the STAMP, which is a separate fact about the
## world rather than about the body.

## ## v6's one addition: the save's HANDOFF of the world polity ledger (DEF-0119)
##
## The world-scoped ledger itself is NOT here — it rides `envelope.world.polity`, beside
## the actor, for the reason ADR 0083 gives: an obligation between two institutions is true
## of no actor, so a copy under `module_data` would be one copy per actor and the second
## body could contradict the first. What this slot carries is the **stamp**: the save
## version at which that world slot was written, so a save can be TOLD which world its
## actor expects rather than assuming one.
##
## ## Why the slot exists at all, since the world carries the ledger
##
## Two reasons, and both are migration rather than transport:
##
## 1. **An old save is not silently the same save.** A payload with no v6 slot was written
##    by a build that had no world polity ledger; one written with it was. `WorldLedgerMigrate`
##    reads this stamp to decide whether a `polity` key it finds is one this build's
##    migration understands or a foreign body's opinion of the world.
## 2. **The gate is ADDITIVE and TOTAL, exactly as ADR 0037's attempt slot is.** A v5 or
##    older payload carries no stamp and loads with **no** stamp — not a default that
##    asserts this save predates the world slot, and not a zero that a caller could read as
##    "written at generation zero". An absent key is the honest "this build did not write
##    one", and `Actor._restore_versioned` states it rather than manufacturing it.
##
## ## ## An INTEGER, never a nested world ledger
##
## A payload here is JSON-safe by construction and cannot carry an `Actor`, a `Resource`
## or a `StringName` key — the three things `WorldFact` and `InstitutionClaim` both name as
## invisible-save-breakers. The world ledger's whole shape lives in
## `core/world_polity_ledger.gd`, and this slot is the only thing about it on the actor.

## The world-slot stamp, as a key in `actor.module_data`. Restated here by NAME rather than
## read through `Actor`, for the one-way-edge reason above; `Actor.POLITY_SLOT_KEY` is the
## published spelling and the two are asserted equal by `tests/core/test_world_polity_ledger.gd`.
const POLITY_SLOT_KEY := &"world_polity_version"


## The world-slot stamp this actor carries, or -1 when it carries none. -1 rather than
## zero because zero is a legal stamp and a caller comparing two stamps must be able to
## tell "generation zero" from "never told".
static func polity_version(actor: Actor) -> int:
	if actor == null:
		return -1
	# The stamp rides `module_data` as a BARE INT, which is what
	# `Actor._restore_versioned` copies back and what `Actor.to_dict` writes, so the read
	# here takes the int directly: `module_data[POLITY_SLOT_KEY]` is absent on an unstamped
	# body and `null` on a malformed one, and both answer -1.
	var stamped: Variant = actor.module_data.get(POLITY_SLOT_KEY)
	return int(stamped) if (stamped is int) and int(stamped) >= 0 else -1


## Record the world-slot stamp this actor's save was written at. The only writer, so no
## second caller can invent a stamp the world slot does not carry.
##
## The stamp is a BARE INT in `module_data`, which is what [method polity_version] reads,
## what `Actor.to_dict` copies into `module_data` and what `Actor._restore_versioned`
## restores: an earlier Dictionary-wrapped spelling disagreed with all three of them on
## every round trip, so this wrote a slot nothing ever read.
static func set_polity_version(actor: Actor, version: int) -> void:
	if actor == null or version < 0:
		return
	actor.module_data[POLITY_SLOT_KEY] = version
