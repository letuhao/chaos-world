extends TestCase

## Proves the localization seam end to end (ADR 0916/0918): the English lives in the
## catalog, a key resolves to it, a mod locale root layers over the base, and the optional
## `source` still acts as a fallback for a caller that holds the English.

const KEY := "LOC_UI_LOADTEST01"


func test_the_catalog_resolves_a_key_to_its_english() -> void:
	# `game/locale/ui_screens.tres` is written by `tools i18n extract`; `L.install()` loads it
	# lazily on this first call. The pilot string must resolve, so a migrated screen reads
	# exactly as before with no English at the call site.
	assert_eq(
		L.t("LOC_UI_SCREENS_1BADD5A415"),
		"Inputs unknown",
		"the owner catalog resolves the key to its English"
	)


func test_a_composed_string_resolves_the_keys_inside_it() -> void:
	# A sentence woven from several fields is not itself a key, so the embedded key must be
	# found inside it — otherwise a content name would reach the player as `LOC_…`.
	assert_eq(
		L.t("LOC_UI_SCREENS_1BADD5A415 x3"),
		"Inputs unknown x3",
		"the embedded key resolves and the surrounding text survives"
	)
	assert_eq(L.t("no keys here"), "no keys here", "plain English is returned untouched")


func test_localize_tree_resolves_a_scene_declared_key() -> void:
	# A `.tscn` literal has no call site, so a screen resolves its subtree. Idempotent: a second
	# pass over resolved text is free.
	var root := Control.new()
	var label := Label.new()
	label.text = "LOC_UI_SCREENS_1BADD5A415"
	root.add_child(label)
	assert_eq(L.localize_tree(root), 1, "the scene key resolves")
	assert_eq(label.text, "Inputs unknown", "to the catalog's English")
	assert_eq(L.localize_tree(root), 0, "and a second pass changes nothing")
	root.remove_child(label)
	label.free()
	root.free()


func test_an_unresolved_key_with_a_source_falls_back_to_it() -> void:
	# The optional `source` covers a caller that holds the English (a derived content key).
	assert_eq(
		L.t("LOC_UI_NEVERSHIPPED", "A default only the source knows"),
		"A default only the source knows",
		"an unresolved key returns the source it was handed"
	)


func test_a_catalog_resolves_the_key_in_another_locale() -> void:
	var previous := TranslationServer.get_locale()
	var french := Translation.new()
	french.locale = "fr"
	french.add_message(KEY, "Bonjour le monde")
	TranslationServer.add_translation(french)
	TranslationServer.set_locale("fr")
	assert_eq(L.t(KEY), "Bonjour le monde", "a resolved key returns the active locale")
	TranslationServer.set_locale(previous)
	assert_eq(L.t(KEY), KEY, "and an unresolved key returns itself for English")


func test_tn_selects_the_singular_and_plural_rows() -> void:
	var table := Translation.new()
	table.locale = "en"
	table.add_message("LOC_TN_ONE", "one thing")
	table.add_message("LOC_TN_ONE_1", "%d things")
	TranslationServer.add_translation(table)
	assert_eq(L.tn("LOC_TN_ONE", 1), "one thing", "count 1 takes the singular row")
	assert_eq(L.tn("LOC_TN_ONE", 3) % 3, "3 things", "and any other count takes form 1")


func test_tn_selects_the_slavic_three_form_rule() -> void:
	var table := Translation.new()
	table.locale = "ru"
	table.add_message("LOC_RU_X", "%d ruble")
	table.add_message("LOC_RU_X_1", "%d rubles-paucal")
	table.add_message("LOC_RU_X_2", "%d rubles-many")
	TranslationServer.add_translation(table)
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	assert_eq(L.tn("LOC_RU_X", 1) % 1, "1 ruble", "one takes form 0")
	assert_eq(L.tn("LOC_RU_X", 3) % 3, "3 rubles-paucal", "three takes form 1")
	assert_eq(L.tn("LOC_RU_X", 5) % 5, "5 rubles-many", "five takes form 2")
	assert_eq(L.tn("LOC_RU_X", 11) % 11, "11 rubles-many", "eleven is the 11-14 exception")
	assert_eq(L.tn("LOC_RU_X", 22) % 22, "22 rubles-paucal", "twenty-two is back to form 1")
	TranslationServer.set_locale(previous)


func test_apply_script_font_covers_a_cjk_locale_and_spares_a_latin_one() -> void:
	var previous_locale := TranslationServer.get_locale()
	var previous_font := ThemeDB.fallback_font
	TranslationServer.set_locale("en")
	assert_eq(L.apply_script_font(), null, "a Latin locale keeps the engine font")
	TranslationServer.set_locale("zh_cn")
	var font := L.apply_script_font()
	assert_eq(font != null, true, "a CJK locale gets a system font")
	assert_eq(ThemeDB.fallback_font, font, "and it is installed as the engine fallback")
	assert_eq(
		(font as SystemFont).font_names.size() > 0,
		true,
		"carrying the candidate families, so no font asset has to ship",
	)
	TranslationServer.set_locale(previous_locale)
	ThemeDB.fallback_font = previous_font


func test_two_adjacent_keys_both_resolve() -> void:
	var table := Translation.new()
	table.locale = "en"
	table.add_message("LOC_ADJ_A", "Wait a season")
	table.add_message("LOC_ADJ_B", " (unavailable)")
	TranslationServer.add_translation(table)
	assert_eq(
		L.t("LOC_ADJ_A" + "LOC_ADJ_B"),
		"Wait a season (unavailable)",
		"a string woven from two ADJACENT keys resolves both, not one glued token",
	)


func test_set_locale_refuses_a_locale_with_no_catalog() -> void:
	var previous := TranslationServer.get_locale()
	assert_eq(L.set_locale("no_such_locale"), false, "an unloaded locale is refused")
	assert_eq(TranslationServer.get_locale(), previous, "and the active locale is untouched")


func test_a_mod_locale_root_layers_over_the_base() -> void:
	# The ninth seam (ADR 0918): `install_roots` loads a mod's catalogs over the base, so a mod
	# ships and overrides strings without touching core. The probe key is shipped by no base
	# catalog, so the override cannot leak into another suite.
	var key := "LOC_TESTPROBE_KEY"
	assert_eq(L.t(key), key, "before the mod root is installed the key is unresolved")
	L.install_roots(["res://tests/ui/fixtures/locale"])
	assert_eq(L.t(key), "Mod override", "the mod catalog resolves the key")
