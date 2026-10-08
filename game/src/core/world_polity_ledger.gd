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
## No row here may hold a key that is a known actor id. The bound holds on the
## SUBJECT string (two institution ids in canonical order), so it cannot be defeated
## by an awkward term name — and an id carrying a separator (`|`, `->`, `#`) is
## refused at the verb rather than split (ADR 0931). "Known" is decided by the
## caller: the ledger cannot tell an actor id from an institution id, so writers
## pass institution ids and the suite pins the refusal shapes.
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

## The separator joining a grant's canonical pair to its node id (`a->b#node`). A
## character no authored institution or node id contains; a node id carrying it (or
## `|` or `->`) is refused at the verb and dropped by the normalizer, never split.
const GRANT_SEPARATOR := "#"

## The containers this ledger owns, in the exact shape it normalizes. `SaveSlot` and
## `app/world_ledger_store.gd` both need to know a polity ledger by its containers, and
## neither may reach this file's normalizer, so the table is authored here and asserted
## against the store's copy by test.
const CONTAINERS: Array[String] = ["institutions", "debts"]

## `grants` rides the same slot and normalizes beside the routed containers, but is
## deliberately NOT in [constant CONTAINERS]: the routed identity is pinned to the
## two by `tests/core/test_world_polity_ledger.gd`, and widening it is a save-format
## decision for the slice that owns the envelope (ADR 0931). The store's shape rule
## ignores containers it does not route, so a grants-carrying payload still lands on
## `polity`.
const GRANT_CONTAINER := "grants"

