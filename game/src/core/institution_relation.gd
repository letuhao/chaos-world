class_name InstitutionRelation
extends RefCounted

## Inter-organization favour, debt, grant and stance verbs over a `WorldPolityLedger`
## (ADR 0931). This is the capability surface; the ledger file owns storage and the
## fold, and this file never re-implements either — every writer normalizes through
## `WorldPolityLedger.normalize_payload` on the way in and on the way out, so there
## is exactly one answer to what a payload means.
##
## ## A fact whose subject is two institutions lives here, never on an actor
##
## `WorldPolityLedger`'s boundary rule, enforced at both ends: writers take plain
## institution ids and refuse anything carrying key syntax (`|`, `->`, `#`), and an
## id the ledger cannot tell from an actor id is the CALLER's to get right — the
## ledger cannot tell them apart, so sect and nation pass institution ids and the
## suite pins the refusal shapes rather than a registry this file may not name.
##
## ## Favour is the creditor's read of a debt, not a second number
##
## Granting favour opens a debt (`declare`); repaying it settles one (`settle`).
## The creditor's side of that same row — `relations_of`'s `is_owed` — IS the
## favour, so favour needs no writer of its own and no second copy can disagree
## with the debt it describes.
##
## ## Terms are ids and counts, never amounts
##
## A line holds how many periods are owed, never what a period is worth, so
## retuning a rate never rewrites a save (`InstitutionLedger.positive_lines` states
## the shape). `sequence` counts opens onto a row and orders rival spellings in a
## hand-edited save — the lower sequence is the earlier declaration and wins, ties
## going to the lexicographically smaller spelling, exactly as the fold does.
## `settle` only removes, so it never moves the counter.
##
## ## The D8 gate: bounded outputs, a priced revocation, counted receipts
##
## `declare` charges no fee for recording a fact — the debt IS the cost, paid at
## `settle` — but every output is bounded: counts clamp at `PERIOD_CAP`, rows at
## `DEBT_LIMIT`/`GRANT_LIMIT`, lines per row at `TERM_LIMIT`. `settle` returns the
## count it settled, `escheat` always opens a one-period forfeit, and a refusal
## writes nothing (ADR 0044).
##
## ## Refusals, and what each one means
##
## `no_pair` (empty, self-paired, or separator-carrying ids), `unknown_term` (empty,
## separator-carrying, or wrong-typed term — terms are free-form ids, so only the
## shape can be refused), `non_positive` (a zero count is a caller bug, never a
## no-op), `crossed_lines` (the pair already owes the other way — settle first),
## `reserved_term` (a stance flag through the debt verb), `not_a_stance` (a debt
## term through the stance verb), `already_declared` (the flag is already open),
## `no_grant` (nothing open as described), `grant_open` (one grant per pair and
## node), `grant_lines_open` (settle the terms before the node reverts),
## `unknown_node` (empty or separator-carrying node id).

## The pair names no real institutions.
const R_NO_PAIR := "no_pair"
## The term names nothing writable.
const R_UNKNOWN_TERM := "unknown_term"
## A zero or negative count, which is a caller bug rather than a quiet no-op.
const R_NON_POSITIVE := "non_positive"
## The pair already holds open debt lines the other way. Settle them first: netting
## two real obligations into one would destroy the trail of which was which.
const R_CROSSED_LINES := "crossed_lines"
## A stance flag (`schism`, `war`) through `declare` or `grant`. Stance is read by
## the relation graph, never counted as periods owed.
const R_RESERVED_TERM := "reserved_term"
## A debt term through `reconcile`. Reconciliation closes stance flags; debts close
## through `settle`.
const R_NOT_A_STANCE := "not_a_stance"
## The stance flag is already open. Declaring twice changes nothing, so the second
## declaration is refused loudly rather than absorbed.
const R_ALREADY_DECLARED := "already_declared"
## No grant is open as described — wrong pair, wrong node, or wrong direction.
const R_NO_GRANT := "no_grant"
## A grant is already open for this pair and node. One grant per pair per node, so
## a second opening is refused rather than stacked.
const R_GRANT_OPEN := "grant_open"
## The granted terms (or the pair's same-direction lines) are still open. The node
## reverts only over a clean slate, so revocation can never strand a debt.
const R_GRANT_LINES_OPEN := "grant_lines_open"
## The node id is empty or carries key syntax.
const R_UNKNOWN_NODE := "unknown_node"

## Terms that are stance flags, never debt counts. Written only by the stance verbs
## (`declare_schism`, `declare_war`), refused by `declare` and `grant`, and read by
## the relation graph — which is why a debt term can never pollute it.
const RESERVED_TERMS: Array[String] = ["schism", "war"]

