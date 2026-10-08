extends TestCase

## DEF-0385: the rapid (right-click) art family ships one art per element, and every
## field that makes the class what it is is AUTHORED on the art — the slot model stays
## "learn many, equip one", so the roster is content and the slot is the limit.
##
## The contract the ruling names, asserted per element: share 1.0 (pure elemental, so a
## build spams its OWN element), magnitude
## `BARE_SWING_MAGNITUDE * ANCHOR_BLOW_SCALE / 12`, cooldown 0.2 (the fight loop clamps
## at 5 hits/s), a small stamina cost (nothing is free), and a manual whose own source is
## a terminal route (a domain the graph can reach).

## `2.0 * (1 / 5.6) / 12`, evaluated: the census's arena twin and this family must agree
## on one number, and a retune of `BARE_SWING_MAGNITUDE` or `ANCHOR_BLOW_SCALE` moves
## both — this pin is the canary for it.
const EXPECTED_MAGNITUDE := 0.029762
## The clamp the loop enforces, read off the loop so the two cannot drift.
const RAPID_COOLDOWN := FightLoop.MIN_RAPID_INTERVAL
## What "small" means for the per-hit price: cheap enough to be the basic attack, never
## zero (AGENTS.md: a verb that spends neither a resource nor time is a missing mechanic).
const MAX_RAPID_STAMINA := 5.0


func test_every_element_ships_its_rapid_art() -> void:
	for entry in ElementDefaults.all():
		var def := entry as ElementDef
		var art := load("res://data/techniques/qi_%s_rapid.tres" % def.id) as TechniqueDef
		assert_ne(art, null, "%s ships a rapid art" % def.id)
		assert_eq(art.rapid, true, "%s is the rapid class" % def.id)
		assert_eq(art.active, true, "and it is an active art")
		assert_eq(art.element, def.id, "carrying its own element")
		assert_eq(art.path, PathState.QI, "on the qi path the loop casts from")
		assert_almost_eq(art.element_share, 1.0, "pure elemental", 1e-9)
		assert_almost_eq(art.magnitude, EXPECTED_MAGNITUDE, "the 1/12 magnitude", 1e-6)
		assert_almost_eq(art.cooldown, RAPID_COOLDOWN, "the clamp's own interval", 1e-9)
		assert_eq(
			art.stamina_cost > 0.0 and art.stamina_cost <= MAX_RAPID_STAMINA,
			true,
			"%s pays a small stamina cost, never nothing" % def.id
		)


func test_every_rapid_art_is_learnable_where_its_element_opens() -> void:
	# `min_path_realm` is a 1-BASED ladder realm number (the content contract enforces
	# `1..29`; the gate compares it against the actor's realm number). This pins each art
	# at the realm its element opens at — the strongest form of DEF-0385's "reachable
	# early" — and it is the canary for the gate's base: the first generation shipped
	# `0/9/18` and the contract refused the zero.
	var opening := {1: &"qi_refining", 2: &"spirit_condensation", 3: &"earth_immortal"}
	for entry in ElementDefaults.all():
		var def := entry as ElementDef
		var art := load("res://data/techniques/qi_%s_rapid.tres" % def.id) as TechniqueDef
		var required := int(art.min_path_realm.get(PathState.QI, 0))
		var realm_number := RealmDefaults.ladder().index_of(opening[maxi(1, def.tier)]) + 1
		assert_eq(
			required <= realm_number,
			true,
			(
				"%s is learnable where its element opens (needs realm %d, the opening is %d)"
				% [def.id, required, realm_number]
			)
		)


func test_every_rapid_art_is_delivered_by_its_manual_with_a_terminal_source() -> void:
	for entry in ElementDefaults.all():
		var def := entry as ElementDef
		var art := load("res://data/techniques/qi_%s_rapid.tres" % def.id) as TechniqueDef
		assert_ne(art.delivered_by, &"", "%s names its manual" % def.id)
		var manual := load("res://data/items/technique/%s.tres" % art.delivered_by) as ItemDef
		assert_ne(manual, null, "%s exists as an item" % art.delivered_by)
		assert_eq(manual.category, &"technique", "and it is the technique family's manual kind")
		var terminal := false
		for source in manual.sources:
			var text := String(source)
			if (
				text.begins_with("domain:")
				or text.begins_with("boss:")
				or text.begins_with("gather:")
			):
				terminal = true
		assert_eq(terminal, true, "%s declares a terminal route a player can walk" % manual.id)
