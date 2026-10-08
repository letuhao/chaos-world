extends TestCase

## ADR 0931: favour, debt, grant and stance verbs over the world polity ledger, and
## the relation graph reading the world ledger (DEF-0179).
##
## ## What would have failed before this change
##
## Every verb here is new: the ledger normalized debts but published no writer, so
## no production caller could open favour, a grant, a schism or a war between two
## institutions. The graph read the authored catalog only. Each section below names
## the behaviour it pins, and the one pre-existing fold it refuses to break.

const HOUSE := "t_house"
const RIVAL := "t_rival_house"
const TERM := "t_blood_price"
const NODE := "t_north_march"
const PARENT := "t_parent_sect"
const HALF := "t_half_sect"
## An id shaped like an actor id, to prove the honest boundary: the pair rule is
## structural, not identity — the ledger cannot tell an actor id from an
## institution id, so "known" is the caller's decision and the suite pins the
## refusal shapes rather than a detection this file cannot perform.
const PERSON := "t_founder_actor"


func setup() -> void:
	expect_assertions(2)
	RelationsApi.shared = null
	RelationsApi._memo = {}


func teardown() -> void:
	RelationsApi.shared = null
	RelationsApi._memo = {}


func _canonical() -> String:
	return WorldPolityLedger.directed_key(HOUSE, RIVAL)


# --- declare: one pair, one row, both sides read it ---------------------------


func test_declare_is_read_from_both_sides_from_one_row() -> void:
	var receipt := InstitutionRelation.declare(WorldPolityLedger.empty(), HOUSE, RIVAL, TERM, 4)
	assert_eq(bool(receipt.get("ok", false)), true, "declare lands")
	var ledger := receipt["ledger"] as Dictionary
	assert_eq((ledger["debts"] as Dictionary).size(), 1, "one pair, one row")
	assert_eq(WorldPolityLedger.owed(ledger, HOUSE, RIVAL, TERM), 4, "the debtor reads the debt")
	assert_eq(WorldPolityLedger.owed(ledger, RIVAL, HOUSE, TERM), 0, "the creditor owes nothing")


func test_declare_accumulates_same_direction_lines_and_counts_opens() -> void:
	var first := InstitutionRelation.declare(WorldPolityLedger.empty(), HOUSE, RIVAL, TERM, 4)
	var second := InstitutionRelation.declare(first["ledger"] as Dictionary, HOUSE, RIVAL, TERM, 3)
	assert_eq(bool(second.get("ok", false)), true, "the second opening lands")
	assert_eq(int(second.get("periods", 0)), 7, "lines accumulate rather than replace")
	var ledger := second["ledger"] as Dictionary
	assert_eq(WorldPolityLedger.owed(ledger, HOUSE, RIVAL, TERM), 7, "and the read agrees")
	var row := (ledger["debts"] as Dictionary)[_canonical()] as Dictionary
	assert_eq(int(row.get("sequence", 0)), 2, "the second open is the second sequence")


func test_declare_refuses_a_crossed_pair_rather_than_netting() -> void:
	var first := InstitutionRelation.declare(WorldPolityLedger.empty(), HOUSE, RIVAL, TERM, 4)
	var crossed := InstitutionRelation.declare(
		first["ledger"] as Dictionary, RIVAL, HOUSE, "t_tribute", 3
	)
	assert_eq(bool(crossed.get("ok", false)), false, "the opposite direction is refused")
	assert_eq(String(crossed.get("reason", "")), "crossed_lines", "and named")
	var ledger := first["ledger"] as Dictionary
	assert_eq(WorldPolityLedger.owed(ledger, HOUSE, RIVAL, TERM), 4, "the open line is untouched")
	assert_eq(WorldPolityLedger.owed(ledger, RIVAL, HOUSE, "t_tribute"), 0, "and none opened")


