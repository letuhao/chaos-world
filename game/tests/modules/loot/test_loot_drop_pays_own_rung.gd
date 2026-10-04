extends TestCase

## ADR 0166 decision 1, asserted BEHAVIOURALLY: a drop realizes at its own item's
## authored rung, so the band stops paying magnitude.
##
## `tools/cultivation/loot_magnitude.py` cannot guard this. Its `payments()` derives a
## paid rung by WALKING authored placement — `realm = table_realm(...) or realm` down
## the nesting chain from the band — and never reads `loot_rewards.gd`. So `check` reports
## the same 6307 mis-paying entries whether the seam is present or not, which makes it
## blind to the very thing ADR 0166 changed. `test_loot_band_magnitude_ruling.gd` closes
## that from the source side; this closes it from the VALUE side, so a second seam, a
## renamed copy, or a re-introduced assignment somewhere other than `contextualize`
## fails here on the number rather than on a pattern.
##
## The corpus facts this rests on, all read from shipped data:
## - `A26_immortal_auditroll_daybook` is authored `golden_immortal`, is `rollable`
##   (`roll_spec` count 4), and ships in `data/items/key/`.
## - `qi_refining` is a real rung well below it (`item_magnitude_scale.json` 1.00x vs
##   `golden_immortal` 3.60x), so a band there is a large, measurable substitution.
##
## Loop safety: no loop of any kind. Every assertion reads one shipped definition, so
## there is no bound to grow and nothing to cap.

## A real, shipped, ROLLABLE item and a band realm that is genuinely not its own. The
## seam is only observable on a rollable item: a non-rollable one skips `contextualize`
## entirely (`LootRewards._drop` guards on `def.is_rollable()`), so a probe built on one
## would pass with the seam present and prove nothing.
const PROBE_ITEM := &"A26_immortal_auditroll_daybook"
const AUTHORED_REALM := &"golden_immortal"
const FOREIGN_BAND := &"qi_refining"


func _probe_def() -> ItemDef:
	return LootContent.instance().definition(PROBE_ITEM)


## The seam itself: a drop context carrying a FOREIGN realm must not move the
## definition's realm. With `copy.realm = realm` restored this returns `qi_refining` and
## this fails on the value — which is the whole proof that the change is not vacuous.
func test_a_foreign_realm_context_leaves_the_items_realm_alone() -> void:
	var def := _probe_def()
	assert_ne(def, null, "the probe item %s is defined" % PROBE_ITEM)
	assert_eq(def.is_rollable(), true, "and is rollable, so the seam is reachable")
	assert_eq(String(def.realm), String(AUTHORED_REALM), "and is authored at %s" % AUTHORED_REALM)
	assert_ne(String(FOREIGN_BAND), String(def.realm), "the band realm is genuinely foreign")
	var contextual := LootRewards.contextualize(def, FOREIGN_BAND, def.rarity)
	assert_eq(
		String(contextual.realm),
		String(AUTHORED_REALM),
		"a %s band context leaves a %s item at %s" % [FOREIGN_BAND, PROBE_ITEM, AUTHORED_REALM]
	)


## The band keeps what the ADR says it owns. Rarity is the one axis `contextualize` is
## still allowed to override, so a narrowing that dropped rarity too would pass the test
## above and silently remove the band's only remaining expression of difficulty.
func test_rarity_is_still_the_bands_to_override() -> void:
	var def := _probe_def()
	assert_ne(def, null, "the probe item is defined")
	var narrowed: StringName = ItemRarity.ALL[maxi(0, ItemRarity.tier(def.rarity) - 3)]
	var contextual := LootRewards.contextualize(def, FOREIGN_BAND, narrowed)
	assert_eq(
		String(contextual.rarity),
		String(narrowed),
		"rarity still follows the drop context (%s -> %s)" % [def.rarity, narrowed]
	)


## End to end through the real realization path, so the assertion is on the instance a
## player receives rather than on the copy. `LootRewards._drop` sets `realized.realm`
## from the plan (the band) and then, for a rollable item, REPLACES the instance with
## `ItemGenerator.generate(contextual, ...)`, which takes `def.realm`. With the seam
## present the instance comes back at `qi_refining`; with it gone, at `golden_immortal`.
func test_a_realized_drop_reports_the_items_own_realm() -> void:
	var def := _probe_def()
	assert_ne(def, null, "the probe item is defined")
	var plan := {
		"entry_id": "probe_entry",
		"table_id": "probe_table",
		"def_id": String(def.id),
		"quantity": 1,
		"rarity": String(def.rarity),
		"realm": String(FOREIGN_BAND),
	}
	var payload := LootRewards.build(
		"probe_encounter", &"probe_boss", &"probe_domain", null, null, [plan], 12345
	)
	var drops: Array = payload.get("drops", [])
	assert_eq(drops.size(), 1, "the probe realized exactly one drop")
	var drop: Dictionary = drops[0]
	assert_eq(
		String(drop.get("realm", "")),
		String(AUTHORED_REALM),
		"the realized drop pays %s, not the %s band" % [AUTHORED_REALM, FOREIGN_BAND]
	)
	# Deliberately NOT asserted: that the probe rolled a nonzero number of options. That
	# is `OptionCatalog` content for this (rarity, realm) pair, not a property of the
	# seam, so asserting it here would make this suite a test of the catalogue and it
	# would fail for an unrelated content wave. The magnitude path is pinned instead by
	# `test_the_item_def_is_the_magnitude_authority` (which reads `def.realm` at the
	# `OptionCatalog` call) and by `def.is_rollable()` above, which is the condition
	# `LootRewards._drop` gates the seam behind.


## The mirrored direction: the band must not RAISE a drop either. `R25_mortal_plover_clasp`
## is the case ADR 0166 names — authored `qi_refining` and paid `primordial_origin` at
## 3.90x — and a "floor" reading of the same idea would let the band hand out loot scaled
## ABOVE its authored magnitude, which `chain.py:700` names as the hazard. Asserted as a
## property of the seam rather than of one item, so it holds for any authored rung.
func test_the_band_can_never_raise_a_drop_above_its_authored_magnitude() -> void:
	var def := _probe_def()
	assert_ne(def, null, "the probe item is defined")
	var authored := String(def.realm)
	# Every rung the scale carries, so this is the whole ladder and not one hand-picked
	# rung: `ItemRarity.ALL` and the ladder are both finite snapshots taken here.
	var bands := [
		&"mortal",
		&"qi_refining",
		&"foundation",
		&"core_formation",
		&"nascent_soul",
		&"earth_immortal",
		&"golden_immortal",
		&"primordial_origin",
	]
	# Snapshot the bound BEFORE the loop: `bands` is a literal and the body only calls
	# `contextualize`, which duplicates a definition and never touches `bands`.
	for band in bands:
		var contextual := LootRewards.contextualize(def, band, def.rarity)
		assert_eq(
			String(contextual.realm),
			authored,
			"band %s leaves the item at %s, raised or lowered" % [band, authored]
		)