## The term an escheat always opens, and its fixed price in periods. Paid by the
## revoked holder to the revoking grantor: reclaiming a node is never free, and a
## fixed price cannot be haggled into a silent reclaim.
const ESCHEAT_PRICE_TERM := "escheat_price"
const ESCHEAT_PRICE := 1


## Open (or add to) a debt: `debtor_id` owes `creditor_id` `periods` more on
## `term_id`. Same-direction lines accumulate toward `PERIOD_CAP`; a pair owing the
## other way refuses as `crossed_lines` rather than netting.
##
## The receipt carries the replacement ledger under `"ledger"` and the new line
## total under `"periods"`. The input is never mutated.
static func declare(
	ledger: Dictionary, debtor_id: String, creditor_id: String, term_id: String, periods: int
) -> Dictionary:
	var debtor := _clean(debtor_id)
	var creditor := _clean(creditor_id)
	var term := _clean(term_id)
	if debtor == "" or creditor == "" or debtor == creditor:
		return InstitutionLedger.refuse(R_NO_PAIR)
	if term == "":
		return InstitutionLedger.refuse(R_UNKNOWN_TERM)
	if RESERVED_TERMS.has(term):
		return InstitutionLedger.refuse(R_RESERVED_TERM)
	if periods <= 0:
		return InstitutionLedger.refuse(R_NON_POSITIVE)
	var live := _live(ledger)
	var canonical := _canonical_of(debtor, creditor)
	var debts := live["debts"] as Dictionary
	var held = debts.get(canonical)
	var total := 0
	if held is Dictionary:
		var row := held as Dictionary
		if (
			_has_debt_lines(row)
			and (
				String(row.get("debtor_id", "")) != debtor
				or String(row.get("creditor_id", "")) != creditor
			)
		):
			return InstitutionLedger.refuse(R_CROSSED_LINES)
		var lines := row["lines"] as Dictionary
		total = mini(int(lines.get(term, 0)) + periods, WorldPolityLedger.PERIOD_CAP)
		lines[term] = total
		# A stance-only row has no debt direction yet, so the first debt written
		# steers it; a debt row already steered this way keeps its course.
		row["debtor_id"] = debtor
		row["creditor_id"] = creditor
		row["sequence"] = int(row.get("sequence", 0)) + 1
	else:
		total = mini(periods, WorldPolityLedger.PERIOD_CAP)
		debts[canonical] = {
			"debtor_id": debtor,
			"creditor_id": creditor,
			"sequence": 1,
			"lines": {term: total},
		}
	return (
		InstitutionLedger
		. ok(
			{
				"ledger": _live(live),
				"debtor_id": debtor,
				"creditor_id": creditor,
				"term_id": term,
				"periods": total,
			}
		)
	)


## Settle up to `periods` on one line. Over-settling clamps and returns what was
## actually settled; settling a line that was never opened returns 0 on an `ok`,
## because "never opened" and "settled" are the same state. A settled-empty row is
## pruned, so settle-to-zero reads byte-identical to never-opened.
static func settle(
	ledger: Dictionary, debtor_id: String, creditor_id: String, term_id: String, periods: int
) -> Dictionary:
	var debtor := _clean(debtor_id)
	var creditor := _clean(creditor_id)
	var term := _clean(term_id)
	if debtor == "" or creditor == "" or debtor == creditor:
		return InstitutionLedger.refuse(R_NO_PAIR)
	if term == "":
		return InstitutionLedger.refuse(R_UNKNOWN_TERM)
	if periods <= 0:
		return InstitutionLedger.refuse(R_NON_POSITIVE)
	var live := _live(ledger)
	var canonical := _canonical_of(debtor, creditor)
	var debts := live["debts"] as Dictionary
	var settled := 0
	var held = debts.get(canonical)
	if held is Dictionary:
		var row := held as Dictionary
		if (
			String(row.get("debtor_id", "")) == debtor
			and String(row.get("creditor_id", "")) == creditor
		):
			var lines := row["lines"] as Dictionary
			var open_now := int(lines.get(term, 0))
			if open_now > 0:
				settled = mini(open_now, periods)
				var remaining := open_now - settled
				if remaining <= 0:
					lines.erase(term)
				else:
					lines[term] = remaining
				if lines.is_empty():
					debts.erase(canonical)
	return (
		InstitutionLedger
		. ok(
			{
				"ledger": _live(live),
				"debtor_id": debtor,
				"creditor_id": creditor,
				"term_id": term,
				"settled": settled,
			}
		)
	)


