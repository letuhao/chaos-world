class_name L
extends RefCounted

## Localization entry point (ADR 0290-like: one shared resolver, never a per-module copy).
##
## ## Why a helper and not a bare `tr()`
##
## The repo's UI contract is `summary()`: tests assert the exact wording a panel renders,
## and `Label.text` stores and returns the RAW key, not the resolved string (measured on
## 4.7.2). So every string a player reads is resolved where it is produced, and the source
## language (English) is carried AT THE CALL SITE:
##
##   label.text = L.t("LOC_UI_AB12CD34", "Wait a season")
##
## `L.t` returns the catalog translation when one resolves, and otherwise the call-site
## English — so a test run needs no catalog registered at all, and English is the default
## by construction. The slug is the stable translation key: editing the English never
## orphans a translation, because the key does not move.
##
## ## What is NOT here
##
## `.tscn` literal text and authored content (`.tres` display fields) cannot call a helper;
## they are a later phase and are only inventoried by `tools i18n`. See the ADR.

## Catalogs live beside the project, one text `Translation` resource per domain.
const CATALOG_DIR := "res://locale"

## Installed exactly once per process, so a per-call scan never happens and a second
## `install()` is free. Idempotent by construction: the guard is set before the scan.
static var _installed := false


## The resolved string for `key`, falling back to `source` (the call-site English) when no
## catalog resolves it. `source` empty means "the key IS the text" and it is returned as-is.
static func t(key: String, source: String = "") -> String:
	install()
	var resolved := TranslationServer.translate(key)
	if resolved != key:
		return resolved
	return source if not source.is_empty() else key


## Load every `res://locale/*.tres` `Translation` and register it. The project-settings
## startup load does not run before the resource loaders exist headless, so this is the
## one place translations enter the server. Idempotent, and a missing directory is an
## ordinary "no catalogs yet" rather than a fault.
static func install() -> void:
	if _installed:
		return
	_installed = true
	var dir := DirAccess.open(CATALOG_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	# A directory walk terminates on the empty entry this API returns at the end.
	while entry != "":
		if entry.ends_with(".tres"):
			var resource := ResourceLoader.load("%s/%s" % [CATALOG_DIR, entry])
			if resource is Translation:
				TranslationServer.add_translation(resource)
		entry = dir.get_next()
	dir.list_dir_end()
