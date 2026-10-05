class_name WorldPolityLedger
extends RefCounted

## The world-scoped persistence root for facts between POLITIES, riding the save
## envelope's `world.polity` slot beside the actor (DEF-0119, the ADR 0037 precedent).
##
## ## What problem this file exists to solve
##
## ADR 0083 makes a nation "a polity persisting across generations", and definy /
## death / retirement are all actor events. Measured before this file:
## `actor.module_data` was the only persistence root in the repo and it dies with the
## actor, so a save loaded by somebody who is not a member of the polity lost the whole
## political world. `SectState.treasury` was deliberately namespaced `treasury_<sect_id>_`
## (`sect_state.gd:372-379`) precisely so two sects could not read each other's debt —
## which is correct for a MEMBER's ledger and fatal for an INSTITUTION's.
##
## ## ## The boundary rule, argued rather than assumed
##
## **The world ledger holds institution-to-institution facts only. Every
## player-contact fact stays on the actor.** The argument has three steps and the
## middle one is the decision:
##
## 1. **ADR 0076 is the test, and it is already the repo's.** `social`'s own docstring
##    says `SocialState.regard` is "the read model, not a second writer of it" because
##    "the clan module owns that number already". Regard is *how someone regards a
##    person* — it is keyed by an actor and it changes because that person did
##    something. Its lifetime is exactly the actor's lifetime, so promoting it to a
##    world root buys nothing and costs correctness the moment a second person exists.
## 2. **An inter-institution obligation has no such key.** "Sect A owes sect B four
##    periods" is not true of any actor. It is true *of A and B*, and A and B both
##    outlive every actor who ever wrote it. A fact whose subject is a pair of
##    institutions cannot be stored under an actor without inventing a subject the
##    fact does not have — and per-actor copies of a shared fact are the exact bug
##    `WorldLedger`'s own docblock calls out ("two actors then each hold their own copy
##    and a rival reads a held node as vacant").
## 3. **So the split falls out of the subject, not out of convenience.** A fact whose
##    SUBJECT includes an actor id stays on that actor. A fact whose subject is two or
##    more institution ids goes here. That is one sentence a reviewer can apply to a
##    new field, and it is what `is_institutional` below enforces mechanically.
##
## ## ## Consequence: this file names no actor, and there is a test for that
##
## No row here may hold a key that is a known actor id, and `institutional_line_ids`
## exists so a caller cannot smuggle one in through a computed term id. The bound
## holds on the SUBJECT string (`a|b`, two institution ids, canonical order), so it
## cannot be defeated by an awkward term name.
##
## ## ## `core/` may only use `contracts/`, and this file uses neither
##
## It declares no `res://` reference and no module class name. It is handed
## `InstitutionClaim` (a `core/` class) and plain `String` ids. `tools arch` reads
## `res://`/`extends` as real edges, so the absence of both is the mechanical half of
## the boundary; the half it CANNOT see — a bare `SectApi` reference — is why the
## boundary is also stated in `tests/core/test_world_polity_ledger.gd`.

const SCHEMA_VERSION := 1

## The envelope key this ledger rides. Declared HERE as well as in
## `SaveSlot.WORLD_KEYS`, because `modules/save` may not name this file's internals and
## this file may not name `modules/save`. The two are asserted equal by test rather
## than by a `preload`, which would be an upward edge.
const WORLD_KEY := "polity"

## The separator joining the two institution ids of a line. A character no authored
## institution id contains, so the pair always splits back apart and a reversed key can
## always be detected. `NationState.PAIR_SEPARATOR` is the same precedent.
const PAIR_SEPARATOR := "|"

## The containers this ledger owns, in the exact shape it normalizes. `SaveSlot` and
## `app/world_ledger_store.gd` both need to know a polity ledger by its containers, and
## neither may reach this file's normalizer, so the table is authored here and asserted
## against the store's copy by test.
const CONTAINERS: Array[String] = ["institutions", "debts"]

