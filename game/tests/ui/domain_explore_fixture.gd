extends TestCase

## Shared fixture for `test_domain_explore.gd`. NOT a suite itself: the runner discovers
## `test_*.gd` only, so this file is never executed on its own.
##
## Split out of the suite purely for size -- gdlint's `max-file-lines` is 1000. Nothing
## was rewritten, no assertion changed and no test renamed: every constant, the two
## pieces of state `teardown` owns and the helper both halves need now live here, which
## the suite `extends`. A test file can only move HELPERS, which is why the moved
## bodies are exactly the ones no `test_` function names.
##
## `teardown` MUST live here rather than in the suite: it frees every screen the helpers
## minted AND restores the process-wide seams a domain run installs (`_born` is why it
## is central -- `_screen` is called from interleaved sites and a test returning early
## would skip a free at its end).

const SCENE := "res://src/ui/screens/domain_explore.tscn"
## The seed the screen's own `Enter` uses, so a test can reproduce what a button press
## generated rather than generating a DIFFERENT run and asserting about the wrong map.
const SCREEN_SEED := 20260904

## Every screen this suite instantiated. The runner shares one process across every
## suite and never processes a frame, so an unfreed screen subtree stays resident for
## the rest of the run. Freed centrally because the call sites are interleaved and a
## test returning early would skip a free at its end.
var _born: Array[Node] = []
## The last test's screen, so `teardown` can prove the FREE actually ran.
var _last_screen: DomainExploreScreen = null

# ── fixtures ─────────────────────────────────────────────────────────────────


