extends TestCase

## The elements/mastery screen (ADR 0004, BL-0095): a pure consumer of the `elements`
## facade. The contract is `summary()` — primitives only, child summaries nested under
## their own key — and every verb is driven through the screen's own `act_` doors, which
## is the production path a button press takes.

const SCREEN := "res://src/ui/screens/elements_screen.tscn"


func _screen() -> ElementsScreen:
	return (load(SCREEN) as PackedScene).instantiate() as ElementsScreen


## A body with one spark (fire) and a pack to drink from.
func _hero() -> Actor:
	var actor := ActorFactory.build(
		&"elements_screen_hero", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0}
	)
	actor.set_affinity(ElementStats.FIRE, 10.0)
	ItemsApi.attach(actor, 64)
	return actor


func _row(view: Dictionary, element_id: StringName) -> Dictionary:
	for entry in view.get("elements", []) as Array:
		var row := entry as Dictionary
		if StringName(row.get("id", "")) == element_id:
			return row
	return {}


## Stand the actor at a realm on BOTH climbs the tier door reads (the elemental rank
## and the qi climb), so an advanced tier is legitimately open.
func _stand_at(actor: Actor, realm_id: StringName) -> void:
	actor.set_path(PathState.new(ElementMastery.PATH_ID, realm_id))
	actor.set_path(PathState.new(PathState.QI, realm_id))


## Stock one authored item, asserted to resolve.
func _stock(actor: Actor, item_id: StringName, count: int = 1) -> void:
	var def := Crafting.resolve(item_id)
	assert_ne(def, null, "the authored item resolves: %s" % String(item_id))
	if def == null:
		return
	ItemsApi.inventory(actor).add(def, count)


## No actor, no view; a bare body is not enrolled.
func test_the_screen_reports_no_actor_and_an_unawakened_path() -> void:
	var screen := _screen()
	assert_eq(screen.summary().is_empty(), true, "no actor, no view")
	screen.setup(_hero())
	var view := screen.summary()
	assert_eq(bool(view["enrolled"]), false, "a fresh body has not awakened the path")
	assert_eq(String(view["rank"]), "", "so no rank")
	assert_eq(bool(view["can_act"]), false, "and nothing to advance")
	assert_eq((view["elements"] as Array).size(), 13, "the roster carries every element")
	screen.free()


## Awaken enrolls the path (explicit, never implicit) and the tier doors follow the
## rank-and-realm gate: tier 1 usable at the bottom rung, tier 2 not yet.
func test_awaken_enrolls_and_the_tier_one_elements_open() -> void:
	var screen := _screen()
	screen.setup(_hero())
	screen.act_awaken()
	var view := screen.summary()
	assert_eq(bool(view["enrolled"]), true, "the path is open")
	assert_eq(String(view["rank"]), "qi_refining", "at the bottom rung")
	assert_eq(bool(_row(view, ElementStats.FIRE)["usable"]), true, "tier 1 is the base spark")
	assert_eq(bool(_row(view, ElementStats.LIGHTNING)["usable"]), false, "tier 2 needs the climb")
	screen.free()


## Practise trains the least-trained sparked element, on the FACADE's step rather than a
## number the screen chose.
func test_practise_trains_the_selected_element_on_the_facade_step() -> void:
	var screen := _screen()
	screen.setup(_hero())
	screen.act_awaken()
	screen.act_practise()
	var view := screen.summary()
	assert_eq(String(view["selected"]), "fire", "the only sparked element")
	assert_almost_eq(
		float(_row(view, ElementStats.FIRE)["mastery"]),
		ElementsApi.PRACTICE_STEP,
		"one sitting landed"
	)
	assert_eq(String(view["message"]), "Trained Fire.", "and the message names it")
	screen.free()


## The elixir door: an empty pack names the price, a stocked one pays the tier's gain.
func test_use_elixir_reports_absence_then_infuses() -> void:
	var screen := _screen()
	var actor := _hero()
	screen.setup(actor)
	screen.act_awaken()
	screen.act_use_elixir()
	assert_eq(
		String(screen.summary()["message"]), "Fire elixir absent.", "an empty pack names the price"
	)
	var before := ElementsApi.mastery_of(actor, ElementStats.FIRE)
	var def := Crafting.resolve(ElementStats.mastery_elixir_id(ElementStats.FIRE))
	assert_ne(def, null, "the authored elixir resolves")
	ItemsApi.inventory(actor).add(def, 1)
	screen.act_use_elixir()
	assert_almost_eq(
		ElementsApi.mastery_of(actor, ElementStats.FIRE),
		before + ElementTraining.elixir_gain(ElementStats.FIRE),
		"one drink pays the tier's gain"
	)
	assert_eq(String(screen.summary()["message"]), "Infused Fire.", "and the message names it")
	screen.free()


