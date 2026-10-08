class_name SectState
extends RefCounted

## The versioned sect ledger, stored as a plain dictionary under
## `actor.module_data["sect_state"]` (ADR 0027 pattern). Core persists it without
## ever naming a sect type.
##
## ## What this ledger is
##
## One member's relationship to one institution: which sect they are sworn to,
## which position they hold in it, what standing the sect has given them, and
## what they still owe. It is deliberately **not** the sect itself — a sect
## outlives any one member, and a roster of members is not this ledger. ADR 0083
## records where a polity-wide ledger lives as an open question; this one is
## scoped so that question can be answered later without a migration.
##
## ## What a FOUNDING member's ledger additionally carries
##
## Four keys belong to the founder's slice rather than to an ordinary membership,
## and all four are empty for anybody who joined:
##
##   - `founder_id` — a plain actor id string. **Never an `Actor`**: one would reach
##     the save untouched and no checker here can see it.
##   - `roster` — the member list, by office id. This is the first slice's answer to
##     ADR 0083's open question, and it is deliberately the smallest one: the ledger
##     a founder writes is the only roster that exists, so an ordinary member's
##     ledger holds none and every capacity count below reads against the founder.
##   - `treasury` — obligation lines keyed by id (BL-0191). **Never a pile of
##     items**: a treasury that duplicated the `items` module's inventory would be
##     two sources of truth for what an institution owns.
##   - `succession` — the walk in progress, by office id (BL-0181). Held as a COUNT
##     of stages plus the vacancy it is walking out of, so a corrupt save cannot
##     hand this module an index to read or a length to iterate.
##
## ## The position and the standing never derive from each other
##
## ADR 0064's two-part split, carried forward unchanged: `position` is discrete
## and authored, `standing` is continuous and earned. A promotion writes the
## position and leaves the standing alone; a standing change moves the standing
## and leaves the position alone. `normalize` is where that separation is
## mechanical — it reads each field from its own key and never writes one from
## the other.
##
## ## Normalization is where a corrupt save is refused
##
## Four rules, and the third is the one that earns its cost:
##
## 1. An empty payload returns the full default skeleton immediately, never a
##    partial one.
## 2. **A payload that cannot be read is diagnosed as empty, never partially
##    applied.** Half a ledger is worse than none, because a partial one silently
##    changes what the player is owed.
## 3. An entry naming content the catalog no longer ships is dropped, so a save
##    from a wider content build cannot smuggle in a sect the current build does
##    not define.
## 4. Every field is type-coerced on the way in, so a corrupt save cannot inject
##    a wrong type into the projection.

const SCHEMA_VERSION := 1
## `actor.module_data` key.
const MODULE_KEY := &"sect_state"
## The history trail is a bounded explanation of how the member got here, not a
## full audit log. A save cannot grow without limit.
const HISTORY_LIMIT := 64
## Every stat modifier this module contributes is tagged with this prefix, so a
## re-projection can strip and rebuild the whole contribution from the ledger.
const SOURCE_PREFIX := "sect:"
## The actor id stored as the founder. This is a string, never an `Actor`
## reference: an `Actor` in a ledger reaches the save untouched and no checker
## in this repo can see it.
const FOUNDER_KEY := "founder_id"
## The ceiling on fit, in points. Fit is transmission, not a stat: it gates who
## may be taught and projects no modifier at all (ADR 0084). The cap is what
## makes it a gate rather than a currency — a currency that accumulates is a
## thing to buy comprehension with, and comprehension is the one thing this repo
## says cannot be bought.
const FIT_CAP := 100
## A standing value a member is REFUNDED by founding their own sect: they paid for
## it, so charging them again would make the price of existing an infinite regress.
## Not a percent and not a multiplier — a floor would make founding a demotion and
## a multiple would make it a grant, and ADR 0064's split says neither.
const FOUNDER_REFUND_STANDING := 100
## A bound on the roster this ledger holds. Not a capacity — the authored cap lives
## on each `SectPositionDef` and a refusal must name the office it came from. This
## only stops a hand-written save asking for a list of two million ids.
const ROSTER_LIMIT := 64
## The hard ceiling on `succession["stages_walked"]`, so a corrupt save cannot ask
## the walk for more stages than the longest authored walk has. The walk itself is
## still clamped again against `SectPositionDef.walk_length()`.
const STAGE_LIMIT := 8
## A bound on the schisms this ledger records. One line per declared split, and a
## declaration is a political event rather than a per-period accrual, so this is a
## hand-edited-save guard rather than a real budget — the same job `ROSTER_LIMIT`
## does, for the same reason.
const SCHISM_LIMIT := 32


