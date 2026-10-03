extends TestCase

## THE BODY PATH'S REWARDS ARE OBSERVABLE (ADR 0028, ADR 0043).
##
## The defect this file exists to close was an absence, and an absence has no
## failing assertion: a body stat that no screen renders leaves every suite green.
## Measured on the shipped hero before this work, `ActorStats.derived_all()`
## carried `body_cultivation_power`, `carry_capacity` and `regeneration` at 0.0 and
## carried NO KEY AT ALL for `bone_density`, `muscle_fiber` and
## `organ_vitality` — and those three are what a breakthrough actually pays. All
## 22 authored body realm seeds grant `physique` plus one of them at 1.0, and
## `BodyAdvancement` pays it with `set_base(get_base(id) + seed.rewards[id])`.
## So the game's central reward landed on numbers with no row anywhere.
##
## These guards are written to fail on that class of defect, not merely to pass on
## the present shape:
##
##  1. the panel's row set is reconciled against `BodyStats` itself, so a dropped
##     or misspelled id fails BY NAME instead of quietly rendering one row fewer;
##  2. every rendered value is compared against `ActorStats.derived()` on the live
##     actor, so a hard-coded constant or a value cached before training fails;
##  3. a stat the body does not carry is asserted ABSENT, so substituting 0.0 to
##     make a row render fails.
##
## Every reward applied here comes from authored seed data read through
## `BodyRealmSeed`, never from a literal written into this file.

const SCREEN := "res://src/ui/screens/body_cultivation_panel.tscn"
const GROWTH := "res://src/ui/panels/body_growth_panel.tscn"

## The three base attributes a breakthrough reward pays. Read from the module, not
## restated: this file's job is to reconcile two lists, and restating either one
## here is how they would drift apart silently.
const REWARDED_ATTRIBUTES := [
	BodyStats.BONE_DENSITY, BodyStats.MUSCLE_FIBER, BodyStats.ORGAN_VITALITY
]


func _screen() -> BodyCultivationPanel:
	var screen := (load(SCREEN) as PackedScene).instantiate() as BodyCultivationPanel
	assert_ne(screen, null, "body_cultivation_panel.tscn roots a BodyCultivationPanel")
	return screen


func _growth() -> BodyGrowthPanel:
	var panel := (load(GROWTH) as PackedScene).instantiate() as BodyGrowthPanel
	assert_ne(panel, null, "body_growth_panel.tscn roots a BodyGrowthPanel")
	return panel


func _actor() -> Actor:
	var actor := ActorFactory.with_body_cultivation(
		Actor.new(&"growth_hero", {Stat.PHYSIQUE: 20.0})
	)
	ItemsApi.attach(actor)
	BodyTraining.synchronize(actor)
	return actor


## Pay EVERY reward any authored body realm seed grants, exactly the way
## `BodyAdvancement` pays one (`advancement.gd`):
##
##     for key in seed.rewards:
##         actor.stats.set_base(id, actor.stats.get_base(id) + float(seed.rewards[key]))
##
## Unioned over the whole ladder rather than hand-picked, so the fixture cannot
## quietly stop covering an attribute if a seed's rewards are rebalanced — and so
## this file never has to name which seed pays what.
func _pay_every_authored_reward(actor: Actor) -> void:
	var ladder := RealmDefaults.ladder()
	for realm in ladder.realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		for key in seed.rewards:
			var id := StringName(key)
			actor.stats.set_base(id, actor.stats.get_base(id) + float(seed.rewards[key]))
	actor.mark_stats_dirty()


## The module's own answer to "which stats does the body path own", so the panel's
## literals are checked against the module rather than against a second copy.
func _body_stat_ids() -> Array:
	return [
		String(BodyStats.BONE_DENSITY),
		String(BodyStats.MUSCLE_FIBER),
		String(BodyStats.ORGAN_VITALITY),
		String(BodyStats.CARRY_CAPACITY),
		String(BodyStats.BODY_CULTIVATION_POWER),
		String(BodyStats.REGENERATION),
	]


func _row(summary: Dictionary, id: String) -> Dictionary:
	for row in summary.get("rows", []):
		if String((row as Dictionary).get("id", "")) == id:
			return row
	return {}


# --- 1. the row set is reconciled against the module -------------------------


## The panel declares its ids as literals, because `ui/` may not name `BodyStats`.
## This is what stops that duplication from becoming drift: the expected list is
## read from the module, so deleting a row — or misspelling one — fails here by
## name rather than leaving a silently shorter panel forever.
func test_the_growth_rows_are_exactly_the_body_paths_own_stat_ids() -> void:
	var panel := _growth()
	assert_eq(panel.row_ids(), _body_stat_ids(), "the row set matches BodyStats, in order")
	panel.free()


