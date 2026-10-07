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


func test_a_mod_locale_root_layers_over_the_base() -> void:
	# The ninth seam (ADR 0918): `install_roots` loads a mod's catalogs over the base, so a mod
	# ships and overrides strings without touching core. The probe key is shipped by no base
	# catalog, so the override cannot leak into another suite.
	var key := "LOC_TESTPROBE_KEY"
	assert_eq(L.t(key), key, "before the mod root is installed the key is unresolved")
	L.install_roots(["res://tests/ui/fixtures/locale"])
	assert_eq(L.t(key), "Mod override", "the mod catalog resolves it")
