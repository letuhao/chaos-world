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

## The largest stamp the reader will accept. JSON is arbitrary-precision on the way in,
## so without a ceiling a save could ask for a version number beyond anything this build
## could ever have written and have it read back as a legitimate stamp. Every real stamp
## is a small schema version; this is the corrupt-save guard, not a budget.
const MAX_STAMP := 1_000_000_000


## The world-slot stamp this actor carries, or -1 when it carries none. -1 rather than
## zero because zero is a legal stamp and a caller comparing two stamps must be able to
## tell "generation zero" from "never told".
static func polity_version(actor: Actor) -> int:
	if actor == null:
		return -1
	return stamp_of(actor.module_data.get(POLITY_SLOT_KEY))


## The ONE rule that decides what a `world_polity_version` slot means, shared by the
## writer, the reader and the accessor, so the three can never disagree about a shape
## again — which is what the regression was.
##
## ## What is CANONICAL: a bare, non-negative INTEGER under the slot key
##
## Not the `{"version": N}` Dictionary. Three reasons, and they are independent of the
## bug: (1) `module_data` is a `Dictionary` whose every OTHER slot is a Dictionary, and
## `Actor.get_module_data` is typed `-> Dictionary` and answers `{}` for anything else —
## so an int under a module key is already the single exception in the whole map, and it
## is a deliberate one that only the stamp's own code touches (it never goes through
## `get_module_data`). (2) `set_module_data` is typed `(id, data: Dictionary)`, so a
## Dictionary slot would route the stamp through the generic module path and be picked
## up, warned about and restored by the `from_dict` loop rather than by this file —
## which is precisely the disagreement being fixed. (3) ADR 0037's rule for the sibling
## attempt/wounds slots is that a slot is excluded from the generic loop and restored by
## its own versioned branch; a bare int is what keeps the stamp on that path, and
## ADR 0083 §"disclosed gap" makes the actor-side value a *stamp*, never a ledger copy.
##
## ## Why a FLOAT is accepted, and why that is a shape fact and not a fudge
##
## JSON has one number type. `to_dict` writes the int `1`, but a file-backed save goes
## through `JSON.stringify`/`JSON.parse_string`, which has no integer type to come back
## to, so the stamp that arrives from disk is the float `1.0`. Measured, not assumed:
## `test_the_json_hop_returns_the_stamp_as_a_float_and_it_is_still_read` asserts the
## parsed value `is float` before asserting the version survives. A file-backed save and
## an in-memory save would otherwise disagree about the same stamp.
##
## The tolerance is EXACT-INTEGRALITY, not rounding: `1.0` is the int `1` and is
## accepted, `4.5` is refused. That keeps the refusal the untrusted-save rule needs —
## a string, a nested array, a negative, or a fractional number all read -1 — while
## admitting the one float a faithful JSON round trip can produce.
static func stamp_of(slot: Variant) -> int:
	if slot is int:
		return int(slot) if int(slot) >= 0 else -1
	if slot is float:
		var value := float(slot)
		# `is_finite` first: `inf`/`nan` truncate to an int that would look like a
		# perfectly good stamp, and a save must not be able to smuggle one in.
		if is_finite(value) and value >= 0.0 and value == floor(value) and value <= MAX_STAMP:
			return int(value)
		return -1
	return -1


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
