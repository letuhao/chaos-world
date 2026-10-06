extends TestCase

## The stat ledger (DRAFT): the single row list of every stat id — its layer, its principle,
## its owners and their weights.
##
## ## What this test is FOR
##
## The ledger is the census the design sessions of 2026-10-07 produced: 15 primaries
## (3 paths x 5 principles), the L0 channels they own at weights, and the L2/L3/L4/L5
## rows owned by other layers. This test is its checker, not the game's gate:
##
## 1. shape — exactly 15 primaries, one per path x principle; every row well formed;
## 2. weights — every owner-bearing row sums to 1 and every owner shares the channel's
##    principle (the column rule: a channel belongs to ONE principle);
## 3. reconciliation — every id the live vocabulary already exposes (the presenter table,
##    `CombatStats.ALL_IDS`, `Stat.RATE_STATS`, `Stat.BASE_ATTRIBUTES`) has a row. The
##    presenter table is itself reconciled against the live surface by its own suite, so
##    chaining the two checks gives ledger <-> live without a second walk;
## 4. the distribution report — printed, never asserted: the weight rounds are read from
##    it, and its NUMBERS are placeholders until the impact census and play data land
##    (the DEF-0344 discipline: ship the structure, move the values with evidence).

const LEDGER := "res://src/contracts/stat_ledger.json"
const STATUSES: Array[String] = ["exists", "new", "legacy"]
const LAYERS: Array[String] = ["L0", "L1", "L2", "L3", "L4", "L5", "L1-old"]
const PRINCIPLES: Array[String] = ["sinh", "phat", "tang", "luyen", "luu"]
const PATHS: Array[String] = ["body", "qi", "mind"]


func _ledger() -> Dictionary:
	var text := FileAccess.get_file_as_string(LEDGER)
	assert_ne(text.is_empty(), true, "the ledger file exists and is readable")
	var parsed: Variant = JSON.parse_string(text)
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "and parses as JSON")
	return {} if not (parsed is Dictionary) else parsed


func _rows(ledger: Dictionary) -> Array:
	return ledger.get("rows", []) as Array


func _primaries(ledger: Dictionary) -> Array:
	return ledger.get("primaries", []) as Array


func _principle_of(ledger: Dictionary) -> Dictionary:
	var out := {}
	for entry in _primaries(ledger):
		var row: Dictionary = entry
		out[String(row.get("id", ""))] = String(row.get("principle", ""))
	return out


# --- shape ----------------------------------------------------------------------


func test_the_fifteen_primaries_are_three_paths_of_five() -> void:
	var primaries := _primaries(_ledger())
	assert_eq(primaries.size(), 15, "exactly 15 primaries")
	var ids := {}
	var by_path := {}
	var by_path_principle := {}
	for entry in primaries:
		var row: Dictionary = entry
		var id := String(row.get("id", ""))
		var path := String(row.get("path", ""))
		var principle := String(row.get("principle", ""))
		assert_ne(id, "", "every primary has an id")
		assert_eq(ids.has(id), false, "%s is unique" % id)
		ids[id] = true
		assert_eq(PATHS.has(path), true, "%s names a real path (%s)" % [id, path])
		assert_eq(PRINCIPLES.has(principle), true, "%s names a real principle (%s)" % [id, principle])
		by_path[path] = int(by_path.get(path, 0)) + 1
		by_path_principle["%s/%s" % [path, principle]] = true
	assert_eq(by_path.size(), 3, "three paths")
	for path in PATHS:
		assert_eq(int(by_path.get(path, 0)), 5, "%s has five primaries" % path)
	assert_eq(by_path_principle.size(), 15, "every path x principle pair exists exactly once")


func test_every_row_is_well_formed() -> void:
	var ledger := _ledger()
	var seen := {}
	for entry in _rows(ledger):
		var row: Dictionary = entry
		var id := String(row.get("id", ""))
		assert_ne(id, "", "every row has an id")
		assert_eq(seen.has(id), false, "%s appears once" % id)
		seen[id] = true
		var status := String(row.get("status", ""))
		assert_eq(STATUSES.has(status), true, "%s has a known status (%s)" % [id, status])
		var layer := String(row.get("layer", ""))
		assert_eq(LAYERS.has(layer), true, "%s has a known layer (%s)" % [id, layer])