## The stat source id one sect contributes under. A delegate: the construction
## is shared and the namespace is not — `InstitutionLedger.source_tagged` takes
## the prefix as an argument precisely so a `sect:` modifier can never satisfy a
## clan strip half, which is the bug the prefix exists to prevent.
static func source_for(sect_id: StringName) -> StringName:
	return InstitutionLedger.source_tagged(SOURCE_PREFIX, sect_id)


## True when a stat modifier source belongs to this module. A delegate for the
## same reason: the shape is shared, the namespace is the caller's.
static func is_own_source(source: StringName) -> bool:
	return InstitutionLedger.owns_source(SOURCE_PREFIX, source)


## The `Actor.traits` mirror id one sect membership is reflected under.
##
## The mirror carries membership, never strength: a member who has earned no
## standing is still sworn to something, and a gate asking "is this actor in a
## sect" reads the mirror rather than a stat for exactly that reason — a stat can
## be satisfied by an item, and an institution must never be bought past (ADR
## 0076's rule, applied here).
static func trait_for(sect_id: StringName) -> StringName:
	return InstitutionLedger.source_tagged(SOURCE_PREFIX, sect_id)


## True when a trait mirror id belongs to this module. A delegate: the trait
## mirror and the stat source share one namespace (`sect:<sect_id>`), so one
## shared read answers for both carriers.
static func is_own_trait(trait_id: StringName) -> bool:
	return InstitutionLedger.owns_source(SOURCE_PREFIX, trait_id)


## The office the claim names, or `&""` for a member who holds none. **A member
## with thick standing may hold no position at all**, and that gap is the whole
## politics layer (ADR 0064 carried forward through ADR 0083) — so this is a
## read, never an inference from standing.
static func position(ledger: Dictionary) -> StringName:
	return StringName(ledger.get("position", ""))


## The standing the claim carries, clamped into its own authored cap.
static func standing(ledger: Dictionary) -> int:
	var cap := maxi(1, int(ledger.get("standing_cap", 100)))
	return clampi(int(ledger.get("standing", 0)), 0, cap)


## The claim as an `InstitutionClaim`. One vocabulary, constructed here rather
## than in a second shape: `clan`, `sect` and `nation` all speak it, and a
## divergent copy is the ADR 0066 failure mode in a new place.
static func claim(ledger: Dictionary) -> InstitutionClaim:
	return InstitutionClaim.from_dict(ledger)


## The empty ledger.
static func empty() -> Dictionary:
	return normalize({})


## True when this ledger names a sect at all. A member who has never sworn to
## anything has an empty institution id, which is the normal starting state
## (ADR 0083) rather than a failure.
static func is_affiliated(ledger: Dictionary) -> bool:
	return _sect_id(ledger) != &""


## The sect id, or `""` for an unaffiliated member.
static func institution(ledger: Dictionary) -> StringName:
	return _sect_id(ledger)


## The actor id that founded this ledger's sect, as a plain `String` id — never an
## `Actor` (see `FOUNDER_KEY`). `""` is ADR 0083's first state: "no institution
## here", which is a founderless sect rather than a sect whose founder is zero.
static func founder(ledger: Dictionary) -> String:
	return _text(ledger.get(FOUNDER_KEY, ""), "")


## The fit this member carries for `doctrine_id`, clamped into `[0, FIT_CAP]`.
##
## A plain integer off the ledger and never a derived stat: fit is **transmission**
## and transmission is a gate, not a value a member could be handed by an item
## (ADR 0084, ADR 0076's "a gate that reads a stat is a gate the player can buy").
static func fit(ledger: Dictionary, doctrine_id: StringName) -> int:
	if doctrine_id == &"":
		return 0
	var fit_map = ledger.get("fit", {})
	if not (fit_map is Dictionary):
		return 0
	return clampi(int((fit_map as Dictionary).get(String(doctrine_id), 0)), 0, FIT_CAP)


## The roster of this ledger's sect: plain actor ids, indexed by office id. Empty
## for a member who joined rather than founded — ADR 0083 records the member list
## as living on whoever wrote it, and this is the first slice's answer to that open
## question: the founding member's own ledger holds the roster, and `Actor.from_dict`
## carries it verbatim like any other module data.
static func roster(ledger: Dictionary) -> Dictionary:
	var rows = ledger.get("roster", {})
	return (rows as Dictionary) if rows is Dictionary else {}