## A stat the module publishes and no row shows is the defect this whole file
## exists for, so it is asserted from the module's side: every stat in the list
## above must be a row, and every row must be one of them.
func test_no_body_stat_is_missing_from_the_panel() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var growth := screen.summary().get("growth", {}) as Dictionary
	assert_eq(growth.is_empty(), false, "the growth panel is bound and populated")
	for id in _body_stat_ids():
		assert_eq(
			_row(growth, id).is_empty(),
			false,
			"BodyStats.%s has no row on the body screen, so training it is unobservable" % id
		)
	assert_eq(
		int(growth.get("total", 0)),
		_body_stat_ids().size(),
		"and the panel declares no row the module does not own"
	)
	screen.free()


# --- 2. the rendered value is the stat the module derives --------------------


## Every row shows the value `ActorStats` resolves right now, read off the live
## actor. A hard-coded constant, a stale cache captured at `_ready()`, or a value
## recomputed by the panel instead of read all fail here.
func test_every_row_shows_the_stat_the_module_derives() -> void:
	var actor := _actor()
	# A hero mid-ladder carries every id: the three attributes are absent until a
	# reward pays them, and the derived magnitudes move with them.
	_pay_every_authored_reward(actor)
	var screen := _screen()
	screen.setup(actor)
	var growth := screen.summary().get("growth", {}) as Dictionary
	for id in _body_stat_ids():
		var row := _row(growth, id)
		assert_eq(bool(row.get("earned", false)), true, "%s is a stat this body carries" % id)
		assert_almost_eq(
			float(row.get("value", 0.0)),
			actor.stats.derived(StringName(id)),
			"the row for %s shows the stat the module derives, not a number of its own" % id
		)
	screen.free()


## The same claim, through the mounted screen, after the value has MOVED since the
## screen was first rendered. This is the half a value-equality test at a single
## instant cannot catch: a panel that computed its rows once and cached them would
## still pass the test above and fail this one.
func test_a_reward_moves_the_row_the_player_is_looking_at() -> void:
	var actor := _actor()
	var screen := _screen()
	screen.setup(actor)
	var before := _row(
		screen.summary().get("growth", {}) as Dictionary, String(BodyStats.ORGAN_VITALITY)
	)
	assert_eq(
		bool(before.get("earned", false)),
		false,
		"a fresh hero carries no organ vitality: there is no such row to move yet"
	)
	# The reward, applied as `BodyAdvancement` applies it.
	_pay_every_authored_reward(actor)
	screen.refresh()
	var after := _row(
		screen.summary().get("growth", {}) as Dictionary, String(BodyStats.ORGAN_VITALITY)
	)
	assert_eq(
		bool(after.get("earned", false)),
		true,
		"the breakthrough reward makes the stat exist, and the row now shows it"
	)
	assert_almost_eq(
		float(after.get("value", 0.0)),
		actor.stats.derived(BodyStats.ORGAN_VITALITY),
		"and it shows the value the reward actually produced"
	)
	# The consequence is real, not cosmetic: the derived magnitudes moved with it.
	assert_eq(
		float(actor.stats.derived(BodyStats.REGENERATION)) > 0.0,
		true,
		"the reward moved a derived stat the panel also renders"
	)
	assert_almost_eq(
		float(_row(screen.summary()["growth"], String(BodyStats.REGENERATION)).get("value", 0.0)),
		actor.stats.derived(BodyStats.REGENERATION),
		"so the row for it moved too"
	)
	screen.free()


## The row set is pinned to AUTHORED content, not to taste. Every stat the panel
## shows as a paid attribute must actually be paid by some realm seed, and at least
## one must be — otherwise the panel is showing inputs dressed as rewards, and the
## "a player can see what training produced" claim is empty.
func test_the_paid_attribute_rows_are_the_ones_the_seeds_pay() -> void:
	var paid := {}
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		for key in seed.rewards:
			paid[StringName(key)] = true
	for id in REWARDED_ATTRIBUTES:
		assert_eq(
			paid.has(id),
			true,
			"%s is a row on the screen, so some realm seed must pay it" % String(id)
		)
	var shown := _growth().row_ids()
	var overlap := 0
	for id in shown:
		if paid.has(StringName(id)):
			overlap += 1
	_growth().free()
	assert_eq(
		overlap > 0,
		true,
		"at least one row the player sees is a number a breakthrough pays, not a derived echo"
	)


# --- 3. an absent stat is absent, never zero ---------------------------------


