extends TestCase

## Dialog generation (ADR 0398): the engine assembles NPC dialogue from base
## text + fate-held modifiers. These assert:
##   - a dialog with no matching fate modifier returns the base text;
##   - a held fate with a matching dialog_modifiers entry overrides the text;
##   - multiple fates modifying the same dialog_id resolve deterministically
##     (last in canonical fate-id order wins);
##   - a null actor returns an empty result;
##   - an unknown dialog_id returns an empty result;
##   - the summary() fold-in carries the dialog array.

const FATE_A := &"t_fate_a"
const FATE_B := &"t_fate_b"
const FATE_C := &"t_fate_c"
const DIALOG_1 := &"t_dialog_1"
const DIALOG_2 := &"t_dialog_2"
const DIALOG_3 := &"t_dialog_3"
const UNKNOWN_DIALOG := &"t_unknown_dialog"


func setup() -> void:
	# Fates with dialog_modifiers: FATE_A and FATE_B both modify DIALOG_1,
	# FATE_C modifies DIALOG_2. FATE_A also modifies DIALOG_3.
	var fate_a := DestinyFixtureCatalog.story_fate(FATE_A)
	fate_a.dialog_modifiers = {DIALOG_1: "A says this.", DIALOG_3: "A's line."}
	var fate_b := DestinyFixtureCatalog.story_fate(FATE_B)
	fate_b.dialog_modifiers = {DIALOG_1: "B says this."}
	var fate_c := DestinyFixtureCatalog.story_fate(FATE_C)
	fate_c.dialog_modifiers = {DIALOG_2: "C's line."}
	DestinyFixtureCatalog.install([fate_a, fate_b, fate_c], [])
	_install_dialogs()


func teardown() -> void:
	DestinyFixtureCatalog.teardown()
	DialogCatalog.shared = null


func _install_dialogs() -> void:
	var catalog := DialogCatalog.new()
	for entry in [
		{&"id": DIALOG_1, &"npc": &"elder", &"text": "Base line one."},
		{&"id": DIALOG_2, &"npc": &"guard", &"text": "Base line two."},
		{&"id": DIALOG_3, &"npc": &"merchant", &"text": "Base line three."},
	]:
		var def := DialogDef.new()
		def.id = entry[&"id"]
		def.npc_id = entry[&"npc"]
		def.base_text = entry[&"text"]
		catalog._dialogs[String(def.id)] = def
	catalog._loaded = true
	DialogCatalog.shared = catalog


func _hero(actor_id: StringName = &"speaker") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	DestinyApi.attach(actor)
	return actor


# --- DialogGenerator.generate ------------------------------------------------


func test_no_held_fate_returns_base_text() -> void:
	var actor := _hero()
	var result := DialogGenerator.generate(DIALOG_1, actor)
	assert_eq(String(result["final_text"]), "Base line one.", "base text when no fate held")
	assert_eq(result["modifiers_applied"] as Array, [], "no modifiers applied")


func test_held_fate_overrides_base_text() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, FATE_A, "test")
	var result := DialogGenerator.generate(DIALOG_1, actor)
	assert_eq(String(result["final_text"]), "A says this.", "fate override applied")
	assert_eq((result["modifiers_applied"] as Array).size(), 1, "one modifier recorded")


func test_multiple_fates_last_in_canonical_order_wins() -> void:
	var actor := _hero()
	# Earn in reverse canonical order to prove the result is order-independent.
	DestinyApi.earn_fate(actor, FATE_B, "test")
	DestinyApi.earn_fate(actor, FATE_A, "test")
	var result := DialogGenerator.generate(DIALOG_1, actor)
	# FATE_A < FATE_B in canonical order, so FATE_B's override wins.
	assert_eq(String(result["final_text"]), "B says this.", "last canonical fate wins")
	assert_eq((result["modifiers_applied"] as Array).size(), 2, "both modifiers recorded")


func test_fate_modifying_different_dialog_does_not_apply() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, FATE_C, "test")
	var result := DialogGenerator.generate(DIALOG_1, actor)
	assert_eq(String(result["final_text"]), "Base line one.", "no override for this dialog")


func test_null_actor_returns_empty_result() -> void:
	var result := DialogGenerator.generate(DIALOG_1, null)
	assert_eq(String(result["final_text"]), "", "null actor gets empty text")
	assert_eq(String(result["dialog_id"]), String(DIALOG_1), "dialog_id is echoed")


func test_unknown_dialog_returns_empty_result() -> void:
	var actor := _hero()
	var result := DialogGenerator.generate(UNKNOWN_DIALOG, actor)
	assert_eq(String(result["final_text"]), "", "unknown dialog gets empty text")
	assert_eq(String(result["npc_id"]), "", "no npc for unknown dialog")


func test_modifiers_applied_carries_fate_id_and_text() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, FATE_A, "test")
	var result := DialogGenerator.generate(DIALOG_3, actor)
	var mods := result["modifiers_applied"] as Array
	assert_eq(mods.size(), 1, "one modifier")
	var entry: Dictionary = mods[0]
	assert_eq(String(entry["fate_id"]), String(FATE_A), "fate id recorded")
	assert_eq(String(entry["override_text"]), "A's line.", "override text recorded")


# --- summary() fold-in -------------------------------------------------------


func test_summary_carries_dialog_array() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, FATE_A, "test")
	var summary := DestinyApi.summary(actor)
	assert_eq(summary.has("dialog"), true, "summary carries dialog key")
	var dialog: Array = summary["dialog"]
	assert_eq(dialog.size(), 3, "one entry per authored dialog")
	var first: Dictionary = dialog[0]
	assert_eq(String(first["dialog_id"]), String(DIALOG_1), "first dialog id")
	assert_eq(String(first["final_text"]), "A says this.", "override applied in summary")


func test_summary_dialog_empty_for_null_actor() -> void:
	var summary := DestinyApi.summary(null)
	assert_eq(summary.has("dialog"), true, "summary carries dialog key for null actor")
	var dialog: Array = summary["dialog"]
	assert_eq(dialog.size(), 3, "all dialogs present even for null actor")
	for entry in dialog:
		assert_eq(String((entry as Dictionary)["final_text"]), "", "no overrides for null actor")