## How many members this ledger's roster holds in `position_id`.
##
## **Counted from the roster, never passed in.** `SectDef.seat_state` was written to
## take a `held` count because the module held no roster, and an argument is a
## number a caller can be wrong about — so the verb that now knows the roster counts
## for itself and the argument became a stated maximum instead. An unbounded office
## (`capacity == 0`) is never full, which is the whole of what `0` means.
static func roster_held(
	ledger: Dictionary, position_id: StringName, office: SectPositionDef
) -> int:
	if office == null or position_id == &"" or office.capacity <= 0:
		return 0
	var row = roster(ledger).get(String(position_id), [])
	return (row as Array).size() if row is Array else 0


## The walk in progress on `position_id`, as `{side, stage, periods}`. `{}` when
## nothing is in progress — which is what a seat nobody has vacated looks like.
##
## `stage` is a **count** rather than a stage index on purpose. A corrupt save can
## hold a negative number or a million, and a walk driven by "the index of the
## current stage" turns either into an out-of-range index or a very long walk. A
## count clamped by `normalize` against `STAGE_LIMIT` is a number arithmetic can
## refuse; an index is not.
static func succession(ledger: Dictionary, position_id: StringName) -> Dictionary:
	if position_id == &"":
		return {}
	var entry = ledger.get("succession", {})
	if not (entry is Dictionary):
		return {}
	var row = (entry as Dictionary).get(String(position_id), {})
	return (row as Dictionary) if row is Dictionary else {}


## `position_id` is mid-walk. True when a walk has begun and has not finished,
## which is what `advance_succession` refuses to step a second time inside the same
## period.
static func succession_open(ledger: Dictionary, position_id: StringName) -> bool:
	var row := succession(ledger, position_id)
	return row.has("stage") and not bool(row.get("complete", false))


## Every declared split this ledger records, keyed by the SECT id the split
## produced. Read rather than re-derived, so `declare_schism`'s cost arithmetic and
## a panel rendering the same declaration cannot disagree about what happened.
##
## The map is a plain ledger of primitives — `String` keys, ints, one `String` id —
## because it round trips through `Actor.to_dict` like every other line here.
static func schisms(ledger: Dictionary) -> Dictionary:
	return (ledger.get("schisms", {}) as Dictionary).duplicate(true)


## The one declared split that produced `sect_id`, or `{}` when that sect is the
## product of no split in this ledger.
static func schism(ledger: Dictionary, sect_id: StringName) -> Dictionary:
	var entry = (ledger.get("schisms", {}) as Dictionary).get(String(sect_id), null)
	return (entry as Dictionary).duplicate(true) if entry is Dictionary else {}


