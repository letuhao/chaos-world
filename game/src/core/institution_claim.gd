class_name InstitutionClaim
extends Resource

## The one vocabulary every institution speaks: a position, a standing and an
## open ledger of obligations (ADR 0083).
##
## ## Why this is a Resource in `core/` and not in `contracts/`
##
## It has to be an `@export` field on `SectDef` and `NationDef`, which are
## authored `.tres` files, and Godot cannot `@export` a `RefCounted`. That leaves
## a Resource, and `RESOURCE_HOME_UNITS = ("core", "modules")` is where one
## belongs — the detector in `tools/arch/enforce.py` warns about a Resource in
## `contracts/` because an authored content type filed as a contract is how a
## save schema grows without a module ever owning it.
##
## `core` is a LAYER rather than a module, so the cross-module facade rule never
## applied to it and holding shared foundation data here creates zero new edges.
## All of `clan`, `sect` and `nation` already declare `core`. The precedent is
## `RealmRate`: one curve in core, shared by all three cultivation paths, which
## exists precisely because the old per-path copies each had to be kept in sync
## by hand (ADR 0066).
##
## ## The two halves never derive from each other
##
## `position` is discrete and authored, from a `position_id`. `standing` is a
## continuous earned integer that can fall. ADR 0064 made this a two-part split
## for a clan and it is carried forward unchanged: a member may hold a high
## position on thin standing, and may hold thick standing in no position at all.
## That gap is the whole politics layer. A design that collapses the two into one
## number has built a spreadsheet, so **nothing here may derive one from the
## other** and a test asserts that a promotion does not move standing.
##
## ## Standing is earned and can fall, but never goes negative
##
## It is clamped at zero rather than allowed to run down: an institution that
## has been wronged is one that has lost something, and a member with nothing
## left has nothing to lose, which is the property that makes a demotion a real
## cost. Standing is projected as a bounded PERCENT (ADR 0084) and is never a
## FLAT grant, never a base-attribute write, and never a second stat composer.

## The fraction of the cap one point of standing is worth, and the ceiling that
## stops it (ADR 0084). Both are authored here and nowhere else: `core` is a
## layer, not a module, so the cross-module facade rule never applied to it and
## there is no second copy to keep in sync — which is the whole reason this
## formula lives here rather than in a module (the ADR 0066 failure mode).
const STANDING_RATE := 0.001
## The maximum recognition any claim can ever contribute, as a percent. At the
## authored cap of 100 standing that is `0.10`.
const STANDING_PERCENT_CAP := 0.10

## A position id, or `""` for an unaffiliated member. Discretely authored: this
## is a `.tres` id, never an index into a ladder.
@export var position: StringName = &""
## The continuous earned integer. Can fall, clamped at [0, standing_cap].
@export var standing: int = 0
## Open obligation lines keyed by `term_id`, each holding the count still owed.
## Ids and counts, never authored amounts, so retuning a rate never rewrites a
## save.
@export var obligation: Dictionary = {}
## The ceiling `standing` clamps to. Authored per institution, so the political
## range is content rather than a constant buried in a ledger.
@export var standing_cap: int = 100


## The bounded percent this standing projects onto an allowlisted stat
## (ADR 0084). One formula, here, so it cannot be restated per module.
##
## A PERCENT rides the member's own growth, so a claim is a real edge at its
## realm and exactly as strong at R5 as at R30. A FLAT would be decisive at R2 and
## noise by roughly realm 12 across the 551x ladder (ADR 0050), and a FLAT on a
## rate stat is the silent no-op ADR 0068 measured on 44 items.
##
## The cap is the point: the entire political stat surface of the game is bounded
## by construction, so no ladder of authored positions can sum into an uncapped
## multiplier.
static func standing_percent(standing: int) -> float:
	return minf(STANDING_PERCENT_CAP, STANDING_RATE * float(maxi(0, standing)))


## The percent `standing` contributes as a share of its own cap, in [0, 1]. The
## display and gating form: a panel renders a ratio rather than a balance.
func normalized() -> float:
	if standing_cap <= 0:
		return 0.0
	return clampf(float(standing) / float(standing_cap), 0.0, 1.0)


## Move standing by `delta` and clamp. Returns the applied amount, so a caller
## can publish how much of a requested change actually landed rather than
## assuming it did.
func move_standing(delta: int) -> int:
	var before := standing
	standing = clampi(standing + delta, 0, maxi(0, standing_cap))
	return standing - before


## Periods still owed against `term_id`. A read rather than a second dictionary
## lookup by every caller, so a gate asking "is this member still in debt?" and a
## panel rendering the same ledger cannot drift into answering differently. A line
## that was never opened owes nothing: zero is the answer, never an error, because
## "nobody opened this debt" and "this debt is settled" are the same state.
func owed(term_id: StringName) -> int:
	var key := String(term_id)
	if key == "":
		return 0
	return maxi(0, int(obligation.get(key, 0)))


## Record `periods` more periods owed against `term_id`.
func owe(term_id: StringName, periods: int) -> void:
	if term_id == &"" or periods <= 0:
		return
	obligation[String(term_id)] = int(obligation.get(String(term_id), 0)) + periods


## Settle up to `periods` against `term_id`. Returns how many were actually
## settled, so a caller can refuse to settle a line it has no ledger for instead
## of silently paying a debt it does not have.
func settle(term_id: StringName, periods: int) -> int:
	var key := String(term_id)
	if key == "" or periods <= 0 or not obligation.has(key):
		return 0
	var owed := int(obligation[key])
	if owed <= 0:
		return 0
	var settled := mini(owed, periods)
	obligation[key] = owed - settled
	return settled


## True when nothing is owed on any line. A treasury in this shape is a ledger
## of obligations, never a pile of items — the items module stays the only item
## authority.
func settled() -> bool:
	for key in obligation.keys():
		if int(obligation[key]) > 0:
			return false
	return true


## The JSON-safe payload a save carries. `String` keys throughout and no
## `StringName` anywhere: `Actor.to_dict` converts only the OUTER module_data
## key, so an inner `StringName` key would reach the save untouched and break
## every round trip. A `Resource`, an `Actor` or a `Vector2` in here does the
## same, and no checker in this repo can see it.
func to_dict() -> Dictionary:
	var lines: Dictionary = {}
	for key in obligation.keys():
		lines[String(key)] = int(obligation[key])
	return {
		"position": String(position),
		"standing": standing,
		"obligation": lines,
		"standing_cap": standing_cap,
	}


## Restore from `to_dict`. Every field is coerced on the way in, and a
## `standing_cap` of zero or less is repaired rather than persisted, because a
## claim whose cap cannot be computed would report a normalized ratio of zero and
## read as a member nobody respects.
static func from_dict(data: Dictionary) -> InstitutionClaim:
	var claim := InstitutionClaim.new()
	claim.position = StringName(data.get("position", ""))
	claim.standing = maxi(0, int(data.get("standing", 0)))
	claim.standing_cap = maxi(1, int(data.get("standing_cap", 100)))
	var lines = data.get("obligation", {})
	if lines is Dictionary:
		for key in (lines as Dictionary).keys():
			var owed := int((lines as Dictionary)[key])
			if owed > 0:
				claim.obligation[String(key)] = owed
	return claim