## The defect a "helpful" default creates. `bone_density`, `muscle_fiber` and
## `organ_vitality` have no base on a fresh hero, so `derived_all()` has no key for
## them at all. Substituting `0.0` for a missing key would render a measurement the
## body never had — and, worse, would make a paid reward indistinguishable from a
## stat that simply never moves. The row must say it is not there.
func test_a_stat_the_body_does_not_carry_is_reported_absent_not_zero() -> void:
	var actor := _actor()
	var surface := actor.stats.derived_all()
	var screen := _screen()
	screen.setup(actor)
	var growth := screen.summary().get("growth", {}) as Dictionary
	var absent := 0
	for id in REWARDED_ATTRIBUTES:
		var key := String(id)
		if surface.has(key):
			continue
		absent += 1
		var row := _row(growth, key)
		assert_eq(
			bool(row.get("earned", false)),
			false,
			"%s is absent from the stat surface, so its row must not claim a value" % key
		)
		assert_ne(
			String(row.get("text", "")),
			"",
			"and it must say something rather than render a blank line"
		)
	_growth_row_texts_name_the_absence(screen)
	assert_eq(
		absent > 0,
		true,
		"a fresh hero really does lack these attributes, so this guard is not vacuous"
	)
	screen.free()


## The wording, asserted directly: an unearned row names its absence and shows no
## number at all, because there is no number to show.
func _growth_row_texts_name_the_absence(screen: BodyCultivationPanel) -> void:
	var growth := screen.summary().get("growth", {}) as Dictionary
	for row in growth.get("rows", []):
		var entry := row as Dictionary
		if bool(entry.get("earned", true)):
			continue
		var text := String(entry.get("text", ""))
		assert_eq(text.contains("not yet gained"), true, "an unearned row says so: %s" % text)
		assert_eq(
			_is_number(text),
			false,
			"and prints no figure at all, because the body has none: %s" % text
		)


## Whether a line ends in a bare number. Crude on purpose: it only has to notice a
## substituted 0.0, and it must not be fooled by the label's own words.
func _is_number(text: String) -> bool:
	var parts := text.split(" ")
	return parts.size() > 1 and parts[parts.size() - 1].is_valid_float()


# --- the acupoint ids are observable too, on the row above --------------------


## The other half of the body path's stat surface, and the reason the growth panel
## does not duplicate it. `acupoint_quality` and `acupoint_blocked_count` are the
## same value the vitals row already prints, so adding rows for them would render
## one number twice. That is only legitimate while the row really does mirror the
## stat — which is what this asserts, and it fails the moment it stops.
##
## `acupoint_count` is `open_count()` while the vitals row prints the TOTAL, so the
## two diverge the moment a deviation jams a huyệt; total >= open is the invariant.
func test_the_acupoint_stats_are_observable_on_the_vitals_row() -> void:
	var actor := _actor()
	var screen := _screen()
	screen.setup(actor)
	var vitals := screen.summary().get("vitals", {}) as Dictionary
	assert_almost_eq(
		float(vitals.get("average_quality", -1.0)),
		actor.stats.derived(BodyStats.ACUPOINT_QUALITY),
		"the vitals row's quality IS acupoint_quality, at the module's precision"
	)
	assert_almost_eq(
		float(vitals.get("blocked", -1.0)),
		actor.stats.derived(BodyStats.ACUPOINT_BLOCKED_COUNT),
		"and its jammed count IS acupoint_blocked_count"
	)
	var points: AcupointSet = actor.component(&"acupoints")
	assert_ne(points, null, "the hero carries a huyệt set")
	if points != null:
		assert_eq(
			float(actor.stats.derived(BodyStats.ACUPOINT_COUNT)),
			float(points.open_count()),
			"acupoint_count is the OPEN count"
		)
		assert_eq(
			int(vitals.get("acupoints", 0)) >= float(actor.stats.derived(BodyStats.ACUPOINT_COUNT)),
			true,
			"and the row prints the total, so a jammed huyệt is legible as the difference"
		)
	screen.free()


# --- the screen contract ------------------------------------------------------


## The growth panel is nested under the screen's summary under its own key, with
## the child's own summary inside it — the shape every screen in `ui/` publishes.
func test_the_growth_panel_is_nested_under_the_screen_summary() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var view := screen.summary()
	assert_eq(view.has("growth"), true, "the child panel summary is nested under 'growth'")
	var growth := view.get("growth", {}) as Dictionary
	assert_eq(
		bool(growth.get("bound", false)), true, "the panel resolved its labels from the scene"
	)
	assert_eq(int(growth.get("total", 0)), _body_stat_ids().size(), "every row is declared")
	screen.free()


func test_the_screen_reports_nothing_without_an_actor() -> void:
	var screen := _screen()
	assert_eq(screen.summary(), {}, "{} with no actor, so a test never reads a half-built view")
	screen.free()
