extends TestCase

## ADR 0177: a portrait is composable, and `layer_paths` is what makes it so.
##
## ## Why this suite exists at all
##
## `core/portrait_def.gd:37-39` declares `layer_paths` as "the composable layers, back to
## front... which is what lets the same body plan read differently per occasion", and the panel
## **loaded the first layer it could and returned**. A regalia overlay, a faction variant or a
## second expression frame was therefore structurally addressable and visually discarded: the data
## contract promised N layers and exactly one was ever drawn. This suite pins that it now draws
## all of them.
##
## ## What is asserted here and what is not
##
## Pixel identity is NOT asserted — compositing two images and asking whether the result matches a
## hand-built expectation is a test of Godot's `blend_rect`, not of this panel. What is asserted is
## the panel's own decision: which layers it accepts, which it refuses, what it reports, and that a
## single layer still resolves. Those are the parts a future edit can get wrong.

const BASE := "user://portrait_panel_base.png"
const OVERLAY := "user://portrait_panel_overlay.png"
const OVERSIZE := "user://portrait_panel_oversize.png"


func setup() -> void:
	# Every case below asserts at least three times. Declared as a PER-SUITE floor in `setup`, which
	# is where this framework reads it (`framework.gd:135`), so a case that silently asserts nothing
	# — the failure mode that let this suite read "green" while the panel painted nothing — is
	# reported by name instead of passing.
	expect_assertions(3)
	# Cleared before writing, never after: see `teardown`. Idempotent, so a re-run over a dirty
	# `user://` cannot inherit a stale fixture.
	for path in [BASE, OVERLAY, OVERSIZE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# Two same-canvas layers: a fully transparent base and an opaque red one. Order matters —
	# this is what makes "composited" observable: a panel that drew only the FIRST layer would
	# show nothing at all, because the base is empty.
	_write(BASE, Vector2i(64, 80), Color(0, 0, 0, 0))
	_write(OVERLAY, Vector2i(64, 80), Color(255, 0, 0, 255))
	_write(OVERSIZE, Vector2i(32, 40), Color(0, 255, 0, 255))


func teardown() -> void:
	# Deliberately deletes NOTHING. The runner calls `teardown` after EVERY test but `setup` only
	# once per suite (`run_tests.gd:61,92`), so a teardown that removed the fixtures emptied them
	# after the first test and every later case failed against a missing file. `setup` clears them
	# instead, which runs once, at a point where no test is depending on them yet. `user://` is not
	# committed, so a leftover costs nothing.
	pass


# --- compositing ------------------------------------------------------------


func test_two_layers_are_both_drawn_not_just_the_first() -> void:
	# THE REGRESSION. The base layer here is fully transparent, so a panel that drew only the
	# first layer would leave the box empty — and "drawn" would still report true, because the
	# texture is non-null. `composited` is the number that tells the two apart.
	var panel := _panel([BASE, OVERLAY])
	var view: Dictionary = panel.summary()
	assert_eq(int(view["layer_count"]), 2, "both layers were published")
	assert_eq(int(view["composited"]), 2, "both layers were accepted")
	assert_eq(bool(view["drawn"]), true, "something was painted")
	assert_eq((view["mismatched_layers"] as Array).size(), 0, "same canvas, so nothing refused")
	# The PIXEL, not the count. The base is fully transparent and the overlay fully opaque red, so
	# a correct composite is opaque red. A panel that drew only the first layer would leave the
	# texture empty and `drawn` would still be true — which is exactly the bug this pins. And a
	# wrong blend mode (additive, multiply, or a bad argument order) lands on a different value.
	var painted := (panel.get_node("%PortraitTexture") as TextureRect).get_texture()
	var image := painted.get_image()
	assert_eq(image.get_pixel(32, 40).a, 1.0, "the opaque overlay reached the canvas")
	assert_eq(image.get_pixel(32, 40).r, 1.0, "and it is the overlay's red, not a blend artefact")
	_free(panel)


func test_a_single_layer_still_resolves_and_reports_one() -> void:
	# Backward compatibility: every shipped portrait has exactly one layer, and one layer must
	# compose to itself rather than to an empty texture.
	var panel := _panel([BASE])
	var view: Dictionary = panel.summary()
	assert_eq(int(view["composited"]), 1, "the single layer composited")
	assert_eq(int(view["layer_count"]), 1, "and it is the only one")
	_free(panel)


# --- refusal ----------------------------------------------------------------


func test_a_layer_of_the_wrong_size_is_refused_and_named() -> void:
	# `tools/unique_characters.py:_validate_image` already refuses an installed PNG that does not
	# match its shot's declared canvas exactly. Painting one anyway — scaled, or cropped to fit —
	# would hide the same content gap a second time, so the layer is skipped and named.
	var panel := _panel([BASE, OVERSIZE])
	var view: Dictionary = panel.summary()
	assert_eq(int(view["composited"]), 1, "only the matching layer composited")
	var mismatched: Array = view["mismatched_layers"]
	assert_eq(mismatched.size(), 1, "the odd layer is reported")
	assert_eq(String(mismatched[0]), OVERSIZE, "and named by path")
	_free(panel)


func test_a_missing_layer_is_reported_and_does_not_stop_the_others() -> void:
	# A path that will not load is a content gap, never "no face" — resolution is total (ADR 0131).
	# The layers around it must still paint.
	var panel := _panel([BASE, "user://portrait_panel_absent.png", OVERLAY])
	var view: Dictionary = panel.summary()
	var missing: Array = view["missing_layers"]
	assert_eq(missing.size(), 1, "the absent layer is reported")
	assert_eq(int(view["composited"]), 2, "the two loadable layers still composited")
	assert_eq(bool(view["drawn"]), true, "a gap in the middle is not an empty portrait")
	_free(panel)


func test_no_layers_at_all_is_not_drawn_and_says_so() -> void:
	var panel := _panel([])
	var view: Dictionary = panel.summary()
	assert_eq(bool(view["drawn"]), false, "nothing to paint")
	assert_eq(String(view["missing_line"]), "", "and no gap invented for it")
	_free(panel)


# --- internals --------------------------------------------------------------


## A panel wired the way the scene wires it, with the two nodes `_bind_nodes` requires.
## Built in process rather than loaded from a `.tscn` so the suite needs no scene tree.
func _panel(layers: Array) -> PortraitPanel:
	var panel := PortraitPanel.new()
	var container := VBoxContainer.new()
	# EVERY node `_bind_nodes` looks for, not just the two this suite cares about: `_render`
	# writes to `_name_label` first, so a missing one aborts the paint and every case then fails
	# pointing at the panel instead of at the fixture.
	var names := [
		"PortraitNameLabel",
		"PortraitIdLabel",
		"PortraitSourceLabel",
		"LayerLabel",
		"MissingLabel",
	]
	var labels: Array[Label] = []
	for node_name in names:
		var label := Label.new()
		label.name = node_name
		container.add_child(label)
		labels.append(label)
	var texture := TextureRect.new()
	texture.name = "PortraitTexture"
	container.add_child(texture)
	panel.add_child(container)
	# `%Name` resolves through the scene tree's unique-name registry, which only holds a node whose
	# OWNER is set, and `set_unique_name_in_owner` refuses outright without one. So owner is assigned
	# first and the unique name second, which is the order a `.tscn` would already have produced.
	for child in [container, texture] + labels:
		(child as Node).owner = panel
		# The parameter is `force`, not a name. Forced because the node's name is already the unique
		# name we want and the registry is otherwise rebuilt from scene ownership on load.
		(child as Node).set_unique_name_in_owner(true)
	# `%Name` resolves ONLY for nodes inside the SceneTree and owned by a node in it, so a bare panel
	# with children never binds, `_paint` returns before it composites anything, and the suite fails
	# pointing at the panel instead of at the wiring. Adding it to the real root is what makes the
	# lookup the shipped scene performs actually happen here.
	(Engine.get_main_loop() as SceneTree).root.add_child(panel)
	assert_ne(
		panel.get_node_or_null("%PortraitTexture"), null, "the panel never bound its texture node"
	)
	(
		panel
		. show_portrait(
			{
				"portrait_id": "fixture",
				"race_id": "fixture_race",
				"palette_key": "neutral",
				"form": "plain",
				"source": "race",
				"is_placeholder": false,
				"layer_paths": layers,
			}
		)
	)
	return panel


func _free(panel: PortraitPanel) -> void:
	# Detach, then free. `queue_free()` is banned in `res://src` and never runs under
	# `tools test`, which drives every suite from `SceneTree._initialize()`.
	panel.get_parent().remove_child(panel)
	panel.free()


func _write(path: String, size: Vector2i, fill: Color) -> void:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(fill)
	var blob := image.save_png_to_buffer()
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_ne(file, null, "could not open %s for writing" % path)
	file.store_buffer(blob)
	file.close()
	# Asserted rather than assumed: `Image.save_png` returns an Error this suite used to
	# discard, so a fixture that never reached disk showed up much later as "the panel drew
	# nothing" and pointed at the panel instead of at the test.
	assert_eq(FileAccess.file_exists(path), true, "%s was not written" % path)
	assert_eq(Image.load_from_file(path).get_size(), size, "%s is the size it claims" % path)