## The bound on institution rows. A hand-edited save asking for two million institutions
## is refused by the cap rather than read, exactly as `SectState.ROSTER_LIMIT` is.
const INSTITUTION_LIMIT := 64
## The bound on debt lines. One row per ORDERED pair, so two institutions owe at most
## two lines to each other; the cap is a corrupt-save guard, not a budget.
const DEBT_LIMIT := 256
## The bound on grant rows. One row per pair per node; the cap is a corrupt-save
## guard, not a budget, for the same reason [constant DEBT_LIMIT] is.
const GRANT_LIMIT := 128
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
			if ids[0].contains(PAIR_SEPARATOR) or ids[1].contains(PAIR_SEPARATOR):
				continue
			if ids[0].contains("->") or ids[1].contains("->"):
				continue
			if not is_institutional(pair_key(ids[0], ids[1])):
				continue
			# ## THE FOLD: one row per unordered PAIR, stored under its canonical
			# ## DIRECTED spelling, so both spellings collide on one row.
			#
			# `a->b` and `b->a` name one obligation, so the fold reduces both to the
			# lexicographically-ordered pair and stores ONE row under that canonical
			# directed key. That single stored key is what `owed` reads: `owed` looks
			# the pair's canonical row up and answers its lines only when the row's
			# recorded direction matches the question, so the debtor's side finds the
			# row and the creditor's side correctly finds none. One row, two
			# directions, no second opinion (BL-0192).
			#
			# The earlier version stored under `directed` — the spelling that ARRIVED — so
			# two spellings of one pair landed as two rows and each side could read a
			# different answer, which is the one-sided opinion this fold exists to forbid.
			#
			# The row keeps the WINNER's direction: the entry's ids win when they name
			# this pair in either order, and the canonical spelling is only the fallback
			# for a row that cannot name its own sides. Relabelling every winner onto
			# the key (the earlier shape) misattributed the debt whenever the reversed
			# spelling won — "rival owes house" read back as "house owes rival" (ADR 0931).
			var pair_ids := split_pair_key(undirected_of(directed))
			if pair_ids.size() != 2:
				continue
			var canonical := directed_key(pair_ids[0], pair_ids[1])
			if canonical == "":
				continue
			var row := _debt_row((debts as Dictionary)[key], canonical)
			if row.is_empty():
				# An unreadable row, or one with nothing owed on any line: dropped
				# rather than persisted as a fact nothing can ask for.
				continue
			var held = (out["debts"] as Dictionary).get(canonical)
			if (
				held is Dictionary
				and int((held as Dictionary).get("sequence", 0)) <= int(row["sequence"])
			):
				# Two spellings of one pair. The row ALREADY HELD under this canonical key
				# is the one with the LOWER sequence, and the lower sequence is the earlier
				# declaration, so it is kept and this later one is dropped. A hand-edited
				# save therefore cannot raise a debt by writing the losing spelling with a
				# bigger count, and a pair written once is untouched.
				#
				# Comparing `sequence` rather than arrival order is what makes that hold no
				# matter which spelling the payload happened to spell first: `_sorted_keys`
				# walks lexicographically, so `t_house->...` is visited before
				# `t_rival_house->...` regardless of the sequences they carry.
				continue
			(out["debts"] as Dictionary)[canonical] = row
	# The grant rows are folded pair by pair beside the debts, under their own
	# container. A grant names the same pair twice — once as the directed pair the
	# fold canonicalizes, once as the node it is granted under — so the key is the
	# canonical directed spelling plus [constant GRANT_SEPARATOR] plus the node id,
	# and both spellings of one grant collide on one row exactly like debts do. The
	# lower sequence wins for the same reason: a hand-edited save cannot raise a
	# grant by respelling it (ADR 0931).
	out[GRANT_CONTAINER] = {}
	var grants = payload.get(GRANT_CONTAINER, {})
	if grants is Dictionary:
		for key in _sorted_keys(grants as Dictionary):
			if (out[GRANT_CONTAINER] as Dictionary).size() >= GRANT_LIMIT:
				break
			var head := _grant_head(String(key))
			var node := _grant_node(String(key))
			var gids := split_directed_key(head)
			if gids.is_empty() or gids[0] == gids[1] or node == "":
				continue
			if gids[0].contains(PAIR_SEPARATOR) or gids[1].contains(PAIR_SEPARATOR):
				continue
			if gids[0].contains("->") or gids[1].contains("->"):
				continue
			if not is_institutional(pair_key(gids[0], gids[1])):
				continue
			var gpair := split_pair_key(undirected_of(head))
			if gpair.size() != 2:
				continue
			var gcanonical := directed_key(gpair[0], gpair[1]) + GRANT_SEPARATOR + node
			var grow := _grant_row((grants as Dictionary)[key], gcanonical)
			if grow.is_empty():
				continue
			var gheld = (out[GRANT_CONTAINER] as Dictionary).get(gcanonical)
			if (
				gheld is Dictionary
				and int((gheld as Dictionary).get("sequence", 0)) <= int(grow["sequence"])
			):
				continue
			(out[GRANT_CONTAINER] as Dictionary)[gcanonical] = grow
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
##
## The pair's canonical row is read and its recorded direction checked, so a debt the
## larger id owes the smaller answers on the larger's side. Looking the caller's own
## spelling up (the earlier shape) could only ever find rows the smaller id owed.
static func owed(
	ledger: Dictionary, debtor_id: String, creditor_id: String, term_id: String
) -> int:
	if term_id == "":
		return 0
	var unordered := pair_key(debtor_id, creditor_id)
	if unordered == "":
		return 0
	var pair_ids := split_pair_key(unordered)
	if pair_ids.size() != 2:
		return 0
	var canonical := directed_key(pair_ids[0], pair_ids[1])
	var row = (ledger.get("debts", {}) as Dictionary).get(canonical)
	if not (row is Dictionary):
		return 0
	if (
		String((row as Dictionary).get("debtor_id", "")) != debtor_id
		or String((row as Dictionary).get("creditor_id", "")) != creditor_id
	):
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