## A hero with an inventory, because a treasure pays out through one and the screen's
## fixture verbs answer `no_inventory_bridge` without it.
func _hero() -> Actor:
	var hero := Actor.new(&"delver", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	hero.attach_core_resources()
	ItemsApi.attach(hero, 24)
	return hero


## The screen, with the composition root's real bridge attached — the same object
## `ItemWorkbenchApp` would hand it. `_ready` is driven by hand because the runner
## executes inside `SceneTree._initialize()` and the engine never delivers it.
func _screen(hero: Actor, bridged: bool = true) -> DomainExploreScreen:
	var packed := load(SCENE) as PackedScene
	assert_ne(packed, null, "the domain screen scene loads")
	if packed == null:
		return null
	var screen := packed.instantiate() as DomainExploreScreen
	_born.append(screen)
	_last_screen = screen
	screen.call("_ready")
	screen.call("setup", hero)
	if bridged:
		screen.call("bind_bridge", DomainBoot.bridge())
	return screen


## A screen already standing in a generated domain, through the screen's own `Enter`
## button rather than by calling the facade behind its back — so the fixture is the path
## a player takes, and a broken `Enter` fails every case that uses it.
##
## `Enter` is pressed ONLY when the hero has no run yet. `_generated()` hands back a hero
## that is already inside a domain, and pressing `Enter` there is correctly refused — a
## second domain inside one domain is not a thing the module offers, and the refusal is
## the rule (`_can_enter` requires no active run), not a defect to route around. The
## screen ADOPTS the run already on the hero, which is what `read_active` is for; so the
## helper presses the button on a fresh hero and takes the hero it is given as-is.
func _entered(hero: Actor) -> DomainExploreScreen:
	var screen := _screen(hero)
	if screen == null:
		return null
	if DomainApi.map_summary(hero).is_empty():
		screen.act_enter()
	return screen


## The first authored domain that generated a run, and its hero. Discovered rather than
## declared: the catalogue grows as domains are authored, and domains sort by id, so a
## hard-coded id is a test that fails the next time one is added ahead of it.
##
## `{}` when nothing authored can be entered, which is a content fact and not a failure.
func _generated() -> Dictionary:
	for entry in DomainApi.templates():
		var hero := _hero()
		var entered := DomainApi.generate_and_enter(hero, StringName(entry["template_id"]), 11)
		if bool(entered.get("ok", false)):
			return {"hero": hero, "template_id": String(entry["template_id"])}
	return {}


## The first fixture of `kind` the run holds, as `{room_id, fixture_id}`. `{}` when the
## authored domain has none, so a case that needs one says so rather than indexing blind.
func _fixture_of_kind(hero: Actor, kind: String) -> Dictionary:
	for room in DomainApi.rooms(hero):
		var room_id := StringName(room.get("room_id", ""))
		for entry in room.get("fixtures", []):
			var fixture := entry as Dictionary
			if String(fixture.get("kind", "")) == kind:
				return {
					"room_id": room_id,
					"fixture_id": StringName(fixture.get("fixture_id", "")),
					"row": fixture,
				}
	return {}


## Put the screen's selection on one fixture and repaint, the way picking it from the
## dropdown does. `select_room`/`select_fixture` are the screen's own entry points for a
## row the player chose, so the fixture never has to reach into the screen's fields.
func _select(screen: DomainExploreScreen, room_id: StringName, fixture_id: StringName) -> void:
	screen.select_room(room_id)
	if not fixture_id.is_empty():
		screen.select_fixture(fixture_id)


## Free everything this suite minted. Idempotent, so it is safe after an abort, and
## it restores the process-wide seams a domain run installs so the next suite does not
## inherit a domain program wired to a hero that no longer exists.
func teardown() -> void:
	for node in _born:
		if not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_born.clear()
	_last_screen = null


## Point the screen's template selector at `template_id`, as picking it from the
## dropdown does. `select` on the `OptionButton` is honoured like a click, so the
## screen's own handler sets the index and nothing reaches into its fields.
func _select_template(screen: DomainExploreScreen, template_id: StringName) -> void:
	var option := screen.get_node_or_null("%TemplateOption") as OptionButton
	if option == null:
		return
	for index in option.item_count:
		if String(option.get_item_text(index)).ends_with("(%s)" % String(template_id)):
			option.select(index)
			screen.call("_on_template_selected", index)
			return


## A hero inside a run, standing on a real trap's footprint, with the screen aimed at it.
## `{}` when the authored catalogue holds nothing this suite can drive, which is a
## content fact rather than a failure.
func _trap_standing(hero: Actor, screen: DomainExploreScreen) -> Dictionary:
	var trap := _fixture_of_kind(hero, "trap")
	if trap.is_empty():
		return {}
	var at := _footprint_tile(trap["row"] as Dictionary)
	if at == Vector2i(-1, -1):
		return {}
	DomainApi.visit_room(hero, trap["room_id"])
	_select(screen, trap["room_id"], trap["fixture_id"])
	return {"trap": trap, "at": at}


## A tile provably inside `bounds`. The ORIGIN when the fixture authors no footprint at
## all, and `(-1, -1)` when it authors an empty one — the two are different facts, so the
## sentinel is distinct from a real coordinate rather than being `Vector2i.ZERO`, which
## would silently aim a hero at tile 0,0.
func _footprint_tile(row: Dictionary) -> Vector2i:
	var box: Rect2i = row.get("bounds", Rect2i())
	if box.size.x <= 0 or box.size.y <= 0:
		return Vector2i(-1, -1)
	return box.position


## How many entries on `actor` carry `status_id`.
##
## `StatusEffect` names it `id` and a FIXTURE authors it as `status_id`, so the two
## vocabularies meet here rather than at each call site — the confusion once read
## `effect.status_id` and raised on every status.
func _count_of_status(actor: Actor, status_id: String) -> int:
	var found := 0
	for effect in actor.statuses:
		if String(effect.id) == status_id:
			found += 1
	return found


## The declared parameter count of `method` on `object`, or -1 when it is not there.
## Read from the method list rather than by calling it, so the assertion needs no
## arguments and cannot itself fire a trap.
func _arity_of(object: Object, method: String) -> int:
	for entry in object.get_method_list():
		if String(entry["name"]) != method:
			continue
		var args: Array = entry.get("args", []) as Array
		# `get_method_list` reports the bound call's arg count; a method with only
		# optional parameters still declares them, so the DEFAULTED ones count here.
		return args.size()
	return -1


## The active run's map, read the way `DomainMinimap.render` reads it. A harness-side
## helper rather than a call into the module's internals.
func _active_map(hero: Actor) -> DomainMap:
	var state := hero.get_module_data(DomainApi.MODULE_KEY)
	if not state is Dictionary or not (state as Dictionary).has("map"):
		return null
	return DomainMap.from_dict((state as Dictionary)["map"])


## Dotted paths inside a summary whose value is not a primitive, a String, an Array, or a
## dictionary of the same. A `Node`, a `Resource`, a `Vector2i` or a `Rect2i` in a
## testable surface is how a readout quietly stops being testable.
func _non_primitives(value: Variant, path: String = "") -> Array[String]:
	var out: Array[String] = []
	if value is Dictionary:
		for key in value as Dictionary:
			var child: Variant = (value as Dictionary)[key]
			if child is Dictionary or _is_primitive(child):
				out.append_array(_non_primitives(child, "%s.%s" % [path, key]))
			else:
				out.append("%s.%s" % [path, key])
	elif value is Array:
		for index in (value as Array).size():
			out.append_array(_non_primitives((value as Array)[index], "%s[%d]" % [path, index]))
	return out


func _is_primitive(value: Variant) -> bool:
	if value == null:
		return true
	var kind := typeof(value)
	return (
		kind == TYPE_BOOL
		or kind == TYPE_INT
		or kind == TYPE_FLOAT
		or kind == TYPE_STRING
		or kind == TYPE_STRING_NAME
		or kind == TYPE_ARRAY
	)