## The bound on institution rows. A hand-edited save asking for two million institutions
## is refused by the cap rather than read, exactly as `SectState.ROSTER_LIMIT` is.
const INSTITUTION_LIMIT := 64
## The bound on debt lines. One row per ORDERED pair, so two institutions owe at most
## two lines to each other; the cap is a corrupt-save guard, not a budget.
const DEBT_LIMIT := 256
## The bound on term ids inside one line, for the same reason.
const TERM_LIMIT := 16
## A debt period count is clamped here rather than trusted: a corrupt save must not be
## able to ask for a million periods and have arithmetic on it be correct.
const PERIOD_CAP := 1000
## The default authored cap on an institution row's standing, used when a payload carries
## none. `InstitutionClaim.standing_cap` defaults to 100 and this must agree, or a
## restored row would report a different normalized ratio than one built in memory.
const DEFAULT_STANDING_CAP := 100


## ## The boundary rule as CODE
##
## A line id is institutional iff it names TWO ids joined by [constant PAIR_SEPARATOR],
## both non-empty and DIFFERENT from each other. Anything else is a player-contact or
## malformed line and does not belong on this ledger.
##
## A self pair is refused rather than canonicalized, for `NationState`'s stated reason:
## a self pair has no lexicographic ORDER, so one canonical row cannot express a
## two-sided opinion — and "sect A owes sect A" is not a political fact.
static func is_institutional(line_id: String) -> bool:
	var parts := line_id.split(PAIR_SEPARATOR, false, 1)
	if parts.size() != 2:
		return false
	var first := String(parts[0])
	var second := String(parts[1])
	return first != "" and second != "" and first != second


## The canonical key for an unordered pair of institution ids: the two ids ordered
## lexicographically, joined. Swapping the arguments cannot produce a different key,
## which is ADR 0047's symmetry made STRUCTURAL — the precedent is
## `NationState.pair_key` and `tests/modules/nation/test_nation_symmetry.gd`.
##
## **`""` when either id is empty or the pair is a self pair**, never a key the
## normalizer would then have to guess about. A caller that ignores the refusal writes
## a line the normalizer drops, which is visible; a caller that guessed would not be.
static func pair_key(a_id: String, b_id: String) -> String:
	if a_id == "" or b_id == "" or a_id == b_id:
		return ""
	return a_id + PAIR_SEPARATOR + b_id if a_id <= b_id else b_id + PAIR_SEPARATOR + a_id


## Both ids of a canonical key, in canonical order. `[]` for anything that is not one —
## an unreadable key is DROPPED, never guessed at, the same rule `NationState`'s
## self-pair case states.
static func split_pair_key(key: String) -> Array[String]:
	if not is_institutional(key):
		return []
	var parts := key.split(PAIR_SEPARATOR, false, 1)
	return [String(parts[0]), String(parts[1])]


## The OBLIGOR side's perspective, as an ordered key: `payer->receiver`.
##
## **This is the second half of the one-row rule and it is why the ledger is not a copy
## of anybody's.** A debt is directed: A owes B, so B reading "what do I owe?" must not
## see it and A reading "what is owed to me?" must not miss it. One canonical
## UNORDERED row with a `debtor`/`creditor` pair expresses both directions from ONE
## stored fact, which is what "neither side's ledger is a copy of the other's" means
## mechanically. Two ordered rows would be two copies of one political fact and could
## disagree — the one-sided-write failure ADR 0047 forbids.
static func directed_key(debtor_id: String, creditor_id: String) -> String:
	var unordered := pair_key(debtor_id, creditor_id)
	return "" if unordered == "" else "%s->%s" % [String(debtor_id), String(creditor_id)]


## The canonical UNORDERED key a directed key's pair reduces to, or `""` when the
## directed key is not one of ours. This is the fold `normalize` applies, so a payload
## carrying both spellings of one pair lands as one row.
static func undirected_of(directed_id: String) -> String:
	var ids := split_directed_key(directed_id)
	if ids.is_empty():
		return ""
	return pair_key(ids[0], ids[1])


## Both ids of a directed key, obligor first. `[]` for anything unreadable.
static func split_directed_key(directed_id: String) -> Array[String]:
	var at := directed_id.find("->")
	if at <= 0:
		return []
	var debtor := directed_id.substr(0, at)
	var creditor := directed_id.substr(at + 2)
	if creditor == "":
		return []
	return [debtor, creditor]


