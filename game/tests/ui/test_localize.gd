extends TestCase

## Proves the localization seam end to end (ADR 0295): the source English is the default,
## and a registered catalog resolves the same key to another locale with no source change.

const KEY := "LOC_UI_LOADTEST01"


func test_an_unresolved_key_falls_back_to_the_call_site_english() -> void:
	# The property the whole strategy rests on: a key no catalog knows returns the English
	# the call site already carries, never the slug. That is why English needs no catalog.
	assert_eq(
		L.t("LOC_UI_NEVERSHIPPED", "A default only the source knows"),
		"A default only the source knows",
		"an unresolved key falls back to the call-site English, never to the slug"
	)


func test_a_catalog_resolves_the_key_in_another_locale() -> void:
	var previous := TranslationServer.get_locale()
	var french := Translation.new()
	french.locale = "fr"
	french.add_message(KEY, "Bonjour le monde")
	TranslationServer.add_translation(french)
	TranslationServer.set_locale("fr")
	assert_eq(L.t(KEY, "Hello world"), "Bonjour le monde", "a resolved key returns the locale")
	TranslationServer.set_locale(previous)
	assert_eq(L.t(KEY, "Hello world"), "Hello world", "and the fallback returns for English")


func test_the_shipped_catalog_resolves_to_the_english_it_was_extracted_from() -> void:
	# `game/locale/ui.tres` is written by `tools i18n extract`; `L.install()` registers it.
	# The pilot string must resolve to itself, so a migrated panel reads exactly as before.
	assert_eq(
		L.t("LOC_UI_1BADD5A415", "Inputs unknown"),
		"Inputs unknown",
		"the shipped en catalog resolves a key to the text it was extracted from"
	)