## Close a stance flag without needing to know which side carries it. Reads the
## pair's one row once and settles through it, so the order the caller names the
## pair in never matters.
static func reconcile(ledger: Dictionary, a_id: String, b_id: String, verb: String) -> Dictionary:
	var first := _clean(a_id)
	var second := _clean(b_id)
	var word := _clean(verb)
	if first == "" or second == "" or first == second:
		return InstitutionLedger.refuse(R_NO_PAIR)
	if word == "" or not RESERVED_TERMS.has(word):
		return InstitutionLedger.refuse(R_NOT_A_STANCE)
	var live := _live(ledger)
	var held = (live["debts"] as Dictionary).get(_canonical_of(first, second))
	if not (held is Dictionary):
		return InstitutionLedger.ok({"ledger": live, "verb": word, "settled": 0})
	var row := held as Dictionary
	var open_now := int((row["lines"] as Dictionary).get(word, 0))
	if open_now <= 0:
		return InstitutionLedger.ok({"ledger": live, "verb": word, "settled": 0})
	var receipt := settle(
		live, String(row.get("debtor_id", "")), String(row.get("creditor_id", "")), word, open_now
	)
	receipt["verb"] = word
	return receipt


## Record a split: `seceding_id` broke from `parent_id`. The seceding half carries
## the line, and the flag reads through the relation graph as hostility. A debt the
## pair already holds is left alone — splitting while owing is legitimate, and the
## stance verb never steers the row's direction.
static func declare_schism(
	ledger: Dictionary, parent_id: String, seceding_id: String
) -> Dictionary:
	return _declare_stance(ledger, parent_id, seceding_id, "schism", seceding_id, parent_id)


## Record a war between two nations. The declarer's order is kept on the row, and
## `reconcile` stays order-free, so no caller has to remember which side was named
## first. The prize is the nation's to declare; the world ledger records only that
## the pair is at war.
static func declare_war(ledger: Dictionary, a_id: String, b_id: String) -> Dictionary:
	return _declare_stance(ledger, a_id, b_id, "war", a_id, b_id)


## One institution's whole view: what it owes, what it is owed (its favour), and
## the stance flags on every pair it belongs to. `{}` for an empty id — ADR 0083's
## first state, "this does not exist".
static func relations_of(ledger: Dictionary, institution_id: String) -> Dictionary:
	var subject := _clean(institution_id)
	if subject == "":
		return {}
	var live := _live(ledger)
	var owes := {}
	var is_owed := {}
	var stances: Array = []
	var seen := {}
	var debts := live["debts"] as Dictionary
	# A `for` over a snapshot, filling NEW dictionaries: the body never writes to
	# the container being walked, so the bound cannot grow in lockstep with it.
	for key in InstitutionLedger.sorted_keys(debts):
		var row = debts[key]
		if not (row is Dictionary):
			continue
		var debtor := String((row as Dictionary).get("debtor_id", ""))
		var creditor := String((row as Dictionary).get("creditor_id", ""))
		if debtor != subject and creditor != subject:
			continue
		var other := creditor if debtor == subject else debtor
		seen[other] = true
		var counted := {}
		var lines = (row as Dictionary).get("lines", {}) as Dictionary
		for term in lines.keys():
			var word := String(term)
			if RESERVED_TERMS.has(word):
				stances.append({"verb": word, "other_id": other})
			elif int(lines[term]) > 0:
				counted[word] = int(lines[term])
		if not counted.is_empty():
			if debtor == subject:
				owes[other] = counted
			else:
				is_owed[other] = counted
	return {
		"institution": subject,
		"owes": owes,
		"is_owed": is_owed,
		"stances": stances,
		"pairs": seen.size(),
	}