## The climb: refused while the mastery is short, then paid and risen.
func test_advance_refuses_short_mastery_and_names_the_rise() -> void:
	var screen := _screen()
	var actor := _hero()
	screen.setup(actor)
	screen.act_advance()
	assert_eq(L.t(String(screen.summary()["message"])), "Awaken first.", "the unenrolled refusal")
	screen.act_awaken()
	screen.act_advance()
	var view := screen.summary()
	assert_eq(L.t(String(view["message"])), "Mastery short.", "the climb is paid in mastery")
	assert_eq(bool(view["can_act"]), false, "and nothing is offered")
	# Meet the threshold through the facade's own curve, then press the screen's door.
	var threshold := float(view["threshold"])
	assert_eq(threshold > 0.0, true, "the injected curve published a threshold")
	assert_eq(ElementsApi.practise(actor, ElementStats.FIRE, threshold), true, "the curve is met")
	screen.act_advance()
	view = screen.summary()
	assert_eq(String(view["rank"]), "foundation", "one rung up")
	assert_eq(
		String(view["message"]),
		"Risen to %s." % String(view["stage"]),
		"and the rise is named by the path's own stage vocabulary"
	)
	screen.free()


## The route the shell mounts this screen through, and its key's action — the one
## assertion that keeps a listed screen reachable rather than merely present.
func test_the_route_names_the_screen_and_its_key_is_bound() -> void:
	assert_eq(ScreenRoutes.ids().has(&"elements"), true, "the route is listed")
	var action := StringName(ScreenRoutes.ACTION_PREFIX + ScreenRoutes.key_of(&"elements"))
	assert_eq(String(action), "nav_route_a", "its key is a")
	assert_eq(InputMap.has_action(action), true, "and the action is declared in project.godot")
	assert_eq(ScreenRoutes.route_for_action(action), &"elements", "and resolves back to it")


## The affinity door on the screen (ADR 0924): a held treasure makes its element the
## pick (an unsparked root cannot be practised, so the press that can land wins the
## tie), the Attune press opens it, and the affinity row shows the root growing.
func test_attune_opens_the_unsparked_pick_and_the_affinity_row_grows() -> void:
	var screen := _screen()
	var actor := _hero()
	_stand_at(actor, &"spirit_condensation")
	_stock(actor, ElementAttunement.treasure_id(ElementStats.LIGHTNING))
	screen.setup(actor)
	var view := screen.summary()
	assert_eq(String(view["selected"]), "lightning", "the held treasure picks the element it opens")
	assert_eq(
		bool((view["actions"] as Dictionary)["enabled"]["attune"]),
		true,
		"and the Attune press is offered"
	)
	screen.act_attune()
	view = screen.summary()
	assert_eq(String(view["message"]), "Attuned Lightning.", "the press names the element")
	assert_eq(bool(_row(view, ElementStats.LIGHTNING)["spark"]), true, "the spark is real")
	assert_almost_eq(
		float(_row(view, ElementStats.LIGHTNING)["affinity"]), 3.0, "the root opened", 1e-6
	)
	var affinity_row := view["affinity_row"] as Dictionary
	assert_eq(String(affinity_row.get("name", "")), "Lightning affinity", "the row names the root")
	assert_almost_eq(float(affinity_row.get("current", 0.0)), 3.0, "and shows its value", 1e-6)
	assert_almost_eq(float(affinity_row.get("maximum", 0.0)), 15.0, "against the tier-2 cap", 1e-6)
	screen.free()


## Without a source the Attune press refuses by naming the family that is missing.
func test_attune_without_a_source_names_the_missing_treasure() -> void:
	var screen := _screen()
	screen.setup(_hero())
	screen.act_attune()
	assert_eq(
		String(screen.summary()["message"]),
		"No awakening treasure for Fire.",
		"the refusal names the family that is missing"
	)
	screen.free()


## A locked element is never the pick and never offers the press, treasure or not:
## the climb is the door, and the screen says so by offering nothing.
func test_attune_is_not_offered_for_a_locked_element_even_with_a_treasure() -> void:
	var screen := _screen()
	var actor := _hero()
	_stock(actor, ElementAttunement.treasure_id(ElementStats.LIGHTNING))
	screen.setup(actor)
	var view := screen.summary()
	assert_eq(String(view["selected"]), "fire", "a locked element is never the pick")
	assert_eq(
		bool((view["actions"] as Dictionary)["enabled"]["attune"]),
		false,
		"and no Attune press is offered"
	)
	screen.free()