## The empty ledger. A missing slot, an unreadable payload and this are the same value,
## so "no polity has ever owed anything" has one spelling instead of three.
static func empty() -> Dictionary:
	return normalize_payload({})


## A ledger rebuilt from a saved payload, JSON hop included.
##
## Normalization is the MIGRATION and it is total: every field is coerced, every id is
## folded to canonical order, and a row that cannot be read is dropped rather than
## partially applied. An OLD version is accepted and folded onto the current shape — the
## ADR 0165 rule — so a save written before this slot existed reads as an empty world
## rather than failing. A FUTURE version is refused by `app/world_ledger_store.gd` by
## name, never silently read, because reading it and writing it back is how a newer
## build's world is erased by an older one.
static func normalize_payload(payload: Dictionary) -> Dictionary:
	var out := {"version": SCHEMA_VERSION}
	for container in CONTAINERS:
		out[container] = {}
	# The institution rows are copied whole under the normalizer's own rules: one row
	# per institution id, and a row that cannot be read is DROPPED rather than persisted
	# as an empty one (the same repair `WorldFact.normalize_payload` states, for the same
	# reason — a row nothing can read is a fact nothing can ask for).
	var institutions = payload.get("institutions", {})
	if institutions is Dictionary:
		for key in _sorted_keys(institutions as Dictionary):
			if (out["institutions"] as Dictionary).size() >= INSTITUTION_LIMIT:
				break
			var institution := String(key)
			if institution == "":
				continue
			var row := _institution_row((institutions as Dictionary)[key])
			if row.is_empty():
				continue
			out["institutions"][institution] = row
	# The debt rows are folded, which is the whole symmetry mechanism. A payload holding
	# `b|a` and `a|b` lands as ONE row and the loser is never persisted.
	var debts = payload.get("debts", {})
	if debts is Dictionary:
		for key in _sorted_keys(debts as Dictionary):
			if (out["debts"] as Dictionary).size() >= DEBT_LIMIT:
				break
			var directed := String(key)
			var ids := split_directed_key(directed)
			if ids.is_empty() or ids[0] == ids[1]:
				continue
			if not is_institutional(pair_key(ids[0], ids[1])):
				continue
			var row := _debt_row((debts as Dictionary)[key], directed)
			var canonical := directed
			var held = (out["debts"] as Dictionary).get(canonical)
			if (
				held is Dictionary
				and int((held as Dictionary).get("sequence", 0)) >= int(row["sequence"])
			):
				# Two spellings of one pair: the LOWER sequence is the earlier
				# declaration and wins. A hand-edited save cannot make the later one
				# overwrite the earlier, and a pair written once is untouched.
				continue
			(out["debts"] as Dictionary)[canonical] = row
	return out


## A ledger as the disk should carry it, JSON-safe. `String` keys throughout and no
## `StringName` anywhere, for the reason `InstitutionClaim.to_dict` states: these travel
## into save blobs where an interned name is not a value.
static func to_dict(ledger: Dictionary) -> Dictionary:
	return normalize_payload(ledger)


## The row for one institution, as primitives, or `{}` when it is not in the ledger.
## A read rather than a second dictionary lookup by every caller, so a panel and a gate
## cannot drift into answering differently about the same polity.
static func institution(ledger: Dictionary, institution_id: String) -> Dictionary:
	if institution_id == "":
		return {}
	var row = (ledger.get("institutions", {}) as Dictionary).get(institution_id)
	return (row as Dictionary).duplicate(true) if row is Dictionary else {}


## The `[debtor, creditor]` pair the ledger holds for `institution_id`, in the order
## they are stored: what this institution owes, and what is owed to it. `[]` for a
## polity with no lines in either direction.
##
## ## This is the two-sided read, and it is ONE read
##
## A caller asking sect B what sect A owes it must NOT ask twice and combine the
## answers — a pair assembled from two lookups is two facts that can disagree. One
## canonical row per unordered pair is what makes the answer symmetric by
## construction rather than by convention.
static func pairs_of(ledger: Dictionary, institution_id: String) -> Array:
	var out: Array = []
	if institution_id == "":
		return out
	var rows = ledger.get("debts", {}) as Dictionary
	for key in _sorted_keys(rows):
		var ids := split_directed_key(String(key))
		if ids.size() != 2 or (ids[0] != institution_id and ids[1] != institution_id):
			continue
		out.append((rows as Dictionary)[key])
	if out.size() > DEBT_LIMIT:
		out.resize(DEBT_LIMIT)
	return out