## Grant `node_id` from `grantor_id` to `grantee_id` under `terms`. The terms open
## as a REAL debt row the grantee owes the grantor — through `declare`, so every
## refusal and clamp applies — which leaves exactly one copy of every count for
## `settle` to reach. The grant row itself records only who holds what from whom.
##
## Every term is validated before any is written, so a refused grant writes nothing.
static func grant(
	ledger: Dictionary, grantor_id: String, grantee_id: String, node_id: String, terms: Dictionary
) -> Dictionary:
	var grantor := _clean(grantor_id)
	var grantee := _clean(grantee_id)
	var node := _clean(node_id)
	if grantor == "" or grantee == "" or grantor == grantee:
		return InstitutionLedger.refuse(R_NO_PAIR)
	if node == "":
		return InstitutionLedger.refuse(R_UNKNOWN_NODE)
	if not (terms is Dictionary):
		return InstitutionLedger.refuse(R_UNKNOWN_TERM)
	var clean := {}
	for term in (terms as Dictionary).keys():
		var word := _clean(term)
		if word == "":
			return InstitutionLedger.refuse(R_UNKNOWN_TERM)
		if RESERVED_TERMS.has(word):
			return InstitutionLedger.refuse(R_RESERVED_TERM)
		var count = (terms as Dictionary)[term]
		if not (count is int or count is float):
			return InstitutionLedger.refuse(R_UNKNOWN_TERM)
		if int(count) <= 0:
			return InstitutionLedger.refuse(R_NON_POSITIVE)
		clean[word] = mini(int(count), WorldPolityLedger.PERIOD_CAP)
	var live := _live(ledger)
	var gkey := _grant_key(grantor, grantee, node)
	var grants := live[WorldPolityLedger.GRANT_CONTAINER] as Dictionary
	if grants.get(gkey) is Dictionary:
		return InstitutionLedger.refuse(R_GRANT_OPEN)
	# Same pair and direction for every term, so the verdict cannot change
	# mid-loop: the first `declare` either merges or refuses before writing, and
	# every later one merges into what the first wrote.
	var working := live
	for word in clean.keys():
		var opened := declare(working, grantee, grantor, String(word), int(clean[word]))
		if not bool(opened.get("ok", false)):
			return opened
		working = opened["ledger"] as Dictionary
	var wgrants := working[WorldPolityLedger.GRANT_CONTAINER] as Dictionary
	wgrants[gkey] = {
		"grantor_id": grantor,
		"grantee_id": grantee,
		"node_id": node,
		"sequence": 1,
		"lines": {},
	}
	return (
		InstitutionLedger
		. ok(
			{
				"ledger": _live(working),
				"grantor_id": grantor,
				"grantee_id": grantee,
				"node_id": node,
				"terms": clean,
			}
		)
	)


## Reclaim a granted node, by name and for a price. Refuses while any of the
## pair's same-direction lines are still open — the node reverts over a clean
## slate, so revocation can never strand a debt — and always opens a one-period
## forfeit the revoked holder owes the grantor. A settled grant still costs the
## forfeit: reclaiming is the priced act, never a silent one.
static func escheat(
	ledger: Dictionary, grantor_id: String, grantee_id: String, node_id: String
) -> Dictionary:
	var grantor := _clean(grantor_id)
	var grantee := _clean(grantee_id)
	var node := _clean(node_id)
	if grantor == "" or grantee == "" or grantor == grantee:
		return InstitutionLedger.refuse(R_NO_PAIR)
	if node == "":
		return InstitutionLedger.refuse(R_UNKNOWN_NODE)
	var live := _live(ledger)
	var gkey := _grant_key(grantor, grantee, node)
	var grants := live[WorldPolityLedger.GRANT_CONTAINER] as Dictionary
	var held = grants.get(gkey)
	if not (held is Dictionary):
		return InstitutionLedger.refuse(R_NO_GRANT)
	if (
		String((held as Dictionary).get("grantor_id", "")) != grantor
		or String((held as Dictionary).get("grantee_id", "")) != grantee
	):
		return InstitutionLedger.refuse(R_NO_GRANT)
	if not ((held as Dictionary).get("lines", {}) as Dictionary).is_empty():
		return InstitutionLedger.refuse(R_GRANT_LINES_OPEN)
	var drow = (live["debts"] as Dictionary).get(_canonical_of(grantee, grantor))
	if drow is Dictionary:
		var dlines := (drow as Dictionary).get("lines", {}) as Dictionary
		for term in dlines.keys():
			if RESERVED_TERMS.has(String(term)):
				continue
			if int(dlines[term]) > 0:
				return InstitutionLedger.refuse(R_GRANT_LINES_OPEN)
	var priced := declare(live, grantee, grantor, ESCHEAT_PRICE_TERM, ESCHEAT_PRICE)
	if not bool(priced.get("ok", false)):
		return priced
	var working := priced["ledger"] as Dictionary
	(working[WorldPolityLedger.GRANT_CONTAINER] as Dictionary).erase(gkey)
	return (
		InstitutionLedger
		. ok(
			{
				"ledger": _live(working),
				"grantor_id": grantor,
				"grantee_id": grantee,
				"node_id": node,
				"reverted": node,
				"forfeit": ESCHEAT_PRICE,
			}
		)
	)