func test_declare_refuses_malformed_input_before_touching_anything() -> void:
	var empty := WorldPolityLedger.empty()
	var no_pair := InstitutionRelation.declare(empty, "", RIVAL, TERM, 1)
	assert_eq(String(no_pair.get("reason", "")), "no_pair", "an empty id is no pair")
	var self_pair := InstitutionRelation.declare(empty, HOUSE, HOUSE, TERM, 1)
	assert_eq(String(self_pair.get("reason", "")), "no_pair", "nor a self pair")
	var no_term := InstitutionRelation.declare(empty, HOUSE, RIVAL, "", 1)
	assert_eq(String(no_term.get("reason", "")), "unknown_term", "an empty term names nothing")
	var zero := InstitutionRelation.declare(empty, HOUSE, RIVAL, TERM, 0)
	assert_eq(String(zero.get("reason", "")), "non_positive", "a zero count is a caller bug")
	var reserved := InstitutionRelation.declare(empty, HOUSE, RIVAL, "schism", 1)
	assert_eq(String(reserved.get("reason", "")), "reserved_term", "a stance flag is not a debt")
	var injected := InstitutionRelation.declare(empty, "t_a|t_b", RIVAL, TERM, 1)
	assert_eq(String(injected.get("reason", "")), "no_pair", "a separator-carrying id is refused")
	var injected_term := InstitutionRelation.declare(empty, HOUSE, RIVAL, "t_a->t_b", 1)
	assert_eq(String(injected_term.get("reason", "")), "unknown_term", "as is a term")


# --- the fold: rival spellings, lower sequence wins ---------------------------


func test_reverse_spellings_fold_with_the_winner_keeping_its_direction() -> void:
	# Both spellings written out by hand, never asked of `directed_key`: asking it
	# for "the other order" hands back the same string, and the case would pass
	# while proving nothing (`test_nation_symmetry.gd`'s argument, verbatim).
	var forward := "%s->%s" % [HOUSE, RIVAL]
	var reversed := "%s->%s" % [RIVAL, HOUSE]
	var payload := {
		"debts":
		{
			forward: {"debtor_id": HOUSE, "creditor_id": RIVAL, "sequence": 7, "lines": {TERM: 4}},
			reversed:
			{"debtor_id": RIVAL, "creditor_id": HOUSE, "sequence": 5, "lines": {TERM: 11}},
		}
	}
	var out := WorldPolityLedger.normalize_payload(payload)
	assert_eq((out["debts"] as Dictionary).size(), 1, "two spellings still fold to one row")
	assert_eq(
		(out["debts"] as Dictionary).has(WorldPolityLedger.directed_key(HOUSE, RIVAL)),
		true,
		"under the canonical key"
	)
	assert_eq(WorldPolityLedger.owed(out, RIVAL, HOUSE, TERM), 11, "the earlier row survives")
	assert_eq(WorldPolityLedger.owed(out, HOUSE, RIVAL, TERM), 0, "in its true direction")


# --- settle: clamps, counts, prunes -------------------------------------------


func test_settle_clamps_and_prunes_to_never_opened() -> void:
	var opened := InstitutionRelation.declare(WorldPolityLedger.empty(), HOUSE, RIVAL, TERM, 4)
	var receipt := InstitutionRelation.settle(
		opened["ledger"] as Dictionary, HOUSE, RIVAL, TERM, 99
	)
	assert_eq(bool(receipt.get("ok", false)), true, "over-settling clamps rather than refusing")
	assert_eq(int(receipt.get("settled", -1)), 4, "and returns what was actually settled")
	var ledger := receipt["ledger"] as Dictionary
	assert_eq(WorldPolityLedger.owed(ledger, HOUSE, RIVAL, TERM), 0, "nothing is owed")
	assert_eq(ledger, WorldPolityLedger.empty(), "settle-to-zero reads as never-opened")


func test_settle_answers_zero_for_nothing_and_refuses_nonsense() -> void:
	var empty := WorldPolityLedger.empty()
	var quiet := InstitutionRelation.settle(empty, HOUSE, RIVAL, TERM, 3)
	assert_eq(bool(quiet.get("ok", false)), true, "settling a never-opened line is fine")
	assert_eq(int(quiet.get("settled", -1)), 0, "and settles nothing")
	var zero := InstitutionRelation.settle(empty, HOUSE, RIVAL, TERM, 0)
	assert_eq(String(zero.get("reason", "")), "non_positive", "a zero settle is a caller bug")
	var opened := InstitutionRelation.declare(empty, HOUSE, RIVAL, TERM, 4)
	var partial := InstitutionRelation.settle(opened["ledger"] as Dictionary, HOUSE, RIVAL, TERM, 1)
	assert_eq(int(partial.get("settled", -1)), 1, "a partial settle lands")
	assert_eq(
		WorldPolityLedger.owed(partial["ledger"] as Dictionary, HOUSE, RIVAL, TERM),
		3,
		"leaving the rest open"
	)


# --- stance: schism and war reach the graph -----------------------------------