## A known-content filter for this module. `known_positions` comes from the
## catalog and is keyed by position id; a claim naming a position the build does
## not ship is dropped rather than persisted.
##
## Every field is **coerced**, never coerced-and-guessed: an id arrives only when it
## really is one, and a wrong-typed container is refused whole rather than turned
## into a near miss. `String(...)` on a float or a dictionary raises at runtime, so
## a corrupt save that reached a raw cast could abort an attach instead of reading
## as empty — which is rule 2 above.
static func normalize(payload: Dictionary, known_positions: Dictionary = {}) -> Dictionary:
	var out := {
		"version": SCHEMA_VERSION,
		"institution": "",
		"position": "",
		"standing": 0,
		"standing_cap": 100,
		"obligation": {},
		"doctrine": "",
		"fit": {},
		"founder_id": "",
		"roster": {},
		"treasury": {},
		"succession": {},
		"schisms": {},
		"applied_standing": 0,
		"granted_percent": {},
		"history": [],
	}
	if payload.is_empty():
		return out
	if not (payload is Dictionary):
		return out
	var data := payload as Dictionary

	# ## Strict where the claim itself is unreadable, lenient where only a
	# ## neighbour is.
	#
	# `institution`, `position` and `standing` ARE the claim. A payload carrying
	# one of them as the wrong type is not a ledger with a bad field — it is not
	# a ledger, and coercing it would invent a membership and a standing out of
	# bytes. So a wrong-typed claim field rejects the whole payload and the member
	# reads as unaffiliated.
	#
	# The *maps* are a different case, and the difference is the whole point: an
	# unreadable `obligation`, `fit` or `granted_percent` is one unusable line
	# beside three good fields, so it drops that map and keeps the member's earned
	# standing. Losing standing because an unrelated line went bad is a worse
	# failure than losing the line. Both halves are asserted in
	# `tests/modules/sect/test_sect_persistence.gd`.
	if not _claim_fields_readable(data):
		return out

	# A position is content. When the catalog is non-empty, a claim naming a
	# position it does not define is an unaffiliated claim, not a claim with an
	# invented position. Standing survives regardless: a member who earned
	# standing did so even if the seat they held is no longer authored.
	var position := _text(data.get("position", ""), "")
	var position_known := (
		position == "" or known_positions.is_empty() or known_positions.has(position)
	)
	out["position"] = position if position_known else ""

	out["institution"] = _text(data.get("institution", ""), "")
	out["doctrine"] = _text(data.get("doctrine", ""), "")

	var cap := maxi(1, int(data.get("standing_cap", 100)))
	out["standing_cap"] = cap
	out["standing"] = clampi(int(data.get("standing", 0)), 0, cap)

	var obligation = data.get("obligation", {})
	if obligation is Dictionary:
		for term_id in (obligation as Dictionary).keys():
			var owed := int((obligation as Dictionary)[term_id])
			if owed > 0:
				out["obligation"][String(term_id)] = owed

	# Fit is a bounded integer per doctrine id. It is transmission, not
	# recognition, and projects no modifier at all (ADR 0084), so it is kept
	# apart from standing here rather than folded into it.
	var fit = data.get("fit", {})
	if fit is Dictionary:
		for doctrine_id in (fit as Dictionary).keys():
			var points := int((fit as Dictionary)[doctrine_id])
			if points > 0:
				out["fit"][String(doctrine_id)] = mini(points, FIT_CAP)

	# The founder is a plain actor id. `_text` rather than `String()` for the same
	# reason `institution` uses it: a corrupt save holding an object under this key
	# must not raise out of an attach.
	out[FOUNDER_KEY] = _text(data.get(FOUNDER_KEY, ""), "")

	# The roster, the treasury and the walk are each dropped whole if they arrive as
	# anything but a map — the same lenient-one-line rule the maps above follow. A
	# roster row for an office this build no longer authors is dropped, which is the
	# correct known-content filter: a row nobody can be promoted into is not a
	# membership. An empty filter is an unanswered question, never a denial, exactly
	# as it is for `position` above.
	var roster = data.get("roster", {})
	if roster is Dictionary:
		for position_id in (roster as Dictionary).keys():
			if not known_positions.is_empty() and not known_positions.has(String(position_id)):
				continue
			var row = (roster as Dictionary)[position_id]
			if not (row is Array):
				continue
			var ids: Array = []
			for member_id in row as Array:
				if ids.size() >= ROSTER_LIMIT:
					break
				var member := _text(member_id, "")
				if member != "" and not ids.has(member):
					ids.append(member)
			if not ids.is_empty():
				out["roster"][String(position_id)] = ids

	# The treasury is a ledger of obligation lines on ids, never a pile of items —
	# `items` stays the only authority on what an institution owns (BL-0191). Lines
	# are namespaced through the sect id, and a line belonging to some OTHER sect is
	# dropped rather than settled here: two sects share one actor's ledger and
	# neither may touch the other's dues.
	var treasury = data.get("treasury", {})
	if treasury is Dictionary:
		var prefix := "treasury_%s_" % String(out["institution"])
		for line_id in (treasury as Dictionary).keys():
			var key := String(line_id)
			var owed := int((treasury as Dictionary)[line_id])
			if owed > 0 and key.begins_with(prefix):
				out["treasury"][key] = owed

	# A walk, held as a COUNT of stages plus the vacancy the walk is walking out
	# of. `stage` is clamped here for the same reason `standing` is: a corrupt save
	# must not be able to ask for a walk of fifty thousand steps. `held_periods` is
	# what a second caller reads to be told "wait" rather than "the walk is gone".
	var succession = data.get("succession", {})
	if succession is Dictionary:
		for position_id in (succession as Dictionary).keys():
			var entry = (succession as Dictionary)[position_id]
			if not (entry is Dictionary):
				continue
			var row: Dictionary = entry as Dictionary
			out["succession"][String(position_id)] = {
				"side": _text(row.get("side", ""), ""),
				"stage": clampi(int(row.get("stage", 0)), 0, STAGE_LIMIT),
				"held_periods": maxi(0, int(row.get("held_periods", 0))),
				"complete": bool(row.get("complete", false)),
			}

	# A declared split, keyed by the SECT id it produced. **Not** filtered by the
	# catalog, for the reason `applied_standing` is not: a declaration is a
	# political fact that happened, and a `.tres` that has since been deleted does
	# not un-happen it. Dropping an unknown half would silently erase a split the
	# game is still playing out.
	out["schisms"] = _schism_rows(data.get("schisms", {}))

	# What the projection last applied. A `StatModifier` cannot lower a base
	# attribute and `remove_modifiers_from` only knows a source tag, so a rebuild
	# has to know what it previously added — this is `RaceState`'s `applied_race`
	# and `granted` pair, verbatim. Deliberately NOT filtered by the catalog: a
	# dropped definition still has to be subtracted, and losing a position is
	# exactly when it would otherwise be left behind.
	out["applied_standing"] = int(data.get("applied_standing", 0))
	var granted = data.get("granted_percent", {})
	if granted is Dictionary:
		for stat_id in (granted as Dictionary).keys():
			out["granted_percent"][String(stat_id)] = float((granted as Dictionary)[stat_id])

	var history = data.get("history", [])
	if history is Array:
		for record in history as Array:
			if record is Dictionary:
				out["history"].append((record as Dictionary).duplicate(true))
			if out["history"].size() >= HISTORY_LIMIT:
				break
	return out