## Every grant one institution gave or holds, with each grant's terms read live
## from the debt row — always current, never a second copy. `{}` for an empty id.
static func grants_of(ledger: Dictionary, institution_id: String) -> Dictionary:
	var subject := _clean(institution_id)
	if subject == "":
		return {}
	var live := _live(ledger)
	var given: Array = []
	var held: Array = []
	var debts := live["debts"] as Dictionary
	var grants := live[WorldPolityLedger.GRANT_CONTAINER] as Dictionary
	# A `for` over a snapshot, appending to NEW arrays: the walked container is
	# never written to, so the bound is fixed before the first iteration.
	for key in InstitutionLedger.sorted_keys(grants):
		var row = grants[key]
		if not (row is Dictionary):
			continue
		var grantor := String((row as Dictionary).get("grantor_id", ""))
		var grantee := String((row as Dictionary).get("grantee_id", ""))
		if grantor != subject and grantee != subject:
			continue
		var terms := {}
		var drow = debts.get(_canonical_of(grantee, grantor))
		if drow is Dictionary:
			var dlines := (drow as Dictionary).get("lines", {}) as Dictionary
			for term in dlines.keys():
				var word := String(term)
				if RESERVED_TERMS.has(word):
					continue
				if int(dlines[term]) > 0:
					terms[word] = int(dlines[term])
		var entry := {
			"grantor_id": grantor,
			"grantee_id": grantee,
			"node_id": String((row as Dictionary).get("node_id", "")),
			"terms": terms,
		}
		if grantor == subject:
			given.append(entry)
		else:
			held.append(entry)
	return {
		"institution": subject,
		"given": given,
		"held": held,
		"count": given.size() + held.size(),
	}


# --- Internals ---------------------------------------------------------------


## One stance flag onto the pair's row. Never steers the row's direction and never
## refuses over an open debt: splitting while owing is legitimate, and the flag is
## not a count, so there is nothing to net it against.
static func _declare_stance(
	ledger: Dictionary,
	first: String,
	second: String,
	verb: String,
	debtor: String,
	creditor: String
) -> Dictionary:
	var a := _clean(first)
	var b := _clean(second)
	if a == "" or b == "" or a == b:
		return InstitutionLedger.refuse(R_NO_PAIR)
	var live := _live(ledger)
	var canonical := _canonical_of(a, b)
	var debts := live["debts"] as Dictionary
	var held = debts.get(canonical)
	if held is Dictionary:
		var row := held as Dictionary
		if int((row["lines"] as Dictionary).get(verb, 0)) > 0:
			return InstitutionLedger.refuse(R_ALREADY_DECLARED)
		(row["lines"] as Dictionary)[verb] = 1
		row["sequence"] = int(row.get("sequence", 0)) + 1
	else:
		debts[canonical] = {
			"debtor_id": _clean(debtor),
			"creditor_id": _clean(creditor),
			"sequence": 1,
			"lines": {verb: 1},
		}
	return InstitutionLedger.ok({"ledger": _live(live), "verb": verb, "a_id": a, "b_id": b})


## Whether the row holds any open DEBT line. Stance flags do not count: a pair
## that split but owes nothing has no debt direction, and must not block one.
static func _has_debt_lines(row: Dictionary) -> bool:
	var lines = row.get("lines", {})
	if not (lines is Dictionary):
		return false
	for term in (lines as Dictionary).keys():
		if RESERVED_TERMS.has(String(term)):
			continue
		if int((lines as Dictionary)[term]) > 0:
			return true
	return false


## The pair's canonical directed key. The pair is validated before every call, so
## the split always yields two ids; `""` answers a pair that is not one rather than
## indexing into it.
static func _canonical_of(a: String, b: String) -> String:
	var pair_ids := WorldPolityLedger.split_pair_key(WorldPolityLedger.pair_key(a, b))
	if pair_ids.size() != 2:
		return ""
	return WorldPolityLedger.directed_key(pair_ids[0], pair_ids[1])


## A grant's canonical key: the pair's canonical directed spelling plus the node.
## Both spellings of one grant collide on it, exactly like debts.
static func _grant_key(grantor: String, grantee: String, node: String) -> String:
	return _canonical_of(grantor, grantee) + WorldPolityLedger.GRANT_SEPARATOR + node


## The ledger, normalized. Writers always start here, so a hand-built or older
## payload is folded, clamped and sequenced before any verb touches it — and end
## here, so every receipt carries the canonical shape.
static func _live(ledger: Dictionary) -> Dictionary:
	return WorldPolityLedger.normalize_payload(ledger)


## Text that may enter a key or a term: a real string with no key syntax in it.
## Anything else — empty, wrong-typed, or separator-carrying — is refused upstream
## rather than split, coerced, or guessed at.
static func _clean(value: Variant) -> String:
	if not (value is String or value is StringName):
		return ""
	var text := String(value)
	if text == "" or text.contains("|") or text.contains("->") or text.contains("#"):
		return ""
	return text