func test_a_declared_schism_reaches_the_graph_but_not_the_bare_one() -> void:
	var declared := InstitutionRelation.declare_schism(WorldPolityLedger.empty(), PARENT, HALF)
	assert_eq(bool(declared.get("ok", false)), true, "the split is recorded")
	var ledger := declared["ledger"] as Dictionary
	var a_node := RelationKey.node_key(RelationKey.KIND_SECT, HALF)
	var b_node := RelationKey.node_key(RelationKey.KIND_SECT, PARENT)
	assert_eq(RelationsApi.stance(a_node, b_node), {}, "the bare graph answers authored-only")
	var edge := RelationsApi.stance(a_node, b_node, ledger)
	assert_eq(String(edge.get("stance", "")), RelationKey.HOSTILE, "the handed graph is hostile")
	assert_eq(String(edge.get("verb", "")), "schism", "under the declared verb")
	assert_eq(String(edge.get("source", "")), "polity", "with the ledger as provenance")
	assert_eq(RelationsApi.stance(b_node, a_node, ledger), edge, "either order answers identically")
	assert_eq(
		RelationsApi.hostile_to(b_node, ledger).has(a_node),
		true,
		"and the parent names the seceding half hostile"
	)
	assert_eq(RelationsApi.hostile_to(b_node).has(a_node), false, "barely, it names nothing")


func test_a_declared_war_reconciles_back_to_silence() -> void:
	var declared := InstitutionRelation.declare_war(WorldPolityLedger.empty(), HOUSE, RIVAL)
	assert_eq(bool(declared.get("ok", false)), true, "the war is recorded")
	var ledger := declared["ledger"] as Dictionary
	var a_node := RelationKey.node_key(RelationKey.KIND_NATION, HOUSE)
	var b_node := RelationKey.node_key(RelationKey.KIND_NATION, RIVAL)
	var edge := RelationsApi.stance(a_node, b_node, ledger)
	assert_eq(String(edge.get("stance", "")), RelationKey.HOSTILE, "war reads hostile")
	assert_eq(String(edge.get("verb", "")), "war", "as a nation edge")
	var healed := InstitutionRelation.reconcile(ledger, RIVAL, HOUSE, "war")
	assert_eq(int(healed.get("settled", -1)), 1, "reconciliation closes the flag either order")
	assert_eq(
		RelationsApi.stance(a_node, b_node, healed["ledger"] as Dictionary),
		{},
		"and the pair reads as never-declared"
	)
	var again := InstitutionRelation.reconcile(healed["ledger"] as Dictionary, HOUSE, RIVAL, "war")
	assert_eq(int(again.get("settled", -1)), 0, "reconciling silence settles nothing")


func test_a_debt_term_never_becomes_a_graph_edge() -> void:
	var opened := InstitutionRelation.declare(WorldPolityLedger.empty(), HOUSE, RIVAL, TERM, 4)
	var ledger := opened["ledger"] as Dictionary
	assert_eq(
		RelationsApi.stance(
			RelationKey.node_key(RelationKey.KIND_SECT, HOUSE),
			RelationKey.node_key(RelationKey.KIND_SECT, RIVAL),
			ledger
		),
		{},
		"a debt is not a stance"
	)
	assert_eq(
		RelationsApi.stance(
			RelationKey.node_key(RelationKey.KIND_NATION, HOUSE),
			RelationKey.node_key(RelationKey.KIND_NATION, RIVAL),
			ledger
		),
		{},
		"in any namespace"
	)


# --- relations_of: debts, favour, and flags -----------------------------------


func test_relations_of_splits_what_is_owed_from_what_is_owned() -> void:
	var opened := InstitutionRelation.declare(WorldPolityLedger.empty(), HOUSE, RIVAL, TERM, 4)
	var split := InstitutionRelation.declare_schism(opened["ledger"] as Dictionary, HOUSE, RIVAL)
	var ledger := split["ledger"] as Dictionary
	var debtors_view := InstitutionRelation.relations_of(ledger, HOUSE)
	assert_eq(
		(debtors_view["owes"] as Dictionary).has(RIVAL), true, "the debtor reads what it owes"
	)
	assert_eq((debtors_view["is_owed"] as Dictionary).is_empty(), true, "and no favour")
	var creditors_view := InstitutionRelation.relations_of(ledger, RIVAL)
	assert_eq(
		(creditors_view["is_owed"] as Dictionary).has(HOUSE), true, "the creditor reads its favour"
	)
	assert_eq((creditors_view["owes"] as Dictionary).is_empty(), true, "and owes nothing")
	assert_eq((debtors_view["stances"] as Array).size(), 1, "the flag rides beside the debt")
	assert_eq(int(debtors_view.get("pairs", 0)), 1, "one counterparty, however many lines")
	assert_eq(InstitutionRelation.relations_of(ledger, ""), {}, "no id is no view")