## One debt row, coerced. `lines` keeps only positive counts and is capped at
## [constant TERM_LIMIT]; a row with nothing owed on any line is dropped rather than
## persisted, because a settled line and a never-opened one are the same state.
##
## The entry's ids win when they name this pair in either order; the canonical
## spelling is only the fallback for a row that cannot name its own sides. Trusting
## the entry here is what lets the larger id owe the smaller — relabelling every row
## onto the key made that direction inexpressible (ADR 0931). A row naming a THIRD
## institution still falls back, because the key is what makes the symmetry structural.
static func _debt_row(entry, directed: String) -> Dictionary:
	var ids := split_directed_key(directed)
	var debtor := ids[0] if ids.size() == 2 else ""
	var creditor := ids[1] if ids.size() == 2 else ""
	if not (entry is Dictionary):
		return {}
	var row = entry as Dictionary
	var named_debtor := _text(row.get("debtor_id", ""))
	var named_creditor := _text(row.get("creditor_id", ""))
	if (
		ids.size() == 2
		and named_debtor != ""
		and named_creditor != ""
		and pair_key(named_debtor, named_creditor) == pair_key(ids[0], ids[1])
	):
		debtor = named_debtor
		creditor = named_creditor
	var out := {"debtor_id": debtor, "creditor_id": creditor, "sequence": 0, "lines": {}}
	out["sequence"] = maxi(0, int(row.get("sequence", 0)))
	var lines = row.get("lines", {})
	if lines is Dictionary:
		for term_id in _sorted_keys(lines as Dictionary):
			if (out["lines"] as Dictionary).size() >= TERM_LIMIT:
				break
			var owed := int((lines as Dictionary)[term_id])
			if owed > 0:
				(out["lines"] as Dictionary)[String(term_id)] = mini(owed, PERIOD_CAP)
	if (out["lines"] as Dictionary).is_empty():
		return {}
	return out


## One grant row, coerced. Unlike a debt row, a grant with no open lines is still a
## fact — "this node is held by grant" — so an empty `lines` is kept rather than
## dropped. A non-dictionary entry is still dropped: structure that cannot be read
## is never defaulted into a grant.
##
## The direction rule is the debt row's: the entry's ids win when they name the pair
## in either order. The fallback grants the larger id's holding from the smaller —
## the term-debtor (the grantee, who owes the terms) is the smaller id, exactly as
## the debt fallback makes the smaller id the debtor.
static func _grant_row(entry, grant_key: String) -> Dictionary:
	var head := _grant_head(grant_key)
	var node := _grant_node(grant_key)
	var gids := split_directed_key(head)
	var grantor := gids[1] if gids.size() == 2 else ""
	var grantee := gids[0] if gids.size() == 2 else ""
	if not (entry is Dictionary):
		return {}
	var row = entry as Dictionary
	var named_grantor := _text(row.get("grantor_id", ""))
	var named_grantee := _text(row.get("grantee_id", ""))
	if (
		gids.size() == 2
		and named_grantor != ""
		and named_grantee != ""
		and pair_key(named_grantor, named_grantee) == pair_key(gids[0], gids[1])
	):
		grantor = named_grantor
		grantee = named_grantee
	var out := {
		"grantor_id": grantor,
		"grantee_id": grantee,
		"node_id": node,
		"sequence": 0,
		"lines": {},
	}
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


## The pair half of a grant key (`a->b` of `a->b#node`), or `""` when the key names
## no grant. A node id carrying the separator reads as no grant at all — the key is
## unreadable, never guessed at.
static func _grant_head(grant_key: String) -> String:
	var at := grant_key.find(GRANT_SEPARATOR)
	if at <= 0:
		return ""
	return grant_key.substr(0, at)


## The node half of a grant key, or `""` when it is absent or carries key syntax
## (`#`, `|` or `->`) of its own. A node id that could be re-split is not a node id.
static func _grant_node(grant_key: String) -> String:
	var at := grant_key.find(GRANT_SEPARATOR)
	if at <= 0 or at + GRANT_SEPARATOR.length() >= grant_key.length():
		return ""
	var node := grant_key.substr(at + GRANT_SEPARATOR.length())
	if (
		node == ""
		or node.contains(GRANT_SEPARATOR)
		or node.contains(PAIR_SEPARATOR)
		or node.contains("->")
	):
		return ""
	return node


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
##
## A key that is not text is SKIPPED, never coerced: a raw `String(...)` raises at
## runtime on an int, a float or a dictionary, so trusting it here would abort the
## whole load on one corrupt key instead of reading as empty.
static func _sorted_keys(source: Dictionary) -> Array[String]:
	var strings: Array[String] = []
	for key in source.keys():
		if key is String or key is StringName:
			strings.append(String(key))
	strings.sort()
	return strings