# --- Internals -------------------------------------------------------------


## The sect id a ledger names, or `&""` when the key is missing or holds something
## that is not an id at all. A read has to be as defensive as `normalize`, because
## the two disagree is how a corrupt save reaches a gate: `normalize` coerces, this
## only accepts.
static func _sect_id(ledger: Dictionary) -> StringName:
	return StringName(_text(ledger.get("institution", ""), ""))


## `value` when it really is text (a `String` or a `StringName`), otherwise
## `fallback`. **A DELEGATE, and the copy that used to live here is deleted.**
##
## Three files carried this and the reasoning (`InstitutionLedger.text` owns it): a raw
## `String(...)` is not safe on a save payload, because it raises at runtime on a float
## or a dictionary, so a corrupt ledger would abort the attach rather than read as empty
## — the one thing a corrupt save is allowed to do. `ClanState._text` was a third copy
## and documents itself as "`sect_state.gd`'s `_text`, carried over unchanged", so the
## pair is now one rule read from two call sites rather than two rules that could drift.
## The call sites still read `_text` rather than the long class name because this is the
## hot path of every attach; what matters is that there is no body here to disagree.
static func _text(value: Variant, fallback: String) -> String:
	return InstitutionLedger.text(value, fallback)


## Whether `value` is genuinely text. A delegate, paired with `_text` which
## converts: `normalize` must tell a corrupt field from an absent one, and those
## are not repaired the same way. The same ASK/CONVERT pair `ClanState` holds,
## read from one place rather than written twice.
static func _is_text(value: Variant) -> bool:
	return InstitutionLedger.is_text(value)


## Whether the fields that ARE the claim arrive as the types they must be.
##
## An absent field is readable — a missing `position` is a member who holds no
## office, which is the normal state, not damage. A field present with the wrong
## type is not readable, and `normalize` rejects the whole payload rather than
## inventing a membership out of bytes.
##
## **Only the claim fields are checked.** The maps beside them are a different
## case on purpose: a save whose `fit` arrived as an array is a save with one
## unusable line beside three fields that are perfectly good, and taking a
## member's earned standing away because an unrelated map went bad is a worse
## failure than dropping the map. The maps are each dropped on their own below.
## `bool` is excluded from the numeric check because `int(true)` would disguise a
## corrupt count as `1`.
static func _claim_fields_readable(data: Dictionary) -> bool:
	for key in ["institution", "position", "doctrine", FOUNDER_KEY]:
		var value = data.get(key, null)
		if value != null and not _is_text(value):
			return false
	for key in ["standing", "standing_cap", "applied_standing"]:
		var value = data.get(key, null)
		if value != null and not (value is int or value is float):
			return false
	return true


## Every declared split, normalized field by field and capped. A row that is not a
## map, or that names no seceding sect, is dropped whole — the same lenient-one-line
## rule the other maps follow — and the cap is the `ROSTER_LIMIT` argument again: a
## hand-written save cannot ask for a million declarations.
static func _schism_rows(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (value is Dictionary):
		return out
	for sect_id in (value as Dictionary).keys():
		if out.size() >= SCHISM_LIMIT:
			break
		var entry = (value as Dictionary)[sect_id]
		if not (entry is Dictionary):
			continue
		var row: Dictionary = entry as Dictionary
		var half_id := _text(row.get("seceding_id", ""), "")
		if half_id == "":
			continue
		out[String(sect_id)] = {
			"schism_id": _text(row.get("schism_id", ""), ""),
			"parent_id": _text(row.get("parent_id", ""), ""),
			"seceding_id": half_id,
			"verb": _text(row.get("verb", ""), ""),
			"undivided": maxi(0, int(row.get("undivided", 0))),
			"price": maxi(0, int(row.get("price", 0))),
			"unassigned": maxi(0, int(row.get("unassigned", 0))),
			"settled": maxi(0, int(row.get("settled", 0))),
		}
	return out