# --- grants: named holdings, priced revocation --------------------------------


func test_grant_opens_terms_as_debt_and_escheat_costs_a_forfeit() -> void:
	var granted := InstitutionRelation.grant(
		WorldPolityLedger.empty(), HOUSE, RIVAL, NODE, {TERM: 2}
	)
	assert_eq(bool(granted.get("ok", false)), true, "the grant opens")
	var ledger := granted["ledger"] as Dictionary
	assert_eq(WorldPolityLedger.owed(ledger, RIVAL, HOUSE, TERM), 2, "the terms live as debt")
	var given := InstitutionRelation.grants_of(ledger, HOUSE)
	assert_eq((given["given"] as Array).size(), 1, "the grantor reads one grant given")
	assert_eq((given["held"] as Array).is_empty(), true, "and holds none")
	var held := InstitutionRelation.grants_of(ledger, RIVAL)
	assert_eq((held["held"] as Array).size(), 1, "the grantee reads one grant held")
	var early := InstitutionRelation.escheat(ledger, HOUSE, RIVAL, NODE)
	assert_eq(String(early.get("reason", "")), "grant_lines_open", "revoking over arrears refuses")
	var paid := InstitutionRelation.settle(ledger, RIVAL, HOUSE, TERM, 2)
	assert_eq(int(paid.get("settled", -1)), 2, "the terms settle through the debt verb")
	var revoked := InstitutionRelation.escheat(paid["ledger"] as Dictionary, HOUSE, RIVAL, NODE)
	assert_eq(bool(revoked.get("ok", false)), true, "the clean grant reverts")
	assert_eq(String(revoked.get("reverted", "")), NODE, "naming the node")
	var after := revoked["ledger"] as Dictionary
	assert_eq(int(InstitutionRelation.grants_of(after, HOUSE).get("count", -1)), 0, "it is gone")
	assert_eq(
		WorldPolityLedger.owed(after, RIVAL, HOUSE, InstitutionRelation.ESCHEAT_PRICE_TERM),
		1,
		"and the revocation cost one period"
	)
	var anew := InstitutionRelation.grant(after, HOUSE, RIVAL, NODE, {})
	assert_eq(bool(anew.get("ok", false)), true, "a reverted node grants again")


func test_grant_refusals_name_what_went_wrong() -> void:
	var empty := WorldPolityLedger.empty()
	var granted := InstitutionRelation.grant(empty, HOUSE, RIVAL, NODE, {TERM: 2})
	assert_eq(bool(granted.get("ok", false)), true, "the first grant opens")
	var ledger := granted["ledger"] as Dictionary
	var second := InstitutionRelation.grant(ledger, HOUSE, RIVAL, NODE, {TERM: 1})
	assert_eq(String(second.get("reason", "")), "grant_open", "one grant per pair and node")
	var unknown := InstitutionRelation.escheat(ledger, HOUSE, RIVAL, "t_elsewhere")
	assert_eq(String(unknown.get("reason", "")), "no_grant", "nothing open as described")
	var swapped := InstitutionRelation.escheat(ledger, RIVAL, HOUSE, NODE)
	assert_eq(String(swapped.get("reason", "")), "no_grant", "including backwards")
	var no_node := InstitutionRelation.grant(empty, HOUSE, RIVAL, "", {TERM: 1})
	assert_eq(String(no_node.get("reason", "")), "unknown_node", "a grant needs a node")
	var flagged := InstitutionRelation.grant(empty, HOUSE, RIVAL, NODE, {"schism": 1})
	assert_eq(String(flagged.get("reason", "")), "reserved_term", "grant terms are debts")
	var zeroed := InstitutionRelation.grant(empty, HOUSE, RIVAL, NODE, {TERM: 0})
	assert_eq(String(zeroed.get("reason", "")), "non_positive", "of positive counts")
	assert_eq(InstitutionRelation.grants_of(ledger, ""), {}, "no id holds no grants")


# --- the save round trip and the corrupt save ---------------------------------