func test_channel_weights_are_normalized_and_one_principle() -> void:
	var ledger := _ledger()
	var principle_of := _principle_of(ledger)
	for entry in _rows(ledger):
		var row: Dictionary = entry
		var owners: Dictionary = row.get("owners", {}) as Dictionary
		if owners.is_empty():
			continue
		var id := String(row.get("id", ""))
		var principle := String(row.get("principle", ""))
		assert_ne(principle, "", "%s declares its principle" % id)
		var total := 0.0
		for cell in owners.keys():
			var owner := String(cell)
			total += float(owners[cell])
			assert_eq(principle_of.has(owner), true, "%s names a real cell (%s)" % [id, owner])
			assert_eq(
				String(principle_of.get(owner, "")) == principle,
				true,
				"%s: owner %s must share the channel's principle" % [id, owner]
			)
		assert_almost_eq(total, 1.0, "%s: weights sum to 1" % id)


# --- reconciliation against the live vocabulary ---------------------------------


## Ledger must cover everything the game already exposes. THREE live lists, each of which
## already reconciles itself against the running tree, so this chains to the live surface:
## the presenter's table (its own suite walks all three paths), the combat-owned rate ids,
## and the contract's rate registration. A live id with no row fails here, by name.
func test_every_live_vocabulary_id_has_a_row() -> void:
	var ledger := _ledger()
	var known := {}
	for entry in _rows(ledger):
		known[String((entry as Dictionary).get("id", ""))] = true
	var missing: Array[String] = []
	for id in StatPresenter.known_ids():
		if not known.has(String(id)):
			missing.append(String(id))
	for id in CombatStats.ALL_IDS:
		if not known.has(String(id)):
			missing.append(String(id))
	for id in Stat.RATE_STATS:
		if not known.has(String(id)):
			missing.append(String(id))
	for id in Stat.BASE_ATTRIBUTES:
		if not known.has(String(id)):
			missing.append(String(id))
	assert_eq(missing, [], "these live ids have no ledger row: %s" % ", ".join(missing))


# --- the distribution report ----------------------------------------------------


## The numbers the weight rounds are read from. NOT asserted, like the cross-mechanism
## balance table: the report is measured and printed; only the shape above is gated.
func test_the_distribution_report() -> void:
	var ledger := _ledger()
	var totals := {}
	var path_of := {}
	var principle_of := {}
	for entry in _primaries(ledger):
		var row: Dictionary = entry
		var id := String(row.get("id", ""))
		totals[id] = 0.0
		path_of[id] = String(row.get("path", ""))
		principle_of[id] = String(row.get("principle", ""))
	var principle_totals := {}
	var domain_totals := {}
	for entry in _rows(ledger):
		var row: Dictionary = entry
		var owners: Dictionary = row.get("owners", {}) as Dictionary
		var domain := String(row.get("domain", "other"))
		for cell in owners.keys():
			var owner := String(cell)
			var weight := float(owners[cell])
			totals[owner] = float(totals.get(owner, 0.0)) + weight
			principle_totals[principle_of[owner]] = (
				float(principle_totals.get(principle_of[owner], 0.0)) + weight
			)
			domain_totals[domain] = float(domain_totals.get(domain, 0.0)) + weight
	var grand := 0.0
	for value in totals.values():
		grand += float(value)
	print("")
	print("=== STAT LEDGER DISTRIBUTION (draft; weights are placeholders) ==========")
	for path in PATHS:
		var path_total := 0.0
		for id in totals.keys():
			if String(path_of.get(id, "")) == path:
				path_total += float(totals[id])
		print("--- %s: %.2f weighted channels ---" % [path, path_total])
		for id in totals.keys():
			if String(path_of.get(id, "")) != path:
				continue
			print(
				(
					"%-18s %6.2f   %5.1f%% of path   %5.1f%% of all"
					% [
						id,
						float(totals[id]),
						100.0 * float(totals[id]) / maxf(path_total, 0.001),
						100.0 * float(totals[id]) / maxf(grand, 0.001)
					]
				)
			)
	print("--- principles ---")
	for principle in PRINCIPLES:
		print(
			(
				"%-8s %6.2f   %5.1f%%"
				% [
					principle,
					float(principle_totals.get(principle, 0.0)),
					100.0 * float(principle_totals.get(principle, 0.0)) / maxf(grand, 0.001)
				]
			)
		)
	print("--- domains ---")
	for domain in domain_totals.keys():
		print("%-12s %6.2f" % [domain, float(domain_totals[domain])])
	var lowest := 999.0
	var highest := 0.0
	for id in totals.keys():
		lowest = minf(lowest, float(totals[id]))
		highest = maxf(highest, float(totals[id]))
	print(
		(
			"spread: lowest %s  highest %s  ratio %sx"
			% [
				str(lowest),
				str(highest),
				"%.2f" % (highest / maxf(lowest, 0.001))
			]
		)
	)
	print("")
	assert_eq(grand > 0.0, true, "the report has weight to show")