## How many periods `debtor_id` still owes `creditor_id` on `term_id`.
##
## Zero when there is no such line, because "nobody opened this debt" and "this debt
## is settled" are the same state — `InstitutionClaim.owed` states the rule and this
## reads through the same shape rather than restating it.
static func owed(
	ledger: Dictionary, debtor_id: String, creditor_id: String, term_id: String
) -> int:
	var directed := directed_key(debtor_id, creditor_id)
	if directed == "" or term_id == "":
		return 0
	var row = (ledger.get("debts", {}) as Dictionary).get(directed)
	if not (row is Dictionary):
		return 0
	var lines = (row as Dictionary).get("lines", {}) as Dictionary
	return clampi(int(lines.get(term_id, 0)), 0, PERIOD_CAP)


## The canonical UNORDERED key for a pair, so a caller can key its own map on the pair
## rather than on a direction it chose. `""` when the pair is not a real one.
static func pair_of(debtor_id: String, creditor_id: String) -> String:
	return pair_key(debtor_id, creditor_id)


# --- Internals ---------------------------------------------------------------


## One institution row, coerced. `standing_cap` is repaired to at least 1 for the same
## reason `InstitutionClaim.from_dict` repairs it: a row whose cap cannot be computed
## would report a normalized ratio of zero and read as an institution nobody respects.
static func _institution_row(entry) -> Dictionary:
	if not (entry is Dictionary):
		return {}
	var row = entry as Dictionary
	var cap := maxi(1, int(row.get("standing_cap", DEFAULT_STANDING_CAP)))
	return {
		"kind": _text(row.get("kind", "")),
		"standing": clampi(int(row.get("standing", 0)), 0, cap),
		"standing_cap": cap,
		"sequence": maxi(0, int(row.get("sequence", 0))),
	}


## One debt row, coerced. `lines` keeps only positive counts, `terms` is capped at
## [constant TERM_LIMIT], and the two institution ids are re-derived from the KEY rather
## than trusted from the row — a row that names a third institution is folded onto the
## pair its key says, because the key is what makes the symmetry structural.
static func _debt_row(entry, directed: String) -> Dictionary:
	var ids := split_directed_key(directed)
	var out := {
		"debtor_id": ids[0] if ids.size() == 2 else "",
		"creditor_id": ids[1] if ids.size() == 2 else "",
		"sequence": 0,
		"lines": {},
	}
	if not (entry is Dictionary):
		return out
	var row = entry as Dictionary
	out["sequence"] = maxi(0, int(row.get("sequence", 0)))
	var lines = row.get("lines", {})
	if lines is Dictionary:
		for term_id in _sorted_keys(lines as Dictionary):
			if (out["lines"] as Dictionary).size() >= TERM_LIMIT:
				break
			var owed := int((lines as Dictionary)[term_id])
			if owed > 0:
				(out["lines"] as Dictionary)[String(term_id)] = mini(owed, PERIOD_CAP)
	return out


## `value` when it really is text, otherwise `""`. The one text coercion in this file:
## a raw `String(...)` raises at runtime on a float or a dictionary, so a corrupt save
## would abort the load rather than read as empty — the one thing a corrupt save is
## allowed to do.
static func _text(value) -> String:
	if value is String or value is StringName:
		return String(value)
	return ""


## The keys of `source`, canonically ordered by their STRING value. Not `sort()` on the
## raw array: the order is load-bearing — two runs over the same payload must fold in
## the same sequence and persist the same bytes — so a hand-edited save whose two
## spellings of one pair disagree produces the SAME winner every time.
static func _sorted_keys(source: Dictionary) -> Array[String]:
	var strings: Array[String] = []
	for key in source.keys():
		strings.append(String(key))
	strings.sort()
	return strings