func test_the_json_hop_keeps_debts_stances_and_grants() -> void:
	var opened := InstitutionRelation.declare(WorldPolityLedger.empty(), HOUSE, RIVAL, TERM, 4)
	var split := InstitutionRelation.declare_schism(opened["ledger"] as Dictionary, PARENT, HALF)
	# The grant rides the schism pair, whose row holds no debt yet: grant terms flow
	# grantee-to-grantor, so granting onto a pair that already owes the other way
	# is crossed_lines (settle first), not a second row.
	var granted := InstitutionRelation.grant(
		split["ledger"] as Dictionary, PARENT, HALF, NODE, {"t_tribute": 2}
	)
	var ledger := granted["ledger"] as Dictionary
	var reparsed: Variant = JSON.parse_string(JSON.stringify(WorldPolityLedger.to_dict(ledger)))
	assert_eq(reparsed is Dictionary, true, "the hop parses")
	var restored := WorldPolityLedger.normalize_payload(reparsed as Dictionary)
	assert_eq(WorldPolityLedger.owed(restored, HOUSE, RIVAL, TERM), 4, "the debt survives")
	assert_eq(
		(InstitutionRelation.relations_of(restored, HALF)["stances"] as Array).size(),
		1,
		"the flag survives"
	)
	assert_eq(int(InstitutionRelation.grants_of(restored, PARENT).get("count", 0)), 1, "the grant")
	assert_eq(
		WorldPolityLedger.owed(restored, HALF, PARENT, "t_tribute"), 2, "and its terms survive"
	)


func test_a_corrupt_payload_reads_empty_never_partial() -> void:
	var shapeless := WorldPolityLedger.normalize_payload({"debts": "not a map", "grants": [1, 2]})
	assert_eq((shapeless["debts"] as Dictionary).is_empty(), true, "a malformed debts is empty")
	assert_eq((shapeless["grants"] as Dictionary).is_empty(), true, "and so is grants")
	var rows := {
		"no_arrow_here": {"lines": {TERM: 3}},
		"t_house->t_house": {"lines": {TERM: 3}},
		"t_a->t_b|c": {"lines": {TERM: 3}},
		42: {"lines": {TERM: 3}},
	}
	var dropped := WorldPolityLedger.normalize_payload({"debts": rows})
	assert_eq((dropped["debts"] as Dictionary).is_empty(), true, "unreadable keys are dropped")
	var grants := {
		"nokey": {"lines": {TERM: 1}},
		"t_house->t_rival_house#": {"lines": {TERM: 1}},
		"t_house->t_rival_house#t_n#t_m": {"lines": {TERM: 1}},
		"t_house->t_rival_house#t_plain": 42,
	}
	var gempty := WorldPolityLedger.normalize_payload({"grants": grants})
	assert_eq((gempty["grants"] as Dictionary).is_empty(), true, "unreadable grants are dropped")


# --- the actor boundary, as code ----------------------------------------------


func test_an_actor_shaped_id_is_the_callers_decision_not_the_ledgers() -> void:
	# `PERSON` carries no key syntax, so the pair rule accepts it: the ledger has no
	# actor registry and cannot tell it from an institution. The refusal shapes above
	# (separator-carrying ids) are what the ledger itself can enforce, and the source
	# scan below is what keeps it from ever naming an actor.
	var receipt := InstitutionRelation.declare(WorldPolityLedger.empty(), HOUSE, PERSON, TERM, 1)
	assert_eq(bool(receipt.get("ok", false)), true, "the pair rule is structural, not identity")
	assert_eq(
		WorldPolityLedger.owed(receipt["ledger"] as Dictionary, HOUSE, PERSON, TERM),
		1,
		"and reads back mechanically"
	)


func test_core_names_no_module_and_no_actor() -> void:
	# `tools arch` holds `core/` to `{"core", "contracts"}`, and it reads `res://` and
	# `extends` as real edges — so the mechanical half is that this file declares
	# neither. What it CANNOT see is a bare module class name, which is why the
	# second half is here: a test that reads the source and fails on one.
	var source := _code_only(
		FileAccess.get_file_as_string("res://src/core/institution_relation.gd")
	)
	assert_eq(source.contains("res://"), false, "core/ declares no res:// path")
	for module_name in [
		"SectApi",
		"SectState",
		"NationApi",
		"NationState",
		"ClanApi",
		"SaveApi",
		"SaveSlot",
		"Actor",
		"get_node"
	]:
		assert_eq(
			source.contains(module_name),
			false,
			"core/ names no %s (the checker cannot see a bare reference; this can)" % module_name
		)


## `source` with every comment line removed, so a guard reads CODE and never the prose
## describing what the code must not do.
func _code_only(source: String) -> String:
	var out: PackedStringArray = []
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)
